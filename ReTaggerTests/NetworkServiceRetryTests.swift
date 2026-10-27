//
//  NetworkServiceRetryTests.swift
//  ReTaggerTests
//
//  验证瞬时失败只对 GET 自动重发，AI 处理请求使用长超时且不重发（避免重复扣点）
//

import Testing
import Foundation
@testable import ReTagger

/// 拦截 NetworkService 的全部请求：记录收到的请求，并按预设状态码返回
final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statusCode = 200
    private static var requests: [URLRequest] = []

    static func reset(statusCode: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        requests = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let statusCode = Self.statusCode
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"status\":\"UP\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct EmptyBody: Codable {}
private struct StatusResponse: Codable { let status: String }

@Suite(.serialized) @MainActor
struct NetworkServiceRetryTests {

    private func makeService() -> NetworkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return NetworkService(baseURL: "https://api.example.com", configuration: configuration)
    }

    @Test func postIsNotResentAfterServerError() async {
        RecordingURLProtocol.reset(statusCode: 500)
        let service = makeService()

        await #expect(throws: ReTaggerError.self) {
            let _: StatusResponse = try await service.request(endpoint: "/api/v1/vouchers/redeem", method: .POST, body: EmptyBody())
        }
        #expect(RecordingURLProtocol.recordedRequests.count == 1)
    }

    @Test func getIsRetriedAfterServerError() async {
        RecordingURLProtocol.reset(statusCode: 500)
        let service = makeService()

        await #expect(throws: ReTaggerError.self) {
            let _: StatusResponse = try await service.request(endpoint: "/api/v1/tokens/check", method: .GET)
        }
        #expect(RecordingURLProtocol.recordedRequests.count == 3)
    }

    @Test func metadataProcessingUsesLongTimeoutAndSingleAttempt() async {
        RecordingURLProtocol.reset(statusCode: 503)
        let service = makeService()
        let request = MetadataProcessingRequest(files: [], options: .default)

        await #expect(throws: ReTaggerError.self) {
            _ = try await service.processBatch(request, batchSize: 20)
        }
        let recorded = RecordingURLProtocol.recordedRequests
        #expect(recorded.count == 1)
        #expect(recorded.first?.timeoutInterval == Constants.API.metadataProcessingTimeout)
        #expect(recorded.first?.value(forHTTPHeaderField: Constants.API.registrationSourceHeader) == Constants.API.registrationSource)
    }

    @Test func ordinaryRequestsKeepDefaultTimeout() async throws {
        RecordingURLProtocol.reset(statusCode: 200)
        let service = makeService()

        let response: StatusResponse = try await service.request(endpoint: "/api/v1/metadata/health", method: .GET)
        #expect(response.status == "UP")
        #expect(RecordingURLProtocol.recordedRequests.first?.timeoutInterval == Constants.API.defaultTimeout)
    }
}
