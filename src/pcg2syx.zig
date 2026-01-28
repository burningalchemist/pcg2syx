const std = @import("std");
const korgFormat = @import("korg_format.zig");

// SysEx header and footer constants
pub const HEADER = [_]u8{ 0xF0, 0x42, 0x30, 0x35, 0x00, 0x00 };
pub const HEADER_SONG: u8 = 0x48;
pub const HEADER_PROGRAM: u8 = 0x4C;
pub const HEADER_COMBI: u8 = 0x4D;
pub const HEADER_GLOBAL: u8 = 0x51;
pub const HEADER_DRUMS: u8 = 0x52;
pub const HEADER_ALL: u8 = 0x50;
pub const FOOTER: u8 = 0xF7;

// Convert data from 8-bit to 7-bit format for SysEx transmission
pub fn convert(allocator: anytype, src: []const u8) ![]u8 {
    var addByte: u8 = 0;
    if (src.len * 8 % 7 > 0) {
        addByte = 1;
    }

    const dest_size = src.len * 8 / 7 + addByte;

    var dest = try allocator.alloc(u8, dest_size);
    var destIndex: usize = 0;

    for (0..src.len) |i| {
        const remainder: usize = i % 7;
        if (remainder == 0) {
            dest[destIndex] = 0;
            destIndex += 1;
        }

        dest[destIndex] = src[i];
        if (dest[destIndex] >= 128) { // u8 is unsigned, so check >= 128
            const flag_bit: u8 = @as(u8, 1) << @intCast(remainder);
            dest[destIndex - (remainder + 1)] |= flag_bit;
        }

        dest[destIndex] = dest[destIndex] & 127;
        destIndex += 1;
    }

    return dest;
}

// Extract global settings from the source data
pub fn extractGlobal(allocator: anytype, src: []const u8) ![]u8 {
    var extracted = try allocator.alloc(u8, 28);

    @memset(extracted[23..28], 0);
    @memcpy(extracted[0..5], src[0..5]);
    @memcpy(extracted[5..19], src[10..24]);
    @memcpy(extracted[19..21], src[25..27]);
    @memcpy(extracted[21..23], src[44..46]);

    return extracted;
}

// Extract drum settings from the source data
pub fn extractDrums(allocator: anytype, src: []const u8) ![]u8 {
    var extracted = try allocator.alloc(u8, 1680);

    for (0..240) |i| {
        extracted[0 + 7 * i] = src[0 + 22 * i];
        extracted[1 + 7 * i] = src[2 + 22 * i];
        extracted[2 + 7 * i] = src[3 + 22 * i];
        extracted[3 + 7 * i] = src[5 + 22 * i];
        extracted[4 + 7 * i] = src[6 + 22 * i];
        extracted[5 + 7 * i] = src[8 + 22 * i];
        extracted[6 + 7 * i] = src[9 + 22 * i];
    }

    return extracted;
}

// Get global data section from the PCG file
pub fn getGlobalData(allocator: anytype, data: []u8) ![]u8 {
    var addressGlobal: [4]u8 = undefined;
    var sizeGlobal: [4]u8 = undefined;

    @memcpy(addressGlobal[0..4], data[16..20]);
    @memcpy(sizeGlobal[0..4], data[20..24]);

    const globalSize = korgFormat.byteArraytoInt(sizeGlobal[0..4]);
    var global = try allocator.alloc(u8, globalSize);
    defer allocator.free(global);
    const address = korgFormat.byteArraytoInt(addressGlobal[0..4]) - 16;

    @memcpy(global[0..globalSize], data[address .. address + globalSize]);

    const result = try extractGlobal(allocator, global[0..globalSize]);
    return result;
}

// Get drum data section from the PCG file
pub fn getDrumsData(allocator: anytype, data: []u8) ![]u8 {
    var addressDrumsA: [4]u8 = undefined;
    var sizeDrumsA: [4]u8 = undefined;
    var addressDrumsB: [4]u8 = undefined;
    var sizeDrumsB: [4]u8 = undefined;

    @memcpy(addressDrumsA[0..4], data[24..28]);
    @memcpy(sizeDrumsA[0..4], data[28..32]);
    @memcpy(addressDrumsB[0..4], data[48..52]);
    @memcpy(sizeDrumsB[0..4], data[52..56]);

    const sizeA = korgFormat.byteArraytoInt(sizeDrumsA[0..4]);
    const sizeB = korgFormat.byteArraytoInt(sizeDrumsB[0..4]);

    var drums = try allocator.alloc(u8, sizeA + sizeB);
    defer allocator.free(drums);

    const addressA = korgFormat.byteArraytoInt(addressDrumsA[0..4]) - 16;
    const addressB = korgFormat.byteArraytoInt(addressDrumsB[0..4]) - 16;

    @memcpy(drums[0..sizeA], data[addressA .. addressA + sizeA]);
    @memcpy(drums[sizeA .. sizeA + sizeB], data[addressB .. addressB + sizeB]);

    const result = try extractDrums(allocator, drums[0 .. sizeA + sizeB]);
    return result;
}

