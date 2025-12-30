import SwiftUI
import AquaZig

// Well-known circuit IDs
enum CircuitID {
    static let spa: UInt32 = 500
    static let highSpeed: UInt32 = 504
    static let pool: UInt32 = 505
}

@MainActor
class PoolViewModel: ObservableObject {
    private let client = AquaZigClient()

    // State
    @Published var isLoading = false
    @Published var isConnected = false
    @Published var errorMessage: String?

    // Prevent multiple simultaneous connection attempts
    private var isConnecting = false
    private var hasAttemptedInitialConnection = false

    // Circuit states (tracked locally, updated on toggle)
    @Published var isSpaOn = false
    @Published var isHighSpeedOn = false
    @Published var isPoolOn = false

    // Data
    @Published var status: PoolStatus?
    @Published var pumpStatus: PumpStatus?
    @Published var controllerConfig: ControllerConfig?
    @Published var schedule: Schedule?

    // Convenience accessor for backward compatibility
    var controllerInfo: ControllerConfig? { controllerConfig }

    // Computed properties
    var poolBody: BodyStatus? {
        guard let s = status, s.pool.isValid else { return nil }
        return s.pool
    }

    var spaBody: BodyStatus? {
        guard let s = status, s.spa.isValid else { return nil }
        return s.spa
    }

    var hasChemistry: Bool {
        guard let s = status else { return false }
        return s.ph != nil || s.orp != nil || s.saltPPM != nil
    }

    /// Get circuit name by ID, falling back to "Circuit {id}" if not found
    func circuitName(forId id: UInt32) -> String {
        controllerConfig?.circuitName(forId: id) ?? "Circuit \(id)"
    }

    // MARK: - Actions

    /// Called automatically on first view appear
    func connectIfNeeded() async {
        guard !hasAttemptedInitialConnection else { return }
        hasAttemptedInitialConnection = true
        await connect()
    }

    func connect() async {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            print("Connection already in progress, skipping")
            return
        }

        isConnecting = true
        isLoading = true
        errorMessage = nil

        defer {
            isConnecting = false
            isLoading = false
        }

        do {
            try await client.discoverAndConnect()
            isConnected = true

            // Get initial status and config
            status = try await client.getStatus()
            pumpStatus = try await client.getPumpStatus()
            controllerConfig = try await client.getControllerConfig()
            schedule = try? await client.getSchedule()  // Don't fail connect if schedule fails

            // Subscribe to push updates
            try await client.subscribeToStatusChanges()
        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }
    }

    func disconnect() {
        client.disconnect()
        isConnected = false
        status = nil
        pumpStatus = nil
        controllerConfig = nil
        schedule = nil
        // Allow reconnection after manual disconnect
        hasAttemptedInitialConnection = false
    }

    func refresh() async {
        guard isConnected else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            status = try await client.getStatus()
            pumpStatus = try await client.getPumpStatus()
            errorMessage = nil
        } catch {
            // Connection likely lost
            handleConnectionError(error)
        }
    }

    private func handleConnectionError(_ error: Error) {
        errorMessage = error.localizedDescription

        // Check if this is a connection-related error
        if let aquaError = error as? AquaZigError {
            switch aquaError {
            case .notConnected, .connectionClosed, .timeout, .connectionFailed:
                isConnected = false
                hasAttemptedInitialConnection = false  // Allow reconnection
            default:
                break
            }
        }
    }

    func setHeatMode(body: BodyType, mode: HeatMode) async {
        guard isConnected else { return }

        do {
            try await client.setHeatMode(body: body, mode: mode)
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }

    func setHeatSetpoint(body: BodyType, temperature: UInt32) async {
        guard isConnected else { return }

        do {
            try await client.setHeatSetpoint(body: body, temperature: temperature)
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }

    func setCircuitState(circuitId: UInt32, state: Bool) async {
        guard isConnected else { return }

        do {
            try await client.setCircuitState(circuitId: circuitId, state: state)
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }

    // MARK: - Spa/Pool Control

    func toggleSpa() async {
        guard isConnected else { return }

        let newState = !isSpaOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.spa, state: newState)
            isSpaOn = newState
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }

    func toggleHighSpeed() async {
        guard isConnected else { return }

        let newState = !isHighSpeedOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.highSpeed, state: newState)
            isHighSpeedOn = newState
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }

    func togglePool() async {
        guard isConnected else { return }

        let newState = !isPoolOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.pool, state: newState)
            isPoolOn = newState
            await refresh()
        } catch {
            handleConnectionError(error)
        }
    }
}
