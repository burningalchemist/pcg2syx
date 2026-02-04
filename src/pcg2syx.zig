const std = @import("std");
const korgFormat = @import("korg_format.zig");

// SysEx header and footer constants
pub const HEADER = [_]u8{ 0xF0, 0x42, 0x30, 0x35, 0x00, 0x00 };
pub const HEADER_ALL: u8 = 0x50;
pub const FOOTER: u8 = 0xF7;

// Enum for different SysEx header types
pub const SysexHeader = enum(u8) {
    SONG = 0x48,
    PROGRAM = 0x4C,
    COMBI = 0x4D,
    GLOBAL = 0x51,
    DRUMS = 0x52,
};

// SysEx data must be "7-bit clean" meaning the high bit (bit 7) of every byte must be 0. To send 8-bit data,
// manufacturers often use a "7-to-8" packing scheme:
//
// * The Header Byte contains the MSBs of the next 7 data bytes
// * The Data Bytes contain the lower 7 bits of each original byte

// Encode data from 8-bit to 7-bit format for SysEx transmission
fn encodeSysex(allocator: anytype, src: []const u8) ![]u8 {
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

// Decode data from 7-bit back to 8-bit format
fn decodeSysex(allocator: anytype, src: []const u8) ![]u8 {
    // Count data bytes (exclude MSB collection bytes)
    var data_bytes: usize = 0;
    for (0..src.len) |i| {
        if (i % 8 != 0) {
            data_bytes += 1;
        }
    }

    var dest = try allocator.alloc(u8, data_bytes);
    var destIndex: usize = 0;

    for (0..src.len) |i| {
        const remainder: usize = i % 8;
        if (remainder == 0) {
            continue; // Skip MSB collection byte
        }
        dest[destIndex] = src[i];
        const msb_byte: u8 = src[i - remainder];
        const flag_bit: u8 = @as(u8, 1) << @intCast(remainder - 1);
        if ((msb_byte & flag_bit) != 0) {
            dest[destIndex] |= 0x80; // Set the MSB
        }
        destIndex += 1;
    }

    return dest;
}

// Extract global settings from the source data
fn extractGlobal(allocator: anytype, src: []const u8) ![]u8 {
    var extracted = try allocator.alloc(u8, 28);

    @memcpy(extracted[0..5], src[0..5]);
    @memcpy(extracted[5..19], src[10..24]);
    @memcpy(extracted[19..21], src[25..27]);
    @memcpy(extracted[21..23], src[44..46]);
    @memset(extracted[23..], 0);

    return extracted;
}

// Extract drum settings from the source data
fn extractDrums(allocator: anytype, src: []const u8) ![]u8 {
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

// Define categories for different types of data sections
pub const Category = enum {
    Global,
    Drums,
    Program,
    Combi,
};

// Struct to represent a data bank with its offset, size, and address
pub const Bank = struct {
    offset: usize,
    size: usize,
    address: usize,

    const Self = @This();

    pub fn init(size_offset: usize) Bank {
        return Self{
            .offset = size_offset,
            .size = 0,
            .address = 0,
        };
    }
};

// Struct to hold all necessary information for processing a category of data, including its type, associated banks,
// and SysEx header
pub const CategoryData = struct {
    category: Category,
    banks: []Bank,
    sysex_header: SysexHeader,

    const Self = @This();

    pub fn init(category: Category, banks: []Bank) CategoryData {
        const sysex_header = switch (category) {
            .Global => SysexHeader.GLOBAL,
            .Drums => SysexHeader.DRUMS,
            .Program => SysexHeader.PROGRAM,
            .Combi => SysexHeader.COMBI,
        };

        return Self{
            .category = category,
            .banks = banks,
            .sysex_header = sysex_header,
        };
    }
};

// collectData processes the data based on the provided CategoryData and extracts the relevant information
pub fn collectData(allocator: anytype, category: CategoryData, src: []u8) ![]u8 {
    var totalSize: usize = 0;
    for (category.banks) |*bank| {
        var size: [4]u8 = undefined;
        var address: [4]u8 = undefined;
        @memcpy(address[0..4], src[bank.offset .. bank.offset + 4]);
        @memcpy(size[0..4], src[bank.offset + 4 .. bank.offset + 8]);

        bank.size = korgFormat.byteArraytoInt(size[0..4]);
        bank.address = korgFormat.byteArraytoInt(address[0..4]) - 16;
        totalSize += bank.size;
    }

    var extract = try allocator.alloc(u8, totalSize);

    for (category.banks, 0..) |bank, index| {
        @memcpy(
            extract[index * bank.size .. (index + 1) * bank.size],
            src[bank.address .. bank.address + bank.size],
        );
    }

    if (totalSize == 0) {
        return error.NoDataExtracted;
    }

    if (extract.len != totalSize) {
        return error.DataSizeMismatch;
    }

    const result = switch (category.category) {
        .Global => {
            defer allocator.free(extract);
            return try extractGlobal(allocator, extract[0..totalSize]);
        },
        .Drums => {
            defer allocator.free(extract);
            return try extractDrums(allocator, extract[0..totalSize]);
        },
        else => {
            return extract;
        },
    };

    return result;
}

// Create a SysEx file with the given data and type
pub fn createSysexFile(filename: []const u8, fileType: u8, data: []const u8) !void {
    // assert data is not empty
    if (data.len == 0) {
        std.log.err("No data provided for SysEx file: {s}\n", .{filename});
        return;
    }

    var file = std.fs.cwd().createFile(filename, .{}) catch {
        std.log.err("SysEx file could not be created: {s}\n", .{filename});
        return;
    };
    defer file.close();

    var sysexHeader = HEADER;
    sysexHeader[4] = fileType;
    _ = try file.write(&sysexHeader);

    const allocator = std.heap.page_allocator;
    const convertedData = encodeSysex(allocator, data) catch {
        std.log.err("Error converting data for SysEx file: {s}\n", .{filename});
        return;
    };
    defer allocator.free(convertedData);

    _ = try file.write(convertedData);
    _ = try file.write(&[_]u8{FOOTER});

    std.log.info("SysEx file created: {s}", .{filename});
}

// Tests

test "encodeSysex/decodeSysex converts data correctly" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 0x81, 0x42 };
    const expected = [_]u8{ 0x01, 0x01, 0x42 };

    const encoded = try encodeSysex(allocator, input[0..]);
    defer allocator.free(encoded);

    const decoded = try decodeSysex(allocator, encoded[0..]);
    defer allocator.free(decoded);

    try std.testing.expect(std.mem.eql(u8, &expected, encoded));
    try std.testing.expect(std.mem.eql(u8, &input, decoded));
}

