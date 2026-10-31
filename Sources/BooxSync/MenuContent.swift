import SwiftUI
import BooxSyncCore

struct MenuContent: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusHeader(status: monitor.status)
            if let steps = OnboardingSteps.steps(for: monitor.status) {
                OnboardingView(title: steps.title, steps: steps.items)
            }
            Divider()
            HStack {
                Button("Open BooxSync") { MainWindow.show() }
                Button("Refresh") { Task { await monitor.refresh() } }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct StatusHeader: View {
    let status: DeviceStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .unauthorized, .offline, .booxWithoutDebugging: .orange
        case .noDevice, .adbMissing: .red
        }
    }

    private var title: String {
        switch status {
        case .connected(let device): "Boox \(device.model ?? "") connected"
        case .unauthorized: "Waiting for permission on the Boox"
        case .offline: "Boox is offline"
        case .booxWithoutDebugging: "Boox found, USB debugging is off"
        case .noDevice: "No Boox connected"
        case .adbMissing: "adb not found"
        }
    }

    private var detail: String? {
        switch status {
        case .connected(let device): "Serial \(device.serial)"
        case .unauthorized(let serial), .offline(let serial): "Serial \(serial)"
        default: nil
        }
    }
}
