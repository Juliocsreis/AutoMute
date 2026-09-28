import AppKit
import ServiceManagement
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var monitor: AudioRouteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AutoMute")
                .font(.headline)
            Text(monitor.status.title)
                .foregroundStyle(.secondary)
            Text("Output: \(monitor.defaultDeviceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()
                .padding(.vertical, 4)

            Toggle("Enabled", isOn: $monitor.isEnabled)

            Button("Unmute Now") {
                monitor.unmuteNow()
            }
            .disabled(monitor.status != .muted)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                )
            )

            Divider()
                .padding(.vertical, 4)

            Button("Quit AutoMute") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 220)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Unsigned debug builds often cannot register; binding re-reads status.
            }
        }
    }
}
