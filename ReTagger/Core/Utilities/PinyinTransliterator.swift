//
//  PinyinTransliterator.swift
//  ReTagger
//
//  将中文转为无声调拼音以支持检索，并带有结果缓存
//

import Foundation
import os

/// 中文转拼音工具，缓存结果以避免重复转换开销
final class PinyinTransliterator {
    static let shared = PinyinTransliterator()

    /// 拼音转换缓存（输入 → 拼音字符串）
    private var cache: [String: String] = [:]
    /// token 缓存（输入 → [全拼音, 合并拼音, 首字母缩写]）
    private var tokenCache: [String: [String]] = [:]
    /// 无锁保护，替代 DispatchQueue 减少同步开销
    private var lock = os_unfair_lock()

    private init() {}

    /// 返回小写、去声调、合并空格后的拼音。如果转换失败则返回 nil。
    func transliterate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        os_unfair_lock_lock(&lock)
        let cached = cache[trimmed]
        os_unfair_lock_unlock(&lock)
        if let cached { return cached }

        guard let transformed = Self.transform(trimmed) else { return nil }
        os_unfair_lock_lock(&lock)
        cache[trimmed] = transformed
        os_unfair_lock_unlock(&lock)
        return transformed
    }

    /// Returns: [original pinyin with spaces, collapsed pinyin, initials]
    /// Example: "张学友" -> ["zhang xue you", "zhangxueyou", "zxy"]
    func tokens(for input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 先查 token 缓存
        os_unfair_lock_lock(&lock)
        let cached = tokenCache[trimmed]
        os_unfair_lock_unlock(&lock)
        if let cached { return cached }

        guard let base = transliterate(input) else { return [] }

        var result: [String] = []
        result.append(base) // "zhang xue you"

        let collapsed = base.replacingOccurrences(of: " ", with: "")
        if collapsed != base {
            result.append(collapsed) // "zhangxueyou"
        }

        let parts = base.components(separatedBy: " ")
        if parts.count > 1 {
            let initials = parts.compactMap { $0.first }.map { String($0) }.joined()
            if !initials.isEmpty {
                result.append(initials) // "zxy"
            }
        }

        // 写入 token 缓存
        os_unfair_lock_lock(&lock)
        tokenCache[trimmed] = result
        os_unfair_lock_unlock(&lock)
        return result
    }

    private static func transform(_ input: String) -> String? {
        let mutable = NSMutableString(string: input)
        // 转为带声调的拉丁字母
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else {
            return nil
        }
        // 去除声调
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        let sanitized = mutable
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else { return nil }
        return sanitized.lowercased()
    }
}
