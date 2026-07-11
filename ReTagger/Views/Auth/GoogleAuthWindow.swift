
import SwiftUI
import AppKit

// MARK: - Window Management
class AuthWindowManager: NSObject {
    static let shared = AuthWindowManager()
    private var authWindow: NSWindow?
    
    @MainActor
    func showAuthWindow(url: URL, localization: LocalizationManager, onComplete: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        // Close existing window if any
        authWindow?.close()
        
        // Create the content view（独立窗口需显式注入语言环境）
        let contentView = GoogleAuthSheetView(url: url) { [weak self] code in
            onComplete(code)
            self?.closeWindow()
        } onCancel: { [weak self] in
            onCancel()
            self?.closeWindow()
        }
        .environmentObject(localization)
        
        // Host in a new window
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        
        window.contentViewController = hostingController
        window.title = localization.string("auth.google_login_title")
        window.center()
        window.isReleasedWhenClosed = false
        
        self.authWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func closeWindow() {
        authWindow?.close()
        authWindow = nil
    }
}

struct GoogleAuthSheetView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    let url: URL
    let onComplete: (String) -> Void
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
            
            OAuthWebView(url: url) { code in
                onComplete(code)
            }
        }
        .frame(width: 500, height: 650)
    }
}
