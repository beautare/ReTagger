//
//  DeviceFingerprint.swift
//  ReTagger
//
//  设备指纹收集工具，用于注册时发送设备信息。
//

import Foundation
import IOKit

/// 设备指纹收集工具
enum DeviceFingerprint {
    
    /// 收集设备指纹信息
    /// - Returns: JSON 格式的设备指纹字符串
    static func collect() -> String {
        let info: [String: Any] = [
            "platform": "macOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "hardwareUUID": hardwareUUID ?? "unknown",
            "modelIdentifier": modelIdentifier ?? "unknown",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "locale": Locale.current.identifier,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{\"platform\":\"macOS\",\"error\":\"failed_to_serialize\"}"
        }
        
        return jsonString
    }
    
    /// 获取硬件 UUID
    private static var hardwareUUID: String? {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let port: mach_port_t
        if #available(macOS 12.0, *) {
            port = kIOMainPortDefault
        } else {
            port = kIOMasterPortDefault
        }
        let platformExpert = IOServiceGetMatchingService(port, matchingDict)
        defer { 
            if platformExpert != 0 {
                IOObjectRelease(platformExpert) 
            }
        }
        
        guard platformExpert != 0,
              let uuidData = IORegistryEntryCreateCFProperty(
                platformExpert,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0
              )?.takeRetainedValue() as? String else {
            return nil
        }
        
        return uuidData
    }
    
    /// 获取设备型号标识符
    private static var modelIdentifier: String? {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
