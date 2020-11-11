const std = @import("std");
const ecb = @import("./challenge7.zig");
const cbc = @import("./challenge10.zig");
const pad = @import("./challenge9.zig");
const detector = @import("./challenge8.zig");
const assert = std.debug.assert;
const mem = std.mem;
const crypto = std.crypto;
const rand = std.rand;
const testing = std.testing;

pub const AesMode = enum {
    ECB,
    CBC,
};

pub const OracleResult = struct {
    ciphertext: []u8, iv: []u8, mode: AesMode
};

pub fn EncryptionOracle(comptime keysize: usize) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        rng: rand.DefaultCsprng,

        pub fn init(allocator: *mem.Allocator) !Self {
            var seed: [rand.DefaultCsprng.secret_seed_length]u8 = undefined;
            try crypto.randomBytes(seed[0..]);

            return Self{
                .allocator = allocator,
                .rng = std.rand.DefaultCsprng.init(seed),
            };
        }

        pub fn deinit(self: *Self) void {}

        // caller is responsible to free result.ciphertext and result.iv
        pub fn encrypt(self: *Self, plaintext: []const u8) !OracleResult {
            var key: [keysize / 8]u8 = undefined;
            self.rng.random.bytes(&key);

            const garbage_prefix_len = self.rng.random.intRangeLessThan(usize, 5, 10);
            const garbage_suffix_len = self.rng.random.intRangeLessThan(usize, 5, 10);
            const dirtied_len = garbage_prefix_len + plaintext.len + garbage_suffix_len;
            const padded_dirtied_len = pad.calcWithPkcsSize(keysize / 8, dirtied_len);
            const dirtied_input = try self.allocator.alloc(u8, padded_dirtied_len);
            defer self.allocator.free(dirtied_input);

            try crypto.randomBytes(dirtied_input[0..garbage_prefix_len]);
            for (plaintext) |byte, idx| {
                dirtied_input[garbage_prefix_len + idx] = byte;
            }
            try crypto.randomBytes(dirtied_input[dirtied_len - garbage_suffix_len .. dirtied_len]);

            pad.pkcsPad(keysize / 8, dirtied_input, dirtied_input[0..dirtied_len]);

            var ciphertext = try self.allocator.alloc(u8, dirtied_input.len);
            errdefer self.allocator.free(ciphertext);

            var mode = if (self.rng.random.boolean()) AesMode.CBC else AesMode.ECB;
            var iv = try self.allocator.alloc(u8, keysize / 8);

            switch (mode) {
                AesMode.CBC => {
                    self.rng.random.bytes(iv);
                    cbc.encryptCbc(ciphertext, dirtied_input, key, iv[0 .. keysize / 8].*);
                },
                AesMode.ECB => {
                    ecb.encryptEcb(ciphertext, dirtied_input, key);
                },
            }

            return OracleResult{
                .ciphertext = ciphertext,
                .iv = iv,
                .mode = mode,
            };
        }
    };
}

pub fn detectMode(comptime keysize: usize, oracle: *EncryptionOracle(keysize)) !bool {
    const pt = [1]u8{'A'} ** (keysize * 3);
    const enc = try oracle.encrypt(&pt);
    defer oracle.allocator.free(enc.ciphertext);
    defer oracle.allocator.free(enc.iv);

    var det = detector.AesEcbDetector(keysize).init(oracle.allocator);
    defer det.deinit();

    const isEcb = try det.isEcb(enc.ciphertext);
    const isActuallyEcb = enc.mode == AesMode.ECB;

    return (isEcb and isActuallyEcb) or (!isEcb and !isActuallyEcb);
}

test "encryption oracle" {
    var allocator = testing.allocator;
    var oracle = try EncryptionOracle(128).init(allocator);
    defer oracle.deinit();

    var result1 = try oracle.encrypt("hello world");
    defer allocator.free(result1.ciphertext);
    defer allocator.free(result1.iv);
    var result2 = try oracle.encrypt("hello world");
    defer allocator.free(result2.ciphertext);
    defer allocator.free(result2.iv);
    assert(!mem.eql(u8, result1.ciphertext, result2.ciphertext));
}

test "detect oracle output" {
    var allocator = testing.allocator;
    var oracle = try EncryptionOracle(128).init(allocator);
    defer oracle.deinit();

    var count: usize = 0;
    while (count < 10) : (count += 1) {
        assert(try detectMode(128, &oracle));
    }
}
