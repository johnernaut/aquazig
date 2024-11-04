const std = @import("std");
const log = std.log;
const net = std.net;
const utils = @import("utils.zig");
const clients = @import("network_clients.zig");
const messages = @import("messages.zig");
const xev = @import("xev");

pub fn main() !void {
    const broadcastResp = try clients.UdpClient.getTcpAddress();
    log.info("Received response from host: {s}:{d}", .{ broadcastResp.host(), broadcastResp.port });

    // we have the pentair systems IP host and port - start interacting with it
    const pentair_addr = try net.Address.resolveIp(broadcastResp.host(), broadcastResp.port);
    const stream = try net.tcpConnectToAddress(pentair_addr);
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
    _ = try utils.readIntLE(u16, reader);
    const message_type_value = try utils.readIntLE(u16, reader);
    const message_type = messages.MessageType.fromU16(message_type_value).?;
    _ = try utils.readIntLE(u32, reader);

    switch (message_type) {
        .loginQuery => std.debug.print("Got login query\n", .{}),
        .loginResponse => std.debug.print("Got login response\n", .{}),
        .statusQuery => std.debug.print("Got status query\n", .{}),
        .statusResponse => std.debug.print("Got status response\n", .{}),
        .setButtonPressQuery => std.debug.print("Got set button press query\n", .{}),
        .setButtonPressResponse => std.debug.print("Got set button press response\n", .{}),
        .controllerConfigQuery => std.debug.print("Got controller config query\n", .{}),
        .controllerConfigResponse => std.debug.print("Got controller config response\n", .{}),
        .setHeatModeQuery => std.debug.print("Got set head mode query\n", .{}),
    }
}
