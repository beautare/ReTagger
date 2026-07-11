//
//  LocalizationManager.swift
//  ReTagger
//
//  Runtime language switching helper.
//

import Foundation
import Combine

@MainActor
final class LocalizationManager: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var locale: Locale

    private var bundle: Bundle

    init(language: AppLanguage) {
        self.language = language
        self.locale = Locale(identifier: language.localeIdentifier)
        self.bundle = LocalizationManager.makeBundle(for: language) ?? .main
    }

    func updateLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        locale = Locale(identifier: newLanguage.localeIdentifier)
        bundle = LocalizationManager.makeBundle(for: newLanguage) ?? .main
    }

    /// key 缺失时的回退链：当前语言 → 英文 → key 本身，
    /// 避免翻译文件漂移时界面直接暴露原始 key
    func string(_ key: String) -> String {
        let missingSentinel = "\u{FFFF}missing\u{FFFF}"
        let value = bundle.localizedString(forKey: key, value: missingSentinel, table: nil)
        if value != missingSentinel {
            return value
        }
        guard let fallback = Self.englishFallbackBundle, fallback !== bundle else {
            return key
        }
        return fallback.localizedString(forKey: key, value: key, table: nil)
    }

    func string(_ key: String, arguments: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// 英文回退 bundle（英文是 key 覆盖最全的基准语言）
    private static let englishFallbackBundle = makeBundle(for: .english)

    private static func makeBundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.bundleResourceName, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
