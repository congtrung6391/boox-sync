import Foundation

/// One pen position from the Boox Wacom digitizer, normalised to 0...1 of the digitizer's own axes.
public struct PenSample: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var touching: Bool
    public var erasing: Bool

    public init(x: Double, y: Double, touching: Bool, erasing: Bool) {
        self.x = x
        self.y = y
        self.touching = touching
        self.erasing = erasing
    }
}

public struct PenDevice: Equatable, Sendable {
    public let path: String
    public let maxX: Double
    public let maxY: Double

    public init(path: String, maxX: Double, maxY: Double) {
        self.path = path
        self.maxX = maxX
        self.maxY = maxY
    }

    /// Finds the digitizer in the output of `getevent -p` (the device whose name mentions Wacom or Digitizer).
    public static func parse(_ output: String) -> PenDevice? {
        let blocks = output.components(separatedBy: "add device ").dropFirst()
        for block in blocks {
            guard block.localizedCaseInsensitiveContains("wacom") || block.localizedCaseInsensitiveContains("digitizer") else { continue }
            // First line is "1: /dev/input/event8".
            guard let firstLine = block.split(whereSeparator: \.isNewline).first,
                  let separator = firstLine.range(of: ": ") else { continue }
            let path = firstLine[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            var maxima: [String: Double] = [:]
            for rawLine in block.split(whereSeparator: \.isNewline) {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("ABS (0003):") { line = String(line.dropFirst("ABS (0003):".count)).trimmingCharacters(in: .whitespaces) }
                guard let code = line.split(separator: " ").first, code.count == 4,
                      let range = line.range(of: "max ") else { continue }
                let digits = line[range.upperBound...].prefix { $0.isNumber }
                if let value = Double(digits) { maxima[String(code)] = value }
            }
            if let maxX = maxima["0000"], let maxY = maxima["0001"] {
                return PenDevice(path: path, maxX: maxX, maxY: maxY)
            }
        }
        return nil
    }
}

/// Turns `getevent -l` lines into pen samples. One sample per SYN_REPORT.
public struct PenEventParser {
    private let device: PenDevice
    private var x: Int?
    private var y: Int?
    private var touching = false
    private var erasing = false
    private var dirty = false

    public init(device: PenDevice) {
        self.device = device
    }

    public mutating func feed(_ line: String) -> PenSample? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard tokens.count >= 3 else { return nil }
        let type = tokens[0], code = tokens[1], value = tokens[2]
        switch (type, code) {
        case ("EV_ABS", "ABS_X"):
            x = Int(value, radix: 16); dirty = true
        case ("EV_ABS", "ABS_Y"):
            y = Int(value, radix: 16); dirty = true
        case ("EV_KEY", "BTN_TOUCH"):
            touching = value == "DOWN"; dirty = true
        case ("EV_KEY", "BTN_TOOL_RUBBER"):
            erasing = value == "DOWN"; dirty = true
        case ("EV_SYN", "SYN_REPORT"):
            defer { dirty = false }
            guard dirty, let x, let y else { return nil }
            return PenSample(x: Double(x) / device.maxX, y: Double(y) / device.maxY, touching: touching, erasing: erasing)
        default:
            break
        }
        return nil
    }
}

public enum PenMapping {
    /// Maps a digitizer position to 0...1 screen coordinates. Calibrated on the NoteX in landscape
    /// (screen 1872x1404), where the digitizer is rotated 180 degrees. Portrait is not calibrated yet.
    public static func screenPoint(_ sample: PenSample, frameWidth: Int, frameHeight: Int) -> (x: Double, y: Double)? {
        guard frameWidth > frameHeight else { return nil }
        return (1 - sample.x, 1 - sample.y)
    }
}
