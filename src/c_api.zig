// AquaZig C-ABI Export Layer
//
// This module provides a C-compatible interface for Swift/Objective-C interop.
// All exported functions use C calling conventions and simple types.
//
// Design patterns (from Ghostty):
// - Opaque handle pattern for Client
// - extern struct for C ABI-compatible memory layout
// - Error codes as c_int return values
// - Callback function pointers with userdata

const std = @import("std");
const Client = @import("client.zig").Client;
const ClientConfig = @import("client.zig").ClientConfig;
const ClientError = @import("client.zig").ClientError;
const ConnectionState = @import("client.zig").ConnectionState;
const responses = @import("protocol/responses.zig");
const pump_mod = @import("protocol/pump.zig");
const messages = @import("protocol/messages.zig");

// ============================================================================
// Error Codes
// ============================================================================

pub const AQUAZIG_OK: c_int = 0;
pub const AQUAZIG_ERR_NOT_CONNECTED: c_int = -1;
pub const AQUAZIG_ERR_LOGIN_FAILED: c_int = -2;
pub const AQUAZIG_ERR_INVALID_RESPONSE: c_int = -3;
pub const AQUAZIG_ERR_UNEXPECTED_MESSAGE: c_int = -4;
pub const AQUAZIG_ERR_TIMEOUT: c_int = -5;
pub const AQUAZIG_ERR_CONNECTION_CLOSED: c_int = -6;
pub const AQUAZIG_ERR_BUFFER_TOO_SMALL: c_int = -7;
pub const AQUAZIG_ERR_OUT_OF_MEMORY: c_int = -8;
pub const AQUAZIG_ERR_CONNECTION_FAILED: c_int = -9;
pub const AQUAZIG_ERR_ALREADY_CONNECTED: c_int = -10;
pub const AQUAZIG_ERR_UNKNOWN: c_int = -99;

fn errorToCode(err: anyerror) c_int {
    return switch (err) {
        ClientError.NotConnected => AQUAZIG_ERR_NOT_CONNECTED,
        ClientError.LoginFailed => AQUAZIG_ERR_LOGIN_FAILED,
        ClientError.InvalidResponse => AQUAZIG_ERR_INVALID_RESPONSE,
        ClientError.UnexpectedMessage => AQUAZIG_ERR_UNEXPECTED_MESSAGE,
        ClientError.Timeout => AQUAZIG_ERR_TIMEOUT,
        ClientError.ConnectionClosed => AQUAZIG_ERR_CONNECTION_CLOSED,
        ClientError.BufferTooSmall => AQUAZIG_ERR_BUFFER_TOO_SMALL,
        ClientError.OutOfMemory => AQUAZIG_ERR_OUT_OF_MEMORY,
        ClientError.ConnectionFailed => AQUAZIG_ERR_CONNECTION_FAILED,
        ClientError.AlreadyConnected => AQUAZIG_ERR_ALREADY_CONNECTED,
        else => AQUAZIG_ERR_UNKNOWN,
    };
}

// ============================================================================
// Opaque Handle Type
// ============================================================================

/// Opaque client handle for C/Swift interop
pub const aquazig_client_t = opaque {};

// ============================================================================
// C-Compatible Data Structures
// ============================================================================

/// Body (pool/spa) status - C-compatible
pub const aquazig_body_status_t = extern struct {
    current_temp: i32,
    heat_setpoint: i32,
    cool_setpoint: i32,
    heat_mode: u32, // 0=off, 1=solar, 2=solar_preferred, 3=heater
    heat_status: bool,
    is_valid: bool, // true if this body exists
};

/// Pool status - C-compatible
pub const aquazig_pool_status_t = extern struct {
    ok: bool,
    freeze_mode: bool,
    air_temp: i32,
    pool: aquazig_body_status_t,
    spa: aquazig_body_status_t,
    // Chemistry (optional - check values > 0)
    ph: f32, // 0 if not available
    orp: i32, // 0 if not available
    salt_ppm: i32, // 0 if not available
    saturation: f32, // 0 if not available
};

