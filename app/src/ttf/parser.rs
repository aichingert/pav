// https://docs.fileformat.com/font/ttf/

#[derive(Debug)]
struct FontDirectory {
    off_sub: OffsetSubtable,
    tbl_dirs: Vec<TableDirectory>,

    glyf: usize,
    loca: usize,
    head: usize,
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
        let cap = off_sub.num_tables as usize;

        let mut ft = Self {
            off_sub,
            tbl_dirs: Vec::with_capacity(cap),
            glyf: 0,
            loca: 0,
            head: 0,
        };

        let ptr = TableDirectory::read(&mut ft, buf, ptr);

        (ft, ptr)
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
    fn read(ft: &mut FontDirectory, buf: &[u8], ptr: usize) -> usize {
        let tables = ft.off_sub.num_tables as usize;

        for off in 0..tables {
            let pos = ptr + off * 16;

            ft.tbl_dirs.push(Self {
                tag:        u32_from_be_bytes(&buf[pos + 0..pos + 4]),
                check_sum:  u32_from_be_bytes(&buf[pos + 4..pos + 8]),
                offset:     u32_from_be_bytes(&buf[pos + 8..pos + 12]),
                length:     u32_from_be_bytes(&buf[pos + 12..pos + 16]),
            });

            let tbl_dir = ft.tbl_dirs.last().unwrap();

            match tbl_dir.tag {
                1735162214 => ft.glyf = ptr + tbl_dir.offset as usize,
                1819239265 => ft.loca = ptr + tbl_dir.offset as usize,
                1751474532 => ft.head = ptr + tbl_dir.offset as usize,
                1668112752 => {
                    let (cmap, _) = CMap::read(buf, tbl_dir.offset as usize);
                    let ptr = tbl_dir.offset as usize + cmap.subtables[0].offset as usize;
                    let fmt4 = Format4::read(buf, ptr);
                    println!("{fmt4:?}");
                }
                _ => (),
            }
        }

        ptr + tables * 16
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
        let cap = u16_from_be_bytes(&buf[ptr + 6..ptr + 8]) as usize / 2;

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

        let e_ptr = ptr + 14;
        let s_ptr = e_ptr + fmt4.seg_count_x2 as usize * 1 + 2;
        let d_ptr = e_ptr + fmt4.seg_count_x2 as usize * 2 + 2;
        let r_ptr = e_ptr + fmt4.seg_count_x2 as usize * 3 + 2;

        for i in 0..cap {
            fmt4.end_code.push(u16_from_be_bytes(&buf[e_ptr + i*2..e_ptr + i*2 + 2]));
            fmt4.start_code.push(u16_from_be_bytes(&buf[s_ptr + i*2..s_ptr + i*2 + 2]));
            fmt4.id_delta.push(u16_from_be_bytes(&buf[d_ptr + i*2..d_ptr + i*2 + 2]));
            fmt4.id_range_offset.push(u16_from_be_bytes(&buf[r_ptr + i*2..r_ptr + i*2 + 2]));
        }

        let glyph_ptr = ptr + cap * 8 + 2;
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
                let mut pos = ptr as i32 + self.id_range_offset[ptr] as i32 / 2;
                pos += code_point as i32 - self.start_code[ptr] as i32;

                println!("{pos:?}");

                return 0;
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

    println!("{}", u16_from_be_bytes(&file[fd.head + 50..fd.head + 52]));

}

fn u32_from_be_bytes(buf: &[u8]) -> u32 {
    u32::from_be_bytes(buf.try_into().unwrap())
}

fn u16_from_be_bytes(buf: &[u8]) -> u16 {
    u16::from_be_bytes(buf.try_into().unwrap())
}
