import SwiftUI
import BooxSyncCore

@main
struct BooxSyncApp: App {
    @StateObject private var monitor = DeviceMonitor()

    var body: some Scene {
        Window("BooxSync", id: "main") {
            MainView(monitor: monitor)
                .task { monitor.start() }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            Image(systemName: monitor.status.isConnected ? "ipad.landscape" : "ipad.landscape.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

extension DeviceStatus {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