// Get program data section from the PCG file
pub fn getProgramData(allocator: anytype, data: []u8) ![]u8 {
    var addressProgramA: [4]u8 = undefined;
    var sizeProgramA: [4]u8 = undefined;
    var addressProgramB: [4]u8 = undefined;
    var sizeProgramB: [4]u8 = undefined;

    @memcpy(addressProgramA[0..4], data[40..44]);
    @memcpy(sizeProgramA[0..4], data[44..48]);
    @memcpy(addressProgramB[0..4], data[64..68]);
    @memcpy(sizeProgramB[0..4], data[68..72]);

    const sizeA = korgFormat.byteArraytoInt(sizeProgramA[0..4]);
    const sizeB = korgFormat.byteArraytoInt(sizeProgramB[0..4]);

    var prog = try allocator.alloc(u8, sizeA + sizeB);

    const addressA = korgFormat.byteArraytoInt(addressProgramA[0..4]) - 16;
    const addressB = korgFormat.byteArraytoInt(addressProgramB[0..4]) - 16;

    @memcpy(prog[0..sizeA], data[addressA .. addressA + sizeA]);
    @memcpy(prog[sizeA .. sizeA + sizeB], data[addressB .. addressB + sizeB]);

    return prog;
}

// Get combination data section from the PCG file
pub fn getCombiData(allocator: anytype, data: []u8) ![]u8 {
    var addressCombiA: [4]u8 = undefined;
    var sizeCombiA: [4]u8 = undefined;
    var addressCombiB: [4]u8 = undefined;
    var sizeCombiB: [4]u8 = undefined;

    @memcpy(addressCombiA[0..4], data[32..36]);
    @memcpy(sizeCombiA[0..4], data[36..40]);
    @memcpy(addressCombiB[0..4], data[56..60]);
    @memcpy(sizeCombiB[0..4], data[60..64]);

    const sizeA = korgFormat.byteArraytoInt(sizeCombiA[0..4]);
    const sizeB = korgFormat.byteArraytoInt(sizeCombiB[0..4]);

    var combi = try allocator.alloc(u8, sizeA + sizeB);

    const addressA = korgFormat.byteArraytoInt(addressCombiA[0..4]) - 16;
    const addressB = korgFormat.byteArraytoInt(addressCombiB[0..4]) - 16;

    @memcpy(combi[0..sizeA], data[addressA .. addressA + sizeA]);
    @memcpy(combi[sizeA .. sizeA + sizeB], data[addressB .. addressB + sizeB]);

    return combi;
}

// Create a SysEx file with the given data and type
pub fn createSysexFile(filename: []const u8, fileType: u8, data: []const u8) !void {
    var file = std.fs.cwd().createFile(filename, .{}) catch {
        std.log.err("SysEx file could not be created: {s}\n", .{filename});
        return;
    };
    defer file.close();

    var sysexHeader = HEADER;
    sysexHeader[4] = fileType;
    _ = try file.write(&sysexHeader);

    const allocator = std.heap.page_allocator;
    const convertedData = convert(allocator, data) catch {
        std.log.err("Error converting data for SysEx file: {s}\n", .{filename});
        return;
    };
    defer allocator.free(convertedData);

    _ = try file.write(convertedData);
    _ = try file.write(&[_]u8{FOOTER});
}

test "convert functionality" {
    const allocator = std.testing.allocator;
    const input: [10]u8 = [_]u8{ 0xFF, 0x00, 0x7F, 0x80, 0x55, 0xAA, 0x33, 0xCC, 0x99, 0x66 };
    const converted = try convert(allocator, input[0..]);
    defer allocator.free(converted);
    // Expected output needs to be calculated based on the conversion logic
    const expected: [15]u8 = [_]u8{0} ** 15;

    try std.testing.expect(std.mem.eql(u8, converted, expected[0..]));
}

test "extractGlobal functionality" {
    const allocator = std.testing.allocator;
    const input: [100]u8 = [_]u8{0} ** 100;
    const extracted = try extractGlobal(allocator, input[0..]);
    defer allocator.free(extracted);
    // Expected output needs to be defined based on the extraction logic
    const expected: [28]u8 = [_]u8{0} ** 28;

    try std.testing.expect(std.mem.eql(u8, extracted, expected[0..]));
}

test "extractDrums functionality" {
    const allocator = std.testing.allocator;
    const input: [5280]u8 = [_]u8{0} ** 5280;
    const extracted = try extractDrums(allocator, input[0..]);
    defer allocator.free(extracted);
    // Expected output needs to be defined based on the extraction logic
    const expected: [1680]u8 = [_]u8{0} ** 1680;

    try std.testing.expect(std.mem.eql(u8, extracted, expected[0..]));
}

//test "createSysexFile functionality" {
//    const data: [10]u8 = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A };
//
//    try createSysexFile("test_output.syx", HEADER_PROGRAM, data[0..]);
//}
