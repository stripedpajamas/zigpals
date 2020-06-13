const std = @import("std");
const testing = std.testing;

pub fn calcWithPkcsSize(blocksize: u32, input_len: usize) usize {
    const bs = @as(usize, blocksize);
    const pad = bs - (input_len % bs);
    return input_len + pad; 
}

test "pkcs#7 padding" {
    const test_cases = [_][2]usize{
        [_]usize{0, 16},
        [_]usize{14, 16},
        [_]usize{16, 32},
        [_]usize{33, 48},
    };
    for (test_cases) |test_case| {
        const actual = calcWithPkcsSize(16, test_case[0]);
        const expected = test_case[1];
        testing.expectEqual(expected, actual);
    }
}