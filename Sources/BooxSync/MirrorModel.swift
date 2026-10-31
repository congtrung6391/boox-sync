import SwiftUI
import AppKit
import CoreImage
import BooxSyncCore

struct PenStroke {
    var points: [CGPoint]  // 0...1 of the screen
    var endedAt: Date?
}

@MainActor
final class MirrorModel: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var status = "Starting..."
    @Published private(set) var errorMessage: String?
    /// Live pen strokes drawn on top of the (slow) screenshot. Cleared once a later screenshot shows them.
    private(set) var strokes: [PenStroke] = []
    /// Bumped at most every ~33 ms so 400 pen samples per second do not mean 400 redraws.
    @Published private(set) var overlayTick = 0
    private var flushScheduled = false
    @AppStorage("mirror.penOverlay") var penOverlay = true {
        didSet { penOverlay ? startPen() : stopPen() }
    }
    @Published var isPaused = false {
        didSet { isPaused ? stop() : start() }
    }

    /// Tone controls. Off by default. Gamma below 1 darkens, contrast above 1 adds contrast.
    @AppStorage("mirror.gamma2") var gamma = 1.0 { didSet { rerender() } }
    @AppStorage("mirror.contrast2") var contrast = 0.8 { didSet { rerender() } }
    @AppStorage("mirror.grayscale2") var grayscale = false { didSet { rerender() } }

    private let fs: BooxFS
    private var task: Task<Void, Never>?
    private var penTask: Task<Void, Never>?
    private var lastPenPublish = Date.distantPast
    private var lastPixels: Data?
    private var lastFrame: ScreenFrame?
    private var lastChange = Date()
    private let ciContext = CIContext()

    init(fs: BooxFS) {
        self.fs = fs
    }

    func start() {
        guard task == nil, !isPaused else { return }
        task = Task { await captureLoop() }
        startPen()
    }

    func stop() {
        task?.cancel()
        task = nil
        stopPen()
    }

    // MARK: Pen overlay

    private func startPen() {
        guard penTask == nil, penOverlay, task != nil else { return }
        penTask = Task { await penLoop() }
    }

    private func stopPen() {
        penTask?.cancel()
        penTask = nil
        strokes = []
        scheduleFlush()
    }

    private func penLoop() async {
        while !Task.isCancelled {
            do {
                for try await sample in fs.penSamples() {
                    handle(sample)
                }
            } catch {
                if Task.isCancelled { break }
            }
            // Stream ended (cable moved or adb restarted); try again shortly.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func handle(_ sample: PenSample) {
        guard let frame = lastFrame,
              let point = PenMapping.screenPoint(sample, frameWidth: frame.width, frameHeight: frame.height) else { return }
        let position = CGPoint(x: point.x, y: point.y)
        if sample.touching && !sample.erasing {
            if let last = strokes.last, last.endedAt == nil {
                strokes[strokes.count - 1].points.append(position)
            } else {
                strokes.append(PenStroke(points: [position], endedAt: nil))
            }
        } else if let last = strokes.last, last.endedAt == nil {
            strokes[strokes.count - 1].endedAt = Date()
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(33))
            flushScheduled = false
            overlayTick += 1
        }
    }

    /// Drop strokes that a screenshot started after they were finished (plus e-ink settle time) now shows.
    private func pruneStrokes(capturedAfter start: Date) {
        let cutoff = start.addingTimeInterval(-1.0)
        let remaining = strokes.filter { stroke in
            guard let end = stroke.endedAt else { return true }
            return end > cutoff
        }
        if remaining.count != strokes.count {
            strokes = remaining
            scheduleFlush()
        }
    }

    private func captureLoop() async {
        var idleRounds = 0
        while !Task.isCancelled {
            do {
                let captureStarted = Date()
                let frame = try await fs.captureScreen()
                errorMessage = nil
                pruneStrokes(capturedAfter: captureStarted)
                if frame.rgba != lastPixels {
                    lastPixels = frame.rgba
                    lastFrame = frame
                    lastChange = Date()
                    idleRounds = 0
                    rerender()
                } else {
                    idleRounds += 1
                }
                status = idleRounds == 0 ? "Updated just now" : "No change for \(Int(Date().timeIntervalSince(lastChange))) s"
            } catch {
                if Task.isCancelled { break }
                errorMessage = error.localizedDescription
                status = "Capture failed, retrying"
                idleRounds = 5
            }
            // Capture itself takes ~0.6 s. Wait longer the longer the screen has been still.
            let delay = min(2.5, 0.1 * pow(1.6, Double(idleRounds)))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Applies grayscale, contrast and gamma, because the raw e-ink capture looks washed out.
    private func rerender() {
        guard let frame = lastFrame else { return }
        guard let provider = CGDataProvider(data: frame.rgba as CFData) else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let cg = CGImage(
            width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: frame.width * 4, space: space, bitmapInfo: info, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }

        let neutral = !grayscale && contrast == 1.0 && gamma == 1.0
        if neutral {
            image = NSImage(cgImage: cg, size: NSSize(width: frame.width, height: frame.height))
            return
        }
        var ci = CIImage(cgImage: cg)
        let controls = CIFilter(name: "CIColorControls")!
        controls.setValue(ci, forKey: kCIInputImageKey)
        controls.setValue(grayscale ? 0.0 : 1.0, forKey: kCIInputSaturationKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        ci = controls.outputImage ?? ci
        let gammaFilter = CIFilter(name: "CIGammaAdjust")!
        gammaFilter.setValue(ci, forKey: kCIInputImageKey)
        gammaFilter.setValue(1.0 / max(gamma, 0.05), forKey: "inputPower")
        ci = gammaFilter.outputImage ?? ci

        if let out = ciContext.createCGImage(ci, from: ci.extent) {
            image = NSImage(cgImage: out, size: NSSize(width: frame.width, height: frame.height))
        }
    }

    func resetTone() {
        gamma = 1.0
        contrast = 0.8
        grayscale = false
    }

    // MARK: Snapshots

    func copyToClipboard() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func saveSnapshot() {
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Boox \(stamp).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try png.write(to: url) } catch { errorMessage = error.localizedDescription }
    }
}
