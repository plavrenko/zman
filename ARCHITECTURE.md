# Architecture

This document summarizes Zman's runtime architecture and behavior flows.

## C4 - System Context

```mermaid
flowchart LR
    User[User] --> Zman[Zman App]
    Zman --> Calendar[Calendar.app]
    Zman --> UDApp[(UserDefaults: Zman)]
    Zman --> UDIcal[(UserDefaults: com.apple.iCal)]
    Zman --> Workspace[NSWorkspace Notifications]
    Zman --> CG[CGWindowList API]
```

## C4 - Container / Component View

```mermaid
flowchart TB
    subgraph App["Zman-claude (single target)"]
        AppEntry[Zman_claudeApp / AppDelegate]
        Content[ContentView]
        OverlayMgr[CalendarOverlayManager]
        TZSvc[CalendarTimeZoneService]
        TZMgr[TeamTimeZoneManager]
        OverlayView[OverlayView]
    end

    AppEntry --> OverlayMgr
    Content --> TZSvc
    Content --> TZMgr
    OverlayMgr --> TZMgr
    OverlayMgr --> OverlayView
    TZSvc --> UDIcal[(com.apple.iCal defaults)]
    TZMgr --> UDApp[(app defaults)]
    OverlayMgr --> CG[CGWindowList]
    OverlayMgr --> WS[NSWorkspace notifications]
```

## Data Flow

```mermaid
flowchart LR
    UDIcal[(com.apple.iCal)]
    UDApp[(app defaults)]
    TZMgr[TeamTimeZoneManager]
    OverlayMgr[CalendarOverlayManager]
    UI[Overlay NSWindow]

    UDIcal --> TZMgr
    UDApp --> TZMgr
    TZMgr --> OverlayMgr
    OverlayMgr --> UI
```

## Event / State Flow (Overlay Behavior)

```mermaid
stateDiagram-v2
    [*] --> Hidden

    Hidden --> Visible: mismatch + on-screen + unobstructed
    Visible --> Hidden: no mismatch / off-screen / occluded

    Visible --> FadingOut: drag move/resize detected
    FadingOut --> Moving: alpha=0, fast poll (0.15s)
    Moving --> Visible: settled, snap frame, fade in

    Visible --> FadingOut: close/dismiss/focus-leave trigger
    FadingOut --> Hidden: fast visibility refresh burst detects disappearance/occlusion
    FadingOut --> Visible: fast refresh burst retargets and visibility conditions still true
```

## Runtime Notes

- Overlay visibility condition: timezone mismatch + Calendar window on current screen/Space + not occluded by non-Calendar layer-0 windows.
- Position tracking cadence:
  - idle: 1.0s (low CPU)
  - moving: 0.15s (detect stop quickly)
- Fast response paths:
  - `leftMouseDragged` in draggable area and resize border for immediate fade-out on move/resize
  - `leftMouseDown` for traffic-light close and popup outside-click dismiss
  - `keyDown` for `Cmd+W` and `Esc` dismiss
  - focus changes via `NSWorkspace.didActivateApplicationNotification` (immediate fade + single short delayed re-check)
- Fast visibility refresh burst runs at 50ms cadence for short close/dismiss transition windows to avoid waiting for the 1s idle tick.
