
#[derive(Debug)]
pub struct FontDirectory {
    pub off_sub: OffsetSubtable,
    tbl_dir: Vec<TableDirectory>,
}

#[derive(Debug)]
pub struct OffsetSubtable {
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

impl FontDirectory {
    pub fn read_section(buf: &[u8]) -> Self {
        let (off_sub, ptr) = OffsetSubtable::read_section(buf, 0);
        let tbl_dir = TableDirectory::read_section(buf, ptr, off_sub.num_tables);

        Self { off_sub, tbl_dir }
    }
}

impl OffsetSubtable {
    fn read_section(buf: &[u8], ptr: usize) -> (Self, usize) {
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
    fn read_section(buf: &[u8], ptr: usize, tables: u16) -> Vec<Self> {
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

        tbl_dirs
    }
}

fn u32_from_be_bytes(buf: &[u8]) -> u32 {
    u32::from_be_bytes(buf.try_into().unwrap())
}

fn u16_from_be_bytes(buf: &[u8]) -> u16 {
    u16::from_be_bytes(buf.try_into().unwrap())
}
