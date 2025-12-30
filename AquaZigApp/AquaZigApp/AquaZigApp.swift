import SwiftUI
import AquaZig

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and make menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Close any windows that SwiftUI opened on launch
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if window.canBecomeMain {
                    window.close()
                }
            }
        }
    }
}

@main
struct AquaZigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = PoolViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window (hidden by default, opened via menu bar)
        Window("AquaZig", id: "main") {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar icon and dropdown
        MenuBarExtra {
            MenuBarView(openWindow: { openWindow(id: "main") })
                .environmentObject(viewModel)
        } label: {
            Image(systemName: "drop.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
