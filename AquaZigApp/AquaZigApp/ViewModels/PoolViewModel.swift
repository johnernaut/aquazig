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

    func connect() async {
        isLoading = true
        errorMessage = nil

        do {
            // Try discovery first, fall back to known IP
            do {
                try await client.discoverAndConnect()
            } catch {
                // Discovery failed, try direct connection to known IP
                print("Discovery failed: \(error.localizedDescription), trying direct connection...")
                try await client.connect(host: "10.0.0.9", port: 80)
            }
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

        isLoading = false
    }

    func disconnect() {
        client.disconnect()
        isConnected = false
        status = nil
        pumpStatus = nil
        controllerConfig = nil
        schedule = nil
    }

    func refresh() async {
        isLoading = true

        do {
            status = try await client.getStatus()
            pumpStatus = try await client.getPumpStatus()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func setHeatMode(body: BodyType, mode: HeatMode) async {
        do {
            try await client.setHeatMode(body: body, mode: mode)
            // Refresh to get updated state
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setHeatSetpoint(body: BodyType, temperature: UInt32) async {
        do {
            try await client.setHeatSetpoint(body: body, temperature: temperature)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCircuitState(circuitId: UInt32, state: Bool) async {
        do {
            try await client.setCircuitState(circuitId: circuitId, state: state)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Spa/Pool Control

    func toggleSpa() async {
        let newState = !isSpaOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.spa, state: newState)
            isSpaOn = newState
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleHighSpeed() async {
        let newState = !isHighSpeedOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.highSpeed, state: newState)
            isHighSpeedOn = newState
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePool() async {
        let newState = !isPoolOn
        do {
            try await client.setCircuitState(circuitId: CircuitID.pool, state: newState)
            isPoolOn = newState
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
