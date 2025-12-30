const std = @import("std");
const encoding = @import("encoding.zig");

// Pump Control Messages
//
// ScreenLogic supports IntelliFlo variable speed pumps. Pumps can have up to
// 8 circuit configurations, each with a speed setting in RPM or GPM mode.
//
// Message codes:
// - 12584: GetPumpStatus query
// - 12585: GetPumpStatus response
// - 12586: SetPumpSpeed query
// - 12587: SetPumpSpeed response

/// Pump type as reported by the controller
pub const PumpType = enum(u32) {
    unknown = 0,
    variable_flow = 1, // VF
    variable_speed = 2, // VS
    variable_speed_flow = 3, // VSF

    pub fn fromInt(val: u32) PumpType {
        return switch (val) {
            1 => .variable_flow,
            2 => .variable_speed,
            3 => .variable_speed_flow,
            else => .unknown,
        };
    }
};

/// A circuit configuration on a pump
pub const PumpCircuit = struct {
    circuit_id: u32,
    speed: u32,
    is_rpm: bool, // true = RPM, false = GPM
};

/// Pump status response data (message code 12585)
///
/// Wire format:
/// ```
/// | pump_type (u32)      | 1=VF, 2=VS, 3=VSF
/// | is_running (u32)     | 0=stopped, non-zero=running
/// | watts (u32)          | Current power consumption
/// | rpm (u32)            | Current RPM
/// | unknown1 (u32)       | Always 0
/// | gpm (u32)            | Current GPM (flow rate)
/// | unknown2 (u32)       | Always 255
/// | circuits[8]          | 8 circuit entries, each 12 bytes:
/// |   circuit_id (u32)   |
/// |   speed (u32)        |
/// |   is_rpm (u32)       | 0=GPM, non-zero=RPM
/// ```
pub const PumpStatus = struct {
    pump_type: PumpType,
    is_running: bool,
    watts: u32,
    rpm: u32,
    gpm: u32,
    circuits: [8]PumpCircuit,

    pub fn parse(data: []const u8) !PumpStatus {
        if (data.len < 7 * 4 + 8 * 12) return error.BufferTooSmall;

        var offset: usize = 0;

        const pump_type_val = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        const is_running_val = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        const watts = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        const rpm = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        // Skip unknown1 (always 0)
        offset += 4;

        const gpm = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        // Skip unknown2 (always 255)
        offset += 4;

        // Parse 8 circuit configurations
        var circuits: [8]PumpCircuit = undefined;
        for (&circuits) |*circuit| {
            circuit.circuit_id = std.mem.readInt(u32, data[offset..][0..4], .little);
            offset += 4;
            circuit.speed = std.mem.readInt(u32, data[offset..][0..4], .little);
            offset += 4;
            const is_rpm_val = std.mem.readInt(u32, data[offset..][0..4], .little);
            offset += 4;
            circuit.is_rpm = is_rpm_val != 0;
        }

        return PumpStatus{
            .pump_type = PumpType.fromInt(pump_type_val),
            .is_running = is_running_val != 0,
            .watts = watts,
            .rpm = rpm,
            .gpm = gpm,
            .circuits = circuits,
        };
    }
};

/// Get pump status query (message code 12584)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 8) |
/// | controller_index (u32 LE)       | Usually 0
/// | pump_id (u32 LE)                | 0-indexed pump number
/// ```
pub const GetPumpStatusQuery = struct {
    controller_index: u32 = 0,
    pump_id: u32, // 0-indexed

    pub fn serialize(self: GetPumpStatusQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12584); // get_pump_status_query
        try encoding.writeIntLE(u32, writer, 8); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, self.pump_id);
    }
};

