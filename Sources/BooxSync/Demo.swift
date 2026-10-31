import SwiftUI
import AppKit
import BooxSyncCore

/// Fake data for the README screenshots: `BooxSync --demo files|mirror|display|dashboard [--demo-path /sdcard/Books]`.
/// Nothing is read from the Boox or the Mac (no files, windows, music or reminders) and nothing is saved.
enum Demo {
    private static let arguments = CommandLine.arguments

    static let isOn = arguments.contains("--demo")
    /// False while demo data is on screen, and for the headless render commands, so sample data never overwrites real settings.
    static let persistSettings = !(isOn || arguments.contains("--render-dashboard") || arguments.contains("--render-variants"))
    static var tab: String? { argument(after: "--demo") }
    static var startPath: String? { argument(after: "--demo-path") }

    private static func argument(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1, !arguments[index + 1].hasPrefix("--") else { return nil }
        return arguments[index + 1]
    }

    // MARK: Files

    static func entries(in path: String) -> [BooxEntry] {
        let calendar = Calendar.current
        /// `days` ago at a given hour and minute, so the list shows believable, varied times.
        func stamp(_ days: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) ?? Date()
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func folder(_ name: String, _ days: Int, _ hour: Int, _ minute: Int) -> BooxEntry {
            BooxEntry(name: name, path: "\(path)/\(name)", isDirectory: true, modified: stamp(days, hour, minute))
        }
        func file(_ name: String, _ megabytes: Double, _ days: Int, _ hour: Int, _ minute: Int) -> BooxEntry {
            BooxEntry(name: name, path: "\(path)/\(name)", isDirectory: false, size: Int64(megabytes * 1_048_576), modified: stamp(days, hour, minute))
        }
        switch path {
        case BooxFS.root:
            return [folder("Books", 1, 9, 12), folder("Documents", 6, 18, 40), folder("Download", 2, 7, 5),
                    folder("note", 0, 8, 31), folder("Pictures", 30, 21, 15), folder("Push", 9, 13, 48)]
        case BooxFS.root + "/Books":
            return [folder("Novels", 14, 20, 3), folder("Study", 3, 10, 26),
                    file("Pride and Prejudice.epub", 1.1, 20, 22, 14), file("Meditations.epub", 0.6, 11, 7, 52),
                    file("The Art of War.pdf", 0.8, 45, 16, 9), file("Walden.epub", 1.4, 33, 11, 37),
                    file("Design Patterns, my notes.pdf", 6.4, 2, 19, 21), file("Weekly plan.pdf", 0.3, 0, 8, 44)]
        case BooxFS.root + "/Documents":
            return [file("Travel itinerary.pdf", 0.9, 4, 15, 30), file("Lecture slides week 4.pdf", 12.2, 8, 9, 5),
                    file("Meeting notes.pdf", 0.4, 1, 17, 18)]
        default:
            return []
        }
    }

    // MARK: Windows (Display tab)

