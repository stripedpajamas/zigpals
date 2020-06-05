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
    var allocator = testing.allocator;

    var decoder = Base64DecoderWithIgnore.init(base64.standard_alphabet_chars, base64.standard_pad_char, "\n");
    const challenge7_input_raw = @embedFile("./data/challenge7_input.txt");
    var input_bytes = try allocator.alloc(u8, Base64DecoderWithIgnore.calcSizeUpperBound(challenge7_input_raw.len));
    defer allocator.free(input_bytes);
    var written = try decoder.decode(input_bytes, challenge7_input_raw);

    var enc = input_bytes[0..written];

    const key = [16]u8{ 'Y', 'E', 'L', 'L', 'O', 'W', ' ', 'S', 'U', 'B', 'M', 'A', 'R', 'I', 'N', 'E' };
    const dec = try allocator.alloc(u8, enc.len);
    defer allocator.free(dec);
    decryptEcb(dec, enc, key);

    std.debug.warn("\ngot this plaintext:\n{}\n", .{dec});

    encryptEcb(dec, dec, key);

    testing.expectEqualSlices(u8, dec, enc);
}
