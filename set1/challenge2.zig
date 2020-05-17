const std = @import("std");
const Encoder = @import("./challenge1.zig").Encoder;
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const testing = std.testing;
const assert = std.debug.assert;

pub fn fixedXor(out: []u8, input: []u8, key: []u8) !void {
    assert(out.len == input.len and input.len == key.len);
    const outSlice = out[0..out.len];

    for (input) |value, idx| {
        outSlice[idx] = value ^ key[idx];
    }
}

test "xor cipher" {
    const encoder = Encoder.init(testing.allocator);

    var input = try testing.allocator.alloc(u8, 18);
    defer testing.allocator.free(input);
    try fmt.hexToBytes(input, "1c0111001f010100061a024b53535009181c");
    var key = try testing.allocator.alloc(u8, 18);
    defer testing.allocator.free(key);
    try fmt.hexToBytes(key, "686974207468652062756c6c277320657965");
    var expected = try testing.allocator.alloc(u8, 18);
    defer testing.allocator.free(expected);
    try fmt.hexToBytes(expected, "746865206b696420646f6e277420706c6179");

    var actual = try testing.allocator.alloc(u8, 18);
    defer testing.allocator.free(actual);
    try fixedXor(actual, input, key);

    testing.expectEqualSlices(u8, actual, expected);
}
