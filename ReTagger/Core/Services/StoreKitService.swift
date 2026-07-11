//
//  StoreKitService.swift
//  ReTagger
//
//  StoreKit 2 内购服务，管理商品加载、购买流程和交易验证
//

import Foundation
import StoreKit
import Combine
import OSLog

/// IAP 验证请求
struct IapVerifyRequest: Codable {
    let signedTransaction: String
    let productId: String
}

/// IAP 验证响应
struct IapVerifyResponse: Codable {
    let balance: Int?
    let pointsAdded: Int?
    let productId: String?
    let duplicate: Bool?
}

@MainActor
final class StoreKitService: ObservableObject {

    // MARK: - Published Properties

    /// 可购买的商品列表
    @Published var products: [Product] = []

    /// 是否正在购买
    @Published var isPurchasing = false

    /// 购买错误信息
    @Published var purchaseError: String?

    /// 是否正在加载商品
    @Published var isLoadingProducts = false

    /// 是否有未完成的交易（付款成功但后端未确认）
    @Published var hasUnfinishedTransactions = false

    // MARK: - Private

    private weak var authService: AuthService?
    private weak var networkService: NetworkServiceProtocol?

    /// 商品 ID 列表（与 App Store Connect 中配置的一致）
    private let productIds: Set<String> = [
        "vip.retagger.credits.100",
        "vip.retagger.credits.300",
        "vip.retagger.credits.500",
        "vip.retagger.credits.1000"
    ]

    /// 交易监听任务
    private var transactionListener: Task<Void, Error>?

    // MARK: - Initialization

    init(authService: AuthService, networkService: NetworkServiceProtocol?) {
        self.authService = authService
        self.networkService = networkService

        // 启动交易监听（处理未完成的交易、后台恢复等）
        transactionListener = listenForTransactions()
    }

    // MARK: - 加载商品

    /// 从 App Store 加载商品信息
    func loadProducts() async {
        isLoadingProducts = true
        purchaseError = nil

        do {
            let storeProducts = try await Product.products(for: productIds)
            // 按价格排序
            products = storeProducts.sorted { $0.price < $1.price }
            Logger.auth.info("成功加载 \(storeProducts.count) 个内购商品")
        } catch {
            Logger.auth.error("加载内购商品失败: \(error.localizedDescription)")
            purchaseError = "无法加载商品信息，请检查网络连接"
        }

        isLoadingProducts = false

        // 检查是否有未完成的交易
        await checkUnfinishedTransactions()
    }

    // MARK: - 购买

    /// 购买指定商品
    /// - Parameter product: 要购买的商品
    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // 发送到后端验证并充值，传递原始 JWS 字符串
                await verifyWithServer(transaction: transaction, signedData: verification.jwsRepresentation)
                // 后端确认成功后才 finish
                await transaction.finish()
                Logger.auth.info("购买成功: \(product.id)")

            case .userCancelled:
                Logger.auth.info("用户取消购买")

            case .pending:
                Logger.auth.info("购买等待审批（家庭共享等）")
                purchaseError = "购买等待审批，完成后将自动到账"

            @unknown default:
                Logger.auth.warning("未知的购买结果")
            }
        } catch {
            Logger.auth.error("购买失败: \(error.localizedDescription)")
            purchaseError = "购买失败：\(error.localizedDescription)"
        }

        isPurchasing = false
    }

    // MARK: - 同步未到账订单

    /// 同步未完成的交易（付款成功但后端未确认的情况）
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            // 同步后重新检查
            await checkUnfinishedTransactions()
            Logger.auth.info("同步未到账订单完成")
        } catch {
            Logger.auth.error("同步失败: \(error.localizedDescription)")
            purchaseError = "同步失败：\(error.localizedDescription)"
        }
    }

    /// 检查是否存在未完成的交易
    private func checkUnfinishedTransactions() async {
        var found = false
        for await _ in Transaction.unfinished {
            found = true
            break
        }
        hasUnfinishedTransactions = found
    }

    // MARK: - Private Methods

    /// 监听交易更新（应用启动时、后台恢复等）
    private func listenForTransactions() -> Task<Void, Error> {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReTagger", category: "StoreKit")
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try StoreKitService.checkVerifiedStatic(result)
                    await self?.verifyWithServer(transaction: transaction, signedData: result.jwsRepresentation)
                    await transaction.finish()
                } catch {
                    logger.error("处理交易更新失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 验证交易签名
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        try Self.checkVerifiedStatic(result)
    }

    /// 静态版本（可在 Task.detached 中调用，无 actor isolation 限制）
    private nonisolated static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    /// 将交易发送到后端验证并充值
    /// - Parameters:
    ///   - transaction: 已验证的交易对象
    ///   - signedData: VerificationResult 的原始 JWS 字符串
    private func verifyWithServer(transaction: Transaction, signedData: String) async {
        guard let networkService = networkService else {
            Logger.auth.error("NetworkService 未初始化，无法验证交易")
            return
        }

        let request = IapVerifyRequest(
            signedTransaction: signedData,
            productId: transaction.productID
        )

        do {
            let response: ApiResponse<IapVerifyResponse> = try await networkService.request(
                endpoint: "/api/v1/iap/verify",
                method: .POST,
                body: request
            )

            // 更新本地余额
            if let balance = response.data.balance {
                await authService?.updateQuota(remaining: balance)
            }

            if response.data.duplicate == true {
                Logger.auth.info("交易已处理过（幂等），跳过")
            } else {
                Logger.auth.info("后端验证充值成功，新增 \(response.data.pointsAdded ?? 0) 点")
            }
        } catch {
            Logger.auth.error("后端验证交易失败: \(error.localizedDescription)")
            purchaseError = "充值验证失败，请稍后在「恢复购买」中重试"
        }
    }
}
