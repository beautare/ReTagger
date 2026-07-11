//
//  RegisterView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @Binding var activeView: AuthView.AuthState
    @ObservedObject var uiState: AuthUIState
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRegistrationSuccess = false
    
    private let minimumPasswordLength = 8
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localizationManager.string("auth.title.register"))
                .font(.title)
                .fontWeight(.bold)
            
            if let errorMessage = errorMessage {
                AuthErrorBannerView(message: errorMessage)
            }
            
            VStack(spacing: 12) {
                TextField(localizationManager.string("auth.email"), text: $uiState.registerEmail)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.username)
                
                TextField(localizationManager.string("auth.username.optional"), text: $uiState.registerUsername)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    ASCIISecureField(
                        placeholder: localizationManager.string("auth.password"),
                        text: $uiState.registerPassword
                    )
                    
                    if !uiState.registerPassword.isEmpty && uiState.registerPassword.count < minimumPasswordLength {
                        Text(localizationManager.string("auth.password.min_length", arguments: minimumPasswordLength))
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                ASCIISecureField(
                    placeholder: localizationManager.string("auth.confirm_password"),
                    text: $uiState.registerConfirmPassword
                )
            }
            
            // 服务条款同意
            policyAgreementView
            
            Button(action: register) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(localizationManager.string("auth.register.button"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || isLoading)
            
            Button(localizationManager.string("auth.have_account")) {
                activeView = .login
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding()
        .sheet(isPresented: $showRegistrationSuccess) {
            RegistrationSuccessAlert(
                email: uiState.registerEmail,
                onDismiss: {
                    showRegistrationSuccess = false
                    activeView = .login
                }
            )
        }
    }
    
    private var policyAgreementView: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $uiState.registerHasAgreedToPolicy)
                .toggleStyle(.checkbox)
                .labelsHidden()
            
            VStack(alignment: .leading, spacing: 2) {

                Text(localizationManager.string("auth.policy.agree"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Link(localizationManager.string("auth.policy.terms"), destination: URL(string: "https://retagger.vip/terms")!)
                        .font(.caption)
                    
                    Text("&")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link(localizationManager.string("auth.policy.privacy"), destination: URL(string: "https://retagger.vip/privacy")!)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var isFormValid: Bool {
        !uiState.registerEmail.isEmpty
        && !uiState.registerPassword.isEmpty
        && !uiState.registerConfirmPassword.isEmpty
        && uiState.registerPassword.count >= minimumPasswordLength
        && uiState.registerHasAgreedToPolicy
    }
    
    private func register() {
        // 验证密码一致性
        guard uiState.registerPassword == uiState.registerConfirmPassword else {
            errorMessage = localizationManager.string("auth.error.password_mismatch")
            return
        }
        
        // 验证密码长度
        guard uiState.registerPassword.count >= minimumPasswordLength else {
            errorMessage = localizationManager.string("auth.password.min_length", arguments: minimumPasswordLength)
            return
        }
        
        // 验证服务条款同意
        guard uiState.registerHasAgreedToPolicy else {
            errorMessage = localizationManager.string("auth.error.policy_required")
            return
        }

        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            do {
                let request = RegisterRequest(
                    email: uiState.registerEmail,
                    password: uiState.registerPassword,
                    username: uiState.registerUsername.isEmpty ? nil : uiState.registerUsername,
                    displayName: nil,
                    registrationSource: "retagger",
                    referralCode: nil,
                    deviceFingerprint: DeviceFingerprint.collect(),
                    policyAcceptance: PolicyAcceptanceRequest.generate()
                )
                try await authService.register(request: request)
                await MainActor.run {
                    uiState.clearRegisterDraft()
                    // 显示注册成功提示
                    showRegistrationSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = AuthErrorHelper.friendlyMessage(from: error, localization: localizationManager)
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

/// 认证错误横幅视图
private struct AuthErrorBannerView: View {
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
