# AGENTS.md

AI coding assistant context for Zman project.

## Overview

macOS utility that displays an orange overlay on Calendar.app when the app's timezone differs from a configured team timezone. SwiftUI windowed app with AppKit overlay management. Runs in background after window closes. Deployment target: macOS26

## Architecture

- **Pattern**: MVVM-like with ObservableObject managers
- **Layer structure**:
  - UI Layer: SwiftUI views (ContentView, OverlayView)
  - Manager Layer: CalendarOverlayManager, TeamTimeZoneManager (struct with static methods), CalendarTimeZoneService
  - System Integration: AppKit for window management, CGWindowList API for Calendar.app window tracking
- **Data flow**: UserDefaults (both app and com.apple.iCal suite) → Managers → SwiftUI @Published properties → UI

## Tech Stack

- **Swift**: Latest
- **UI Framework**: SwiftUI (primary) + AppKit (overlay windows, workspace monitoring)
- **Key Dependencies**:
  - `AppKit`: Window management, NSWorkspace monitoring
  - `CoreGraphics`: CGWindowList API for window frame tracking
  - `SwiftUI`: Primary UI, NSHostingView for embedding in NSWindow
  - `Combine`: Publisher/subscriber pattern for ObservableObject
  - `Foundation`: UserDefaults, Timer, DateFormatter
- **No external packages**: All dependencies are system frameworks

## Module Map

- **Single target**: Zman-claude (app)
- **Source files**:
  - `Zman_claudeApp.swift`: @main entry point, AppDelegate (owns CalendarOverlayManager), command menu setup
  - `ContentView.swift`: Main settings window, team timezone picker
  - `CalendarOverlayManager.swift`: Floating window overlay management, Calendar.app tracking
  - `CalendarTimeZoneService.swift`: Reads Calendar.app UserDefaults, @MainActor ObservableObject
  - `TeamTimeZoneManager.swift`: Struct with static methods for team timezone storage/comparison
  - `OverlayView.swift`: Inline in CalendarOverlayManager.swift

## Conventions

**Naming**:
- Swift files: PascalCase with underscores for app name (e.g., `Zman_claudeApp.swift`)
- Classes/Structs: PascalCase (e.g., `CalendarOverlayManager`)
- Properties: camelCase
- Static members: camelCase
- UserDefaults keys: camelCase strings (e.g., "teamTimeZone", "lastViewsTimeZone")
- Bundle ID pattern: `com.apple.iCal` for Calendar.app

**File organization**:
- One primary type per file (exception: small helper views like OverlayView)
- Consistent file header with copyright, date, author
- ObservableObjects marked with `@MainActor` where appropriate
- Private members for internal manager state

**Patterns**:
- ObservableObject for UI-bound services (CalendarTimeZoneService)
- AppDelegate owns app-lifetime managers (CalendarOverlayManager)
- @AppStorage for UserDefaults bindings
- Notification-driven updates with adaptive safety-net timer (1s when Calendar frontmost, 5s otherwise)
- Adaptive position tracking: 1s idle poll, overlay hides on move, fades back on settle
- CGWindowList API with cached window ID for single-window queries
- UserDefaults suite access for reading Calendar.app preferences
- NSAnimationContext for GPU-accelerated fade transitions
- NSHostingView bridge for SwiftUI in NSWindow

**UI**:
- SF Symbols for icons
- System colors/materials (controlBackgroundColor)
- Rounded corners (12pt for cards, 25pt for overlay)
- Semantic color names (.tint, .secondary, .tertiary)
- Shadow radius: 2pt for elevated cards

**Memory management**:
- `[weak self]` in Timer and notification closures
- Explicit cleanup in stopMonitoring/deinit
- Timer tolerance set on all timers to allow macOS coalescing
- Cached Calendar.app PID to avoid repeated runningApplications scans
- Cached CGWindowID for single-window queries instead of enumerating all windows
- Notification observer tokens stored and properly removed on cleanup

## Do Not

- **Do not use EventKit**: Despite README mention, no EventKit access in code. App reads Calendar.app UserDefaults, not calendar events.
- **Do not switch back to Accessibility API for position tracking**: CGWindowList is significantly lighter than AXUIElement cross-process IPC. AX API is no longer used.
- **Do not change overlay opacity/color**: Fixed at `Color.orange.opacity(0.15)` - this is the core UX.
- **Do not remove safety-net timer**: Calendar.app does not reliably post notifications for timezone preference changes. The adaptive safety-net timer (1s when Calendar frontmost, 5s otherwise) catches edge cases that UserDefaults.didChangeNotification misses for the com.apple.iCal suite.
- **Do not access calendar events**: This is a timezone indicator, not an event reader.
- **Do not change bundle ID references**: `com.apple.iCal` is hardcoded for Calendar.app detection.
- **Do not remove AppDelegate**: Prevents app quit on window close—essential for menu bar utility behavior.
- **Do not show windows on all spaces**: Overlay uses `.canJoinAllSpaces` but main window does not.
- **Do not make overlay clickable**: `.ignoresMouseEvents = true` is critical—overlay must be non-intrusive.
- **Do not change UserDefaults suite names**: `com.apple.iCal` suite is required for reading Calendar settings.
- **Do not simplify coordinate conversion**: Screen coordinate conversion (top-left → bottom-left origin) is necessary for CGWindowList → NSWindow mapping. Must use `NSScreen.screens.first` (primary screen), never `NSScreen.main` (focused screen) — the CG/NS coordinate systems are defined relative to the primary screen.
- **Do not remove overlay fade animations**: The 0.15s fade-out / 0.2s fade-in masks the 1s idle poll detection delay and makes movement feel intentional.

## Additional Notes

- TeamTimeZoneManager is a struct with only static methods—could be enum or namespace instead.
- **Timer polling rationale**: Calendar.app doesn't reliably post notifications when timezone preferences change in com.apple.iCal UserDefaults suite. Primary detection uses UserDefaults.didChangeNotification and NSWorkspace.didActivateApplicationNotification, with an adaptive safety-net timer (1s when Calendar is frontmost — where timezone changes happen — 5s otherwise). Position tracking idle ticks also re-check mismatch for immediate overlay removal.
- **Position tracking strategy**: Adaptive two-speed polling — 1s idle to detect movement start, 0.15s while moving to detect stop. Overlay fades out on movement, fades in at final position. CGWindowList with cached window ID for single-window queries.
- No error handling for CGWindowList failures—overlay silently fails if screen recording permission unavailable.
- App stays running when window closed (AppDelegate prevents termination)—typical menu bar app pattern.
