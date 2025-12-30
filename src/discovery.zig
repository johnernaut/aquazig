const std = @import("std");
const testing = std.testing;
const posix = std.posix;
const net = std.net;

// ScreenLogic UDP Discovery
//
// ScreenLogic controllers can be discovered on the local network via UDP broadcast.
// The discovery process sends a probe packet to the broadcast address on port 1444,
// and listening controllers respond with their IP address and TCP port.
//
// Reference: protocol_document.pdf

pub const DiscoveryError = error{
    InvalidResponse,
    CheckDigitMismatch,
    SocketError,
    Timeout,
    BufferTooSmall,
};

/// Response from UDP broadcast discovery
///
/// Wire format (12 bytes):
/// ```
/// | Offset | Size | Field           | Description                        |
/// |--------|------|-----------------|------------------------------------|
/// | 0      | 4    | check_digit     | Must be 2 (u32 LE) to be valid     |
/// | 4      | 4    | ip_address      | IPv4 address bytes (e.g., 10.0.0.9)|
/// | 8      | 2    | port            | TCP port (u16 LE, usually 80)      |
/// | 10     | 1    | gateway_type    | Device type identifier             |
/// | 11     | 1    | gateway_subtype | Device subtype                     |
/// ```
pub const BroadcastResponse = struct {
    /// IP address components
    ip: [4]u8,
    /// TCP port for communication
    port: u16,
    /// Gateway type
    gateway_type: u8,
    /// Gateway subtype
    gateway_subtype: u8,

    /// Expected check digit value
    pub const EXPECTED_CHECK_DIGIT: u32 = 2;

    /// Parse a 12-byte broadcast response
    pub fn parse(buf: []const u8) !BroadcastResponse {
        if (buf.len < 12) return error.BufferTooSmall;

        // Check digit should be 2 (little-endian)
        const check_digit = std.mem.readInt(u32, buf[0..4], .little);
        if (check_digit != EXPECTED_CHECK_DIGIT) return error.CheckDigitMismatch;

        return BroadcastResponse{
            .ip = buf[4..8].*,
            .port = std.mem.readInt(u16, buf[8..10], .little),
            .gateway_type = buf[10],
            .gateway_subtype = buf[11],
        };
    }

    /// Get IP address as a formatted string
    pub fn ipString(self: BroadcastResponse, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{
            self.ip[0],
            self.ip[1],
            self.ip[2],
            self.ip[3],
        }) catch return error.BufferTooSmall;
    }

    /// Get as a std.net.Address for TCP connection
    pub fn toAddress(self: BroadcastResponse) !net.Address {
        return net.Address.initIp4(self.ip, self.port);
    }
};

/// Discovery configuration
pub const DiscoveryConfig = struct {
    /// Broadcast port - ScreenLogic controllers listen on UDP port 1444
    broadcast_port: u16 = 1444,
    /// Timeout in milliseconds for waiting for a response
    timeout_ms: u32 = 5000,
};

/// Discover Pentair ScreenLogic devices on the local network
///
/// Sends a UDP broadcast probe packet and waits for a response.
///
/// Discovery packet (8 bytes): `[1, 0, 0, 0, 0, 0, 0, 0]`
/// - First byte (1) indicates a discovery request
/// - Remaining bytes are reserved/padding
///
/// The controller responds with a 12-byte BroadcastResponse containing
/// its IP address and TCP port for subsequent connections.
///
/// Note: Uses SO_BROADCAST socket option and binds to port 0 (OS-assigned)
/// to avoid permission issues. SO_REUSEADDR is set for macOS compatibility.
pub fn discover(config: DiscoveryConfig) !BroadcastResponse {
    // Create UDP socket
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, 0);
    defer posix.close(sockfd);

    // Enable address reuse (helps on macOS)
    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

    // Enable broadcast
    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.BROADCAST, &std.mem.toBytes(@as(c_int, 1)));

    // Set receive timeout
    const timeout_sec = config.timeout_ms / 1000;
    const timeout_usec = (config.timeout_ms % 1000) * 1000;
    const timeout = posix.timeval{
        .sec = @intCast(timeout_sec),
        .usec = @intCast(timeout_usec),
    };
    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // Bind to any available port (let OS assign)
    const listen_addr = net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
    try posix.bind(sockfd, &listen_addr.any, listen_addr.getOsSockLen());

    // Use direct IP construction for broadcast (255.255.255.255)
    // Note: We use initIp4 instead of resolveIp to avoid DNS lookup issues
    // that can cause NetworkUnreachable errors on some systems.
    const broadcast_addr = net.Address.initIp4(.{ 255, 255, 255, 255 }, config.broadcast_port);

    // Discovery packet format (8 bytes):
    // [0]: 1 = discovery request type
    // [1-7]: Reserved (zeros)
    // The controller validates this format before responding.
    const discovery_packet = [8]u8{ 1, 0, 0, 0, 0, 0, 0, 0 };
    _ = try posix.sendto(sockfd, &discovery_packet, 0, &broadcast_addr.any, broadcast_addr.getOsSockLen());

    // Receive response
    var recv_buf: [12]u8 = undefined;
    const recv_len = posix.recv(sockfd, &recv_buf, 0) catch |err| {
        if (err == error.WouldBlock) return error.Timeout;
        return err;
    };

    return try BroadcastResponse.parse(recv_buf[0..recv_len]);
}

