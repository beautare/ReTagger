//
//  AboutView.swift
//  ReTagger
//
//  Created by Antigravity on 2026/01/08.
//

import SwiftUI

struct AboutView: View {
    private let appVersion = AppConfiguration.InfoPlist.appVersion
    private let buildNumber = AppConfiguration.InfoPlist.buildNumber
    
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 128, height: 128)
            
            VStack(spacing: 8) {
                Text("ReTagger")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 12) {
                Text("Support")
                    .font(.headline)
                
                Link("support@retagger.vip", destination: URL(string: "mailto:support@retagger.vip")!)
                    .foregroundColor(.blue)
                
                Text("© 2026 ReTagger. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
