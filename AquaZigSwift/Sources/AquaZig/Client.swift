import Foundation
import CAquaZig

/// Error type for AquaZig operations
public enum AquaZigError: Error, LocalizedError {
    case notConnected
    case loginFailed
    case invalidResponse
    case unexpectedMessage
    case timeout
    case connectionClosed
    case bufferTooSmall
    case outOfMemory
    case connectionFailed
    case alreadyConnected
    case unknown(Int32)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to device"
        case .loginFailed: return "Login failed"
        case .invalidResponse: return "Invalid response from device"
        case .unexpectedMessage: return "Unexpected message type"
        case .timeout: return "Operation timed out - no ScreenLogic device found"
        case .connectionClosed: return "Connection was closed"
        case .bufferTooSmall: return "Buffer too small"
        case .outOfMemory: return "Out of memory"
        case .connectionFailed: return "Connection failed - check network"
        case .alreadyConnected: return "Already connected"
        case .unknown(let code): return "Unknown error (code: \(code))"
        }
    }

    static func from(code: Int32) -> AquaZigError? {
        switch code {
        case AQUAZIG_OK: return nil
        case AQUAZIG_ERR_NOT_CONNECTED: return .notConnected
        case AQUAZIG_ERR_LOGIN_FAILED: return .loginFailed
        case AQUAZIG_ERR_INVALID_RESPONSE: return .invalidResponse
        case AQUAZIG_ERR_UNEXPECTED_MSG: return .unexpectedMessage
        case AQUAZIG_ERR_TIMEOUT: return .timeout
        case AQUAZIG_ERR_CONNECTION_CLOSED: return .connectionClosed
        case AQUAZIG_ERR_BUFFER_TOO_SMALL: return .bufferTooSmall
        case AQUAZIG_ERR_OUT_OF_MEMORY: return .outOfMemory
        case AQUAZIG_ERR_CONNECTION_FAILED: return .connectionFailed
        case AQUAZIG_ERR_ALREADY_CONNECTED: return .alreadyConnected
        default: return .unknown(code)
        }
    }
}

/// Connection state
public enum ConnectionState: Int32 {
    case disconnected = 0
    case connecting = 1
    case handshaking = 2
    case authenticating = 3
    case ready = 4
    case reconnecting = 5
    case failed = 6
}

/// High-level AquaZig client for SwiftUI
@MainActor
public class AquaZigClient: ObservableObject {
    private var handle: OpaquePointer?

    // Published properties for reactive UI
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var status: PoolStatus?
    @Published public private(set) var pumpStatus: PumpStatus?
    @Published public private(set) var lastError: AquaZigError?

    /// Create a new AquaZig client
    public init() {
        handle = aquazig_client_create()
    }

    /// Create a client with custom configuration
    public init(
        timeoutMs: UInt32 = 10000,
        pingIntervalMs: UInt32 = 30000,
        autoReconnect: Bool = true,
        maxReconnectAttempts: UInt32 = 10
    ) {
        handle = aquazig_client_create_with_config(
            timeoutMs,
            pingIntervalMs,
            autoReconnect,
            maxReconnectAttempts
        )
    }

    deinit {
        if let h = handle {
            aquazig_client_free(h)
        }
    }

    /// Discover and connect to a ScreenLogic device on the local network
    public func discoverAndConnect() async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        lastError = nil

        let result = await Task.detached {
            aquazig_discover_and_connect(h)
        }.value

        if let err = AquaZigError.from(code: result) {
            lastError = err
            throw err
        }

