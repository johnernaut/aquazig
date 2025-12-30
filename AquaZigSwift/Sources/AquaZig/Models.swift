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

/// Controller info
public struct ControllerInfo: Equatable {
    public let controllerId: UInt32
    public let controllerType: UInt8
    public let hardwareType: UInt8
    public let controllerData: UInt8
    public let equipmentFlags: UInt8
    public let isCelsius: Bool
    public let minSetpointPool: UInt8
    public let maxSetpointPool: UInt8
    public let minSetpointSpa: UInt8
    public let maxSetpointSpa: UInt8

    /// Human-readable hardware type description
    public var hardwareTypeDescription: String {
        switch hardwareType {
        case 0: return "IntelliTouch i5+3"
        case 1: return "IntelliTouch i7+3"
        case 2: return "IntelliTouch i9+3"
        case 3: return "IntelliTouch i5+3S"
        case 4: return "IntelliTouch i9+3S"
        case 5: return "IntelliTouch i10+3D"
        case 10: return "IntelliTouch"
        case 11: return "IntelliCom II"
        case 13: return "EasyTouch 8"
        case 14: return "EasyTouch 4"
        case 23: return "EasyTouch PL4"
        case 24: return "EasyTouch PSL4"
        default: return "Unknown (\(hardwareType))"
        }
    }

    init(from c: aquazig_controller_info_t) {
        self.controllerId = c.controller_id
        self.controllerType = c.controller_type
        self.hardwareType = c.hardware_type
        self.controllerData = c.controller_data
        self.equipmentFlags = c.equipment_flags
        self.isCelsius = c.is_celsius
        self.minSetpointPool = c.min_setpoint_pool
        self.maxSetpointPool = c.max_setpoint_pool
        self.minSetpointSpa = c.min_setpoint_spa
        self.maxSetpointSpa = c.max_setpoint_spa
    }
}

/// Circuit info with name
public struct CircuitInfo: Equatable, Identifiable {
    public var id: UInt32 { circuitId }

    public let circuitId: UInt32
    public let name: String
    public let nameIndex: UInt8
    public let function: UInt8
    public let interface: UInt8
    public let freeze: Bool
    public let deviceId: UInt8

    init(from c: aquazig_circuit_info_t) {
        self.circuitId = c.id
        // Convert C string (fixed buffer) to Swift String
        self.name = withUnsafePointer(to: c.name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 32) { cStr in
                String(cString: cStr)
            }
        }
        self.nameIndex = c.name_index
        self.function = c.function
        self.interface = c.interface
        self.freeze = c.freeze != 0
        self.deviceId = c.device_id
    }
}

/// Full controller configuration with circuits
public struct ControllerConfig: Equatable {
    public let controllerId: UInt32
    public let controllerType: UInt8
    public let hardwareType: UInt8
    public let controllerData: UInt8
    public let equipmentFlags: UInt8
    public let isCelsius: Bool
    public let minSetpointPool: UInt8
    public let maxSetpointPool: UInt8
    public let minSetpointSpa: UInt8
    public let maxSetpointSpa: UInt8
    public let circuits: [CircuitInfo]

    /// Human-readable hardware type description
    public var hardwareTypeDescription: String {
        switch hardwareType {
        case 0: return "IntelliTouch i5+3"
        case 1: return "IntelliTouch i7+3"
        case 2: return "IntelliTouch i9+3"
        case 3: return "IntelliTouch i5+3S"
        case 4: return "IntelliTouch i9+3S"
        case 5: return "IntelliTouch i10+3D"
        case 10: return "IntelliTouch"
        case 11: return "IntelliCom II"
        case 13: return "EasyTouch 8"
        case 14: return "EasyTouch 4"
        case 23: return "EasyTouch PL4"
        case 24: return "EasyTouch PSL4"
        default: return "Unknown (\(hardwareType))"
        }
    }

    /// Get circuit by ID
    public func circuit(withId id: UInt32) -> CircuitInfo? {
        circuits.first { $0.circuitId == id }
    }

    /// Get circuit name by ID (returns nil if not found)
    public func circuitName(forId id: UInt32) -> String? {
        circuit(withId: id)?.name
    }

