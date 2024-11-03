const std = @import("std");
const os = std.posix;
const log = std.log;
const time = std.time;
const mem = std.mem;
const net = std.net;
const messages = @import("messages.zig");

const broadcastIpAddr = "255.255.255.255";
const broadcastPort = 1444;

const responseIpAddr = "0.0.0.0";
const responsePort = 8117;

pub fn main() !void {
    const sockd = try os.socket(os.AF.INET, os.SOCK.DGRAM | os.SOCK.CLOEXEC, 0);
    errdefer os.close(sockd);

    try os.setsockopt(sockd, os.SOL.SOCKET, os.SO.BROADCAST, &mem.toBytes(@as(c_int, 1)));

    const responseAddr = try net.Address.resolveIp(responseIpAddr, responsePort);
    try os.bind(sockd, &responseAddr.any, responseAddr.getOsSockLen());

    const broadCastAddr = try net.Address.resolveIp(broadcastIpAddr, broadcastPort);
    const send_bytes = try os.sendto(sockd, messages.initiationMessage[0..], 0, &broadCastAddr.any, broadCastAddr.getOsSockLen());
    log.info("{d}: send bytes:={d}", .{ time.milliTimestamp(), send_bytes });

    var buf: [12]u8 = undefined;
    const recv_bytes = try os.recv(sockd, buf[0..], 0);

    const broadcastResp = try messages.broadcastResponse.parse(buf[0..recv_bytes]);
    log.info("Received response from host: {s}:{d}", .{ broadcastResp.host(), broadcastResp.port });

    // we have the pentair systems IP host and port - start interacting with it
    const pentairAddr = try net.Address.resolveIp(broadcastResp.host(), broadcastResp.port);
    const stream = try net.tcpConnectToAddress(pentairAddr);
    defer stream.close();

    const connectMsg = "CONNECTSERVERHOST".* ++ [4]u8{ 13, 10, 13, 10 };
    const writer = stream.writer();

    _ = try writer.writeAll(&connectMsg);
    log.info("Wrote {s}", .{connectMsg});

    // 5.2 Server Responses
    // 5.2.1 MESSAGE - Login Message Accepted
    // Message Codes: 0,28
    // 5.2.2 Ping Message (Answer)
    // Message Codes: 0,17
    // Response to 5.1.3.
    const allocator = std.heap.page_allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const login_msg = LoginMessage{};
    try login_msg.serialize(&buffer.writer());

    log.info("Buffer length: {d}", .{buffer.items.len});
    log.info("Buffer contents: {x}", .{buffer.items[0..buffer.items.len]});

    _ = try writer.writeAll(buffer.items[0..buffer.items.len]);
    log.info("Wrote LoginMessage {any}\n", .{buffer.items});

    var readBuffer: [1024]u8 = undefined;
    const reader = stream.reader();
    const read = try reader.read(&readBuffer);
    log.info("Read {any}\n", .{readBuffer[0..read]});
    const read_bytes = readBuffer[0..read];

    const id = std.mem.readInt(u16, read_bytes[0..2], .little);
    const message_type = std.mem.readInt(u16, read_bytes[2..4], .little);
    const content_length = std.mem.readInt(u32, read_bytes[4..8], .little);
    log.info("Message ID: {d}, Type: {d}, Content Length: {d}\n", .{ id, message_type, content_length });
}

// Login message
// Message Codes: 0,27
// Parameters:
// • (int) Schema [use 348]
// • (int) Connection type [use 0]
// • (String) Client Version [use ‘Android’]
// • (byte[ ]) Data [use array filled with zeros of length 16]
// • (int) Process ID [use 2]
const LoginMessage = struct {
    msg_cd1: u16 = 0,
    msg_cd2: u16 = 27,
    schema: u32 = 348,
    conn_type: u32 = 0,
    client_version: []const u8 = "Android",
    data_array: [16]u8 = [_]u8{0} ** 16,
    process_id: u32 = 2,

    fn serialize(self: *const LoginMessage, writer: anytype) !void {
        try writer.writeInt(u16, self.msg_cd1, .little);
        try writer.writeInt(u16, self.msg_cd2, .little);

        const client_version_padded_len = 4 + paddedLength(self.client_version.len); // length prefix + data + padding
        const data_array_padded_len = 4 + paddedLength(self.data_array.len); // length prefix + data + padding

        const data_size: u32 = @intCast(4 +
            4 +
            client_version_padded_len +
            data_array_padded_len +
            4);
        try writer.writeInt(u32, data_size, .little);

        try writer.writeInt(u32, self.schema, .little);
        try writer.writeInt(u32, self.conn_type, .little);

        // write client version with 4 byte padding alignment
        try writePaddedSlice(u8, writer, self.client_version);

        // write data_array with length and padding
        try writePaddedSlice(u8, writer, self.data_array[0..]);

        try writer.writeInt(u32, self.process_id, .little);
    }
};

fn paddedLength(length: usize) usize {
    return length + ((4 - (length % 4)) % 4);
}

fn writePaddedSlice(comptime T: type, writer: anytype, data: []const T) !void {
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
