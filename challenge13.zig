const std = @import("std");
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const assert = std.debug.assert;
const testing = std.testing;

pub const Role = enum {
    User,
    Admin,

    pub fn fromName(name: []const u8) ?Role {
        return std.meta.stringToEnum(Role, name);
    }
};

pub const User = struct {
    email: []const u8,
    uid: u32,
    role: Role,

    pub fn encode(user: *User, dest: []u8) void {
        assert(dest.len >= user.encodedSize());

        var buf: [10]u8 = undefined;
        var uid_str = fmt.bufPrint(buf[0..], "{}", .{user.uid}) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable, // u32 gotta fit into 10 bytes by definition
        };
        var slices = &[_][]const u8{
            "email=", user.email,          "&",
            "uid=",   uid_str,             "&",
            "role=",  @tagName(user.role),
        };

        var idx: usize = 0;
        for (slices) |slice| {
            mem.copy(u8, dest[idx..], slice);
            idx += slice.len;
        }
    }

    fn encodedSize(user: *User) usize {
        var email_len = user.email.len;
        var uid_len = @floatToInt(usize, math.floor(math.log10(@intToFloat(f64, user.uid))) + 1);
        var role_len = @tagName(user.role).len;

        var meta_len = "email=&uid=&role=".len;
        return meta_len + email_len + uid_len + role_len;
    }
};

test "user encoding" {
    var u = User{
        .email = "foo@bar.com",
        .uid = 4294967295,
        .role = Role.User,
    };

    var dest = try testing.allocator.alloc(u8, u.encodedSize());
    defer testing.allocator.free(dest);
    u.encode(dest);

    testing.expectEqualSlices(u8, "email=foo@bar.com&uid=4294967295&role=User", dest);
}
