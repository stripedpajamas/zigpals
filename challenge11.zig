const std = @import("std");
const ecb = @import("./challenge7.zig");
const cbc = @import("./challenge10.zig");
const pad = @import("./challenge9.zig");
const assert = std.debug.assert;
const mem = std.mem;
const crypto = std.crypto;
const testing = std.testing;

pub const AesMode = enum {
    ECB,
    CBC,
};

pub const OracleResult = struct {
    ciphertext: []u8,
    iv: [16]u8,
    mode: AesMode
};

pub fn encryptionOracle(allocator: *mem.Allocator, plaintext: []const u8) !OracleResult {
    var buf: [8]u8 = undefined;
    try crypto.randomBytes(buf[0..]);
    const seed = mem.readIntLittle(u64, buf[0..8]);

    var rng = std.rand.DefaultCsprng.init(seed);

    var key: [16]u8 = undefined;
    rng.random.bytes(&key);

    const garbage_prefix_len = rng.random.intRangeLessThan(usize, 5, 10);
    const garbage_suffix_len = rng.random.intRangeLessThan(usize, 5, 10);
    const dirtied_len = garbage_prefix_len + plaintext.len + garbage_suffix_len;
    const padded_dirtied_len = pad.calcWithPkcsSize(16, dirtied_len);
    const dirtied_input = try allocator.alloc(u8, padded_dirtied_len);
    defer allocator.free(dirtied_input);

    try crypto.randomBytes(dirtied_input[0..garbage_prefix_len]);
    for (plaintext) |byte, idx| {
        dirtied_input[garbage_prefix_len+idx] = byte;
    }
    try crypto.randomBytes(dirtied_input[dirtied_len-garbage_suffix_len..dirtied_len]);

    pad.pkcsPad(16, dirtied_input, dirtied_input[0..dirtied_len]);
    
    var ciphertext = try allocator.alloc(u8, dirtied_input.len);
    errdefer allocator.free(ciphertext);

    var mode = if (rng.random.boolean()) AesMode.CBC else AesMode.ECB;
    var iv: [16]u8 = undefined;

    switch (mode) {
        AesMode.CBC => {
            rng.random.bytes(&iv);
            cbc.encryptCbc(ciphertext, dirtied_input, key, iv);
        },
        AesMode.ECB => {
            ecb.encryptEcb(ciphertext, dirtied_input, key);
        }
    }

    return OracleResult{
        .ciphertext = ciphertext,
        .iv = iv,
        .mode = mode,
    };
}

test "encryption oracle" {
    var result1 = try encryptionOracle(testing.allocator, "hello world");
    var result2 = try encryptionOracle(testing.allocator, "hello world");
    assert(!mem.eql(u8, result1.ciphertext, result2.ciphertext));
    testing.allocator.free(result1.ciphertext);
    testing.allocator.free(result2.ciphertext);
}
