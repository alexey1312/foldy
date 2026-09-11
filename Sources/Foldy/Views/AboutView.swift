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

            HStack(alignment: .top, spacing: 18) {
                // The icon the Dock and Finder show, not a stand-in symbol.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foldy")
                        .font(.system(size: 22, weight: .semibold))
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("Your desktop bends as you close the lid.")
                        .foregroundStyle(.secondary)
                    GlassGroup(spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Welcome Tour…") { controller.showOnboarding(step: 0) }
                                .glassButtonStyle()
                            Link("Website", destination: Self.site)
                                .glassButtonStyle()
                            Link("Source", destination: Self.repository)
                                .glassButtonStyle()
                            Link("License", destination: Self.license)
                                .glassButtonStyle()
                        }
                    }
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
                SettingsRow(title: "iPhone Duo", subtitle: "Apple's foldable, and the fold this borrows.") {
                    OpenLink(title: "iPhone Duo", destination: URL(string: "https://www.apple.com/iphone-duo/")!)
                }
                RowDivider()
                SettingsRow(title: "Bendy", subtitle: "The app that first put the fold on a MacBook lid. Foldy is an open re-creation.") {
                    OpenLink(title: "Bendy", destination: URL(string: "https://trybendy.app/")!)
                }
                RowDivider()
                SettingsRow(title: "LidAngleSensor", subtitle: "Sam Henri Gold's work on the hinge sensor's HID report.") {
                    OpenLink(title: "LidAngleSensor", destination: URL(string: "https://github.com/samhenrigold/LidAngleSensor")!)
                }
            }
        }
    }

    static let site = URL(string: "https://foldy.proteinunit.dev/")!
    static let repository = URL(string: "https://github.com/alexey1312/foldy")!
    static let license = URL(string: "https://github.com/alexey1312/foldy/blob/main/LICENSE")!
}

/// The arrow at the end of a credit row: opens `destination` in the browser.
private struct OpenLink: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .help("Open \(title) in the browser")
        .accessibilityLabel("Open \(title)")
    }
}
