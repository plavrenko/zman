//
//  CalendarOverlayManager.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import AppKit
import SwiftUI

/// Manages a floating overlay window that tracks Calendar.app's position on screen.
///
/// Responsibilities: detecting Calendar visibility (on-screen, unobstructed), showing/hiding
/// the overlay, tracking window movement with adaptive polling, and instant drag detection
/// via a global mouse monitor. Owned by AppDelegate for app-lifetime scope.
class CalendarOverlayManager: NSObject {
    private var overlayWindow: NSWindow?
    private var timer: Timer?
    private var isMonitoring = false
    private var calendarPID: pid_t = 0
    /// Calendar window frame in CG coordinates (top-left origin), cached by isCalendarWindowOnScreen()
    private var cachedCalendarCGFrame: CGRect?

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

        // Catch Space switches — Calendar may appear/disappear from current Space
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // Catch Cmd+H hide/unhide — Calendar window leaves/joins on-screen list
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceChanged),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceChanged),
            name: NSWorkspace.didUnhideApplicationNotification,
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
        calendarPID = 0
        calendarWindowID = kCGNullWindowID
        cachedCalendarCGFrame = nil
    }

    @objc private func userDefaultsChanged() {
        updateOverlay()
    }

    private var safetyNetSkipCount = 0

    /// Adaptive polling: 1s when Calendar is frontmost (timezone changes happen here),
    /// every 5th tick (~5s) otherwise. Catches cross-process UserDefaults changes that
    /// don't reliably fire notifications.
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

    /// Central decision: show overlay if mismatch + on-screen + not occluded, hide otherwise.
    private func updateOverlay() {
        guard TeamTimeZoneManager.isCalendarTimezoneMismatch(),
              isCalendarWindowOnScreen() else {
            hideOverlay()
            return
        }

        if isCalendarWindowOccluded() {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func isCalendarAppFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontmostApp.bundleIdentifier == "com.apple.iCal"
    }

    /// Resolve Calendar.app PID, using cache when available.
    /// Returns 0 if Calendar is not running.
    private func resolveCalendarPID() -> pid_t {
        if calendarPID != 0 {
            // Check if cached PID is still valid (process exists)
            if kill(calendarPID, 0) == 0 { return calendarPID }
            calendarPID = 0
            calendarWindowID = kCGNullWindowID
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.iCal"
        }) else { return 0 }
        calendarPID = app.processIdentifier
        return calendarPID
    }

    /// Check if Calendar.app has a window visible on the current Space.
    /// Uses CGWindowList with .optionOnScreenOnly which excludes minimized,
    /// other-Space, and off-screen windows. Also caches the window ID.
    private func isCalendarWindowOnScreen() -> Bool {
        let pid = resolveCalendarPID()
        guard pid != 0 else { return false }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return false }

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == pid,
                  let layer = entry[kCGWindowLayer] as? Int, layer == 0 else {
                continue
            }
            // Cache window ID and CG frame as side effects
            if let wid = entry[kCGWindowNumber] as? CGWindowID {
                calendarWindowID = wid
            }
            if let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
               let x = bounds["X"], let y = bounds["Y"],
               let w = bounds["Width"], let h = bounds["Height"] {
                cachedCalendarCGFrame = CGRect(x: x, y: y, width: w, height: h)
            }
            return true
        }
        cachedCalendarCGFrame = nil
        return false
    }

    /// Check if any other window overlaps Calendar's frame.
    /// Uses .optionOnScreenAboveWindow to get only windows above Calendar in z-order.
    private func isCalendarWindowOccluded() -> Bool {
        guard calendarWindowID != kCGNullWindowID,
              let calendarCGFrame = cachedCalendarCGFrame else {
            return false
        }

        guard let windowsAbove = CGWindowListCopyWindowInfo(
            [.optionOnScreenAboveWindow, .excludeDesktopElements],
            calendarWindowID
        ) as? [[CFString: Any]] else { return false }

        let overlayWinNum = overlayWindow.map { CGWindowID($0.windowNumber) }

        for entry in windowsAbove {
            let wid = entry[kCGWindowNumber] as? CGWindowID ?? 0

            // Skip our own overlay window
            if wid == overlayWinNum { continue }
            // Skip non-standard layers (menu bar, dock, system UI elements)
            guard let layer = entry[kCGWindowLayer] as? Int, layer == 0 else { continue }
            // Skip Calendar's own windows (popups, popovers, sheets, dropdowns)
            if let ownerPID = entry[kCGWindowOwnerPID] as? pid_t, ownerPID == calendarPID { continue }

            guard let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else {
                continue
            }
            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            if windowRect.intersects(calendarCGFrame) {
                return true
            }
        }
        return false
    }

    /// Create the overlay window and start position tracking + mouse monitor.
    /// No-op if overlay already exists (idempotent).
    private func showOverlay() {
        // If overlay already exists, just keep it
        if overlayWindow != nil { return }

        guard resolveCalendarPID() != 0 else { return }

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

        // Start updating position to track Calendar window movement
        startPositionTracking()
        startMouseMonitor()
    }

    /// Tear down overlay window, mouse monitor, and position tracking.
    private func hideOverlay() {
        stopMouseMonitor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        // Don't clear calendarPID here — the overlay may re-appear when occlusion
        // clears. PID is cleared when Calendar actually quits (appTerminated).
        stopPositionTracking()
    }

    // MARK: - Global mouse monitor for fast drag detection

    private var mouseMonitor: Any?

    // Title bar + toolbar height — Calendar.app uses unified style (~52-78pt).
    // Using generous value to catch all draggable areas.
    private static let draggableAreaHeight: CGFloat = 78

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleGlobalMouse(event)
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Detect drag gestures in Calendar's draggable area (title bar / toolbar).
    /// Fades overlay out immediately and switches to fast polling. If the window
    /// didn't actually move (false trigger), checkPosition() fades it back in ~300ms.
    private func handleGlobalMouse(_ event: NSEvent) {
        guard let window = overlayWindow, !isMoving else { return }
        let mouseLoc = NSEvent.mouseLocation
        let frame = window.frame

        // Drag in draggable area (title bar / toolbar) — likely a window drag.
        // Fade out immediately and switch to fast polling. checkPosition()
        // detects when the window stops and fades overlay back in.
        let draggableTop = frame.maxY
        let draggableBottom = draggableTop - Self.draggableAreaHeight
        if mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
           mouseLoc.y >= draggableBottom && mouseLoc.y <= draggableTop {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                window.animator().alphaValue = 0
            }
            isMoving = true
            settleCount = 0
            scheduleTimer(interval: Self.movingInterval)
        }
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
        // Don't clear calendarWindowID — it's used by isCalendarWindowOccluded()
        // and isCalendarWindowOnScreen() even when overlay is hidden.
        // It's cleared when Calendar quits (appTerminated).
    }

    private func scheduleTimer(interval: TimeInterval) {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPosition()
        }
        positionTimer?.tolerance = interval * 0.3
    }

    /// Position tracking state machine. On each tick:
    /// - Frame unchanged + isMoving → count settle frames, then fade in and go idle
    /// - Frame unchanged + idle → re-check mismatch/occlusion, hide if needed
    /// - Frame changed + idle → fade out, switch to fast polling
    /// - Frame changed + isMoving → update lastFrame, reset settle counter
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

            // Re-check visibility on idle ticks (~1s) — catches timezone changes
            // and occlusion changes (windows covering/uncovering Calendar)
            if !isMoving {
                if !TeamTimeZoneManager.isCalendarTimezoneMismatch() || isCalendarWindowOccluded() {
                    hideOverlay()
                }
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

    /// Get Calendar's window frame in NS coordinates (bottom-left origin).
    /// Fast path: single-window query by cached ID. Slow path: enumerate all windows.
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

    /// Convert CG coordinates (top-left origin) to NS coordinates (bottom-left origin).
    /// Uses primary screen height — CG/NS coordinate systems are defined relative to it.
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
