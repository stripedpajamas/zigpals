const std = @import("std");
const singleByteXor = @import("./challenge2.zig").singleByteXor;
const ascii = std.ascii;
const math = std.math;
const testing = std.testing;
const log = std.log;
const assert = std.debug.assert;

const english_letter_frequencies = [_]f32{
    8.3400, // a
    1.5400, // b
    2.7300, // c
    4.1400, // d
    12.600, // e
    2.0300, // f
    1.9200, // g
    6.1100, // h
    6.7100, // i
    0.2300, // j
    0.8700, // k
    4.2400, // l
    2.5300, // m
    6.8000, // n
    7.7000, // o
    1.6600, // p
    0.0900, // q
    5.6800, // r
    6.1100, // s
    9.3700, // t
    2.8500, // u
    1.0600, // v
    2.3400, // w
    0.2000, // x
    2.0400, // y
    0.0600, // z

    9.0000, // placeholder for punctuation and digits
    19.180, // <space>
    0.0000, // placeholder for everything else
};

const LOWERCASE_A: usize = 97;
const PUNC_OR_DIGIT_IDX: usize = 26;
const SPACE_IDX: usize = 27;
const GARBAGE_IDX: usize = 28;

// takes a char (u8) and returns the appropriate idx into the frequency table
// for punctuation and digits, it uses idx 26 from the table
// for spaces, it uses idx 27 from the table
// for lowercase alpha letters, it subtracts 97 (a == 0)
// for uppercase letters, it gets the corresponding lowercase value
// for anything else, it uses idx 28 from the table (garbage chars)
fn getLetterIdx(ltr: u8) usize {
    if (ascii.isPunct(ltr) or ascii.isDigit(ltr)) return PUNC_OR_DIGIT_IDX;
    if (ltr == ' ') return SPACE_IDX;
    if (ascii.isLower(ltr)) return @as(usize, ltr) - LOWERCASE_A;
    if (ascii.isUpper(ltr)) return @as(usize, ascii.toLower(ltr)) - LOWERCASE_A;
    return GARBAGE_IDX;
}

fn computeDeviation(letter_counts: []f32, sample_len: f32) f32 {
    assert(letter_counts.len == english_letter_frequencies.len);

    var sum_of_squared_errors: f32 = 0.0;
    var ltr: usize = 0;
    while (ltr < english_letter_frequencies.len) : (ltr += 1) {
        const actual_freq = ((letter_counts[ltr] / sample_len) * 100);
        const expected_freq = english_letter_frequencies[ltr];
        sum_of_squared_errors += math.pow(f32, expected_freq - actual_freq, 2);

        // OPTIONAL -- penalty for garbage? if we need it, we can raise the error
        // to a higher power than 2 in the case that ltr == GARBAGE_IDX.
    }

    return -sum_of_squared_errors;
}

// higher score == sample seems more englishy
// score == 0 means the sample letter distribution was identical to our known english distribution
pub fn scoreSample(sample: []const u8) f32 {
    var letter_counts = [1]f32{0.0} ** 29;
    var total_chars_in_sample: f32 = 0.0;
    for (sample) |letter| {
        const ltr_idx = getLetterIdx(letter);
        letter_counts[ltr_idx] += 1.0;
        total_chars_in_sample += 1.0;
    }

    return computeDeviation(letter_counts[0..], total_chars_in_sample);
}

fn printLetterCounts(letter_counts: []f32) void {
    log.warn("letter counts:", .{});
    for (letter_counts) |count, idx| {
        var ltr = @truncate(u8, idx);
        if (idx == GARBAGE_IDX) {
            log.warn("  <garbage>: {d}", .{count});
        } else if (idx == SPACE_IDX) {
            log.warn("  <space>: {d}", .{count});
        } else if (idx == PUNC_OR_DIGIT_IDX) {
            log.warn("  <punc>: {d}", .{count});
        } else {
            log.warn("  {c}: {d}", .{ ltr + 97, count });
        }
    }
}

// returns key that produces most englishy sample after decrypting
// this fn re-implements scoreSample but splits things up to avoid allocations
pub fn findSingleByteKey(enc: []const u8) u8 {
    var buf: [16]u8 = undefined;
    var key_scores = [1]f32{-math.f32_max} ** 256;

    var key: u8 = 0;
    while (true) : (key += 1) {
        var enc_idx: usize = 0;
        var letter_counts = [1]f32{0.0} ** 29;
        var total_chars_in_enc: f32 = 0.0;

        while (enc_idx < enc.len) : (enc_idx += buf.len) {
            // decrypt buf_len bytes of enc into buf
            var enc_size = if (enc.len - enc_idx < buf.len) enc.len - enc_idx else buf.len;
            singleByteXor(buf[0..enc_size], enc[enc_idx .. enc_idx + enc_size], key);

            for (buf[0..enc_size]) |letter| {
                const ltr_idx = getLetterIdx(letter);
                letter_counts[ltr_idx] += 1.0;
                total_chars_in_enc += 1.0;
            }
        }

        key_scores[@as(usize, key)] = computeDeviation(letter_counts[0..], total_chars_in_enc);

        if (key == 255) break;
    }

    var high_score_key: u8 = 0;
    var high_score: f32 = -math.f32_max;

    for (key_scores) |score, key_idx| {
        if (score > high_score) {
            high_score = score;
            high_score_key = @truncate(u8, key_idx);
        }
    }

    return high_score_key;
}

test "language scorer" {
    var score_eng = scoreSample("you can get back to enjoying your new Hyundai");
    var score_gib = scoreSample("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    log.warn("1. score_eng: {d} :: score_gib: {d}", .{ score_eng, score_gib });
    assert(score_eng > score_gib); // 1

    score_eng = scoreSample("YOU CAN GET BACK TO ENJOYING YOUR NEW HYUNDAI");
    score_gib = scoreSample("asjf jas jasldfj alskf alsdfj skfj lasfj alff");

    log.warn("2. score_eng: {d} :: score_gib: {d}", .{ score_eng, score_gib });
    assert(score_eng > score_gib); // 2

    score_eng = scoreSample(" olceiom c  ho nuce  st2sl  k,\notl'eol e rldtspas yaandnou rsogmctiy,aeo doo ct a k tf,fwoif  s aet");
    score_gib = scoreSample("e*)& ,*(e&ee-*e+0& ee61w6)ee.iO*1)b *)e e7)!165$6e<$$+!+*0e76*\"(&1,<i$ *e!**e&1e$e.e1#i#2*,#ee6e$ 1");

    log.warn("3. score_eng: {d} :: score_gib: {d}\n", .{ score_eng, score_gib });
    assert(score_eng > score_gib); // 3
}

test "find single byte xor key" {
    var enc = [_]u8{ 0x1b, 0x37, 0x37, 0x33, 0x31, 0x36, 0x3f, 0x78, 0x15, 0x1b, 0x7f, 0x2b, 0x78, 0x34, 0x31, 0x33, 0x3d, 0x78, 0x39, 0x78, 0x28, 0x37, 0x2d, 0x36, 0x3c, 0x78, 0x37, 0x3e, 0x78, 0x3a, 0x39, 0x3b, 0x37, 0x36 };

    const key = findSingleByteKey(enc[0..]);

    var dec: [enc.len]u8 = undefined;
    singleByteXor(dec[0..], enc[0..], key);
    log.warn("determined key to be: {d} ({x})", .{ key, key });
    log.warn("decrypted: {s}", .{dec});

    // histogram can't tell difference between uppercase and lowercase key
    assert(key == 88 or key == 120);
}
