// NOTE: zig port of puff.c from zlib

const std = @import("std");

const MAXBITS: i32 = 15;          
const MAXLCODES: i32 = 286;          
const MAXDCODES: i32 = 30;
const MAXCODES: i32 = (MAXLCODES+MAXDCODES);
const FIXLCODES: i32 = 288;

const DeflateError = error {
    InvalidSeq,
    OutOfCodes,
    OutOfInput,
    OutOfOutput,
};

const Huffman = struct {
    count: []u16,
    symbol: []u16,
};

const DeflateState = struct {
    out: []u8,
    out_len: usize,
    out_cnt: usize,

    in: []u8,
    in_len: usize,
    in_cnt: usize,

    bitbuf: i32,
    bitcnt: i32,

    fn bits(self: *DeflateState, need: i32) !i32 {
        var val: i32 = self.bitbuf;

        while (self.bitcnt < need) {
            if (self.in_cnt == self.in_len) {
                return DeflateError.OutOfInput;
            }

            val |= @as(i32, self.in[self.incnt]) << self.bitcnt;
            self.incnt += 1;
            self.bitcnt += 8;
        }

        self.bitbuf = val >> need;
        self.bitcnt -= need;

        return val & ((@as(i32, 1) << need) - 1);
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
        if (self.in[self.incnt + 2] != (~len & 0xFF) ||
            self.in[self.incnt + 3] != (((~len) >> 8) & 0xFF)) {
            return DeflateErrror.InvalidSeq;
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
            code |= self.bits(1);
            count = h.count[len];
            if (code - count < first) {
                return h.symbol[index + (code - first)];
            }

            index += count;
            first += count;
            code = code << 1;
            first = first << 1;
        }

        return DeflateError.OutOfCodes;
    }

    fn codes(self: *DeflateState, lencode: Huffman*, distcode: *Huffman) !void {
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
                self.out[self.outcnt] = symbol;
                self.outcnt += 1;
            } else if (symbol > 256) {
                symbol -= 257;
                if (symbol >= 29) {
                    return DeflateError.InvalidSeq;
                }

                len = lens[symbol] + self.bits(lext[symbol]);

                symbol = try self.decode(distcode);
                dist = dists[symbol] + self.bits(dext[symbol]);

                if (self.outcnt + len > self.outlen) {
                    return DeflateError.OutOfOuput;
                }

                while (len > 0) {
                    self.out[self.outcnt] = self.out[self.outcnt - dist];
                    self.outcnt += 1;
                    len -= 1;
                }
            }
        }
    }

    fn fixed(self: *DeflateState) i32 {
        var static: struct {
            var virgin: i32 = 1,
            var lencnt = [_]u16{0} ** (MAXBITS + 1),
            var lensym = [_]u16{0} ** FIXLCODES,
            var distcnt = [_]u16{0} ** (MAXBITS + 1),
            var distsym = [_]u16{0} ** MAXDCODES,
            var lencode: Huffman = undefined,
        };

        if (static.virgin == 1) {
            var symbol: i32 = 0;
            var lengths = [_]u16{0} ** FIXLCODES;
            static.lencode.count = lencnt;
            static.lencode.symbol = lensym;
            static.distcnt.cnt = distcnt;
            static.distcnt.symbol = distsym;

            symbol = 0;
            while (symbol < 144) : (symbol += 1) {
                lengths[symbol] = 8;
            }
            while (symbol < 256) : (symbol += 1) {
                lengths[symbol] = 9;
            }
            while (symbol < 280) : (symbol += 1) {
                lengths[symbol] = 7;
            }
            while (symbol < FIXLCODES) : (symbol += 1) {
                lengths[symbol] = 8;
            }
            construct(&static.lencodes, lengths, FIXLCODES);

            symbol = 0;
            while (symbol < MAXDCODES) : (symbol += 1) {
                lengths[symbol] = 5;
            }
            construct(&static.distcode, lengths, MAXDCODES);

            static.virgin = 0;
        }

        return self.codes(&static.lencode, &static.distcode);
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
        h.count[len] = 0;
    }
    while (symbol < n) : (symbol += 1) {
        h.count[length[symbol]] += 1;
    }

    if (h.count[0] == n) {
        return 0;
    }

    left = 1;
    len = 1;

    while (len <= MAXBITS) : (len += 1) {
        left = left << 1;
        left -= h.count[len];
        if (left < 0) {
            return left;
        }
    }

    offs[1] = 0;
    len = 1;
    while (len < MAXBITS) : (len += 1) {
        offs[len + 1] = offs[len] + h.count[len];
    }

    symbol = 0;
    while (symbol < n) {
        if (length[symbol] != 0) {
            h.symbol[offs[length[symbol]]] = symbol;
            offs[length[symbol]] += 1;
        }
    }

    return left;
}

