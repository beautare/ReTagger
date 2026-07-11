//
//  RedeemCodeView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI

struct RedeemCodeView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    @State private var code = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false
    @State private var hasSubmitted = false  // 防止重复提交的标志

    var body: some View {
        VStack(spacing: 20) {
            Text(localizationManager.string("redeem.title"))
                .font(.headline)

            if let message = message {
                Text(message)
                    .foregroundColor(isError ? .red : .green)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            TextField(localizationManager.string("redeem.code_placeholder"), text: $code)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)
                .onSubmit {
                    redeem()
                }

            HStack {
                Button(localizationManager.string("common.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localizationManager.string("redeem.activate")) {
                    redeem()
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty || isLoading || hasSubmitted)
                // 移除 keyboardShortcut 以避免双重触发，已通过 TextField.onSubmit 处理回车键
            }
            
            // 购买兑换码链接
            // 移除不合规的购买链接
            // Link(destination: URL(string: "https://item.taobao.com/item.htm?id=994432052250")!) {
            //     Text("购买兑换码")
            //         .font(.caption)
            //         .foregroundColor(.blue)
            // }
            // .help("点击跳转到淘宝购买兑换码")
        }
        .padding()
        .frame(width: 300)
    }
    
    private func redeem() {
        // 防止重复提交 - 使用双重检查
        guard !isLoading, !hasSubmitted else { return }
        
        isLoading = true
        hasSubmitted = true  // 一旦开始提交，永久禁用
        message = nil
        isError = false
        
        let codeToRedeem = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                let response = try await authService.redeemVoucher(code: codeToRedeem)
                await MainActor.run {
                    if let value = response.value {
                        message = localizationManager.string("redeem.success_with_value", arguments: value, response.balance)
                    } else {
                        message = localizationManager.string("redeem.success", arguments: response.balance)
                    }
                    isError = false
                    code = "" // 清空兑换码
                }
                
                // Close after delay
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    message = AuthErrorHelper.friendlyMessage(from: error, localization: localizationManager)
                    isError = true
                    isLoading = false
                    hasSubmitted = false  // 失败时允许重试
                }
            }
        }
    }
}
