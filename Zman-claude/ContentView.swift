//
//  ContentView.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var timeZoneService = CalendarTimeZoneService()
    @AppStorage("teamTimeZone") private var teamTimeZone: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.checkmark")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .font(.system(size: 60))
            
            Text("iCal Timezone Info")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Timezone Support:")
                        .fontWeight(.medium)
                    Text(timeZoneService.timeZoneSupported ? "Enabled" : "Disabled")
                        .foregroundStyle(timeZoneService.timeZoneSupported ? .green : .secondary)
                }
                
                HStack {
                    Text("Current Timezone:")
                        .fontWeight(.medium)
                    Text(timeZoneService.currentTimeZone)
                        .foregroundStyle(.blue)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Team's Timezone:")
                        .fontWeight(.medium)
                    
                    if timeZoneService.recentlyUsedTimeZones.isEmpty {
                        Text("No recently used timezones")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button("Refresh") {
                            timeZoneService.refresh()
                        }
                        .buttonStyle(.link)
                    } else {
                        Picker("", selection: $teamTimeZone) {
                            Text("Not set")
                                .tag("")
                            
                            Divider()
                            
                            ForEach(timeZoneService.recentlyUsedTimeZones, id: \.self) { timezone in
                                HStack {
                                    Text(timezone)
                                    if let tz = TimeZone(identifier: timezone) {
                                        Text("(\(tz.abbreviation() ?? ""))")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(timezone)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if !teamTimeZone.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(teamTimeZone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            timeZoneService.startMonitoring()
        }
        .onDisappear {
            timeZoneService.stopMonitoring()
        }
    }
}

#Preview {
    ContentView()
}
