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
            selector: #selector(activeAppChanged(_:)),
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

    @objc private func activeAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            updateOverlay()
            return
        }

        // When focus leaves Calendar, fade quickly first, then re-evaluate after
        // the new app's window stack has settled in CGWindowList.
        if app.bundleIdentifier != "com.apple.iCal" {
            fadeOutOverlayQuickly()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fastRefreshDelay) { [weak self] in
                self?.updateOverlay()
            }
        } else {
            updateOverlay()
        }
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
        scheduleInitialVisibilityValidation()
    }

    /// Tear down overlay window, mouse monitor, and position tracking.
    private func hideOverlay() {
        initialValidationGeneration += 1
        stopMouseMonitor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        // Don't clear calendarPID here — the overlay may re-appear when occlusion
        // clears. PID is cleared when Calendar actually quits (appTerminated).
        stopPositionTracking()
    }

    // MARK: - Global input monitor for fast drag/close detection

    private var mouseMonitor: Any?

    // Title bar + toolbar height — Calendar.app uses unified style (~52-78pt).
    // Using generous value to catch all draggable areas.
    private static let draggableAreaHeight: CGFloat = 78
    // Resize handles are near edges/corners; use a narrow border ring hit-test.
    private static let resizeBorderThickness: CGFloat = 8
    // Small outward tolerance improves edge detection at high pointer speed.
    private static let resizeOuterTolerance: CGFloat = 2
    // macOS traffic-light controls are in the top-left corner of titled windows.
    private static let trafficLightAreaWidth: CGFloat = 96
    private static let trafficLightAreaHeight: CGFloat = 32
    private static let fastRefreshDelay: TimeInterval = 0.05
    private static let fastRefreshAttempts = 6
    private var fastRefreshGeneration = 0
    private static let initialValidationDelay: TimeInterval = 0.05
    private static let initialValidationAttempts = 6
    private var initialValidationGeneration = 0

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseDown, .keyDown]) { [weak self] event in
            self?.handleGlobalInput(event)
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Detect drag gestures in Calendar windows and close actions.
    /// - Drag in move/resize handles: fade overlay immediately and switch to fast polling.
    /// - Close actions (traffic-light click or Cmd+W): trigger immediate visibility refresh.
    private func handleGlobalInput(_ event: NSEvent) {
        if event.type == .keyDown {
            handleGlobalKeyDown(event)
            return
        }
        if event.type == .leftMouseDown {
            handleGlobalMouseDown(event)
            return
        }
        handleGlobalMouseDragged(event)
    }

    private func handleGlobalMouseDragged(_ event: NSEvent) {
        guard let window = overlayWindow, !isMoving else { return }
        let mouseLoc = NSEvent.mouseLocation
        let targetFrame: CGRect
        if window.frame.contains(mouseLoc) {
            targetFrame = window.frame
        } else if let hoveredCalendarFrame = calendarWindowFrameContaining(mouseLoc) {
            // Calendar can switch active windows (e.g., event editor/info popup)
            // while overlay/frame tracking catches up on the next position tick.
            targetFrame = hoveredCalendarFrame
        } else {
            return
        }

        guard isMouseInMoveOrResizeHandle(mouseLoc, frame: targetFrame) else { return }

        // Fade out immediately and switch to fast polling. checkPosition()
        // detects when the window stops and fades overlay back in.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }
        isMoving = true
        settleCount = 0
        scheduleTimer(interval: Self.movingInterval)
    }

    /// Detect non-drag close/dismiss interactions that should hide or retarget overlay quickly.
    private func handleGlobalMouseDown(_ event: NSEvent) {
        guard let overlay = overlayWindow else { return }
        let mouseLoc = NSEvent.mouseLocation

        // Popup-dismiss path: overlay is on one Calendar window (e.g. event info),
        // user clicks another Calendar window area. Fade immediately instead of
        // waiting for idle polling.
        if !overlay.frame.contains(mouseLoc),
           let hoveredFrame = calendarWindowFrameContaining(mouseLoc),
           !areFramesApproximatelyEqual(overlay.frame, hoveredFrame) {
            fadeOutOverlayQuickly()
            scheduleFastVisibilityRefreshBurst()
            return
        }

        let targetFrame: CGRect
        if overlay.frame.contains(mouseLoc) {
            let frame = overlay.frame
            targetFrame = frame
        } else if let frame = calendarWindowFrameContaining(mouseLoc) {
            targetFrame = frame
        } else {
            return
        }
        guard isMouseInTrafficLightArea(mouseLoc, frame: targetFrame) else { return }
        fadeOutOverlayQuickly()
        scheduleFastVisibilityRefreshBurst()
    }

    /// Detect keyboard-driven window dismiss actions (`Esc`, `Cmd+W`).
    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard overlayWindow != nil else { return }
        guard isCalendarAppFrontmost() else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandOnly = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let isCommandW = isCommandOnly && key == "w"
        let isEscape = event.keyCode == 53 || key == "\u{1b}"
        if isEscape {
            scheduleFastVisibilityRefreshBurst()
            return
        }
        guard isCommandW else { return }
        fadeOutOverlayQuickly()
        scheduleFastVisibilityRefreshBurst()
    }

    private func fadeOutOverlayQuickly() {
        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }
    }

    /// Some UI actions complete asynchronously (close/dismiss/focus/z-order commit).
    /// Refresh multiple times to avoid falling back to 1s idle polling.
    private func scheduleFastVisibilityRefreshBurst() {
        fastRefreshGeneration += 1
        let generation = fastRefreshGeneration
        runFastVisibilityRefreshBurst(generation: generation, remaining: Self.fastRefreshAttempts)
    }

    private func runFastVisibilityRefreshBurst(generation: Int, remaining: Int) {
        guard generation == fastRefreshGeneration else { return }
        checkPosition()
        guard overlayWindow != nil else { return }
        guard remaining > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fastRefreshDelay) { [weak self] in
            self?.runFastVisibilityRefreshBurst(generation: generation, remaining: remaining - 1)
        }
    }

    /// Right after showing, validate frequently to catch quick open→close races
    /// before the 1s idle polling tick.
    private func scheduleInitialVisibilityValidation() {
        initialValidationGeneration += 1
        let generation = initialValidationGeneration
        runInitialVisibilityValidation(generation: generation, remaining: Self.initialValidationAttempts)
    }

    private func runInitialVisibilityValidation(generation: Int, remaining: Int) {
        guard generation == initialValidationGeneration else { return }
        guard overlayWindow != nil else { return }
        checkPosition()
        guard overlayWindow != nil, remaining > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialValidationDelay) { [weak self] in
            self?.runInitialVisibilityValidation(generation: generation, remaining: remaining - 1)
        }
    }

    /// Shared hit-test for move and resize handles of a Calendar window frame.
    private func isMouseInMoveOrResizeHandle(_ mouseLoc: CGPoint, frame: CGRect) -> Bool {
        // Drag in draggable area (title bar / toolbar) — likely a window move.
        let draggableTop = frame.maxY
        let draggableBottom = draggableTop - Self.draggableAreaHeight
        let inTitleDragArea =
            mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
            mouseLoc.y >= draggableBottom && mouseLoc.y <= draggableTop

        // Drag near edges/corners — likely a window resize.
        let expandedFrame = frame.insetBy(dx: -Self.resizeOuterTolerance, dy: -Self.resizeOuterTolerance)
        let innerFrame = frame.insetBy(dx: Self.resizeBorderThickness, dy: Self.resizeBorderThickness)
        let inResizeBorder = expandedFrame.contains(mouseLoc) && !innerFrame.contains(mouseLoc)

        return inTitleDragArea || inResizeBorder
    }

    /// Hit-test the standard traffic-light area (close/minimize/zoom controls).
    private func isMouseInTrafficLightArea(_ mouseLoc: CGPoint, frame: CGRect) -> Bool {
        let area = CGRect(
            x: frame.minX,
            y: frame.maxY - Self.trafficLightAreaHeight,
            width: Self.trafficLightAreaWidth,
            height: Self.trafficLightAreaHeight
        )
        return area.contains(mouseLoc)
    }

    private func areFramesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.size.width - rhs.size.width) <= tolerance &&
        abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    /// Finds topmost on-screen Calendar layer-0 window under the mouse in NS coordinates.
    private func calendarWindowFrameContaining(_ mouseLoc: CGPoint) -> CGRect? {
        let pid = resolveCalendarPID()
        guard pid != 0 else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == pid,
                  let layer = entry[kCGWindowLayer] as? Int, layer == 0,
                  let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else {
                continue
            }
            let frame = convertToNSWindowCoords(x: x, y: y, w: w, h: h)
            if frame.contains(mouseLoc) {
                return frame
            }
        }
        return nil
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
        guard let window = overlayWindow else {
            return
        }
        guard let calendarFrame = getCalendarWindowFrame() else {
            // Tracked Calendar window disappeared (close/Cmd+W/Space change) — hide immediately.
            hideOverlay()
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
