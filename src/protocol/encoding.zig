const std = @import("std");
const testing = std.testing;

/// Calculate padded length aligned to 4-byte boundary
pub fn paddedLength(length: usize) usize {
    return length + ((4 - (length % 4)) % 4);
}

/// Read a little-endian integer from a reader
pub fn readIntLE(comptime T: type, reader: anytype) !T {
    return try reader.readInt(T, .little);
}

/// Write a little-endian integer to a writer
pub fn writeIntLE(comptime T: type, writer: anytype, value: T) !void {
    try writer.writeInt(T, value, .little);
}

/// Read a little-endian integer from a byte slice at offset
pub fn readIntFromSlice(comptime T: type, data: []const u8, offset: usize) !T {
    const size = @sizeOf(T);
    if (offset + size > data.len) return error.BufferTooSmall;
    const bytes = data[offset..][0..size];
    return std.mem.readInt(T, bytes, .little);
}

/// Write a length-prefixed, 4-byte aligned padded slice
pub fn writePaddedSlice(writer: anytype, data: []const u8) !void {
    const length: u32 = @intCast(data.len);
    try writer.writeInt(u32, length, .little);
    try writer.writeAll(data);

    const padding = (4 - (data.len % 4)) % 4;
    if (padding > 0) {
        const pad_bytes = [_]u8{0} ** 4;
        try writer.writeAll(pad_bytes[0..padding]);
    }
}

/// Read a length-prefixed, padded string from a reader
pub fn readPaddedString(reader: anytype, allocator: std.mem.Allocator) ![]u8 {
    const length = try reader.readInt(u32, .little);
    if (length == 0) return &[_]u8{};

    const buffer = try allocator.alloc(u8, length);
    errdefer allocator.free(buffer);

    try reader.readNoEof(buffer);

    const padding = (4 - (length % 4)) % 4;
    if (padding > 0) {
        var pad_buf: [4]u8 = undefined;
        try reader.readNoEof(pad_buf[0..padding]);
    }

    return buffer;
}

/// Read a length-prefixed, padded string from a byte slice
pub fn readPaddedStringFromSlice(data: []const u8, offset: usize, allocator: std.mem.Allocator) !struct { string: []u8, bytes_consumed: usize } {
    if (offset + 4 > data.len) return error.BufferTooSmall;

    const length = std.mem.readInt(u32, data[offset..][0..4], .little);
    if (length == 0) return .{ .string = &[_]u8{}, .bytes_consumed = 4 };

    const padded_len = paddedLength(length);
    if (offset + 4 + padded_len > data.len) return error.BufferTooSmall;

    const string = try allocator.alloc(u8, length);
    @memcpy(string, data[offset + 4 ..][0..length]);

    return .{ .string = string, .bytes_consumed = 4 + padded_len };
}

/// Skip a padded string in a byte slice, returning bytes consumed
pub fn skipPaddedString(data: []const u8, offset: usize) !usize {
    if (offset + 4 > data.len) return error.BufferTooSmall;

    const length = std.mem.readInt(u32, data[offset..][0..4], .little);
    const padded_len = paddedLength(length);
    return 4 + padded_len;
}

// Tests
test "paddedLength calculates correct alignment" {
    try testing.expectEqual(@as(usize, 0), paddedLength(0));
    try testing.expectEqual(@as(usize, 4), paddedLength(1));
    try testing.expectEqual(@as(usize, 4), paddedLength(2));
    try testing.expectEqual(@as(usize, 4), paddedLength(3));
    try testing.expectEqual(@as(usize, 4), paddedLength(4));
    try testing.expectEqual(@as(usize, 8), paddedLength(5));
    try testing.expectEqual(@as(usize, 8), paddedLength(7));
    try testing.expectEqual(@as(usize, 8), paddedLength(8));
}

