//
//  GoogleAuthWindow.swift
//  ReTagger
//
//  应用内 Google 授权窗口：以独立 NSWindow 承载 WKWebView 加载授权页。
//  授权完成后 Google 重定向到本地 loopback 地址，授权码由
//  GoogleOAuthLoopbackServer 接收，本窗口只负责展示与取消。
//  （macOS 上 ASWebAuthenticationSession 会把流程移交系统默认浏览器，
//  无法满足"不脱离应用"的要求，故采用 WKWebView 方案。）
//

import SwiftUI
import AppKit
import WebKit

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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
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
        NSApp.activate(ignoringOtherApps: true)
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
        VStack(spacing: 0) {
            HStack {
                Text(localizationManager.string("auth.google_login_title"))
                    .font(.headline)
                Spacer()
                Button(localizationManager.string("common.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.background)

            Divider()

            AuthWebView(url: url)
        }
        .frame(minWidth: 480, minHeight: 600)
    }
}

/// 纯展示用的 WKWebView 容器：授权码由 loopback 服务接收，无需拦截导航
private struct AuthWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url == nil {
            nsView.load(URLRequest(url: url))
        }
    }
}
