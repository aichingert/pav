// NOTE: zig port of puff.c from zlib

const std = @import("std");

const MAXBITS: i32 = 15;          
const MAXLCODES: i32 = 286;          
const MAXDCODES: i32 = 30;
const MAXCODES: i32 = (MAXLCODES+MAXDCODES);
const FIXLCODES: i32 = 288;

pub const DeflateError = error {
    InvalidSeq,
    OutOfCodes,
    OutOfInput,
    OutOfOutput,
};

const Huffman = struct {
    count: []u16,
    symbol: []u16,
};

pub const DeflateState = struct {
    out: []u8,
    outlen: usize,
    outcnt: usize,

    in: []u8,
    inlen: usize,
    incnt: usize,

    bitbuf: i32,
    bitcnt: i32,

    pub fn puff(self: *DeflateState) !void { 
        var last: i32 = 1;
        var ctype: i32 = 0;

        while (last != 0) {
            last = try self.bits(1);
            ctype = try self.bits(2);

            if (ctype == 0) {
                try self.stored();
            } else if (ctype == 1) {
               _ = try self.fixed();
            } else if (ctype == 2) {
                try self.dynamic();
            } else {
                std.debug.print("here\n", .{});
                return DeflateError.InvalidSeq;
            }
        }
    }

    fn bits(self: *DeflateState, need: i32) !i32 {
        var val: i32 = self.bitbuf;

        while (self.bitcnt < need) {
            if (self.incnt == self.inlen) {
                return DeflateError.OutOfInput;
            }

            val |= @as(i32, self.in[self.incnt]) << @intCast(self.bitcnt);
            self.incnt += 1;
            self.bitcnt += 8;
        }

        self.bitbuf = val >> @intCast(need);
        self.bitcnt -= need;

        return val & ((@as(i32, 1) << @intCast(need)) - 1);
    }
    
    fn stored(self: *DeflateState) !void {
        var len: u32 = 0;

        self.bitbuf = 0;
        self.bitcnt = 0;

        if (self.incnt + 4 > self.inlen) {
            return DeflateError.OutOfInput;
        }

        len = @as(u32, self.in[self.incnt]);
        len |= @as(u32, self.in[self.incnt + 1]) << 8;
        if (self.in[self.incnt + 2] != (~len & 0xFF) or
            self.in[self.incnt + 3] != (((~len) >> 8) & 0xFF)) {
            std.debug.print("here\n", .{});
            return DeflateError.InvalidSeq;
        }

        self.incnt += 4;
        if (self.incnt + len > self.inlen) {
            return DeflateError.OutOfInput;
        }
        if (self.outcnt + len > self.outlen) {
            return DeflateError.OutOfOutput;
        }

        while (len > 0) {
            self.out[self.outcnt] = self.in[self.incnt];

            len -= 1;
            self.incnt += 1;
            self.outcnt += 1;
        }
    }

    fn decode(self: *DeflateState, h: *Huffman) !i32 {
        var code: i32 = 0;
        var first: i32 = 0;
        var index: i32 = 0;

        var len: i32 = 1;

        while (len <= MAXBITS) : (len += 1) {
            code |= try self.bits(1);
            const count = h.count[@intCast(len)];
            if (code - count < first) {
                return h.symbol[@intCast(index + (code - first))];
            }

            index += count;
            first += count;
            code = code << 1;
            first = first << 1;
        }

        return DeflateError.OutOfInput;
    }

    fn codes(self: *DeflateState, lencode: *Huffman, distcode: *Huffman) !void {
        var symbol: i32 = 0;
        var len: i32 = 0;
        var dist: u32 = 0;

        const lens = [29]u16{ 
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
        const lext = [29]u16{ 
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
        const dists = [30]u16{ 
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
            257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
            8193, 12289, 16385, 24577};
        const dext = [30]u16{ 
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
            7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
            12, 12, 13, 13};

        while (symbol != 256) {
            symbol = try self.decode(lencode);

            if (symbol < 256) {
                if (self.outcnt == self.outlen) {
                    return DeflateError.OutOfOutput;
                }
                self.out[@intCast(self.outcnt)] = @intCast(symbol);
                self.outcnt += 1;
            } else if (symbol > 256) {
                symbol -= 257;
                if (symbol >= 29) {
                    std.debug.print("here\n", .{});
                    return DeflateError.InvalidSeq;
                }

                len = lens[@intCast(symbol)] + try self.bits(lext[@intCast(symbol)]);

                symbol = try self.decode(distcode);
                dist = @intCast(dists[@intCast(symbol)] + try self.bits(dext[@intCast(symbol)]));

                if (self.outcnt + @as(usize, @intCast(len)) > self.outlen) {
                    return DeflateError.OutOfOutput;
                }

                while (len > 0) {
                    self.out[self.outcnt] = self.out[self.outcnt - dist];
                    self.outcnt += 1;
                    len -= 1;
                }
            }
        }
    }

    fn fixed(self: *DeflateState) !void {
        const Static = struct {
            var virgin: i32 = 1;
            var lencnt = [_]u16{0} ** (MAXBITS + 1);
            var lensym = [_]u16{0} ** FIXLCODES;
            var distcnt = [_]u16{0} ** (MAXBITS + 1);
            var distsym = [_]u16{0} ** MAXDCODES;
            var lencode: Huffman = undefined;
            var distcode: Huffman = undefined;
        };

        if (Static.virgin == 1) {
            var symbol: i32 = 0;
            var lengths = [_]u16{0} ** FIXLCODES;
            Static.lencode.count = &Static.lencnt;
            Static.lencode.symbol = &Static.lensym;
            Static.distcode.count = &Static.distcnt;
            Static.distcode.symbol = &Static.distsym;

            symbol = 0;
            while (symbol < 144) : (symbol += 1) {
                lengths[@intCast(symbol)] = 8;
            }
            while (symbol < 256) : (symbol += 1) {
                lengths[@intCast(symbol)] = 9;
            }
            while (symbol < 280) : (symbol += 1) {
                lengths[@intCast(symbol)] = 7;
            }
            while (symbol < FIXLCODES) : (symbol += 1) {
                lengths[@intCast(symbol)] = 8;
            }
            _ = construct(&Static.lencode, &lengths, FIXLCODES);

            symbol = 0;
            while (symbol < MAXDCODES) : (symbol += 1) {
                lengths[@intCast(symbol)] = 5;
            }
            _ = construct(&Static.distcode, &lengths, MAXDCODES);

            Static.virgin = 0;
        }

        try self.codes(&Static.lencode, &Static.distcode);
    }

    fn dynamic(self: *DeflateState) !void {
        var nlen: i32 = 0;
        var ndist: i32 = 0;
        var ncode: i32 = 0;

        var lengths: [MAXCODES]u16 = undefined;
        var lencnt: [MAXBITS + 1]u16 = undefined;
        var lensym: [MAXLCODES]u16 = undefined;
        var distcnt: [MAXBITS + 1]u16 = undefined;
        var distsym: [MAXLCODES]u16 = undefined;

        var lencode: Huffman = undefined;
        var distcode: Huffman = undefined;

        const order: [19]u16 =  [_]u16{
            16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
        };

        lencode.count = &lencnt;
        lencode.symbol = &lensym;
        distcode.count = &distcnt;
        distcode.symbol = &distsym;

        nlen = try self.bits(5) + 257;
        ndist = try self.bits(5) + 1;
        ncode = try self.bits(4) + 4;

        if (nlen > MAXLCODES or ndist > MAXDCODES) {
            std.debug.print("here\n", .{});
            return DeflateError.InvalidSeq;
        }

        var index: i32 = 0;
        while (index < ncode) : (index += 1) {
            lengths[@intCast(order[@intCast(index)])] = @intCast(try self.bits(3));
        }
        while (index < 19) : (index += 1) {
            lengths[@intCast(order[@intCast(index)])] = 0;
        }

        var err = construct(&lencode, &lengths, 19);
        if (err != 0) {
            std.debug.print("this here\n", .{});
            return DeflateError.InvalidSeq;
        }

        index = 0;
        while (index < nlen + ndist) {
            var symbol: i32 = try self.decode(&lencode);
            var len: i32 = 0;

            if (symbol < 0) {
                return DeflateError.InvalidSeq;
            }
            if (symbol < 16) {
                lengths[@intCast(index)] = @intCast(symbol);
                index += 1;
                continue;
            }

            if (symbol == 16) {
                if (index == 0) {
                    return DeflateError.InvalidSeq;
                }

                len = lengths[@intCast(index - 1)];
                symbol = 3 + try self.bits(2);
            } else if (symbol == 17) {
                symbol = 3 + try self.bits(3);
            } else {
                symbol = 11 + try self.bits(7);
            }

            if (index + symbol > nlen + ndist) {
                return DeflateError.InvalidSeq;
            }

            while (symbol > 0) : (symbol -= 1) {
                lengths[@intCast(index)] = @intCast(len);
                index += 1;
            }
        }

        if (lengths[256] == 0) {
            return DeflateError.InvalidSeq;
        }

        err = construct(&lencode, &lengths, nlen);
        if (err != 0 and (err < 0 or nlen != lencode.count[0] + lencode.count[1])) {
            return DeflateError.InvalidSeq;
        }

        err = construct(&distcode, lengths[@intCast(nlen)..lengths.len], ndist);
        if (err != 0 and (err < 0 or ndist != distcode.count[0] + distcode.count[1])) {
            return DeflateError.InvalidSeq;
        }

        try self.codes(&lencode, &distcode);
    }
};

// TODO: implement fast solution
//local int decode(struct state *s, const struct huffman *h)
//{
//    int len;            /* current number of bits in code */
//    int code;           /* len bits being decoded */
//    int first;          /* first code of length len */
//    int count;          /* number of codes of length len */
//    int index;          /* index of first code of length len in symbol table */
//    int bitbuf;         /* bits from stream */
//    int left;           /* bits left in next or left to process */
//    short *next;        /* next number of codes */
//
//    bitbuf = s->bitbuf;
//    left = s->bitcnt;
//    code = first = index = 0;
//    len = 1;
//    next = h->count + 1;
//    while (1) {
//        while (left--) {
//            code |= bitbuf & 1;
//            bitbuf >>= 1;
//            count = *next++;
//            if (code - count < first) { /* if length len, return symbol */
//                s->bitbuf = bitbuf;
//                s->bitcnt = (s->bitcnt - len) & 7;
//                return h->symbol[index + (code - first)];
//            }
//            index += count;             /* else update for next length */
//            first += count;
//            first <<= 1;
//            code <<= 1;
//            len++;
//        }
//        left = (MAXBITS+1) - len;
//        if (left == 0)
//            break;
//        if (s->incnt == s->inlen)
//            longjmp(s->env, 1);         /* out of input */
//        bitbuf = s->in[s->incnt++];
//        if (left > 8)
//            left = 8;
//    }
//    return -10;                         /* ran out of codes */
//}

pub fn construct(h: *Huffman, length: []u16, n: i32) i32 {
    var symbol: i32 = 0;
    var len: i32 = 0;
    var left: i32 = 0;
    var offs: [MAXBITS + 1]u16 = undefined;

    while (len <= MAXBITS) : (len += 1) {
        h.count[@intCast(len)] = 0;
    }
    while (symbol < n) : (symbol += 1) {
        h.count[@intCast(length[@intCast(symbol)])] += 1;
    }

    if (h.count[0] == n) {
        return 0;
    }

    left = 1;
    len = 1;

    while (len <= MAXBITS) : (len += 1) {
        left = left << 1;
        left -= h.count[@intCast(len)];
        if (left < 0) {
            std.debug.print("{any}\n", .{left});
            return left;
        }
    }

    offs[1] = 0;
    len = 1;
    while (len < MAXBITS) : (len += 1) {
        offs[@intCast(len + 1)] = offs[@intCast(len)] + h.count[@intCast(len)];
    }

    symbol = 0;
    while (symbol < n) : (symbol += 1) {
        if (length[@intCast(symbol)] != 0) {
            h.symbol[@intCast(offs[@intCast(length[@intCast(symbol)])])] = @intCast(symbol);
            offs[@intCast(length[@intCast(symbol)])] += 1;
        }
    }

    std.debug.print("{any}\n", .{left});
    return left;
}

