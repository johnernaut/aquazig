const std = @import("std");
const testing = std.testing;
const encoding = @import("encoding.zig");

// ScreenLogic Message Types and Serialization
//
// All TCP communication with ScreenLogic uses a common message framing format.
// Messages are preceded by an 8-byte header, followed by variable-length data.
//
// Reference: protocol_document.pdf and github.com/parnic/node-screenlogic

/// Message header structure - all messages start with this 8-byte header
///
/// Wire format:
/// ```
/// | Offset | Size | Field      | Description                              |
/// |--------|------|------------|------------------------------------------|
/// | 0      | 2    | msg_code_1 | Usually 0, sometimes sender ID           |
/// | 2      | 2    | msg_code_2 | Message type identifier (see MessageType)|
/// | 4      | 4    | data_size  | Byte count of payload following header   |
/// ```
///
/// The message type is identified primarily by msg_code_2. For queries, msg_code_1
/// is typically 0. For responses, both codes may be set to the same value.
pub const MessageHeader = struct {
    msg_code_1: u16,
    msg_code_2: u16,
    data_size: u32,

    pub const SIZE: usize = 8;

    pub fn parse(data: []const u8) !MessageHeader {
        if (data.len < SIZE) return error.BufferTooSmall;
        return MessageHeader{
            .msg_code_1 = std.mem.readInt(u16, data[0..2], .little),
            .msg_code_2 = std.mem.readInt(u16, data[2..4], .little),
            .data_size = std.mem.readInt(u32, data[4..8], .little),
        };
    }

    pub fn serialize(self: MessageHeader, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, self.msg_code_1);
        try encoding.writeIntLE(u16, writer, self.msg_code_2);
        try encoding.writeIntLE(u32, writer, self.data_size);
    }

    pub fn messageType(self: MessageHeader) ?MessageType {
        return MessageType.fromCodes(self.msg_code_1, self.msg_code_2);
    }
};

/// All known message types from the protocol
pub const MessageType = enum(u32) {
    // Control messages
    ping_query = 16,
    ping_response = 17,
    login_query = 27,
    login_response = 28,
    get_controller_mode = 110,

    // Pool status messages
    status_changed = 12500,
    schedule_changed = 12501,
    history_data = 12502,
    runtime_changed = 12503,
    color_update = 12504,
    chem_data_changed = 12505,
    chem_history_data = 12506,

    // Circuit definitions
    get_circuit_definitions_query = 12510,
    get_circuit_definitions_response = 12511,

    // Circuit info
    get_circuit_info_query = 12518,
    get_circuit_info_response = 12519,
    set_circuit_info_query = 12520,
    set_circuit_info_response = 12521,

    // Client management
    add_client_query = 12522,
    add_client_response = 12523,
    remove_client_query = 12524,
    remove_client_response = 12525,

    // Status
    get_status_query = 12526,
    get_status_response = 12527,

    // Heat control
    set_heat_setpoint_query = 12528,
    set_heat_setpoint_response = 12529,
    button_press_query = 12530,
    button_press_response = 12531,

    // Controller config
    get_controller_config_query = 12532,
    get_controller_config_response = 12533,

    // History
    get_history_query = 12534,
    get_history_response = 12535,

    // Heat mode
    set_heat_mode_query = 12538,
    set_heat_mode_response = 12539,

    // Schedule
    get_schedule_query = 12542,
    get_schedule_response = 12543,
    add_scheduled_event_query = 12544,
    add_scheduled_event_response = 12545,
    delete_scheduled_event_query = 12546,
    delete_scheduled_event_response = 12547,
    set_scheduled_event_query = 12548,
    set_scheduled_event_response = 12549,

    // Circuit runtime
    set_circuit_runtime_query = 12550,
    set_circuit_runtime_response = 12551,

    // Lights
    configure_light_query = 12554,
    configure_light_response = 12555,
    color_lights_command_query = 12556,
    color_lights_command_response = 12557,

    // Circuit names
    get_n_circuits_query = 12558,
    get_n_circuits_response = 12559,
    get_circuit_names_query = 12560,
    get_circuit_names_response = 12561,
    get_all_custom_names_query = 12562,
    get_all_custom_names_response = 12563,
    set_custom_name_query = 12564,
    set_custom_name_response = 12565,

    // Equipment config
    get_equipment_config_query = 12566,
    get_equipment_config_response = 12567,
    set_equipment_config_query = 12568,
    set_equipment_config_response = 12569,

    // Calibration
    set_cal_query = 12570,
    set_cal_response = 12571,

    // SCG (Salt Chlorine Generator)
    get_scg_config_query = 12572,
    get_scg_config_response = 12573,
    set_scg_enabled_query = 12574,
    set_scg_enabled_response = 12575,
    set_scg_config_query = 12576,
    set_scg_config_response = 12577,

    // Remotes
    enable_remotes_query = 12578,
    enable_remotes_response = 12579,

    // Delays
    cancel_delays_query = 12580,
    cancel_delays_response = 12581,

    // Errors
    get_all_errors_query = 12582,
    get_all_errors_response = 12583,

    // Pump
    get_pump_status_query = 12584,
    get_pump_status_response = 12585,
    set_pump_flow_query = 12586,
    set_pump_flow_response = 12587,

    // House code
    reset_house_code_query = 12588,
    reset_house_code_response = 12589,

    // Cool setpoint
    set_cool_setpoint_query = 12590,
    set_cool_setpoint_response = 12591,

    // Chemistry
    get_all_chem_data_query = 12592,
    get_all_chem_data_response = 12593,
    set_chem_data_query = 12594,
    set_chem_data_response = 12595,
    get_chem_history_query = 12596,
    get_chem_history_response = 12597,

    // Weather
    weather_forecast_changed = 9806,
    weather_forecast_query = 9807,
    weather_forecast_response = 9808,

    pub fn fromCodes(_: u16, code2: u16) ?MessageType {
        // Most messages have code1=0 (or an ID), so we identify by code2
        const value: u32 = code2;
        return std.meta.intToEnum(MessageType, value) catch null;
    }

    pub fn toCodes(self: MessageType) struct { code1: u16, code2: u16 } {
        const value = @intFromEnum(self);
        return .{ .code1 = 0, .code2 = @intCast(value) };
    }
};

