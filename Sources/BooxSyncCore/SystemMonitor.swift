import Foundation
import Darwin
import IOKit.ps

public struct ResourceSnapshot: Equatable, Sendable {
    public var cpu: Double = 0               // 0...1
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = 0
    public var diskUsed: UInt64 = 0
    public var diskTotal: UInt64 = 0
    public var networkDown: Double = 0       // bytes per second
    public var networkUp: Double = 0
    public var batteryPercent: Int?
    public var batteryCharging = false

    public init() {}

    public var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }
    public var diskFraction: Double { diskTotal == 0 ? 0 : Double(diskUsed) / Double(diskTotal) }
}

/// Samples CPU, memory, disk, network and battery. Rates are computed between consecutive `sample()` calls.
public final class SystemMonitor {
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var lastNetwork: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastNetworkDate: Date?

    public init() {}

    public func sample() -> ResourceSnapshot {
        var snapshot = ResourceSnapshot()
        snapshot.cpu = sampleCPU()
        (snapshot.memoryUsed, snapshot.memoryTotal) = sampleMemory()
        (snapshot.diskUsed, snapshot.diskTotal) = sampleDisk()
        (snapshot.networkDown, snapshot.networkUp) = sampleNetwork()
        (snapshot.batteryPercent, snapshot.batteryCharging) = sampleBattery()
        return snapshot
    }

    // MARK: CPU

    private func sampleCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return 0 }
        let user = Double(ticks.user &- last.user), system = Double(ticks.system &- last.system)
        let idle = Double(ticks.idle &- last.idle), nice = Double(ticks.nice &- last.nice)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total : 0
    }

    // MARK: Memory

    private func sampleMemory() -> (UInt64, UInt64) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        // Close to Activity Monitor's "Memory Used": app memory + wired + compressed.
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    // MARK: Disk

    private func sampleDisk() -> (UInt64, UInt64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return (0, 0) }
        return (UInt64(max(0, Int64(total) - free)), UInt64(total))
    }

    // MARK: Network

    private func interfaceCounters() -> [String: (rx: UInt32, tx: UInt32)] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [:] }
        defer { freeifaddrs(addresses) }
        var result: [String: (rx: UInt32, tx: UInt32)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            if let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data {
                let name = String(cString: entry.ifa_name)
                if name.hasPrefix("en"), entry.ifa_flags & UInt32(IFF_UP) != 0 {
                    let counters = data.assumingMemoryBound(to: if_data.self).pointee
                    result[name] = (counters.ifi_ibytes, counters.ifi_obytes)
                }
            }
            pointer = entry.ifa_next
        }
        return result
    }

    private func sampleNetwork() -> (Double, Double) {
        let now = Date()
        let counters = interfaceCounters()
        defer {
            lastNetwork = counters
            lastNetworkDate = now
        }
        guard let before = lastNetworkDate else { return (0, 0) }
        let seconds = now.timeIntervalSince(before)
        guard seconds > 0 else { return (0, 0) }
        var down = 0.0, up = 0.0
        for (name, current) in counters {
            guard let previous = lastNetwork[name] else { continue }
            down += Double(current.rx &- previous.rx)   // 32-bit counters wrap
            up += Double(current.tx &- previous.tx)
        }
        return (down / seconds, up / seconds)
    }

    // MARK: Battery

    private func sampleBattery() -> (Int?, Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return (current * 100 / maximum, charging)
        }
        return (nil, false)
    }
}
