const std = @import("std");

const korgFormat = @import("korg_format.zig");
const pcg2syx = @import("pcg2syx.zig");

// Read a file and return its contents if it's in a supported format
pub fn readFile(allocator: anytype, path: []const u8) ![]u8 {
    const result: []u8 = undefined;
    const DATA_OFFSET: usize = 11;

    std.log.info("Reading file: {s}", .{path});
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();

    var header: [5]u8 = undefined;
    var header_reader = file.reader(&header);
    _ = try header_reader.interface.readSliceShort(&header);
    try file.seekTo(header_reader.pos + DATA_OFFSET);

    if (!korgFormat.isSupported(&header)) {
        std.log.err("Unsupported file format\n", .{});
        return error.InvalidFormat;
    }

    std.log.info("Input file format: {s}", .{&header});
    const position = try file.getPos();

    var data_reader = file.reader(result);
    try data_reader.seekBy(@intCast(position));

    return try data_reader.interface.readAlloc(allocator, file_size - position);
}

pub fn main() !void {
    std.log.info("Starting PCG to SysEx conversion...", .{});
    const allocator = std.heap.page_allocator;
    const data = readFile(allocator, "X3_PLOAD.PCG") catch |err| {
        std.log.err("Error reading file: {}\n", .{err});
        return;
    };
    defer allocator.free(data);

    std.log.info("Extracting data sections...", .{});
    const global = try pcg2syx.getGlobalData(allocator, data);
    defer allocator.free(global);

    const drums = try pcg2syx.getDrumsData(allocator, data);
    defer allocator.free(drums);

    const program = try pcg2syx.getProgramData(allocator, data);
    defer allocator.free(program);

    const combi = try pcg2syx.getCombiData(allocator, data);
    defer allocator.free(combi);

    std.log.info("Creating SysEx files...", .{});
    try pcg2syx.createSysexFile("global.syx", pcg2syx.HEADER_GLOBAL, global);
    try pcg2syx.createSysexFile("drums.syx", pcg2syx.HEADER_DRUMS, drums);
    try pcg2syx.createSysexFile("program.syx", pcg2syx.HEADER_PROGRAM, program);
    try pcg2syx.createSysexFile("combi.syx", pcg2syx.HEADER_COMBI, combi);

    std.log.info("Conversion completed successfully.", .{});
}

// Tests

// Discover all tests in the module
test "tests:beforeAll" {
    std.testing.refAllDecls(@This());
}

test "readFile functionality" {
    const allocator = std.testing.allocator;
    const data = try readFile(allocator, "X3_PLOAD.PCG");
    defer allocator.free(data);
    try std.testing.expect(data.len > 0);
}

test "verify combi.syx integrity" {
    const REF_COMBI_SHA1 = "4fbbe1276e0178912724e4e15e08dba9fc6cea88";
    const allocator = std.testing.allocator;

    const r_buf: []u8 = undefined;
    const f = try std.fs.cwd().openFile("combi.syx", .{ .mode = .read_only });
    defer f.close();
    var reader = f.reader(r_buf);
    const data = try reader.interface.readAlloc(allocator, try reader.getSize());
    defer allocator.free(data);

    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &hash, .{});
    const hash_hex = try std.fmt.allocPrint(allocator, "{x}", .{hash});
    defer allocator.free(hash_hex);

    try std.testing.expect(std.mem.eql(u8, hash_hex, REF_COMBI_SHA1));
}
