# Zman

A minimalistic macOS utility that colors the Calendar app with an overlay indicator when your Calendar app timezone differs from your remote team's timezone.

## Features

- Detects timezone differences between Calendar.app's viewing timezone and your team's timezone
- Provides a visual overlay on the macOS Calendar app when timezones differ

## Requirements

- macOS (built with SwiftUI)
- Accessibility permissions (to detect Calendar.app windows)

## Installation

1. Clone this repository
2. Open `Zman-claude.xcodeproj` in Xcode
3. Build and run the project
4. Grant Accessibility permissions when prompted (needed to detect Calendar.app)

## How It Works

Zman reads Calendar.app's current viewing timezone setting (the timezone you've set for viewing your calendar) and compares it with your configured team timezone. When these differ, it displays an orange overlay on Calendar.app to remind you that you're viewing your calendar in a different timezone than your team operates in.

## Configuration

The app allows you to:
- Set your team's timezone

## Privacy

Zman only reads Calendar.app's timezone preferences from your system. It does not access your calendar events or any personal data. No data is sent to external servers or stored outside of your Mac.

## Development

Built with:
- SwiftUI
- AppKit (macOS integration, window overlays, Accessibility API)
- UserDefaults (reading Calendar.app preferences)

## Author

Pavel Lavrenko
- Email: pavel@lavrenko.info

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

Copyright © 2026 Pavel Lavrenko

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