    init(from c: aquazig_controller_config_t) {
        self.controllerId = c.controller_id
        self.controllerType = c.controller_type
        self.hardwareType = c.hardware_type
        self.controllerData = c.controller_data
        self.equipmentFlags = c.equipment_flags
        self.isCelsius = c.is_celsius
        self.minSetpointPool = c.min_setpoint_pool
        self.maxSetpointPool = c.max_setpoint_pool
        self.minSetpointSpa = c.min_setpoint_spa
        self.maxSetpointSpa = c.max_setpoint_spa

        // Convert circuits array
        var circuits: [CircuitInfo] = []
        let count = Int(min(c.circuit_count, 20))
        let mirror = Mirror(reflecting: c.circuits)
        for (index, child) in mirror.children.enumerated() {
            if index >= count { break }
            if let circuit = child.value as? aquazig_circuit_info_t {
                circuits.append(CircuitInfo(from: circuit))
            }
        }
        self.circuits = circuits
    }
}

/// Heat command for schedule events
public enum ScheduleHeatCommand: UInt8, CustomStringConvertible {
    case off = 0
    case heater = 1
    case solarPref = 2
    case solar = 3
    case noChange = 4

    public var description: String {
        switch self {
        case .off: return "Off"
        case .heater: return "Heater"
        case .solarPref: return "Solar Preferred"
        case .solar: return "Solar"
        case .noChange: return "No Change"
        }
    }
}

/// Day mask for schedule events
public struct DayMask: OptionSet {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let sunday = DayMask(rawValue: 0x01)
    public static let monday = DayMask(rawValue: 0x02)
    public static let tuesday = DayMask(rawValue: 0x04)
    public static let wednesday = DayMask(rawValue: 0x08)
    public static let thursday = DayMask(rawValue: 0x10)
    public static let friday = DayMask(rawValue: 0x20)
    public static let saturday = DayMask(rawValue: 0x40)
    public static let everyDay: DayMask = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    public static let weekdays: DayMask = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekends: DayMask = [.saturday, .sunday]

    /// Human-readable description of the day mask
    public var description: String {
        if self == .everyDay { return "Every Day" }
        if self == .weekdays { return "Weekdays" }
        if self == .weekends { return "Weekends" }

        var days: [String] = []
        if contains(.sunday) { days.append("Sun") }
        if contains(.monday) { days.append("Mon") }
        if contains(.tuesday) { days.append("Tue") }
        if contains(.wednesday) { days.append("Wed") }
        if contains(.thursday) { days.append("Thu") }
        if contains(.friday) { days.append("Fri") }
        if contains(.saturday) { days.append("Sat") }

        return days.joined(separator: ", ")
    }
}

/// Individual scheduled event
public struct ScheduledEvent: Equatable, Identifiable {
    public var id: UInt32 { scheduleId }

    public let scheduleId: UInt32
    public let circuitId: UInt32
    public let startTime: UInt32  // Minutes from midnight (0-1439)
    public let stopTime: UInt32   // Minutes from midnight (0-1439)
    public let dayMask: DayMask
    public let flags: UInt8
    public let heatCmd: ScheduleHeatCommand
    public let heatSetpoint: UInt8

    /// Whether the schedule is enabled
    public var isEnabled: Bool {
        (flags & 0x02) != 0
    }

    /// Format start time as HH:MM string
    public var startTimeFormatted: String {
        formatMinutes(startTime)
    }

    /// Format stop time as HH:MM string
    public var stopTimeFormatted: String {
        formatMinutes(stopTime)
    }

    /// Duration in minutes
    public var durationMinutes: UInt32 {
        if stopTime >= startTime {
            return stopTime - startTime
        } else {
            // Crosses midnight
            return (1440 - startTime) + stopTime
        }
    }

    private func formatMinutes(_ minutes: UInt32) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    init(from c: aquazig_scheduled_event_t) {
        self.scheduleId = c.schedule_id
        self.circuitId = c.circuit_id
        self.startTime = c.start_time
        self.stopTime = c.stop_time
        self.dayMask = DayMask(rawValue: c.day_mask)
        self.flags = c.flags
        self.heatCmd = ScheduleHeatCommand(rawValue: c.heat_cmd) ?? .noChange
        self.heatSetpoint = c.heat_setpoint
    }
}

/// Schedule data containing multiple events
public struct Schedule: Equatable {
    public let events: [ScheduledEvent]

    init(from c: aquazig_schedule_t) {
        var events: [ScheduledEvent] = []
        let count = Int(min(c.event_count, 16))

        // Access the tuple elements through reflection
        let mirror = Mirror(reflecting: c.events)
        for (index, child) in mirror.children.enumerated() {
            if index >= count { break }
            if let event = child.value as? aquazig_scheduled_event_t {
                events.append(ScheduledEvent(from: event))
            }
        }

        self.events = events
    }
}
