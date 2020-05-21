const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const HashMap = std.HashMap;
const ascii = std.ascii;
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;

// a comptime lookup table of u8 -> f32
// this is mostly a convenience since its known that all the keys will be unique
pub fn FrequencyLookupTable(comptime values: var) type {
    const size = 255;
    const Entry = struct {
        key: u8, val: f32
    };
    const empty = Entry{
        .key = undefined,
        .val = undefined,
    };
    var slots = [1]Entry{empty} ** size;

    for (values) |kv| {
        var key: u8 = kv[0];
        var val: f32 = kv[1];

        const idx = @as(usize, key);
        const entry = &slots[idx];
        entry.* = .{
            .key = key,
            .val = val,
        };
    }

    return struct {
        const entries = slots;

        pub fn get(letter: u8) f32 {
            const idx = @as(usize, letter);
            const entry = &entries[idx];
            if (entry.key != letter) {
                return 0.0;
            }
            return entry.val;
        }
    };
}

pub const Language = enum {
    English
};

pub const EnglishLetterFrequencies = FrequencyLookupTable(.{
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
            var old_freq = try letterFrequencies.put(letter, 1.0 + (letterFrequencies.getValue(letter) orelse 0.0));
        }

        const text_len = @intToFloat(f32, text.len);

        var _score: f32 = 1.0;
        var ltr: u8 = 0;
        while (ltr < 255) {
            const actual_freq = (letterFrequencies.getValue(ltr) orelse 0.0) / text_len;
            const expected_freq = EnglishLetterFrequencies.get(ltr);
            const diff = math.absFloat(expected_freq - actual_freq);
            _score -= diff;
            ltr += 1;
        }

        return _score;
    }
};

test "language scorer" {
    const scorer = LanguageScorer.init(testing.allocator, Language.English);
    var score_eng = try scorer.score("you can get back to enjoying your new Hyundai");
    var score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("score_eng: {} :: score_gib: {}\n\n", .{ score_eng, score_gib });
    assert(score_eng > score_gib);

    score_eng = try scorer.score("YOU CAN GET BACK TO ENJOYING YOUR NEW HYUNDAI");
    score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("score_eng: {} :: score_gib: {}\n\n", .{ score_eng, score_gib });
    assert(score_eng > score_gib);
}
