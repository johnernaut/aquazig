# AquaZig - ScreenLogic Pool Controller Library

## Overview

A Zig library for communicating with Pentair ScreenLogic pool controllers. Designed as a shared library for SwiftUI integration, enabling native macOS and iOS applications with a single Zig backend. Includes a CLI for testing and debugging.

## Architecture

```
src/
├── screenlogic.zig      # Main library module - re-exports public API
├── client.zig           # High-level ScreenLogic client (async via libxev)
├── c_api.zig            # C-ABI export layer for Swift/Objective-C interop
├── discovery.zig        # UDP broadcast discovery
├── main.zig             # CLI application
└── protocol/
    ├── encoding.zig     # Little-endian encoding utilities
    ├── messages.zig     # Message types and serialization
    ├── responses.zig    # Response parsing (PoolStatus, ControllerConfig)
    └── pump.zig         # Pump status and control messages
```

## Protocol Reference

Primary sources:
- `protocol_document.pdf` - Official Pentair protocol documentation
- [node-screenlogic](https://github.com/parnic/node-screenlogic) - Reference implementation for field ordering

### Discovery (UDP Broadcast)

- **Port**: 1444
- **Request**: 8-byte packet `[1, 0, 0, 0, 0, 0, 0, 0]`
- **Response** (12 bytes):
  ```
  | Check digit (u32 LE, must be 2) | IP address (4 bytes) | Port (u16 LE) | Gateway type (u8) | Gateway subtype (u8) |
  ```

### Connection Handshake (TCP)

1. Connect to discovered IP:port
2. Send ASCII: `CONNECTSERVERHOST\r\n\r\n`
3. Send login message (code 27) with schema 348 and connection type 0
4. Receive login response (code 28)

### Message Frame Format

All TCP messages use this 8-byte header followed by data:
```
| MSG_CD1 (u16 LE) | MSG_CD2 (u16 LE) | Data Size (u32 LE) | Data... |
```
- MSG_CD1 and MSG_CD2 are typically the same (message code)
- Data size is the byte count of the payload (excluding header)

### Message Codes

| Query | Response | Description |
|-------|----------|-------------|
| 16 | 17 | Ping |
| 27 | 28 | Login |
| 12522 | 12523 | Add client (subscribe to push updates) |
| 12524 | 12525 | Remove client (unsubscribe) |
| 12526 | 12527 | Get equipment status |
| 12528 | 12529 | Set heat setpoint |
| 12530 | 12531 | Button press (circuit control) |
| 12532 | 12533 | Get controller configuration |
| 12538 | 12539 | Set heat mode |
| 12584 | 12585 | Get pump status |
| 12586 | 12587 | Set pump speed |
| - | 12500 | Async equipment state (push notification) |

### Data Encoding Rules

- **Integers**: Little-endian byte order
- **Strings**: Length-prefixed (u32 LE) + data + padding to 4-byte boundary
- **Booleans**: u32 where 0 = false, non-zero = true

### Response Data Structures

#### Controller Config (12533) - Circuit Entry Format

Each circuit in the config response has this structure:
```
| Circuit ID (u32) | Name (padded string) | Extra fields (12 bytes) |
```

The 12 extra bytes per circuit:
```
| nameIndex (u8) | function (u8) | interface (u8) | freeze (u8) |
| colorSet (u8)  | colorPos (u8) | colorStagger (u8) | deviceId (u8) |
| eggTimer (u16 LE) | reserved (u16) |
```

#### Pool Status (12527) - Body Entry Format

Each body (pool/spa) in the status response:
```
| body_type (u32) | current_temp (i32) | heat_status (u32) |
| heat_setpoint (i32) | cool_setpoint (i32) | heat_mode (u32) |
```

**Important**: `heat_status` comes BEFORE `heat_setpoint` - this differs from what you might expect and was discovered by testing against real hardware.

#### Pump Status (12585) - Response Format

```
| pump_type (u32)      | 1=VF, 2=VS, 3=VSF
| is_running (u32)     | 0=stopped, non-zero=running
| watts (u32)          | Current power consumption
| rpm (u32)            | Current RPM
| unknown1 (u32)       | Always 0
| gpm (u32)            | Current GPM (flow rate)
| unknown2 (u32)       | Always 255
| circuits[8]          | 8 circuit entries (see below)
```

Each pump circuit entry (12 bytes):
```
| circuit_id (u32)     | Controller circuit ID (e.g., 505 for Pool)
| speed (u32)          | Configured speed for this circuit
| is_rpm (u32)         | 0=GPM mode, non-zero=RPM mode
```

**Note**: The circuit configurations show *preset speeds* for when each circuit activates. When `is_running=false`, the rpm/gpm/watts will be 0. The pump runs at the configured speed when its associated circuit turns on.

## Completed Work

### Build System (Zig 0.15.2)
- [x] Updated `build.zig.zon` with enum literal `.aquazig` syntax
- [x] Added required `fingerprint` field
- [x] Updated `build.zig` to use new module API (`b.createModule`, `.root_module`)
- [x] libxev dependency configured (for future async support)

### Protocol Implementation
- [x] `encoding.zig` - Little-endian I/O, padded strings, 4-byte alignment
- [x] `messages.zig` - All message types from protocol doc
- [x] `responses.zig` - PoolStatus and ControllerConfig parsing

### Protocol Bug Fixes
- [x] UDP discovery sends correct 8-byte packet (was sending 1 byte)
- [x] Port parsing uses proper little-endian read
- [x] Circuit parsing reads all 12 extra bytes per circuit
- [x] Body status field order corrected (heat_status before heat_setpoint)

### Real Device Testing
- [x] Discovery works on local network (found device at 10.0.0.9:80)
- [x] Login handshake successful
- [x] Controller config parsing (18 circuits discovered)
- [x] Pool status parsing (temperatures, setpoints, heat modes)

### Library Structure
- [x] Clean public API in `screenlogic.zig`
- [x] High-level `Client` with methods: `discoverAndConnect`, `getStatus`, `getControllerConfig`, `setCircuitState`, `setHeatMode`, `setTemperature`, `ping`
- [x] Response structs with proper memory management (`deinit`)

### CLI
- [x] Basic CLI that discovers, connects, and prints pool stats
- [x] Displays pump status with circuit configurations

### Testing (46+ tests passing)
- [x] Encoding utilities (round-trip, padding, edge cases)
- [x] Message serialization (all query types)
- [x] Response parsing (PoolStatus, ChemData with realistic data)
- [x] Discovery response parsing
- [x] Pump status parsing and query serialization

### Async I/O (libxev)
- [x] Rewrote `client.zig` to use libxev for async I/O
- [x] Connection state machine (disconnected → connecting → handshaking → authenticating → ready)
- [x] Synchronous API wrapper over async internals
- [x] Ping timer infrastructure (30s keepalive, fires during operations)

### Status Subscriptions
- [x] `subscribeToStatusChanges()` - sends AddClient (12522) message
- [x] `unsubscribeFromStatusChanges()` - sends RemoveClient (12524) message
- [x] Device pushes status updates via message code 12500

### Reconnection Logic
- [x] `reconnect()` method with exponential backoff
- [x] Configurable max attempts and delay bounds
- [x] Auto-reconnect on connection errors (when enabled)

### Pump Control
- [x] `getPumpStatus(pump_id)` - returns type, running state, watts, RPM, GPM, circuit configs
- [x] `setPumpSpeed(pump_id, circuit_index, speed, is_rpm)` - adjust pump speed
- [x] Tested against IntelliFlo VSF pump

## SwiftUI Integration Plan

### Goal
Create native macOS and iOS pool controller apps using AquaZig as the shared backend.

### Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Layer                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  AquaZigApp.swift          PoolViewModel.swift      │    │
│  │  ContentView.swift         SettingsView.swift       │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│  ┌─────────────────────────▼───────────────────────────┐    │
│  │              AquaZig.Client.swift                    │    │
│  │  - Wraps opaque aquazig_client_t handle             │    │
│  │  - @Published properties for reactive UI            │    │
│  │  - Swift async/await wrappers                       │    │
│  │  - Handles memory lifecycle (deinit calls free)     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
                    XCFramework
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                    C-ABI Layer (Zig)                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  src/c_api.zig                                       │    │
│  │  - export fn aquazig_client_create()                │    │
│  │  - export fn aquazig_client_free()                  │    │
│  │  - export fn aquazig_discover_and_connect()         │    │
│  │  - export fn aquazig_get_status()                   │    │
│  │  - Callback function pointer pattern                │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│  ┌─────────────────────────▼───────────────────────────┐    │
│  │              Existing AquaZig Core                   │    │
│  │  client.zig, discovery.zig, protocol/*              │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Phases

#### Phase 1: C-ABI Export Layer (Done)
**Created `src/c_api.zig`** with C-compatible exports using Ghostty-inspired patterns:
- `export fn` for C-callable functions
- `extern struct` for C ABI-compatible memory layout
- Opaque handle pattern: `pub const aquazig_client_t = opaque {};`
- Error codes as c_int return values
- Callback function pointers with userdata

**Exports implemented:**
```zig
// Lifecycle
export fn aquazig_client_create() ?*aquazig_client_t
export fn aquazig_client_free(client: *aquazig_client_t) void

// Connection
export fn aquazig_discover_and_connect(client: *aquazig_client_t) c_int
export fn aquazig_connect(client: *aquazig_client_t, host: [*:0]const u8, port: u16) c_int
export fn aquazig_disconnect(client: *aquazig_client_t) void
export fn aquazig_is_connected(client: *aquazig_client_t) bool

// Status
export fn aquazig_get_status(client: *aquazig_client_t, out: *aquazig_pool_status_t) c_int

// Control
export fn aquazig_set_circuit_state(client: *aquazig_client_t, circuit_id: u32, state: bool) c_int
export fn aquazig_set_heat_mode(client: *aquazig_client_t, body_id: u32, mode: u32) c_int
export fn aquazig_set_heat_setpoint(client: *aquazig_client_t, body_id: u32, temp: u32) c_int

// Pump
export fn aquazig_get_pump_status(client: *aquazig_client_t, pump_id: u32, out: *aquazig_pump_status_t) c_int
export fn aquazig_set_pump_speed(...) c_int
```

#### Phase 2: C Header File (Done)
**Created `include/aquazig.h`** declaring all exported functions and types for Swift bridging.

#### Phase 3: Build System Updates (Done)
**Modified `build.zig`** with library targets:
- Shared library for macOS (.dylib)
- XCFramework creation script (`scripts/build-xcframework.sh`)
- Universal binary (arm64 + x86_64) via lipo

#### Phase 4: Swift Package (Done)
**Created `AquaZigSwift/` directory:**
```
AquaZigSwift/
├── Package.swift
├── Sources/AquaZig/
│   ├── Client.swift        # Main wrapper class with async/await
│   └── Models.swift        # Swift model types (PoolStatus, PumpStatus, etc.)
```

Key patterns used:
- `@MainActor class AquaZigClient: ObservableObject`
- `@Published` properties for reactive UI
- `deinit` calls `aquazig_client_free()`
- `async` wrappers using `Task.detached` for blocking Zig calls
- `LocalizedError` for user-friendly error messages

#### Phase 5: macOS App (Done)
**Created `AquaZigApp/` Xcode project:**
```
AquaZigApp/
├── AquaZigApp.swift           # @main entry
├── ContentView.swift          # Dashboard with all views
└── ViewModels/
    └── PoolViewModel.swift    # ObservableObject with all logic
```

**Features implemented:**
- Auto-connect on launch with discovery fallback to direct IP
- Status header (air temp, system OK, freeze protection)
- Body cards (pool/spa) with temp, setpoint, heat mode menu
- Circuit control card with Spa/Pool on/off toggle buttons
- Pump card with RPM, GPM, watts, running status
- Chemistry card with pH, ORP, salt PPM
- Error handling with retry button
- Pull-to-refresh via toolbar button

### Key Design Decisions

1. **Opaque handle pattern**: Swift holds `OpaquePointer` to Zig-allocated Client. Swift owns lifecycle via `deinit`.

2. **Synchronous Zig, async Swift**: Zig API stays synchronous (internal libxev). Swift wraps in `Task.detached` for async/await.

3. **Push notifications via callbacks**: Status changes use C function pointer with userdata pattern, converted to `@Published` property updates on MainActor.

4. **Value types for data**: Status, Circuit, PumpStatus are Swift structs copied from C structs. No shared memory concerns.

5. **Error handling**: Zig returns error codes, Swift converts to typed errors.

### Files to Create/Modify

| File | Status | Description |
|------|--------|-------------|
| `src/c_api.zig` | Done | C-ABI export layer |
| `include/aquazig.h` | Done | Public C header |
| `build.zig` | Done | Library targets added |
| `scripts/build-xcframework.sh` | Done | XCFramework build script |
| `AquaZigSwift/` | Done | Swift package with Client wrapper |
| `AquaZigApp/` | Done | macOS SwiftUI app |

### Build Instructions

1. **Build the XCFramework:**
   ```bash
   ./scripts/build-xcframework.sh
   ```

2. **Use in Swift project:**
   Add `AquaZigSwift` as a local package dependency pointing to the `AquaZigSwift/` directory.

## Known Issues & Quirks

### ScreenLogic Controller Sync
The ScreenLogic controller sometimes reports incorrect circuit states (e.g., shows everything OFF when circuits are actually ON). This is a hardware/firmware issue, not a library bug - the official Pentair app shows the same incorrect data. The controller eventually syncs correctly.

### Login Race Condition
During login, the controller may push status update messages (e.g., weather forecasts) before sending the login response. The client now skips these unexpected messages and continues reading until the login response arrives.

### Circuit IDs
Well-known circuit IDs (may vary by installation):
- Spa: 500
- Pool: 505

### Discovery Fallback
UDP discovery may fail on some networks. The app falls back to direct connection at a known IP (currently hardcoded to 10.0.0.9:80).

## Future Enhancements

### Core Library
- [x] ~~Use libxev for async I/O~~ (completed)
- [x] ~~Add reconnection logic with exponential backoff~~ (completed)
- [x] ~~Connection keepalive with ping messages~~ (completed)
- [x] ~~Status change subscriptions (AddClient message)~~ (completed)

### Protocol Features
- [ ] Schedule management (read/write schedules)
- [ ] Chemistry data (IntelliChem) support
- [x] ~~Pump speed control~~ (completed)
- [ ] Light color/mode control (IntelliBrite)
- [ ] Firmware version detection

### Testing
- [ ] Integration tests with mock server
- [ ] Packet capture replay tests
- [ ] Fuzz testing for response parsers

### SwiftUI Integration
- [x] ~~C-ABI export layer~~ (completed - `src/c_api.zig`)
- [x] ~~C header file~~ (completed - `include/aquazig.h`)
- [x] ~~Build system for library targets~~ (completed)
- [x] ~~XCFramework build script~~ (completed - `scripts/build-xcframework.sh`)
- [x] ~~Swift package with async wrappers~~ (completed - `AquaZigSwift/`)
- [x] ~~macOS SwiftUI app~~ (completed - `AquaZigApp/`)
  - Dashboard with pool/spa temperatures and heat controls
  - Pump status display (RPM, GPM, watts)
  - Circuit controls (Spa/Pool on/off toggles)
  - Chemistry data display (pH, ORP, salt)
  - Discovery with fallback to direct IP
- [ ] iOS app with widgets
- [ ] Apple Watch complication

## Usage

### Build
```bash
zig build
```

### Run CLI
```bash
zig build run
```

### Run Tests
```bash
zig build test
```

### Library Usage
```zig
const screenlogic = @import("screenlogic");

var client = try screenlogic.createClient(allocator);
defer client.deinit();

try client.discoverAndConnect();

// Get pool/spa status
var status = try client.getStatus();
defer status.deinit();

if (status.bodies.pool) |pool| {
    std.debug.print("Pool temp: {d}F\n", .{pool.current_temp});
}

// Get pump status
const pump_status = try client.getPumpStatus(0);
std.debug.print("Pump: {d} RPM, {d} watts\n", .{pump_status.rpm, pump_status.watts});

// Subscribe to push updates
try client.subscribeToStatusChanges();
```

## Dependencies
- Zig 0.15.2+
- libxev (async I/O)
