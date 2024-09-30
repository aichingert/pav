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
        let scalar_type = self.u32();
        let num_tables = self.u16();
        let search_range = self.u16();
        let entry_selector = self.u16();
        let range_shift = self.u16();

        for _ in 0..num_tables {
            let tag = self.bytes_to_str(4);
            let checksum = self.u32();
            let offset = self.u32();
            let lenght = self.u32();

            println!("{:?} {:?}", tag, b"head");
        }
    }

    #[inline(always)]
    fn u16(&mut self) -> u16 {
        self.ptr += 2;
        u16::from_be_bytes(self.buf[self.ptr - 2..self.ptr].try_into().unwrap())
    }

    #[inline(always)]
    fn u32(&mut self) -> u32 {
        self.ptr += 4;
        u32::from_be_bytes(self.buf[self.ptr - 4..self.ptr].try_into().unwrap())
    }

    fn bytes_to_str(&mut self, len: usize) -> String {
        self.ptr += len;
        self.buf[self.ptr - len..self.ptr].iter().map(|&b| b as char).collect()
    }
}
