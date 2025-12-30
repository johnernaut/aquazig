import SwiftUI
import AquaZig

@main
struct AquaZigApp: App {
    @StateObject private var viewModel = PoolViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)
    }
}
