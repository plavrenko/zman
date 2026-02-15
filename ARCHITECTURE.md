# Architecture

## C4 Context

Zman's external dependencies — what crosses process and system boundaries.

```mermaid
flowchart TD
    user["👤 User"]
    zman["🟧 Zman<br/>Overlay utility"]
    calendar["📅 Calendar.app<br/>macOS Calendar"]
    macos["🖥️ macOS APIs<br/>CGWindowList · NSWorkspace · NSEvent"]

    user -- "changes viewing timezone" --> calendar
    zman -- "reads UserDefaults<br/>(com.apple.iCal suite)" --> calendar
    zman -- "queries windows, listens<br/>for notifications, monitors mouse" --> macos
```

## C4 Component

Internal structure — how the 5 source files relate to each other and to system APIs.

```mermaid
flowchart TD
    subgraph app["Zman-claude.app"]
        appEntry["Zman_claudeApp<br/><i>SwiftUI @main</i>"]
        delegate["AppDelegate<br/><i>NSApplicationDelegate</i>"]
        overlay["CalendarOverlayManager<br/><i>NSObject</i><br/>Visibility · overlay window<br/>position tracking · mouse monitor"]
        tzService["CalendarTimeZoneService<br/><i>ObservableObject</i><br/>Reads iCal prefs → UI"]
        tzManager["TeamTimeZoneManager<br/><i>struct (static)</i><br/>Mismatch comparison"]
        contentView["ContentView<br/><i>SwiftUI View</i><br/>Settings window"]
        overlayView["OverlayView<br/><i>SwiftUI View</i><br/>Orange tint"]
    end

    icalDefaults[("com.apple.iCal<br/>UserDefaults")]
    appDefaults[("UserDefaults.standard<br/><i>teamTimeZone</i>")]
    cgWindowList["CGWindowList API"]
    nsWorkspace["NSWorkspace<br/>notifications"]
    nsEvent["NSEvent<br/>mouse monitor"]

    appEntry -- "adaptor" --> delegate
    delegate -- "owns" --> overlay
    appEntry -- "WindowGroup" --> contentView
    contentView -- "@StateObject" --> tzService
    contentView -- "@AppStorage" --> appDefaults
    overlay -- "isCalendarTimezoneMismatch()" --> tzManager
    overlay -- "NSHostingView" --> overlayView
    overlay --> cgWindowList
    overlay --> nsWorkspace
    overlay --> nsEvent
    tzService --> icalDefaults
    tzManager --> icalDefaults
    tzManager --> appDefaults
```

## Data Flow

How timezone data moves through the system — from Calendar.app's preferences to the overlay show/hide decision.

```mermaid
flowchart LR
    subgraph "Calendar.app (separate process)"
        A[User changes timezone] --> B["com.apple.iCal<br/>UserDefaults<br/><i>lastViewsTimeZone</i>"]
    end

    subgraph "Zman"
        B -- "cross-process read" --> C["TeamTimeZoneManager<br/>.isCalendarTimezoneMismatch()"]
        D["UserDefaults.standard<br/><i>teamTimeZone</i>"] --> C
        C -- "true → mismatch" --> E{updateOverlay}
        C -- "false → match" --> F[hideOverlay]

        E -- "on-screen?" --> G["isCalendarWindowOnScreen()<br/><i>CGWindowList .optionOnScreenOnly</i>"]
        G -- "yes" --> H["isCalendarWindowOccluded()<br/><i>CGWindowList .optionOnScreenAboveWindow</i>"]
        G -- "no" --> F
        H -- "not occluded" --> I[showOverlay]
        H -- "occluded" --> F
    end

    subgraph "UI (ContentView)"
        B -- "cross-process read" --> J["CalendarTimeZoneService<br/>@Published currentTimeZone"]
        D <-- "@AppStorage" --> K["Timezone Picker"]
        J --> K
    end
```

