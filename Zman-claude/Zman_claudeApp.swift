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
    }
    
    init() {
        // Start monitoring when app launches
        let manager = CalendarOverlayManager()
        _overlayManager = StateObject(wrappedValue: manager)
        
        DispatchQueue.main.async {
            manager.startMonitoring()
        }
    }
}

// App delegate to prevent app from quitting when windows close
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

