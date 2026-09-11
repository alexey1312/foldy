import FoldyCore
import SwiftUI

struct GeneralSettingsView: View {
    var controller: AppController
    @State private var launchAtLogin = false
    @State private var launchError: String?

    private var settings: SettingsStore { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 24) {
            PaneHeader(title: "General", symbol: "gearshape.fill", tint: .gray)

            SettingsCard {
                SettingsRow(title: "Launch at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            guard enabled != settings.launchAtLogin else { return }
                            do {
                                try settings.setLaunchAtLogin(enabled)
                                launchError = nil
                            } catch {
                                launchError = "Launch at login needs Foldy to run from an app bundle. \(error.localizedDescription)"
                                launchAtLogin = settings.launchAtLogin
                            }
                        }
                }
                if let launchError {
                    Text(launchError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
                RowDivider()
                SettingsRow(title: "Sound", subtitle: "A soft click when the lid opens and the desktop clears.") {
                    Toggle("", isOn: $settings.soundEnabled).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingsRow(title: "Show the lid angle in the menu bar") {
                    Toggle("", isOn: $settings.showsAngleInMenuBar).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingsRow(title: "Fold the sample wallpaper", subtitle: "Instead of the live desktop. Handy for demos and for Macs without Screen Recording.") {
                    Toggle("", isOn: $settings.sampleWallpaper).labelsHidden().toggleStyle(.switch)
                        .onChange(of: settings.sampleWallpaper) { _, _ in controller.evaluate() }
                }
            }

            SettingsCard(title: "Lid sensor") {
                SettingsRow(title: sensorTitle, subtitle: sensorSubtitle) {
                    Image(systemName: controller.sensorAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(controller.sensorAvailable ? .green : .orange)
                }
                RowDivider()
                SettingsRow(title: "Try it now", subtitle: "Runs the fold once on the real desktop, down and back up.") {
                    Button("Try It") { controller.sweep() }
                        .glassButtonStyle()
                        .disabled(controller.isSweeping || controller.isPaused)
                }
            }

            SettingsCard(title: "Screen Recording") {
                SettingsRow(title: controller.hasScreenPermission ? "Allowed" : "Not allowed",
                            subtitle: "Foldy folds the live desktop only with this permission; until then it folds the sample wallpaper. Frames stay on this Mac; nothing is recorded, saved or uploaded.") {
                    Image(systemName: controller.hasScreenPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(controller.hasScreenPermission ? .green : .red)
                }
                if controller.needsRelaunchForPermission {
                    RowDivider()
                    SettingsRow(title: "Relaunch to start capturing", subtitle: "macOS hands a new Screen Recording permission to a fresh process only.") {
                        Button("Relaunch Foldy") { controller.relaunch() }
                            .glassButtonStyle(.prominent)
                    }
                } else if !controller.hasScreenPermission {
                    RowDivider()
                    SettingsRow(title: "Grant access", subtitle: "macOS asks once. If it already said no, allow Foldy in System Settings, then relaunch the app.") {
                        GlassGroup(spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Request…") { controller.requestScreenPermission() }
                                    .glassButtonStyle(.prominent)
                                Button("System Settings…") { controller.openScreenRecordingSettings() }
                                    .glassButtonStyle()
                            }
                        }
                    }
                }
                if case let .failed(message) = controller.captureState {
                    RowDivider()
                    Text("Capture failed: \(message)")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(16)
                }
            }

            SettingsCard(title: "Updates") {
                SettingsRow(title: "Check for updates automatically", subtitle: updatesSubtitle) {
                    Toggle("", isOn: Binding(
                        get: { controller.updater.automaticallyChecks },
                        set: { controller.updater.automaticallyChecks = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(!controller.updater.isAvailable)
                }
                RowDivider()
                SettingsRow(title: "Version \(appVersion)", subtitle: controller.updater.isAvailable ? "Updates come from GitHub Releases, signed with Sparkle's EdDSA key." : "Updates are available in the packaged app only.") {
                    Button("Check Now") { controller.updater.checkForUpdates() }
                        .glassButtonStyle()
                        .disabled(!controller.updater.isAvailable)
                }
            }

            SettingsCard(title: "Pausing") {
                SettingsRow(title: "Click the fold, or press Esc, to clear it until the lid opens again. Pause from the menu bar to switch Foldy off for a while.") {
                    EmptyView()
                }
            }
        }
        .onAppear {
            launchAtLogin = settings.launchAtLogin
            controller.refreshPermission()
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    private var updatesSubtitle: String {
        guard controller.updater.isAvailable else { return "Run Foldy.app to enable updates." }
        if let last = controller.updater.lastCheck {
            return "Last checked \(last.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Not checked yet."
    }

    private var sensorTitle: String {
        switch controller.sensorAvailability {
        case .searching: "Looking for the sensor…"
        case .available: "Lid at \(Int(controller.lidAngle.rounded()))°"
        case .unavailable: "No lid angle sensor"
        }
    }

    private var sensorSubtitle: String {
        switch controller.sensorAvailability {
        case .searching: "Apple silicon MacBooks and the 2019 16-inch MacBook Pro have one."
        case .available: "Read from the Mac's own hinge sensor (\(MacModel.current.identifier))."
        case let .unavailable(reason): reason
        }
    }
}
