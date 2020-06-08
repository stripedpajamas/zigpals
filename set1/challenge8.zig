const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const testing = std.testing;
const fmt = std.fmt;
const mem = std.mem;
const assert = std.debug.assert;

pub fn AesEcbDetector(comptime keysize: usize) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        samples: ArrayList([]const u8),
        blocks: StringHashMap(void),

        pub fn init(allocator: *mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .blocks = StringHashMap(void).init(allocator),
                .samples = ArrayList([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.blocks.deinit();
            for (self.samples.items) |item| {
                self.allocator.free(item);
            }
            self.samples.deinit();
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

        pub fn addSample(self: *Self, enc: []const u8) !void {
            if (try self.isEcb(enc)) {
                var enc_copy = try mem.Allocator.dupe(self.allocator, u8, enc);
                try self.samples.append(enc_copy);
            }
        }

        pub fn getEcbSamples(self: *Self) [][]const u8 {
            return self.samples.items;
        }
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
        try detector.addSample(enc);
    }

    const expected_ecb_sample = [_]u8{ 0xd8, 0x80, 0x61, 0x97, 0x40, 0xa8, 0xa1, 0x9b, 0x78, 0x40, 0xa8, 0xa3, 0x1c, 0x81, 0x0a, 0x3d, 0x08, 0x64, 0x9a, 0xf7, 0x0d, 0xc0, 0x6f, 0x4f, 0xd5, 0xd2, 0xd6, 0x9c, 0x74, 0x4c, 0xd2, 0x83, 0xe2, 0xdd, 0x05, 0x2f, 0x6b, 0x64, 0x1d, 0xbf, 0x9d, 0x11, 0xb0, 0x34, 0x85, 0x42, 0xbb, 0x57, 0x08, 0x64, 0x9a, 0xf7, 0x0d, 0xc0, 0x6f, 0x4f, 0xd5, 0xd2, 0xd6, 0x9c, 0x74, 0x4c, 0xd2, 0x83, 0x94, 0x75, 0xc9, 0xdf, 0xdb, 0xc1, 0xd4, 0x65, 0x97, 0x94, 0x9d, 0x9c, 0x7e, 0x82, 0xbf, 0x5a, 0x08, 0x64, 0x9a, 0xf7, 0x0d, 0xc0, 0x6f, 0x4f, 0xd5, 0xd2, 0xd6, 0x9c, 0x74, 0x4c, 0xd2, 0x83, 0x97, 0xa9, 0x3e, 0xab, 0x8d, 0x6a, 0xec, 0xd5, 0x66, 0x48, 0x91, 0x54, 0x78, 0x9a, 0x6b, 0x03, 0x08, 0x64, 0x9a, 0xf7, 0x0d, 0xc0, 0x6f, 0x4f, 0xd5, 0xd2, 0xd6, 0x9c, 0x74, 0x4c, 0xd2, 0x83, 0xd4, 0x03, 0x18, 0x0c, 0x98, 0xc8, 0xf6, 0xdb, 0x1f, 0x2a, 0x3f, 0x9c, 0x40, 0x40, 0xde, 0xb0, 0xab, 0x51, 0xb2, 0x99, 0x33, 0xf2, 0xc1, 0x23, 0xc5, 0x83, 0x86, 0xb0, 0x6f, 0xba, 0x18, 0x6a };

    var ecb_samples = detector.getEcbSamples();
    assert(ecb_samples.len == 1);
    testing.expectEqualSlices(u8, ecb_samples[0], expected_ecb_sample[0..]);
}
