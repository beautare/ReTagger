//
//  AuthUIState.swift
//  ReTagger
//
//  临时存储认证表单输入，避免弹窗关闭后丢失。
//

import Foundation
import Combine

final class AuthUIState: ObservableObject {
    // 登录
    @Published var loginEmail: String = UserDefaults.standard.string(forKey: AuthStorageKeys.lastLoginEmail) ?? ""
    @Published var loginPassword: String = ""
    
    // 注册
    @Published var registerEmail: String = ""
    @Published var registerPassword: String = ""
    @Published var registerConfirmPassword: String = ""
    @Published var registerUsername: String = ""
    @Published var registerReferralCode: String = ""
    @Published var registerHasAgreedToPolicy: Bool = false
    
    // 忘记密码
    @Published var forgotPasswordEmail: String = ""
    
    func clearLoginCredentials() {
        loginPassword = ""
    }
    
    func clearRegisterDraft() {
        registerEmail = ""
        registerPassword = ""
        registerConfirmPassword = ""
        registerUsername = ""
        registerReferralCode = ""
        registerHasAgreedToPolicy = false
    }
    
    func clearForgotPasswordEmail() {
        forgotPasswordEmail = ""
    }
}
