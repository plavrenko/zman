# Changelog

All notable changes to Zman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Safety-net timer now adapts to context: 1s when Calendar is frontmost (where timezone changes happen), 5s otherwise — reduces worst-case timezone detection from ~7.5s to ~1s
- Position tracking idle ticks re-check timezone mismatch for immediate overlay removal
- Reduced position tracking timer from 0.1s to 1.0s (was 30 Accessibility API calls/sec, now 3)
- Reduced main monitoring timer from 0.5s to 5.0s safety-net (notifications are primary trigger)
- Replaced CalendarTimeZoneService 2s polling timer with notification-based updates
- Cached UserDefaults(suiteName:) in TeamTimeZoneManager instead of re-creating per call
- Added guard against position timer leak and duplicate notification observers
- Removed documentation files from app bundle resources
- Added timer tolerance (50% on safety-net, 20% on position) for CPU wake-up coalescing
- Cached Calendar.app PID to skip runningApplications scan on every position tick
- Removed dead code: unused `isCalendarAppRunning()` method and empty `cancellables` set
- Replaced Accessibility API (AXUIElement) with CGWindowList API for window frame tracking — no cross-process IPC
- Cached Calendar.app window ID for single-window queries via `CGWindowListCreateDescriptionFromArray`
- Overlay now hides during Calendar window movement and reappears at final position (adaptive two-speed polling: 1s idle / 0.15s moving)
- Added fade-out (0.15s) and fade-in (0.2s) animations using NSAnimationContext for smooth overlay transitions

### Fixed
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
