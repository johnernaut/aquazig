const std = @import("std");
const os = std.posix;
const log = std.log;
const time = std.time;
const mem = std.mem;

const broadcastIpAddr = "255.255.255.255";
const broadcastPort = 1444;

const responseIpAddr = "0.0.0.0";
const responsePort = 8117;

const BroadcastResponse = struct {
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
        return std.fmt.allocPrint(std.heap.page_allocator, "{}.{}.{}.{}:{}", .{
            self.ip1,
            self.ip2,
            self.ip3,
            self.ip4,
            self.port,
        }) catch "invalid address";
    }
};

pub fn main() !void {
    var buf: [12]u8 = undefined;
    const sockd = try os.socket(os.AF.INET, os.SOCK.DGRAM | os.SOCK.CLOEXEC, 0);
    errdefer os.close(sockd);

    try os.setsockopt(sockd, os.SOL.SOCKET, os.SO.BROADCAST, &mem.toBytes(@as(c_int, 1)));

    const responseAddr = try std.net.Address.resolveIp(responseIpAddr, responsePort);
    try os.bind(sockd, &responseAddr.any, responseAddr.getOsSockLen());

    const broadCastAddr = try std.net.Address.resolveIp(broadcastIpAddr, broadcastPort);
    const message: [1]u8 = .{1};
    const send_bytes = try os.sendto(sockd, message[0..], 0, &broadCastAddr.any, broadCastAddr.getOsSockLen());
    log.info("{d}: send bytes:={d}", .{ time.milliTimestamp(), send_bytes });

    const recv_bytes = try os.recv(sockd, buf[0..], 0);

    const response = try BroadcastResponse.parse(buf[0..recv_bytes]);
    log.info("Received response from host: {s}", .{response.host()});
}
