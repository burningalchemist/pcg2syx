const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const korgFormat = @import("korg_format.zig");
const korgOffsets = @import("korg_offsets.zig");
const pcg2syx = @import("pcg2syx.zig");

// Read a file and return its contents if it's in a supported format
pub fn readFile(io: Io, allocator: Allocator, path: []const u8) ![]u8 {
    const DATA_OFFSET: usize = 11;

    std.log.info("Reading file: {s}", .{path});
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    const file_size = try file.length(io);

    // Read the header
    var header: [5]u8 = undefined;
    var bufs = [_][]u8{&header};
    _ = try file.readPositional(io, &bufs, 0);

    var r_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &r_buf);
    try reader.seekTo(DATA_OFFSET + header.len);

    if (!korgFormat.isSupported(&header)) {
        std.process.fatal("File format not supported: {s}\n", .{path});
    }

    std.log.info("Input file format: {s}", .{&header});
    const position = reader.logicalPos();

    var data_reader = file.reader(io, &r_buf);
    try data_reader.seekBy(@intCast(position));
    return try data_reader.interface.readAlloc(allocator, file_size - position);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Setup stdout for printing
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("PCG to SysEx Converter\n---\n", .{});
    try stdout.flush();

    // Initialize an arena allocator for temporary data storage during processing
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse command-line arguments
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const input_file = if (args.len > 1) args[1] else {
        try stdout.print("Usage: pcg2syx <input_file.pcg> [synth_model|n364]\n", .{});
        try stdout.flush();
        std.log.err("No input file specified\n", .{});
        return std.process.exit(2);
    };
    const arg_synth = if (args.len > 2) args[2] else "n364";

    std.log.info("Starting conversion for file: {s}", .{input_file});

    // Read the input file
    const data = readFile(io, allocator, input_file) catch |err| {
        std.process.fatal("Failed to read input file: {}", .{err});
    };
    defer allocator.free(data);

    // Determine synthesizer type and corresponding data offsets
    const synth = korgOffsets.deviceOffsets(arg_synth) orelse {
        std.process.fatal("Unsupported synthesizer specified: {s}", .{arg_synth});
    };

    std.log.info("Extracting data sections...", .{});

    // Initialize databanks for Korg N364/264
    const progA = pcg2syx.Bank.init(synth.PROGRAM_A);
    const progB = pcg2syx.Bank.init(synth.PROGRAM_B);
    const combiA = pcg2syx.Bank.init(synth.COMBI_A);
    const combiB = pcg2syx.Bank.init(synth.COMBI_B);
    const globalA = pcg2syx.Bank.init(synth.GLOBAL_A);
    const drumsA = pcg2syx.Bank.init(synth.DRUMS_A);
    const drumsB = pcg2syx.Bank.init(synth.DRUMS_B);

    // Create category data structures
    var global_bank = [_]pcg2syx.Bank{globalA};
    const global_category = pcg2syx.CategoryData.init(pcg2syx.Category.Global, &global_bank);
    var drum_banks = [_]pcg2syx.Bank{ drumsA, drumsB };
    const drum_category = pcg2syx.CategoryData.init(pcg2syx.Category.Drums, &drum_banks);
    var program_banks = [_]pcg2syx.Bank{ progA, progB };
    const prog_category = pcg2syx.CategoryData.init(pcg2syx.Category.Program, &program_banks);
    var combi_banks = [_]pcg2syx.Bank{ combiA, combiB };
    const combi_category = pcg2syx.CategoryData.init(pcg2syx.Category.Combi, &combi_banks);

    // Process source data and create SysEx files for each category
    const categories = [_]pcg2syx.CategoryData{ global_category, drum_category, prog_category, combi_category };
    for (categories) |cat| {
        std.log.info("Processing category: {s}", .{@tagName(cat.category)});
        const file_name = try std.fmt.allocPrint(allocator, "{s}_{s}.syx", .{ std.fs.path.stem(input_file), @tagName(cat.category) });
        defer allocator.free(file_name);
        const extracted_data = try pcg2syx.collectData(allocator, cat, data);
        defer allocator.free(extracted_data);
        try pcg2syx.createSysexFile(io, file_name, @intFromEnum(cat.sysex_header), extracted_data);
    }

    std.log.info("Conversion completed successfully.", .{});
}

// Tests

// Discover all tests in the module
test "tests:beforeAll" {
    std.testing.refAllDecls(@This());
}

test "readFile functionality" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const data = try readFile(io, allocator, "X3_PLOAD.PCG");
    defer allocator.free(data);
    try std.testing.expect(data.len > 0);
}

test "verify Combi.syx integrity" {
    const io = std.testing.io;
    const REF_COMBI_SHA1 = "4fbbe1276e0178912724e4e15e08dba9fc6cea88";
    const TEST_FILE = "Combi.syx";
    const allocator = std.testing.allocator;

    var r_buf: [4096]u8 = undefined;
    const f = try std.Io.Dir.cwd().openFile(io, TEST_FILE, .{ .mode = .read_only });
    defer f.close(io);
    var reader = f.reader(io, &r_buf);
    const data = try reader.interface.readAlloc(allocator, try reader.getSize());
    defer allocator.free(data);

    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &hash, .{});

    const hash_hex = try std.fmt.allocPrint(allocator, "{x}", .{hash});
    defer allocator.free(hash_hex);

    try std.testing.expect(std.mem.eql(u8, hash_hex, REF_COMBI_SHA1));
}
