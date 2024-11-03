const messages = @import("messages.zig");
const std = @import("std");

pub const UdpClient = struct {
    pub fn getTcpAddress() !messages.BroadcastResponse {
        const broadcast_ip_addr = "255.255.255.255";
        const broadcast_port = 1444;

        const response_ip_addr = "0.0.0.0";
        const response_port = 8117;

        const initiation_message: [1]u8 = .{1};

        const sockd = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC, 0);
        errdefer std.posix.close(sockd);

        // protocol expects "1" to be passed in as a byte to the bind call
        try std.posix.setsockopt(sockd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, &std.mem.toBytes(@as(c_int, 1)));

        const response_addr = try std.net.Address.resolveIp(response_ip_addr, response_port);
        try std.posix.bind(sockd, &response_addr.any, response_addr.getOsSockLen());

        const broadcast_addr = try std.net.Address.resolveIp(broadcast_ip_addr, broadcast_port);
        _ = try std.posix.sendto(sockd, initiation_message[0..], 0, &broadcast_addr.any, broadcast_addr.getOsSockLen());

        var buf: [12]u8 = undefined;
        const recv_bytes = try std.posix.recv(sockd, buf[0..], 0);
        return try messages.BroadcastResponse.parse(buf[0..recv_bytes]);
    }
};
