//
//  EnvironmentParser.swift
//  ReTagger
//
//  .env file parser for development configuration
//

import Foundation
import OSLog

/// .env 文件解析工具，仅在 DEBUG 模式下使用
class EnvironmentParser {
    
    /// 已加载的配置文件路径
    nonisolated(unsafe) static private(set) var loadedFilePath: String?
    
    /// 解析 .env 文件内容
    /// - Parameter fileName: 文件名，默认为 ".env.local"
    /// - Returns: 解析出的键值对字典
    static func parseEnvironmentFile(fileName: String = ".env.local", sourceFilePath: String = #file) -> [String: String] {
        var path = Bundle.main.path(forResource: fileName, ofType: nil)
        
        // Fallback: Try to find .env.local in the project root relative to this source file
        if path == nil {
            let sourceURL = URL(fileURLWithPath: sourceFilePath)
            // Go up 4 levels: Utilities -> Core -> ReTagger -> Project Root
            let projectRoot = sourceURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            
            let localEnvPath = projectRoot.appendingPathComponent(fileName).path
            if FileManager.default.fileExists(atPath: localEnvPath) {
                path = localEnvPath
                Logger.config.debug("Found .env.local file at project root: \(localEnvPath)")
            }
        }
        
        guard let envPath = path else {
            Logger.config.debug("No .env.local file found at bundle root or project root")
            return [:]
        }
        
        loadedFilePath = envPath
        
        do {
            let content = try String(contentsOfFile: envPath, encoding: .utf8)
            return parseContent(content)
        } catch {
            Logger.config.error("Failed to read .env.local file: \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// 检查是否存在指定的环境变量键
    static func hasKey(_ key: String) -> Bool {
        let envVars = parseEnvironmentFile()
        return envVars.keys.contains(key)
    }
    
    /// 从解析的环境变量中获取值
    /// - Parameters:
    ///   - key: 环境变量键名
    ///   - defaultValue: 默认值
    /// - Returns: 环境变量值或默认值
    static func getValue(for key: String, defaultValue: String) -> String {
        let envVars = parseEnvironmentFile()
        return envVars[key] ?? defaultValue
    }
    
    /// 解析文件内容
    /// - Parameter content: 文件内容字符串
    /// - Returns: 键值对字典
    private static func parseContent(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            // 移除前后空白字符
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 跳过空行和注释行
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // 解析键值对
            // Fix: Use split with maxSplits to handle values containing '='
            let components = trimmedLine.split(separator: "=", maxSplits: 1).map(String.init)
            guard components.count == 2 else {
                Logger.config.warning("Invalid .env.local line format: \(trimmedLine)")
                continue
            }
            
            let key = components[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let value = components[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // 移除值两端的引号
            let unquotedValue = removeQuotes(from: value)
            
            result[key] = unquotedValue
        }
        
        Logger.config.debug("Parsed \(result.count) environment variables from .env.local file")
        return result
    }
    
    /// 移除字符串两端的引号
    /// - Parameter string: 输入字符串
    /// - Returns: 移除引号后的字符串
    private static func removeQuotes(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        
        return trimmed
    }
}
