import AppKit
import ApplicationServices

public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String
    /// Global coordinates, origin at the top left of the main display.
    public let bounds: CGRect

    public init(id: CGWindowID, pid: pid_t, appName: String, title: String, bounds: CGRect) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.bounds = bounds
    }
}

public enum WindowMoveError: Error, LocalizedError {
    case notTrusted
    case windowNotFound
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notTrusted: "Accessibility permission is needed to move windows. Allow BooxSync in System Settings > Privacy & Security > Accessibility."
        case .windowNotFound: "That window is gone or cannot be moved (full-screen and some system windows cannot)."
        case .failed(let detail): "Could not move the window: \(detail)"
        }
    }
}

// Private but long-stable: maps an Accessibility window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

public enum WindowMover {
    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "SystemUIServer", "Control Center", "Notification Center", "Spotlight", "WindowManager",
    ]

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Normal application windows that are on screen, front to back.
    public static func listWindows(excludingPID: pid_t = getpid()) -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var result: [WindowInfo] = []
        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != excludingPID,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let owner = entry[kCGWindowOwnerName as String] as? String, !ignoredOwners.contains(owner),
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 120, bounds.height >= 80,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
            result.append(WindowInfo(id: id, pid: pid, appName: owner, title: entry[kCGWindowName as String] as? String ?? "", bounds: bounds))
        }
        return result
    }

    /// Moves and resizes a window. Position, size, position again: macOS clamps the size to the screen the window is
    /// on at that moment, so a window moving to a different-sized display needs a second pass.
    public static func move(_ window: WindowInfo, to frame: CGRect) throws {
        guard isTrusted(prompt: false) else { throw WindowMoveError.notTrusted }
        guard let element = axElement(for: window) else { throw WindowMoveError.windowNotFound }

        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &fullScreen) == .success, (fullScreen as? Bool) == true {
            AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, kCFBooleanFalse)
            usleep(900_000)
        }

        func setPosition() -> AXError {
            var point = frame.origin
            guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
            return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
        func setSize() -> AXError {
            var size = frame.size
            guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
            return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        let first = setPosition()
        let sized = setSize()
        let second = setPosition()
        _ = setSize()
        if first != .success && second != .success { throw WindowMoveError.failed("Accessibility error \(first.rawValue)") }
        if sized != .success && sized != .cannotComplete { /* some windows have a fixed size; position still counts */ }
    }

    /// Brings one window above the others. The app has to be activated for the raise to win over other apps'
    /// windows on the same display, so callers should re-activate their own app afterwards.
    public static func raise(_ window: WindowInfo) throws {
        guard isTrusted(prompt: false) else { throw WindowMoveError.notTrusted }
        guard let element = axElement(for: window) else { throw WindowMoveError.windowNotFound }
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [.activateIgnoringOtherApps])
        usleep(120_000)
        let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if result != .success { throw WindowMoveError.failed("Accessibility error \(result.rawValue)") }
    }

    private static func axElement(for window: WindowInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return nil }
        for element in elements {
            var id: CGWindowID = 0
            if axWindowID(element, &id) == .success, id == window.id { return element }
        }
        // Fallback: match by title when the private lookup is unavailable.
        guard !window.title.isEmpty else { return nil }
        return elements.first { element in
            var title: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success && (title as? String) == window.title
        }
    }

    // MARK: Display geometry

    /// The area of a display that windows can use, in the same top-left global coordinates as `WindowInfo.bounds`
    /// (below the menu bar).
    public static func usableFrame(of displayID: CGDirectDisplayID) -> CGRect {
        let bounds = CGDisplayBounds(displayID)
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        let menuBar = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
        return CGRect(x: bounds.minX, y: bounds.minY + menuBar, width: bounds.width, height: bounds.height - menuBar)
    }

    /// A reasonable place on the main display for a window that has no remembered position.
    public static func fallbackFrame(for window: WindowInfo) -> CGRect {
        let main = CGDisplayBounds(CGMainDisplayID())
        let width = min(window.bounds.width, main.width * 0.8)
        let height = min(window.bounds.height, main.height * 0.8)
        return CGRect(x: main.minX + (main.width - width) / 2, y: main.minY + (main.height - height) / 2 + 20, width: width, height: height)
    }
}