/// Body type for temperature controls
pub const BodyType = enum(u32) {
    pool = 0,
    spa = 1,

    pub fn fromInt(value: u32) ?BodyType {
        return std.meta.intToEnum(BodyType, value) catch null;
    }
};

/// Heat mode options
pub const HeatMode = enum(u32) {
    off = 0,
    solar = 1,
    solar_preferred = 2,
    heater = 3,
    dont_change = 4,

    pub fn fromInt(value: u32) ?HeatMode {
        return std.meta.intToEnum(HeatMode, value) catch null;
    }
};

/// Circuit state
pub const CircuitState = enum(u32) {
    off = 0,
    on = 1,

    pub fn fromInt(value: u32) ?CircuitState {
        return std.meta.intToEnum(CircuitState, value) catch null;
    }
};

/// Login message - sent after TCP connection and "CONNECTSERVERHOST\r\n\r\n" handshake
///
/// Wire format (message code 27):
/// ```
/// | Header (8 bytes)                                      |
/// | schema (u32 LE)          | Protocol version (348)     |
/// | connection_type (u32 LE) | 0 = local, 1 = remote      |
/// | client_version (padded)  | String like "Android"      |
/// | data_array (padded)      | 16 bytes of zeros          |
/// | process_id (u32 LE)      | Client process ID          |
/// ```
///
/// The schema value 348 is required for current firmware versions.
/// Connection type 0 is used for local network connections.
pub const LoginMessage = struct {
    schema: u32 = 348,
    connection_type: u32 = 0,
    client_version: []const u8 = "Android",
    data_array: [16]u8 = [_]u8{0} ** 16,
    process_id: u32 = 2,

    pub fn serialize(self: LoginMessage, writer: anytype) !void {
        // Header
        try encoding.writeIntLE(u16, writer, 0); // msg_code_1
        try encoding.writeIntLE(u16, writer, 27); // msg_code_2 (login)

        // Calculate data size
        const client_version_padded = 4 + encoding.paddedLength(self.client_version.len);
        const data_array_padded = 4 + encoding.paddedLength(self.data_array.len);
        const data_size: u32 = 4 + 4 + @as(u32, @intCast(client_version_padded)) + @as(u32, @intCast(data_array_padded)) + 4;
        try encoding.writeIntLE(u32, writer, data_size);

        // Data
        try encoding.writeIntLE(u32, writer, self.schema);
        try encoding.writeIntLE(u32, writer, self.connection_type);
        try encoding.writePaddedSlice(writer, self.client_version);
        try encoding.writePaddedSlice(writer, &self.data_array);
        try encoding.writeIntLE(u32, writer, self.process_id);
    }

    pub fn serializeToSlice(self: LoginMessage, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();
        try self.serialize(buffer.writer());
        return buffer.toOwnedSlice();
    }
};

