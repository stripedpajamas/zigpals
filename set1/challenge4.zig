const std = @import("std");
const challenge2 = @import("./challenge2.zig");
const challenge3 = @import("./challenge3.zig");
const LanguageScorer = challenge3.LanguageScorer;
const Language = challenge3.Language;
const singleByteXor = challenge2.singleByteXor;
const findSingleByteXorKey = challenge3.findSingleByteXorKey;
const math = std.math;
const testing = std.testing;
const fmt = std.fmt;
const mem = std.mem;
const ArrayList = std.ArrayList;

pub const DetectionResult = struct {
    enc: []u8,
    dec: []u8,
    key: u8
};

pub fn detectSingleByteXor(allocator: *mem.Allocator, challenge4_input_raw: []const u8) !DetectionResult {
    const scorer = LanguageScorer.init(testing.allocator, Language.English);

    var highScoreEnc = try allocator.alloc(u8, 0);
    var highScoreDec = try allocator.alloc(u8, 0);
    var highScoreKey: u8 = undefined;
    var highScore: f32 = math.f32_min;

    var input_it = mem.split(challenge4_input_raw, "\n");
    while (input_it.next()) |line| {
        const enc = try allocator.alloc(u8, line.len / 2);
        defer allocator.free(enc);
        try fmt.hexToBytes(enc, line);

        const key = try findSingleByteXorKey(allocator, Language.English, enc);
        const dec = try allocator.alloc(u8, enc.len);
        defer allocator.free(dec);
        try singleByteXor(dec, enc, key);

        const score = try scorer.score(dec);

        if (score > highScore) {
            highScore = score;
            highScoreKey = key;

            highScoreEnc = try allocator.realloc(highScoreEnc, enc.len);
            highScoreDec = try allocator.realloc(highScoreDec, dec.len);

            mem.copy(u8, highScoreEnc, enc);
            mem.copy(u8, highScoreDec, dec);
        }
    }

    return DetectionResult{
        .enc = highScoreEnc,
        .dec = highScoreDec,
        .key = highScoreKey,
    };
}

test "detect single byte xor" {
    // TODO switch this out for testing.allocator when that allocator isn't limited to 2mb
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const challenge4_input_raw = @embedFile("./data/challenge4_input.txt");
    
    const detectionResult = try detectSingleByteXor(&arena.allocator, challenge4_input_raw);

    std.debug.warn("\nenc: {}\ndec: {}\nkey: {}\n", .{
        detectionResult.enc,
        detectionResult.dec,
        detectionResult.key,
    });

    std.debug.assert(detectionResult.key == 53);
}