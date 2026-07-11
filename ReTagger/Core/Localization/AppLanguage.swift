//
//  AppLanguage.swift
//  ReTagger
//
//  Defines supported interface languages.
//

import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "🇨🇳 简体中文"
        case .english:
            return "🇺🇸 English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    var bundleResourceName: String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}
