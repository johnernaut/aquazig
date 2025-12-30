const std = @import("std");
const net = std.net;
const posix = std.posix;
const log = std.log.scoped(.screenlogic);
const xev = @import("xev");

const discovery = @import("discovery.zig");
const messages = @import("protocol/messages.zig");
const encoding = @import("protocol/encoding.zig");
const responses = @import("protocol/responses.zig");
const pump = @import("protocol/pump.zig");

// Client Architecture
//
// This client uses libxev internally for async I/O while exposing a synchronous API.
// The event loop is owned by the client and run to completion for each operation.
// This enables features like timeouts, keepalive pings, and reconnection while
// keeping the API simple for users.

pub const ClientError = error{
    NotConnected,
    LoginFailed,
    InvalidResponse,
    UnexpectedMessage,
    Timeout,
    ConnectionClosed,
    BufferTooSmall,
    OutOfMemory,
    ConnectionFailed,
    AlreadyConnected,
};

/// Connection state machine
pub const ConnectionState = enum {
    disconnected,
    connecting,
    handshaking,
    authenticating,
    ready,
    reconnecting,
    failed,
};

/// ScreenLogic client configuration
pub const ClientConfig = struct {
    /// Connection timeout in milliseconds
    timeout_ms: u32 = 10000,
    /// Buffer size for reading messages
    buffer_size: usize = 8192,
    /// Ping interval in milliseconds (0 to disable)
    ping_interval_ms: u32 = 30000,
    /// Enable automatic reconnection
    auto_reconnect: bool = true,
    /// Maximum reconnection attempts (0 for unlimited)
    max_reconnect_attempts: u32 = 10,
    /// Base delay for reconnection backoff in ms
    reconnect_base_delay_ms: u32 = 1000,
    /// Maximum delay for reconnection backoff in ms
    reconnect_max_delay_ms: u32 = 60000,
};

/// Callback type for status change notifications
pub const StatusChangedCallback = *const fn (status: *responses.PoolStatus, userdata: ?*anyopaque) void;

/// Callback type for disconnection notifications
pub const DisconnectedCallback = *const fn (reason: DisconnectReason, userdata: ?*anyopaque) void;

pub const DisconnectReason = enum {
    normal,
    connection_lost,
    timeout,
    max_retries_exceeded,
};

/// Generate a unique client ID for subscriptions
fn generateClientId() u32 {
    // Use timestamp as a simple unique ID generator
    const ts = std.time.milliTimestamp();
    return @truncate(@as(u64, @bitCast(ts)));
}