/*
 * Process a dynamic codes block.
 *
 * Format notes:
 *
 * - A dynamic block starts with a description of the literal/length and
 *   distance codes for that block.  New dynamic blocks allow the compressor to
 *   rapidly adapt to changing data with new codes optimized for that data.
 *
 * - The codes used by the deflate format are "canonical", which means that
 *   the actual bits of the codes are generated in an unambiguous way simply
 *   from the number of bits in each code.  Therefore the code descriptions
 *   are simply a list of code lengths for each symbol.
 *
 * - The code lengths are stored in order for the symbols, so lengths are
 *   provided for each of the literal/length symbols, and for each of the
 *   distance symbols.
 *
 * - If a symbol is not used in the block, this is represented by a zero as the
 *   code length.  This does not mean a zero-length code, but rather that no
 *   code should be created for this symbol.  There is no way in the deflate
 *   format to represent a zero-length code.
 *
 * - The maximum number of bits in a code is 15, so the possible lengths for
 *   any code are 1..15.
 *
 * - The fact that a length of zero is not permitted for a code has an
 *   interesting consequence.  Normally if only one symbol is used for a given
 *   code, then in fact that code could be represented with zero bits.  However
 *   in deflate, that code has to be at least one bit.  So for example, if
 *   only a single distance base symbol appears in a block, then it will be
 *   represented by a single code of length one, in particular one 0 bit.  This
 *   is an incomplete code, since if a 1 bit is received, it has no meaning,
 *   and should result in an error.  So incomplete distance codes of one symbol
 *   should be permitted, and the receipt of invalid codes should be handled.
 *
 * - It is also possible to have a single literal/length code, but that code
 *   must be the end-of-block code, since every dynamic block has one.  This
 *   is not the most efficient way to create an empty block (an empty fixed
 *   block is fewer bits), but it is allowed by the format.  So incomplete
 *   literal/length codes of one symbol should also be permitted.
 *
 * - If there are only literal codes and no lengths, then there are no distance
 *   codes.  This is represented by one distance code with zero bits.
 *
 * - The list of up to 286 length/literal lengths and up to 30 distance lengths
 *   are themselves compressed using Huffman codes and run-length encoding.  In
 *   the list of code lengths, a 0 symbol means no code, a 1..15 symbol means
 *   that length, and the symbols 16, 17, and 18 are run-length instructions.
 *   Each of 16, 17, and 18 are followed by extra bits to define the length of
 *   the run.  16 copies the last length 3 to 6 times.  17 represents 3 to 10
 *   zero lengths, and 18 represents 11 to 138 zero lengths.  Unused symbols
 *   are common, hence the special coding for zero lengths.
 *
 * - The symbols for 0..18 are Huffman coded, and so that code must be
 *   described first.  This is simply a sequence of up to 19 three-bit values
 *   representing no code (0) or the code length for that symbol (1..7).
 *
 * - A dynamic block starts with three fixed-size counts from which is computed
 *   the number of literal/length code lengths, the number of distance code
 *   lengths, and the number of code length code lengths (ok, you come up with
 *   a better name!) in the code descriptions.  For the literal/length and
 *   distance codes, lengths after those provided are considered zero, i.e. no
 *   code.  The code length code lengths are received in a permuted order (see
 *   the order[] array below) to make a short code length code length list more
 *   likely.  As it turns out, very short and very long codes are less likely
 *   to be seen in a dynamic code description, hence what may appear initially
 *   to be a peculiar ordering.
 *
 * - Given the number of literal/length code lengths (nlen) and distance code
 *   lengths (ndist), then they are treated as one long list of nlen + ndist
 *   code lengths.  Therefore run-length coding can and often does cross the
 *   boundary between the two sets of lengths.
 *
 * - So to summarize, the code description at the start of a dynamic block is
 *   three counts for the number of code lengths for the literal/length codes,
 *   the distance codes, and the code length codes.  This is followed by the
 *   code length code lengths, three bits each.  This is used to construct the
 *   code length code which is used to read the remainder of the lengths.  Then
 *   the literal/length code lengths and distance lengths are read as a single
 *   set of lengths using the code length codes.  Codes are constructed from
 *   the resulting two sets of lengths, and then finally you can start
 *   decoding actual compressed data in the block.
 *
 * - For reference, a "typical" size for the code description in a dynamic
 *   block is around 80 bytes.
 */
