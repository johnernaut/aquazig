const std = @import("std");
const utils = @import("utils.zig");

pub const BroadcastResponse = struct {
    chk: [4]u8,
    ip1: u8,
    ip2: u8,
    ip3: u8,
    ip4: u8,
    port: u16,
    gt: u8,
    gs: u8,

    pub fn parse(buf: []const u8) !BroadcastResponse {
        if (buf[0] != 2) return error.InvalidResponse;
        if (buf.len < 12) return error.BufferTooSmall;

        return BroadcastResponse{
            .chk = buf[0..4].*,
            .ip1 = buf[4],
            .ip2 = buf[5],
            .ip3 = buf[6],
            .ip4 = buf[7],
            .port = @as(u16, (buf[8] + buf[9])),
            .gt = buf[10],
            .gs = buf[11],
        };
    }

    pub fn host(self: BroadcastResponse) []const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "{}.{}.{}.{}", .{
            self.ip1,
            self.ip2,
            self.ip3,
            self.ip4,
        }) catch "invalid address";
    }
};

// Login message
// Message Codes: 0,27
// Parameters:
// • (int) Schema [use 348]
// • (int) Connection type [use 0]
// • (String) Client Version [use ‘Android’]
// • (byte[ ]) Data [use array filled with zeros of length 16]
// • (int) Process ID [use 2]
pub const LoginMessage = struct {
    base: Message,
    schema: u32,
    conn_type: u32,
    client_version: []const u8,
    data_array: [16]u8,
    process_id: u32,

    pub fn init() LoginMessage {
        return LoginMessage{
            .base = .{ .msg_cd1 = 0, .msg_cd2 = 27 },
            .schema = 348,
            .conn_type = 0,
            .client_version = "Android",
            .data_array = [_]u8{0} ** 16,
            .process_id = 2,
        };
    }

    pub fn serialize(self: *const LoginMessage, writer: anytype) !void {
        try utils.writeIntLE(u16, writer, self.base.msg_cd1);
        try utils.writeIntLE(u16, writer, self.base.msg_cd2);

        const client_version_padded_len = 4 + utils.paddedLength(self.client_version.len); // length prefix + data + padding
        const data_array_padded_len = 4 + utils.paddedLength(self.data_array.len); // length prefix + data + padding

        const data_size: u32 = @intCast(4 +
            4 +
            client_version_padded_len +
            data_array_padded_len +
            4);
        try utils.writeIntLE(u32, writer, data_size);

        try utils.writeIntLE(u32, writer, self.schema);
        try utils.writeIntLE(u32, writer, self.conn_type);

        // write client version with 4 byte padding alignment
        try utils.writePaddedSlice(u8, writer, self.client_version);

        // write data_array with length and padding
        try utils.writePaddedSlice(u8, writer, self.data_array[0..]);

        try utils.writeIntLE(u32, writer, self.process_id);
    }
};

const Message = struct {
    msg_cd1: u16,
    msg_cd2: u16,
};
