# Zman

A minimalistic macOS utility that colors the Calendar app with an overlay indicator when your local timezone differs from your remote team's timezone.

## Features

- Detects timezone differences between your location and your team's timezone
- Provides a visual overlay on the macOS Calendar app

## Requirements

- macOS (built with SwiftUI)
- Access to Calendar (EventKit permissions required)

## Installation

1. Clone this repository
2. Open `Zman-claude.xcodeproj` in Xcode
3. Build and run the project
4. Grant Calendar access when prompted

## How It Works

Zman monitors your calendar events and compares your local timezone with your configured team timezone. When there's a difference, it displays a visual indicator to help you stay aware of the time difference during meetings and events.

## Configuration

The app allows you to:
- Set your team's timezone

## Privacy

Zman only accesses your calendar data locally on your device. No data is sent to external servers or stored outside of your Mac.

## Development

Built with:
- SwiftUI
- EventKit (Calendar access)
- AppKit (macOS integration)

## Author

Pavel Lavrenko
- Email: pavel@lavrenko.info

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

Copyright © 2026 Pavel Lavrenko

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