local int dynamic(struct state *s)
{
    int nlen, ndist, ncode;             /* number of lengths in descriptor */
    int index;                          /* index of lengths[] */
    int err;                            /* construct() return value */
    short lengths[MAXCODES];            /* descriptor code lengths */
    short lencnt[MAXBITS+1], lensym[MAXLCODES];         /* lencode memory */
    short distcnt[MAXBITS+1], distsym[MAXDCODES];       /* distcode memory */
    struct huffman lencode, distcode;   /* length and distance codes */
    static const short order[19] =      /* permutation of code length codes */
        {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

    /* construct lencode and distcode */
    lencode.count = lencnt;
    lencode.symbol = lensym;
    distcode.count = distcnt;
    distcode.symbol = distsym;

    /* get number of lengths in each table, check lengths */
    nlen = bits(s, 5) + 257;
    ndist = bits(s, 5) + 1;
    ncode = bits(s, 4) + 4;
    if (nlen > MAXLCODES || ndist > MAXDCODES)
        return -3;                      /* bad counts */

    /* read code length code lengths (really), missing lengths are zero */
    for (index = 0; index < ncode; index++)
        lengths[order[index]] = bits(s, 3);
    for (; index < 19; index++)
        lengths[order[index]] = 0;

    /* build huffman table for code lengths codes (use lencode temporarily) */
    err = construct(&lencode, lengths, 19);
    if (err != 0)               /* require complete code set here */
        return -4;

    /* read length/literal and distance code length tables */
    index = 0;
    while (index < nlen + ndist) {
        int symbol;             /* decoded value */
        int len;                /* last length to repeat */

        symbol = decode(s, &lencode);
        if (symbol < 0)
            return symbol;          /* invalid symbol */
        if (symbol < 16)                /* length in 0..15 */
            lengths[index++] = symbol;
        else {                          /* repeat instruction */
            len = 0;                    /* assume repeating zeros */
            if (symbol == 16) {         /* repeat last length 3..6 times */
                if (index == 0)
                    return -5;          /* no last length! */
                len = lengths[index - 1];       /* last length */
                symbol = 3 + bits(s, 2);
            }
            else if (symbol == 17)      /* repeat zero 3..10 times */
                symbol = 3 + bits(s, 3);
            else                        /* == 18, repeat zero 11..138 times */
                symbol = 11 + bits(s, 7);
            if (index + symbol > nlen + ndist)
                return -6;              /* too many lengths! */
            while (symbol--)            /* repeat last or zero symbol times */
                lengths[index++] = len;
        }
    }

    /* check for end-of-block code -- there better be one! */
    if (lengths[256] == 0)
        return -9;

    /* build huffman table for literal/length codes */
    err = construct(&lencode, lengths, nlen);
    if (err && (err < 0 || nlen != lencode.count[0] + lencode.count[1]))
        return -7;      /* incomplete code ok only for single length 1 code */

    /* build huffman table for distance codes */
    err = construct(&distcode, lengths + nlen, ndist);
    if (err && (err < 0 || ndist != distcode.count[0] + distcode.count[1]))
        return -8;      /* incomplete code ok only for single length 1 code */

    /* decode data until end-of-block code */
    return codes(s, &lencode, &distcode);
}

/*
 * Inflate source to dest.  On return, destlen and sourcelen are updated to the
 * size of the uncompressed data and the size of the deflate data respectively.
 * On success, the return value of puff() is zero.  If there is an error in the
 * source data, i.e. it is not in the deflate format, then a negative value is
 * returned.  If there is not enough input available or there is not enough
 * output space, then a positive error is returned.  In that case, destlen and
 * sourcelen are not updated to facilitate retrying from the beginning with the
 * provision of more input data or more output space.  In the case of invalid
 * inflate data (a negative error), the dest and source pointers are updated to
 * facilitate the debugging of deflators.
 *
 * puff() also has a mode to determine the size of the uncompressed output with
 * no output written.  For this dest must be (unsigned char *)0.  In this case,
 * the input value of *destlen is ignored, and on return *destlen is set to the
 * size of the uncompressed output.
 *
 * The return codes are:
 *
 *   2:  available inflate data did not terminate
 *   1:  output space exhausted before completing inflate
 *   0:  successful inflate
 *  -1:  invalid block type (type == 3)
 *  -2:  stored block length did not match one's complement
 *  -3:  dynamic block code description: too many length or distance codes
 *  -4:  dynamic block code description: code lengths codes incomplete
 *  -5:  dynamic block code description: repeat lengths with no first length
 *  -6:  dynamic block code description: repeat more than specified lengths
 *  -7:  dynamic block code description: invalid literal/length code lengths
 *  -8:  dynamic block code description: invalid distance code lengths
 *  -9:  dynamic block code description: missing end-of-block code
 * -10:  invalid literal/length or distance code in fixed or dynamic block
 * -11:  distance is too far back in fixed or dynamic block
 *
 * Format notes:
 *
 * - Three bits are read for each block to determine the kind of block and
 *   whether or not it is the last block.  Then the block is decoded and the
 *   process repeated if it was not the last block.
 *
 * - The leftover bits in the last byte of the deflate data after the last
 *   block (if it was a fixed or dynamic block) are undefined and have no
 *   expected values to check.
 */
int puff(unsigned char *dest,           /* pointer to destination pointer */
         unsigned long *destlen,        /* amount of output space */
         const unsigned char *source,   /* pointer to source data pointer */
         unsigned long *sourcelen)      /* amount of input available */
{
    struct state s;             /* input/output state */
    int last, type;             /* block information */
    int err;                    /* return value */

    /* initialize output state */
    s.out = dest;
    s.outlen = *destlen;                /* ignored if dest is NIL */
    s.outcnt = 0;

    /* initialize input state */
    s.in = source;
    s.inlen = *sourcelen;
    s.incnt = 0;
    s.bitbuf = 0;
    s.bitcnt = 0;

    /* return if bits() or decode() tries to read past available input */
    if (setjmp(s.env) != 0)             /* if came back here via longjmp() */
        err = 2;                        /* then skip do-loop, return error */
    else {
        /* process blocks until last block or error */
        do {
            last = bits(&s, 1);         /* one if last block */
            type = bits(&s, 2);         /* block type 0..3 */
            err = type == 0 ?
                    stored(&s) :
                    (type == 1 ?
                        fixed(&s) :
                        (type == 2 ?
                            dynamic(&s) :
                            -1));       /* type == 3, invalid */
            if (err != 0)
                break;                  /* return with error */
        } while (!last);
    }

    /* update the lengths and return */
    if (err <= 0) {
        *destlen = s.outcnt;
        *sourcelen = s.incnt;
    }
    return err;
}
