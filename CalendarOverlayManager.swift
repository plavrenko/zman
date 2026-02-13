//
//  CalendarOverlayManager.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import AppKit
import SwiftUI
/// Manages an overlay window that appears on top of Calendar.app when there's a timezone mismatch
class CalendarOverlayManager: NSObject {
    private var overlayWindow: NSWindow?
    private var timer: Timer?
    private var isMonitoring = false
    private var calendarPID: pid_t = 0

    /// Start monitoring and showing overlay when needed
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Check immediately
        updateOverlay()

        // Safety-net timer: notifications handle most changes, this catches edge cases
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateOverlay()
        }
        timer?.tolerance = 2.5

        // Also listen for workspace notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Listen for UserDefaults changes (both iCal and our app)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    /// Stop monitoring and remove overlay
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        hideOverlay()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func workspaceChanged() {
        updateOverlay()
    }
    
    @objc private func userDefaultsChanged() {
        updateOverlay()
    }
    
    private func updateOverlay() {
        let shouldShow = isCalendarAppFrontmost() && TeamTimeZoneManager.isCalendarTimezoneMismatch()
        
        if shouldShow {
            showOverlay()
        } else {
            hideOverlay()
        }
    }
    
    private func isCalendarAppFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontmostApp.bundleIdentifier == "com.apple.iCal"
    }
    
    private func showOverlay() {
        // If overlay already exists, just update its position
        if let existingWindow = overlayWindow, existingWindow.isVisible {
            updateOverlayPosition()
            return
        }

        // Cache Calendar.app PID to avoid scanning runningApplications on every position tick
        guard let calendarApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.iCal"
        }) else {
            return
        }
        calendarPID = calendarApp.processIdentifier

        // Get Calendar.app window frame
        guard let calendarFrame = getCalendarWindowFrame() else {
            return
        }
        
        // Create overlay window
        let window = NSWindow(
            contentRect: calendarFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        
        // Create the orange tint view
        let hostingView = NSHostingView(rootView: OverlayView())
        hostingView.frame = window.contentView!.bounds
        window.contentView = hostingView
        
        overlayWindow = window
        window.orderFront(nil)
        
        // Start updating position
        startPositionTracking()
    }
    
    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        calendarPID = 0
        stopPositionTracking()
    }
    
    private var positionTimer: Timer?
    
    private func startPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateOverlayPosition()
        }
        positionTimer?.tolerance = 0.2
    }
    
    private func stopPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }
    
    private func updateOverlayPosition() {
        guard let window = overlayWindow,
              let calendarFrame = getCalendarWindowFrame() else {
            return
        }
        
        window.setFrame(calendarFrame, display: true)
    }
    
    private func getCalendarWindowFrame() -> CGRect? {
        guard calendarPID != 0 else { return nil }

        // Use cached PID for Accessibility API
        let app = AXUIElementCreateApplication(calendarPID)
        var windowsValue: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(
            app,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        
        guard result == .success,
              let windows = windowsValue as? [AXUIElement],
              let firstWindow = windows.first else {
            return nil
        }
        
        // Get position (in screen coordinates - bottom-left origin)
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(
            firstWindow,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        
        var position = CGPoint.zero
        if let positionValue = positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        
        // Get size
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(
            firstWindow,
            kAXSizeAttribute as CFString,
            &sizeValue
        )
        
        var size = CGSize.zero
        if let sizeValue = sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        
        // Convert from screen coordinates (bottom-left origin) to NSWindow coordinates (top-left origin)
        guard let screen = NSScreen.main else {
            return CGRect(origin: position, size: size)
        }
        
        let screenHeight = screen.frame.height
        let convertedY = screenHeight - position.y - size.height
        let convertedPosition = CGPoint(x: position.x, y: convertedY)
        
        return CGRect(origin: convertedPosition, size: size)
    }
    
    deinit {
        stopMonitoring()
    }
}

/// The visual overlay view
struct OverlayView: View {
    var body: some View {
        Color.orange.opacity(0.15)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .ignoresSafeArea()
    }
}
