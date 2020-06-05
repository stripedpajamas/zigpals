const std = @import("std");
const StringHashMap = std.StringHashMap;
const testing = std.testing;
const fmt = std.fmt;
const mem = std.mem;

pub fn AesEcbDetector(comptime keysize: usize) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        blocks: StringHashMap(void),

        pub fn init(allocator: *mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .blocks = StringHashMap(void).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.blocks.deinit();
        }

        pub fn isEcb(self: *Self, enc: []const u8) !bool {
            self.blocks.clear();
            const ks_bytes = keysize / 8;
            var idx: usize = 0;
            while (idx < enc.len) : (idx += ks_bytes) {
                if (self.blocks.get(enc[idx .. idx + ks_bytes])) |_| {
                    return true;
                }
                _ = try self.blocks.put(enc[idx .. idx + ks_bytes], {});
            }
            return false;
        }

        pub fn addSample(self: *Self, enc: []const u8) !void {}

        pub fn getEcbSamples(self: *Self) [][]u8 {}
    };
}

test "detect single byte xor" {
    var allocator = testing.allocator;

    const challenge8_input_raw = @embedFile("./data/challenge8_input.txt");

    var detector = AesEcbDetector(128).init(allocator);
    defer detector.deinit();

    var enc = try allocator.alloc(u8, 30);
    defer allocator.free(enc);
    var input_it = mem.split(challenge8_input_raw, "\n");
    while (input_it.next()) |line| {
        var line_size = line.len / 2;
        if (line_size > enc.len) {
            enc = try allocator.realloc(enc, line_size);
        }
        try fmt.hexToBytes(enc[0..line_size], line);
        if (try detector.isEcb(enc)) {
            testing.expectEqualStrings(line, "d880619740a8a19b7840a8a31c810a3d08649af70dc06f4fd5d2d69c744cd283e2dd052f6b641dbf9d11b0348542bb5708649af70dc06f4fd5d2d69c744cd2839475c9dfdbc1d46597949d9c7e82bf5a08649af70dc06f4fd5d2d69c744cd28397a93eab8d6aecd566489154789a6b0308649af70dc06f4fd5d2d69c744cd283d403180c98c8f6db1f2a3f9c4040deb0ab51b29933f2c123c58386b06fba186a");
        }
    }
}