/// Pump circuit configuration - C-compatible
pub const aquazig_pump_circuit_t = extern struct {
    circuit_id: u32,
    speed: u32,
    is_rpm: bool,
};

/// Pump status - C-compatible
pub const aquazig_pump_status_t = extern struct {
    pump_type: u32, // 0=unknown, 1=VF, 2=VS, 3=VSF
    is_running: bool,
    watts: u32,
    rpm: u32,
    gpm: u32,
    circuits: [8]aquazig_pump_circuit_t,
};

/// Circuit info - C-compatible
pub const aquazig_circuit_t = extern struct {
    id: u32,
    state: bool,
    // Name is returned separately via aquazig_get_circuit_name
};

/// Callback type for status change notifications
pub const aquazig_status_callback_t = *const fn (
    userdata: ?*anyopaque,
    status: *const aquazig_pool_status_t,
) callconv(.c) void;

/// Callback type for disconnect notifications
pub const aquazig_disconnect_callback_t = *const fn (
    userdata: ?*anyopaque,
    reason: c_int, // 0=normal, 1=connection_lost, 2=timeout, 3=max_retries
) callconv(.c) void;

// ============================================================================
// Client Lifecycle
// ============================================================================

/// Create a new AquaZig client
///
/// Returns: Opaque client handle, or null on failure
export fn aquazig_client_create() ?*aquazig_client_t {
    const client = Client.init(std.heap.c_allocator, .{}) catch return null;
    // Store the client on the heap
    const client_ptr = std.heap.c_allocator.create(Client) catch return null;
    client_ptr.* = client;
    return @ptrCast(client_ptr);
}

/// Create a new AquaZig client with custom configuration
///
/// Parameters:
/// - timeout_ms: Connection/operation timeout in milliseconds
/// - ping_interval_ms: Keepalive ping interval (0 to disable)
/// - auto_reconnect: Enable automatic reconnection
/// - max_reconnect_attempts: Maximum reconnection attempts (0 for unlimited)
///
/// Returns: Opaque client handle, or null on failure
export fn aquazig_client_create_with_config(
    timeout_ms: u32,
    ping_interval_ms: u32,
    auto_reconnect: bool,
    max_reconnect_attempts: u32,
) ?*aquazig_client_t {
    const config = ClientConfig{
        .timeout_ms = timeout_ms,
        .ping_interval_ms = ping_interval_ms,
        .auto_reconnect = auto_reconnect,
        .max_reconnect_attempts = max_reconnect_attempts,
    };
    const client = Client.init(std.heap.c_allocator, config) catch return null;
    const client_ptr = std.heap.c_allocator.create(Client) catch return null;
    client_ptr.* = client;
    return @ptrCast(client_ptr);
}

/// Free an AquaZig client
///
/// This disconnects if connected and releases all resources.
export fn aquazig_client_free(handle: ?*aquazig_client_t) void {
    const client = castClient(handle) orelse return;
    client.deinit();
    std.heap.c_allocator.destroy(client);
}

// ============================================================================
// Connection
// ============================================================================

