//
//  AboutView.swift
//  Zman-claude
//
//  Created by Pavel Lavrenko on 12/02/2026.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            
            // App Name
            Text("Zman")
                .font(.title)
                .fontWeight(.bold)
            
            // Version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Description
            Text("iCal Timezone Info")
                .font(.headline)
            
            Text("A minimalistic utility that colors iCal with overlay if it differs from remote team's timezone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Developer Info
            VStack(spacing: 8) {
                Text("Developed by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Pavel Lavrenko")
                    .font(.headline)
                
                Link("pavel@lavrenko.info", destination: URL(string: "mailto:pavel@lavrenko.info")!)
                    .font(.subheadline)
            }
            
            // Copyright
            Text("© 2026 Pavel Lavrenko")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 350, height: 450)
    }
}

#Preview {
    AboutView()
}
