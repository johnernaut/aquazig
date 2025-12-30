// Schedule Data Response Parsing
//
// This module handles parsing of schedule data from the ScreenLogic controller.
// Message codes: 12542 (query), 12543 (response)
//
// Based on protocol_document.pdf section 4.1.20/4.2.20 and 4.1.36 (SetScheduledEvent parameters)

const std = @import("std");
const testing = std.testing;
const encoding = @import("encoding.zig");

/// Day of week bitmask values
pub const DayMask = struct {
    pub const sunday: u8 = 0x01;
    pub const monday: u8 = 0x02;
    pub const tuesday: u8 = 0x04;
    pub const wednesday: u8 = 0x08;
    pub const thursday: u8 = 0x10;
    pub const friday: u8 = 0x20;
    pub const saturday: u8 = 0x40;
    pub const every_day: u8 = 0x7F; // All days (127)
};

/// Schedule event flags
pub const ScheduleFlags = struct {
    pub const none: u8 = 0;
    pub const enabled: u8 = 2; // Default enabled flag
};

/// Heat command values for schedule events
pub const HeatCommand = enum(u8) {
    off = 0,
    heater = 1,
    solar_pref = 2,
    solar = 3,
    no_change = 4,

    pub fn fromInt(val: u32) ?HeatCommand {
        return std.meta.intToEnum(HeatCommand, @as(u8, @truncate(val))) catch null;
    }
};

/// Individual scheduled event
///
/// Wire format (per event, estimated 32 bytes):
/// ```
/// | schedule_id (u32 LE)    | Unique ID for this schedule
/// | circuit_id (u32 LE)     | Circuit this schedule controls
/// | start_time (u32 LE)     | Start time in minutes from midnight
/// | stop_time (u32 LE)      | Stop time in minutes from midnight
/// | day_mask (u8)           | Bitmask of active days (Sun=1, Mon=2, etc)
/// | flags (u8)              | Schedule flags (2 = enabled)
/// | heat_cmd (u8)           | Heat command (0=off, 1=heater, etc)
/// | heat_setpoint (u8)      | Temperature setpoint
/// ```
pub const ScheduledEvent = struct {
    schedule_id: u32,
    circuit_id: u32,
    start_time: u32, // Minutes from midnight (0-1439)
    stop_time: u32, // Minutes from midnight (0-1439)
    day_mask: u8,
    flags: u8,
    heat_cmd: HeatCommand,
    heat_setpoint: u8,

    /// Format start time as HH:MM string
    pub fn formatStartTime(self: ScheduledEvent, buf: []u8) []u8 {
        return formatMinutes(self.start_time, buf);
    }

    /// Format stop time as HH:MM string
    pub fn formatStopTime(self: ScheduledEvent, buf: []u8) []u8 {
        return formatMinutes(self.stop_time, buf);
    }

    /// Check if schedule runs on a specific day
    pub fn runsOnDay(self: ScheduledEvent, day: u8) bool {
        return (self.day_mask & day) != 0;
    }

    /// Check if schedule is enabled
    pub fn isEnabled(self: ScheduledEvent) bool {
        return (self.flags & ScheduleFlags.enabled) != 0;
    }
};

/// Format minutes from midnight as "HH:MM" into the provided buffer
fn formatMinutes(minutes: u32, buf: []u8) []u8 {
    if (buf.len < 5) return buf[0..0];

    const hours = minutes / 60;
    const mins = minutes % 60;

    _ = std.fmt.bufPrint(buf[0..5], "{d:0>2}:{d:0>2}", .{ hours, mins }) catch return buf[0..0];
    return buf[0..5];
}

