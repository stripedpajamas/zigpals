const std = @import("std");
const singleByteXor = @import("./challenge2.zig").singleByteXor;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const HashMap = std.HashMap;
const fmt = std.fmt;
const ascii = std.ascii;
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;

pub const Language = enum {
    English
};

// a comptime lookup table of u8 -> f32
// this is mostly a convenience since its known that all the keys will be unique
// any bytes that aren't specified in the input are considered to occur 0% in normal text
pub fn FrequencyLookupTable(comptime byteFrequencies: var) [255]f32 {
    var entries = [1]f32{0.0} ** 255;
    for (byteFrequencies) |kv| {
        var byte: u8 = kv[0];
        var freq: f32 = kv[1];

        const idx = @as(usize, byte);
        const entry = &entries[idx];
        entry.* = freq;
    }
    return entries;
}

pub const EnglishLetterFrequencies = FrequencyLookupTable(.{
    .{ ' ', 0.1918 },
    .{ 'a', 0.0834 },
    .{ 'b', 0.0154 },
    .{ 'c', 0.0273 },
    .{ 'd', 0.0414 },
    .{ 'e', 0.1260 },
    .{ 'f', 0.0203 },
    .{ 'g', 0.0192 },
    .{ 'h', 0.0611 },
    .{ 'i', 0.0671 },
    .{ 'j', 0.0023 },
    .{ 'k', 0.0087 },
    .{ 'l', 0.0424 },
    .{ 'm', 0.0253 },
    .{ 'n', 0.0680 },
    .{ 'o', 0.0770 },
    .{ 'p', 0.0166 },
    .{ 'q', 0.0009 },
    .{ 'r', 0.0568 },
    .{ 's', 0.0611 },
    .{ 't', 0.0937 },
    .{ 'u', 0.0285 },
    .{ 'v', 0.0106 },
    .{ 'w', 0.0234 },
    .{ 'x', 0.0020 },
    .{ 'y', 0.0204 },
    .{ 'z', 0.0006 },
});

pub const LanguageScorer = struct {
    allocator: *Allocator,
    language: Language,

    pub fn init(allocator: *Allocator, language: Language) LanguageScorer {
        return LanguageScorer{
            .allocator = allocator,
            .language = language,
        };
    }

    pub fn score(self: *const LanguageScorer, input: []const u8) !f32 {
        const text = try ascii.allocLowerString(self.allocator, input);
        defer self.allocator.free(text);

        var letterFrequencies = AutoHashMap(u8, f32).init(self.allocator);
        defer letterFrequencies.deinit();

        for (text) |letter| {
            _ = try letterFrequencies.put(letter, 1.0 + (letterFrequencies.getValue(letter) orelse 0.0));
        }

        const text_len = @intToFloat(f32, text.len);

        const freq_table = switch (self.language) {
            Language.English => EnglishLetterFrequencies,
        };

        var _score: f32 = 1.0;
        var ltr: u8 = 0;
        while (ltr < 255) : (ltr += 1) {
            const actual_freq = (letterFrequencies.getValue(ltr) orelse 0.0) / text_len;
            const expected_freq = freq_table[ltr];
            const diff = math.absFloat(expected_freq - actual_freq);
            _score -= diff;
        }

        return _score;
    }
};

pub const SingleByteXorKeyFinder = struct {
    allocator: *Allocator,
    language: Language,

    keyScores: AutoHashMap(u8, f32),
    scorer: LanguageScorer,
    dec: []u8,
    buf: []u8,

    pub fn init(allocator: *Allocator, language: Language) !SingleByteXorKeyFinder {
        var buf = try allocator.alloc(u8, 30);
        return SingleByteXorKeyFinder{
            .allocator = allocator,
            .language = language,
            .keyScores = AutoHashMap(u8, f32).init(allocator),
            .scorer = LanguageScorer.init(allocator, language),
            .dec = buf[0..30],
            .buf = buf,
        };
    }

    pub fn deinit(self: *SingleByteXorKeyFinder) void {
        self.allocator.free(self.buf);
        self.keyScores.deinit();
    }

    pub fn findKey(self: *SingleByteXorKeyFinder, enc: []const u8) !u8 {
        if (self.dec.len < enc.len) {
            self.dec = try self.allocator.realloc(self.dec, enc.len);
        }
        var dec = self.dec[0..enc.len];

        var key: u8 = 0;
        while (key < 255) : (key += 1) {
            try singleByteXor(dec, enc, key);
            _ = try self.keyScores.put(key, try self.scorer.score(dec));
        }

        var highScoreKey: u8 = 0;
        var highScore: f32 = math.f32_min;
        var it = self.keyScores.iterator();
        while (it.next()) |entry| {
            if (entry.value > highScore) {
                highScore = entry.value;
                highScoreKey = entry.key;
            }
        }

        return highScoreKey;
    }
};

test "language scorer" {
    const scorer = LanguageScorer.init(testing.allocator, Language.English);
    var score_eng = try scorer.score("you can get back to enjoying your new Hyundai");
    var score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("\nscore_eng: {} :: score_gib: {}", .{ score_eng, score_gib });
    assert(score_eng > score_gib);

    score_eng = try scorer.score("YOU CAN GET BACK TO ENJOYING YOUR NEW HYUNDAI");
    score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("\nscore_eng: {} :: score_gib: {}\n", .{ score_eng, score_gib });
    assert(score_eng > score_gib);
}

test "find single byte xor key" {
    var enc = try testing.allocator.alloc(u8, 34);
    defer testing.allocator.free(enc);
    try fmt.hexToBytes(enc, "1b37373331363f78151b7f2b783431333d78397828372d363c78373e783a393b3736");

    var key_finder = try SingleByteXorKeyFinder.init(testing.allocator, Language.English);
    defer key_finder.deinit();
    const key = try key_finder.findKey(enc);

    var dec = try testing.allocator.alloc(u8, 34);
    defer testing.allocator.free(dec);
    try singleByteXor(dec, enc, key);
    std.debug.warn("\ndetermined key to be: {}\ndecrypted: {}\n\n", .{ key, dec });

    assert(key == 88);
}
