import AppKit
import SwiftUI

@main
struct AutoMuteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(monitor: appDelegate.monitor)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: AudioRouteMonitor

    var body: some View {
        Image(systemName: monitor.status.symbolName)
            .accessibilityLabel("AutoMute \(monitor.status.title)")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = AudioRouteMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MuteNotifier.requestAuthorizationIfNeeded()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
