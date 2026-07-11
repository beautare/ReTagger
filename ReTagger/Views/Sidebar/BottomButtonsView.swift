//
//  BottomButtonsView.swift
//  ReTagger
//
//  Sidebar bottom buttons - improved with design system
//

import SwiftUI

/// 侧边栏底部的重置按钮
struct BottomButtonsView: View, Equatable {
    static func == (lhs: BottomButtonsView, rhs: BottomButtonsView) -> Bool {
        lhs.isAuthPresented == rhs.isAuthPresented &&
        lhs.authService === rhs.authService &&
        lhs.authUIState === rhs.authUIState &&
        lhs.storeService === rhs.storeService &&
        lhs.sidebarSizeClass == rhs.sidebarSizeClass
    }

    @EnvironmentObject var localizationManager: LocalizationManager
    @Binding var isAuthPresented: Bool
    @ObservedObject var authService: AuthService
    @ObservedObject var authUIState: AuthUIState
    @ObservedObject var storeService: StoreKitService
    /// 侧边栏尺寸等级，按阈值驱动视图布局
    var sidebarSizeClass: DesignSystem.Layout.SidebarSizeClass = .regular

    /// 是否处于迷你列模式
    private var isMini: Bool {
        sidebarSizeClass == .mini
    }

    /// 是否处于紧凑模式（标准模式下宽度较窄）
    private var isCompact: Bool {
        sidebarSizeClass == .compact
    }

    init(
        isAuthPresented: Binding<Bool>,
        authService: AuthService,
        authUIState: AuthUIState,
        storeService: StoreKitService,
        sidebarSizeClass: DesignSystem.Layout.SidebarSizeClass = .regular
    ) {
        self._isAuthPresented = isAuthPresented
        self.authService = authService
        self.authUIState = authUIState
        self.storeService = storeService
        self.sidebarSizeClass = sidebarSizeClass
    }

    var body: some View {
        Group {
            if isMini {
                miniLayout
            } else {
                standardLayout
            }
        }
        .animation(DesignSystem.Animation.fast, value: isMini)
        .animation(DesignSystem.Animation.fast, value: isCompact)
    }

    // MARK: - 迷你模式：仅图标

    private var miniLayout: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Divider()

            Button(action: { isAuthPresented.toggle() }) {
                Image(systemName: authService.isAuthenticated ? "person.fill" : "person")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .help(authService.isAuthenticated ?
                (authService.currentUser?.displayName ?? localizationManager.string("sidebar.my_account")) :
                localizationManager.string("auth.sign_in_register")
            )
            .popover(
                isPresented: $isAuthPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                AuthView(authService: authService, authUIState: authUIState, storeService: storeService)
            }


        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.xs)
    }

    // MARK: - 标准模式（含紧凑变体）

    private var standardLayout: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Divider()
            
            // 剩余点数展示（紧凑模式下隐藏，避免内容过于拥挤）
            if !isCompact, let balance = authService.balance {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text(localizationManager.string("sidebar.remaining_points", arguments: balance))
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .help(localizationManager.string("sidebar.points_tooltip"))
            }
            
            Button(action: { isAuthPresented.toggle() }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: authService.isAuthenticated ? "person.fill" : "person")
                    if !isCompact {
                        Text(authService.isAuthenticated ? 
                            (authService.currentUser?.displayName ?? authService.currentUser?.username ?? localizationManager.string("sidebar.my_account")) : 
                            localizationManager.string("auth.sign_in_register")
                        )
                    }
                }

                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .buttonStyle(.bordered)
            .help(isCompact ? (authService.isAuthenticated ?
                (authService.currentUser?.displayName ?? localizationManager.string("sidebar.my_account")) :
                localizationManager.string("auth.sign_in_register")) : "")
            .popover(
                isPresented: $isAuthPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                AuthView(authService: authService, authUIState: authUIState, storeService: storeService)
            }


        }
        .padding(isCompact ? DesignSystem.Spacing.sm : DesignSystem.Spacing.md)
    }
}

#Preview {
    let authService = AuthService(deviceTokenManager: DeviceTokenManager(baseURL: "http://localhost:8009"))
    BottomButtonsView(
        isAuthPresented: .constant(false),
        authService: authService,
        authUIState: AuthUIState(),
        storeService: StoreKitService(authService: authService, networkService: nil)
    )
    .frame(width: 280)
}
