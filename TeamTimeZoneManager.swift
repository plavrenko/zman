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
    
    /// Get the team timezone identifier string
    static var teamTimeZoneIdentifier: String {
        return UserDefaults.standard.string(forKey: teamTimeZoneKey) ?? ""
    }
    
    /// Set the team timezone
    static func setTeamTimeZone(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: teamTimeZoneKey)
    }
    
    /// Clear the team timezone
    static func clearTeamTimeZone() {
        UserDefaults.standard.removeObject(forKey: teamTimeZoneKey)
    }
    
    /// Format a date in the team's timezone
    static func formatDate(_ date: Date, style: DateFormatter.Style = .medium) -> String {
        guard let tz = teamTimeZone else {
            return "Team timezone not set"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = style
        formatter.timeZone = tz
        return formatter.string(from: date)
    }
    
    /// Get the current time in the team's timezone
    static func currentTimeInTeamTimeZone() -> String {
        guard let tz = teamTimeZone else {
            return "Team timezone not set"
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.timeZone = tz
        return formatter.string(from: Date())
    }
    
    /// Calculate time difference between local and team timezone
    static func timeDifferenceFromLocal() -> String {
        guard let teamTZ = teamTimeZone else {
            return "N/A"
        }
        
        let localOffset = TimeZone.current.secondsFromGMT()
        let teamOffset = teamTZ.secondsFromGMT()
        let differenceSeconds = teamOffset - localOffset
        let differenceHours = differenceSeconds / 3600
        
        if differenceHours == 0 {
            return "Same as local"
        } else if differenceHours > 0 {
            return "+\(differenceHours) hours"
        } else {
            return "\(differenceHours) hours"
        }
    }
    
    /// Check if the calendar timezone matches the team timezone
    static func isCalendarTimezoneMismatch() -> Bool {
        guard let teamTZ = teamTimeZone else {
            // If no team timezone is set, no mismatch
            return false
        }
        
        // Get iCal's timezone from its UserDefaults
        guard let iCalDefaults = UserDefaults(suiteName: "com.apple.iCal"),
              let iCalTimeZone = iCalDefaults.string(forKey: "lastViewsTimeZone") else {
            // If we can't read iCal's timezone, assume mismatch
            return true
        }
        
        // Compare iCal's timezone with team timezone
        return iCalTimeZone != teamTZ.identifier
    }
}
