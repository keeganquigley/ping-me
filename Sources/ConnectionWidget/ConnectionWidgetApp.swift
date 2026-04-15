import AppKit
import SwiftUI

final class ConnectionWidgetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ConnectionWidgetApp: App {
    @NSApplicationDelegateAdaptor(ConnectionWidgetAppDelegate.self) private var appDelegate
    @StateObject private var monitor = ConnectivityMonitor()

    var body: some Scene {
        Window("Connection Widget", id: "main-dashboard-window") {
            ConnectionDashboardView()
                .environmentObject(monitor)
        }
        .defaultSize(width: 420, height: 620)
        MenuBarExtra {
            ConnectionDashboardView()
                .environmentObject(monitor)
        } label: {
            Image(systemName: monitor.menuBarSymbolName)
                .accessibilityLabel("Connection Widget")
        }
        .menuBarExtraStyle(.window)
    }
}
