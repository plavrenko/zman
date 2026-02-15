//
//  Zman_claudeApp.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

/// App entry point. Uses AppDelegate adaptor to own CalendarOverlayManager
/// and prevent quit on last window close (background utility pattern).
@main
struct Zman_claudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Zman") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Zman",
                            NSApplication.AboutPanelOptionKey.applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                            NSApplication.AboutPanelOptionKey.version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "A minimalistic utility that colors iCal with overlay if it differs from remote team's timezone.\n\nDeveloped by Pavel Lavrenko\npavel@lavrenko.info",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                ]
                            ),
                            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Pavel Lavrenko"
                        ]
                    )
                }
            }
        }
    }
}

/// App delegate: prevents quit on window close, owns overlay manager for app lifetime
class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayManager = CalendarOverlayManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayManager.startMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

