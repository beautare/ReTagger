//
//  LocalizationParityTests.swift
//  ReTaggerTests
//
//  校验各语言 Localizable.strings 的 key 集合完全一致，防止翻译文件漂移。
//

import XCTest
@testable import ReTagger

final class LocalizationParityTests: XCTestCase {

    private func loadKeys(for language: AppLanguage) throws -> Set<String> {
        let bundle = Bundle(for: LocalizationManager.self)
        let path = try XCTUnwrap(
            bundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language.bundleResourceName
            ),
            "缺少 \(language.rawValue) 的 Localizable.strings"
        )
        let dictionary = try XCTUnwrap(
            NSDictionary(contentsOfFile: path) as? [String: String],
            "\(language.rawValue) 的 Localizable.strings 无法解析"
        )
        return Set(dictionary.keys)
    }

    /// 以英文为基准，所有语言的 key 集合必须完全一致
    func testAllLanguagesShareTheSameKeySet() throws {
        let englishKeys = try loadKeys(for: .english)
        XCTAssertFalse(englishKeys.isEmpty, "英文 key 集合为空，资源可能未打包")

        for language in AppLanguage.allCases where language != .english {
            let keys = try loadKeys(for: language)
            let missing = englishKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(englishKeys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(language.rawValue) 缺少 key：\(missing)")
            XCTAssertTrue(extra.isEmpty, "\(language.rawValue) 多出 key：\(extra)")
        }
    }
}
