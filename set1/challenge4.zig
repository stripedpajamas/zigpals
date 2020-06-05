const std = @import("std");
const challenge2 = @import("./challenge2.zig");
const challenge3 = @import("./challenge3.zig");
const SingleByteXorKeyFinder = challenge3.SingleByteXorKeyFinder;
const LanguageScorer = challenge3.LanguageScorer;
const Language = challenge3.Language;
const singleByteXor = challenge2.singleByteXor;
const math = std.math;
const testing = std.testing;
const fmt = std.fmt;
const mem = std.mem;

pub const DetectionResult = struct {
    enc: []u8, dec: []u8, key: u8
};

pub const SingleByteXorDetector = struct {
    allocator: *mem.Allocator,
    scorer: LanguageScorer,
    key_finder: SingleByteXorKeyFinder,
    language: Language,

    highScoreEnc: []u8,
    highScoreDec: []u8,
    highScoreKey: u8,
    highScore: f32,

    dec: []u8,
    buf: []u8,

    pub fn init(allocator: *mem.Allocator, language: Language) !SingleByteXorDetector {
        var buf = try allocator.alloc(u8, 90);
        errdefer allocator.free(buf);

        var key_finder = try SingleByteXorKeyFinder.init(allocator, Language.English);
        var scorer = try LanguageScorer.init(allocator, language);

        return SingleByteXorDetector{
            .allocator = allocator,
            .language = language,
            .scorer = scorer,
            .key_finder = key_finder,
            .highScore = math.f32_min,
            .highScoreKey = 0,
            .highScoreDec = buf[0..30],
            .highScoreEnc = buf[30..60],
            .dec = buf[60..90],
            .buf = buf,
        };
    }

    pub fn deinit(self: *SingleByteXorDetector) void {
        self.allocator.free(self.buf);
        self.key_finder.deinit();
        self.scorer.deinit();
    }

    pub fn addSample(self: *SingleByteXorDetector, enc: []const u8) !void {
        const key = try self.key_finder.findKey(enc);
        var dec = self.dec[0..enc.len];
        try singleByteXor(dec, enc, key);

        const score = try self.scorer.score(dec);

        if (score > self.highScore) {
            self.highScore = score;
            self.highScoreKey = key;

            if (enc.len > self.highScoreEnc.len) {
                self.highScoreEnc = try self.allocator.realloc(self.highScoreEnc, enc.len);
            }
            if (self.dec.len > self.highScoreDec.len) {
                self.highScoreDec = try self.allocator.realloc(self.highScoreDec, dec.len);
            }

            mem.copy(u8, self.highScoreEnc, enc);
            mem.copy(u8, self.highScoreDec, dec);
        }
    }

    pub fn getMostLikelySample(self: *SingleByteXorDetector) DetectionResult {
        return DetectionResult{
            .enc = self.highScoreEnc,
            .dec = self.highScoreDec,
            .key = self.highScoreKey,
        };
    }
};

test "detect single byte xor" {
    var allocator = testing.allocator;

    const challenge4_input_raw = @embedFile("./data/challenge4_input.txt");

    var beginTs = std.time.milliTimestamp();

    var detector = try SingleByteXorDetector.init(allocator, Language.English);
    defer detector.deinit();

    var enc = try allocator.alloc(u8, 30);
    var input_it = mem.split(challenge4_input_raw, "\n");
    while (input_it.next()) |line| {
        var line_size = line.len / 2;
        if (line_size > enc.len) {
            enc = try allocator.realloc(enc, line_size);
        }
        try fmt.hexToBytes(enc[0..line_size], line);
        try detector.addSample(enc[0..line_size]);
    }
    allocator.free(enc);

    const detectionResult = detector.getMostLikelySample();
    std.debug.warn("\n\ncompleted in {}ms\n", .{std.time.milliTimestamp() - beginTs});

    std.debug.warn("\nenc: {x}\ndec: {}\nkey: {}\n", .{
        detectionResult.enc,
        detectionResult.dec,
        detectionResult.key,
    });

    std.debug.assert(detectionResult.key == 53);
}
