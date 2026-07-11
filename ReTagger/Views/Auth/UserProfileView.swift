//
//  UserProfileView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @State private var isLoadingProfile = false
    @State private var loadError: String?
    @State private var isResendingVerification = false
    @State private var verificationMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showStore = false
    @ObservedObject var storeService: StoreKitService
    
    var body: some View {
        VStack(spacing: 20) {
            if let user = authService.currentUser {
                profileContent(for: user)
            } else if isLoadingProfile {
                ProgressView(localizationManager.string("auth.loading.profile"))
            } else if let loadError {
                VStack(spacing: 10) {
                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                    Button(localizationManager.string("auth.retry")) {
                        loadProfile(force: true)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView(localizationManager.string("auth.loading.profile"))
            }
        }
        .padding()
        .alert(localizationManager.string("auth.delete_account_confirm"), isPresented: $showDeleteConfirmation) {
            Button(localizationManager.string("auth.cancel"), role: .cancel) { }
            Button(localizationManager.string("auth.delete_account.button"), role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text(localizationManager.string("auth.delete_account_warning"))
        }
        .onAppear {
            loadProfile()
        }
        .onChange(of: authService.currentUser?.id) { _ in
            if authService.currentUser != nil {
                isLoadingProfile = false
                loadError = nil
            }
        }
    }
    
    @ViewBuilder
    private func profileContent(for user: UserResponse) -> some View {
        // 邮箱验证警告横幅
        if user.isEmailVerified == false {
            EmailVerificationBanner(
                email: user.email,
                isResending: isResendingVerification,
                onResend: resendVerificationEmail
            )
        }
        
        if let verificationMessage {
            Text(verificationMessage)
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal)
        }
        
        HStack(spacing: 15) {
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(user.displayName ?? user.username)
                        .font(.headline)
                    
                    if user.isEmailVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .help(localizationManager.string("auth.email_verified"))
                    }
                }
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        
        // 积分余额与购买入口
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizationManager.string("profile.remaining_credits"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(authService.balance ?? 0)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            Button(action: { showStore = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text(localizationManager.string("store.buy_credits"))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .popover(isPresented: $showStore, arrowEdge: .top) {
            StoreView(
                storeService: storeService,
                authService: authService,
                isPresented: $showStore
            )
        }
        
        Divider()
        
        VStack(spacing: 20) {
            Button(action: {
                authService.logout()
            }) {
                Text(localizationManager.string("auth.logout"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            // 账户删除按钮
            Button(role: .destructive, action: {
                showDeleteConfirmation = true
            }) {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Image(systemName: "trash")
                    Text(localizationManager.string("auth.delete_account"))
                }
                .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(isDeletingAccount)
            
            if let deleteError {
                Text(deleteError)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 10)
    }
    
    private func loadProfile(force: Bool = false) {
        guard authService.currentUser == nil else { return }
        guard force || !isLoadingProfile else { return }
        
        isLoadingProfile = true
        loadError = nil
        
        Task {
            do {
                try await authService.fetchProfile()
                await MainActor.run {
                    isLoadingProfile = false
                    loadError = nil
                }
            } catch {
                await MainActor.run {
                    isLoadingProfile = false
                    loadError = localizationManager.string("profile.load_failed", arguments: error.localizedDescription as NSString)
                }
            }
        }
    }
    
    private func resendVerificationEmail() {
        guard let email = authService.currentUser?.email else { return }
        
        Task {
            await MainActor.run {
                isResendingVerification = true
                verificationMessage = nil
            }
            
            do {
                try await authService.resendEmailVerification(email: email)
                await MainActor.run {
                    verificationMessage = localizationManager.string("auth.verification.sent")
                    isResendingVerification = false
                }
            } catch {
                await MainActor.run {
                    verificationMessage = nil
                    isResendingVerification = false
                }
            }
        }
    }
    
    private func deleteAccount() {
        Task {
            await MainActor.run {
                isDeletingAccount = true
                deleteError = nil
            }
            
            do {
                try await authService.deleteAccount()
                // 删除成功后 authService.logout() 会在 deleteAccount 内部调用
            } catch {
                await MainActor.run {
                    deleteError = AuthErrorHelper.friendlyMessage(from: error, localization: localizationManager)
                    isDeletingAccount = false
                }
            }
        }
    }
}
