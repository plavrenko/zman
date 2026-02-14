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

        // Safety-net timer: cross-process UserDefaults changes don't fire notifications
        // reliably, so poll for timezone mismatch. Fast (1s) when Calendar is frontmost
        // (where timezone changes happen), slow (5s) when it's not.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.safetyNetCheck()
        }
        timer?.tolerance = 0.3

        // Also listen for workspace notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Hide overlay immediately when Calendar.app quits
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
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
        stopMouseMonitor()
        hideOverlay()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func workspaceChanged() {
        updateOverlay()
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.iCal" else { return }
        hideOverlay()
    }

    @objc private func userDefaultsChanged() {
        updateOverlay()
    }

    private var safetyNetSkipCount = 0

    private func safetyNetCheck() {
        // When Calendar is frontmost, check every tick (1s) — timezone changes happen here
        if isCalendarAppFrontmost() {
            safetyNetSkipCount = 0
            updateOverlay()
            return
        }
        // When Calendar is not frontmost, only check every 5th tick (~5s) to save CPU
        safetyNetSkipCount += 1
        if safetyNetSkipCount >= 5 {
            safetyNetSkipCount = 0
            updateOverlay()
        }
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
        if overlayWindow != nil {
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

        // Start updating position and listening for drag
        startPositionTracking()
        startMouseMonitor()
    }

    private func hideOverlay() {
        stopMouseMonitor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        calendarPID = 0
        stopPositionTracking()
    }

    // MARK: - Global mouse monitor for instant drag detection

    private var mouseMonitor: Any?

    // Title bar + toolbar height — Calendar.app uses unified style (~52-78pt).
    // Using generous value to catch all draggable areas.
    private static let draggableAreaHeight: CGFloat = 78

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.handleGlobalMouse(event)
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func handleGlobalMouse(_ event: NSEvent) {
        guard let window = overlayWindow, !isMoving else { return }
        let mouseLoc = NSEvent.mouseLocation
        let frame = window.frame

        switch event.type {
        case .leftMouseDown:
            // Check if click is in Calendar's title bar / toolbar zone
            let draggableTop = frame.maxY
            let draggableBottom = draggableTop - Self.draggableAreaHeight
            if mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
               mouseLoc.y >= draggableBottom && mouseLoc.y <= draggableTop {
                fadeOutAndStartMoving(window)
            }
        case .leftMouseDragged:
            // Fallback: if a drag is happening anywhere in the overlay frame,
            // the window is likely being moved (catches edge-drag resize too)
            if frame.contains(mouseLoc) {
                fadeOutAndStartMoving(window)
            }
        default:
            break
        }
    }

    private func fadeOutAndStartMoving(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }
        isMoving = true
        scheduleTimer(interval: Self.movingInterval)
    }

    // MARK: - Position tracking

    private var positionTimer: Timer?
    private var lastFrame: CGRect = .zero
    private var calendarWindowID: CGWindowID = kCGNullWindowID

    private static let idleInterval: TimeInterval = 1.0      // 1 fps while idle — cheap detection of movement start
    private static let movingInterval: TimeInterval = 0.15   // ~7 fps while moving — detect when drag stops
    private static let settleFrames = 2                       // 2 identical frames (~0.3s) = window stopped

    private var settleCount = 0
    private var isMoving = false

    private func startPositionTracking() {
        positionTimer?.invalidate()
        settleCount = 0
        isMoving = false
        calendarWindowID = findCalendarWindowID() ?? kCGNullWindowID
        lastFrame = getCalendarWindowFrame() ?? .zero
        scheduleTimer(interval: Self.idleInterval)
    }

    private func stopPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
        calendarWindowID = kCGNullWindowID
    }

    private func scheduleTimer(interval: TimeInterval) {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPosition()
        }
        positionTimer?.tolerance = interval * 0.3
    }

    private func checkPosition() {
        guard let window = overlayWindow,
              let calendarFrame = getCalendarWindowFrame() else {
            return
        }

        if calendarFrame == lastFrame {
            settleCount += 1
            // Window stopped — snap overlay to final position, fade in, and slow down
            if settleCount == Self.settleFrames && isMoving {
                window.setFrame(calendarFrame, display: false)
                window.alphaValue = 0
                window.orderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    window.animator().alphaValue = 1
                }
                isMoving = false
                scheduleTimer(interval: Self.idleInterval)
            }

            // Re-check timezone mismatch on idle ticks (~1s) — cross-process
            // UserDefaults changes don't fire notifications reliably, so this
            // catches timezone changes much faster than the 5s safety-net timer
            if !isMoving && !TeamTimeZoneManager.isCalendarTimezoneMismatch() {
                hideOverlay()
            }
        } else {
            // Window is moving — fade out overlay and speed up polling to detect stop
            if !isMoving {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    window.animator().alphaValue = 0
                }
                isMoving = true
                scheduleTimer(interval: Self.movingInterval)
            }
            settleCount = 0
            lastFrame = calendarFrame
        }
    }

    /// One-time scan to find Calendar.app's main window ID for targeted queries
    private func findCalendarWindowID() -> CGWindowID? {
        guard calendarPID != 0 else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == calendarPID,
                  let layer = entry[kCGWindowLayer] as? Int, layer == 0,
                  let windowID = entry[kCGWindowNumber] as? CGWindowID else {
                continue
            }
            return windowID
        }
        return nil
    }

    private func getCalendarWindowFrame() -> CGRect? {
        // Fast path: query a single known window ID directly
        if calendarWindowID != kCGNullWindowID {
            if let frame = frameForWindowID(calendarWindowID) {
                return frame
            }
            // Window ID went stale (closed/reopened) — re-discover
            calendarWindowID = findCalendarWindowID() ?? kCGNullWindowID
        }

        // Slow path: enumerate to find the window (also caches the ID for next time)
        guard calendarPID != 0 else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == calendarPID,
                  let layer = entry[kCGWindowLayer] as? Int, layer == 0,
                  let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else {
                continue
            }
            if let wid = entry[kCGWindowNumber] as? CGWindowID {
                calendarWindowID = wid
            }
            return convertToNSWindowCoords(x: x, y: y, w: w, h: h)
        }
        return nil
    }

    /// Query a single window by ID — avoids enumerating all on-screen windows
    private func frameForWindowID(_ windowID: CGWindowID) -> CGRect? {
        let idArray = [windowID] as CFArray
        guard let infoList = CGWindowListCreateDescriptionFromArray(idArray) as? [[CFString: Any]],
              let entry = infoList.first,
              let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"] else {
            return nil
        }
        return convertToNSWindowCoords(x: x, y: y, w: w, h: h)
    }

    private func convertToNSWindowCoords(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        let convertedY = primaryScreen.frame.height - y - h
        return CGRect(x: x, y: convertedY, width: w, height: h)
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