    static func windows() -> (boox: [WindowInfo], mac: [WindowInfo]) {
        func window(_ id: UInt32, _ app: String, _ title: String) -> WindowInfo {
            WindowInfo(id: id, pid: 0, appName: app, title: title, bounds: CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        return (
            boox: [window(1, "Safari", "Meditations, Book 2 (reading)"), window(2, "Notes", "Study plan")],
            mac: [window(3, "Safari", "Weather forecast"), window(4, "Mail", "Inbox"), window(5, "Calendar", "November 2026"),
                  window(6, "Preview", "Cambridge IELTS 18.pdf"), window(7, "Reminders", "Today")]
        )
    }

    /// The real icon of a system app, so the demo list looks like the real one.
    static func icon(forApp name: String) -> NSImage? {
        let bundleIDs = ["Safari": "com.apple.Safari", "Notes": "com.apple.Notes", "Mail": "com.apple.mail",
                         "Calendar": "com.apple.iCal", "Preview": "com.apple.Preview", "Reminders": "com.apple.reminders"]
        guard let id = bundleIDs[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Mirror

    @MainActor
    static func mirrorImage() -> NSImage {
        let renderer = ImageRenderer(content: MockNotePage())
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: NSSize(width: 1872, height: 1404))
    }
}

/// A made-up Boox notebook page, so the Mirror screenshot shows plausible content.
struct MockNotePage: View {
    private let ink = Color(white: 0.08)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Canvas { context, size in
                for x in stride(from: 108, to: size.width - 40, by: 54) {
                    for y in stride(from: 216, to: size.height - 40, by: 54) {
                        context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.gray.opacity(0.55)))
                    }
                }
            }
            HStack(spacing: 46) {
                Image(systemName: "arrow.left")
                Text("Study plan").font(.system(size: 40, weight: .semibold))
                Spacer()
                Image(systemName: "pencil.tip")
                Image(systemName: "highlighter")
                Image(systemName: "eraser")
                Image(systemName: "arrow.uturn.backward")
                Image(systemName: "arrow.uturn.forward")
            }
            .font(.system(size: 44))
            .foregroundStyle(ink)
            .padding(.horizontal, 60)
            .frame(height: 120)
            Rectangle().fill(ink).frame(height: 3).offset(y: 120)

            VStack(alignment: .leading, spacing: 34) {
                Text("IELTS study plan").font(.custom("Bradley Hand", size: 112).bold())
                Text("Mon  -  Writing task 2").font(.custom("Bradley Hand", size: 74))
                Text("Wed  -  Listening practice").font(.custom("Bradley Hand", size: 74))
                Text("Fri  -  Full mock test").font(.custom("Bradley Hand", size: 74))
                Text("Sun  -  Review mistakes").font(.custom("Bradley Hand", size: 74))
                Text("Goal: band 7.5 by December").font(.custom("Bradley Hand", size: 86).bold()).padding(.top, 36)
            }
            .foregroundStyle(ink)
            .rotationEffect(.degrees(-1.2), anchor: .topLeading)
            .offset(x: 150, y: 190)

            Canvas { context, _ in
                var underline = Path()
                underline.move(to: CGPoint(x: 150, y: 372)); underline.addCurve(to: CGPoint(x: 920, y: 366), control1: CGPoint(x: 420, y: 388), control2: CGPoint(x: 700, y: 352))
                context.stroke(underline, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                var box = Path()
                box.addRoundedRect(in: CGRect(x: 138, y: 904, width: 1120, height: 130), cornerSize: CGSize(width: 40, height: 40))
                context.stroke(box, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // A small hand-drawn diagram on the right: three boxes joined by arrows.
                for (index, label) in ["Read", "Write", "Review"].enumerated() {
                    let x = 1230 + CGFloat(index) * 210, y: CGFloat = 420
                    var shape = Path()
                    shape.addRoundedRect(in: CGRect(x: x, y: y + CGFloat(index % 2) * 90, width: 170, height: 96), cornerSize: CGSize(width: 26, height: 26))
                    context.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    context.draw(Text(label).font(.custom("Bradley Hand", size: 46)).foregroundStyle(ink), at: CGPoint(x: x + 85, y: y + 48 + CGFloat(index % 2) * 90))
                    if index < 2 {
                        var arrow = Path()
                        let start = CGPoint(x: x + 172, y: y + 48 + CGFloat(index % 2) * 90), end = CGPoint(x: x + 208, y: y + 48 + CGFloat((index + 1) % 2) * 90)
                        arrow.move(to: start); arrow.addLine(to: end)
                        arrow.move(to: end); arrow.addLine(to: CGPoint(x: end.x - 14, y: end.y - 8))
                        arrow.move(to: end); arrow.addLine(to: CGPoint(x: end.x - 10, y: end.y + 12))
                        context.stroke(arrow, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    }
                }
            }
        }
        .frame(width: 1872, height: 1404)
    }
}
