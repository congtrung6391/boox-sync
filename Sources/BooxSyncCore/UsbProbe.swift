import Foundation

public enum UsbProbe {
    /// True if a USB device with vendor name ONYX is attached (Boox in MTP/charging mode).
    public static func booxPresent() async -> Bool {
        let ioreg = URL(fileURLWithPath: "/usr/sbin/ioreg")
        guard let result = try? await ProcessRunner.run(ioreg, ["-p", "IOUSB", "-l", "-w0"]) else { return false }
        return containsOnyx(result.stdout)
    }

    public static func containsOnyx(_ ioregOutput: String) -> Bool {
        ioregOutput.contains("\"USB Vendor Name\" = \"ONYX\"")
    }
}
