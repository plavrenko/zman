//
//  CalendarTimeZoneService.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import Foundation
import Combine

/// Service for monitoring and reading the Calendar app's timezone settings
@MainActor
class CalendarTimeZoneService: ObservableObject {
    @Published var currentTimeZone: String = "Not set"
    @Published var timeZoneSupported: Bool = false
    @Published var recentlyUsedTimeZones: [String] = []
    
    private let iCalDefaults: UserDefaults

    init() {
        self.iCalDefaults = UserDefaults(suiteName: "com.apple.iCal") ?? .standard
        loadTimeZone()
        loadRecentlyUsedTimeZones()
    }

    /// Start monitoring for timezone changes via notifications
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadTimeZone()
            }
        }
    }

    /// Stop monitoring for timezone changes
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Manually refresh the timezone
    func refresh() {
        loadTimeZone()
        loadRecentlyUsedTimeZones()
    }
    
    private func loadTimeZone() {
        // Read the current iCal window timezone
        if let timezone = iCalDefaults.string(forKey: "lastViewsTimeZone") {
            currentTimeZone = timezone
        } else {
            currentTimeZone = "Not set"
        }
        
        // Read timezone support setting
        timeZoneSupported = iCalDefaults.bool(forKey: "TimeZone support enabled")
    }
    
    /// Load the recently used timezones from iCal preferences
    private func loadRecentlyUsedTimeZones() {
        if let timezones = iCalDefaults.array(forKey: "RecentlyUsedTimeZones") as? [String] {
            recentlyUsedTimeZones = timezones
        } else {
            recentlyUsedTimeZones = []
        }
    }
}
