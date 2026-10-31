import Foundation

/// One raw screenshot from `adb exec-out screencap` (RGBA8888).
public struct ScreenFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data

    public init(width: Int, height: Int, rgba: Data) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// Boox firmware prints "capture from screenshot!\n" before the data, and Android adds a
    /// small header (width, height, format, ...). The pixels are always the last width*height*4 bytes.
    public static func parse(_ data: Data) -> ScreenFrame? {
        var start = data.startIndex
        let banner = Data("capture from screenshot!\n".utf8)
        if data.starts(with: banner) { start += banner.count }
        guard data.count - (start - data.startIndex) >= 12 else { return nil }

        func word(_ offset: Int) -> Int {
            let i = start + offset
            return Int(data[i]) | Int(data[i + 1]) << 8 | Int(data[i + 2]) << 16 | Int(data[i + 3]) << 24
        }
        let width = word(0), height = word(4), format = word(8)
        guard format == 1, width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let pixelBytes = width * height * 4
        guard data.count >= pixelBytes + 12 else { return nil }
        return ScreenFrame(width: width, height: height, rgba: data.suffix(pixelBytes))
    }
}
