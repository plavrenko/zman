# Changelog

All notable changes to Zman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Reduced position tracking timer from 0.1s to 1.0s (was 30 Accessibility API calls/sec, now 3)
- Reduced main monitoring timer from 0.5s to 5.0s safety-net (notifications are primary trigger)
- Replaced CalendarTimeZoneService 2s polling timer with notification-based updates
- Cached UserDefaults(suiteName:) in TeamTimeZoneManager instead of re-creating per call
- Added guard against position timer leak and duplicate notification observers
- Removed documentation files from app bundle resources

## [1.0.0] - 2026-02-12

### Added
- Initial public release

---

## Release Notes

### Version 1.0.0
First public release of Zman, a minimalistic utility that colors iCal with overlay if it differs from remote team's timezone.
