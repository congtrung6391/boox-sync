import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

public enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied
    case displayNotFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is needed. Allow BooxSync in System Settings > Privacy & Security > Screen & System Audio Recording, then start again."
        case .displayNotFound:
            "The virtual display did not show up for capture"
        case .captureFailed(let detail):
            "Screen capture failed: \(detail)"
        }
    }
}

/// Captures one display with ScreenCaptureKit and hands raw BGRA frames to a handler.
public final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public typealias FrameHandler = @Sendable (_ bgra: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ bytesPerRow: Int) -> Void

    private var stream: SCStream?
    private var configuration: SCStreamConfiguration?
    private var handler: FrameHandler?
    private let queue = DispatchQueue(label: "booxsync.capture")

    /// Shows the system prompt the first time and reports whether capture is allowed.
    public static func requestPermission() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    public func start(displayID: CGDirectDisplayID, width: Int, height: Int, framesPerSecond: Double, showsCursor: Bool = true, handler: @escaping FrameHandler) async throws {
        var found: SCDisplay?
        for attempt in 0..<12 {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                let ns = error as NSError
                // -3801 is "user declined TCC". Anything else is a different problem worth showing.
                if ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.userDeclined.rawValue { throw ScreenCaptureError.permissionDenied }
                throw ScreenCaptureError.captureFailed("\(ns.domain) \(ns.code): \(ns.localizedDescription)")
            }
            found = content.displays.first { $0.displayID == displayID }
            if found != nil { break }
            if attempt < 11 { try await Task.sleep(for: .milliseconds(300)) }
        }
        guard let display = found else { throw ScreenCaptureError.displayNotFound }

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, framesPerSecond)))
        configuration.queueDepth = 3
        configuration.showsCursor = showsCursor

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.handler = handler
        self.stream = stream
        self.configuration = configuration
        try await stream.startCapture()
    }

    /// Applies to the running stream, no restart needed.
    public func setShowsCursor(_ show: Bool) async {
        guard let stream, let configuration else { return }
        configuration.showsCursor = show
        try? await stream.updateConfiguration(configuration)
    }

    public func stop() async {
        let current = stream
        stream = nil
        configuration = nil
        handler = nil
        try? await current?.stopCapture()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        handler?(base.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), CVPixelBufferGetBytesPerRow(pixels))
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {}
}