/// Ping message - keep connection alive (message code 16)
///
/// Wire format: Header only, no payload (data_size = 0)
/// Response: Message code 17 with empty payload
///
/// Send periodically to prevent connection timeout.
pub const PingMessage = struct {
    pub fn serialize(writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0); // msg_code_1
        try encoding.writeIntLE(u16, writer, 16); // msg_code_2 (ping)
        try encoding.writeIntLE(u32, writer, 0); // data_size = 0
    }
};

/// Get Status query (message code 12526)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 4) |
/// | controller_index (u32 LE)       | Usually 0
/// ```
///
/// Response: Message code 12527 with PoolStatus data (see responses.zig)
pub const GetStatusQuery = struct {
    controller_index: u32 = 0,

    pub fn serialize(self: GetStatusQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12526); // get_status_query
        try encoding.writeIntLE(u32, writer, 4); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
    }
};

/// Get Controller Config query (message code 12532)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 8) |
/// | reserved (u32 LE)               | Always 0
/// | reserved (u32 LE)               | Always 0
/// ```
///
/// Response: Message code 12533 with ControllerConfig data (see responses.zig)
pub const GetControllerConfigQuery = struct {
    pub fn serialize(writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12532); // get_controller_config_query
        try encoding.writeIntLE(u32, writer, 8); // data_size
        try encoding.writeIntLE(u32, writer, 0); // reserved
        try encoding.writeIntLE(u32, writer, 0); // reserved
    }
};

/// Get Schedule Data query (message code 12542)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 8) |
/// | schedule_type (u32 LE)          | 0 = recurring, 1 = one-time (run-once)
/// | reserved (u32 LE)               | Always 0
/// ```
///
/// Response: Message code 12543 with schedule event data (see schedule.zig)
pub const GetScheduleQuery = struct {
    schedule_type: u32 = 0, // 0 = recurring schedules, 1 = one-time/run-once

    pub fn serialize(self: GetScheduleQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12542); // get_schedule_query
        try encoding.writeIntLE(u32, writer, 8); // data_size
        try encoding.writeIntLE(u32, writer, self.schedule_type);
        try encoding.writeIntLE(u32, writer, 0); // reserved
    }
};

/// Add Client query - register for push status updates (message code 12522)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 8) |
/// | controller_index (u32 LE)       | Usually 0
/// | sender_id (u32 LE)              | Unique client identifier
/// ```
///
/// After registering, the controller will send status_changed (12500) messages
/// when equipment state changes, rather than requiring polling.
pub const AddClientQuery = struct {
    controller_index: u32 = 0,
    sender_id: u32,

    pub fn serialize(self: AddClientQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12522); // add_client_query
        try encoding.writeIntLE(u32, writer, 8); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, self.sender_id);
    }
};

/// Remove Client query - unregister from push status updates (message code 12524)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 8) |
/// | controller_index (u32 LE)       | Usually 0
/// | sender_id (u32 LE)              | Same ID used in AddClient
/// ```
pub const RemoveClientQuery = struct {
    controller_index: u32 = 0,
    sender_id: u32,

    pub fn serialize(self: RemoveClientQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12524); // remove_client_query
        try encoding.writeIntLE(u32, writer, 8); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, self.sender_id);
    }
};

