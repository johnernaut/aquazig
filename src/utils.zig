const std = @import("std");

pub fn paddedLength(length: usize) usize {
    return length + ((4 - (length % 4)) % 4);
}

pub fn writeUInt32LE(writer: anytype, value: u32) !void {
    try writer.writeInt(u32, value, .little);
}

pub fn writeUInt16LE(writer: anytype, value: u16) !void {
    try writer.writeInt(u16, value, .little);
}

pub fn readUInt16LE(reader: anytype) !u16 {
    return try reader.readInt(u16, .little);
}

pub fn readUInt32LE(reader: anytype) !u32 {
    return try reader.readInt(u32, .little);
}

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
