import SwiftUI
import BooxSyncCore

/// Brings the main window back. SwiftUI gives no way to open a window from outside a view, so the
/// menu bar label (always alive) stores `openWindow` here for the app delegate to use.
@MainActor
enum MainWindow {
    static var open: (() -> Void)?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Clicking the app in Finder, Launchpad or the Dock while only the menu bar icon is left.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { MainWindow.show() } }
        return true
    }
}

@main
struct BooxSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var monitor = DeviceMonitor()

    init() {
        // `BooxSync --render-variants clock out.png` shows every variant of one component, to check them.
        if let flag = CommandLine.arguments.firstIndex(of: "--render-variants"), CommandLine.arguments.count > flag + 2,
           let kind = WidgetKind(rawValue: CommandLine.arguments[flag + 1]) {
            let path = CommandLine.arguments[flag + 2]
            MainActor.assumeIsolated {
                let model = DashboardModel.sample()
                model.layout = DashboardLayout(items: [])
                for variant in 0..<kind.variantNames.count {
                    if let id = model.layout.add(kind) { model.layout.setVariant(id, variant) }
                }
                let view = DashboardView(model: model, topInset: 37).frame(width: 1872, height: 1302)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                if let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    print("rendered \(kind.rawValue) x\(kind.variantNames.count)")
                }
            }
            exit(0)
        }
        // `BooxSync --render-dashboard out.png` draws the dashboard with sample data and exits, to check the layout.
        if let flag = CommandLine.arguments.firstIndex(of: "--render-dashboard"), CommandLine.arguments.count > flag + 1 {
            let path = CommandLine.arguments[flag + 1]
            MainActor.assumeIsolated {
                let model = DashboardModel.sample()
                // Optional third argument: preset index, to check every layout.
                if CommandLine.arguments.count > flag + 2, let preset = Int(CommandLine.arguments[flag + 2]) { model.applyPreset(preset) }
                if CommandLine.arguments.contains("dark") { model.layout.dark = true }
                let view = DashboardView(model: model, topInset: 37).frame(width: 1872, height: 1302)
                if CommandLine.arguments.contains("appkit") {
                    // Render through a real AppKit hosting view, like the dashboard window does.
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: 1872, height: 1302)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        print("rendered (appkit) \(path)")
                    }
                } else {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    if let image = renderer.cgImage,
                       let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                        print("rendered \(path)")
                    } else {
                        print("render failed")
                    }
                }
            }
            exit(0)
        }
    }

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
                .onAppear { MainWindow.open = { openWindow(id: "main") } }
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
