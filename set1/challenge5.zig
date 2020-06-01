const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const assert = std.debug.assert;

pub fn repeatedKeyXor(out: []u8, input: []const u8, key: []const u8) !void {
    assert(out.len == input.len);
    const outSlice = out[0..out.len];

    var keyIdx: usize = 0;
    for (input) |value, idx| {
        outSlice[idx] = value ^ key[keyIdx];
        keyIdx = (keyIdx + 1) % key.len;
    }
}

test "repeated key xor" {
    const inputText = "Burning 'em, if you ain't quick and nimble\nI go crazy when I hear a cymbal";
    const key = "ICE";
    const expectedOut = try testing.allocator.alloc(u8, inputText.len);
    defer testing.allocator.free(expectedOut);
    try fmt.hexToBytes(expectedOut, "0b3637272a2b2e63622c2e69692a23693a2a3c6324202d623d63343c2a26226324272765272a282b2f20430a652e2c652a3124333a653e2b2027630c692b20283165286326302e27282f");

    const actualOut = try testing.allocator.alloc(u8, expectedOut.len);
    defer testing.allocator.free(actualOut);
    try repeatedKeyXor(actualOut, inputText, key);

    testing.expectEqualSlices(u8, expectedOut, actualOut);
}
