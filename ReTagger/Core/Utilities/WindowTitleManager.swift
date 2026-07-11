//
//  WindowTitleManager.swift
//  ReTagger
//
//  提供统一入口在 AppKit 层更新窗口标题
//

import AppKit

enum WindowTitleManager {
    static func update(to title: String) {
        guard !title.isEmpty else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            if window.title != title {
                window.title = title
            }
        }
    }
}