        isConnected = true
        connectionState = ConnectionState(rawValue: aquazig_get_state(h)) ?? .ready
    }

    /// Connect to a specific IP address and port
    public func connect(host: String, port: UInt16) async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        lastError = nil

        let result = await Task.detached {
            host.withCString { hostPtr in
                aquazig_connect(h, hostPtr, port)
            }
        }.value

        if let err = AquaZigError.from(code: result) {
            lastError = err
            throw err
        }

        isConnected = true
        connectionState = ConnectionState(rawValue: aquazig_get_state(h)) ?? .ready
    }

    /// Disconnect from the device
    public func disconnect() {
        guard let h = handle else { return }
        aquazig_disconnect(h)
        isConnected = false
        connectionState = .disconnected
    }

    /// Get current pool/spa status
    public func getStatus() async throws -> PoolStatus {
        guard let h = handle else { throw AquaZigError.notConnected }

        var cStatus = aquazig_pool_status_t()

        let result = await Task.detached {
            aquazig_get_status(h, &cStatus)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }

        let status = PoolStatus(from: cStatus)
        self.status = status
        return status
    }

    /// Get pump status
    public func getPumpStatus(pumpId: UInt32 = 0) async throws -> PumpStatus {
        guard let h = handle else { throw AquaZigError.notConnected }

        var cStatus = aquazig_pump_status_t()

        let result = await Task.detached {
            aquazig_get_pump_status(h, pumpId, &cStatus)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }

        let status = PumpStatus(from: cStatus)
        self.pumpStatus = status
        return status
    }

    /// Set circuit state (turn on/off)
    public func setCircuitState(circuitId: UInt32, state: Bool) async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_set_circuit_state(h, circuitId, state)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Set heat mode for pool or spa
    public func setHeatMode(body: BodyType, mode: HeatMode) async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_set_heat_mode(h, body.rawValue, mode.rawValue)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Set temperature setpoint for pool or spa
    public func setHeatSetpoint(body: BodyType, temperature: UInt32) async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_set_heat_setpoint(h, body.rawValue, temperature)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Set pump speed
    public func setPumpSpeed(
        pumpId: UInt32,
        circuitIndex: UInt32,
        speed: UInt32,
        isRpm: Bool
    ) async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_set_pump_speed(h, pumpId, circuitIndex, speed, isRpm)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Send ping to keep connection alive
    public func ping() async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_ping(h)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Subscribe to status change notifications
    public func subscribeToStatusChanges() async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_subscribe_status(h)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Unsubscribe from status change notifications
    public func unsubscribeFromStatusChanges() async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        let result = await Task.detached {
            aquazig_unsubscribe_status(h)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }
    }

    /// Attempt to reconnect
    public func reconnect() async throws {
        guard let h = handle else { throw AquaZigError.notConnected }

        connectionState = .reconnecting

        let result = await Task.detached {
            aquazig_reconnect(h)
        }.value

        if let err = AquaZigError.from(code: result) {
            connectionState = .failed
            lastError = err
            throw err
        }

        isConnected = true
        connectionState = .ready
    }

    /// Refresh status and pump data
    public func refresh() async throws {
        _ = try await getStatus()
        _ = try await getPumpStatus()
    }

    /// Get controller configuration info (basic)
    public func getControllerInfo() async throws -> ControllerInfo {
        guard let h = handle else { throw AquaZigError.notConnected }

        var cInfo = aquazig_controller_info_t()

        let result = await Task.detached {
            aquazig_get_controller_info(h, &cInfo)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }

        return ControllerInfo(from: cInfo)
    }

    /// Get full controller configuration including circuit names
    public func getControllerConfig() async throws -> ControllerConfig {
        guard let h = handle else { throw AquaZigError.notConnected }

        var cConfig = aquazig_controller_config_t()

        let result = await Task.detached {
            aquazig_get_controller_config(h, &cConfig)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }

        return ControllerConfig(from: cConfig)
    }

    /// Get schedule data
    ///
    /// - Parameter scheduleType: 0 = recurring schedules, 1 = one-time (run-once) events
    /// - Returns: Schedule containing all events
    public func getSchedule(scheduleType: UInt32 = 0) async throws -> Schedule {
        guard let h = handle else { throw AquaZigError.notConnected }

        var cSchedule = aquazig_schedule_t()

        let result = await Task.detached {
            aquazig_get_schedule(h, scheduleType, &cSchedule)
        }.value

        if let err = AquaZigError.from(code: result) {
            throw err
        }

        return Schedule(from: cSchedule)
    }
}
