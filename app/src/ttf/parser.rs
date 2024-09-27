#[derive(Debug)]
struct FontDirectory {
    off_sub: OffsetSubtable,
    tbl_dirs: Vec<TableDirectory>,
}

#[derive(Debug)]
struct OffsetSubtable {
    scaler_type: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
}

#[derive(Debug)]
struct TableDirectory {
    tag: u32,
    check_sum: u32,
    offset: u32,
    length: u32,
}

#[derive(Debug)]
struct CMap {
    version: u16,
    subtables_number: u16,
    subtables: Vec<CMapEncodingSubtable>,
}

#[derive(Debug)]
struct CMapEncodingSubtable {
    platform_id: u16,
    platform_specific_id: u16,
    offset: u32,
}

#[derive(Debug)]
struct Format4 {
    format: u16,
    length: u16,
    language: u16,
    seg_count_x2: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
    reserve_pad: u16,
    end_code: Vec<u16>,
    start_code: Vec<u16>,
    id_delta: Vec<u16>,
    id_range_offset: Vec<u16>,
    glyph_id_array: Vec<u16>,
}

impl FontDirectory {
    fn read(buf: &[u8]) -> (Self, usize) {
        let (off_sub, ptr) = OffsetSubtable::read(buf, 0);
        let (tbl_dirs, ptr) = TableDirectory::read(buf, ptr, off_sub.num_tables);

        (Self { off_sub, tbl_dirs }, ptr)
    }
}

impl OffsetSubtable {
    fn read(buf: &[u8], ptr: usize) -> (Self, usize) {
        (
            Self {
                scaler_type:    u32_from_be_bytes(&buf[ptr + 0..ptr + 4]),
                num_tables:     u16_from_be_bytes(&buf[ptr + 4..ptr + 6]),
                search_range:   u16_from_be_bytes(&buf[ptr + 6..ptr + 8]),
                entry_selector: u16_from_be_bytes(&buf[ptr + 8..ptr + 10]),
                range_shift:    u16_from_be_bytes(&buf[ptr + 10..ptr + 12]),
            }, 
            ptr + 12,
        )
    }
}

impl TableDirectory {
    fn read(buf: &[u8], ptr: usize, tables: u16) -> (Vec<Self>, usize) {
        let tables = tables as usize;
        let mut tbl_dirs = Vec::with_capacity(tables);

        for off in 0..tables {
            let pos = ptr + off * 16;

            tbl_dirs.push(Self {
                tag:        u32_from_be_bytes(&buf[pos + 0..pos + 4]),
                check_sum:  u32_from_be_bytes(&buf[pos + 4..pos + 8]),
                offset:     u32_from_be_bytes(&buf[pos + 8..pos + 12]),
                length:     u32_from_be_bytes(&buf[pos + 12..pos + 16]),
            });
        }

        (tbl_dirs, ptr + tables * 16)
    }
}

impl CMap {
    fn read(buf: &[u8], ptr: usize) -> (Self, usize) {
        let version = u16_from_be_bytes(&buf[ptr + 0..ptr + 2]);
        let subtables_number = u16_from_be_bytes(&buf[ptr + 2..ptr + 4]);
        println!("n: {subtables_number}");
        let mut subtables = Vec::with_capacity(subtables_number as usize);

        for i in 0..subtables_number as usize {
            let pos = ptr + 4 + i * 8;

            subtables.push(CMapEncodingSubtable {
                platform_id:            u16_from_be_bytes(&buf[pos + 0..pos + 2]),
                platform_specific_id:   u16_from_be_bytes(&buf[pos + 2..pos + 4]),
                offset:                 u32_from_be_bytes(&buf[pos + 4..pos + 8]),
            });
        }

        (
            Self {
                version,
                subtables_number,
                subtables,
            },
            ptr + 4 + subtables_number as usize * 8,
        )
    }
}

