//
//  DeviceTokenModels.swift
//  ReTagger
//
//  Created by Codex on 2025/02/15.
//

import Foundation
import Combine

/// 设备令牌请求体
struct DeviceTokenRequest: Encodable {
    let deviceType: String
    let deviceModel: String
    let osVersion: String
    let deviceId: String
    let appVersion: String?
    let appBuildNumber: String?
}

/// 设备令牌响应体
struct DeviceTokenResponse: Decodable {
    struct Payload: Decodable {
        let token: String
        let remainingRequests: Int?
    }

    let data: Payload
}
