const std = @import("std");
const singleByteXor = @import("./challenge2.zig").singleByteXor;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
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
pub fn frequencyLookupTable(comptime byteFrequencies: var) [255]f32 {
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

pub const EnglishLetterFrequencies = frequencyLookupTable(.{
    .{ '.', 9.0000 }, // represents punctuation and digits
    .{ ' ', 19.180 },
    .{ 'a', 8.3400 },
    .{ 'b', 1.5400 },
    .{ 'c', 2.7300 },
    .{ 'd', 4.1400 },
    .{ 'e', 12.600 },
    .{ 'f', 2.0300 },
    .{ 'g', 1.9200 },
    .{ 'h', 6.1100 },
    .{ 'i', 6.7100 },
    .{ 'j', 0.2300 },
    .{ 'k', 0.8700 },
    .{ 'l', 4.2400 },
    .{ 'm', 2.5300 },
    .{ 'n', 6.8000 },
    .{ 'o', 7.7000 },
    .{ 'p', 1.6600 },
    .{ 'q', 0.0900 },
    .{ 'r', 5.6800 },
    .{ 's', 6.1100 },
    .{ 't', 9.3700 },
    .{ 'u', 2.8500 },
    .{ 'v', 1.0600 },
    .{ 'w', 2.3400 },
    .{ 'x', 0.2000 },
    .{ 'y', 2.0400 },
    .{ 'z', 0.0600 },
});

pub const LanguageScorer = struct {
    allocator: *Allocator,
    language: Language,

    letter_frequencies: AutoHashMap(u8, f32),
    text: []u8,

    pub fn init(allocator: *Allocator, language: Language) !LanguageScorer {
        var text = try allocator.alloc(u8, 32);
        errdefer allocator.free(text);

        var letter_frequencies = AutoHashMap(u8, f32).init(allocator);
        errdefer letter_frequencies.deinit();

        return LanguageScorer{
            .allocator = allocator,
            .language = language,
            .letter_frequencies = letter_frequencies,
            .text = text,
        };
    }

    pub fn deinit(self: *LanguageScorer) void {
        self.letter_frequencies.deinit();
        self.allocator.free(self.text);
    }

    pub fn score(self: *LanguageScorer, input: []const u8) !f32 {
        const text = try self.toLower(input);

        self.letter_frequencies.clear();
        var char_count: f32 = 0;
        for (text) |letter| {
            const freq_key = if (ascii.isPunct(letter) or ascii.isDigit(letter)) '.' else letter;
            if (ascii.isAlpha(freq_key) or freq_key == ' ' or freq_key == '.') {
                _ = try self.letter_frequencies.put(freq_key, 1.0 + (self.letter_frequencies.getValue(freq_key) orelse 0.0));
                char_count += 1;
            }
        }

        const freq_table = switch (self.language) {
            Language.English => EnglishLetterFrequencies,
        };

        var sum_of_squared_errors: f32 = 0;
        var byte: u8 = 0;
        while (byte < 255) : (byte += 1) {
            const actual_freq = (self.letter_frequencies.getValue(byte) orelse 0.0) / char_count * 100;
            const expected_freq = freq_table[byte];
            sum_of_squared_errors += math.pow(f32, expected_freq - actual_freq, 2);

            // penalty for absolutely nonsense
            if (!ascii.isPrint(byte) and actual_freq > 0) {
                sum_of_squared_errors += 255;
            }
        }

        return 100 - (sum_of_squared_errors / 255);
    }

    fn toLower(self: *LanguageScorer, input: []const u8) ![]u8 {
        if (self.text.len < input.len) {
            self.text = try self.allocator.realloc(self.text, input.len);
        }
        var text = self.text[0..input.len];
        for (text) |*c, i| {
            c.* = ascii.toLower(input[i]);
        }
        return text;
    }
};

pub const SingleByteXorKeyFinder = struct {
    allocator: *Allocator,
    language: Language,

    key_scores: AutoHashMap(u8, f32),
    scorer: LanguageScorer,
    dec: []u8,
    buf: []u8,

    pub fn init(allocator: *Allocator, language: Language) !SingleByteXorKeyFinder {
        var buf = try allocator.alloc(u8, 30);
        errdefer allocator.free(buf);

        var key_scores = AutoHashMap(u8, f32).init(allocator);
        errdefer key_scores.deinit();

        var scorer = try LanguageScorer.init(allocator, language);
        errdefer scorer.deinit();

        return SingleByteXorKeyFinder{
            .allocator = allocator,
            .language = language,
            .key_scores = key_scores,
            .scorer = scorer,
            .dec = buf[0..30],
            .buf = buf,
        };
    }

    pub fn deinit(self: *SingleByteXorKeyFinder) void {
        self.allocator.free(self.buf);
        self.key_scores.deinit();
        self.scorer.deinit();
    }

    pub fn findKey(self: *SingleByteXorKeyFinder, enc: []const u8) !u8 {
        if (self.dec.len < enc.len) {
            self.dec = try self.allocator.realloc(self.dec, enc.len);
        }
        var dec = self.dec[0..enc.len];

        var key: u8 = 0;
        while (key < 255) : (key += 1) {
            try singleByteXor(dec, enc, key);
            _ = try self.key_scores.put(key, try self.scorer.score(dec));
        }

        var high_score_key: u8 = 0;
        var high_score: f32 = -math.f32_max;
        var it = self.key_scores.iterator();
        while (it.next()) |entry| {
            if (entry.value > high_score) {
                high_score = entry.value;
                high_score_key = entry.key;
            }
        }

        return high_score_key;
    }
};

test "language scorer" {
    var scorer = try LanguageScorer.init(testing.allocator, Language.English);
    defer scorer.deinit();
    var score_eng = try scorer.score("you can get back to enjoying your new Hyundai");
    var score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("\nscore_eng: {} :: score_gib: {}", .{ score_eng, score_gib });
    assert(score_eng > score_gib);

    score_eng = try scorer.score("YOU CAN GET BACK TO ENJOYING YOUR NEW HYUNDAI");
    score_gib = try scorer.score("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    std.debug.warn("\nscore_eng: {} :: score_gib: {}", .{ score_eng, score_gib });
    assert(score_eng > score_gib);

    score_eng = try scorer.score(" olceiom c  ho nuce  st2sl  k,\notl'eol e rldtspas yaandnou rsogmctiy,aeo doo ct a k tf,fwoif  s aet");
    score_gib = try scorer.score("e*)& ,*(e&ee-*e+0& ee61w6)ee.iO*1)b *)e e7)!165$6e<$$+!+*0e76*\"(&1,<i$ *e!**e&1e$e.e1#i#2*,#ee6e$ 1");

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
