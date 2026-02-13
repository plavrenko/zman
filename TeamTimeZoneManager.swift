//
//  TeamTimeZoneManager.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import Foundation
import SwiftUI

/// Manager for accessing and working with the team's timezone preference
struct TeamTimeZoneManager {
    
    /// Key for storing team timezone in UserDefaults
    static let teamTimeZoneKey = "teamTimeZone"
    
    /// Get the currently configured team timezone
    static var teamTimeZone: TimeZone? {
        let identifier = UserDefaults.standard.string(forKey: teamTimeZoneKey) ?? ""
        return identifier.isEmpty ? nil : TimeZone(identifier: identifier)
    }
    
    private static let iCalDefaults = UserDefaults(suiteName: "com.apple.iCal")

    /// Check if the calendar timezone matches the team timezone
    static func isCalendarTimezoneMismatch() -> Bool {
        guard let teamTZ = teamTimeZone else {
            // If no team timezone is set, no mismatch
            return false
        }

        // Get iCal's timezone from its cached UserDefaults
        guard let iCalTimeZone = iCalDefaults?.string(forKey: "lastViewsTimeZone") else {
            // If we can't read iCal's timezone, assume mismatch
            return true
        }

        // Compare iCal's timezone with team timezone
        return iCalTimeZone != teamTZ.identifier
    }
}
