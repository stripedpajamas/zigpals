const std = @import("std");
const ecb = @import("./challenge7.zig");
const pad = @import("./challenge9.zig");
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const crypto = std.crypto;
const mem = std.mem;
const testing = std.testing;

pub fn EncryptionOracle(comptime keysize: usize) type {
    return struct {
        const Self = @This();
        const secret_suffix = [_]u8{ 0x52, 0x6f, 0x6c, 0x6c, 0x69, 0x6e, 0x27, 0x20, 0x69, 0x6e, 0x20, 0x6d, 0x79, 0x20, 0x35, 0x2e, 0x30, 0x0a, 0x57, 0x69, 0x74, 0x68, 0x20, 0x6d, 0x79, 0x20, 0x72, 0x61, 0x67, 0x2d, 0x74, 0x6f, 0x70, 0x20, 0x64, 0x6f, 0x77, 0x6e, 0x20, 0x73, 0x6f, 0x20, 0x6d, 0x79, 0x20, 0x68, 0x61, 0x69, 0x72, 0x20, 0x63, 0x61, 0x6e, 0x20, 0x62, 0x6c, 0x6f, 0x77, 0x0a, 0x54, 0x68, 0x65, 0x20, 0x67, 0x69, 0x72, 0x6c, 0x69, 0x65, 0x73, 0x20, 0x6f, 0x6e, 0x20, 0x73, 0x74, 0x61, 0x6e, 0x64, 0x62, 0x79, 0x20, 0x77, 0x61, 0x76, 0x69, 0x6e, 0x67, 0x20, 0x6a, 0x75, 0x73, 0x74, 0x20, 0x74, 0x6f, 0x20, 0x73, 0x61, 0x79, 0x20, 0x68, 0x69, 0x0a, 0x44, 0x69, 0x64, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x73, 0x74, 0x6f, 0x70, 0x3f, 0x20, 0x4e, 0x6f, 0x2c, 0x20, 0x49, 0x20, 0x6a, 0x75, 0x73, 0x74, 0x20, 0x64, 0x72, 0x6f, 0x76, 0x65, 0x20, 0x62, 0x79, 0x0a };

        var key: [keysize / 8]u8 = undefined;

        allocator: *mem.Allocator,

        pub fn init(allocator: *mem.Allocator) !Self {
            var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
            try crypto.randomBytes(seed[0..]);

            var rng = std.rand.DefaultCsprng.init(seed);

            rng.random.bytes(key[0..]);

            return Self{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {}

        pub fn calcSize(self: *const Self, plaintext_len: usize) usize {
            return pad.calcWithPkcsSize(keysize / 8, secret_suffix.len + plaintext_len);
        }

        pub fn encrypt(self: *const Self, dest: []u8, plaintext: []const u8) void {
            assert(dest.len >= self.calcSize(plaintext.len));

            // create (plaintext || suffix)
            mem.copy(u8, dest, plaintext);
            mem.copy(u8, dest[plaintext.len..], secret_suffix[0..]);

            pad.pkcsPad(keysize / 8, dest, dest[0 .. secret_suffix.len + plaintext.len]);

            // encrypt on top of plaintext || secret
            ecb.encryptEcb(dest, dest, key);
        }

        pub fn encryptAlloc(self: *const Self, plaintext: []const u8) ![]u8 {
            var dest = try self.allocator.alloc(u8, self.calcSize(plaintext.len));

            self.encrypt(dest, plaintext);

            return dest;
        }

        // for testing; return whether or not the secret has been found
        pub fn verify(self: *const Self, secret: []const u8) bool {
            if (mem.indexOf(u8, secret, secret_suffix[0..])) |idx| {
                return true;
            }
            return false;
        }
    };
}

pub fn discoverBlockSize(comptime keysize: usize, oracle: EncryptionOracle(keysize)) u32 {
    // detect block size
    // 1. begin with input of size 1 (smallest) and make note of size
    // 2. grow input until size changes; make note of new size
    // 3. block size == size(2) - size(1)

    // get initial size of encryption
    var initial_size = oracle.calcSize(1);

    var size: usize = 1;
    while (oracle.calcSize(size) == initial_size) : (size += 1) {}

    return @truncate(u32, oracle.calcSize(size) - initial_size);
}

pub fn isOracleECB(comptime keysize: usize, allocator: *mem.Allocator, blocksize: u32, oracle: EncryptionOracle(keysize)) !bool {
    var payload = try allocator.alloc(u8, oracle.calcSize(3 * blocksize));
    defer allocator.free(payload);

    for (payload) |*byte| {
        byte.* = 'A';
    }

    // overwrite payload with its encryption
    var enc = payload;
    oracle.encrypt(enc, payload[0 .. 3 * blocksize]);

    // look for dupe blocks
    var seen_blocks = StringHashMap(void).init(allocator);
    defer seen_blocks.deinit();

    var blk_idx: usize = 0;
    while (blk_idx < enc.len) : (blk_idx += blocksize) {
        var blk = enc[blk_idx .. blk_idx + blocksize];
        if (seen_blocks.contains(blk)) return true;
        _ = try seen_blocks.put(blk, {});
    }

    return false;
}

pub fn discoverSecretSuffix(comptime keysize: usize, allocator: *mem.Allocator, oracle: EncryptionOracle(keysize)) ![]u8 {
    const blocksize = discoverBlockSize(keysize, oracle);
    const isECB = try isOracleECB(keysize, allocator, blocksize, oracle);
    assert(isECB);

    var padded_secret_len = oracle.calcSize(0);
    var secret = try ArrayList(u8).initCapacity(allocator, padded_secret_len);

    // make a big buffer than can hold everything we will ever need
    var enc_buf = try allocator.alloc(u8, oracle.calcSize(padded_secret_len));
    defer allocator.free(enc_buf);

    var buf = try allocator.alloc(u8, padded_secret_len);
    defer allocator.free(buf);

    var block: usize = 0;
    while (block < padded_secret_len / blocksize) : (block += 1) {
        var offset: usize = 0;
        while (offset < blocksize) : (offset += 1) {
            var payload = buf[0 .. (block + 1) * blocksize];

            // set payload to all (A's || discovered-so-far)
            var idx: usize = 0;
            while (idx < payload.len - secret.items.len) : (idx += 1) {
                payload[idx] = 'A';
            }
            mem.copy(u8, payload[payload.len - secret.items.len - 1 ..], secret.items);

            // fill dictionary with the encryption of [AAAAA..<discovered secret><b>] => b
            var dict = StringHashMap(u8).init(allocator);
            defer {
                freeDictionary(allocator, dict);
                dict.deinit();
            }
            try dict.ensureCapacity(256);

            var b: u8 = 0;
            while (b <= 255) : (b += 1) {
                payload[payload.len - 1] = b;
                var enc = enc_buf[0..oracle.calcSize(payload.len)];
                oracle.encrypt(enc, payload);

                // remember just the relevant block
                var blk = try mem.dupe(allocator, u8, enc[block * blocksize .. (block + 1) * blocksize]);
                _ = try dict.put(blk, b);

                if (b == 255) break;
            }

            // encrypt [AAAAA..], leaving last byte open for unknown letter
            var enc_payload = payload[0 .. payload.len - secret.items.len - 1];
            var enc = enc_buf[0..oracle.calcSize(enc_payload.len)];
            oracle.encrypt(enc, enc_payload);

            var blk = enc[block * blocksize .. (block + 1) * blocksize];

            var match = dict.get(blk) orelse break;
            try secret.append(match);
        }
    }

    return secret.toOwnedSlice();
}

fn freeDictionary(allocator: *mem.Allocator, dict: StringHashMap(u8)) void {
    var it = dict.iterator();
    while (it.next()) |kv| {
        allocator.free(kv.key);
    }
}

test "byte-at-a-time ecb decryption (simple)" {
    const allocator = testing.allocator;
    const keysize: usize = 128;
    var oracle = try EncryptionOracle(keysize).init(allocator);
    defer oracle.deinit();

    var secret = try discoverSecretSuffix(keysize, allocator, oracle);
    defer allocator.free(secret);

    assert(oracle.verify(secret));
}
