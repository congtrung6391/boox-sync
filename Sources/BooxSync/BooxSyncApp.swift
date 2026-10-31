import SwiftUI
import BooxSyncCore

@main
struct BooxSyncApp: App {
    @StateObject private var monitor = DeviceMonitor()

    init() {
        if Demo.isOn { NSApplication.shared.appearance = NSAppearance(named: .aqua) }   // light screenshots
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
                .task {
                    if Demo.isOn {
                        monitor.useDemoDevice()
                        // Screenshots of an inactive window show grayed-out controls.
                        try? await Task.sleep(for: .milliseconds(700))
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                            window.setContentSize(NSSize(width: 1180, height: 780))
                            window.center()
                            window.makeKeyAndOrderFront(nil)
                        }
                    } else {
                        monitor.start()
                    }
                }
        }
        .defaultSize(width: 1180, height: 800)
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
