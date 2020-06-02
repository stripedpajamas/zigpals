const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const repeatedKeyXor = @import("./challenge5.zig").repeatedKeyXor;

const KeysizeCandidate = struct {
    keysize: usize,
    distance: f32,
};

fn smallerDistance(a: KeysizeCandidate, b: KeysizeCandidate) bool {
    return a.distance < b.distance;
}

pub const RepeatedKeyXorKeyFinder = struct {
    allocator: *mem.Allocator,

    candidates: std.PriorityQueue(KeysizeCandidate),

    pub fn init(allocator: *mem.Allocator) RepeatedKeyXorKeyFinder {
        var candidates = std.PriorityQueue(KeysizeCandidate).init(allocator, smallerDistance);

        return RepeatedKeyXorKeyFinder{
            .allocator = allocator,
            .candidates = candidates,
        };
    }

    pub fn deinit(self: *RepeatedKeyXorKeyFinder) void {
        self.candidates.deinit();
    }

    pub fn getKeysizeCandidates(self: *RepeatedKeyXorKeyFinder, input: []const u8) !std.PriorityQueue(KeysizeCandidate) {
        var max_key_size_candidate = input.len / 4;
        try self.candidates.ensureCapacity(max_key_size_candidate);

        var key_size_candidate: usize = 1;
        while (key_size_candidate <= max_key_size_candidate) : (key_size_candidate += 1) {
            const a = input[0..key_size_candidate];
            const b = input[key_size_candidate .. key_size_candidate * 2];
            const c = input[key_size_candidate * 2 .. key_size_candidate * 3];
            const d = input[key_size_candidate * 3 .. key_size_candidate * 4];
            const distance_ab = try computeHammingDistance(a, b);
            const distance_cd = try computeHammingDistance(c, d);
            const distance_avg = (distance_ab + distance_cd) / 2.0;
            const normalized_distance = distance_avg / @intToFloat(f32, key_size_candidate);
            try self.candidates.add(KeysizeCandidate{
                .keysize = key_size_candidate,
                .distance = normalized_distance,
            });
        }

        return self.candidates;
    }
};

pub fn computeHammingDistance(a: []const u8, b: []const u8) !f32 {
    assert(a.len == b.len);
    var distance: f32 = 0;
    for (a) |byte, idx| {
        distance += @intToFloat(f32, @popCount(u8, byte ^ b[idx]));
    }
    return distance;
}

test "hamming distance" {
    const hd = try computeHammingDistance("wokka wokka!!!", "this is a test");
    assert(hd == 37);
}

test "guess repeated-key xor key size" {
    var out = try testing.allocator.alloc(u8, 29);
    defer testing.allocator.free(out);
    try repeatedKeyXor(out, "hello world and goodbye world", "iceypop");

    var key_finder = RepeatedKeyXorKeyFinder.init(testing.allocator);
    defer key_finder.deinit();
    var candidates = try key_finder.getKeysizeCandidates(out);
    std.debug.warn("\n", .{});
    var seen: u8 = 1;
    var it = candidates.iterator();
    while (it.next()) |candidate| {
        std.debug.warn("keysize: {}, distance: {}\n", .{ candidate.keysize, candidate.distance });
        if (candidate.keysize == 7) {
            std.debug.warn("found correct keysize ranked {} with hamming distance {}\n", .{ seen, candidate.distance });
            break;
        }
        // assert that the correct answer is within the top 5 candidates
        assert(seen < 5);
        seen += 1;
    }
}
