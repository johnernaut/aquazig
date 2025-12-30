import Foundation
import CAquaZig

/// Body type (pool or spa)
public enum BodyType: UInt32 {
    case pool = 0
    case spa = 1
}

/// Heat mode settings
public enum HeatMode: UInt32, CustomStringConvertible {
    case off = 0
    case solar = 1
    case solarPreferred = 2
    case heater = 3

    public var description: String {
        switch self {
        case .off: return "Off"
        case .solar: return "Solar"
        case .solarPreferred: return "Solar Preferred"
        case .heater: return "Heater"
        }
    }
}

/// Pump type
public enum PumpType: UInt32, CustomStringConvertible {
    case unknown = 0
    case variableFlow = 1
    case variableSpeed = 2
    case variableSpeedFlow = 3

    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .variableFlow: return "Variable Flow (VF)"
        case .variableSpeed: return "Variable Speed (VS)"
        case .variableSpeedFlow: return "Variable Speed/Flow (VSF)"
        }
    }
}

/// Body (pool/spa) status
public struct BodyStatus: Equatable {
    public let currentTemp: Int32
    public let heatSetpoint: Int32
    public let coolSetpoint: Int32
    public let heatMode: HeatMode
    public let heaterRunning: Bool
    public let isValid: Bool

    init(from c: aquazig_body_status_t) {
        self.currentTemp = c.current_temp
        self.heatSetpoint = c.heat_setpoint
        self.coolSetpoint = c.cool_setpoint
        self.heatMode = HeatMode(rawValue: c.heat_mode) ?? .off
        self.heaterRunning = c.heat_status
        self.isValid = c.is_valid
    }
}

/// Pool/spa overall status
public struct PoolStatus: Equatable {
    public let ok: Bool
    public let freezeMode: Bool
    public let airTemp: Int32

    public let pool: BodyStatus
    public let spa: BodyStatus

    // Chemistry data (nil if not available)
    public let ph: Float?
    public let orp: Int32?
    public let saltPPM: Int32?
    public let saturation: Float?

    init(from c: aquazig_pool_status_t) {
        self.ok = c.ok
        self.freezeMode = c.freeze_mode
        self.airTemp = c.air_temp
        self.pool = BodyStatus(from: c.pool)
        self.spa = BodyStatus(from: c.spa)

        // Chemistry is optional (0 means not available)
        self.ph = c.ph > 0 ? c.ph : nil
        self.orp = c.orp > 0 ? c.orp : nil
        self.saltPPM = c.salt_ppm > 0 ? c.salt_ppm : nil
        self.saturation = c.saturation != 0 ? c.saturation : nil
    }
}

/// Pump circuit configuration
public struct PumpCircuit: Equatable {
    public let circuitId: UInt32
    public let speed: UInt32
    public let isRpm: Bool

    init(from c: aquazig_pump_circuit_t) {
        self.circuitId = c.circuit_id
        self.speed = c.speed
        self.isRpm = c.is_rpm
    }
}

/// Pump status
public struct PumpStatus: Equatable {
    public let pumpType: PumpType
    public let isRunning: Bool
    public let watts: UInt32
    public let rpm: UInt32
    public let gpm: UInt32
    public let circuits: [PumpCircuit]

    init(from c: aquazig_pump_status_t) {
        self.pumpType = PumpType(rawValue: c.pump_type) ?? .unknown
        self.isRunning = c.is_running
        self.watts = c.watts
        self.rpm = c.rpm
        self.gpm = c.gpm

        // Convert fixed array to Swift array
        var circuits: [PumpCircuit] = []
        let mirror = Mirror(reflecting: c.circuits)
        for child in mirror.children {
            if let circuit = child.value as? aquazig_pump_circuit_t {
                circuits.append(PumpCircuit(from: circuit))
            }
        }
        self.circuits = circuits
    }
}

/// Circuit info
public struct Circuit: Equatable, Identifiable {
    public let id: UInt32
    public let state: Bool

    init(from c: aquazig_circuit_t) {
        self.id = c.id
        self.state = c.state
    }
}
