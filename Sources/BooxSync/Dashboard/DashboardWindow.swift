import SwiftUI
import AppKit
import BooxSyncCore

/// A borderless window that sits on the Boox display just above the desktop, like a wallpaper.
/// Windows sent to the Boox appear on top of it, and once they are pulled back the dashboard shows again.
@MainActor
final class DashboardWindow {
    private var window: NSWindow?
    private var observer: NSObjectProtocol?
    private var displayID: CGDirectDisplayID?

    func show(model: DashboardModel, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        guard let screen = Self.screen(for: displayID) else { return }
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        if window == nil {
            let created = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            created.isOpaque = true
            created.backgroundColor = .white
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            created.isReleasedWhenClosed = false
            created.appearance = NSAppearance(named: .aqua)
            window = created
        }
        window?.contentView = NSHostingView(rootView: DashboardView(model: model, topInset: topInset))
        window?.setFrame(screen.frame, display: true)
        window?.orderFront(nil)

        observer = observer ?? NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func hide() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        window?.orderOut(nil)
        window = nil
        displayID = nil
    }

    private func reposition() {
        guard let displayID, let screen = Self.screen(for: displayID) else { return }
        window?.setFrame(screen.frame, display: true)
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
