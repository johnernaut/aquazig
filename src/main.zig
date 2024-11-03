const std = @import("std");
const log = std.log;
const net = std.net;
const utils = @import("utils.zig");
const clients = @import("network_clients.zig");
const messages = @import("messages.zig");

pub fn main() !void {
    const broadcastResp = try clients.UdpClient.getTcpAddress();
    log.info("Received response from host: {s}:{d}", .{ broadcastResp.host(), broadcastResp.port });

    // we have the pentair systems IP host and port - start interacting with it
    const pentairAddr = try net.Address.resolveIp(broadcastResp.host(), broadcastResp.port);
    const stream = try net.tcpConnectToAddress(pentairAddr);
    defer stream.close();

    const connectMsg = "CONNECTSERVERHOST".* ++ [4]u8{ 13, 10, 13, 10 };
    const writer = stream.writer();

    _ = try writer.writeAll(&connectMsg);

    const allocator = std.heap.page_allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const login_msg = messages.LoginMessage.init();
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