impl Format4 {
    fn read(buf: &[u8], ptr: usize) -> (Self, usize) {
        let cap = u16_from_be_bytes(&buf[ptr + 6..ptr + 8]) as usize;

        let mut fmt4 = Self {
            format:         u16_from_be_bytes(&buf[ptr + 0..ptr + 2]),
            length:         u16_from_be_bytes(&buf[ptr + 2..ptr + 4]),
            language:       u16_from_be_bytes(&buf[ptr + 4..ptr + 6]),
            seg_count_x2:   u16_from_be_bytes(&buf[ptr + 6..ptr + 8]),
            search_range:   u16_from_be_bytes(&buf[ptr + 8..ptr +10]),
            entry_selector: u16_from_be_bytes(&buf[ptr +10..ptr +12]),
            range_shift:    u16_from_be_bytes(&buf[ptr +12..ptr +14]),
            reserve_pad: 0,

            end_code: Vec::with_capacity(cap),
            start_code: Vec::with_capacity(cap),
            id_delta: Vec::with_capacity(cap),
            id_range_offset: Vec::with_capacity(cap),
            glyph_id_array: Vec::with_capacity(cap),
        };

        let end_code_ptr = ptr + 14;
        let start_code_ptr = ptr + 14 + fmt4.seg_count_x2 as usize + 2;
        let id_delta_ptr = ptr + 14 + fmt4.seg_count_x2 as usize * 2 + 2;
        let id_range_ptr = ptr + 14 + fmt4.seg_count_x2 as usize * 3 + 2;

        let size = fmt4.seg_count_x2 as usize / 2;

        assert_eq!(size, cap);

        for i in 0..size {
            fmt4.end_code.push(u16_from_be_bytes(&buf[end_code_ptr + i * 2..end_code_ptr + i * 2 + 2]));
            fmt4.start_code.push(u16_from_be_bytes(&buf[start_code_ptr + i * 2..start_code_ptr + i * 2 + 2]));
            fmt4.id_delta.push(u16_from_be_bytes(&buf[id_delta_ptr + i * 2..id_delta_ptr + i * 2]));
            fmt4.id_range_offset.push(u16_from_be_bytes(&buf[id_range_ptr + i * 2..id_range_ptr + i * 2]));
        }

        let glyph_ptr = size * 8 + 2;
        let remaining = fmt4.length as usize - (glyph_ptr - ptr);

        for i in 0..remaining / 2 {
            fmt4.glyph_id_array.push(
                u16_from_be_bytes(&buf[glyph_ptr + i * 2..glyph_ptr + i * 2 + 2])
            );
        }

        (fmt4, glyph_ptr + remaining)
    }

    // TODO
    fn get_glyph_index(&self, code_point: u16) -> u16 {
        let mut index = None::<usize>;

        for (i, &end_code) in self.end_code.iter().enumerate() {
            if end_code > code_point {
                index = Some(i);
                break;
            }
        }

        let Some(ptr) = index else { return 0; };

        if self.start_code[ptr] < code_point {
            if self.id_range_offset[ptr] != 0 {
                //let mut ptr = index as i32 + self.id_range_offset[index] as i32 / 2;
                //ptr += code_point as i32 - self.start_code[index];
                //println!("{ptr}");

            } else {
                return self.id_delta[ptr] + code_point;
            }
        }

        0
    }
}

pub fn parse(filename: &str) {
    let file = std::fs::read("../tmp/envy/envy_code.ttf").unwrap();

    let (fd, mut ptr) = FontDirectory::read(&file);
    println!("{}", fd.tbl_dirs.len());

    for tbl_dir in &fd.tbl_dirs {
        if tbl_dir.tag == u32_from_be_bytes(b"cmap") {
            let offset = tbl_dir.offset as usize + ptr;

            let (cmap, nxt) = CMap::read(&file, offset);

            for enc in &cmap.subtables {
                println!("{enc:?}");
            }

            ptr = nxt;
        }
    }
}

fn u32_from_be_bytes(buf: &[u8]) -> u32 {
    u32::from_be_bytes(buf.try_into().unwrap())
}

fn u16_from_be_bytes(buf: &[u8]) -> u16 {
    u16::from_be_bytes(buf.try_into().unwrap())
}