/// Schedule data response (message code 12543)
///
/// Wire format:
/// ```
/// | event_count (u32 LE)     | Number of schedule events
/// | ScheduledEvent[count]    | Array of events
/// ```
pub const Schedule = struct {
    events: []ScheduledEvent,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Schedule) void {
        self.allocator.free(self.events);
    }

    pub fn parse(data: []const u8, allocator: std.mem.Allocator) !Schedule {
        if (data.len < 4) return error.BufferTooSmall;

        var offset: usize = 0;

        // Read event count
        const event_count = try encoding.readIntFromSlice(u32, data, offset);
        offset += 4;

        // Sanity check - don't allocate too many events
        if (event_count > 100) return error.InvalidResponse;

        var events: std.ArrayList(ScheduledEvent) = .{};
        errdefer events.deinit(allocator);

        var i: u32 = 0;
        while (i < event_count) : (i += 1) {
            // Each event is 32 bytes (8 x u32 fields)
            if (offset + 32 > data.len) break;

            const schedule_id = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const circuit_id = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const start_time = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const stop_time = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            // All fields are u32 in the wire format
            const day_mask_raw = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const flags_raw = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const heat_cmd_raw = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            const heat_setpoint_raw = try encoding.readIntFromSlice(u32, data, offset);
            offset += 4;

            try events.append(allocator, .{
                .schedule_id = schedule_id,
                .circuit_id = circuit_id,
                .start_time = start_time,
                .stop_time = stop_time,
                .day_mask = @truncate(day_mask_raw),
                .flags = @truncate(flags_raw),
                .heat_cmd = HeatCommand.fromInt(@truncate(heat_cmd_raw)) orelse .no_change,
                .heat_setpoint = @truncate(heat_setpoint_raw),
            });
        }

        return Schedule{
            .events = try events.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "formatMinutes" {
    var buf: [8]u8 = undefined;

    const t1 = formatMinutes(0, &buf);
    try testing.expectEqualStrings("00:00", t1);

    const t2 = formatMinutes(60, &buf);
    try testing.expectEqualStrings("01:00", t2);

    const t3 = formatMinutes(720, &buf); // noon
    try testing.expectEqualStrings("12:00", t3);

    const t4 = formatMinutes(1439, &buf); // 23:59
    try testing.expectEqualStrings("23:59", t4);

    const t5 = formatMinutes(510, &buf); // 8:30 AM
    try testing.expectEqualStrings("08:30", t5);
}

test "ScheduledEvent.runsOnDay" {
    const event = ScheduledEvent{
        .schedule_id = 1,
        .circuit_id = 505,
        .start_time = 480,
        .stop_time = 1080,
        .day_mask = DayMask.monday | DayMask.wednesday | DayMask.friday,
        .flags = ScheduleFlags.enabled,
        .heat_cmd = .no_change,
        .heat_setpoint = 0,
    };

    try testing.expect(event.runsOnDay(DayMask.monday));
    try testing.expect(event.runsOnDay(DayMask.wednesday));
    try testing.expect(event.runsOnDay(DayMask.friday));
    try testing.expect(!event.runsOnDay(DayMask.sunday));
    try testing.expect(!event.runsOnDay(DayMask.tuesday));
}

test "ScheduledEvent.isEnabled" {
    const enabled = ScheduledEvent{
        .schedule_id = 1,
        .circuit_id = 505,
        .start_time = 480,
        .stop_time = 1080,
        .day_mask = DayMask.every_day,
        .flags = ScheduleFlags.enabled,
        .heat_cmd = .no_change,
        .heat_setpoint = 0,
    };
    try testing.expect(enabled.isEnabled());

    const disabled = ScheduledEvent{
        .schedule_id = 2,
        .circuit_id = 505,
        .start_time = 480,
        .stop_time = 1080,
        .day_mask = DayMask.every_day,
        .flags = ScheduleFlags.none,
        .heat_cmd = .no_change,
        .heat_setpoint = 0,
    };
    try testing.expect(!disabled.isEnabled());
}

test "Schedule.parse minimal" {
    const allocator = testing.allocator;

    // Minimal valid response: 0 events
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], 0, .little);

    var schedule = try Schedule.parse(&data, allocator);
    defer schedule.deinit();

    try testing.expectEqual(@as(usize, 0), schedule.events.len);
}

test "Schedule.parse with one event" {
    const allocator = testing.allocator;

    // Build a response with 1 event (32 bytes per event + 4 for count = 36 bytes)
    var data: [36]u8 = [_]u8{0} ** 36;
    var offset: usize = 0;

    // event_count = 1
    std.mem.writeInt(u32, data[offset..][0..4], 1, .little);
    offset += 4;

    // schedule_id = 100
    std.mem.writeInt(u32, data[offset..][0..4], 100, .little);
    offset += 4;

    // circuit_id = 505 (pool)
    std.mem.writeInt(u32, data[offset..][0..4], 505, .little);
    offset += 4;

    // start_time = 480 (8:00 AM)
    std.mem.writeInt(u32, data[offset..][0..4], 480, .little);
    offset += 4;

    // stop_time = 1080 (6:00 PM)
    std.mem.writeInt(u32, data[offset..][0..4], 1080, .little);
    offset += 4;

    // day_mask = every day (127) - u32 in wire format
    std.mem.writeInt(u32, data[offset..][0..4], DayMask.every_day, .little);
    offset += 4;

    // flags = enabled (2) - u32 in wire format
    std.mem.writeInt(u32, data[offset..][0..4], ScheduleFlags.enabled, .little);
    offset += 4;

    // heat_cmd = no_change (4) - u32 in wire format
    std.mem.writeInt(u32, data[offset..][0..4], 4, .little);
    offset += 4;

    // heat_setpoint = 85 - u32 in wire format
    std.mem.writeInt(u32, data[offset..][0..4], 85, .little);
    offset += 4;

    var schedule = try Schedule.parse(data[0..offset], allocator);
    defer schedule.deinit();

    try testing.expectEqual(@as(usize, 1), schedule.events.len);

    const event = schedule.events[0];
    try testing.expectEqual(@as(u32, 100), event.schedule_id);
    try testing.expectEqual(@as(u32, 505), event.circuit_id);
    try testing.expectEqual(@as(u32, 480), event.start_time);
    try testing.expectEqual(@as(u32, 1080), event.stop_time);
    try testing.expectEqual(DayMask.every_day, event.day_mask);
    try testing.expect(event.isEnabled());
    try testing.expectEqual(HeatCommand.no_change, event.heat_cmd);
    try testing.expectEqual(@as(u8, 85), event.heat_setpoint);
}
