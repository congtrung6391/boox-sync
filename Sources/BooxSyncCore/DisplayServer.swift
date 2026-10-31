import Foundation
import Network

public struct DisplayClientInfo: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let dpr: Double
}

/// Serves the display page over HTTP and streams tiles over a WebSocket, both on loopback only.
/// The Boox reaches them through `adb reverse`, so nothing is exposed on the network.
public final class DisplayServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "booxsync.display-server")
    private var httpListener: NWListener?
    private var wsListener: NWListener?
    private var client: NWConnection?

    /// Called whenever the page reports its canvas size (on connect and on resize).
    public var onHello: (@Sendable (DisplayClientInfo) -> Void)?
    public var onClientChange: (@Sendable (Bool) -> Void)?
    /// Any other text message from the page (diagnostics).
    public var onText: (@Sendable (String) -> Void)?

    public init() {}

    public func start() throws {
        let http = try NWListener(using: loopbackParameters(port: DisplayPage.httpPort))
        http.newConnectionHandler = { [weak self] connection in self?.serveHTTP(connection) }
        http.start(queue: queue)
        httpListener = http

        let params = loopbackParameters(port: DisplayPage.webSocketPort)
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let ws = try NWListener(using: params)
        ws.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        ws.start(queue: queue)
        wsListener = ws
    }

    public func stop() {
        queue.sync {
            httpListener?.cancel()
            wsListener?.cancel()
            client?.cancel()
            httpListener = nil
            wsListener = nil
            client = nil
        }
    }

    public var hasClient: Bool { queue.sync { client != nil } }

    /// Tile message: 0x01, x, y, w, h (u16 big endian), then a PNG.
    public func sendTile(x: Int, y: Int, width: Int, height: Int, png: Data) {
        var message = Data([0x01])
        for value in [x, y, width, height] { message.append(contentsOf: [UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]) }
        message.append(png)
        queue.async { [weak self] in
            guard let connection = self?.client else { return }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "tile", metadata: [metadata])
            connection.send(content: message, contentContext: context, isComplete: true, completion: .idempotent)
        }
    }

    /// Binds to 127.0.0.1 only. `requiredInterfaceType` alone still listened on every interface.
    private func loopbackParameters(port: UInt16) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        return parameters
    }

    // MARK: HTTP

    private func serveHTTP(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            let body = Data(DisplayPage.html.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            let isFavicon = data.flatMap { String(data: $0, encoding: .utf8) }?.hasPrefix("GET /favicon") ?? false
            if isFavicon {
                connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                                contentContext: .finalMessage, isComplete: true, completion: .idempotent)
            } else {
                connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
            }
        }
    }

    // MARK: WebSocket

    private func accept(_ connection: NWConnection) {
        client?.cancel()
        client = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.onClientChange?(true)
                self.receive(on: connection)
            case .failed, .cancelled:
                if self.client === connection {
                    self.client = nil
                    self.onClientChange?(false)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            guard let self, let connection, error == nil else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .text, let data, let text = String(data: data, encoding: .utf8), !text.contains("\"hello\"") {
                self.onText?(text)
            }
            if metadata?.opcode == .text, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["type"] as? String == "hello",
               let width = json["w"] as? Int, let height = json["h"] as? Int {
                self.onHello?(DisplayClientInfo(width: width, height: height, dpr: json["dpr"] as? Double ?? 1))
            }
            self.receive(on: connection)
        }
    }
}
