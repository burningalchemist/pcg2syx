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
        std.log.err("Unsupported file format\n", .{});
        return error.InvalidFormat;
    }
}

pub fn main() !void {
    std.log.info("Starting PCG to SysEx conversion...", .{});
    const data = readFile("X3_PLOAD.PCG") catch |err| {
        std.log.err("Error reading file: {}\n", .{err});
        return;
    };

    std.log.info("Extracting data sections...", .{});
    const global = try pcg2syx.getGlobalData(data);
    const drums = try pcg2syx.getDrumsData(data);
    const program = try pcg2syx.getProgramData(data);
    const combi = try pcg2syx.getCombiData(data);

    std.log.info("Creating SysEx files...", .{});
    try pcg2syx.createSysexFile("global.syx", pcg2syx.HEADER_GLOBAL, global);
    try pcg2syx.createSysexFile("drums.syx", pcg2syx.HEADER_DRUMS, drums);
    try pcg2syx.createSysexFile("program.syx", pcg2syx.HEADER_PROGRAM, program);
    try pcg2syx.createSysexFile("combi.syx", pcg2syx.HEADER_COMBI, combi);

    // Free allocated memory here
    std.log.info("Freeing allocated memory...", .{});
    std.heap.page_allocator.free(data);
    std.heap.page_allocator.free(global);
    std.heap.page_allocator.free(drums);
    std.heap.page_allocator.free(program);
    std.heap.page_allocator.free(combi);

    std.log.info("Conversion completed successfully.", .{});
}
