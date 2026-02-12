//
//  SettingsView.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var timeZoneService: CalendarTimeZoneService
    @AppStorage("teamTimeZone") private var teamTimeZone: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Content
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("My Team's Timezone")
                            .font(.headline)
                        
                        if timeZoneService.recentlyUsedTimeZones.isEmpty {
                            Text("No recently used timezones found in Calendar")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Picker("Select timezone:", selection: $teamTimeZone) {
                                Text("None selected")
                                    .tag("")
                                
                                Divider()
                                
                                ForEach(timeZoneService.recentlyUsedTimeZones, id: \.self) { timezone in
                                    HStack {
                                        Text(timezone)
                                        Spacer()
                                        if let tz = TimeZone(identifier: timezone) {
                                            Text(tz.abbreviation() ?? "")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                    }
                                    .tag(timezone)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        if !teamTimeZone.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Team timezone set to: \(teamTimeZone)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Team Settings")
                } footer: {
                    Text("Select a timezone from your recently used Calendar timezones to set as your team's default timezone.")
                }
                
                Section {
                    Button("Refresh Recently Used Timezones") {
                        timeZoneService.refresh()
                    }
                } header: {
                    Text("Actions")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 450, minHeight: 350)
        .onAppear {
            timeZoneService.refresh()
        }
    }
}

#Preview {
    SettingsView(timeZoneService: CalendarTimeZoneService())
}