/// Button Press query - turn circuits on/off (message code 12530)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 12) |
/// | controller_index (u32 LE)        | Usually 0
/// | circuit_id (u32 LE)              | Circuit number (500-519 typical)
/// | state (u32 LE)                   | 0 = off, 1 = on
/// ```
///
/// Circuit IDs are returned by GetControllerConfig. Common IDs:
/// - 500: Spa
/// - 505: Pool
/// - 506: Lights
pub const ButtonPressQuery = struct {
    controller_index: u32 = 0,
    circuit_id: u32,
    state: CircuitState,

    pub fn serialize(self: ButtonPressQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12530); // button_press_query
        try encoding.writeIntLE(u32, writer, 12); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, self.circuit_id);
        try encoding.writeIntLE(u32, writer, @intFromEnum(self.state));
    }
};

/// Set Heat Mode query (message code 12538)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 12) |
/// | controller_index (u32 LE)        | Usually 0
/// | body_type (u32 LE)               | 0 = pool, 1 = spa
/// | mode (u32 LE)                    | 0=off, 1=solar, 2=solar_pref, 3=heater
/// ```
pub const SetHeatModeQuery = struct {
    controller_index: u32 = 0,
    body_type: BodyType,
    mode: HeatMode,

    pub fn serialize(self: SetHeatModeQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12538); // set_heat_mode_query
        try encoding.writeIntLE(u32, writer, 12); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, @intFromEnum(self.body_type));
        try encoding.writeIntLE(u32, writer, @intFromEnum(self.mode));
    }
};

/// Set Heat Setpoint query (message code 12528)
///
/// Wire format:
/// ```
/// | Header (8 bytes, data_size = 12) |
/// | controller_index (u32 LE)        | Usually 0
/// | body_type (u32 LE)               | 0 = pool, 1 = spa
/// | temperature (u32 LE)             | Target temp in controller's units (F/C)
/// ```
///
/// Temperature limits are defined in ControllerConfig (typically 40-104F).
pub const SetHeatSetpointQuery = struct {
    controller_index: u32 = 0,
    body_type: BodyType,
    temperature: u32,

    pub fn serialize(self: SetHeatSetpointQuery, writer: anytype) !void {
        try encoding.writeIntLE(u16, writer, 0);
        try encoding.writeIntLE(u16, writer, 12528); // set_heat_setpoint_query
        try encoding.writeIntLE(u32, writer, 12); // data_size
        try encoding.writeIntLE(u32, writer, self.controller_index);
        try encoding.writeIntLE(u32, writer, @intFromEnum(self.body_type));
        try encoding.writeIntLE(u32, writer, self.temperature);
    }
};

// Tests
test "MessageHeader parse and serialize" {
    const data = [_]u8{ 0x00, 0x00, 0xee, 0x30, 0x04, 0x00, 0x00, 0x00 };
    const header = try MessageHeader.parse(&data);

    try testing.expectEqual(@as(u16, 0), header.msg_code_1);
    try testing.expectEqual(@as(u16, 12526), header.msg_code_2);
    try testing.expectEqual(@as(u32, 4), header.data_size);

    var out_buf: [8]u8 = undefined;
    var stream = std.io.fixedBufferStream(&out_buf);
    try header.serialize(stream.writer());
    try testing.expectEqualSlices(u8, &data, &out_buf);
}

test "LoginMessage serialization" {
    const msg = LoginMessage{};
    var buffer: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try msg.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expect(written.len > 8);

    // Check header
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 27), std.mem.readInt(u16, written[2..4], .little));
}

test "MessageType fromCodes" {
    try testing.expectEqual(MessageType.login_query, MessageType.fromCodes(0, 27).?);
    try testing.expectEqual(MessageType.login_response, MessageType.fromCodes(0, 28).?);
    try testing.expectEqual(MessageType.get_status_query, MessageType.fromCodes(0, 12526).?);
    try testing.expectEqual(MessageType.get_status_response, MessageType.fromCodes(0, 12527).?);
    try testing.expectEqual(MessageType.ping_query, MessageType.fromCodes(0, 16).?);
    try testing.expect(MessageType.fromCodes(0, 65000) == null);
}

