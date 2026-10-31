import SwiftUI
import BooxSyncCore

struct MirrorView: View {
    @StateObject private var model: MirrorModel
    @State private var showDisplay = false

    init(fs: BooxFS) {
        _model = StateObject(wrappedValue: MirrorModel(fs: fs))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle(isOn: $model.isPaused) { Label("Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill") }
                    .toggleStyle(.button)
                Button { showDisplay.toggle() } label: { Label("Display", systemImage: "slider.horizontal.3") }
                    .popover(isPresented: $showDisplay) { displayControls }
                Spacer()
                Text(model.errorMessage ?? model.status)
                    .font(.caption)
                    .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                Button { model.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.image == nil)
                Button { model.saveSnapshot() } label: { Label("Save...", systemImage: "square.and.arrow.down") }
                    .disabled(model.image == nil)
            }
            .padding(8)
            Divider()
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let image = model.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .overlay { PenOverlay(model: model) }
                } else {
                    ProgressView("Waiting for the first frame...")
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Grayscale", isOn: Binding(get: { model.grayscale }, set: { model.grayscale = $0 }))
            LabeledContent("Darkness") {
                Slider(value: Binding(get: { model.gamma }, set: { model.gamma = $0 }), in: 0.2...1.2).frame(width: 150)
            }
            LabeledContent("Contrast") {
                Slider(value: Binding(get: { model.contrast }, set: { model.contrast = $0 }), in: 0.3...2.0).frame(width: 150)
            }
            Toggle("Live pen strokes", isOn: Binding(get: { model.penOverlay }, set: { model.penOverlay = $0 }))
            Button("Reset") { model.resetTone() }
        }
        .padding(14)
    }
}

/// Draws pen strokes that have not reached a screenshot yet.
private struct PenOverlay: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        let _ = model.overlayTick
        Canvas { context, size in
            for stroke in model.strokes where stroke.points.count > 1 {
                var path = Path()
                path.move(to: CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
