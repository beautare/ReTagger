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

    private let listener: NWListener
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
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
            throw LoopbackError.startFailed(error.localizedDescription)
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

        return GoogleOAuthLoopbackServer(listener: listener, port: port)
    }

    /// 等待系统浏览器带着授权码（或错误）回调本地地址
    func waitForCallback(timeout: TimeInterval = 300) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask { [listener] in
                try await withCheckedThrowingContinuation { continuation in
                    listener.newConnectionHandler = { connection in
                        Self.handle(connection, continuation: continuation)
                    }
                }
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

    private static func handle(_ connection: NWConnection, continuation: CheckedContinuation<Callback, Error>) {
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                defer { connection.cancel() }

                guard let data, let rawRequest = String(data: data, encoding: .utf8) else {
                    respond(on: connection, success: false)
                    continuation.resume(throwing: LoopbackError.invalidCallback)
                    return
                }

                switch parseCallback(from: rawRequest) {
                case .success(let callback):
                    respond(on: connection, success: true)
                    continuation.resume(returning: callback)
                case .failure(let error):
                    respond(on: connection, success: false)
                    continuation.resume(throwing: error)
                }
            }
        }
        connection.start(queue: .main)
    }

    private static func parseCallback(from rawRequest: String) -> Result<Callback, LoopbackError> {
        guard let requestLine = rawRequest.components(separatedBy: "\r\n").first,
              let path = requestLine.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)") else {
            return .failure(.invalidCallback)
        }

        if let errorValue = components.queryItems?.first(where: { $0.name == "error" })?.value {
            return .failure(.oauthDenied(errorValue))
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return .failure(.invalidCallback)
        }

        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return .success(Callback(code: code, state: state))
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
