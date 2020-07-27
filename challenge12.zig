const std = @import("std");
const ecb = @import("./challenge7.zig");
const pad = @import("./challenge9.zig");
const crypto = std.crypto;
const mem = std.mem;
const testing = std.testing;

pub fn EncryptionOracle(comptime keysize: usize) type {
    return struct {
        const Self = @This();
        const secret_suffix = [_]u8{0x52, 0x6f, 0x6c, 0x6c, 0x69, 0x6e, 0x27, 0x20, 0x69, 0x6e, 0x20, 0x6d, 0x79, 0x20, 0x35, 0x2e, 0x30, 0x0a, 0x57, 0x69, 0x74, 0x68, 0x20, 0x6d, 0x79, 0x20, 0x72, 0x61, 0x67, 0x2d, 0x74, 0x6f, 0x70, 0x20, 0x64, 0x6f, 0x77, 0x6e, 0x20, 0x73, 0x6f, 0x20, 0x6d, 0x79, 0x20, 0x68, 0x61, 0x69, 0x72, 0x20, 0x63, 0x61, 0x6e, 0x20, 0x62, 0x6c, 0x6f, 0x77, 0x0a, 0x54, 0x68, 0x65, 0x20, 0x67, 0x69, 0x72, 0x6c, 0x69, 0x65, 0x73, 0x20, 0x6f, 0x6e, 0x20, 0x73, 0x74, 0x61, 0x6e, 0x64, 0x62, 0x79, 0x20, 0x77, 0x61, 0x76, 0x69, 0x6e, 0x67, 0x20, 0x6a, 0x75, 0x73, 0x74, 0x20, 0x74, 0x6f, 0x20, 0x73, 0x61, 0x79, 0x20, 0x68, 0x69, 0x0a, 0x44, 0x69, 0x64, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x73, 0x74, 0x6f, 0x70, 0x3f, 0x20, 0x4e, 0x6f, 0x2c, 0x20, 0x49, 0x20, 0x6a, 0x75, 0x73, 0x74, 0x20, 0x64, 0x72, 0x6f, 0x76, 0x65, 0x20, 0x62, 0x79, 0x0a};

        var key: [keysize/8]u8 = undefined;

        allocator: *mem.Allocator,
        rng: std.rand.DefaultCsprng,

        pub fn init(allocator: *mem.Allocator) !Self {
            var buf: [8]u8 = undefined;
            try crypto.randomBytes(buf[0..]);

            var seed = mem.readIntLittle(u64, buf[0..8]);
            var rng = std.rand.DefaultCsprng.init(seed);

            rng.random.bytes(key[0..]);

            return Self{
                .allocator = allocator,
                .rng = rng, 
            };
        }

        pub fn deinit(self: *Self) void {
        }

        pub fn encrypt(self: *Self, plaintext: []const u8) ![]u8 {
            var secret_and_plaintext = try self.createInput(plaintext);
            defer self.allocator.free(secret_and_plaintext);

            var ciphertext = try self.allocator.alloc(u8, secret_and_plaintext.len);
            errdefer self.allocator.free(ciphertext);
            ecb.encryptEcb(ciphertext, secret_and_plaintext, key);

            return ciphertext;
        }

        fn createInput(self: *Self, plaintext: []const u8) ![]u8 {
            const padded_len = pad.calcWithPkcsSize(keysize/8, secret_suffix.len + plaintext.len);
            var secret_and_plaintext = try self.allocator.alloc(u8, padded_len);

            // create (plaintext || suffix)
            var idx: usize = 0;
            while (idx < plaintext.len) : (idx += 1) {
                secret_and_plaintext[idx + secret_suffix.len] = plaintext[idx];
            }
            idx = 0;
            while (idx < secret_suffix.len) : (idx += 1) {
                secret_and_plaintext[idx] = secret_suffix[idx];
            }

            pad.pkcsPad(keysize/8, secret_and_plaintext, secret_and_plaintext[0..secret_suffix.len + plaintext.len]);
            return secret_and_plaintext;
        }
    };

}

test "byte-at-a-time ecb decryption (simple)" {
    const allocator = testing.allocator;
    var oracle = try EncryptionOracle(128).init(allocator);
    defer oracle.deinit();

    var ciphertext = try oracle.encrypt("hello world");
    std.debug.warn("\nciphertext! {x}\n", .{ciphertext});
    allocator.free(ciphertext);
}
