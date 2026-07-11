//
//  StoreView.swift
//  ReTagger
//
//  内购商店页面，展示可购买的点数套餐
//

import SwiftUI
import StoreKit

struct StoreView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @ObservedObject var storeService: StoreKitService
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    /// 当前正在购买的商品 ID（用于只在该按钮上显示菊花）
    @State private var purchasingProductId: String?

    var body: some View {
        VStack(spacing: 16) {
            // 标题栏（含关闭按钮）
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.accentColor)
                Text(localizationManager.string("store.buy_credits"))
                    .font(.headline)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            // 当前余额
            if let balance = authService.balance {
                HStack(spacing: 4) {
                    Text(localizationManager.string("store.current_balance"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(balance)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Text(localizationManager.string("store.credits_unit"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 商品列表
            if storeService.isLoadingProducts {
                ProgressView(localizationManager.string("store.loading_products"))
                    .frame(height: 120)
            } else if storeService.products.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(localizationManager.string("store.no_products"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(localizationManager.string("common.retry")) {
                        Task { await storeService.loadProducts() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(height: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(storeService.products, id: \.id) { product in
                        productCard(product)
                    }
                }
            }

            // 错误提示
            if let error = storeService.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // 底部（仅在有未完成交易时显示同步按钮）
            if storeService.hasUnfinishedTransactions {
                Divider()

                HStack {
                    Button(localizationManager.string("store.sync_pending_orders")) {
                        Task { await storeService.restorePurchases() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help(localizationManager.string("store.sync_pending_orders_hint"))

                    Spacer()
                }
            }
        }
        .padding()
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true) // 确保内容不被裁剪
        .onAppear {
            Task { await storeService.loadProducts() }
        }
    }

    // MARK: - 商品卡片

    @ViewBuilder
    private func productCard(_ product: Product) -> some View {
        let isRecommended = product.id == "vip.retagger.credits.500"
        let isThisPurchasing = purchasingProductId == product.id
        let anyPurchasing = purchasingProductId != nil

        HStack(spacing: 12) {
            // 点数信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(product.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if isRecommended {
                        Text(localizationManager.string("store.recommended"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }

                Text(product.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 购买按钮（只有当前购买的才显示菊花）
            Button(action: {
                purchasingProductId = product.id
                Task {
                    await storeService.purchase(product)
                    purchasingProductId = nil
                }
            }) {
                if isThisPurchasing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70)
                } else {
                    Text(product.displayPrice)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 70)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(anyPurchasing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRecommended
                      ? Color.accentColor.opacity(0.06)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecommended ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
