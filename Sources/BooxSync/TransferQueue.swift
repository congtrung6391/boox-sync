import SwiftUI
import AppKit
import BooxSyncCore

@MainActor
final class TransferQueue: ObservableObject {
    enum Direction { case toBoox, toMac }
    enum State: Equatable { case queued, running, done, failed(String), cancelled }

    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let direction: Direction
        var state: State = .queued
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        /// Where the finished copy ended up on the Mac (for "Show in Finder").
        var localURL: URL?
    }

    private enum Job {
        case push(URL, destination: String)
        case pull(BooxEntry, folder: URL)
    }

    @Published private(set) var items: [Item] = []
    /// Called after a push into `destination` completes so the browser can refresh.
    var onPushFinished: ((String) -> Void)?

    private let fs: BooxFS
    private var jobs: [UUID: Job] = [:]
    private var worker: Task<Void, Never>?
    private var currentTask: Task<Void, Never>?
    private var currentID: UUID?

    init(fs: BooxFS) {
        self.fs = fs
    }

    var hasFinished: Bool { items.contains { $0.state != .queued && $0.state != .running } }

    func enqueuePush(_ urls: [URL], destination: String) {
        for url in urls {
            add(Item(title: url.lastPathComponent, direction: .toBoox), .push(url, destination: destination))
        }
    }

    func enqueuePull(_ entries: [BooxEntry], folder: URL) {
        for entry in entries {
            add(Item(title: entry.name, direction: .toMac), .pull(entry, folder: folder))
        }
    }

    func cancel(_ id: UUID) {
        if id == currentID { currentTask?.cancel() } else { update(id) { $0.state = .cancelled } }
    }

    func clearFinished() {
        items.removeAll { $0.state != .queued && $0.state != .running }
    }

    private func add(_ item: Item, _ job: Job) {
        items.append(item)
        jobs[item.id] = job
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task {
            while let next = items.first(where: { $0.state == .queued }) {
                currentID = next.id
                update(next.id) { $0.state = .running }
                let task = Task { await self.run(next.id) }
                currentTask = task
                await task.value
                currentTask = nil
                currentID = nil
            }
            worker = nil
        }
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func run(_ id: UUID) async {
        guard let job = jobs[id] else { return }
        let fs = self.fs
        do {
            switch job {
            case .push(let url, let destination):
                let total = LocalFS.size(of: url)
                update(id) { $0.bytesTotal = total }
                let remote = (destination.hasSuffix("/") ? destination : destination + "/") + url.lastPathComponent
                let poller = poll(id) { (try? await fs.size(of: remote)) ?? 0 }
                defer { poller.cancel() }
                do { try await fs.push(url, toDirectory: destination) } catch {
                    poller.cancel()
                    if Task.isCancelled { try? await fs.delete(remote) }
                    throw error
                }
                await fs.scanMedia(remote)
                onPushFinished?(destination)
            case .pull(let entry, let folder):
                let total = (try? await fs.size(of: entry.path)) ?? 0
                update(id) { $0.bytesTotal = total }
                let local = folder.appendingPathComponent(entry.name)
                let poller = poll(id) { LocalFS.size(of: local) }
                defer { poller.cancel() }
                do { try await fs.pull(entry.path, to: folder) } catch {
                    poller.cancel()
                    if Task.isCancelled { try? FileManager.default.removeItem(at: local) }
                    throw error
                }
                update(id) { $0.localURL = local }
            }
            update(id) { $0.state = .done; $0.bytesDone = $0.bytesTotal }
        } catch {
            if Task.isCancelled {
                update(id) { $0.state = .cancelled }
            } else {
                update(id) { $0.state = .failed(error.localizedDescription) }
            }
        }
        jobs[id] = nil
    }

    /// Samples how many bytes have arrived at the destination about once a second.
    private func poll(_ id: UUID, _ measure: @escaping @Sendable () async -> Int64) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                let bytes = await measure()
                update(id) { $0.bytesDone = min(bytes, max($0.bytesTotal, 0)) }
            }
        }
    }
}

struct TransfersPanel: View {
    @ObservedObject var queue: TransferQueue

    var body: some View {
        if !queue.items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Transfers").font(.subheadline.weight(.semibold))
                    Spacer()
                    if queue.hasFinished { Button("Clear") { queue.clearFinished() }.buttonStyle(.link) }
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(queue.items) { item in TransferRow(queue: queue, item: item) }
                    }
                }
                .frame(maxHeight: 130)
            }
            .padding(10)
        }
    }
}

private struct TransferRow: View {
    let queue: TransferQueue
    let item: TransferQueue.Item

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.direction == .toBoox ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                switch item.state {
                case .running:
                    if item.bytesTotal > 0 {
                        ProgressView(value: Double(item.bytesDone), total: Double(item.bytesTotal))
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                case .queued: Text("Waiting").font(.caption).foregroundStyle(.secondary)
                case .done: Text("Done").font(.caption).foregroundStyle(.green)
                case .cancelled: Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                case .failed(let message): Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            switch item.state {
            case .running, .queued:
                Button { queue.cancel(item.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
            case .done:
                if let url = item.localURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                }
            default: EmptyView()
            }
        }
        .font(.callout)
    }

    private var detail: String {
        let done = ByteCountFormatter.string(fromByteCount: item.bytesDone, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: item.bytesTotal, countStyle: .file)
        return "\(done) of \(total)"
    }
}
