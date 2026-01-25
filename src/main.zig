const std = @import("std");
const korgFormat = @import("korg_format.zig");
const pcg2syx = @import("pcg2syx.zig");

// Read a file and return its contents if it is in Korg5 format
pub fn readFile(path: []const u8) ![]u8 {
    const result: []u8 = undefined;
    const DATA_OFFSET: usize = 11;

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();
    std.debug.print("File length is {} bytes\n", .{file_size});

    var header: [5]u8 = undefined;
    var header_reader = file.reader(&header);
    const contents = try header_reader.interface.readSliceShort(&header);
    try file.seekTo(header_reader.pos + DATA_OFFSET);

    // Check if the format is Korg5
    if (korgFormat.isKorg5(header[0..contents])) {
        const allocator = std.heap.page_allocator;
        const position = try file.getPos();

        var data_reader = file.reader(result);
        try data_reader.seekBy(@intCast(position));

        return try data_reader.interface.readAlloc(allocator, file_size - position);
    } else {
        std.debug.print("File is NOT in Korg5 format.\n", .{});
        return error.InvalidFormat;
    }
}

pub fn main() !void {
    const data = readFile("X3_PLOAD.PCG") catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };

    const global = try pcg2syx.getGlobalData(data);
    try pcg2syx.createSysexFile("global.syx", pcg2syx.HEADER_GLOBAL, global);

    // Free allocated memory here
    std.heap.page_allocator.free(data);
    std.heap.page_allocator.free(global);
}