/// Discover with default configuration
pub fn discoverDefault() !BroadcastResponse {
    return discover(.{});
}

// Tests
test "BroadcastResponse parse valid response" {
    // Check digit (2), IP (192.168.1.100), Port (80), GT (0), GS (0)
    const data = [_]u8{ 0x02, 0x00, 0x00, 0x00, 192, 168, 1, 100, 0x50, 0x00, 0x00, 0x00 };
    const response = try BroadcastResponse.parse(&data);

    try testing.expectEqual(@as(u8, 192), response.ip[0]);
    try testing.expectEqual(@as(u8, 168), response.ip[1]);
    try testing.expectEqual(@as(u8, 1), response.ip[2]);
    try testing.expectEqual(@as(u8, 100), response.ip[3]);
    try testing.expectEqual(@as(u16, 80), response.port);
}

test "BroadcastResponse parse invalid check digit" {
    const data = [_]u8{ 0x03, 0x00, 0x00, 0x00, 192, 168, 1, 100, 0x50, 0x00, 0x00, 0x00 };
    const result = BroadcastResponse.parse(&data);
    try testing.expectError(error.CheckDigitMismatch, result);
}

test "BroadcastResponse toAddress" {
    const data = [_]u8{ 0x02, 0x00, 0x00, 0x00, 192, 168, 1, 100, 0x50, 0x00, 0x00, 0x00 };
    const response = try BroadcastResponse.parse(&data);
    const addr = try response.toAddress();

    const ip4 = addr.in.sa.addr;
    const bytes = std.mem.asBytes(&ip4);
    try testing.expectEqual(@as(u8, 192), bytes[0]);
    try testing.expectEqual(@as(u8, 168), bytes[1]);
    try testing.expectEqual(@as(u8, 1), bytes[2]);
    try testing.expectEqual(@as(u8, 100), bytes[3]);
    try testing.expectEqual(@as(u16, 80), addr.getPort());
}

test "BroadcastResponse parse buffer too small" {
    const data = [_]u8{ 0x02, 0x00, 0x00, 0x00, 192, 168 };
    const result = BroadcastResponse.parse(&data);
    try testing.expectError(error.BufferTooSmall, result);
}

test "BroadcastResponse ipString" {
    const data = [_]u8{ 0x02, 0x00, 0x00, 0x00, 10, 0, 1, 50, 0x89, 0x13, 0x00, 0x00 };
    const response = try BroadcastResponse.parse(&data);

    var buf: [16]u8 = undefined;
    const ip_str = try response.ipString(&buf);

    try testing.expectEqualStrings("10.0.1.50", ip_str);
}

test "BroadcastResponse parse non-standard port" {
    // Port 8080 = 0x1F90 in little-endian = 0x90, 0x1F
    const data = [_]u8{ 0x02, 0x00, 0x00, 0x00, 192, 168, 1, 1, 0x90, 0x1F, 0x00, 0x00 };
    const response = try BroadcastResponse.parse(&data);

    try testing.expectEqual(@as(u16, 8080), response.port);
}

test "DiscoveryConfig default values" {
    const config = DiscoveryConfig{};
    try testing.expectEqual(@as(u16, 1444), config.broadcast_port);
    try testing.expectEqual(@as(u32, 5000), config.timeout_ms);
}
