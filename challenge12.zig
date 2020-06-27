const std = @import("std");
const crypto = std.crypto;
const mem = std.mem;
const testing = std.testing;

pub fn EncryptionOracle(comptime keysize: usize) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        rng: std.rand.DefaultCsprng,
        key: []u8,

        pub fn init(allocator: *mem.Allocator) !Self {
            var buf: [8]u8 = undefined;
            try crypto.randomBytes(buf[0..]);

            var seed = mem.readIntLittle(u64, buf[0..8]);
            var rng = std.rand.DefaultCsprng.init(seed);

            var key = try allocator.alloc(u8, keysize/8);
            errdefer allocator.free(key);
            rng.random.bytes(key);

            return Self{
                .allocator = allocator,
                .rng = rng, 
                .key = key,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.key);
        }
    };

}

test "byte-at-a-time ecb decryption (simple)" {
    const allocator = testing.allocator;
    var oracle = try EncryptionOracle(128).init(allocator);
    defer oracle.deinit();
}