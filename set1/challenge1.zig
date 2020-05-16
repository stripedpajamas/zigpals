const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = std.Buffer;
const b64Decoder = std.base64.standard_decoder;
const fmt = std.fmt;
const testing = std.testing;
const assert = std.debug.assert;
const warn = std.debug.warn;

pub const Encoder = struct {
  allocator: *Allocator,
  pub fn init(allocator: *Allocator) Encoder {
    return Encoder{
      .allocator = allocator,
    };
  }

  pub fn base64ToHex(enc: *const Encoder, input: []const u8) ![]const u8 {
      var inputBytes = try enc.allocator.alloc(u8, try b64Decoder.calcSize(input));
      defer enc.allocator.free(inputBytes);
      try b64Decoder.decode(inputBytes, input);

      var output = try fmt.allocPrint(enc.allocator, "{x}", .{inputBytes});
      
      return output;
  }
};


test "encoder" {
  const encoder = Encoder.init(testing.allocator);
  const res = try encoder.base64ToHex("SSdtIGtpbGxpbmcgeW91ciBicmFpbiBsaWtlIGEgcG9pc29ub3VzIG11c2hyb29t");
  warn("hello? {}\n", .{res});
  testing.allocator.free(res);
}