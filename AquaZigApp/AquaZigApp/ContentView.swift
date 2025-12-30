import SwiftUI
import AquaZig

struct ContentView: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    LoadingView()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error) {
                        Task { await viewModel.connect() }
                    }
                } else if viewModel.isConnected {
                    DashboardView()
                } else {
                    ConnectView()
                }
            }
            .navigationTitle("AquaZig")
            .toolbar {
                if viewModel.isConnected {
                    ToolbarItem {
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        }
        .task {
            // Auto-connect on launch
            await viewModel.connect()
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Connecting to ScreenLogic...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Connection Error")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connect View

struct ConnectView: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "water.waves")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("AquaZig")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("ScreenLogic Pool Controller")
                .font(.headline)
                .foregroundColor(.secondary)

            Button("Connect") {
                Task { await viewModel.connect() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status header
                if let status = viewModel.status {
                    StatusHeaderView(status: status, controllerInfo: viewModel.controllerInfo)
                }

                // Body cards
                HStack(spacing: 20) {
                    if let pool = viewModel.poolBody {
                        BodyCard(
                            title: "Pool",
                            icon: "figure.pool.swim",
                            bodyStatus: pool,
                            bodyType: .pool
                        )
                    }

                    if let spa = viewModel.spaBody {
                        BodyCard(
                            title: "Spa",
                            icon: "bathtub",
                            bodyStatus: spa,
                            bodyType: .spa
                        )
                    }
                }

                // Circuit controls (Spa/Pool on/off)
                CircuitControlCard()

                // Pump status
                if let pump = viewModel.pumpStatus {
                    PumpCard(pump: pump)
                }

                // Chemistry
                if viewModel.hasChemistry {
                    ChemistryCard()
                }

                // Schedules
                if let schedule = viewModel.schedule, !schedule.events.isEmpty {
                    ScheduleCard(schedule: schedule)
                }
            }
            .padding()
        }
    }
}

// MARK: - Status Header

struct StatusHeaderView: View {
    let status: PoolStatus
    let controllerInfo: ControllerConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(status.airTemp)°F", systemImage: "thermometer.medium")
                    .font(.headline)

                Spacer()

                if status.freezeMode {
                    Label("Freeze Protection", systemImage: "snowflake")
                        .foregroundColor(.blue)
                }

                if status.ok {
                    Label("System OK", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("System Alert", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                }
            }

            if let info = controllerInfo {
                HStack {
                    Label(info.hardwareTypeDescription, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("ID: \(info.controllerId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Body Card

struct BodyCard: View {
    let title: String
    let icon: String
    let bodyStatus: BodyStatus
    let bodyType: BodyType

    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                if bodyStatus.heaterRunning {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Temperature
            HStack {
                Text("Current")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(bodyStatus.currentTemp)°F")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("Setpoint")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(bodyStatus.heatSetpoint)°F")
            }

            // Heat mode
            HStack {
                Text("Heat Mode")
                    .foregroundColor(.secondary)
                Spacer()
                Menu(bodyStatus.heatMode.description) {
                    Button("Off") {
                        Task { await viewModel.setHeatMode(body: bodyType, mode: .off) }
                    }
                    Button("Heater") {
                        Task { await viewModel.setHeatMode(body: bodyType, mode: .heater) }
                    }
                    Button("Solar") {
                        Task { await viewModel.setHeatMode(body: bodyType, mode: .solar) }
                    }
                    Button("Solar Preferred") {
                        Task { await viewModel.setHeatMode(body: bodyType, mode: .solarPreferred) }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Pump Card

struct PumpCard: View {
    let pump: PumpStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pump", systemImage: "arrow.3.trianglepath")
                    .font(.headline)
                Spacer()
                Text(pump.pumpType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 30) {
                VStack {
                    Text("\(pump.rpm)")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(pump.gpm)")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("GPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(pump.watts)")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Watts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if pump.isRunning {
                    Label("Running", systemImage: "play.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Stopped", systemImage: "stop.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Chemistry Card

struct ChemistryCard: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chemistry", systemImage: "flask")
                .font(.headline)

            Divider()

            HStack(spacing: 30) {
                if let ph = viewModel.status?.ph {
                    VStack {
                        Text(String(format: "%.2f", ph))
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("pH")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let orp = viewModel.status?.orp {
                    VStack {
                        Text("\(orp)")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("ORP mV")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let salt = viewModel.status?.saltPPM {
                    VStack {
                        Text("\(salt)")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Salt PPM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Circuit Control Card

struct CircuitControlCard: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Circuit Controls", systemImage: "power")
                .font(.headline)

            Divider()

            HStack(spacing: 30) {
                // Spa toggle
                VStack(spacing: 8) {
                    Button {
                        Task { await viewModel.toggleSpa() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: viewModel.isSpaOn ? "bathtub.fill" : "bathtub")
                                .font(.system(size: 32))
                                .foregroundColor(viewModel.isSpaOn ? .orange : .secondary)
                            Text("Spa")
                                .font(.caption)
                                .foregroundColor(viewModel.isSpaOn ? .primary : .secondary)
                        }
                        .frame(width: 80, height: 70)
                        .background(viewModel.isSpaOn ? Color.orange.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Text(viewModel.isSpaOn ? "ON" : "OFF")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isSpaOn ? .orange : .secondary)
                }

                // Pool toggle
                VStack(spacing: 8) {
                    Button {
                        Task { await viewModel.togglePool() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: viewModel.isPoolOn ? "figure.pool.swim" : "figure.pool.swim")
                                .font(.system(size: 32))
                                .foregroundColor(viewModel.isPoolOn ? .blue : .secondary)
                            Text("Pool")
                                .font(.caption)
                                .foregroundColor(viewModel.isPoolOn ? .primary : .secondary)
                        }
                        .frame(width: 80, height: 70)
                        .background(viewModel.isPoolOn ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Text(viewModel.isPoolOn ? "ON" : "OFF")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isPoolOn ? .blue : .secondary)
                }

                // High Speed toggle
                VStack(spacing: 8) {
                    Button {
                        Task { await viewModel.toggleHighSpeed() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: viewModel.isHighSpeedOn ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.50percent")
                                .font(.system(size: 32))
                                .foregroundColor(viewModel.isHighSpeedOn ? .green : .secondary)
                            Text("High Speed")
                                .font(.caption)
                                .foregroundColor(viewModel.isHighSpeedOn ? .primary : .secondary)
                        }
                        .frame(width: 80, height: 70)
                        .background(viewModel.isHighSpeedOn ? Color.green.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Text(viewModel.isHighSpeedOn ? "ON" : "OFF")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isHighSpeedOn ? .green : .secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Schedule Card

struct ScheduleCard: View {
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedules", systemImage: "calendar.badge.clock")
                .font(.headline)

            Divider()

            ForEach(schedule.events) { event in
                ScheduleEventRow(event: event)
                if event.id != schedule.events.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct ScheduleEventRow: View {
    @EnvironmentObject var viewModel: PoolViewModel
    let event: ScheduledEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(viewModel.circuitName(forId: event.circuitId))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if event.isEnabled {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Disabled", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("\(event.startTimeFormatted) - \(event.stopTimeFormatted)")
                    .font(.subheadline)

                Spacer()

                Text(event.dayMask.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if event.heatCmd != .noChange {
                HStack {
                    Image(systemName: "flame")
                        .foregroundColor(.orange)
                    Text("\(event.heatCmd.description)")
                        .font(.caption)
                    if event.heatSetpoint > 0 {
                        Text("@ \(event.heatSetpoint)°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(PoolViewModel())
}
