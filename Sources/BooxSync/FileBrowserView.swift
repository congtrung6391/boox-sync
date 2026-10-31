import SwiftUI
import BooxSyncCore

private let shortcuts: [(title: String, symbol: String, path: String)] = [
    ("Internal storage", "internaldrive", BooxFS.root),
    ("Books", "books.vertical", BooxFS.root + "/Books"),
    ("Documents", "doc.text", BooxFS.root + "/Documents"),
    ("Download", "arrow.down.circle", BooxFS.root + "/Download"),
    ("Notes", "pencil.and.scribble", BooxFS.root + "/note"),
    ("Pictures", "photo", BooxFS.root + "/Pictures"),
    ("Push", "tray.and.arrow.down", BooxFS.root + "/Push"),
]

struct FileBrowserView: View {
    @ObservedObject var model: FileBrowserModel
    @State private var renameTarget: BooxEntry?
    @State private var renameText = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var deleteIDs: Set<String>?
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(shortcuts, id: \.path, selection: Binding(get: { model.path }, set: { if let p = $0 { model.go(to: p) } })) { item in
                Label(item.title, systemImage: item.symbol).tag(item.path)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                breadcrumbBar
                Divider()
                table
                if let activity = model.activity {
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(activity).font(.callout)
                        Spacer()
                    }
                    .padding(8)
                }
                if !model.transfers.items.isEmpty { Divider() }
                TransfersPanel(queue: model.transfers)
            }
        }
        .task { await model.load() }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let target = renameTarget { model.rename(target, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { model.makeFolder(named: newFolderName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(deleteIDs?.count ?? 0) item(s) from the Boox? This cannot be undone.",
            isPresented: Binding(get: { deleteIDs != nil }, set: { if !$0 { deleteIDs = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { if let ids = deleteIDs { model.delete(ids) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
            Button { model.goUp() } label: { Image(systemName: "chevron.up") }
                .disabled(!model.canGoUp)
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                Button(crumb.name) { model.go(to: crumb.path) }
                    .buttonStyle(.plain)
                    .fontWeight(index == model.breadcrumbs.count - 1 ? .semibold : .regular)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button { showNewFolder = true; newFolderName = "" } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            Button { model.chooseFilesToSend() } label: { Label("Send to Boox", systemImage: "square.and.arrow.up") }
            Button { model.copyToMac(model.selection) } label: { Label("Copy to Mac", systemImage: "square.and.arrow.down") }
                .disabled(model.selection.isEmpty)
            Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
        }
        .padding(8)
    }

    private var table: some View {
        Table(of: BooxEntry.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { entry in
                Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
            }
            TableColumn("Size", value: \.sortSize) { entry in
                Text(entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Modified", value: \.sortDate) { entry in
                Text(entry.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "--")
                    .foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 200, max: 260)
        } rows: {
            ForEach(model.sortedEntries) { entry in
                TableRow(entry).itemProvider { model.itemProvider(for: entry) }
            }
        }
        .contextMenu(forSelectionType: BooxEntry.ID.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1, model.entries.first(where: { ids.contains($0.id) })?.isDirectory == true {
                    Button("Open") { model.open(ids) }
                }
                Button("Copy to Mac...") { model.copyToMac(ids) }
                if ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) }) {
                    Button("Rename...") { renameText = entry.name; renameTarget = entry }
                }
                Divider()
                Button("Delete...", role: .destructive) { deleteIDs = ids }
            }
        } primaryAction: { ids in
            model.open(ids)
        }
        .dropDestination(for: URL.self, action: { urls, _ in
            model.send(urls.filter(\.isFileURL))
            return true
        }, isTargeted: { dropTargeted = $0 })
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
    }
}
