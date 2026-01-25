const std = @import("std");

pub fn byteArraytoInt(input: []const u8) usize {
    var result: usize = 0;

    for (0..4) |index| {
       // result += input[index] << index * 8;
        result += @as(usize, input[index]) << @intCast(index * 8);
    }

    std.debug.print("Converted integer: {d}\n", .{result});
    return result;
}

fn isKorg(b: []const u8) bool {
    return b[0] == 75 and b[1] == 79 and b[2] == 82 and b[3] == 71;
}

pub fn isKorg5(b: []const u8) bool {
    std.debug.print("Checking Korg5 format for bytes: {s}\n", .{b});
    return isKorg(b) and b[4] == 53;
}

pub fn isKorg9(b: []const u8) bool {
    return isKorg(b) and b[4] == 57;
}