test "readIntFromSlice reads little-endian integers" {
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    try testing.expectEqual(@as(u16, 0x0201), try readIntFromSlice(u16, &data, 0));
    try testing.expectEqual(@as(u32, 0x04030201), try readIntFromSlice(u32, &data, 0));
    try testing.expectEqual(@as(u16, 0x0403), try readIntFromSlice(u16, &data, 2));
}

test "writePaddedSlice writes with correct padding" {
    var buffer: [20]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writePaddedSlice(writer, "ABC");

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 8), written.len);
    try testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, written[0..4], .little));
    try testing.expectEqualSlices(u8, "ABC", written[4..7]);
    try testing.expectEqual(@as(u8, 0), written[7]);
}

test "writePaddedSlice handles exact 4-byte alignment" {
    var buffer: [20]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writePaddedSlice(writer, "ABCD");

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 8), written.len);
    try testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, written[0..4], .little));
    try testing.expectEqualSlices(u8, "ABCD", written[4..8]);
}

test "writePaddedSlice handles empty string" {
    var buffer: [20]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writePaddedSlice(writer, "");

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 4), written.len);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[0..4], .little));
}

test "readPaddedStringFromSlice reads correctly" {
    const allocator = testing.allocator;

    // "Pool" with length prefix and padding
    const data = [_]u8{
        0x04, 0x00, 0x00, 0x00, // length = 4
        'P',  'o',  'o',  'l', // data
    };

    const result = try readPaddedStringFromSlice(&data, 0, allocator);
    defer allocator.free(result.string);

    try testing.expectEqualStrings("Pool", result.string);
    try testing.expectEqual(@as(usize, 8), result.bytes_consumed);
}

test "readPaddedStringFromSlice handles empty string" {
    const allocator = testing.allocator;

    const data = [_]u8{ 0x00, 0x00, 0x00, 0x00 };

    const result = try readPaddedStringFromSlice(&data, 0, allocator);

    try testing.expectEqual(@as(usize, 0), result.string.len);
    try testing.expectEqual(@as(usize, 4), result.bytes_consumed);
}

test "readPaddedStringFromSlice with padding" {
    const allocator = testing.allocator;

    // "Spa" (3 bytes) + 1 padding byte
    const data = [_]u8{
        0x03, 0x00, 0x00, 0x00, // length = 3
        'S',  'p',  'a',  0x00, // data + padding
    };

    const result = try readPaddedStringFromSlice(&data, 0, allocator);
    defer allocator.free(result.string);

    try testing.expectEqualStrings("Spa", result.string);
    try testing.expectEqual(@as(usize, 8), result.bytes_consumed);
}

test "readIntFromSlice returns error on buffer overflow" {
    const data = [_]u8{ 0x01, 0x02 };

    const result = readIntFromSlice(u32, &data, 0);
    try testing.expectError(error.BufferTooSmall, result);
}

test "readIntFromSlice with offset" {
    const data = [_]u8{ 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x00 };

    try testing.expectEqual(@as(u32, 1), try readIntFromSlice(u32, &data, 2));
}

test "skipPaddedString calculates correct skip length" {
    // 5-byte string padded to 8
    const data = [_]u8{
        0x05, 0x00, 0x00, 0x00, // length = 5
        'H',  'e',  'l',  'l',
        'o',  0x00, 0x00, 0x00, // + 3 padding
    };

    const skip = try skipPaddedString(&data, 0);
    try testing.expectEqual(@as(usize, 12), skip); // 4 (len) + 8 (padded data)
}

test "write then read padded slice round-trip" {
    const allocator = testing.allocator;

    var buffer: [100]u8 = undefined;
    var write_stream = std.io.fixedBufferStream(&buffer);

    const original = "ScreenLogic Test";
    try writePaddedSlice(write_stream.writer(), original);

    const written = write_stream.getWritten();
    const result = try readPaddedStringFromSlice(written, 0, allocator);
    defer allocator.free(result.string);

    try testing.expectEqualStrings(original, result.string);
}
