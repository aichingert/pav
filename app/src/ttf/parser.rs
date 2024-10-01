// https://learn.microsoft.com/en-us/typography/opentype/spec/
// https://stevehanov.ca/blog/?id=143

pub struct Parser {
    ptr: usize,
    buf: Vec<u8>,
}

impl Parser {
    pub fn new(filename: &str) -> Self {
        let mut parser = Self {
            ptr: 0,
            buf: std::fs::read(filename).unwrap(),
        };

        parser.read_offset_tables();

        parser
    }

    fn read_offset_tables(&mut self) {
        let _scalar_type = self.u32();
        let num_tables = self.u16();
        let _search_range = self.u16();
        let _entry_selector = self.u16();
        let _range_shift = self.u16();

        let mut glyph_offset = 0;

        for _ in 0..num_tables {
            let tag = self.bytes_to_str(4);
            let _checksum = self.u32();
            let offset = self.u32();
            let _lenght = self.u32();

            if &tag == "glyf" {
                glyph_offset = offset;
            }

            if &tag == "head" {
                self.read_head_table(offset as usize);
            } else if &tag == "loca" {
                self.read_glyph_offset(offset, glyph_offset);
            }
        }
    }

    fn read_head_table(&mut self, head_offset: usize) {
        let ptr = self.ptr;
        self.ptr = head_offset;
        let version = self.u32() / (1u32 << 16);
        let font_revision = self.u32() / (1u32 << 16);
        let _checksum = self.u32();
        let magic_number = self.u32();
        assert!(magic_number == 0x5f0f3cf5);
        let flags = self.u16();
        let units_per_em = self.u16();
        let _created = self.u32();
        let _modified = self.u32();
        let x_min = self.u16(); // should be i16
        let y_min = self.u16(); // should be i16
        let x_max = self.u16(); // should be i16
        let y_max = self.u16(); // should be i16
        let mac_style = self.u16();
        let lowest_rec_ppem = self.u16();
        let font_direction_hint = self.u16();
        let index_to_loc_format = self.u16();
        let glyph_data_format = self.u16() // i16

        println!("{version:?}");
    }

    fn get_glyph_offset(&mut self, loca_offset: usize, glyph_offset: usize) {
    }

    #[inline(always)]
    fn u16(&mut self) -> u16 {
        self.ptr += 2;
        u16::from_be_bytes(self.buf[self.ptr - 2..self.ptr].try_into().unwrap())
    }

    #[inline(always)]
    fn ru16(&self, ptr: usize) -> u16 {
        u16::from_be_bytes(self.buf[ptr..ptr + 2].try_into().unwrap())
    }

    #[inline(always)]
    fn u32(&mut self) -> u32 {
        self.ptr += 4;
        u32::from_be_bytes(self.buf[self.ptr - 4..self.ptr].try_into().unwrap())
    }

    #[inline(always)]
    fn ru32(&self, ptr: usize) -> u32 {
        u32::from_be_bytes(self.buf[ptr..ptr + 4].try_into().unwrap())
    }

    fn bytes_to_str(&mut self, len: usize) -> String {
        self.ptr += len;
        self.buf[self.ptr - len..self.ptr].iter().map(|&b| b as char).collect()
    }
}
