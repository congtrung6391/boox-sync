import SwiftUI
import BooxSyncCore

struct OnboardingStepsContent {
    let title: String
    let items: [String]
}

enum OnboardingSteps {
    /// Setup instructions for the current state, or nil when nothing is needed.
    static func steps(for status: DeviceStatus) -> OnboardingStepsContent? {
        switch status {
        case .connected:
            nil
        case .noDevice:
            OnboardingStepsContent(title: "Connect the Boox", items: [
                "Plug the Boox into a Mac USB-C or Thunderbolt port with a data cable.",
                "Charge-only cables will not work.",
            ])
        case .booxWithoutDebugging:
            OnboardingStepsContent(title: "Turn on USB debugging", items: [
                "On the Boox open Apps, then the menu at the top right, then App Management.",
                "Switch on USB Debug Mode.",
                "Unplug and replug the cable.",
                "Tap Allow on the \"Allow USB debugging?\" prompt.",
            ])
        case .unauthorized:
            OnboardingStepsContent(title: "Allow this Mac", items: [
                "Look at the Boox screen and tap Allow on the USB debugging prompt.",
                "Tick \"Always allow from this computer\" to skip this next time.",
                "E-ink is slow, so give the dialog a few seconds to draw.",
            ])
        case .offline:
            OnboardingStepsContent(title: "Reconnect the Boox", items: [
                "Unplug and replug the cable.",
                "If it stays offline, switch USB Debug Mode off and on.",
            ])
        case .adbMissing:
            OnboardingStepsContent(title: "Install adb", items: [
                "Run: brew install android-platform-tools",
                "A future release bundles adb so this step goes away.",
            ])
        }
    }
}

struct OnboardingView: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }
}