test "MessageType toCodes" {
    const login = MessageType.login_query.toCodes();
    try testing.expectEqual(@as(u16, 0), login.code1);
    try testing.expectEqual(@as(u16, 27), login.code2);

    const status = MessageType.get_status_query.toCodes();
    try testing.expectEqual(@as(u16, 0), status.code1);
    try testing.expectEqual(@as(u16, 12526), status.code2);
}

test "BodyType fromInt" {
    try testing.expectEqual(BodyType.pool, BodyType.fromInt(0).?);
    try testing.expectEqual(BodyType.spa, BodyType.fromInt(1).?);
    try testing.expect(BodyType.fromInt(99) == null);
}

test "HeatMode fromInt" {
    try testing.expectEqual(HeatMode.off, HeatMode.fromInt(0).?);
    try testing.expectEqual(HeatMode.solar, HeatMode.fromInt(1).?);
    try testing.expectEqual(HeatMode.solar_preferred, HeatMode.fromInt(2).?);
    try testing.expectEqual(HeatMode.heater, HeatMode.fromInt(3).?);
    try testing.expectEqual(HeatMode.dont_change, HeatMode.fromInt(4).?);
    try testing.expect(HeatMode.fromInt(99) == null);
}

test "CircuitState fromInt" {
    try testing.expectEqual(CircuitState.off, CircuitState.fromInt(0).?);
    try testing.expectEqual(CircuitState.on, CircuitState.fromInt(1).?);
    try testing.expect(CircuitState.fromInt(2) == null);
}

test "GetStatusQuery serialization" {
    const query = GetStatusQuery{};
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 12), written.len);

    // Header
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 12526), std.mem.readInt(u16, written[2..4], .little));
    try testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, written[4..8], .little));
    // Controller index
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[8..12], .little));
}

test "ButtonPressQuery serialization" {
    const query = ButtonPressQuery{
        .circuit_id = 505,
        .state = .on,
    };
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 20), written.len);

    // Header
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 12530), std.mem.readInt(u16, written[2..4], .little));
    try testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, written[4..8], .little));
    // Data
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[8..12], .little)); // controller_index
    try testing.expectEqual(@as(u32, 505), std.mem.readInt(u32, written[12..16], .little)); // circuit_id
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, written[16..20], .little)); // state=on
}

test "SetHeatModeQuery serialization" {
    const query = SetHeatModeQuery{
        .body_type = .spa,
        .mode = .heater,
    };
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 20), written.len);

    // Header
    try testing.expectEqual(@as(u16, 12538), std.mem.readInt(u16, written[2..4], .little));
    // Data
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, written[12..16], .little)); // body_type=spa
    try testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, written[16..20], .little)); // mode=heater
}

test "SetHeatSetpointQuery serialization" {
    const query = SetHeatSetpointQuery{
        .body_type = .pool,
        .temperature = 85,
    };
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try query.serialize(stream.writer());

    const written = stream.getWritten();

    // Header
    try testing.expectEqual(@as(u16, 12528), std.mem.readInt(u16, written[2..4], .little));
    // Data
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[12..16], .little)); // body_type=pool
    try testing.expectEqual(@as(u32, 85), std.mem.readInt(u32, written[16..20], .little)); // temperature
}

test "PingMessage serialization" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try PingMessage.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 8), written.len);

    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 16), std.mem.readInt(u16, written[2..4], .little));
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[4..8], .little));
}

test "GetControllerConfigQuery serialization" {
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try GetControllerConfigQuery.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 16), written.len);

    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 12532), std.mem.readInt(u16, written[2..4], .little));
    try testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, written[4..8], .little));
}

test "GetScheduleQuery serialization" {
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // Default schedule_type = 0 (recurring)
    const query = GetScheduleQuery{};
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(usize, 16), written.len);

    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, written[0..2], .little));
    try testing.expectEqual(@as(u16, 12542), std.mem.readInt(u16, written[2..4], .little)); // get_schedule_query
    try testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, written[4..8], .little)); // data_size
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[8..12], .little)); // schedule_type
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, written[12..16], .little)); // reserved
}

test "GetScheduleQuery with one-time schedules" {
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // schedule_type = 1 (one-time/run-once)
    const query = GetScheduleQuery{ .schedule_type = 1 };
    try query.serialize(stream.writer());

    const written = stream.getWritten();
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, written[8..12], .little)); // schedule_type
}
