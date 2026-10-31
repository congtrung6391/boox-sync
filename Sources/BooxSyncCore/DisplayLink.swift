import Foundation

public enum DisplayLinkError: Error, LocalizedError {
    case connectFailed(String)
    case badHello
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .connectFailed(let reason): "Could not reach the BooxDisplay app: \(reason)"
        case .badHello: "The Boox app sent an unexpected greeting"
        case .writeFailed: "Lost the connection to the Boox"
        }
    }
}

/// Wire format for the second display (see android/display MainActivity.java).
public enum DisplayProtocol {
    public static let port: UInt16 = 7788

    /// 'T' x y w h length payload, all big endian; payload is raw DEFLATE of w*h gray bytes.
    public static func tileMessage(x: Int, y: Int, width: Int, height: Int, gray: Data) -> Data? {
        precondition(gray.count == width * height)
        guard let payload = try? (gray as NSData).compressed(using: .zlib) as Data else { return nil }
        var message = Data([0x54])
        for value in [x, y, width, height] { message.append(contentsOf: [UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]) }
        let length = UInt32(payload.count)
        message.append(contentsOf: [UInt8(length >> 24 & 0xff), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
        message.append(payload)
        return message
    }
}

/// Blocking socket to the BooxDisplay app through `adb forward`. Use from a background thread.
public final class DisplayLink: @unchecked Sendable {
    public let width: Int
    public let height: Int
    private let fd: Int32
    private let lock = NSLock()

    private init(fd: Int32, width: Int, height: Int) {
        self.fd = fd
        self.width = width
        self.height = height
    }

    deinit { close() }

    public static func connect(port: UInt16 = DisplayProtocol.port) throws -> DisplayLink {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DisplayLinkError.connectFailed("socket") }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw DisplayLinkError.connectFailed(String(cString: strerror(errno)))
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // adb forward accepts the connection even when nothing listens, so the greeting is the real test.
        var hello = [UInt8](repeating: 0, count: 8)
        var got = 0
        while got < 8 {
            let n = hello.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, 8 - got) }
            if n <= 0 {
                Darwin.close(fd)
                throw DisplayLinkError.connectFailed("no greeting from the Boox app")
            }
            got += n
        }
        guard Array(hello[0..<4]) == Array("BXH1".utf8) else {
            Darwin.close(fd)
            throw DisplayLinkError.badHello
        }
        return DisplayLink(fd: fd, width: Int(hello[4]) << 8 | Int(hello[5]), height: Int(hello[6]) << 8 | Int(hello[7]))
    }

    public func send(x: Int, y: Int, width: Int, height: Int, gray: Data) throws {
        guard let message = DisplayProtocol.tileMessage(x: x, y: y, width: width, height: height, gray: gray) else {
            throw DisplayLinkError.writeFailed
        }
        lock.lock(); defer { lock.unlock() }
        try message.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = write(fd, buffer.baseAddress! + sent, buffer.count - sent)
                if n <= 0 { throw DisplayLinkError.writeFailed }
                sent += n
            }
        }
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}
