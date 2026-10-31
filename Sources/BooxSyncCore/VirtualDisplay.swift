import Foundation
import CoreGraphics
import CVirtualDisplay

public enum VirtualDisplayError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "macOS refused to create the virtual display (private API unavailable or size rejected)"
    }
}

/// A second display that exists only while this object is alive.
public final class VirtualDisplay {
    public let displayID: CGDirectDisplayID
    public let width: Int
    public let height: Int
    private var handle: UnsafeMutableRawPointer?

    public init(width: Int, height: Int) throws {
        var id: CGDirectDisplayID = 0
        guard let handle = BooxVirtualDisplayCreate(UInt32(width), UInt32(height), &id) else {
            throw VirtualDisplayError.unavailable
        }
        self.handle = handle
        self.displayID = id
        self.width = width
        self.height = height
    }

    /// macOS starts the display in a smaller mode (1024x712); switch to the Boox-sized one so one
    /// Mac pixel is one Boox pixel, and park it to the right of the main display.
    public func activateNativeMode() async -> Bool {
        for _ in 0..<15 {
            let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
            if let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
               let mode = modes.first(where: { $0.width == width && $0.height == height && $0.pixelWidth == width }) {
                var config: CGDisplayConfigRef?
                guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
                CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
                let main = CGDisplayBounds(CGMainDisplayID())
                CGConfigureDisplayOrigin(config, displayID, Int32(main.maxX), 0)
                return CGCompleteDisplayConfiguration(config, .forSession) == .success
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    public func destroy() {
        if let handle { BooxVirtualDisplayDestroy(handle) }
        handle = nil
    }

    deinit { destroy() }
}
