//
//  LoginView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @Binding var activeView: AuthView.AuthState
    @ObservedObject var uiState: AuthUIState
    
    @State private var isLoggingIn = false
    @State private var isGoogleLoading = false
    @State private var errorMessage: String?
    @State private var oauthErrorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localizationManager.string("auth.title.login"))
                .font(.title)
                .fontWeight(.bold)
            
            if let errorMessage = errorMessage {
                AuthErrorBanner(message: errorMessage)
            }
            
            VStack(spacing: 12) {
                TextField(localizationManager.string("auth.email"), text: $uiState.loginEmail)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.username)
                    .disabled(isLoggingIn)
                
                ASCIISecureField(
                    placeholder: localizationManager.string("auth.password"),
                    text: $uiState.loginPassword,
                    isDisabled: isLoggingIn
                )
            }
            
            Button(action: login) {
                if isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(localizationManager.string("auth.login.button"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(uiState.loginEmail.isEmpty || uiState.loginPassword.isEmpty || isLoggingIn)
            
            // Google Login
            Button(action: startGoogleLogin) {
                HStack(spacing: 8) {
                    if isGoogleLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        GoogleLogoMark()
                            .frame(width: 18, height: 18)
                    }
                    
                    Text(isGoogleLoading ? localizationManager.string("auth.loading.google") : localizationManager.string("auth.sign_in_with_google"))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGoogleLoading || isLoggingIn)
            
            // Apple Login
            // 直发渠道（SPARKLE_ENABLED）不提供：Apple 明确不支持 Developer ID
            // 分发使用 Sign in with Apple 受限权限，直发版走邮箱 / Google 登录
            #if !SPARKLE_ENABLED
            SignInWithAppleButton(
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    handleAppleLogin(result)
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 32) // Match standard button height ~32-40
            #endif
            
            if let oauthErrorMessage {
                AuthErrorBanner(message: oauthErrorMessage)
            }
            
            HStack {
                Button(localizationManager.string("auth.forgot_password")) {
                    activeView = .forgotPassword
                }
                .buttonStyle(.link)
                .font(.caption)
                
                Spacer()
                
                Button(localizationManager.string("auth.register_new")) {
                    activeView = .register
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding()
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    private func login() {
        Task {
            await MainActor.run {
                isLoggingIn = true
                errorMessage = nil
            }
            do {
                let request = LoginRequest(email: uiState.loginEmail, password: uiState.loginPassword)
                try await authService.login(request: request)
                await MainActor.run {
                    uiState.clearLoginCredentials()
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = friendlyMessage(from: error)
                }
            }
            await MainActor.run {
                isLoggingIn = false
            }
        }
    }
    
    private func startGoogleLogin() {
        do {
            isGoogleLoading = true
            oauthErrorMessage = nil
            errorMessage = nil
            
            let url = try authService.generateGoogleAuthURL()
            AuthWindowManager.shared.showAuthWindow(url: url, localization: localizationManager) { code in
                completeGoogleLogin(code: code)
            } onCancel: {
                isGoogleLoading = false
            }
        } catch {
            oauthErrorMessage = friendlyMessage(from: error)
            isGoogleLoading = false
        }
    }
    
    #if !SPARKLE_ENABLED
    private func handleAppleLogin(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            guard let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential else {
                oauthErrorMessage = localizationManager.string("auth.apple_credential_missing")
                return
            }

            guard let authorizationCodeData = appleIDCredential.authorizationCode,
                  let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
                oauthErrorMessage = localizationManager.string("auth.authorization_code_missing")
                return
            }
            
            let givenName = appleIDCredential.fullName?.givenName
            let familyName = appleIDCredential.fullName?.familyName
            
            Task {
                await MainActor.run {
                    isLoggingIn = true
                    oauthErrorMessage = nil
                }
                do {
                    try await authService.handleAppleCallback(
                        code: authorizationCode,
                        givenName: givenName,
                        familyName: familyName
                    )
                } catch {
                    await MainActor.run {
                        oauthErrorMessage = friendlyMessage(from: error)
                    }
                }
                await MainActor.run {
                    isLoggingIn = false
                }
            }
            
        case .failure(let error):
            // Ignore user cancellation
            if let err = error as? ASAuthorizationError, err.code == .canceled {
                return
            }
            oauthErrorMessage = error.localizedDescription
        }
    }
    #endif

    private func completeGoogleLogin(code: String) {
        Task {
            await MainActor.run {
                isGoogleLoading = true
                oauthErrorMessage = nil
            }
            do {
                try await authService.handleGoogleCallback(code: code)
            } catch {
                await MainActor.run {
                    oauthErrorMessage = friendlyMessage(from: error)
                }
            }
            await MainActor.run {
                isGoogleLoading = false
            }
        }
    }
    
    private func friendlyMessage(from error: Error) -> String {
        AuthErrorHelper.friendlyMessage(from: error, localization: localizationManager)
    }
}

private struct GoogleLogoMark: View {
    var body: some View {
        Image("GoogleLogo")
            .resizable()
            .scaledToFit()
    }
}
    
    private struct AuthErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.backgroundTertiary.opacity(0.9))
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}
