import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

public struct EncodedTile: Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let png: Data
}

/// Converts frames to quantised gray, finds the tiles that changed since the last frame, and
/// encodes them as PNG. Only changed tiles cross the USB cable, which matters for e-ink.
public final class TileDiffer {
    public let tileSize: Int
    /// Number of gray levels kept. 16 matches what the e-ink panel can show and hides capture noise.
    public var levels: Int

    private var previous: [UInt8] = []
    private var previousWidth = 0
    private var previousHeight = 0

    public init(tileSize: Int = 128, levels: Int = 16) {
        self.tileSize = tileSize
        self.levels = max(2, min(256, levels))
    }

    /// Forget the previous frame so the next one is sent in full (new client, resize).
    public func reset() {
        previous = []
    }

    /// `bgra` points at 4-byte pixels (as ScreenCaptureKit delivers them).
    public func process(bgra: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> [EncodedTile] {
        var gray = [UInt8](repeating: 0, count: width * height)
        let scale = levels - 1
        let step = 255 / scale
        gray.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let row = bgra + y * bytesPerRow
                let outRow = y * width
                for x in 0..<width {
                    let p = row + x * 4
                    let g = (29 * Int(p[0]) + 150 * Int(p[1]) + 77 * Int(p[2])) >> 8
                    out[outRow + x] = UInt8(min(255, ((g * scale + 127) / 255) * step))
                }
            }
        }
        defer {
            previous = gray
            previousWidth = width
            previousHeight = height
        }

        let full = previous.isEmpty || previousWidth != width || previousHeight != height
        var tiles: [EncodedTile] = []
        let columns = (width + tileSize - 1) / tileSize
        let rows = (height + tileSize - 1) / tileSize
        for tileRow in 0..<rows {
            let y0 = tileRow * tileSize
            let h = min(tileSize, height - y0)
            var run: (start: Int, end: Int)?
            func flush() {
                guard let r = run else { return }
                let x0 = r.start * tileSize
                let w = min((r.end + 1) * tileSize, width) - x0
                if let png = encode(gray: gray, width: width, x: x0, y: y0, w: w, h: h) {
                    tiles.append(EncodedTile(x: x0, y: y0, width: w, height: h, png: png))
                }
                run = nil
            }
            for tileColumn in 0..<columns {
                let x0 = tileColumn * tileSize
                let w = min(tileSize, width - x0)
                let changed = full || regionDiffers(gray, previous, width: width, x: x0, y: y0, w: w, h: h)
                if changed {
                    run = (run?.start ?? tileColumn, tileColumn)
                } else {
                    flush()
                }
            }
            flush()
        }
        return tiles
    }

    private func regionDiffers(_ a: [UInt8], _ b: [UInt8], width: Int, x: Int, y: Int, w: Int, h: Int) -> Bool {
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for row in y..<(y + h) {
                    let offset = row * width + x
                    if memcmp(pa.baseAddress! + offset, pb.baseAddress! + offset, w) != 0 { return true }
                }
                return false
            }
        }
    }

    private func encode(gray: [UInt8], width: Int, x: Int, y: Int, w: Int, h: Int) -> Data? {
        var region = Data(count: w * h)
        region.withUnsafeMutableBytes { out in
            gray.withUnsafeBufferPointer { source in
                for row in 0..<h {
                    memcpy(out.baseAddress! + row * w, source.baseAddress! + (y + row) * width + x, w)
                }
            }
        }
        guard let provider = CGDataProvider(data: region as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
