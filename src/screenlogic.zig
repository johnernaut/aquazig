/// ScreenLogic - A Zig library for communicating with Pentair ScreenLogic pool controllers
///
/// This library provides a clean, type-safe API for:
/// - Discovering ScreenLogic devices on the local network
/// - Connecting and authenticating
/// - Reading pool/spa status and configuration
/// - Controlling circuits (pumps, lights, etc.)
/// - Adjusting temperature settings
///
/// Example usage:
/// ```zig
/// const screenlogic = @import("screenlogic");
///
/// var client = try screenlogic.Client.init(allocator, .{});
/// defer client.deinit();
///
/// try client.discoverAndConnect();
///
/// const status = try client.getStatus();
/// defer status.deinit();
///
/// if (status.bodies.pool) |pool| {
///     std.debug.print("Pool temp: {d}F\n", .{pool.current_temp});
/// }
/// ```

const std = @import("std");

// Core client
pub const Client = @import("client.zig").Client;
pub const ClientConfig = @import("client.zig").ClientConfig;
pub const ClientError = @import("client.zig").ClientError;

// Discovery
pub const discovery = @import("discovery.zig");
pub const BroadcastResponse = discovery.BroadcastResponse;
pub const DiscoveryConfig = discovery.DiscoveryConfig;
pub const discover = discovery.discover;
pub const discoverDefault = discovery.discoverDefault;

// Protocol types
pub const protocol = struct {
    pub const messages = @import("protocol/messages.zig");
    pub const encoding = @import("protocol/encoding.zig");
    pub const responses = @import("protocol/responses.zig");
    pub const pump = @import("protocol/pump.zig");
    pub const schedule = @import("protocol/schedule.zig");
};

// Re-export commonly used types
pub const MessageType = protocol.messages.MessageType;
pub const MessageHeader = protocol.messages.MessageHeader;
pub const BodyType = protocol.messages.BodyType;
pub const HeatMode = protocol.messages.HeatMode;
pub const CircuitState = protocol.messages.CircuitState;

pub const PoolStatus = protocol.responses.PoolStatus;
pub const ControllerConfig = protocol.responses.ControllerConfig;
pub const BodyStatus = protocol.responses.BodyStatus;
pub const Circuit = protocol.responses.Circuit;
pub const ChemData = protocol.responses.ChemData;

// Pump types
pub const PumpStatus = protocol.pump.PumpStatus;
pub const PumpType = protocol.pump.PumpType;
pub const PumpCircuit = protocol.pump.PumpCircuit;

// Schedule types
pub const Schedule = protocol.schedule.Schedule;
pub const ScheduledEvent = protocol.schedule.ScheduledEvent;
pub const DayMask = protocol.schedule.DayMask;
pub const HeatCommand = protocol.schedule.HeatCommand;

// Version info
pub const version = "0.1.0";

/// Create a new ScreenLogic client with default configuration
pub fn createClient(allocator: std.mem.Allocator) !Client {
    return Client.init(allocator, .{});
}

/// Create a new ScreenLogic client with custom configuration
pub fn createClientWithConfig(allocator: std.mem.Allocator, config: ClientConfig) !Client {
    return Client.init(allocator, config);
}

// Tests
test {
    // Run all tests from submodules
    _ = @import("discovery.zig");
    _ = @import("client.zig");
    _ = @import("protocol/encoding.zig");
    _ = @import("protocol/messages.zig");
    _ = @import("protocol/responses.zig");
    _ = @import("protocol/pump.zig");
    _ = @import("protocol/schedule.zig");
}

test "library version" {
    try std.testing.expectEqualStrings("0.1.0", version);
}