/// Set pump speed query (message code 12586)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 20) |
/// | controller_index (u32 LE)        | Usually 0
/// | pump_id (u32 LE)                 | 0-indexed pump number
/// | circuit_index (u32 LE)           | Index into pump's circuit array (0-7)
/// | speed (u32 LE)                   | Speed value (RPM or GPM depending on is_rpm)
/// | is_rpm (u32 LE)                  | 1 = RPM, 0 = GPM
/// ```
///
/// Note: circuit_index refers to the index in the pump's circuit array,
/// not the circuit ID. Get the circuit configuration via GetPumpStatus first.
pub const SetPumpSpeedQuery = struct {
    controller_index: u32 = 0,
    pump_id: u32, // 0-indexed
    circuit_index: u32, // 0-7, index into pump's circuit array
    speed: u32,
    is_rpm: bool,

    pub fn serialize(self: SetPumpSpeedQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12586); // set_pump_speed_query
        try encoding.writeIntLE(u32, writer, 20); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, self.pump_id);
        try encoding.writeIntLE(u32, writer, self.circuit_index);
        try encoding.writeIntLE(u32, writer, self.speed);
        try encoding.writeIntLE(u32, writer, if (self.is_rpm) @as(u32, 1) else @as(u32, 0));
    }
};

// Tests
test "PumpStatus parse" {
    // Minimal test data for pump status
    var data: [7 * 4 + 8 * 12]u8 = undefined;
    var offset: usize = 0;

    // pump_type = 2 (VS)
    std.mem.writeInt(u32, data[offset..][0..4], 2, .little);
    offset += 4;
    // is_running = 1
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little);
    offset += 4;
    // watts = 500
    std.mem.writeInt(u32, data[offset..][0..4], 500, .little);
    offset += 4;
    // rpm = 2500
    std.mem.writeInt(u32, data[offset..][0..4], 2500, .little);
    offset += 4;
    // unknown1 = 0
    std.mem.writeInt(u32, data[offset..][0..4], 0, .little);
    offset += 4;
    // gpm = 50
    std.mem.writeInt(u32, data[offset..][0..4], 50, .little);
    offset += 4;
    // unknown2 = 255
    std.mem.writeInt(u32, data[offset..][0..4], 255, .little);
    offset += 4;

    // 8 circuits (all zeros for simplicity)
    for (0..8) |i| {
        std.mem.writeInt(u32, data[offset..][0..4], @intCast(i), .little); // circuit_id
        offset += 4;
        std.mem.writeInt(u32, data[offset..][0..4], 3000, .little); // speed
        offset += 4;
        std.mem.writeInt(u32, data[offset..][0..4], 1, .little); // is_rpm
        offset += 4;
    }

    const status = try PumpStatus.parse(&data);
    try std.testing.expectEqual(PumpType.variable_speed, status.pump_type);
    try std.testing.expect(status.is_running);
    try std.testing.expectEqual(@as(u32, 500), status.watts);
    try std.testing.expectEqual(@as(u32, 2500), status.rpm);
    try std.testing.expectEqual(@as(u32, 50), status.gpm);
    try std.testing.expectEqual(@as(u32, 0), status.circuits[0].circuit_id);
    try std.testing.expectEqual(@as(u32, 3000), status.circuits[0].speed);
    try std.testing.expect(status.circuits[0].is_rpm);
}

test "GetPumpStatusQuery serialize" {
    var buf: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const query = GetPumpStatusQuery{ .pump_id = 0 };
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try std.testing.expectEqual(@as(usize, 16), written.len);

    // Check message code
    const msg_code = std.mem.readInt(u16, written[2..4], .little);
    try std.testing.expectEqual(@as(u16, 12584), msg_code);

    // Check data size
    const data_size = std.mem.readInt(u32, written[4..8], .little);
    try std.testing.expectEqual(@as(u32, 8), data_size);
}

test "SetPumpSpeedQuery serialize" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const query = SetPumpSpeedQuery{
        .pump_id = 0,
        .circuit_index = 1,
        .speed = 2500,
        .is_rpm = true,
    };
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try std.testing.expectEqual(@as(usize, 28), written.len);

    // Check message code
    const msg_code = std.mem.readInt(u16, written[2..4], .little);
    try std.testing.expectEqual(@as(u16, 12586), msg_code);

    // Check data size
    const data_size = std.mem.readInt(u32, written[4..8], .little);
    try std.testing.expectEqual(@as(u32, 20), data_size);

    // Check is_rpm field
    const is_rpm = std.mem.readInt(u32, written[24..28], .little);
    try std.testing.expectEqual(@as(u32, 1), is_rpm);
}