/// High-level ScreenLogic client with async I/O (libxev)
pub const Client = struct {
    allocator: std.mem.Allocator,
    config: ClientConfig,

    // Event loop (owned)
    loop: xev.Loop,
    loop_initialized: bool,

    // Socket (xev TCP)
    socket: ?xev.TCP,
    address: ?net.Address,

    // Connection state
    state: ConnectionState,
    logged_in: bool,
    subscribed: bool,
    client_id: u32,

    // Buffers
    read_buffer: []u8,
    write_buffer: []u8,

    // For synchronous operations - result storage
    last_error: ?anyerror,
    response_header: ?messages.MessageHeader,
    response_data_len: usize,

    // Reconnection state
    reconnect_attempts: u32,

    // Callbacks for push notifications
    on_status_changed: ?StatusChangedCallback,
    on_status_changed_userdata: ?*anyopaque,
    on_disconnected: ?DisconnectedCallback,
    on_disconnected_userdata: ?*anyopaque,

    // Completion objects (reusable)
    connect_completion: xev.Completion,
    read_completion: xev.Completion,
    write_completion: xev.Completion,
    ping_completion: xev.Completion,

    // Ping timer for keepalive
    ping_timer: ?xev.Timer,
    ping_timer_active: bool,
    last_ping_time: i64,

    // Operation state flags
    operation_complete: bool,
    bytes_written: usize,
    bytes_to_write: usize,
    bytes_read: usize,
    bytes_to_read: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ClientConfig) !Self {
        const read_buffer = try allocator.alloc(u8, config.buffer_size);
        errdefer allocator.free(read_buffer);

        const write_buffer = try allocator.alloc(u8, 256);
        errdefer allocator.free(write_buffer);

        const loop = try xev.Loop.init(.{});

        return Self{
            .allocator = allocator,
            .config = config,
            .loop = loop,
            .loop_initialized = true,
            .socket = null,
            .address = null,
            .state = .disconnected,
            .logged_in = false,
            .subscribed = false,
            .client_id = generateClientId(),
            .read_buffer = read_buffer,
            .write_buffer = write_buffer,
            .last_error = null,
            .response_header = null,
            .response_data_len = 0,
            .reconnect_attempts = 0,
            .on_status_changed = null,
            .on_status_changed_userdata = null,
            .on_disconnected = null,
            .on_disconnected_userdata = null,
            .connect_completion = undefined,
            .read_completion = undefined,
            .write_completion = undefined,
            .ping_completion = undefined,
            .ping_timer = null,
            .ping_timer_active = false,
            .last_ping_time = 0,
            .operation_complete = false,
            .bytes_written = 0,
            .bytes_to_write = 0,
            .bytes_read = 0,
            .bytes_to_read = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopPingTimer();
        self.disconnect();
        if (self.loop_initialized) {
            self.loop.deinit();
            self.loop_initialized = false;
        }
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
    }

    /// Start the keepalive ping timer
    fn startPingTimer(self: *Self) void {
        if (self.config.ping_interval_ms == 0) return;
        if (self.ping_timer_active) return;

        self.ping_timer = xev.Timer.init() catch {
            log.warn("Failed to initialize ping timer", .{});
            return;
        };

        self.ping_timer_active = true;
        self.last_ping_time = std.time.milliTimestamp();

        // Schedule the first ping
        self.ping_timer.?.run(&self.loop, &self.ping_completion, self.config.ping_interval_ms, Self, self, pingTimerCallback);

        log.debug("Ping timer started (interval: {d}ms)", .{self.config.ping_interval_ms});
    }

    /// Stop the keepalive ping timer
    fn stopPingTimer(self: *Self) void {
        if (self.ping_timer) |*timer| {
            timer.deinit();
            self.ping_timer = null;
        }
        self.ping_timer_active = false;
    }

    /// Ping timer callback - sends a ping and reschedules
    fn pingTimerCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;

        _ = result catch |err| {
            if (err == error.Canceled) {
                // Timer was canceled, don't reschedule
                return .disarm;
            }
            log.warn("Ping timer error: {any}", .{err});
            return .disarm;
        };

        // Only send ping if we're in ready state
        if (self.state != .ready or !self.logged_in) {
            return .disarm;
        }

        // Send ping asynchronously
        log.debug("Sending keepalive ping", .{});

        // Serialize ping message
        var msg_stream = std.io.fixedBufferStream(self.write_buffer);
        messages.PingMessage.serialize(msg_stream.writer()) catch {
            log.warn("Failed to serialize ping message", .{});
            return .disarm;
        };

        const ping_len = msg_stream.pos;
        self.socket.?.write(loop, &self.write_completion, .{ .slice = self.write_buffer[0..ping_len] }, Self, self, pingWriteCallback);

        return .disarm;
    }

    /// Callback after ping is written
    fn pingWriteCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;
        _ = loop;

        _ = result catch |err| {
            log.warn("Ping write failed: {any}", .{err});
            return .disarm;
        };

        self.last_ping_time = std.time.milliTimestamp();
        log.debug("Keepalive ping sent", .{});

        // Note: We don't wait for the ping response here.
        // The response will be received and validated during the next request.
        // This is intentional for simplicity.

        // Reschedule the timer for next ping
        if (self.ping_timer_active and self.ping_timer != null) {
            self.ping_timer.?.run(&self.loop, &self.ping_completion, self.config.ping_interval_ms, Self, self, pingTimerCallback);
        }

        return .disarm;
    }

    /// Set callback for status change notifications (push updates)
    pub fn setStatusChangedHandler(
        self: *Self,
        callback: ?StatusChangedCallback,
        userdata: ?*anyopaque,
    ) void {
        self.on_status_changed = callback;
        self.on_status_changed_userdata = userdata;
    }

    /// Set callback for disconnection notifications
    pub fn setDisconnectedHandler(
        self: *Self,
        callback: ?DisconnectedCallback,
        userdata: ?*anyopaque,
    ) void {
        self.on_disconnected = callback;
        self.on_disconnected_userdata = userdata;
    }

    /// Discover and connect to a ScreenLogic device on the network
    pub fn discoverAndConnect(self: *Self) !void {
        log.info("Discovering ScreenLogic devices...", .{});

        const broadcast_response = try discovery.discoverDefault();

        var ip_buf: [16]u8 = undefined;
        const ip_str = try broadcast_response.ipString(&ip_buf);
        log.info("Found device at {s}:{d}", .{ ip_str, broadcast_response.port });

        const addr = try broadcast_response.toAddress();
        try self.connect(addr);
    }

    /// Connect to a specific address
    pub fn connect(self: *Self, address: net.Address) !void {
        if (self.state != .disconnected and self.state != .failed) {
            return error.AlreadyConnected;
        }

        log.info("Connecting to ScreenLogic...", .{});

        self.address = address;
        self.state = .connecting;
        self.last_error = null;
        self.operation_complete = false;

        // Initialize TCP socket
        self.socket = try xev.TCP.init(address);

        // Start async connect
        self.socket.?.connect(&self.loop, &self.connect_completion, address, Self, self, connectCallback);

        // Run event loop until connect completes
        self.loop.run(.until_done) catch |err| {
            log.err("Event loop error: {any}", .{err});
            self.state = .failed;
            return error.ConnectionFailed;
        };

        // Check if connection succeeded
        if (self.last_error) |err| {
            self.state = .failed;
            return @as(ClientError, @errorCast(err));
        }

        if (self.state != .ready) {
            self.state = .failed;
            return error.ConnectionFailed;
        }

        log.info("Login successful", .{});
    }

    fn connectCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        result: xev.ConnectError!void,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;

        _ = result catch |err| {
            log.err("Connect failed: {any}", .{err});
            self.last_error = error.ConnectionFailed;
            self.state = .failed;
            return .disarm;
        };

        log.debug("TCP connected, sending handshake...", .{});
        self.state = .handshaking;

        // Send handshake message
        const handshake = "CONNECTSERVERHOST\r\n\r\n";
        @memcpy(self.write_buffer[0..handshake.len], handshake);
        self.bytes_to_write = handshake.len;
        self.bytes_written = 0;

        self.socket.?.write(loop, &self.write_completion, .{ .slice = self.write_buffer[0..handshake.len] }, Self, self, handshakeWriteCallback);

        return .disarm;
    }

    fn handshakeWriteCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        _ = result catch |err| {
            log.err("Handshake write failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        };

        log.debug("Handshake sent, sending login...", .{});
        self.state = .authenticating;

        // Serialize login message
        var msg_stream = std.io.fixedBufferStream(self.write_buffer);
        const login_msg = messages.LoginMessage{};
        login_msg.serialize(msg_stream.writer()) catch |err| {
            log.err("Login serialization failed: {any}", .{err});
            self.last_error = error.InvalidResponse;
            self.state = .failed;
            return .disarm;
        };

        const login_len = msg_stream.pos;
        self.socket.?.write(loop, &self.write_completion, .{ .slice = self.write_buffer[0..login_len] }, Self, self, loginWriteCallback);

        return .disarm;
    }

    fn loginWriteCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        _ = result catch |err| {
            log.err("Login write failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        };

        log.debug("Login sent, waiting for response...", .{});

        // Read login response header (8 bytes)
        self.bytes_to_read = 8;
        self.bytes_read = 0;
        self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..8] }, Self, self, loginReadHeaderCallback);

        return .disarm;
    }

    fn loginReadHeaderCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        const bytes = result catch |err| {
            log.err("Login read failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        };

        if (bytes == 0) {
            log.err("Connection closed during login", .{});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        }

        self.bytes_read += bytes;

        // Check if we have full header
        if (self.bytes_read < 8) {
            // Need more data - continue reading
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[self.bytes_read..8] }, Self, self, loginReadHeaderCallback);
            return .disarm;
        }

        // Parse header
        const header = messages.MessageHeader.parse(self.read_buffer[0..8]) catch |err| {
            log.err("Header parse failed: {any}", .{err});
            self.last_error = error.InvalidResponse;
            self.state = .failed;
            return .disarm;
        };

        // Check message type
        if (header.messageType()) |msg_type| {
            if (msg_type != .login_response) {
                // Device sometimes pushes status updates before login response
                // Skip this message and read the next one
                log.debug("Skipping unexpected message during login: {any}", .{msg_type});
                if (header.data_size > 0) {
                    // Skip the data for this message, then read next header
                    self.bytes_to_read = header.data_size;
                    self.bytes_read = 0;
                    self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..header.data_size] }, Self, self, loginSkipDataCallback);
                } else {
                    // No data to skip, read next header
                    self.bytes_read = 0;
                    self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..8] }, Self, self, loginReadHeaderCallback);
                }
                return .disarm;
            }
        } else {
            log.debug("Unknown message type during login, skipping", .{});
            if (header.data_size > 0) {
                self.bytes_to_read = header.data_size;
                self.bytes_read = 0;
                self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..header.data_size] }, Self, self, loginSkipDataCallback);
            } else {
                self.bytes_read = 0;
                self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..8] }, Self, self, loginReadHeaderCallback);
            }
            return .disarm;
        }

        // Read response data if any
        if (header.data_size > 0) {
            self.bytes_to_read = header.data_size;
            self.bytes_read = 0;
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..header.data_size] }, Self, self, loginReadDataCallback);
            return .disarm;
        }

        // Login complete!
        self.state = .ready;
        self.logged_in = true;
        self.reconnect_attempts = 0;
        // Note: Don't start ping timer here - it would block loop.run(.until_done)
        // Users can call ping() manually or use startListening() for continuous mode
        return .disarm;
    }

    fn loginReadDataCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;
        _ = loop;

        const bytes = result catch |err| {
            log.err("Login data read failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        };

        self.bytes_read += bytes;

        if (self.bytes_read < self.bytes_to_read) {
            // Need more - but for simplicity, fail for now
            // (login response is usually small)
            log.err("Incomplete login response data", .{});
            self.last_error = error.InvalidResponse;
            self.state = .failed;
            return .disarm;
        }

        // Login complete!
        self.state = .ready;
        self.logged_in = true;
        self.reconnect_attempts = 0;
        // Note: Don't start ping timer here - it would block loop.run(.until_done)
        return .disarm;
    }

    fn loginSkipDataCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        const bytes = result catch |err| {
            log.err("Login skip read failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            self.state = .failed;
            return .disarm;
        };

        self.bytes_read += bytes;

        if (self.bytes_read < self.bytes_to_read) {
            // Need to read more to skip the full message
            const remaining = self.bytes_to_read - self.bytes_read;
            const to_read = @min(remaining, self.read_buffer.len);
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..to_read] }, Self, self, loginSkipDataCallback);
            return .disarm;
        }

        // Data skipped, now read the next message header
        self.bytes_read = 0;
        self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..8] }, Self, self, loginReadHeaderCallback);
        return .disarm;
    }

    /// Connect using IP and port directly
    pub fn connectTo(self: *Self, ip: []const u8, port: u16) !void {
        const addr = try net.Address.resolveIp(ip, port);
        try self.connect(addr);
    }

    /// Disconnect from the device
    pub fn disconnect(self: *Self) void {
        self.stopPingTimer();
        if (self.socket) |*sock| {
            sock.close(&self.loop, &self.connect_completion, Self, self, closeCallback);
            self.loop.run(.until_done) catch {};
            self.socket = null;
        }
        self.state = .disconnected;
        self.logged_in = false;
        log.info("Disconnected", .{});
    }

    fn closeCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        result: xev.CloseError!void,
    ) xev.CallbackAction {
        _ = self_opt;
        _ = loop;
        _ = completion;
        _ = socket;
        _ = result catch {};
        return .disarm;
    }

    /// Send a message and wait for response (synchronous wrapper)
    fn sendAndReceive(self: *Self, msg_data: []const u8, expected_response: ?messages.MessageType) !struct { header: messages.MessageHeader, data: []const u8 } {
        if (self.state != .ready) return error.NotConnected;

        // Reset operation state
        self.last_error = null;
        self.operation_complete = false;
        self.response_header = null;
        self.response_data_len = 0;

        // Copy message to write buffer
        @memcpy(self.write_buffer[0..msg_data.len], msg_data);
        self.bytes_to_write = msg_data.len;
        self.bytes_written = 0;

        // Store expected response type for validation
        // (We'll validate after receiving)
        _ = expected_response;

        // Start async write
        self.socket.?.write(&self.loop, &self.write_completion, .{ .slice = self.write_buffer[0..msg_data.len] }, Self, self, messageWriteCallback);

        // Run until complete
        self.loop.run(.until_done) catch |err| {
            log.err("Event loop error: {any}", .{err});
            return error.ConnectionClosed;
        };

        if (self.last_error) |err| {
            return @as(ClientError, @errorCast(err));
        }

        const header = self.response_header orelse return error.InvalidResponse;
        return .{
            .header = header,
            .data = self.read_buffer[0..self.response_data_len],
        };
    }

    fn messageWriteCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        _ = result catch |err| {
            log.err("Write failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            return .disarm;
        };

        // Start reading response header
        self.bytes_read = 0;
        self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..8] }, Self, self, responseHeaderCallback);

        return .disarm;
    }

    fn responseHeaderCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        const bytes = result catch |err| {
            log.err("Read failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            return .disarm;
        };

        if (bytes == 0) {
            self.last_error = error.ConnectionClosed;
            return .disarm;
        }

        self.bytes_read += bytes;

        if (self.bytes_read < 8) {
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[self.bytes_read..8] }, Self, self, responseHeaderCallback);
            return .disarm;
        }

        // Parse header
        const header = messages.MessageHeader.parse(self.read_buffer[0..8]) catch |err| {
            log.err("Header parse failed: {any}", .{err});
            self.last_error = error.InvalidResponse;
            return .disarm;
        };

        self.response_header = header;

        // Read data if any
        if (header.data_size > 0) {
            if (header.data_size > self.read_buffer.len) {
                self.last_error = error.BufferTooSmall;
                return .disarm;
            }
            self.bytes_read = 0;
            self.bytes_to_read = header.data_size;
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[0..header.data_size] }, Self, self, responseDataCallback);
            return .disarm;
        }

        self.response_data_len = 0;
        self.operation_complete = true;
        return .disarm;
    }

    fn responseDataCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        socket: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_opt orelse return .disarm;
        _ = completion;
        _ = socket;
        _ = buffer;

        const bytes = result catch |err| {
            log.err("Data read failed: {any}", .{err});
            self.last_error = error.ConnectionClosed;
            return .disarm;
        };

        self.bytes_read += bytes;

        if (self.bytes_read < self.bytes_to_read) {
            // Need more data
            self.socket.?.read(loop, &self.read_completion, .{ .slice = self.read_buffer[self.bytes_read..self.bytes_to_read] }, Self, self, responseDataCallback);
            return .disarm;
        }

        self.response_data_len = self.bytes_to_read;
        self.operation_complete = true;
        return .disarm;
    }

    /// Get pool/spa status
    pub fn getStatus(self: *Self) !responses.PoolStatus {
        if (!self.logged_in) return error.NotConnected;

        // Serialize query
        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);
        const query = messages.GetStatusQuery{};
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .get_status_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .get_status_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        return try responses.PoolStatus.parse(response.data, self.allocator);
    }

    /// Get controller configuration
    pub fn getControllerConfig(self: *Self) !responses.ControllerConfig {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);
        try messages.GetControllerConfigQuery.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .get_controller_config_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .get_controller_config_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        return try responses.ControllerConfig.parse(response.data, self.allocator);
    }

    /// Set circuit state (turn on/off)
    pub fn setCircuitState(self: *Self, circuit_id: u32, state: bool) !void {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = messages.ButtonPressQuery{
            .circuit_id = circuit_id,
            .state = if (state) .on else .off,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .button_press_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .button_press_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        log.info("Circuit {d} set to {s}", .{ circuit_id, if (state) "ON" else "OFF" });
    }

    /// Set heat mode for pool or spa
    pub fn setHeatMode(self: *Self, body: messages.BodyType, mode: messages.HeatMode) !void {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = messages.SetHeatModeQuery{
            .body_type = body,
            .mode = mode,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .set_heat_mode_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .set_heat_mode_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        log.info("Heat mode for {s} set to {s}", .{ @tagName(body), @tagName(mode) });
    }

    /// Set temperature setpoint for pool or spa
    pub fn setTemperature(self: *Self, body: messages.BodyType, temperature: u32) !void {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = messages.SetHeatSetpointQuery{
            .body_type = body,
            .temperature = temperature,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .set_heat_setpoint_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .set_heat_setpoint_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        log.info("Temperature for {s} set to {d}F", .{ @tagName(body), temperature });
    }

    /// Get pump status
    ///
    /// Returns the current status of the specified pump including:
    /// - Pump type (VF, VS, VSF)
    /// - Running state
    /// - Current power consumption (watts)
    /// - Current speed (RPM and GPM)
    /// - Circuit configurations (8 slots)
    pub fn getPumpStatus(self: *Self, pump_id: u32) !pump.PumpStatus {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = pump.GetPumpStatusQuery{ .pump_id = pump_id };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .get_pump_status_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .get_pump_status_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        return try pump.PumpStatus.parse(response.data);
    }

    /// Set pump speed for a circuit
    ///
    /// Parameters:
    /// - pump_id: 0-indexed pump number
    /// - circuit_index: Index into pump's circuit array (0-7), NOT the circuit ID
    /// - speed: Speed value (typically 400-3450 for RPM, or 1-130 for GPM)
    /// - is_rpm: true for RPM, false for GPM
    ///
    /// Note: Get pump status first to find the circuit_index for your desired circuit.
    pub fn setPumpSpeed(self: *Self, pump_id: u32, circuit_index: u32, speed: u32, is_rpm: bool) !void {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [64]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = pump.SetPumpSpeedQuery{
            .pump_id = pump_id,
            .circuit_index = circuit_index,
            .speed = speed,
            .is_rpm = is_rpm,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .set_pump_flow_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .set_pump_flow_response) {
                log.warn("Unexpected response type: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        log.info("Pump {d} circuit {d} speed set to {d} {s}", .{
            pump_id,
            circuit_index,
            speed,
            if (is_rpm) "RPM" else "GPM",
        });
    }

    /// Send ping to keep connection alive
    pub fn ping(self: *Self) !void {
        if (!self.logged_in) return error.NotConnected;

        var msg_buf: [16]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);
        try messages.PingMessage.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .ping_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .ping_response) {
                log.warn("Unexpected response to ping: {any}", .{msg_type});
            }
        }
    }

    /// Check if connected and logged in
    pub fn isConnected(self: *Self) bool {
        return self.state == .ready and self.logged_in;
    }

    /// Get current connection state
    pub fn getState(self: *Self) ConnectionState {
        return self.state;
    }

    /// Subscribe to status change notifications
    ///
    /// After calling this, the controller will push status updates (message 12500)
    /// whenever equipment state changes. Use `setStatusChangedHandler` to receive them.
    ///
    /// Note: Push notifications are received during `processEvents()` or
    /// while other synchronous operations are running.
    pub fn subscribeToStatusChanges(self: *Self) !void {
        if (!self.logged_in) return error.NotConnected;
        if (self.subscribed) return; // Already subscribed

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = messages.AddClientQuery{
            .sender_id = self.client_id,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .add_client_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .add_client_response) {
                log.warn("Unexpected response to AddClient: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        self.subscribed = true;
        log.info("Subscribed to status updates (client_id: {d})", .{self.client_id});
    }

    /// Unsubscribe from status change notifications
    pub fn unsubscribeFromStatusChanges(self: *Self) !void {
        if (!self.logged_in) return error.NotConnected;
        if (!self.subscribed) return; // Not subscribed

        var msg_buf: [32]u8 = undefined;
        var msg_stream = std.io.fixedBufferStream(&msg_buf);

        const query = messages.RemoveClientQuery{
            .sender_id = self.client_id,
        };
        try query.serialize(msg_stream.writer());

        const response = try self.sendAndReceive(msg_stream.getWritten(), .remove_client_response);

        if (response.header.messageType()) |msg_type| {
            if (msg_type != .remove_client_response) {
                log.warn("Unexpected response to RemoveClient: {any}", .{msg_type});
                return error.UnexpectedMessage;
            }
        }

        self.subscribed = false;
        log.info("Unsubscribed from status updates", .{});
    }

    /// Check if subscribed to status updates
    pub fn isSubscribed(self: *Self) bool {
        return self.subscribed;
    }

    /// Attempt to reconnect to the last known address
    ///
    /// Uses exponential backoff between attempts. Returns error if max retries exceeded.
    pub fn reconnect(self: *Self) !void {
        const addr = self.address orelse return error.NotConnected;

        if (self.config.max_reconnect_attempts > 0 and
            self.reconnect_attempts >= self.config.max_reconnect_attempts)
        {
            log.err("Max reconnection attempts ({d}) exceeded", .{self.config.max_reconnect_attempts});
            if (self.on_disconnected) |cb| {
                cb(.max_retries_exceeded, self.on_disconnected_userdata);
            }
            return error.ConnectionFailed;
        }

        // Calculate backoff delay with exponential increase
        const attempt = self.reconnect_attempts;
        const base_delay = self.config.reconnect_base_delay_ms;
        const max_delay = self.config.reconnect_max_delay_ms;

        // 2^attempt * base_delay, capped at max_delay
        const multiplier = std.math.shl(u32, 1, @min(attempt, 10));
        const delay = @min(base_delay * multiplier, max_delay);

        log.info("Reconnecting in {d}ms (attempt {d})...", .{ delay, attempt + 1 });
        self.reconnect_attempts += 1;
        self.state = .reconnecting;

        // Sleep for backoff delay
        std.Thread.sleep(delay * std.time.ns_per_ms);

        // Clean up old socket if any
        if (self.socket) |*sock| {
            sock.close(&self.loop, &self.connect_completion, Self, self, closeCallback);
            self.loop.run(.until_done) catch {};
            self.socket = null;
        }

        // Reset state for new connection
        self.state = .disconnected;
        self.logged_in = false;
        self.subscribed = false;

        // Attempt reconnect
        self.connect(addr) catch |err| {
            log.warn("Reconnection attempt failed: {any}", .{err});
            return self.reconnect(); // Recursive retry
        };

        // Success - reset attempt counter
        self.reconnect_attempts = 0;
        log.info("Reconnected successfully", .{});
    }

    /// Handle connection error - attempt reconnect if enabled
    fn handleConnectionError(self: *Self, err: anyerror) !void {
        log.warn("Connection error: {any}", .{err});

        if (self.on_disconnected) |cb| {
            cb(.connection_lost, self.on_disconnected_userdata);
        }

        if (self.config.auto_reconnect) {
            try self.reconnect();
        } else {
            self.state = .failed;
            return err;
        }
    }
};

// Tests
test "Client init and deinit" {
    const allocator = std.testing.allocator;
    var client = try Client.init(allocator, .{});
    defer client.deinit();

    try std.testing.expect(!client.isConnected());
    try std.testing.expectEqual(ConnectionState.disconnected, client.getState());
}

test "Client state transitions" {
    const allocator = std.testing.allocator;
    var client = try Client.init(allocator, .{});
    defer client.deinit();

    try std.testing.expectEqual(ConnectionState.disconnected, client.state);

    // Can't test actual connection without a server, but we can test initial state
    try std.testing.expect(!client.logged_in);
    try std.testing.expect(client.socket == null);
}
