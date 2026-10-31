import Foundation

public struct BooxEntry: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64?
    public let modified: Date?

    public init(name: String, path: String, isDirectory: Bool, isSymlink: Bool = false, size: Int64? = nil, modified: Date? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modified = modified
    }

    public var sortSize: Int64 { size ?? -1 }
    public var sortDate: Date { modified ?? .distantPast }
}

/// Parses the output of Android toybox `ls -lA`.
public enum LsParser {
    public static func parse(_ output: String, directory: String) -> [BooxEntry] {
        output.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0), directory: directory) }
    }

    static func parseLine(_ rawLine: String, directory: String) -> BooxEntry? {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if line.isEmpty || line.hasPrefix("total ") { return nil }

        // perms links owner group size date time name...
        var index = line.startIndex
        func token() -> String? {
            while index < line.endIndex, line[index] == " " { index = line.index(after: index) }
            guard index < line.endIndex else { return nil }
            let start = index
            while index < line.endIndex, line[index] != " " { index = line.index(after: index) }
            return String(line[start..<index])
        }
        guard let perms = token(), perms.count >= 10,
              token() != nil, token() != nil, token() != nil,
              let sizeText = token(), let date = token(), let time = token() else { return nil }
        // Exactly one space separates the time from the name; the name may itself contain spaces.
        guard index < line.endIndex else { return nil }
        var name = String(line[line.index(after: index)...])

        let kind = perms.first
        let isSymlink = kind == "l"
        if isSymlink, let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
        if name.isEmpty || name == "." || name == ".." { return nil }

        let isDirectory = kind == "d"
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        return BooxEntry(
            name: name,
            path: base + name,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: isDirectory ? nil : Int64(sizeText),
            modified: parseDate(date, time))
    }

    private static func parseDate(_ date: String, _ time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = time.count > 5 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }
}

public enum LocalFS {
    /// Total size in bytes of a file or folder on the Mac.
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let file as URL in walker {
                let values = try? file.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
            }
        }
        return total
    }
}
