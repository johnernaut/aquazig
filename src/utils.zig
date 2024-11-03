const std = @import("std");

// return the length of an object + padding so its base 4
pub fn paddedLength(length: usize) usize {
    return length + ((4 - (length % 4)) % 4);
}

// read integer in little endian format
pub fn readIntLE(comptime T: type, reader: anytype) !T {
    return try reader.readInt(T, .little);
}

// write integer in little endian format
pub fn writeIntLE(comptime T: type, writer: anytype, value: T) !void {
    try writer.writeInt(T, value, .little);
}

// writes the length of a slice and then slice contents with padding for the contents so
// its base 4
pub fn writePaddedSlice(comptime T: type, writer: anytype, data: []const T) !void {
    const elem_size = @sizeOf(T);
    const data_len_in_bytes = data.len * elem_size;
    const length: u32 = @intCast(data_len_in_bytes);
    try writer.writeInt(u32, length, .little);

    // cast data to a byte slice
    const byte_data = std.mem.bytesAsSlice(T, data);
    try writer.writeAll(byte_data);

    const padding = (4 - (data_len_in_bytes % 4)) % 4;
    if (padding != 0) {
        var pad_bytes: [4]u8 = [_]u8{0} ** 4;
        try writer.writeAll(pad_bytes[0..padding]);
    }
}
