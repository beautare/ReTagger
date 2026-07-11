//
//  EmailVerificationBanner.swift
//  ReTagger
//
//  邮箱验证提示横幅组件
//

import SwiftUI

/// 邮箱验证提示横幅
struct EmailVerificationBanner: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    let email: String
    let isResending: Bool
    let onResend: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(localizationManager.string("auth.email_not_verified"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(localizationManager.string("auth.check_email_for_verification", arguments: email as NSString))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: onResend) {
                    HStack(spacing: 4) {
                        if isResending {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isResending ? localizationManager.string("auth.resending") : localizationManager.string("auth.resend_verification"))
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(isResending)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

/// 注册成功后的验证提示弹窗
struct RegistrationSuccessAlert: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    let email: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text(localizationManager.string("auth.registration_success"))
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 8) {
                Text(localizationManager.string("auth.verification_sent_to"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(email)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(localizationManager.string("auth.check_email_with_spam"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(localizationManager.string("common.got_it")) {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

#Preview("EmailVerificationBanner") {
    EmailVerificationBanner(
        email: "test@example.com",
        isResending: false,
        onResend: {}
    )
    .environmentObject(LocalizationManager(language: .simplifiedChinese))
    .padding()
}

#Preview("RegistrationSuccessAlert") {
    RegistrationSuccessAlert(
        email: "test@example.com",
        onDismiss: {}
    )
    .environmentObject(LocalizationManager(language: .simplifiedChinese))
}
