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
    
    private var pollTimer: Timer?
    private let defaults: UserDefaults
    
    init() {
        self.defaults = UserDefaults(suiteName: "com.apple.iCal") ?? .standard
        loadTimeZone()
    }
    
    /// Start monitoring for timezone changes
    func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadTimeZone()
            }
        }
    }
    
    /// Stop monitoring for timezone changes
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    /// Manually refresh the timezone
    func refresh() {
        loadTimeZone()
    }
    
    private func loadTimeZone() {
        // Read the current iCal window timezone
        if let timezone = defaults.string(forKey: "lastViewsTimeZone") {
            currentTimeZone = timezone
        } else {
            currentTimeZone = "Not set"
        }
        
        // Read timezone support setting
        timeZoneSupported = defaults.bool(forKey: "TimeZone support enabled")
    }
}
