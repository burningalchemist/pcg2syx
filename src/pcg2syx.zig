const std = @import("std");
const korgFormat = @import("korg_format.zig");

pub const HEADER = [_]u8{ 0xF0, 66, 48, 53, 0, 0 };
pub const HEADER_SONG: u8 = 72;
pub const HEADER_PROGRAM: u8 = 76;
pub const HEADER_COMBI: u8 = 77;
pub const HEADER_GLOBAL: u8 = 81;
pub const HEADER_DRUMS: u8 = 82;
pub const HEADER_ALL: u8 = 80;
pub const FOOTER: u8 = 0xF7;

pub fn convert(src: []u8) ![]u8 {
    var addByte: u8 = 0;
    if (src.len * 8 % 7 > 0) {
        addByte = 1;
    }

    const allocator = std.heap.page_allocator;
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

pub fn extractGlobal(src: []u8) ![]u8 {
    const allocator = std.heap.page_allocator;
    var extracted = try allocator.alloc(u8, 28);
    for (extracted[23..28]) |*byte| {
        byte.* = 0;
    }
    @memcpy(extracted[0..5], src[0..5]);
    @memcpy(extracted[5..19], src[10..24]);
    @memcpy(extracted[19..21], src[25..27]);
    @memcpy(extracted[21..23], src[44..46]);

    return extracted;
}

pub fn getGlobalData(data: []u8) ![]u8 {
    const allocator = std.heap.page_allocator;
    var addressGlobal: [4]u8 = undefined;
    var sizeGlobal: [4]u8 = undefined;
    @memcpy(addressGlobal[0..4], data[16..20]);
    @memcpy(sizeGlobal[0..4], data[20..24]);
    const globalSize = korgFormat.byteArraytoInt(sizeGlobal[0..4]);
    var global = try allocator.alloc(u8, globalSize);
    const address = korgFormat.byteArraytoInt(addressGlobal[0..4]) - 16;
    @memcpy(global[0..globalSize], data[address .. address + globalSize]);
    return extractGlobal(global[0..globalSize]);
}

pub fn createSysexFile(filename: []const u8, fileType: u8, data: []u8) !void {
    const allocator = std.heap.page_allocator;
    var file = std.fs.cwd().createFile(filename, .{}) catch {
        std.debug.print("SysEx file could not be created: {s}\n", .{filename});
        return;
    };
    defer file.close();

    var sysexHeader = HEADER;
    sysexHeader[4] = fileType;
    _ = try file.write(&sysexHeader);

    const convertedData = convert(data) catch {
        std.debug.print("Error converting data for SysEx file: {s}\n", .{filename});
        return;
    };
    defer allocator.free(convertedData);
    _ = try file.write(convertedData);
    _ = try file.write(&[_]u8{FOOTER});
}
