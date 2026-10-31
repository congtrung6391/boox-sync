import SwiftUI
import BooxSyncCore

struct DisplayView: View {
    @ObservedObject var model: DisplayModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: model.isActive ? "display.2" : "display")
                .font(.system(size: 54))
                .foregroundStyle(model.isActive ? Color.accentColor : Color.secondary)

            Text("Use the Boox as a second display").font(.title2.weight(.semibold))

            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)

            if case .failed(let message) = model.phase {
                VStack(spacing: 8) {
                    Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Open Screen Recording settings") { model.openScreenRecordingSettings() }
                    Text("If BooxSync is already switched on there, the entry is probably stale from an older build. Run  tccutil reset ScreenCapture dev.booxsync.app  in Terminal, reopen BooxSync and allow it again.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
            }

            if model.phase == .running {
                VStack(spacing: 4) {
                    Text("\(model.stats.width) x \(model.stats.height) px  ·  \(model.stats.tilesPerSecond) tiles/s  ·  \(model.stats.kilobytesPerSecond) KB/s")
                        .font(.callout.monospacedDigit())
                    Text("A new display now sits to the right of your main display. Drag windows onto it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Display settings...") { model.openDisplaySettings() }
            }

            Button {
                model.isActive ? model.stop() : model.start()
            } label: {
                Text(model.isActive ? "Stop" : "Start second display")
                    .frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(model.isActive ? .red : .accentColor)
            .disabled(model.phase == .starting)

            if model.phase == .idle || model.phase == .failed("") {
                Text("The Boox opens its browser in fullscreen over USB. macOS asks for Screen Recording permission the first time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
