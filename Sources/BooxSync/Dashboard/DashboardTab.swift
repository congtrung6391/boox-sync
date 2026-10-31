import SwiftUI
import BooxSyncCore

/// Edits the dashboard: drag components on the grid, resize from the corner, add from the palette.
struct DashboardTab: View {
    @ObservedObject var display: DisplayModel
    @ObservedObject var model: DashboardModel
    let fs: BooxFS

    @State private var selection: UUID?
    @State private var noRoom: WidgetKind?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                DashboardCanvas(model: model, selection: $selection)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                Inspector(model: model, selection: $selection, onNoRoom: { noRoom = $0 })
                    .frame(width: 320)
            }
        }
        .onAppear { model.retain(fs: fs) }
        .onDisappear { model.release() }
        .alert("No room for \(noRoom?.title ?? "that")", isPresented: Binding(get: { noRoom != nil }, set: { if !$0 { noRoom = nil } })) {
            Button("OK") { noRoom = nil }
        } message: {
            Text("Make a component smaller or remove one, then add it again.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Toggle("Show on the Boox", isOn: $display.dashboardOn).toggleStyle(.switch).fixedSize()
            if display.phase != .running {
                Text("Start the second display in the Display tab to see it on the Boox.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(Array(DashboardLayout.presets.enumerated()), id: \.offset) { index, preset in
                    Button(preset.name) { model.applyPreset(index); selection = nil }
                }
            } label: {
                Label("Presets", systemImage: "square.grid.2x2")
            }
            .fixedSize()
            Toggle("Outlines", isOn: $model.layout.outlines).toggleStyle(.checkbox)
            Toggle("Dark theme", isOn: $model.layout.dark).toggleStyle(.checkbox)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: Canvas

private struct DashboardCanvas: View {
    @ObservedObject var model: DashboardModel
    @Binding var selection: UUID?
    @State private var drag: DragState?

    private let inset: CGFloat = 37
    private let aspect: CGFloat = 1872.0 / 1302.0

    private struct DragState {
        var id: UUID
        var col: Int, row: Int, cols: Int, rows: Int
        var valid: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * aspect)
            let canvas = CGSize(width: width, height: width / aspect)
            ZStack(alignment: .topLeading) {
                DashboardView(model: model, topInset: inset)
                    .frame(width: canvas.width, height: canvas.height)
                    .allowsHitTesting(false)
                gridDots(canvas)
                ForEach(model.layout.items) { item in overlay(for: item, canvas: canvas) }
                if let drag { ghost(drag, canvas: canvas) }
            }
            .frame(width: canvas.width, height: canvas.height)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { selection = nil }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func gridDots(_ canvas: CGSize) -> some View {
        Canvas { context, _ in
            let area = DashboardGeometry.gridArea(in: canvas, topInset: inset)
            let cell = DashboardGeometry.cellSize(in: canvas, topInset: inset)
            for col in 0...DashboardLayout.columns {
                for row in 0...DashboardLayout.rows {
                    let point = CGPoint(x: area.minX + CGFloat(col) * cell.width, y: area.minY + CGFloat(row) * cell.height)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(.gray.opacity(0.45)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func overlay(for item: WidgetItem, canvas: CGSize) -> some View {
        let rect = DashboardGeometry.frame(of: item, in: canvas, topInset: inset)
        let selected = selection == item.id
        return ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(Color.accentColor.opacity(selected ? 0.10 : 0))
            Rectangle().stroke(selected ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: selected ? 3 : 1)
            if selected {
                Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 9, y: 9)
                    .gesture(resizeGesture(item, canvas: canvas))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .onTapGesture { selection = item.id }
        .gesture(moveGesture(item, canvas: canvas))
        .position(x: rect.midX, y: rect.midY)
    }

    private func ghost(_ state: DragState, canvas: CGSize) -> some View {
        let rect = DashboardGeometry.frame(col: state.col, row: state.row, cols: state.cols, rows: state.rows, in: canvas, topInset: inset)
        let color: Color = state.valid ? .green : .red
        return Rectangle().fill(color.opacity(0.18))
            .overlay(Rectangle().stroke(color, style: StrokeStyle(lineWidth: 3, dash: [8, 5])))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func moveGesture(_ item: WidgetItem, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                selection = item.id
                let cell = DashboardGeometry.cellSize(in: canvas, topInset: inset)
                var proposed = item
                proposed.col = min(max(0, item.col + Int((value.translation.width / cell.width).rounded())), DashboardLayout.columns - item.cols)
                proposed.row = min(max(0, item.row + Int((value.translation.height / cell.height).rounded())), DashboardLayout.rows - item.rows)
                drag = DragState(id: item.id, col: proposed.col, row: proposed.row, cols: item.cols, rows: item.rows, valid: model.layout.isFree(proposed))
            }
            .onEnded { _ in
                if let drag, drag.valid { model.layout.move(item.id, toCol: drag.col, row: drag.row) }
                drag = nil
            }
    }

    private func resizeGesture(_ item: WidgetItem, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let cell = DashboardGeometry.cellSize(in: canvas, topInset: inset)
                var proposed = item
                proposed.cols = min(max(item.kind.minSize.cols, item.cols + Int((value.translation.width / cell.width).rounded())), DashboardLayout.columns - item.col)
                proposed.rows = min(max(item.kind.minSize.rows, item.rows + Int((value.translation.height / cell.height).rounded())), DashboardLayout.rows - item.row)
                drag = DragState(id: item.id, col: item.col, row: item.row, cols: proposed.cols, rows: proposed.rows, valid: model.layout.isFree(proposed))
            }
            .onEnded { _ in
                if let drag, drag.valid { model.layout.resize(item.id, cols: drag.cols, rows: drag.rows) }
                drag = nil
            }
    }
}

// MARK: Inspector

private struct Inspector: View {
    @ObservedObject var model: DashboardModel
    @Binding var selection: UUID?
    var onNoRoom: (WidgetKind) -> Void

    private var item: WidgetItem? { model.layout.items.first { $0.id == selection } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let item {
                    selected(item)
                } else {
                    Text("Select a component on the canvas to change it. Drag to move, drag the dot in the corner to resize.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                palette
            }
            .padding(16)
        }
    }

    // MARK: Selected component

    @ViewBuilder
    private func selected(_ item: WidgetItem) -> some View {
        HStack {
            Label(item.kind.title, systemImage: item.kind.symbol).font(.headline)
            Spacer()
            Button(role: .destructive) { model.layout.remove(item.id); selection = nil } label: { Label("Remove", systemImage: "trash") }
        }
        Picker("Style", selection: Binding(get: { item.safeVariant }, set: { model.layout.setVariant(item.id, $0) })) {
            ForEach(Array(item.kind.variantNames.enumerated()), id: \.offset) { index, name in Text(name).tag(index) }
        }
        .pickerStyle(.menu)
        VStack(alignment: .leading, spacing: 8) {
            stepper("Column", value: item.col + 1, range: 1...DashboardLayout.columns) { model.layout.move(item.id, toCol: $0 - 1, row: item.row) }
            stepper("Row", value: item.row + 1, range: 1...DashboardLayout.rows) { model.layout.move(item.id, toCol: item.col, row: $0 - 1) }
            stepper("Width", value: item.cols, range: item.kind.minSize.cols...DashboardLayout.columns) { model.layout.resize(item.id, cols: $0, rows: item.rows) }
            stepper("Height", value: item.rows, range: item.kind.minSize.rows...DashboardLayout.rows) { model.layout.resize(item.id, cols: item.cols, rows: $0) }
        }
        switch item.kind {
        case .note: NoteSettings(model: model, itemID: item.id, text: item.text)
        case .weather: WeatherSettings(model: model)
        case .todo: TodoSettings(model: model)
        default: EmptyView()
        }
    }

    /// A stepper that quietly ignores values that would overlap another component or leave the grid.
    private func stepper(_ title: String, value: Int, range: ClosedRange<Int>, apply: @escaping (Int) -> Bool) -> some View {
        Stepper(value: Binding(get: { value }, set: { _ = apply($0) }), in: range) {
            HStack { Text(title); Spacer(); Text("\(value)").monospacedDigit().foregroundStyle(.secondary) }
        }
    }

    // MARK: Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add component").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(WidgetKind.allCases, id: \.self) { kind in
                    Button {
                        if let id = model.layout.add(kind) { selection = id } else { onNoRoom(kind) }
                    } label: {
                        Label(kind.title, systemImage: kind.symbol).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: Per-component settings

private struct NoteSettings: View {
    @ObservedObject var model: DashboardModel
    let itemID: UUID
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text").font(.subheadline.weight(.semibold))
            TextEditor(text: Binding(get: { text }, set: { model.setNote(itemID, text: $0) }))
                .font(.body).frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
        }
    }
}

private struct WeatherSettings: View {
    @ObservedObject var model: DashboardModel
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("City").font(.subheadline.weight(.semibold))
            Text(model.place?.displayName ?? "Not set").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Search for a city", text: $query).onSubmit(search)
                Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { _, place in
                Button {
                    model.place = place
                    results = []
                    query = ""
                } label: {
                    Text(place.displayName).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            Toggle("Use Fahrenheit", isOn: $model.fahrenheit)
            Text("Weather comes from Open-Meteo and needs internet on the Mac.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        Task {
            results = await model.searchPlaces(text)
            searching = false
        }
    }
}

private struct TodoSettings: View {
    @ObservedObject var model: DashboardModel
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source").font(.subheadline.weight(.semibold))
            Picker("Source", selection: $model.todoSource) {
                Text("BooxSync list").tag(TodoSource.local)
                Text("Reminders").tag(TodoSource.reminders)
            }
            .pickerStyle(.segmented).labelsHidden()

            switch model.todoSource {
            case .local: local
            case .reminders: reminders
            }
        }
    }

    private var local: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Add a task", text: $newTitle).onSubmit(add)
                Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(model.todos) { todo in
                HStack(spacing: 8) {
                    Button { model.toggleTodo(todo.id) } label: { Image(systemName: todo.done ? "checkmark.square.fill" : "square") }
                        .buttonStyle(.plain)
                    Text(todo.title).strikethrough(todo.done).lineLimit(2)
                    Spacer()
                    Button { model.removeTodo(todo.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                }
            }
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("List", selection: $model.reminderList) {
                Text("All lists").tag("")
                ForEach(model.reminderLists, id: \.self) { Text($0).tag($0) }
            }
            switch model.reminders {
            case .denied:
                Text("Reminders access is off for BooxSync.").font(.caption).foregroundStyle(.red)
                Button("Open Reminders privacy settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                }
            case .items(let items):
                Text("\(items.count) open reminders").font(.caption).foregroundStyle(.secondary)
            case .idle:
                Text("Asking for access...").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await model.refreshReminders() }
    }

    private func add() {
        model.addTodo(newTitle)
        newTitle = ""
    }
}
