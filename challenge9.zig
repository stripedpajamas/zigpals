const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

pub fn allocPkcsPad(allocator: *mem.Allocator, blocksize: u32, src: []const u8) ![]u8 {
    var dst = try allocator.alloc(u8, calcWithPkcsSize(blocksize, src.len));
    pkcsPad(blocksize, dst, src);

    return dst;
}

pub fn pkcsPad(blocksize: u32, dst: []u8, src: []const u8) void {
    const padded_len = calcWithPkcsSize(blocksize, src.len);
    assert(dst.len >= padded_len);

    const pad_len = padded_len - src.len;
    const pad = @truncate(u8, pad_len);

    for (src) |byte, idx| {
        dst[idx] = byte;
    }

    var idx: usize = src.len;
    while (idx < dst.len) : (idx += 1) {
        dst[idx] = pad;
    }
}

pub fn calcWithPkcsSize(blocksize: u32, input_len: usize) usize {
    const bs = @as(usize, blocksize);
    const pad = bs - (input_len % bs);
    return input_len + pad;
}

test "calc pkcs#7 padding size" {
    const test_cases = [_][2]usize{
        [_]usize{ 0, 16 },
        [_]usize{ 14, 16 },
        [_]usize{ 16, 32 },
        [_]usize{ 33, 48 },
    };
    for (test_cases) |test_case| {
        const actual = calcWithPkcsSize(16, test_case[0]);
        const expected = test_case[1];
        testing.expectEqual(expected, actual);
    }
}

test "pkcs#7 padding" {
    const expected = [_]u8{ 'Y', 'E', 'L', 'L', 'O', 'W', ' ', 'S', 'U', 'B', 'M', 'A', 'R', 'I', 'N', 'E', 0x04, 0x04, 0x04, 0x04 };

    var actual: [20]u8 = undefined;
    pkcsPad(20, actual[0..], "YELLOW SUBMARINE");

    testing.expectEqualSlices(u8, expected[0..], actual[0..]);

    var alloc_actual = try allocPkcsPad(testing.allocator, 20, "YELLOW SUBMARINE");
    defer testing.allocator.free(alloc_actual);
    testing.expectEqualSlices(u8, expected[0..], alloc_actual);
}
