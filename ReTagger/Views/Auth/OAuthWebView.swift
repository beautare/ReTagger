//
//  OAuthWebView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI
import WebKit

struct OAuthWebView: NSViewRepresentable {
    let url: URL
    let onCodeReceived: (String) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url == nil {
            let request = URLRequest(url: url)
            nsView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OAuthWebView
        
        init(_ parent: OAuthWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // Check if this is the native OAuth callback URL
                // Format: com.googleusercontent.apps.{client_prefix}:/oauth2redirect?code=xxx
                let urlString = url.absoluteString
                
                if urlString.hasPrefix("com.googleusercontent.apps.") && urlString.contains("oauth2redirect") {
                    // Extract the code from query parameters
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                        parent.onCodeReceived(code)
                        decisionHandler(.cancel)
                        return
                    }
                }
                
                // Also support legacy web callback path for backward compatibility
                if url.path.hasSuffix("/auth/google/callback") {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                        parent.onCodeReceived(code)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }
    }
}
