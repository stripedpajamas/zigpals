const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = std.Buffer;
const base64 = std.base64;
const fmt = std.fmt;
const testing = std.testing;

pub const Encoder = struct {
    allocator: *Allocator,
    pub fn init(allocator: *Allocator) Encoder {
        return Encoder{
            .allocator = allocator,
        };
    }

    pub fn base64ToHex(enc: *const Encoder, input: []const u8) ![]const u8 {
        var inputBytes = try enc.allocator.alloc(u8, try base64.standard_decoder.calcSize(input));
        defer enc.allocator.free(inputBytes);
        try base64.standard_decoder.decode(inputBytes, input);

        var output = try fmt.allocPrint(enc.allocator, "{x}", .{inputBytes});

        return output;
    }

    pub fn hexToBase64(enc: *const Encoder, input: []const u8) ![]const u8 {
        var inputBytes = try enc.allocator.alloc(u8, input.len / 2);
        defer enc.allocator.free(inputBytes);
        try fmt.hexToBytes(inputBytes, input);

        const outputLen = base64.Base64Encoder.calcSize(inputBytes.len);
        var output = try enc.allocator.alloc(u8, outputLen);
        base64.standard_encoder.encode(output, inputBytes);

        return output;
    }
};

test "encoder" {
    const encoder = Encoder.init(testing.allocator);
    const expected_b64 = "SSdtIGtpbGxpbmcgeW91ciBicmFpbiBsaWtlIGEgcG9pc29ub3VzIG11c2hyb29t";
    const expected_hex = "49276d206b696c6c696e6720796f757220627261696e206c696b65206120706f69736f6e6f7573206d757368726f6f6d";

    const actual_b64 = try encoder.hexToBase64(expected_hex);
    const actual_hex = try encoder.base64ToHex(expected_b64);
    testing.expectEqualSlices(u8, actual_hex, expected_hex);
    testing.expectEqualSlices(u8, actual_b64, expected_b64);

    testing.allocator.free(actual_b64);
    testing.allocator.free(actual_hex);
}
