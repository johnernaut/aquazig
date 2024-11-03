const std = @import("std");
const os = std.posix;
const log = std.log;
const time = std.time;
const mem = std.mem;
const net = std.net;
const messages = @import("messages.zig");
const utils = @import("utils.zig");

const UdpClient = struct {
    pub fn getTcpAddress() !messages.BroadcastResponse {
        const broadcast_ip_addr = "255.255.255.255";
        const broadcast_port = 1444;

        const response_ip_addr = "0.0.0.0";
        const response_port = 8117;

        const initiation_message: [1]u8 = .{1};

        const sockd = try os.socket(os.AF.INET, os.SOCK.DGRAM | os.SOCK.CLOEXEC, 0);
        errdefer os.close(sockd);

        // protocol expects "1" to be passed in as a byte to the bind call
        try os.setsockopt(sockd, os.SOL.SOCKET, os.SO.BROADCAST, &mem.toBytes(@as(c_int, 1)));

        const response_addr = try net.Address.resolveIp(response_ip_addr, response_port);
        try os.bind(sockd, &response_addr.any, response_addr.getOsSockLen());

        const broadcast_addr = try net.Address.resolveIp(broadcast_ip_addr, broadcast_port);
        _ = try os.sendto(sockd, initiation_message[0..], 0, &broadcast_addr.any, broadcast_addr.getOsSockLen());

        var buf: [12]u8 = undefined;
        const recv_bytes = try os.recv(sockd, buf[0..], 0);
        return try messages.BroadcastResponse.parse(buf[0..recv_bytes]);
    }
};

pub fn main() !void {
    const broadcastResp = try UdpClient.getTcpAddress();
    log.info("Received response from host: {s}:{d}", .{ broadcastResp.host(), broadcastResp.port });

    // we have the pentair systems IP host and port - start interacting with it
    const pentairAddr = try net.Address.resolveIp(broadcastResp.host(), broadcastResp.port);
    const stream = try net.tcpConnectToAddress(pentairAddr);
    defer stream.close();

    const connectMsg = "CONNECTSERVERHOST".* ++ [4]u8{ 13, 10, 13, 10 };
    const writer = stream.writer();

    _ = try writer.writeAll(&connectMsg);

    // 5.2 Server Responses
    // 5.2.1 MESSAGE - Login Message Accepted
    // Message Codes: 0,28
    // 5.2.2 Ping Message (Answer)
    // Message Codes: 0,17
    // Response to 5.1.3.
    const allocator = std.heap.page_allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const login_msg = LoginMessage.init();
    try login_msg.serialize(&buffer.writer());

    _ = try writer.writeAll(buffer.items[0..buffer.items.len]);

    const reader = stream.reader();
    try readMessage(reader);
}

fn readMessage(reader: anytype) !void {
    const id = try utils.readIntLE(u16, reader);
    const message_type = try utils.readIntLE(u16, reader);
    const content_length = try utils.readIntLE(u32, reader);
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
    base: Message,
    schema: u32,
    conn_type: u32,
    client_version: []const u8,
    data_array: [16]u8,
    process_id: u32,

    fn init() LoginMessage {
        return LoginMessage{
            .base = .{ .msg_cd1 = 0, .msg_cd2 = 27 },
            .schema = 348,
            .conn_type = 0,
            .client_version = "Android",
            .data_array = [_]u8{0} ** 16,
            .process_id = 2,
        };
    }

    fn serialize(self: *const LoginMessage, writer: anytype) !void {
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
