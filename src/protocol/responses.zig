const std = @import("std");
const testing = std.testing;
const encoding = @import("encoding.zig");
const messages = @import("messages.zig");

// ScreenLogic Response Parsing
//
// This module handles parsing of responses from the ScreenLogic controller.
// All multi-byte integers are little-endian. Strings are length-prefixed (u32)
// and padded to 4-byte boundaries.
//
// Reference: protocol_document.pdf and github.com/parnic/node-screenlogic

/// Circuit information from controller config (message code 12533)
///
/// Each circuit entry in the controller config response has this wire format:
/// ```
/// | Circuit ID (u32 LE) |
/// | Name length (u32 LE) | Name bytes | Padding to 4-byte boundary |
/// | nameIndex (u8) | function (u8) | interface (u8) | freeze (u8) |
/// | colorSet (u8) | colorPos (u8) | colorStagger (u8) | deviceId (u8) |
/// | eggTimer (u16 LE) | reserved (u16) |
/// ```
/// Total: 4 + padded_string + 12 bytes per circuit
pub const Circuit = struct {
    id: u32,
    name: []const u8,
    state: bool,
    name_index: u8 = 0,
    function: u8 = 0,
    interface: u8 = 0,
    freeze: u8 = 0,
    color_set: u8 = 0,
    color_position: u8 = 0,
    color_stagger: u8 = 0,
    device_id: u8 = 0,
    egg_timer: u16 = 0,

    pub fn deinit(self: *Circuit, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// Pool/Spa body status from equipment state (message code 12527)
///
/// Wire format for each body entry (24 bytes total):
/// ```
/// | body_type (u32 LE)      | 0 = pool, 1 = spa
/// | current_temp (i32 LE)   | Current water temperature
/// | heat_status (u32 LE)    | Non-zero if heater is actively running
/// | heat_setpoint (i32 LE)  | Target temperature when heating
/// | cool_setpoint (i32 LE)  | Target temperature for cooling (if supported)
/// | heat_mode (u32 LE)      | 0=off, 1=solar, 2=solar_preferred, 3=heater
/// ```
///
/// IMPORTANT: heat_status comes BEFORE heat_setpoint in the wire format.
/// This was discovered through real device testing and confirmed via node-screenlogic.
pub const BodyStatus = struct {
    current_temp: i32,
    heat_setpoint: i32,
    cool_setpoint: i32,
    heat_mode: messages.HeatMode,
    heat_status: bool,
};

/// Pool status response (message code 12527)
///
/// Wire format overview:
/// ```
/// Offset  Size  Field
/// 0       1     ok (bool, only first byte matters)
/// 4       1     freeze_mode
/// 5       1     remotes
/// 6       1     pool_delay
/// 7       1     spa_delay
/// 8       1     cleaner_delay
/// 9       3     (padding)
/// 12      4     air_temp (i32 LE)
/// 16      4     body_count (u32 LE)
/// 20      24*N  body entries (see BodyStatus)
/// ...     4     circuit_count (u32 LE)
/// ...     12*N  circuit status entries
/// ...     16    chemistry data (pH, ORP, salt, saturation) if present
/// ```
pub const PoolStatus = struct {
    ok: bool,
    freeze_mode: bool,
    remotes: u8,
    pool_delay: u8,
    spa_delay: u8,
    cleaner_delay: u8,
    air_temp: i32,
    bodies: struct {
        pool: ?BodyStatus,
        spa: ?BodyStatus,
    },
    circuits: []CircuitStatus,
    ph: ?f32,
    orp: ?i32,
    salt_ppm: ?i32,
    saturation: ?f32,

    allocator: std.mem.Allocator,

    /// Circuit status entry (12 bytes each)
    /// ```
    /// | circuit_id (u32 LE) | state (u32 LE) |
    /// | colorSet (u8) | colorPos (u8) | colorStagger (u8) | delay (u8) |
    /// ```
    pub const CircuitStatus = struct {
        id: u32,
        state: bool,
        color_set: u8,
        color_position: u8,
        color_stagger: u8,
        delay: u8,
    };

    pub fn deinit(self: *PoolStatus) void {
        self.allocator.free(self.circuits);
    }

    pub fn parse(data: []const u8, allocator: std.mem.Allocator) !PoolStatus {
        if (data.len < 12) return error.BufferTooSmall;

        var offset: usize = 0;

        const ok_byte = data[offset];
        offset += 4;

        const freeze_mode = data[offset] != 0;
        offset += 1;

        const remotes = data[offset];
        offset += 1;

        const pool_delay = data[offset];
        offset += 1;

        const spa_delay = data[offset];
        offset += 1;

        const cleaner_delay = data[offset];
        offset += 1;

        offset += 3; // padding

        const air_temp = try encoding.readIntFromSlice(i32, data, offset);
        offset += 4;

        // Bodies count
        const body_count = try encoding.readIntFromSlice(u32, data, offset);
        offset += 4;

        var pool_status: ?BodyStatus = null;
        var spa_status: ?BodyStatus = null;

        var i: u32 = 0;
        while (i < body_count) : (i += 1) {
            if (offset + 24 > data.len) break;

            const body_type = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const current_temp = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;

            // Per node-screenlogic: heat_status comes before heat_setpoint
            const heat_status = try encoding.readIntFromSlice(u32, data, offset) != 0;
            offset += 4;

            const heat_setpoint = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;

            const cool_setpoint = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;

            const heat_mode_raw = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const body_status = BodyStatus{
                .current_temp = current_temp,
                .heat_setpoint = heat_setpoint,
                .cool_setpoint = cool_setpoint,
                .heat_mode = messages.HeatMode.fromInt(heat_mode_raw) orelse .off,
                .heat_status = heat_status,
            };

            if (body_type == 0) {
                pool_status = body_status;
            } else if (body_type == 1) {
                spa_status = body_status;
            }
        }

        // Circuit count
        const circuit_count = if (offset + 4 <= data.len)
            try encoding.readIntFromSlice(u32, data, offset)
        else
            0;
        offset += 4;

        var circuits: std.ArrayList(CircuitStatus) = .{};
        errdefer circuits.deinit(allocator);

        var c: u32 = 0;
        while (c < circuit_count) : (c += 1) {
            if (offset + 12 > data.len) break;

            const circuit_id = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const circuit_state = try encoding.readIntFromSlice(u32, data, offset) != 0;
            offset += 4;

            const color_set = data[offset];
            offset += 1;

            const color_position = data[offset];
            offset += 1;

            const color_stagger = data[offset];
            offset += 1;

            const delay = data[offset];
            offset += 1;

            try circuits.append(allocator, .{
                .id = circuit_id,
                .state = circuit_state,
                .color_set = color_set,
                .color_position = color_position,
                .color_stagger = color_stagger,
                .delay = delay,
            });
        }

        // Chemistry data (if present)
        var ph: ?f32 = null;
        var orp: ?i32 = null;
        var salt_ppm: ?i32 = null;
        var saturation: ?f32 = null;

        if (offset + 16 <= data.len) {
            const ph_raw = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;
            if (ph_raw > 0) {
                ph = @as(f32, @floatFromInt(ph_raw)) / 100.0;
            }

            const orp_raw = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;
            if (orp_raw > 0) {
                orp = orp_raw;
            }

            const salt_raw = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;
            if (salt_raw > 0) {
                salt_ppm = salt_raw * 50;
            }

            const sat_raw = try encoding.readIntFromSlice(i32, data, offset);
            offset += 4;
            if (sat_raw != 0) {
                saturation = @as(f32, @floatFromInt(sat_raw)) / 100.0;
            }
        }

        return PoolStatus{
            .ok = ok_byte != 0,
            .freeze_mode = freeze_mode,
            .remotes = remotes,
            .pool_delay = pool_delay,
            .spa_delay = spa_delay,
            .cleaner_delay = cleaner_delay,
            .air_temp = air_temp,
            .bodies = .{
                .pool = pool_status,
                .spa = spa_status,
            },
            .circuits = try circuits.toOwnedSlice(allocator),
            .ph = ph,
            .orp = orp,
            .salt_ppm = salt_ppm,
            .saturation = saturation,
            .allocator = allocator,
        };
    }
};

/// Controller configuration response (message code 12533)
///
/// Wire format:
/// ```
/// Offset  Size  Field
/// 0       4     controller_id (u32 LE)
/// 4       1     min_setpoint_pool
/// 5       1     max_setpoint_pool
/// 6       1     min_setpoint_spa
/// 7       1     max_setpoint_spa
/// 8       1     is_celsius (0 = Fahrenheit, 1 = Celsius)
/// 9       1     controller_type
/// 10      1     hardware_type
/// 11      1     controller_data
/// 12      1     equipment_flags
/// 13-15   3     (padding to 4-byte boundary)
/// 16      var   generic_circuit_name (padded string)
/// ...     4     circuit_count (u32 LE)
/// ...     var   circuit entries (see Circuit struct for format)
/// ```
pub const ControllerConfig = struct {
    controller_id: u32,
    min_setpoint_pool: u8,
    max_setpoint_pool: u8,
    min_setpoint_spa: u8,
    max_setpoint_spa: u8,
    is_celsius: bool,
    controller_type: u8,
    hardware_type: u8,
    controller_data: u8,
    equipment_flags: u8,
    generic_circuit_name: []const u8,
    circuits: []Circuit,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *ControllerConfig) void {
        self.allocator.free(self.generic_circuit_name);
        for (self.circuits) |*circuit| {
            self.allocator.free(circuit.name);
        }
        self.allocator.free(self.circuits);
    }

    pub fn parse(data: []const u8, allocator: std.mem.Allocator) !ControllerConfig {
        if (data.len < 20) return error.BufferTooSmall;

        var offset: usize = 0;

        const controller_id = try encoding.readIntFromSlice(u32, data, offset);
        offset += 4;

        const min_setpoint_pool = data[offset];
        offset += 1;
        const max_setpoint_pool = data[offset];
        offset += 1;
        const min_setpoint_spa = data[offset];
        offset += 1;
        const max_setpoint_spa = data[offset];
        offset += 1;
        const is_celsius = data[offset] != 0;
        offset += 1;
        const controller_type = data[offset];
        offset += 1;
        const hardware_type = data[offset];
        offset += 1;
        const controller_data = data[offset];
        offset += 1;
        const equipment_flags = data[offset];
        offset += 1;

        // Align to 4 bytes
        offset = (offset + 3) & ~@as(usize, 3);

        // Generic circuit name (padded string)
        const name_result = try encoding.readPaddedStringFromSlice(data, offset, allocator);
        offset += name_result.bytes_consumed;

        // Circuit count
        if (offset + 4 > data.len) {
            return ControllerConfig{
                .controller_id = controller_id,
                .min_setpoint_pool = min_setpoint_pool,
                .max_setpoint_pool = max_setpoint_pool,
                .min_setpoint_spa = min_setpoint_spa,
                .max_setpoint_spa = max_setpoint_spa,
                .is_celsius = is_celsius,
                .controller_type = controller_type,
                .hardware_type = hardware_type,
                .controller_data = controller_data,
                .equipment_flags = equipment_flags,
                .generic_circuit_name = name_result.string,
                .circuits = &[_]Circuit{},
                .allocator = allocator,
            };
        }

        const circuit_count = try encoding.readIntFromSlice(u32, data, offset);
        offset += 4;

        var circuits: std.ArrayList(Circuit) = .{};
        errdefer {
            for (circuits.items) |*c| {
                allocator.free(c.name);
            }
            circuits.deinit(allocator);
        }

        var i: u32 = 0;
        while (i < circuit_count) : (i += 1) {
            if (offset + 4 > data.len) break;

            const circuit_id = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const circuit_name_result = try encoding.readPaddedStringFromSlice(data, offset, allocator);
            offset += circuit_name_result.bytes_consumed;

            // Read additional circuit fields (12 bytes per node-screenlogic)
            if (offset + 12 > data.len) {
                allocator.free(circuit_name_result.string);
                break;
            }

            const name_index = data[offset];
            offset += 1;
            const function = data[offset];
            offset += 1;
            const interface_val = data[offset];
            offset += 1;
            const freeze = data[offset];
            offset += 1;
            const color_set = data[offset];
            offset += 1;
            const color_pos = data[offset];
            offset += 1;
            const color_stagger = data[offset];
            offset += 1;
            const device_id = data[offset];
            offset += 1;
            const egg_timer = try encoding.readIntFromSlice(u16, data, offset);
            offset += 2;
            offset += 2; // skip 2 bytes

            try circuits.append(allocator, .{
                .id = circuit_id,
                .name = circuit_name_result.string,
                .state = false,
                .name_index = name_index,
                .function = function,
                .interface = interface_val,
                .freeze = freeze,
                .color_set = color_set,
                .color_position = color_pos,
                .color_stagger = color_stagger,
                .device_id = device_id,
                .egg_timer = egg_timer,
            });
        }

        return ControllerConfig{
            .controller_id = controller_id,
            .min_setpoint_pool = min_setpoint_pool,
            .max_setpoint_pool = max_setpoint_pool,
            .min_setpoint_spa = min_setpoint_spa,
            .max_setpoint_spa = max_setpoint_spa,
            .is_celsius = is_celsius,
            .controller_type = controller_type,
            .hardware_type = hardware_type,
            .controller_data = controller_data,
            .equipment_flags = equipment_flags,
            .generic_circuit_name = name_result.string,
            .circuits = try circuits.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }
};

/// Chemistry data response (IntelliChem)
///
/// Wire format (46 bytes minimum):
/// ```
/// Offset  Size  Field
/// 0       4     data_size (u32 LE, must be 42)
/// 4       2     (unknown/reserved)
/// 6       2     pH * 100 (u16 LE, e.g., 740 = 7.40)
/// 8       2     ORP in mV (u16 LE)
/// 10      2     pH setpoint * 100 (u16 LE)
/// 12      2     ORP setpoint (u16 LE)
/// 14      12    (unknown/reserved)
/// 26      1     pH tank level (0-6 scale)
/// 27      1     ORP tank level (0-6 scale)
/// 28      1     saturation index * 100 (i8, signed)
/// 29      2     calcium hardness (u16 LE)
/// 31      2     cyanuric acid (u16 LE)
/// 33      2     alkalinity (u16 LE)
/// 35      2     salt level / 50 (u16 LE, multiply by 50 for ppm)
/// 37      2     temperature (u16 LE)
/// 39      1     flags (bit 0 = scaling, bit 1 = corrosive)
/// ```
pub const ChemData = struct {
    ph: f32,
    orp: i32,
    ph_setpoint: f32,
    orp_setpoint: i32,
    ph_tank_level: u8,
    orp_tank_level: u8,
    saturation: f32,
    calcium: i32,
    cyanuric: i32,
    alkalinity: i32,
    salt_ppm: i32,
    temperature: i32,
    is_corrosive: bool,
    is_scaling: bool,

    pub fn parse(data: []const u8) !ChemData {
        if (data.len < 42) return error.BufferTooSmall;

        var offset: usize = 0;

        const data_size = try encoding.readIntFromSlice(u32, data, offset);
        offset += 4;

        if (data_size != 42) return error.InvalidResponse;

        offset += 2; // skip unknown field

        const ph_raw = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const orp_raw = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const ph_setpoint_raw = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const orp_setpoint_raw = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        offset += 12; // skip 12 bytes

        const ph_tank_level = data[offset];
        offset += 1;

        const orp_tank_level = data[offset];
        offset += 1;

        const saturation_raw: i8 = @bitCast(data[offset]);
        offset += 1;

        const calcium = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const cyanuric = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const alkalinity = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const salt_raw = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const temperature = try encoding.readIntFromSlice(u16, data, offset);
        offset += 2;

        const flags = data[offset];

        return ChemData{
            .ph = @as(f32, @floatFromInt(ph_raw)) / 100.0,
            .orp = @as(i32, orp_raw),
            .ph_setpoint = @as(f32, @floatFromInt(ph_setpoint_raw)) / 100.0,
            .orp_setpoint = @as(i32, orp_setpoint_raw),
            .ph_tank_level = ph_tank_level,
            .orp_tank_level = orp_tank_level,
            .saturation = @as(f32, @floatFromInt(saturation_raw)) / 100.0,
            .calcium = @as(i32, calcium),
            .cyanuric = @as(i32, cyanuric),
            .alkalinity = @as(i32, alkalinity),
            .salt_ppm = @as(i32, salt_raw) * 50,
            .temperature = @as(i32, temperature),
            .is_scaling = (flags & 0x01) != 0,
            .is_corrosive = (flags & 0x02) != 0,
        };
    }
};

// Tests
test "BodyStatus initialization" {
    const status = BodyStatus{
        .current_temp = 82,
        .heat_setpoint = 85,
        .cool_setpoint = 90,
        .heat_mode = .heater,
        .heat_status = true,
    };

    try testing.expectEqual(@as(i32, 82), status.current_temp);
    try testing.expectEqual(@as(i32, 85), status.heat_setpoint);
    try testing.expect(status.heat_status);
}

test "PoolStatus parse minimal response" {
    const allocator = testing.allocator;

    // Minimal valid response: ok=1, freeze=0, remotes=0, delays=0, padding, air_temp=72, 0 bodies, 0 circuits
    var data: [24]u8 = undefined;
    var offset: usize = 0;

    // ok (4 bytes - first byte is bool)
    data[offset] = 1;
    data[offset + 1] = 0;
    data[offset + 2] = 0;
    data[offset + 3] = 0;
    offset += 4;

    // freeze_mode, remotes, pool_delay, spa_delay, cleaner_delay
    data[offset] = 0; // freeze_mode
    offset += 1;
    data[offset] = 0; // remotes
    offset += 1;
    data[offset] = 0; // pool_delay
    offset += 1;
    data[offset] = 0; // spa_delay
    offset += 1;
    data[offset] = 0; // cleaner_delay
    offset += 1;

    // padding (3 bytes)
    data[offset] = 0;
    offset += 1;
    data[offset] = 0;
    offset += 1;
    data[offset] = 0;
    offset += 1;

    // air_temp (i32 LE) = 72
    std.mem.writeInt(i32, data[offset..][0..4], 72, .little);
    offset += 4;

    // body_count = 0
    std.mem.writeInt(u32, data[offset..][0..4], 0, .little);
    offset += 4;

    var status = try PoolStatus.parse(&data, allocator);
    defer status.deinit();

    try testing.expect(status.ok);
    try testing.expect(!status.freeze_mode);
    try testing.expectEqual(@as(i32, 72), status.air_temp);
    try testing.expect(status.bodies.pool == null);
    try testing.expect(status.bodies.spa == null);
}

test "PoolStatus parse with bodies and circuits" {
    const allocator = testing.allocator;

    // Build a response with 1 body (pool) and 1 circuit
    var data: [80]u8 = [_]u8{0} ** 80;
    var offset: usize = 0;

    // ok
    data[offset] = 1;
    offset += 4;

    // freeze, remotes, delays
    offset += 5;

    // padding
    offset += 3;

    // air_temp = 75
    std.mem.writeInt(i32, data[offset..][0..4], 75, .little);
    offset += 4;

    // body_count = 1
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little);
    offset += 4;

    // Body 0 (pool) - field order per node-screenlogic: type, temp, heat_status, setpoint, cool, mode
    std.mem.writeInt(u32, data[offset..][0..4], 0, .little); // body_type = pool
    offset += 4;
    std.mem.writeInt(i32, data[offset..][0..4], 82, .little); // current_temp
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little); // heat_status = true
    offset += 4;
    std.mem.writeInt(i32, data[offset..][0..4], 85, .little); // heat_setpoint
    offset += 4;
    std.mem.writeInt(i32, data[offset..][0..4], 90, .little); // cool_setpoint
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 3, .little); // heat_mode = heater
    offset += 4;

    // circuit_count = 1
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little);
    offset += 4;

    // Circuit 0
    std.mem.writeInt(u32, data[offset..][0..4], 505, .little); // circuit_id
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little); // state = on
    offset += 4;
    data[offset] = 1; // color_set
    offset += 1;
    data[offset] = 2; // color_position
    offset += 1;
    data[offset] = 3; // color_stagger
    offset += 1;
    data[offset] = 0; // delay
    offset += 1;

    var status = try PoolStatus.parse(data[0..offset], allocator);
    defer status.deinit();

    try testing.expect(status.ok);
    try testing.expectEqual(@as(i32, 75), status.air_temp);

    // Check pool body
    try testing.expect(status.bodies.pool != null);
    const pool = status.bodies.pool.?;
    try testing.expectEqual(@as(i32, 82), pool.current_temp);
    try testing.expectEqual(@as(i32, 85), pool.heat_setpoint);
    try testing.expectEqual(messages.HeatMode.heater, pool.heat_mode);
    try testing.expect(pool.heat_status);

    // Check circuits
    try testing.expectEqual(@as(usize, 1), status.circuits.len);
    try testing.expectEqual(@as(u32, 505), status.circuits[0].id);
    try testing.expect(status.circuits[0].state);
}

