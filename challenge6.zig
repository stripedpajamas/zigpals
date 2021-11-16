const std = @import("std");
const challenge3 = @import("./challenge3.zig");
const repeatedKeyXor = @import("./challenge5.zig").repeatedKeyXor;
const base64 = std.base64;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const SingleByteXorKeyFinder = challenge3.SingleByteXorKeyFinder;
const LanguageScorer = challenge3.LanguageScorer;
const Language = challenge3.Language;

const KeysizeCandidate = struct {
    keysize: usize,
    distance: f32,
};

const KeyCandidate = struct {
    key: []u8,
    score: f32,
};

fn smallerDistance(a: KeysizeCandidate, b: KeysizeCandidate) math.Order {
    return math.order(a.distance, b.distance);
}

pub const RepeatedKeyXorKeyFinder = struct {
    allocator: *mem.Allocator,
    sk_key_finder: SingleByteXorKeyFinder,
    scorer: LanguageScorer,
    candidates: std.PriorityQueue(KeysizeCandidate),

    pub fn init(allocator: *mem.Allocator, language: Language) !RepeatedKeyXorKeyFinder {
        var candidates = std.PriorityQueue(KeysizeCandidate).init(allocator, smallerDistance);
        var sk_key_finder = try SingleByteXorKeyFinder.init(allocator, language);
        var scorer = try LanguageScorer.init(allocator, language);

        return RepeatedKeyXorKeyFinder{
            .allocator = allocator,
            .sk_key_finder = sk_key_finder,
            .scorer = scorer,
            .candidates = candidates,
        };
    }

    pub fn deinit(self: *RepeatedKeyXorKeyFinder) void {
        self.candidates.deinit();
        self.sk_key_finder.deinit();
        self.scorer.deinit();
    }

    pub fn findKey(self: *RepeatedKeyXorKeyFinder, input: []const u8) ![]u8 {
        var key = try self.allocator.alloc(u8, 8);
        errdefer self.allocator.free(key);

        var candidates = try self.getKeysizeCandidates(input);
        var it = candidates.iterator();

        var high_score_keysize: usize = 0;
        var high_score: f32 = -math.f32_max;
        var count: usize = 0;
        while (it.next()) |key_size_candidate| {
            var key_candidate = try self.evaluateKeysize(input, key_size_candidate.keysize);
            defer self.allocator.free(key_candidate.key);

            if (key_candidate.score > high_score) {
                high_score = key_candidate.score;
                high_score_keysize = key_size_candidate.keysize;
                if (key_candidate.key.len > key.len) {
                    key = try self.allocator.realloc(key, key_candidate.key.len);
                }
                mem.copy(u8, key, key_candidate.key);
            }

            count += 1;
            if (count >= 3) break;
        }

        return key[0..high_score_keysize];
    }

    pub fn evaluateKeysize(self: *RepeatedKeyXorKeyFinder, input: []const u8, keysize: usize) !KeyCandidate {
        var key = try self.allocator.alloc(u8, keysize);
        errdefer self.allocator.free(key);
        var buf = try self.allocator.alloc(u8, input.len);
        defer self.allocator.free(buf);

        for (key) |*k, key_idx| {
            var buf_idx: usize = 0;
            var in_idx: usize = key_idx;
            while (in_idx < input.len) : (in_idx += keysize) {
                buf[buf_idx] = input[in_idx];
                buf_idx += 1;
            }
            k.* = try self.sk_key_finder.findKey(buf[0..buf_idx]);
        }

        repeatedKeyXor(buf, input, key);
        var score = try self.scorer.score(buf);

        return KeyCandidate{
            .key = key,
            .score = score,
        };
    }

    pub fn getKeysizeCandidates(self: *RepeatedKeyXorKeyFinder, input: []const u8) !std.PriorityQueue(KeysizeCandidate) {
        var max_key_size_candidate = math.min(input.len / 4, 40);
        try self.candidates.ensureCapacity(max_key_size_candidate);

        var key_size_candidate: usize = 1;
        while (key_size_candidate <= max_key_size_candidate) : (key_size_candidate += 1) {
            const a = input[0..key_size_candidate];
            const b = input[key_size_candidate .. key_size_candidate * 2];
            const c = input[key_size_candidate * 2 .. key_size_candidate * 3];
            const d = input[key_size_candidate * 3 .. key_size_candidate * 4];
            const distance_ab = computeHammingDistance(a, b);
            const distance_bc = computeHammingDistance(b, c);
            const distance_cd = computeHammingDistance(c, d);
            const distance_da = computeHammingDistance(d, a);
            const distance_avg = (distance_ab + distance_bc + distance_cd + distance_da) / 4.0;
            const normalized_distance = distance_avg / @intToFloat(f32, key_size_candidate);
            try self.candidates.add(KeysizeCandidate{
                .keysize = key_size_candidate,
                .distance = normalized_distance,
            });
        }

        return self.candidates;
    }
};

pub fn computeHammingDistance(a: []const u8, b: []const u8) f32 {
    assert(a.len == b.len);
    var distance: f32 = 0;
    for (a) |byte, idx| {
        distance += @intToFloat(f32, @popCount(u8, byte ^ b[idx]));
    }
    return distance;
}

test "hamming distance" {
    const hd = computeHammingDistance("wokka wokka!!!", "this is a test");
    assert(hd == 37);
}

test "guess repeated-key xor key size" {
    const input = "hello world and goodbye world";
    var enc: [input.len]u8 = undefined;
    repeatedKeyXor(enc[0..], input, "iceypop");

    var key_finder = try RepeatedKeyXorKeyFinder.init(testing.allocator, Language.English);
    defer key_finder.deinit();

    var candidates = try key_finder.getKeysizeCandidates(enc[0..]);

    var seen: u8 = 0;
    var it = candidates.iterator();
    while (it.next()) |candidate| {
        seen += 1;
        std.debug.warn("\nkeysize: {}, distance: {d}", .{ candidate.keysize, candidate.distance });
        if (candidate.keysize == 7) {
            std.debug.warn("\nfound correct keysize ranked {} with hamming distance {d}\n", .{ seen, candidate.distance });
            break;
        }
        // assert that the correct answer is within the top 5 candidates
        assert(seen < 5);
    }
}

test "break repeating-key xor" {
    var allocator = testing.allocator;

    const challenge7_input_raw = @embedFile("./data/challenge6_input.txt");
    var decoder = base64.standard.decoderWithIgnore("\n");
    var input_bytes: [try base64.standard.Decoder.calcSizeUpperBound(challenge7_input_raw.len)]u8 = undefined;
    var written = try decoder.decode(input_bytes[0..], challenge7_input_raw);
    var input = input_bytes[0..written];

    var key_finder = try RepeatedKeyXorKeyFinder.init(allocator, Language.English);
    defer key_finder.deinit();

    var key = try key_finder.findKey(input);
    defer allocator.free(key);

    try testing.expectEqualSlices(u8, key, "Terminator X: Bring the noise");

    std.debug.warn("\nfound this key: {s}", .{key});

    repeatedKeyXor(input, input, key);
    std.debug.warn("\nfound this plaintext:\n{s}\n", .{input});
}
