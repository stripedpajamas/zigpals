const std = @import("std");
const ecb = @import("./challenge7.zig");
const pad = @import("./challenge9.zig");
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const crypto = std.crypto;
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
    pub fn profileFor(allocator: *mem.Allocator, email: []const u8) !User {
        var clean_email = try allocator.alloc(u8, email.len);
        var idx: usize = 0;
        var bad_chars: usize = 0;
        while (idx < email.len) : (idx += 1) {
            if (email[idx] == '=' or email[idx] == '&') {
                bad_chars += 1;
                continue;
            }
            clean_email[idx - bad_chars] = email[idx];
        }

        clean_email = allocator.shrink(clean_email, email.len - bad_chars);

        return User{
            .email = clean_email,
            .uid = 15,
            .role = Role.User,
        };
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
                        return error.ValueTooBig;
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

pub const UserController = struct {
    var key: [16]u8 = undefined;

    allocator: *mem.Allocator,

    pub fn init(allocator: *mem.Allocator) !UserController {
        var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        try crypto.randomBytes(seed[0..]);

        var rng = std.rand.DefaultCsprng.init(seed);

        rng.random.bytes(key[0..]);

        return UserController{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UserController) void {}

    // create a profile, encode it, encrypt the encoding, and return it
    pub fn profileFor(self: *UserController, email: []const u8) ![]const u8 {
        var profile = try User.profileFor(self.allocator, email);
        defer self.allocator.free(profile.email);

        var encoded = try self.allocator.alloc(u8, profile.encodedSize());
        defer self.allocator.free(encoded);
        profile.encode(encoded);

        var enc = try self.allocator.alloc(u8, pad.calcWithPkcsSize(16, encoded.len));
        pad.pkcsPad(16, enc, encoded);

        ecb.encryptEcb(enc, enc, key);

        return enc;
    }

    // given an encrypted, encoded profile, return the underlying user data
    pub fn parseProfile(self: *UserController, encrypted_profile: []const u8) !User {
        var encoded = try self.allocator.alloc(u8, encrypted_profile.len);
        defer self.allocator.free(encoded);
        ecb.decryptEcb(encoded, encrypted_profile, key);

        // remove padding in a silly kinda way
        var pad_len = encoded[encoded.len - 1];
        var unpadded = encoded[0 .. encoded.len - pad_len];
        var user = try User.fromString(self.allocator, unpadded);

        return user;
    }
};

pub fn createAdminProfile(allocator: *mem.Allocator, controller: *UserController) !User {
    comptime var padding = [_]u8{0x0B} ** 11;
    comptime var payload = "abcdefghij" ++ "Admin" ++ padding ++ "@xz";

    var enc_user = try controller.profileFor(payload);
    defer controller.allocator.free(enc_user);
    var admin_blk = enc_user[16..32];

    // admin user will be 1 block smaller than user profile
    var enc_admin = try allocator.alloc(u8, enc_user.len - 16);
    defer allocator.free(enc_admin);
    mem.copy(u8, enc_admin, enc_user[0..16]);
    mem.copy(u8, enc_admin[16..], enc_user[32..48]);
    mem.copy(u8, enc_admin[32..], admin_blk);

    var admin = try controller.parseProfile(enc_admin);

    return admin;
}

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
        .{ .input = "email=foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo@bar.com&uid=4294967295&role=User", .expected_err = error.ValueTooBig },
    };
    for (tests) |t| {
        if (User.fromString(testing.allocator, t.input)) |user| {
            assert(false); // should have been an error
        } else |err| {
            assert(err == t.expected_err);
        }
    }
}

test "profile from email" {
    var allocator = testing.allocator;
    var user = try User.profileFor(allocator, "asdf@fdsa.net");
    defer allocator.free(user.email);

    testing.expectEqualSlices(u8, user.email, "asdf@fdsa.net");
    assert(user.role == Role.User);

    // meta chars don't work
    var user2 = try User.profileFor(allocator, "asdf@fdsa.net&role=admin");
    defer allocator.free(user2.email);

    testing.expectEqualSlices(u8, user2.email, "asdf@fdsa.netroleadmin");
    assert(user2.role == Role.User);
}

test "user controller profile for" {
    var allocator = testing.allocator;
    var controller = try UserController.init(allocator);

    var enc_user = try controller.profileFor("asdf@fdsa.net");
    defer allocator.free(enc_user);
    std.debug.warn("\n{x}\n", .{enc_user});

    var dec_user = try controller.parseProfile(enc_user);
    defer allocator.free(dec_user.email);
    std.debug.warn("\n{}\n", .{dec_user});
}

test "create admin profile" {
    var allocator = testing.allocator;
    var controller = try UserController.init(allocator);

    var admin = try createAdminProfile(allocator, &controller);
    defer allocator.free(admin.email);
    assert(admin.role == Role.Admin);
}