## Event & State Flow

What triggers overlay updates, and the position tracking state machine.

### Overlay Lifecycle

A typical session — from Calendar launch through drag to Calendar quit:

```mermaid
sequenceDiagram
    participant WS as NSWorkspace
    participant COM as CalendarOverlayManager
    participant TZM as TeamTimeZoneManager
    participant CG as CGWindowList API
    participant OW as Overlay Window
    participant ME as NSEvent (mouse)

    Note over WS: Calendar.app launches
    WS->>COM: didActivateApplication
    COM->>TZM: isCalendarTimezoneMismatch()?
    TZM-->>COM: true
    COM->>CG: isCalendarWindowOnScreen()?
    CG-->>COM: true (caches frame + window ID)
    COM->>CG: isCalendarWindowOccluded()?
    CG-->>COM: false
    COM->>OW: showOverlay()
    Note over OW: Overlay visible (alpha 1)
    COM->>COM: start position timer (1s)
    COM->>ME: start mouse monitor

    Note over WS: User changes timezone in Calendar
    WS->>COM: UserDefaults didChange
    COM->>TZM: isCalendarTimezoneMismatch()?
    TZM-->>COM: false (match now)
    COM->>OW: hideOverlay()

    Note over WS: User changes back / different TZ
    COM->>COM: safety-net timer tick (1s)
    COM->>TZM: isCalendarTimezoneMismatch()?
    TZM-->>COM: true
    COM->>CG: isCalendarWindowOnScreen()?
    CG-->>COM: true
    COM->>CG: isCalendarWindowOccluded()?
    CG-->>COM: false
    COM->>OW: showOverlay()

    Note over ME: User drags Calendar title bar
    ME->>COM: leftMouseDragged in top 78pt
    COM->>OW: fade out (0.1s)
    COM->>COM: switch to fast poll (150ms)
    Note over COM: checkPosition() detects settle
    COM->>OW: fade in (0.2s) at new position
    COM->>COM: switch to idle poll (1s)

    Note over WS: Another window covers Calendar
    COM->>COM: idle tick
    COM->>CG: isCalendarWindowOccluded()?
    CG-->>COM: true (window intersects)
    COM->>OW: hideOverlay()

    Note over WS: Calendar.app quits
    WS->>COM: didTerminateApplication
    COM->>OW: hideOverlay()
    COM->>COM: clear cached PID
```

### Position Tracking State Machine

Two states (idle / moving), driven by a timer that adapts its interval:

```mermaid
stateDiagram-v2
    [*] --> Idle: showOverlay()

    Idle --> Moving_pollDetected: checkPosition() detects frame change
    Idle --> Moving_mouseDetected: leftMouseDragged in toolbar area

    Moving_pollDetected --> Moving_pollDetected: frame still changing (reset settle)
    Moving_mouseDetected --> Moving_mouseDetected: frame still changing (reset settle)

    Moving_pollDetected --> Idle: settleCount reaches 2 (frame stable ~300ms)
    Moving_mouseDetected --> Idle: settleCount reaches 2 (frame stable ~300ms)

    Idle --> [*]: hideOverlay()
    Moving_pollDetected --> [*]: hideOverlay()
    Moving_mouseDetected --> [*]: hideOverlay()

    state Idle {
        [*] --> polling_1s
        polling_1s: Timer 1s — overlay visible (alpha 1)
        polling_1s: Re-checks mismatch + occlusion each tick
    }

    state Moving_pollDetected {
        [*] --> polling_150ms_a
        polling_150ms_a: Timer 150ms — overlay faded out (alpha 0)
        polling_150ms_a: Fade-out 0.15s on entry
    }

    state Moving_mouseDetected {
        [*] --> polling_150ms_b
        polling_150ms_b: Timer 150ms — overlay faded out (alpha 0)
        polling_150ms_b: Fade-out 0.1s on entry (faster — user expects instant)
    }
```
