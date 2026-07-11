//
//  WindowAccessor.swift
//  ReTagger
//
//  提供 SwiftUI -> NSWindow 的注入渠道，便于配置窗口属性
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> AccessorHostingView {
        let view = AccessorHostingView()
        view.onWindowChange = { window in
            if let window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: AccessorHostingView, context: Context) {}

    final class AccessorHostingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
