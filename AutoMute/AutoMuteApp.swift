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
        Image(systemName: symbolName)
            .accessibilityLabel("AutoMute \(monitor.statusText)")
    }

    private var symbolName: String {
        switch monitor.statusText {
        case "Muted":
            return "speaker.slash.fill"
        case "Bluetooth":
            return "headphones"
        case "Disabled":
            return "speaker.slash"
        default:
            return "ear"
        }
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
