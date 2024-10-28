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

    var readBuffer: [1024]u8 = undefined;
    const reader = stream.reader();
    const read = try reader.read(&readBuffer);
    log.info("Read {s}\n", .{readBuffer[0..read]});
}

fn tcp_read(stream: net.Stream) !void {
    var readBuffer: [1024]u8 = .{0} ** 1024;
    while (true) {
        const read = try stream.read(readBuffer[0..]);
        if (read > 0) {
            log.info("read {d} bytesd.  buffer: {s}", .{ read, readBuffer });
        } else {
            log.info("read == 0", .{});
        }
    }
}
