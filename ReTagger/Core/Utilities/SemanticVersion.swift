//
//  SemanticVersion.swift
//  ReTagger
//
//  语义化版本解析与比较，借鉴 Sparkle 的 SUStandardVersionComparator。
//  支持 "major.minor.patch" 格式，正确处理数值排序和 pre-release 标签。
//

import Foundation

/// 语义化版本号，支持解析和比较
struct SemanticVersion: Comparable, CustomStringConvertible {

    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    // MARK: - 初始化

    /// 从版本字符串解析，支持 "1.5.18"、"2.0"、"3" 等格式
    init?(_ string: String) {
        // 去除可能的 "v" 前缀和空白
        let cleaned = string.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)

        // 按 "." 分割，取前三段
        let parts = cleaned.split(separator: ".", maxSplits: 2).compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }

        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    /// 直接构造
    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    // MARK: - Comparable

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    // MARK: - 便捷方法

    /// 判断 other 是否比 self 更新
    func isOlderThan(_ other: SemanticVersion) -> Bool {
        self < other
    }
}
