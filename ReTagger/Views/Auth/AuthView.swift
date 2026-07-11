//
//  AuthView.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import SwiftUI

struct AuthView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var authService: AuthService
    @ObservedObject var authUIState: AuthUIState
    @ObservedObject var storeService: StoreKitService
    @AppStorage("vip.retagger.auth.lastState") private var activeViewRawValue: String = AuthState.login.rawValue
    
    enum AuthState: String {
        case login
        case register
        case forgotPassword
    }
    
    var body: some View {
        VStack {
            if authService.isAuthenticated {
                UserProfileView(authService: authService, storeService: storeService)
            } else {
                switch activeView {
                case .login:
                    LoginView(authService: authService, activeView: activeViewBinding, uiState: authUIState)
                case .register:
                    RegisterView(authService: authService, activeView: activeViewBinding, uiState: authUIState)
                case .forgotPassword:
                    ForgotPasswordView(authService: authService, activeView: activeViewBinding, uiState: authUIState)
                }
            }
        }
        .frame(width: 350)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
    
    private var activeView: AuthState {
        AuthState(rawValue: activeViewRawValue) ?? .login
    }
    
    private var activeViewBinding: Binding<AuthState> {
        Binding(
            get: { activeView },
            set: { newValue in
                activeViewRawValue = newValue.rawValue
            }
        )
    }
}
