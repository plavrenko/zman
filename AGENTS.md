# AGENTS.md

AI coding assistant context for Zman project.

## Overview

macOS utility that displays an orange overlay on Calendar.app when the app's timezone differs from a configured team timezone. SwiftUI windowed app with AppKit overlay management. Runs in background after window closes. Deployment target: macOS26

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md) contains Mermaid diagrams (C4, data flow, event/state flow) for human readers. **Do not load it into context** — it duplicates what's below in visual form and wastes tokens. **Do update it** when changing architecture.

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

**Code comments**:
- `///` doc comment on every type (class/struct/enum) — role and relationships
- `///` on public/internal methods — the API surface a caller sees
- `///` on non-obvious private methods — where the name doesn't fully explain behavior (e.g. state machines, multi-path logic)
- Skip `///` on trivial private helpers where the name is self-documenting (e.g. `hideOverlay`, `stopMouseMonitor`)
- Inline `//` comments for "why", not "what" — explain decisions, tradeoffs, non-obvious constraints
- No DocC or formal documentation generation — comments are for humans and AI agents

**Patterns**:
- ObservableObject for UI-bound services (CalendarTimeZoneService)
- AppDelegate owns app-lifetime managers (CalendarOverlayManager)
- @AppStorage for UserDefaults bindings
- Notification-driven updates with adaptive safety-net timer (1s when Calendar frontmost, 5s otherwise)
- Overlay visible whenever Calendar window is on-screen and unobstructed (not just when Calendar is frontmost)
- Occlusion detection via `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow)` — hides overlay if any layer-0 window intersects Calendar's frame (filters out own overlay by window number and Calendar's own popups by PID)
- Workspace notifications for Space switches, app hide/unhide to react immediately to visibility changes
- Adaptive position tracking: 1s idle poll, overlay hides on move, fades back on settle
- Global mouse monitor (`NSEvent.addGlobalMonitorForEvents(.leftMouseDragged)`) for instant drag detection — fades overlay out when drag starts in Calendar's draggable area (title bar / toolbar, top 78pt)
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
- Cached Calendar.app PID (`resolveCalendarPID()` helper with `kill(pid, 0)` validation) to avoid repeated runningApplications scans
- Cached CGWindowID and CG-coordinate frame for single-window queries and occlusion checks
- Notification observers removed on cleanup (selector-based in CalendarOverlayManager, token-based in CalendarTimeZoneService)

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
- **Do not use leftMouseDown for drag detection**: Only `leftMouseDragged` in the draggable area (top 78pt) should trigger overlay fade-out. Using mouseDown causes false triggers on toolbar button clicks. Detecting drags in the full frame area causes false triggers on in-app drags (text selection, event dragging).

## Build & Release

- **Build**: `xcodebuild -project Zman-claude.xcodeproj -scheme Zman-claude -configuration Release build`
- **Versioning**: SemVer. `MARKETING_VERSION` (user-facing, e.g. `1.1`) and `CURRENT_PROJECT_VERSION` (build number) in `project.pbxproj`. Bump both in Debug and Release configs.
- **Changelog**: `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com). Use `[Unreleased]` for in-progress work, move to `[X.Y.Z] - YYYY-MM-DD` on release.
- **Tags**: `vX.Y.Z` on the version bump commit (e.g. `v1.1.0`).
- **Distribution**: Source-only (build from source). No binary releases — the app is not notarized, so downloaded binaries get blocked by Gatekeeper.
- **Do not attach binary artifacts to GitHub releases**: Without notarization, macOS quarantines downloaded `.app` bundles and refuses to open them.
- **Sandbox**: `ENABLE_APP_SANDBOX = NO`. CGWindowList API requires non-sandboxed app. No Screen Recording permission prompt — works silently for non-sandboxed apps.

## Additional Notes

- TeamTimeZoneManager is a struct with only static methods—could be enum or namespace instead.
- **Timer polling rationale**: Calendar.app doesn't reliably post notifications when timezone preferences change in com.apple.iCal UserDefaults suite. Primary detection uses UserDefaults.didChangeNotification and NSWorkspace.didActivateApplicationNotification, with an adaptive safety-net timer (1s when Calendar is frontmost — where timezone changes happen — 5s otherwise). Position tracking idle ticks also re-check mismatch for immediate overlay removal.
- **Position tracking strategy**: Adaptive two-speed polling — 1s idle to detect movement start, 0.15s while moving to detect stop. Overlay fades out on movement, fades in at final position. CGWindowList with cached window ID for single-window queries. Global mouse monitor detects `leftMouseDragged` in Calendar's draggable area (top 78pt) for instant fade-out without waiting for the 1s idle poll. If mouse monitor triggers but window didn't actually move (false trigger), settle logic fades overlay back in after ~300ms.
- **Visibility strategy**: Overlay shows when Calendar window is on-screen AND unobstructed — not just when Calendar is the frontmost app. `isCalendarWindowOnScreen()` checks CGWindowList with `.optionOnScreenOnly` (excludes minimized, other-Space, hidden windows). `isCalendarWindowOccluded()` uses `.optionOnScreenAboveWindow` to get windows above Calendar in z-order and checks geometric intersection. Filtered out: own overlay (by window number), Calendar's own popups/sheets (by PID), and non-layer-0 system UI. All CG frames use top-left origin coordinates for consistent comparison.
- No error handling for CGWindowList failures—overlay silently fails if screen recording permission unavailable.
- App stays running when window closed (AppDelegate prevents termination)—typical menu bar app pattern.
