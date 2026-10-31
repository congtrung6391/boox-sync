import SwiftUI
import BooxSyncCore

struct DisplayView: View {
    @ObservedObject var model: DisplayModel
    var openDashboard: () -> Void = {}

    var body: some View {
        if model.phase == .running {
            runningView
        } else {
            idleView
        }
    }

    // MARK: Idle, starting, failed

    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: model.isActive ? "display.2" : "display")
                .font(.system(size: 54))
                .foregroundStyle(model.isActive ? Color.accentColor : Color.secondary)

            Text("Use the Boox as a second display").font(.title2.weight(.semibold))
            Text(model.status).font(.callout).foregroundStyle(.secondary)

            if case .failed(let message) = model.phase {
                VStack(spacing: 8) {
                    Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Open Screen Recording settings") { model.openScreenRecordingSettings() }
                }
                .frame(maxWidth: 520)
            }

            Button { model.start() } label: {
                Text("Start second display").frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.phase == .starting)

            Text("The Boox opens its browser in fullscreen over USB. Then choose which windows to show on it, or leave the dashboard there. macOS asks for Screen Recording and Accessibility permission.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Running

    private var runningView: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            if !model.accessibilityTrusted {
                accessibilityBanner
                Divider()
            }
            dashboardRow
            Divider()
            windowList
        }
        .alert("Could not move the window", isPresented: Binding(get: { model.windowError != nil }, set: { if !$0 { model.windowError = nil } })) {
            Button("OK") { model.windowError = nil }
        } message: {
            Text(model.windowError ?? "")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Boox display is on").font(.headline)
                Text("\(model.stats.width) x \(model.stats.height) px  ·  \(model.stats.tilesPerSecond) tiles/s  ·  \(model.stats.kilobytesPerSecond) KB/s")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Show pointer", isOn: $model.showsCursor)
                .help("Draw the Mac mouse pointer on the Boox display")
            Button("Display settings...") { model.openDisplaySettings() }
            Button("Stop") { model.stop() }.tint(.red)
        }
        .padding(12)
    }

    private var dashboardRow: some View {
        HStack(spacing: 12) {
            Toggle("Dashboard on the Boox", isOn: $model.dashboardOn).toggleStyle(.switch).fixedSize()
            Text("Shows behind any windows you send.").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Edit dashboard...", action: openDashboard)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var windowList: some View {
        List {
            Section {
                if model.windowsOnBoox.isEmpty {
                    Text("No windows on top. The Boox shows the dashboard. Send a window from the list below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.windowsOnBoox.enumerated()), id: \.element.id) { index, window in
                    WindowRow(
                        window: window, actionTitle: "Pull back", symbol: "arrow.uturn.backward",
                        badge: model.windowsOnBoox.count > 1 && index == 0 ? "On top" : nil,
                        secondaryTitle: model.windowsOnBoox.count > 1 && index > 0 ? "Bring to top" : nil,
                        secondaryAction: { model.bringToTop(window) }
                    ) { model.pullBack(window) }
                }
            } header: {
                HStack {
                    Text("On the Boox (\(model.windowsOnBoox.count))")
                    Spacer()
                    if model.windowsOnBoox.count > 1 { Button("Pull back all") { model.pullBackAll() }.buttonStyle(.link) }
                }
            }
            Section("On this Mac (\(model.windowsOnMac.count))") {
                ForEach(model.windowsOnMac) { window in
                    WindowRow(window: window, actionTitle: "Send to Boox", symbol: "arrow.right.to.line") { model.sendToBoox(window) }
                }
            }
        }
        .listStyle(.inset)
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Allow Accessibility so BooxSync can move windows to the Boox.").font(.callout)
            Spacer()
            Button("Allow...") { model.requestAccessibility() }
            Button("Open settings") { model.openAccessibilitySettings() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let actionTitle: String
    let symbol: String
    var badge: String? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: () -> Void = {}
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.appName).font(.body.weight(.medium))
                if !window.title.isEmpty {
                    Text(window.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            Spacer()
            if let secondaryTitle {
                Button(action: secondaryAction) { Label(secondaryTitle, systemImage: "square.3.layers.3d.top.filled") }
            }
            Button(action: action) { Label(actionTitle, systemImage: symbol) }
        }
        .padding(.vertical, 2)
    }

    private var icon: NSImage {
        (Demo.isOn ? Demo.icon(forApp: window.appName) : nil)
            ?? NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
    }
}
