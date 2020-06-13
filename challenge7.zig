const std = @import("std");
const base64 = std.base64;
const testing = std.testing;
const Base64DecoderWithIgnore = base64.Base64DecoderWithIgnore;

pub fn encryptEcb(dst: []u8, src: []const u8, key: [16]u8) void {
    var aes = std.crypto.AES128.init(key);
    var idx: usize = 0;
    while (idx < src.len) : (idx += key.len) {
        aes.encrypt(dst[idx .. idx + key.len], src[idx .. idx + key.len]);
    }
}

pub fn decryptEcb(dst: []u8, src: []const u8, key: [16]u8) void {
    var aes = std.crypto.AES128.init(key);

    var idx: usize = 0;
    while (idx < src.len) : (idx += key.len) {
        aes.decrypt(dst[idx .. idx + key.len], src[idx .. idx + key.len]);
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
