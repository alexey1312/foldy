import FoldyCore
import SwiftUI

struct SettingsView: View {
    var controller: AppController
    @State private var pane: Pane

    init(controller: AppController, initialPane: Pane = .appearance) {
        self.controller = controller
        _pane = State(initialValue: initialPane)
    }

    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, about
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section("Settings") {
                    SidebarRow(title: "General", symbol: "gearshape.fill", tint: .gray).tag(Pane.general)
                    SidebarRow(title: "Appearance", symbol: "circle.lefthalf.filled", tint: .blue).tag(Pane.appearance)
                }
                Section("Foldy") {
                    SidebarRow(title: "About", symbol: "info.circle.fill", tint: .gray).tag(Pane.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                Group {
                    switch pane {
                    case .general: GeneralSettingsView(controller: controller)
                    case .appearance: AppearanceSettingsView(controller: controller)
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
        }
        .frame(minWidth: 900, idealWidth: 940, minHeight: 700, idealHeight: 760)
        .onAppear { NSApp.activate() }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
        }
        .padding(.vertical, 2)
    }
}

/// A pane title with the sidebar icon, like System Settings.
struct PaneHeader: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

/// A rounded group of rows, the way Bendy and System Settings lay out controls.
struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary.opacity(0.6)))
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}
