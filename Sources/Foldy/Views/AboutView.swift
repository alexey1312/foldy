import SwiftUI

struct AboutView: View {
    var controller: AppController

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "Version \(short) (\(build))"
        case let (short?, nil): return "Version \(short)"
        default: return "Development build"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PaneHeader(title: "About", symbol: "info.circle.fill", tint: .gray)

            HStack(spacing: 18) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.gradient))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foldy")
                        .font(.system(size: 22, weight: .semibold))
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("Your desktop bends as you close the lid.")
                        .foregroundStyle(.secondary)
                    Button("Welcome Tour…") { controller.showOnboarding(step: 0) }
                        .glassButtonStyle()
                        .padding(.top, 6)
                }
            }

            SettingsCard(title: "How it works") {
                SettingsRow(title: "Lid sensor", subtitle: "Reads the hinge angle from the Mac's own HID sensor. It asks for input reports and keeps a heartbeat poll that speeds up only while the lid moves.") { EmptyView() }
                RowDivider()
                SettingsRow(title: "Live desktop", subtitle: "Captures the display with ScreenCaptureKit and draws it with Metal: a sheet that tilts and bends, blurs toward the top and falls into shadow.") { EmptyView() }
                RowDivider()
                SettingsRow(title: "On device", subtitle: "Frames go from the capture straight to the GPU. Nothing is recorded, saved or uploaded, and there is no account.") { EmptyView() }
            }

            SettingsCard(title: "Credits") {
                SettingsRow(title: "iPhone Duo", subtitle: "Apple's foldable, and the fold this borrows.") { EmptyView() }
                RowDivider()
                SettingsRow(title: "Bendy", subtitle: "The app that first put the fold on a MacBook lid. Foldy is an open re-creation.") { EmptyView() }
                RowDivider()
                SettingsRow(title: "LidAngleSensor", subtitle: "Sam Henri Gold's work on the hinge sensor's HID report.") { EmptyView() }
            }
        }
    }
}
