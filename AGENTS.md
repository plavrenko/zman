# AGENTS.md

AI coding assistant context for Zman project.

## Overview

macOS utility that displays an orange overlay on Calendar.app when the app's timezone differs from a configured team timezone. SwiftUI windowed app with AppKit overlay management. Runs in background after window closes. Deployment target: macOS26

## Architecture

- **Pattern**: MVVM-like with ObservableObject managers
- **Layer structure**:
  - UI Layer: SwiftUI views (ContentView, AboutView, OverlayView)
  - Manager Layer: CalendarOverlayManager, TeamTimeZoneManager (struct with static methods), CalendarTimeZoneService
  - System Integration: AppKit for window management, Accessibility API for Calendar.app window tracking
- **Data flow**: UserDefaults (both app and com.apple.iCal suite) → Managers → SwiftUI @Published properties → UI

## Tech Stack

- **Swift**: Latest
- **UI Framework**: SwiftUI (primary) + AppKit (overlay windows, workspace monitoring)
- **Key Dependencies**:
  - `AppKit`: Window management, NSWorkspace monitoring, Accessibility API
  - `SwiftUI`: Primary UI, NSHostingView for embedding in NSWindow
  - `Combine`: Publisher/subscriber pattern for ObservableObject
  - `Foundation`: UserDefaults, Timer, DateFormatter
- **No external packages**: All dependencies are system frameworks

## Module Map

- **Single target**: Zman-claude (app)
- **Source files**:
  - `Zman_claudeApp.swift`: @main entry point, AppDelegate, command menu setup
  - `ContentView.swift`: Main settings window, team timezone picker
  - `CalendarOverlayManager.swift`: Floating window overlay management, Calendar.app tracking
  - `CalendarTimeZoneService.swift`: Reads Calendar.app UserDefaults, @MainActor ObservableObject
  - `TeamTimeZoneManager.swift`: Struct with static methods for team timezone storage/comparison
  - `AboutView.swift`: About panel (not currently shown - standard panel used instead)
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
- ObservableObject for stateful managers
- @StateObject for manager ownership
- @AppStorage for UserDefaults bindings
- Timer-based polling (0.1-2s intervals) for external state monitoring
- UserDefaults suite access for reading Calendar.app preferences
- Accessibility API (AXUIElement) for window frame tracking
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
- Set<AnyCancellable> for Combine subscriptions

## Do Not

- **Do not use EventKit**: Despite README mention, no EventKit access in code. App reads Calendar.app UserDefaults, not calendar events.
- **Do not modify Accessibility permissions handling**: Code uses AXUIElement directly without permission checks—maintain this pattern.
- **Do not change overlay opacity/color**: Fixed at `Color.orange.opacity(0.15)` - this is the core UX.
- **Do not replace Timer-based polling**: Calendar.app does not post notifications for timezone preference changes. Polling is the only way to detect these changes. UserDefaults.didChangeNotification fires for our own defaults but not for com.apple.iCal suite changes.
- **Do not access calendar events**: This is a timezone indicator, not an event reader.
- **Do not change bundle ID references**: `com.apple.iCal` is hardcoded for Calendar.app detection.
- **Do not remove AppDelegate**: Prevents app quit on window close—essential for menu bar utility behavior.
- **Do not show windows on all spaces**: Overlay uses `.canJoinAllSpaces` but main window does not.
- **Do not make overlay clickable**: `.ignoresMouseEvents = true` is critical—overlay must be non-intrusive.
- **Do not use the AboutView**: Standard about panel is shown via `orderFrontStandardAboutPanel` instead.
- **Do not change UserDefaults suite names**: `com.apple.iCal` suite is required for reading Calendar settings.
- **Do not simplify coordinate conversion**: Screen coordinate conversion (bottom-left → top-left origin) is necessary for Accessibility API.

## Additional Notes

- App initializes CalendarOverlayManager twice (once in @StateObject, once in init)—⚠️ potential issue to discuss.
- TeamTimeZoneManager is a struct with only static methods—could be enum or namespace instead.
- **Timer polling rationale**: Calendar.app doesn't post notifications when timezone preferences change in com.apple.iCal UserDefaults suite, making polling necessary (0.1s for overlay position, 0.5s for timezone/app state, 2s for timezone service).
- No error handling for Accessibility API failures—overlay silently fails if AX unavailable.
- App stays running when window closed (AppDelegate prevents termination)—typical menu bar app pattern.
