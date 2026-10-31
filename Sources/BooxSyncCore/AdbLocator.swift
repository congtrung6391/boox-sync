import Foundation

public enum AdbLocator {
    /// Finds adb: bundled copy first, then common install locations, then PATH.
    public static func find(
        bundleResources: URL? = Bundle.main.resourceURL,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let bundleResources { candidates.append(bundleResources.appendingPathComponent("adb")) }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/adb"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/adb"))
        for dir in (environmentPath ?? "").split(separator: ":") {
            candidates.append(URL(fileURLWithPath: String(dir)).appendingPathComponent("adb"))
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
