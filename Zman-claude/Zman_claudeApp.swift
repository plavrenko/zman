//
//  Zman_claudeApp.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

@main
struct Zman_claudeApp: App {
    @StateObject private var overlayManager = CalendarOverlayManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    overlayManager.startMonitoring()
                }
                .onDisappear {
                    overlayManager.stopMonitoring()
                }
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
    
    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
