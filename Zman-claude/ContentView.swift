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
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .padding()
            }
            
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
                
                HStack {
                    Text("Team's Timezone:")
                        .fontWeight(.medium)
                    if teamTimeZone.isEmpty {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                        Button("Set in Settings") {
                            showingSettings = true
                        }
                        .buttonStyle(.link)
                    } else {
                        Text(teamTimeZone)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
        }
        .padding()
        .sheet(isPresented: $showingSettings) {
            SettingsView(timeZoneService: timeZoneService)
        }
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
