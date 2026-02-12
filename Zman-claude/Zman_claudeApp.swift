//
//  Zman_claudeApp.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

@main
struct Zman_claudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var overlayManager = CalendarOverlayManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView(timeZoneService: CalendarTimeZoneService())
        }
    }
    
    init() {
        // Start monitoring when app launches
        let manager = CalendarOverlayManager()
        _overlayManager = StateObject(wrappedValue: manager)
        
        DispatchQueue.main.async {
            manager.startMonitoring()
        }
    }
    
    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
// App delegate to prevent app from quitting when windows close
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

