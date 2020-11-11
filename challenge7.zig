const std = @import("std");
const Aes128 = std.crypto.core.aes.Aes128;
const base64 = std.base64;
const testing = std.testing;
const Base64DecoderWithIgnore = base64.Base64DecoderWithIgnore;

pub fn encryptEcb(dst: []u8, src: []const u8, key: [16]u8) void {
    var aes = Aes128.initEnc(key);
    var blk: [16]u8 = undefined;

    var idx: usize = 0;
    while (idx < src.len) : (idx += blk.len) {
        // copy src into blk
        var j: usize = 0;
        while (j < blk.len) : (j += 1) {
            blk[j] = src[j + idx];
        }

        // encrypt into blk
        aes.encrypt(&blk, &blk);

        // copy encryption into dst
        j = 0;
        while (j < blk.len) : (j += 1) {
            dst[j + idx] = blk[j];
        }
    }
}

pub fn decryptEcb(dst: []u8, src: []const u8, key: [16]u8) void {
    var aes = Aes128.initDec(key);
    var blk: [16]u8 = undefined;

    var idx: usize = 0;
    while (idx < src.len) : (idx += blk.len) {
        // copy src into blk
        var j: usize = 0;
        while (j < blk.len) : (j += 1) {
            blk[j] = src[j + idx];
        }

        // decrypt into blk
        aes.decrypt(&blk, &blk);

        // copy decryption into dst
        j = 0;
        while (j < blk.len) : (j += 1) {
            dst[j + idx] = blk[j];
        }
    }
}

test "aes ecb" {
    const challenge7_input_raw = @embedFile("./data/challenge7_input.txt");
    var decoder = Base64DecoderWithIgnore.init(base64.standard_alphabet_chars, base64.standard_pad_char, "\n");
    var input_bytes: [Base64DecoderWithIgnore.calcSizeUpperBound(challenge7_input_raw.len)]u8 = undefined;
    var written = try decoder.decode(input_bytes[0..], challenge7_input_raw);

    var enc = input_bytes[0..written];

    const key = [_]u8{ 'Y', 'E', 'L', 'L', 'O', 'W', ' ', 'S', 'U', 'B', 'M', 'A', 'R', 'I', 'N', 'E' };
    var dec_buf: [input_bytes.len]u8 = undefined;
    var dec = dec_buf[0..written];
    decryptEcb(dec[0..written], enc[0..], key);

    std.debug.warn("\ngot this plaintext:\n{}\n", .{dec});

    encryptEcb(dec[0..], dec[0..], key);

    testing.expectEqualSlices(u8, dec[0..], enc);
}
