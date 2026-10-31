import Foundation

public enum Gzip {
    /// Decompresses a single-member gzip stream. Foundation's .zlib algorithm is raw DEFLATE,
    /// so the gzip header and the 8-byte trailer are stripped first.
    public static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data.prefix(10))
        guard bytes.count == 10, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        func skipZeroTerminated() -> Bool {
            while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }
            offset += 1
            return offset <= data.count
        }
        if flags & 0x04 != 0 {  // FEXTRA
            guard data.count > offset + 2 else { return nil }
            let length = Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8
            offset += 2 + length
        }
        if flags & 0x08 != 0, !skipZeroTerminated() { return nil }  // FNAME
        if flags & 0x10 != 0, !skipZeroTerminated() { return nil }  // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC
        guard data.count > offset + 8 else { return nil }
        let body = data.subdata(in: (data.startIndex + offset)..<(data.endIndex - 8))
        return try? (body as NSData).decompressed(using: .zlib) as Data
    }
}