test "PoolStatus parse returns error on buffer too small" {
    const allocator = testing.allocator;
    const data = [_]u8{0} ** 8; // Too small

    const result = PoolStatus.parse(&data, allocator);
    try testing.expectError(error.BufferTooSmall, result);
}

test "Circuit deinit frees name" {
    const allocator = testing.allocator;

    var circuit = Circuit{
        .id = 1,
        .name = try allocator.dupe(u8, "Test Circuit"),
        .state = true,
    };

    circuit.deinit(allocator);
    // If we get here without crash, the test passes
}

test "ChemData parse" {
    // Build a chemistry response
    var data: [46]u8 = [_]u8{0} ** 46;
    var offset: usize = 0;

    // data_size = 42
    std.mem.writeInt(u32, data[offset..][0..4], 42, .little);
    offset += 4;

    // skip unknown (2 bytes)
    offset += 2;

    // pH = 740 (7.40)
    std.mem.writeInt(u16, data[offset..][0..2], 740, .little);
    offset += 2;

    // ORP = 750
    std.mem.writeInt(u16, data[offset..][0..2], 750, .little);
    offset += 2;

    // pH setpoint = 720 (7.20)
    std.mem.writeInt(u16, data[offset..][0..2], 720, .little);
    offset += 2;

    // ORP setpoint = 700
    std.mem.writeInt(u16, data[offset..][0..2], 700, .little);
    offset += 2;

    // skip 12 bytes
    offset += 12;

    // tank levels
    data[offset] = 5; // pH tank
    offset += 1;
    data[offset] = 6; // ORP tank
    offset += 1;

    // saturation = 10 (0.10)
    data[offset] = 10;
    offset += 1;

    // calcium = 400
    std.mem.writeInt(u16, data[offset..][0..2], 400, .little);
    offset += 2;

    // cyanuric = 50
    std.mem.writeInt(u16, data[offset..][0..2], 50, .little);
    offset += 2;

    // alkalinity = 100
    std.mem.writeInt(u16, data[offset..][0..2], 100, .little);
    offset += 2;

    // salt = 60 (60 * 50 = 3000 ppm)
    std.mem.writeInt(u16, data[offset..][0..2], 60, .little);
    offset += 2;

    // temperature = 82
    std.mem.writeInt(u16, data[offset..][0..2], 82, .little);
    offset += 2;

    // flags = 0 (no scaling/corrosion)
    data[offset] = 0;

    const chem = try ChemData.parse(&data);

    try testing.expectApproxEqAbs(@as(f32, 7.40), chem.ph, 0.01);
    try testing.expectEqual(@as(i32, 750), chem.orp);
    try testing.expectApproxEqAbs(@as(f32, 7.20), chem.ph_setpoint, 0.01);
    try testing.expectEqual(@as(i32, 700), chem.orp_setpoint);
    try testing.expectEqual(@as(u8, 5), chem.ph_tank_level);
    try testing.expectEqual(@as(u8, 6), chem.orp_tank_level);
    try testing.expectEqual(@as(i32, 400), chem.calcium);
    try testing.expectEqual(@as(i32, 50), chem.cyanuric);
    try testing.expectEqual(@as(i32, 100), chem.alkalinity);
    try testing.expectEqual(@as(i32, 3000), chem.salt_ppm);
    try testing.expectEqual(@as(i32, 82), chem.temperature);
    try testing.expect(!chem.is_scaling);
    try testing.expect(!chem.is_corrosive);
}

test "ChemData parse with scaling flag" {
    var data: [46]u8 = [_]u8{0} ** 46;

    // data_size = 42
    std.mem.writeInt(u32, data[0..4], 42, .little);

    // flags offset: 4 (size) + 2 (unknown) + 2+2+2+2 (pH,ORP,setpoints) + 12 (skip)
    // + 1+1+1 (tanks,sat) + 2+2+2+2+2 (Ca,CYA,alk,salt,temp) = 39
    data[39] = 0x01; // scaling flag

    const chem = try ChemData.parse(&data);
    try testing.expect(chem.is_scaling);
    try testing.expect(!chem.is_corrosive);
}

test "ChemData parse returns error on wrong size" {
    var data: [46]u8 = [_]u8{0} ** 46;

    // data_size = 100 (wrong)
    std.mem.writeInt(u32, data[0..4], 100, .little);

    const result = ChemData.parse(&data);
    try testing.expectError(error.InvalidResponse, result);
}
