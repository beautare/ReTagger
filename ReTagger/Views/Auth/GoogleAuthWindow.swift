//
//  GoogleAuthWindow.swift
//  ReTagger
//
//  Google 在系统浏览器中授权；此窗口提供等待与取消操作。
//  授权码由本地 loopback 服务接收。
//

import SwiftUI
import AppKit

final class AuthWindowManager: NSObject {
    static let shared = AuthWindowManager()

    private var authWindow: NSWindow?
    private var onCancel: (() -> Void)?

    /// 打开授权窗口；用户点"取消"或直接关窗时回调 onCancel
    @MainActor
    func showAuthWindow(url: URL, localization: LocalizationManager, onCancel: @escaping () -> Void) {
        close()
        self.onCancel = onCancel

        let contentView = GoogleAuthSheetView(url: url) { [weak self] in
            self?.cancel()
        }
        .environmentObject(localization)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = localization.string("auth.google_login_title")
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        authWindow = window
        window.makeKeyAndOrderFront(nil)
        NSWorkspace.shared.open(url)
    }

    /// 授权流程结束（成功或失败）后收起窗口，不触发 onCancel
    @MainActor
    func close() {
        onCancel = nil
        authWindow?.delegate = nil
        authWindow?.close()
        authWindow = nil
    }

    @MainActor
    private func cancel() {
        let handler = onCancel
        close()
        handler?()
    }
}

extension AuthWindowManager: NSWindowDelegate {
    /// 用户点了窗口红色关闭按钮（程序内关闭走 close()，已先摘除 delegate）
    func windowWillClose(_ notification: Notification) {
        let handler = onCancel
        onCancel = nil
        authWindow = nil
        handler?()
    }
}

private struct GoogleAuthSheetView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    let url: URL
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text(localizationManager.string("auth.google_browser_hint"))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button(localizationManager.string("auth.google_open_browser")) {
                    NSWorkspace.shared.open(url)
                }
                Button(localizationManager.string("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 180)
    }
}
