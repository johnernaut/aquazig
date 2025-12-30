# AquaZig - Context for Claude

## Project Goal

Build a Zig library for communicating with Pentair ScreenLogic pool controllers. The library will be used in a future Swift UI application. Current focus is on the library with a CLI for testing.

## Critical Technical Details

### Zig Version
Using **Zig 0.15.2**. Key API differences from older versions:
- `build.zig.zon`: Use `.name = .aquazig` (enum literal), not `"aquazig"` (string)
- `build.zig.zon`: Requires `fingerprint` field
- `build.zig`: Use `b.createModule()` and `.root_module`, not `.root_source_file`
- ArrayList: Initialize with `.{}`, pass allocator to each method call
- I/O: Use `std.debug.print`, `posix.read/write` - old Stream API changed

### Protocol (from protocol_document.pdf)

**Discovery (UDP port 1444)**:
- Send 8 bytes: `[1, 0, 0, 0, 0, 0, 0, 0]`
- Response: IP (4 bytes) + port (u16 LE) + gateway info

**TCP Connection**:
1. Connect to IP:port
2. Send: `CONNECTSERVERHOST\r\n\r\n`
3. Send login (msg code 27) with schema=348, client="Android"
4. Receive login response (msg code 28)

**Message Format**:
```
MSG_CD1 (u16 LE) | MSG_CD2 (u16 LE) | Data Size (u32 LE) | Data
```

**Key Message Codes**:
- 27/28: Login
- 12522/12523: Add client (subscribe to push updates)
- 12524/12525: Remove client (unsubscribe)
- 12526/12527: Get status
- 12528/12529: Set heat setpoint
- 12530/12531: Button press (circuit control)
- 12532/12533: Get controller config
- 12538/12539: Set heat mode
- 12542/12543: Get schedule (recurring or one-time)
- 12584/12585: Get pump status
- 12586/12587: Set pump speed
- 12500: Async equipment state (push notification)

**Encoding**:
- All integers: little-endian
- Strings: u32 length prefix + data + padding to 4-byte boundary

## File Structure

```
src/
├── screenlogic.zig      # Public API - re-exports types
├── client.zig           # High-level Client struct (async via libxev)
├── c_api.zig            # C-compatible API for Swift/FFI
├── discovery.zig        # UDP broadcast discovery
├── main.zig             # CLI app
└── protocol/
    ├── encoding.zig     # Encoding utilities
    ├── messages.zig     # Message types & serialization
    ├── responses.zig    # Response parsing
    ├── pump.zig         # Pump status and control
    └── schedule.zig     # Schedule parsing (events, day masks)
```

## Key Types

- `Client` - Main interface, handles connection/auth (libxev async internally)
- `PoolStatus` - Pool/spa temperatures, circuit states, chemistry
- `ControllerConfig` - Controller info (hardware type, setpoint limits, circuits with names)
- `Circuit` - Circuit definition with ID, name, function, freeze protection
- `BodyStatus` - Pool or spa body (temp, heat mode, setpoints)
- `PumpStatus` - Pump type, running state, RPM/GPM/watts, circuit configs
- `Schedule` - Collection of scheduled events
- `ScheduledEvent` - Individual schedule (circuit, times, day mask, heat settings)
- `MessageType` - Enum of all protocol message codes

## Protocol Bugs Fixed

1. **UDP Discovery**: Was sending 1 byte, now sends 8 bytes
2. **Port Parsing**: Now uses proper little-endian read
3. **Schedule Parsing**: All fields are u32 (not u8 for day_mask/flags/heat_cmd/heat_setpoint)

## Code Style

- Clean, self-documenting code
- Comments only for complex logic
- Tests should be meaningful and test real interactions
- Use mocking only where appropriate

## Commands

```bash
zig build           # Build library and CLI
zig build run       # Run CLI
zig build test      # Run tests
```

## Dependencies

- libxev (mitchellh) - async I/O (now integrated)

## Current State

- Build passes, 50+ tests passing
- Library structure complete
- Protocol implementation done
- **libxev async I/O integrated** - client uses async internally with sync API
- **Real device tested** - works with ScreenLogic at 10.0.0.9:80
- **Pump control working** - IntelliFlo VSF tested
- **Swift app working** - macOS SwiftUI app with full control

### Features Implemented
- Discovery, connect, login
- Pool/spa status, controller config
- Controller info (hardware type, equipment flags)
- Circuit control, heat mode, temperature setpoints
- Pump status and speed control
- Schedule retrieval (recurring and one-time events)
- Status subscriptions (push updates via AddClient)
- Reconnection with exponential backoff
- Ping keepalive timer

### Swift/macOS App
- XCFramework build (arm64 + x86_64 universal binary)
- Swift wrapper with async/await API
- Dashboard UI: pool/spa temps, heat controls, pump status, chemistry
- Controller info display (hardware type, controller ID)
- Circuit names from controller config (Pool, Spa, Cleaner, etc.)
- Schedule display with circuit names, times, and active days
- Circuit controls: Spa, Pool, and High Speed toggles
- Discovery with fallback to direct IP connection
- LocalizedError for user-friendly error messages

### Protocol Fixes Applied
- Login handles unexpected push messages (weather forecasts) during authentication
- Skips non-login responses and continues reading until login_response arrives

### Test Coverage
- Encoding utilities (padding, round-trips)
- All message serialization (including GetScheduleQuery)
- Response parsing with realistic packet data
- Discovery response parsing
- Pump status parsing
- Schedule parsing (events, day masks, time formatting)
