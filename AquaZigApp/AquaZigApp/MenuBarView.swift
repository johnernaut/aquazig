import SwiftUI
import AquaZig

struct MenuBarView: View {
    @EnvironmentObject var viewModel: PoolViewModel
    let openWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isConnected {
                connectedView
            } else if viewModel.isLoading {
                loadingView
            } else {
                disconnectedView
            }
        }
        .frame(width: 280)
    }

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(spacing: 0) {
            // Header with temps
            HStack(spacing: 16) {
                if let pool = viewModel.poolBody {
                    tempBadge(label: "Pool", temp: pool.currentTemp, color: .blue)
                }
                if let spa = viewModel.spaBody {
                    tempBadge(label: "Spa", temp: spa.currentTemp, color: .orange)
                }
                Spacer()
                if let status = viewModel.status {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .font(.caption)
                        Text("\(status.airTemp)°")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Quick controls
            HStack(spacing: 12) {
                quickToggle(
                    icon: "bathtub.fill",
                    label: "Spa",
                    isOn: viewModel.isSpaOn,
                    color: .orange
                ) {
                    Task { await viewModel.toggleSpa() }
                }

                quickToggle(
                    icon: "figure.pool.swim",
                    label: "Pool",
                    isOn: viewModel.isPoolOn,
                    color: .blue
                ) {
                    Task { await viewModel.togglePool() }
                }

                quickToggle(
                    icon: "gauge.with.dots.needle.100percent",
                    label: "High",
                    isOn: viewModel.isHighSpeedOn,
                    color: .green
                ) {
                    Task { await viewModel.toggleHighSpeed() }
                }
            }
            .padding(12)

            Divider()

            // Pump status row
            if let pump = viewModel.pumpStatus {
                HStack {
                    Image(systemName: pump.isRunning ? "arrow.3.trianglepath" : "stop.circle")
                        .foregroundStyle(pump.isRunning ? .green : .secondary)
                    Text(pump.isRunning ? "Pump Running" : "Pump Idle")
                        .font(.subheadline)
                    Spacer()
                    if pump.isRunning {
                        Text("\(pump.watts)W")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
            }

            // Actions
            VStack(spacing: 0) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowButtonStyle())

                Button {
                    openWindow()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Dashboard", systemImage: "macwindow")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowButtonStyle())

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit AquaZig", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowButtonStyle())
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Disconnected View

    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Not Connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Connect") {
                Task { await viewModel.connect() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Divider()
                .padding(.top, 8)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit AquaZig", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuRowButtonStyle())
        }
        .padding(.vertical, 16)
    }

    // MARK: - Components

    private func tempBadge(label: String, temp: Int32, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(temp)°")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(color)
    }

    private func quickToggle(icon: String, label: String, isOn: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 70, height: 54)
            .foregroundStyle(isOn ? color : .secondary)
            .background(isOn ? color.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isOn ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu Row Button Style

struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
    }
}
