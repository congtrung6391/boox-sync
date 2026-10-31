import SwiftUI
import BooxSyncCore

/// Keeps one file browser and one second-display session per device, so folder, transfers and a
/// running display survive switching tabs.
@MainActor
private final class ModelHolder {
    private var serial: String?
    private var browser: FileBrowserModel?
    private var display: DisplayModel?

    private func refresh(for fs: BooxFS) {
        guard serial != fs.serial else { return }
        display?.stop()
        browser = FileBrowserModel(fs: fs)
        display = DisplayModel(fs: fs)
        serial = fs.serial
    }

    func browser(for fs: BooxFS) -> FileBrowserModel { refresh(for: fs); return browser! }
    func display(for fs: BooxFS) -> DisplayModel { refresh(for: fs); return display! }
}

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case files = "Files"
        case mirror = "Mirror"
        case display = "Display"
        var id: String { rawValue }
    }

    @ObservedObject var monitor: DeviceMonitor
    @State private var tab: Tab = .files
    @State private var holder = ModelHolder()

    var body: some View {
        Group {
            if case .connected(let device) = monitor.status, let adb = monitor.adbURL {
                let fs = BooxFS(adb: adb, serial: device.serial)
                Group {
                    switch tab {
                    case .files: FileBrowserView(model: holder.browser(for: fs))
                    case .mirror: MirrorView(fs: fs)
                    case .display: DisplayView(model: holder.display(for: fs))
                    }
                }
                .id("\(device.serial)-\(tab.rawValue)")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("View", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            } else {
                MenuContent(monitor: monitor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 860, minHeight: 520)
    }
}
