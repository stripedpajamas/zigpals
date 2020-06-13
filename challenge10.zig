const std = @import("std");
const xor = @import("./challenge2.zig");
const aes = @import("./challenge7.zig");
const assert = std.debug.assert;
const base64 = std.base64;
const testing = std.testing;
const Base64DecoderWithIgnore = base64.Base64DecoderWithIgnore;

pub fn encryptCbc(dst: []u8, src: []const u8, key: [16]u8, iv: [16]u8) void {
    assert(dst.len >= src.len);

    var _iv: []const u8 = iv[0..];
    var blk: [16]u8 = undefined;
    var idx: usize = 0;
    while (idx < src.len) : (idx += 16) {
        xor.fixedXor(blk[0..], src[idx .. idx + 16], _iv);
        aes.encryptEcb(dst[idx .. idx + 16], blk[0..], key);
        _iv = dst[idx .. idx + 16];
    }
}

pub fn decryptCbc(dst: []u8, src: []const u8, key: [16]u8, iv: [16]u8) void {
    assert(dst.len >= src.len);

    var _iv: []const u8 = iv[0..];
    var blk: [16]u8 = undefined;
    var idx: usize = 0;
    while (idx < src.len) : (idx += 16) {
        aes.decryptEcb(blk[0..], src[idx .. idx + 16], key);
        xor.fixedXor(dst[idx .. idx + 16], blk[0..], _iv);
        _iv = src[idx .. idx + 16];
    }
}

test "aes cbc" {
    const challenge10_input_raw = @embedFile("./data/challenge10_input.txt");
    var decoder = Base64DecoderWithIgnore.init(base64.standard_alphabet_chars, base64.standard_pad_char, "\n");
    var input_bytes: [Base64DecoderWithIgnore.calcSizeUpperBound(challenge10_input_raw.len)]u8 = undefined;
    var written = try decoder.decode(input_bytes[0..], challenge10_input_raw);

    var enc = input_bytes[0..written];

    const key = [_]u8{ 'Y', 'E', 'L', 'L', 'O', 'W', ' ', 'S', 'U', 'B', 'M', 'A', 'R', 'I', 'N', 'E' };
    const iv = [1]u8{0} ** 16;
    var dec_buf: [input_bytes.len]u8 = undefined;
    var dec = dec_buf[0..written];
    decryptCbc(dec, enc, key, iv);

    std.debug.warn("\ngot this plaintext:\n{}\n", .{dec});

    encryptCbc(dec[0..], dec[0..], key, iv);

    testing.expectEqualSlices(u8, dec[0..], enc);
}
