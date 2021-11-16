const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const assert = std.debug.assert;

pub fn singleByteXor(out: []u8, input: []const u8, key: u8) void {
    assert(out.len == input.len);
    const outSlice = out[0..out.len];

    for (input) |value, idx| {
        outSlice[idx] = value ^ key;
    }
}

pub fn fixedXor(out: []u8, input: []const u8, key: []const u8) void {
    assert(out.len == input.len and input.len == key.len);
    const outSlice = out[0..out.len];

    for (input) |value, idx| {
        outSlice[idx] = value ^ key[idx];
    }
}

test "xor cipher" {
    var input = [_]u8{ 0x1c, 0x01, 0x11, 0x00, 0x1f, 0x01, 0x01, 0x00, 0x06, 0x1a, 0x02, 0x4b, 0x53, 0x53, 0x50, 0x09, 0x18, 0x1c };
    var key = [_]u8{ 0x68, 0x69, 0x74, 0x20, 0x74, 0x68, 0x65, 0x20, 0x62, 0x75, 0x6c, 0x6c, 0x27, 0x73, 0x20, 0x65, 0x79, 0x65 };
    var expected = [_]u8{ 0x74, 0x68, 0x65, 0x20, 0x6b, 0x69, 0x64, 0x20, 0x64, 0x6f, 0x6e, 0x27, 0x74, 0x20, 0x70, 0x6c, 0x61, 0x79 };

    var actual: [18]u8 = undefined;
    fixedXor(actual[0..], input[0..], key[0..]);

    try testing.expectEqualSlices(u8, actual[0..], expected[0..]);
}

test "single-byte cipher" {
    const input = "hello world";
    const key = 'z';
    const expected = [_]u8{ 0x12, 0x1f, 0x16, 0x16, 0x15, 0x5a, 0x0d, 0x15, 0x08, 0x16, 0x1e };

    var actual: [11]u8 = undefined;
    singleByteXor(actual[0..], input, key);
    try testing.expectEqualSlices(u8, actual[0..], expected[0..]);
}
