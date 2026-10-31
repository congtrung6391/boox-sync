import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BooxSyncCore

@MainActor
final class FileBrowserModel: ObservableObject {
    let fs: BooxFS
    let transfers: TransferQueue

    @Published var path = BooxFS.root
    @Published var entries: [BooxEntry] = []
    @Published var selection = Set<String>()
    @Published var sortOrder = [KeyPathComparator(\BooxEntry.name)]
    @Published var isLoading = false
    @Published var activity: String?
    @Published var errorMessage: String?

    private var backStack: [String] = []

    init(fs: BooxFS) {
        self.fs = fs
        self.transfers = TransferQueue(fs: fs)
        transfers.onPushFinished = { [weak self] destination in
            guard let self, destination == self.path else { return }
            Task { await self.load() }
        }
    }

    var sortedEntries: [BooxEntry] {
        let sorted = entries.sorted(using: sortOrder)
        return sorted.filter(\.isDirectory) + sorted.filter { !$0.isDirectory }
    }

    var canGoUp: Bool { path != BooxFS.root && path != "/" }
    var canGoBack: Bool { !backStack.isEmpty }

    /// Folders from the storage root to the current folder, for the breadcrumb.
    var breadcrumbs: [(name: String, path: String)] {
        var result = [(name: "Internal storage", path: BooxFS.root)]
        let relative = path.dropFirst(BooxFS.root.count)
        var current = BooxFS.root
        for part in relative.split(separator: "/") {
            current += "/" + part
            result.append((String(part), current))
        }
        return result
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await fs.list(path)
            selection = []
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    func go(to newPath: String, recordHistory: Bool = true) {
        guard newPath != path else { return }
        if recordHistory { backStack.append(path) }
        path = newPath
        Task { await load() }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        go(to: previous, recordHistory: false)
    }

    func goUp() {
        guard canGoUp else { return }
        go(to: (path as NSString).deletingLastPathComponent)
    }

    func open(_ ids: Set<String>) {
        guard ids.count == 1, let entry = entries.first(where: { ids.contains($0.id) }), entry.isDirectory else { return }
        go(to: entry.path)
    }

    // MARK: Transfers

    func copyToMac(_ ids: Set<String>) {
        let chosen = entries.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Copy Here"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        transfers.enqueuePull(chosen, folder: folder)
    }

    func chooseFilesToSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send to Boox"
        guard panel.runModal() == .OK else { return }
        send(panel.urls)
    }

    func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        transfers.enqueuePush(urls, destination: path)
    }

    // MARK: Edits

    func delete(_ ids: Set<String>) {
        let chosen = entries.filter { ids.contains($0.id) }
        Task {
            await perform("Deleting") {
                for entry in chosen { try await self.fs.delete(entry.path) }
            }
            await load()
        }
    }

    func rename(_ entry: BooxEntry, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), name != entry.name else { return }
        Task {
            await perform("Renaming") { try await self.fs.rename(entry.path, to: name) }
            await load()
        }
    }

    func makeFolder(named newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        let target = path + "/" + name
        Task {
            await perform("Creating folder") { try await self.fs.makeDirectory(target) }
            await load()
        }
    }

    /// File promise for dragging an item out of the window into Finder.
    func itemProvider(for entry: BooxEntry) -> NSItemProvider {
        let fs = self.fs
        let provider = NSItemProvider()
        provider.suggestedName = entry.name
        let type = entry.isDirectory ? UTType.folder : UTType.data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task.detached {
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("booxsync-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try await fs.pull(entry.path, to: dir)
                    completion(dir.appendingPathComponent(entry.name), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func perform(_ label: String, _ work: () async throws -> Void) async {
        activity = label
        defer { activity = nil }
        do { try await work() } catch { errorMessage = error.localizedDescription }
    }
}
