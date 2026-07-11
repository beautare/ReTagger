//
//  ForgotPasswordView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @Binding var activeView: AuthView.AuthState
    @ObservedObject var uiState: AuthUIState
    
    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localizationManager.string("auth.title.forgot_password"))
                .font(.title)
                .fontWeight(.bold)
            
            Text(localizationManager.string("auth.reset_hint"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let message = message {
                Text(message)
                    .foregroundColor(isError ? .red : .green)
                    .font(.caption)
            }
            
            TextField(localizationManager.string("auth.email"), text: $uiState.forgotPasswordEmail)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.username)
            
            Button(action: sendResetLink) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {

                    Text(localizationManager.string("auth.send_reset_link"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(uiState.forgotPasswordEmail.isEmpty || isLoading)
            
            Button(localizationManager.string("auth.back_to_login")) {
                activeView = .login
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding()
    }
    
    private func sendResetLink() {
        Task {
            await MainActor.run {
                isLoading = true
                message = nil
                isError = false
            }
            do {
                try await authService.forgotPassword(email: uiState.forgotPasswordEmail)
                await MainActor.run {
                    message = localizationManager.string("auth.reset_success")
                    isError = false
                    uiState.clearForgotPasswordEmail()
                }
            } catch {
                await MainActor.run {
                    message = AuthErrorHelper.friendlyMessage(from: error, localization: localizationManager)
                    isError = true
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
