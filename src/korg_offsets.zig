const std = @import("std");

const DeviceOffsets = struct {
    PROGRAM_A: usize,
    PROGRAM_B: usize,
    COMBI_A: usize,
    COMBI_B: usize,
    GLOBAL_A: usize,
    DRUMS_A: usize,
    DRUMS_B: usize,
};

const devices = enum {
    x2,
    x3,
    x5,
    n264,
    n364,
    o1w,
    o3rw,
    // Other devices can be added here
};

pub fn deviceOffsets(synth: []const u8) ?DeviceOffsets {
    const device: ?devices = std.meta.stringToEnum(devices, synth);
    if (device == null) {
        return null;
    }

    return switch (device.?) {
        .x2,
        .x3,
        .x5,
        .n264,
        .n364,
        .o1w,
        .o3rw,
        => DeviceOffsets{
            .PROGRAM_A = 40,
            .PROGRAM_B = 64,
            .COMBI_A = 32,
            .COMBI_B = 56,
            .GLOBAL_A = 16,
            .DRUMS_A = 24,
            .DRUMS_B = 48,
        },
        // Other device offsets can be added here
    };
}
