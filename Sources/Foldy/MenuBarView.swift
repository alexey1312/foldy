import AppKit
import FoldyCore
import SwiftUI

struct MenuBarView: View {
    var controller: AppController

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Button(controller.isPaused ? "Resume" : "Pause") {
            controller.togglePause()
        }
        .keyboardShortcut("p")
        Button("Try It Now") {
            controller.sweep()
        }
        .disabled(controller.isSweeping || controller.isPaused)
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Foldy") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct MenuBarLabel: View {
    var controller: AppController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: controller.isPaused ? "laptopcomputer.slash" : "laptopcomputer")
            if controller.settings.showsAngleInMenuBar, controller.sensorAvailable {
                Text("\(Int(controller.lidAngle.rounded()))°")
                    .monospacedDigit()
            }
        }
    }
}
