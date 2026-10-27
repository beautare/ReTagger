//
//  AppSettingsDecodingTests.swift
//  ReTaggerTests
//
//  验证旧版本设置存档缺少新增字段时，用户已有设置不会被整体重置
//

import Testing
import Foundation
@testable import ReTagger

@MainActor
struct AppSettingsDecodingTests {

    /// 模拟旧版本存档：用户自定义过若干设置，但缺少后续版本新增的字段
    private func legacyArchive(removingKeys removedKeys: [String]) throws -> Data {
        var settings = AppSettings()
        settings.recentDirectories = [
            RecentDirectoryEntry(path: "/Volumes/Music/Jazz", bookmarkData: Data([0x01, 0x02]), lastOpened: Date(timeIntervalSince1970: 1_700_000_000))
        ]
        settings.backupLocation = "/Volumes/Music/Backup"
        settings.preferredLanguage = .english
        settings.createBackups = false
        settings.diagnosticsLoggingEnabled = true
        settings.metadataTableFontScale = .huge

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        for key in removedKeys {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func legacyArchiveMissingNewKeysKeepsUserSettings() throws {
        let data = try legacyArchive(removingKeys: ["diagnosticsLoggingEnabled", "metadataTableFontScale"])

        // 合成的 Decodable 对缺失的非可选键直接失败，这正是旧版本整体重置设置的根因
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppSettings.self, from: data)
        }

        let settings = try AppSettings.decodeMergingDefaults(data)
        #expect(settings.recentDirectories.map(\.path) == ["/Volumes/Music/Jazz"])
        #expect(settings.recentDirectories.first?.bookmarkData == Data([0x01, 0x02]))
        #expect(settings.backupLocation == "/Volumes/Music/Backup")
        #expect(settings.preferredLanguage == .english)
        #expect(settings.createBackups == false)
        // 缺失字段取默认值
        #expect(settings.diagnosticsLoggingEnabled == false)
        #expect(settings.metadataTableFontScale == .medium)
    }

    @Test func completeArchiveRoundTripsAllStoredValues() throws {
        let data = try legacyArchive(removingKeys: [])
        let settings = try AppSettings.decodeMergingDefaults(data)
        #expect(settings.diagnosticsLoggingEnabled == true)
        #expect(settings.metadataTableFontScale == .huge)
        #expect(settings.backupLocation == "/Volumes/Music/Backup")
    }

    @Test func nonObjectArchiveIsRejected() {
        #expect(throws: DecodingError.self) {
            try AppSettings.decodeMergingDefaults(Data("[]".utf8))
        }
    }
}
