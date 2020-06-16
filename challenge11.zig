const std = @import("std");
const ecb = @import("./challenge7.zig");
const cbc = @import("./challenge10.zig");
const pad = @import("./challenge9.zig");
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

    const input = try pad.allocPkcsPad(allocator, 16, plaintext);
    defer allocator.free(input);
    
    var ciphertext = try allocator.alloc(u8, input.len);
    var mode = if (rng.random.boolean()) AesMode.CBC else AesMode.ECB;
    var iv: [16]u8 = undefined;

    switch (mode) {
        AesMode.CBC => {
            rng.random.bytes(&iv);
            cbc.encryptCbc(ciphertext, input, key, iv);
        },
        AesMode.ECB => {
            ecb.encryptEcb(ciphertext, input, key);
        }
    }

    return OracleResult{
        .ciphertext = ciphertext,
        .iv = iv,
        .mode = mode,
    };
}

test "encryption oracle" {
    var result = try encryptionOracle(testing.allocator, "hello world");
    std.debug.warn("\nciphertext: {x}\nmode: {}\n", .{result.ciphertext, result.mode});

    testing.allocator.free(result.ciphertext);
}
