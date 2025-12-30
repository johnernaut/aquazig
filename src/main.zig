const std = @import("std");
const screenlogic = @import("screenlogic");

const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n", .{});
    print("====================================\n", .{});
    print("  AquaZig - ScreenLogic Controller\n", .{});
    print("  Version {s}\n", .{screenlogic.version});
    print("====================================\n\n", .{});

    // Create client
    var client = try screenlogic.createClient(allocator);
    defer client.deinit();

    // Discover and connect
    print("Searching for ScreenLogic devices...\n", .{});

    client.discoverAndConnect() catch |err| {
        print("Failed to connect: {any}\n", .{err});
        print("\nTip: Make sure your ScreenLogic device is on the same network.\n", .{});
        return;
    };

    print("Connected!\n\n", .{});

    // Get controller configuration
    print("--- Controller Configuration ---\n", .{});
    var config = client.getControllerConfig() catch |err| {
        print("Failed to get config: {any}\n", .{err});
        return;
    };
    defer config.deinit();

    print("Controller ID: {d}\n", .{config.controller_id});
    print("Pool setpoint range: {d}F - {d}F\n", .{ config.min_setpoint_pool, config.max_setpoint_pool });
    print("Spa setpoint range: {d}F - {d}F\n", .{ config.min_setpoint_spa, config.max_setpoint_spa });
    print("Temperature unit: {s}\n", .{if (config.is_celsius) "Celsius" else "Fahrenheit"});

    if (config.circuits.len > 0) {
        print("\nCircuits:\n", .{});
        for (config.circuits) |circuit| {
            print("  [{d}] {s}\n", .{ circuit.id, circuit.name });
        }
    }

    // Get pool status
    print("\n--- Pool Status ---\n", .{});
    var status = client.getStatus() catch |err| {
        print("Failed to get status: {any}\n", .{err});
        return;
    };
    defer status.deinit();

    print("System OK: {}\n", .{status.ok});
    print("Freeze mode: {}\n", .{status.freeze_mode});
    print("Air temp: {d}F\n", .{status.air_temp});

    if (status.bodies.pool) |pool| {
        print("\nPool:\n", .{});
        print("  Current temp: {d}F\n", .{pool.current_temp});
        print("  Heat setpoint: {d}F\n", .{pool.heat_setpoint});
        print("  Heat mode: {s}\n", .{@tagName(pool.heat_mode)});
        print("  Heater running: {}\n", .{pool.heat_status});
    }

    if (status.bodies.spa) |spa| {
        print("\nSpa:\n", .{});
        print("  Current temp: {d}F\n", .{spa.current_temp});
        print("  Heat setpoint: {d}F\n", .{spa.heat_setpoint});
        print("  Heat mode: {s}\n", .{@tagName(spa.heat_mode)});
        print("  Heater running: {}\n", .{spa.heat_status});
    }

    if (status.circuits.len > 0) {
        print("\nActive circuits:\n", .{});
        var has_active = false;
        for (status.circuits) |circuit| {
            if (circuit.state) {
                has_active = true;
                // Try to find circuit name from config
                var name: []const u8 = "Unknown";
                for (config.circuits) |c| {
                    if (c.id == circuit.id) {
                        name = c.name;
                        break;
                    }
                }
                print("  [{d}] {s} - ON\n", .{ circuit.id, name });
            }
        }
        if (!has_active) {
            print("  (none)\n", .{});
        }
    }

    // Chemistry data if available
    if (status.ph != null or status.orp != null or status.salt_ppm != null) {
        print("\nChemistry:\n", .{});
        if (status.ph) |ph| {
            print("  pH: {d:.2}\n", .{ph});
        }
        if (status.orp) |orp| {
            print("  ORP: {d} mV\n", .{orp});
        }
        if (status.salt_ppm) |salt| {
            print("  Salt: {d} ppm\n", .{salt});
        }
        if (status.saturation) |sat| {
            print("  Saturation index: {d:.2}\n", .{sat});
        }
    }

    // Get pump status (pump 0)
    print("\n--- Pump Status ---\n", .{});
    if (client.getPumpStatus(0)) |pump_status| {
        print("Type: {s}\n", .{@tagName(pump_status.pump_type)});
        print("Running: {}\n", .{pump_status.is_running});
        print("Power: {d} watts\n", .{pump_status.watts});
        print("Speed: {d} RPM, {d} GPM\n", .{ pump_status.rpm, pump_status.gpm });

        print("\nCircuit speed presets:\n", .{});
        for (pump_status.circuits, 0..) |circuit, i| {
            if (circuit.circuit_id != 0) {
                print("  [{d}] Circuit {d}: {d} {s}\n", .{
                    i,
                    circuit.circuit_id,
                    circuit.speed,
                    if (circuit.is_rpm) "RPM" else "GPM",
                });
            }
        }
    } else |err| {
        print("Failed to get pump status: {any}\n", .{err});
    }

    // Get schedules
    print("\n--- Schedules ---\n", .{});
    if (client.getSchedule(0)) |sched_const| {
        var sched = sched_const;
        defer sched.deinit();
        print("Found {d} scheduled events:\n", .{sched.events.len});
        for (sched.events) |event| {
            // Find circuit name
            var circuit_name: []const u8 = "Unknown";
            for (config.circuits) |c| {
                if (c.id == event.circuit_id) {
                    circuit_name = c.name;
                    break;
                }
            }
            print("  Schedule {d}: Circuit {d} ({s})\n", .{ event.schedule_id, event.circuit_id, circuit_name });
            print("    Time: {d:0>2}:{d:0>2} - {d:0>2}:{d:0>2}\n", .{
                event.start_time / 60,
                event.start_time % 60,
                event.stop_time / 60,
                event.stop_time % 60,
            });
            print("    Days: 0x{X:0>2}, Enabled: {}\n", .{ event.day_mask, event.isEnabled() });
        }
    } else |err| {
        print("Failed to get schedules: {any}\n", .{err});
    }

    print("\n====================================\n", .{});
    print("Done!\n", .{});
}
