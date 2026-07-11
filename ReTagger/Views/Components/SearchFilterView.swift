//
//  SearchFilterView.swift
//  ReTagger
//
//  Reusable search/filter input with static active-state highlight
//

import SwiftUI

struct SearchFilterView: View {
    @Binding var text: String
    
    @EnvironmentObject var localizationManager: LocalizationManager
    
    private var isActive: Bool { !text.isEmpty }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .font(.system(size: 13, weight: .medium))
            
            TextField(localizationManager.string("search.placeholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onExitCommand {
                    // 允许按下 ESC 快速清空搜索内容
                    text = ""
                }
            
            if isActive {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        // Inner border
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActive ? Color.accentColor : Color.clear,
                    lineWidth: isActive ? 1.5 : 0
                )
        )
        // 外层辉光改为静态，避免 CPU/GPU 持续消耗
        .shadow(
            color: isActive ? Color.accentColor.opacity(0.4) : Color.clear,
            radius: isActive ? 4 : 0,
            x: 0,
            y: 0
        )
        .animation(.easeOut(duration: 0.3), value: isActive)
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchFilterView(text: .constant(""))
            .frame(width: 200)
        
        SearchFilterView(text: .constant("test"))
            .frame(width: 200)
    }
    .padding()
}
