//
//  GoogleOAuthLoopbackServer.swift
//  ReTagger
//
//  Google 已不再支持 Desktop 类型 OAuth Client 使用自定义 URL Scheme 重定向，
//  官方要求改用 loopback 地址（127.0.0.1）接收系统浏览器的授权回调。
//  本类在回环接口上临时起一个仅处理单次请求的 HTTP 监听，用完即关闭。
//

import Foundation
import Network
import OSLog

final class GoogleOAuthLoopbackServer {

    enum LoopbackError: LocalizedError {
        case startFailed(String)
        case timedOut
        case invalidCallback
        case oauthDenied(String)

        var errorDescription: String? {
            switch self {
            case .startFailed(let reason):
                return "无法启动本地登录回调服务：\(reason)"
            case .timedOut:
                return "Google 登录授权超时，请重试"
            case .invalidCallback:
                return "未能从授权回调中读取到授权码"
            case .oauthDenied(let reason):
                return "Google 登录未完成：\(reason)"
            }
        }
    }

    struct Callback: Sendable {
        let code: String
        let state: String?
    }

    /// 授权回调的单次交付状态机：回调可能先于 waitForCallback 注册到达，
    /// 因此结果需要暂存；反向则唤醒等待中的 continuation
    private enum WaitState {
        case idle
        case waiting(CheckedContinuation<Callback, Error>)
        case finished(Result<Callback, Error>)
    }

    private let listener: NWListener
    private(set) var port: UInt16 = 0

    private let lock = NSLock()
    private var waitState: WaitState = .idle

    private init(listener: NWListener) {
        self.listener = listener
    }

    /// 在回环接口启动监听，返回系统分配的临时端口
    static func start() async throws -> GoogleOAuthLoopbackServer {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            Logger.auth.error("创建 loopback 监听器失败：\(String(describing: error), privacy: .public)")
            throw LoopbackError.startFailed(error.localizedDescription)
        }

        let server = GoogleOAuthLoopbackServer(listener: listener)

        // 必须在 start 前设置连接处理器：Network.framework 对未设置
        // newConnectionHandler 就启动的监听直接报 failed(Invalid argument)
        listener.newConnectionHandler = { [weak server] connection in
            guard let server else {
                connection.cancel()
                return
            }
            server.handle(connection)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            listener.stateUpdateHandler = { state in
                guard !didResume else { return }
                switch state {
                case .ready:
                    didResume = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    didResume = true
                    Logger.auth.error("loopback 监听启动失败：\(String(describing: error), privacy: .public)")
                    continuation.resume(throwing: LoopbackError.startFailed(error.localizedDescription))
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }

        guard port != 0 else {
            listener.cancel()
            throw LoopbackError.startFailed("系统未分配可用端口")
        }

        server.port = port
        Logger.auth.info("loopback 回调服务已就绪，端口 \(port, privacy: .public)")
        return server
    }

    /// 等待系统浏览器带着授权码（或错误）回调本地地址
    func waitForCallback(timeout: TimeInterval = 300) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask {
                try await self.nextCallback()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LoopbackError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    func stop() {
        listener.cancel()
    }

    /// 提前终止等待（例如用户关闭了授权窗口），唤醒 waitForCallback 并抛出取消
    func cancelWaiting() {
        resolve(.failure(CancellationError()))
    }

    // MARK: - 回调交付

    private func nextCallback() async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                switch waitState {
                case .finished(let result):
                    waitState = .idle
                    lock.unlock()
                    continuation.resume(with: result)
                case .idle:
                    waitState = .waiting(continuation)
                    lock.unlock()
                case .waiting:
                    lock.unlock()
                    continuation.resume(throwing: LoopbackError.invalidCallback)
                }
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    /// 连接结果的统一出口：有等待者则唤醒，否则暂存首个结果供稍后消费
    private func resolve(_ result: Result<Callback, Error>) {
        lock.lock()
        switch waitState {
        case .waiting(let continuation):
            waitState = .idle
            lock.unlock()
            continuation.resume(with: result)
        case .idle:
            waitState = .finished(result)
            lock.unlock()
        case .finished:
            lock.unlock()
        }
    }

    // MARK: - HTTP 请求处理

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
                defer { connection.cancel() }
                guard let self else { return }

                guard let data, let rawRequest = String(data: data, encoding: .utf8) else {
                    Self.respond(on: connection, success: false)
                    return
                }

                switch Self.parseCallback(from: rawRequest) {
                case .callback(let callback):
                    Self.respond(on: connection, success: true)
                    self.resolve(.success(callback))
                case .oauthError(let error):
                    Self.respond(on: connection, success: false)
                    Logger.auth.error("授权回调解析失败：\(error.localizedDescription, privacy: .public)")
                    self.resolve(.failure(error))
                case .unrelated:
                    Self.respond(on: connection, success: false)
                }
            }
        }
        connection.start(queue: .main)
    }

    /// 回调请求的解析结果；unrelated 表示与授权无关的请求（如 favicon），
    /// 应答后忽略即可，不能让它抢先占用回调结果
    private enum ParseOutcome {
        case callback(Callback)
        case oauthError(LoopbackError)
        case unrelated
    }

    private static func parseCallback(from rawRequest: String) -> ParseOutcome {
        guard let requestLine = rawRequest.components(separatedBy: "\r\n").first,
              let path = requestLine.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)") else {
            return .unrelated
        }

        guard components.path == GoogleOAuthConfig.redirectPath else {
            return .unrelated
        }

        if let errorValue = components.queryItems?.first(where: { $0.name == "error" })?.value {
            return .oauthError(.oauthDenied(errorValue))
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return .oauthError(.invalidCallback)
        }

        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return .callback(Callback(code: code, state: state))
    }

    private static func respond(on connection: NWConnection, success: Bool) {
        let message = success
            ? "登录成功，可以关闭此页面返回 ReTagger。"
            : "登录未完成，请返回 ReTagger 重试。"
        let html = """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>ReTagger</title>\
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;\
        align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f;}</style>\
        </head><body><p>\(message)</p></body></html>
        """
        let body = Data(html.utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
