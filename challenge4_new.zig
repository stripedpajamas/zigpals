const std = @import("std");
const challenge2 = @import("./challenge2.zig");
const challenge3 = @import("./challenge3_new.zig");
const findSingleByteKey = challenge3.findSingleByteKey;
const scoreSample = challenge3.scoreSample;
const singleByteXor = challenge2.singleByteXor;
const math = std.math;
const testing = std.testing;
const fmt = std.fmt;
const mem = std.mem;

pub const DetectionResult = struct { enc: []u8, key: u8 };

pub const SingleByteXorDetector = struct {
    allocator: *mem.Allocator,

    highScoreEnc: []u8,
    highScoreKey: u8,
    highScore: f32,

    pub fn init(allocator: *mem.Allocator) !SingleByteXorDetector {
        var buf = try allocator.alloc(u8, 30);
        errdefer allocator.free(buf);

        return SingleByteXorDetector{
            .allocator = allocator,
            .highScore = -math.f32_max,
            .highScoreKey = 0,
            .highScoreEnc = buf,
        };
    }

    pub fn deinit(self: *SingleByteXorDetector) void {
        self.allocator.free(self.highScoreEnc);
    }

    pub fn addSample(self: *SingleByteXorDetector, enc: []const u8) !void {
        const key = findSingleByteKey(enc);
        var dec: [30]u8 = undefined;
        singleByteXor(dec[0..enc.len], enc, key);

        const score = scoreSample(dec[0..enc.len]);

        if (score > self.highScore) {
            self.highScore = score;
            self.highScoreKey = key;

            mem.copy(u8, self.highScoreEnc, enc);
        }
    }

    pub fn getMostLikelySample(self: *SingleByteXorDetector) DetectionResult {
        return DetectionResult{
            .enc = self.highScoreEnc,
            .key = self.highScoreKey,
        };
    }
};

test "detect single byte xor" {
    var allocator = testing.allocator;

    const challenge4_input_raw = @embedFile("./data/challenge4_input.txt");

    var beginTs = std.time.milliTimestamp();

    var detector = try SingleByteXorDetector.init(allocator);
    defer detector.deinit();

    var enc: [30]u8 = undefined;
    var input_it = mem.split(challenge4_input_raw, "\n");
    while (input_it.next()) |line| {
        var line_size = line.len / 2;
        _ = try fmt.hexToBytes(enc[0..line_size], line);
        try detector.addSample(enc[0..line_size]);
    }

    const detectionResult = detector.getMostLikelySample();
    std.log.warn("\n\ncompleted in {}ms\n", .{std.time.milliTimestamp() - beginTs});

    singleByteXor(enc[0..], detectionResult.enc, detectionResult.key);
    std.log.warn("\nenc: {x}\ndec: {s}\nkey: {}\n", .{
        fmt.fmtSliceHexLower(detectionResult.enc),
        enc,
        detectionResult.key,
    });

    std.debug.assert(detectionResult.key == 53);
}
