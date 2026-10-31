import Foundation

public enum DeviceStatus: Equatable, Sendable {
    case adbMissing
    case noDevice
    /// A Boox (USB vendor ONYX) is plugged in but adb does not see it.
    case booxWithoutDebugging
    case unauthorized(serial: String)
    case offline(serial: String)
    case connected(AdbDevice)
}

@MainActor
public final class DeviceMonitor: ObservableObject {
    @Published public private(set) var status: DeviceStatus = .noDevice
    @Published public private(set) var adbURL: URL?

    private var task: Task<Void, Never>?
    private let interval: Duration

    public init(interval: Duration = .seconds(2)) {
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func refresh() async {
        let adb = AdbLocator.find()
        adbURL = adb
        guard let adb else {
            status = .adbMissing
            return
        }
        let devices: [AdbDevice]
        do {
            let result = try await ProcessRunner.run(adb, ["devices", "-l"])
            devices = AdbParser.parseDevices(result.stdout)
        } catch {
            status = .adbMissing
            return
        }
        status = await Self.resolve(devices: devices)
    }

    private static func resolve(devices: [AdbDevice]) async -> DeviceStatus {
        if let ready = devices.first(where: { $0.state == .device }) { return .connected(ready) }
        if let unauth = devices.first(where: { $0.state == .unauthorized }) { return .unauthorized(serial: unauth.serial) }
        if let off = devices.first(where: { $0.state == .offline }) { return .offline(serial: off.serial) }
        return await UsbProbe.booxPresent() ? .booxWithoutDebugging : .noDevice
    }
}
