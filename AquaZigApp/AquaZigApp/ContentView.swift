import SwiftUI
import AquaZig

struct ContentView: View {
    @EnvironmentObject var viewModel: PoolViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.isConnected {
                LoadingView()
            } else if let error = viewModel.errorMessage, !viewModel.isConnected {
                ErrorView(message: error) {
                    Task { await viewModel.connect() }
                }
            } else if viewModel.isConnected {
                DashboardView()
            } else {
                ConnectView()
            }
        }
        .frame(width: 520, height: 420)
        .background(backgroundGradient)
        .task {
            await viewModel.connectIfNeeded()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.1), Color(white: 0.15)]
                : [Color(white: 0.96), Color(white: 0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Discovering ScreenLogic...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Connection Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Connect View

struct ConnectView: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)

            Text("AquaZig")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Pool Controller")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Connect") {
                Task { await viewModel.connect() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Temperature cards
            HStack(spacing: 12) {
                if let pool = viewModel.poolBody {
                    TemperatureCard(
                        title: "Pool",
                        icon: "figure.pool.swim",
                        status: pool,
                        bodyType: .pool,
                        accentColor: .blue
                    )
                }

                if let spa = viewModel.spaBody {
                    TemperatureCard(
                        title: "Spa",
                        icon: "bathtub.fill",
                        status: spa,
                        bodyType: .spa,
                        accentColor: .orange
                    )
                }
            }
            .padding(.horizontal, 20)

            // Quick controls
            ControlsRow()
                .padding(.horizontal, 20)

            // Pump status
            if let pump = viewModel.pumpStatus {
                PumpRow(pump: pump)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            // Footer
            footerView
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let info = viewModel.controllerInfo {
                    Text(info.hardwareTypeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let status = viewModel.status {
                HStack(spacing: 12) {
                    Label("\(status.airTemp)°", systemImage: "thermometer.medium")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if status.freezeMode {
                        Image(systemName: "snowflake")
                            .foregroundStyle(.cyan)
                    }

                    Circle()
                        .fill(status.ok ? .green : .orange)
                        .frame(width: 8, height: 8)
                }
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isLoading)
        }
    }

    private var footerView: some View {
        HStack {
            if viewModel.hasChemistry, let status = viewModel.status {
                HStack(spacing: 16) {
                    if let ph = status.ph {
                        Label(String(format: "%.1f pH", ph), systemImage: "flask")
                    }
                    if let salt = status.saltPPM {
                        Label("\(salt) ppm", systemImage: "drop")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }
}

// MARK: - Temperature Card

struct TemperatureCard: View {
    let title: String
    let icon: String
    let status: BodyStatus
    let bodyType: BodyType
    let accentColor: Color

    @EnvironmentObject var viewModel: PoolViewModel
    @State private var showHeatMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if status.heaterRunning {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // Temperature display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(status.currentTemp)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("°F")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(accentColor)

            // Setpoint and heat mode
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setpoint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(status.heatSetpoint)°")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                Menu {
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
                } label: {
                    HStack(spacing: 4) {
                        Text(status.heatMode.description)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Controls Row

struct ControlsRow: View {
    @EnvironmentObject var viewModel: PoolViewModel

    var body: some View {
        HStack(spacing: 12) {
            ControlButton(
                icon: "bathtub.fill",
                label: "Spa",
                isOn: viewModel.isSpaOn,
                color: .orange
            ) {
                Task { await viewModel.toggleSpa() }
            }

            ControlButton(
                icon: "figure.pool.swim",
                label: "Pool",
                isOn: viewModel.isPoolOn,
                color: .blue
            ) {
                Task { await viewModel.togglePool() }
            }

            ControlButton(
                icon: "gauge.with.dots.needle.100percent",
                label: "High Speed",
                isOn: viewModel.isHighSpeedOn,
                color: .green
            ) {
                Task { await viewModel.toggleHighSpeed() }
            }
        }
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    let isOn: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(isOn ? color : .secondary)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isOn ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pump Row

struct PumpRow: View {
    let pump: PumpStatus

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: pump.isRunning ? "arrow.3.trianglepath" : "stop.circle")
                    .foregroundStyle(pump.isRunning ? .green : .secondary)
                Text(pump.pumpType.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            if pump.isRunning {
                HStack(spacing: 16) {
                    statItem(value: "\(pump.rpm)", label: "RPM")
                    statItem(value: "\(pump.gpm)", label: "GPM")
                    statItem(value: "\(pump.watts)", label: "W")
                }
            } else {
                Text("Idle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PoolViewModel())
}
