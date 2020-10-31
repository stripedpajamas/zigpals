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

    // for parsing; idk how to get this from the struct dynamically
    // and still have it be an enum
    const Field = enum {
        email,
        uid,
        role,
    };

    const OptionalUser = struct {
        email: ?[]const u8,
        uid: ?u32,
        role: ?Role,
    };

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

    pub fn encodedSize(user: *User) usize {
        var email_len = user.email.len;
        var uid_len = @floatToInt(usize, math.floor(math.log10(@intToFloat(f64, user.uid))) + 1);
        var role_len = @tagName(user.role).len;

        var meta_len = "email=&uid=&role=".len;
        return meta_len + email_len + uid_len + role_len;
    }

    // Caller owns allocated email field (must free user.email at some point)
    pub fn fromString(allocator: *mem.Allocator, str: []const u8) !User {
        // buffer to hold values as we parse
        var buf: [100]u8 = undefined;
        var buf_idx: usize = 0;
        var idx: usize = 0;

        var user = OptionalUser{
            .email = null,
            .uid = null,
            .role = null,
        };
        errdefer {
            if (user.email) |email| {
                allocator.free(email);
            }
        }

        var parsingField: ?Field = null;
        while (idx < str.len) : (idx += 1) {
            switch (str[idx]) {
                '=' => {
                    // at the end of a key
                    // 1. validate it
                    var fieldName = buf[0..buf_idx];
                    if (std.meta.stringToEnum(Field, fieldName)) |field| {
                        parsingField = field;
                    } else {
                        return error.InvalidField;
                    }

                    // 2. begin collecting value
                    buf_idx = 0;
                },
                '&' => {
                    // at the end of a value
                    // 1. save it
                    if (parsingField) |field| {
                        try populate(allocator, &user, field, buf[0..buf_idx]);
                    } else {
                        return error.InvalidInput;
                    }
                    // 2. begin collecting next key
                    parsingField = null;
                    buf_idx = 0;
                },
                else => {
                    if (buf_idx >= buf.len) {
                        return error.EmailTooLong;
                    }
                    buf[buf_idx] = str[idx];
                    buf_idx += 1;
                },
            }
        }

        // grab last value
        if (parsingField) |field| {
            try populate(allocator, &user, field, buf[0..buf_idx]);
        }

        if (user.email == null or user.uid == null or user.role == null) {
            return error.IncompleteInput;
        }

        return User{
            .email = user.email.?,
            .uid = user.uid.?,
            .role = user.role.?,
        };
    }

    fn populate(allocator: *mem.Allocator, user: *OptionalUser, field: Field, val: []const u8) !void {
        var value = try mem.dupe(allocator, u8, val); // copy the value
        errdefer allocator.free(value);

        switch (field) {
            Field.email => {
                user.email = value;
            },
            Field.uid => {
                var uid = fmt.parseInt(u32, value, 10) catch |err| {
                    return error.InvalidUserID;
                };
                user.uid = uid;
                allocator.free(value);
            },
            Field.role => {
                var role = Role.fromName(value);
                if (role) |r| {
                    user.role = r;
                } else {
                    return error.InvalidRole;
                }
                allocator.free(value);
            },
        }
    }
};

test "user encoding" {
    var u = User{
        .email = "foo@bar.com",
        .uid = 4294967295,
        .role = Role.User,
    };

    var encoded = try testing.allocator.alloc(u8, u.encodedSize());
    defer testing.allocator.free(encoded);
    u.encode(encoded);

    testing.expectEqualSlices(u8, "email=foo@bar.com&uid=4294967295&role=User", encoded);

    const user = try User.fromString(testing.allocator, encoded);

    testing.expectEqualSlices(u8, u.email, user.email);
    assert(u.uid == user.uid);
    assert(u.role == user.role);

    testing.allocator.free(user.email);
}

test "user parsing errors" {
    const testCase = struct {
        input: []const u8,
        expected_err: anyerror,
    };
    const tests = [_]testCase{
        .{ .input = "uid=4294967295&role=User", .expected_err = error.IncompleteInput },
        .{ .input = "mail=foo@bar.com&uid=4294967295&role=User", .expected_err = error.InvalidField },
        .{ .input = "email=foo@bar.com&uid=14294967295&role=User", .expected_err = error.InvalidUserID },
        .{ .input = "email=foo@bar.com&uid=4294967295&role=Poppy", .expected_err = error.InvalidRole },
        .{ .input = "&email=foo@bar.com&uid=4294967295&role=User", .expected_err = error.InvalidInput },
        .{ .input = "email=foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo@bar.com&uid=4294967295&role=User", .expected_err = error.EmailTooLong },
    };
    for (tests) |t| {
        if (User.fromString(testing.allocator, t.input)) |user| {
            assert(false); // should have been an error
        } else |err| {
            assert(err == t.expected_err);
        }
    }
}
