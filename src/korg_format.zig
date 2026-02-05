const std = @import("std");

// Korg Product IDs
const product_id = enum(u8) {
    X_series = 0x35, // Also includes N264/364
    i_series = 0x39,
    Triton = 0x50,
    Karma = 0x5D,
    Triton_LE = 0x63,
    Kronos = 0x68,
    Oasys = 0x70,
    M3 = 0x75,
};

pub fn byteArraytoInt(input: []const u8) usize {
    var result: usize = 0;
    for (0..4) |index| {
        result += @as(usize, input[index]) << @intCast(index * 8);
    }
    return result;
}

fn isKorg(b: []const u8) bool {
    return std.mem.eql(u8, b[0..4], "KORG");
}

pub fn isSupported(b: []const u8) bool {
    if (!isKorg(b)) {
        return false;
    }
    const id = @as(product_id, @enumFromInt(b[4]));
    const result = switch (id) {
        product_id.X_series => true,
        else => false,
    };

    return result;
}