test "extractGlobal functionality" {
    const allocator = std.testing.allocator;

    // Sample data - A-Za-z0-9
    const src = [_]u8{
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
        0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50,
        0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
        0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E,
        0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76,
        0x77, 0x78, 0x79, 0x7A, 0x30, 0x31, 0x32, 0x33,
        0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x41, 0x42,
    };
    const extracted = try extractGlobal(allocator, src[0..]);
    defer allocator.free(extracted);

    // Expected data - ABCDEKLMNOPQRSTUVWXZast
    const expected = [_]u8{
        0x41, 0x42, 0x43, 0x44, 0x45, 0x4B, 0x4C,
        0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53,
        0x54, 0x55, 0x56, 0x57, 0x58, 0x5A, 0x61,
        0x73, 0x74, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    try std.testing.expect(std.mem.eql(u8, extracted, &expected));
}

test "extractDrums functionality" {
    const allocator = std.testing.allocator;
    var input = [_]u8{0} ** 5280;

    // Iteration 0: bytes 0,2,3,5,6,8,9 should become output bytes 0-6
    input[0] = 0x11;
    input[2] = 0x22;
    input[3] = 0x33;
    input[5] = 0x44;
    input[6] = 0x55;
    input[8] = 0x66;
    input[9] = 0x77;

    // Iteration 1: bytes 22,24,25,27,28,30,31 should become output bytes 7-13
    input[22] = 0x88;
    input[24] = 0x99;
    input[25] = 0xAA;
    input[27] = 0xBB;
    input[28] = 0xCC;
    input[30] = 0xDD;
    input[31] = 0xEE;

    const extracted = try extractDrums(allocator, input[0..]);
    defer allocator.free(extracted);

    const expected = [_]u8{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE,
    };

    try std.testing.expect(std.mem.eql(u8, extracted[0..14], &expected));
}
