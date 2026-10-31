import Foundation

public struct AdbDevice: Equatable, Sendable {
    public enum State: String, Sendable {
        case device, unauthorized, offline, other
    }

    public let serial: String
    public let state: State
    public let model: String?
    public let product: String?
    public let transportId: String?

    public init(serial: String, state: State, model: String? = nil, product: String? = nil, transportId: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
        self.transportId = transportId
    }
}

public enum AdbParser {
    /// Parses the output of `adb devices -l`.
    public static func parseDevices(_ output: String) -> [AdbDevice] {
        var devices: [AdbDevice] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") || line.hasPrefix("*") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 2 else { continue }
            let state = AdbDevice.State(rawValue: fields[1]) ?? .other
            var props: [String: String] = [:]
            for field in fields.dropFirst(2) {
                if let colon = field.firstIndex(of: ":") {
                    props[String(field[..<colon])] = String(field[field.index(after: colon)...])
                }
            }
            devices.append(AdbDevice(
                serial: fields[0], state: state,
                model: props["model"], product: props["product"], transportId: props["transport_id"]))
        }
        return devices
    }
}