/// Discover and connect to a ScreenLogic device on the local network
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_discover_and_connect(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.discoverAndConnect() catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Connect to a ScreenLogic device at a specific IP and port
///
/// Parameters:
/// - host: Null-terminated IP address string (e.g., "192.168.1.100")
/// - port: Port number (typically 80)
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_connect(
    handle: ?*aquazig_client_t,
    host: [*:0]const u8,
    port: u16,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    const host_slice = std.mem.span(host);
    client.connectTo(host_slice, port) catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Disconnect from the device
export fn aquazig_disconnect(handle: ?*aquazig_client_t) void {
    const client = castClient(handle) orelse return;
    client.disconnect();
}

/// Check if connected and logged in
///
/// Returns: true if connected, false otherwise
export fn aquazig_is_connected(handle: ?*aquazig_client_t) bool {
    const client = castClient(handle) orelse return false;
    return client.isConnected();
}

/// Get current connection state
///
/// Returns: 0=disconnected, 1=connecting, 2=handshaking, 3=authenticating,
///          4=ready, 5=reconnecting, 6=failed
export fn aquazig_get_state(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return 0;
    return switch (client.getState()) {
        .disconnected => 0,
        .connecting => 1,
        .handshaking => 2,
        .authenticating => 3,
        .ready => 4,
        .reconnecting => 5,
        .failed => 6,
    };
}

/// Attempt to reconnect to the last known address
///
/// Uses exponential backoff between attempts.
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_reconnect(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.reconnect() catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

// ============================================================================
// Status
// ============================================================================

/// Get pool/spa status
///
/// Parameters:
/// - out_status: Pointer to status struct to fill
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_get_status(
    handle: ?*aquazig_client_t,
    out_status: ?*aquazig_pool_status_t,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    const out = out_status orelse return AQUAZIG_ERR_INVALID_RESPONSE;

    var status = client.getStatus() catch |err| {
        return errorToCode(err);
    };
    defer status.deinit();

    // Convert to C struct
    out.* = convertPoolStatus(&status);
    return AQUAZIG_OK;
}

/// Send ping to keep connection alive
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_ping(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.ping() catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

// ============================================================================
// Control
// ============================================================================

/// Set circuit state (turn on/off)
///
/// Parameters:
/// - circuit_id: Circuit ID (e.g., 505 for Pool, 500 for Spa)
/// - state: true = on, false = off
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_set_circuit_state(
    handle: ?*aquazig_client_t,
    circuit_id: u32,
    state: bool,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.setCircuitState(circuit_id, state) catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Set heat mode for pool or spa
///
/// Parameters:
/// - body_id: 0 = pool, 1 = spa
/// - mode: 0=off, 1=solar, 2=solar_preferred, 3=heater
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_set_heat_mode(
    handle: ?*aquazig_client_t,
    body_id: u32,
    mode: u32,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;

    const body_type: messages.BodyType = if (body_id == 0) .pool else .spa;
    const heat_mode = messages.HeatMode.fromInt(mode) orelse .off;

    client.setHeatMode(body_type, heat_mode) catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Set temperature setpoint for pool or spa
///
/// Parameters:
/// - body_id: 0 = pool, 1 = spa
/// - temperature: Target temperature in current units (F or C)
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_set_heat_setpoint(
    handle: ?*aquazig_client_t,
    body_id: u32,
    temperature: u32,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;

    const body_type: messages.BodyType = if (body_id == 0) .pool else .spa;

    client.setTemperature(body_type, temperature) catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

// ============================================================================
// Pump
// ============================================================================

/// Get pump status
///
/// Parameters:
/// - pump_id: 0-indexed pump number
/// - out_status: Pointer to pump status struct to fill
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_get_pump_status(
    handle: ?*aquazig_client_t,
    pump_id: u32,
    out_status: ?*aquazig_pump_status_t,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    const out = out_status orelse return AQUAZIG_ERR_INVALID_RESPONSE;

    const pump_status = client.getPumpStatus(pump_id) catch |err| {
        return errorToCode(err);
    };

    // Convert to C struct
    out.* = convertPumpStatus(&pump_status);
    return AQUAZIG_OK;
}

/// Set pump speed for a circuit
///
/// Parameters:
/// - pump_id: 0-indexed pump number
/// - circuit_index: Index into pump's circuit array (0-7)
/// - speed: Speed value (RPM: 400-3450, GPM: 1-130)
/// - is_rpm: true for RPM mode, false for GPM mode
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_set_pump_speed(
    handle: ?*aquazig_client_t,
    pump_id: u32,
    circuit_index: u32,
    speed: u32,
    is_rpm: bool,
) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.setPumpSpeed(pump_id, circuit_index, speed, is_rpm) catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

// ============================================================================
// Subscriptions
// ============================================================================

/// Subscribe to status change notifications
///
/// After calling this, the controller will push status updates.
/// Use aquazig_set_status_callback to receive them.
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_subscribe_status(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.subscribeToStatusChanges() catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Unsubscribe from status change notifications
///
/// Returns: AQUAZIG_OK on success, error code on failure
export fn aquazig_unsubscribe_status(handle: ?*aquazig_client_t) c_int {
    const client = castClient(handle) orelse return AQUAZIG_ERR_NOT_CONNECTED;
    client.unsubscribeFromStatusChanges() catch |err| {
        return errorToCode(err);
    };
    return AQUAZIG_OK;
}

/// Check if subscribed to status updates
///
/// Returns: true if subscribed, false otherwise
export fn aquazig_is_subscribed(handle: ?*aquazig_client_t) bool {
    const client = castClient(handle) orelse return false;
    return client.isSubscribed();
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Cast opaque handle to Client pointer
fn castClient(handle: ?*aquazig_client_t) ?*Client {
    const ptr = handle orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Convert PoolStatus to C-compatible struct
fn convertPoolStatus(status: *const responses.PoolStatus) aquazig_pool_status_t {
    var result = aquazig_pool_status_t{
        .ok = status.ok,
        .freeze_mode = status.freeze_mode,
        .air_temp = status.air_temp,
        .pool = .{
            .current_temp = 0,
            .heat_setpoint = 0,
            .cool_setpoint = 0,
            .heat_mode = 0,
            .heat_status = false,
            .is_valid = false,
        },
        .spa = .{
            .current_temp = 0,
            .heat_setpoint = 0,
            .cool_setpoint = 0,
            .heat_mode = 0,
            .heat_status = false,
            .is_valid = false,
        },
        .ph = if (status.ph) |p| p else 0,
        .orp = if (status.orp) |o| o else 0,
        .salt_ppm = if (status.salt_ppm) |s| s else 0,
        .saturation = if (status.saturation) |s| s else 0,
    };

    if (status.bodies.pool) |pool| {
        result.pool = .{
            .current_temp = pool.current_temp,
            .heat_setpoint = pool.heat_setpoint,
            .cool_setpoint = pool.cool_setpoint,
            .heat_mode = @intFromEnum(pool.heat_mode),
            .heat_status = pool.heat_status,
            .is_valid = true,
        };
    }

    if (status.bodies.spa) |spa| {
        result.spa = .{
            .current_temp = spa.current_temp,
            .heat_setpoint = spa.heat_setpoint,
            .cool_setpoint = spa.cool_setpoint,
            .heat_mode = @intFromEnum(spa.heat_mode),
            .heat_status = spa.heat_status,
            .is_valid = true,
        };
    }

    return result;
}

/// Convert PumpStatus to C-compatible struct
fn convertPumpStatus(status: *const pump_mod.PumpStatus) aquazig_pump_status_t {
    var result = aquazig_pump_status_t{
        .pump_type = @intFromEnum(status.pump_type),
        .is_running = status.is_running,
        .watts = status.watts,
        .rpm = status.rpm,
        .gpm = status.gpm,
        .circuits = undefined,
    };

    for (&result.circuits, 0..) |*c, i| {
        c.* = .{
            .circuit_id = status.circuits[i].circuit_id,
            .speed = status.circuits[i].speed,
            .is_rpm = status.circuits[i].is_rpm,
        };
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "error code conversion" {
    const testing = std.testing;

    try testing.expectEqual(AQUAZIG_ERR_NOT_CONNECTED, errorToCode(ClientError.NotConnected));
    try testing.expectEqual(AQUAZIG_ERR_TIMEOUT, errorToCode(ClientError.Timeout));
    try testing.expectEqual(AQUAZIG_ERR_CONNECTION_FAILED, errorToCode(ClientError.ConnectionFailed));
}

test "client create and free" {
    const handle = aquazig_client_create();
    try std.testing.expect(handle != null);

    try std.testing.expect(!aquazig_is_connected(handle));
    try std.testing.expectEqual(@as(c_int, 0), aquazig_get_state(handle)); // disconnected

    aquazig_client_free(handle);
}

test "operations on null handle return errors" {
    const testing = std.testing;

    try testing.expectEqual(AQUAZIG_ERR_NOT_CONNECTED, aquazig_discover_and_connect(null));
    try testing.expectEqual(AQUAZIG_ERR_NOT_CONNECTED, aquazig_ping(null));
    try testing.expect(!aquazig_is_connected(null));
}
