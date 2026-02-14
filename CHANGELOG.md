# Changelog

All notable changes to Zman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Overlay now shows whenever Calendar window is visible and unobstructed, even when Calendar is not the frontmost app
- Occlusion detection: overlay hides when any window overlaps Calendar's frame, reappears when Calendar is uncovered
- Workspace notifications for Space switches (`activeSpaceDidChangeNotification`) and app hide/unhide for instant visibility reaction
- `resolveCalendarPID()` helper with PID caching and `kill(pid, 0)` validation

### Changed
- Safety-net timer now adapts to context: 1s when Calendar is frontmost (where timezone changes happen), 5s otherwise — reduces worst-case timezone detection from ~7.5s to ~1s
- Position tracking idle ticks re-check timezone mismatch for immediate overlay removal
- Reduced position tracking timer from 0.1s to 1.0s (was 30 Accessibility API calls/sec, now 3)
- Reduced main monitoring timer from 0.5s to 5.0s safety-net (notifications are primary trigger)
- Replaced CalendarTimeZoneService 2s polling timer with notification-based updates
- Cached UserDefaults(suiteName:) in TeamTimeZoneManager instead of re-creating per call
- Added guard against position timer leak and duplicate notification observers
- Removed documentation files from app bundle resources
- Added timer tolerance (30%) on all timers for CPU wake-up coalescing
- Cached Calendar.app PID to skip runningApplications scan on every position tick
- Removed dead code: unused `isCalendarAppRunning()` method and empty `cancellables` set
- Replaced Accessibility API (AXUIElement) with CGWindowList API for window frame tracking — no cross-process IPC
- Cached Calendar.app window ID for single-window queries via `CGWindowListCreateDescriptionFromArray`
- Overlay now hides during Calendar window movement and reappears at final position (adaptive two-speed polling: 1s idle / 0.15s moving)
- Added fade-out (0.15s) and fade-in (0.2s) animations using NSAnimationContext for smooth overlay transitions
- Added global mouse monitor for instant drag detection — overlay fades out immediately when `leftMouseDragged` starts in Calendar's draggable area (title bar / toolbar)

### Fixed
- Fixed overlay disappearing when clicking Calendar's timezone picker or view selector buttons (mouse monitor restricted to `leftMouseDragged` in draggable area only — no `leftMouseDown`, no body-area drags)
- Fixed Calendar's own popup windows (timezone dropdown, popovers) being treated as occluding windows — now skipped by PID
- Fixed notification observer leak in CalendarTimeZoneService (token was discarded, observer never removed)
- Fixed double initialization of CalendarOverlayManager — moved to AppDelegate as single owner
- Removed unnecessary ObservableObject conformance and Combine import from CalendarOverlayManager
- Overlay now hides immediately when Calendar.app quits (was delayed up to 5s)
- Changed `setFrame(display: true)` to `display: false` — eliminates forced synchronous redraw every 1s
- Added safety deinit to CalendarTimeZoneService for observer cleanup
- Fixed multi-screen overlay positioning — used `NSScreen.screens.first` (primary screen) instead of `NSScreen.main` (focused screen) for CG→NS coordinate conversion

### Removed
- Deleted unused AboutView.swift (75 lines of dead code)

## [1.0.0] - 2026-02-12

### Added
- Initial public release

---

## Release Notes

### Version 1.0.0
First public release of Zman, a minimalistic utility that colors iCal with overlay if it differs from remote team's timezone.
