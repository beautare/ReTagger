//
//  AudioFormatSupport.swift
//  ReTagger
//
//  统一管理受支持音频格式及其扩展名，便于扫描、提示与校验保持一致。
//

import Foundation

enum AudioFormatSupport {
    struct Format: Sendable {
        let displayName: String
        let extensions: [String]
    }

    /// 统一配置受支持的音频格式
    nonisolated static let supportedFormats: [Format] = [
        Format(displayName: "MP3", extensions: ["mp3"]),
        Format(displayName: "FLAC", extensions: ["flac"]),
        Format(displayName: "AAC / ALAC（M4A）", extensions: ["aac", "m4a", "m4b"]),
        Format(displayName: "WAV", extensions: ["wav"]),
        Format(displayName: "AIFF", extensions: ["aif", "aiff"]),
        Format(displayName: "Ogg Vorbis", extensions: ["ogg"]),
        Format(displayName: "Opus", extensions: ["opus"]),
        Format(displayName: "DSD", extensions: ["dsf", "dff"])
    ]

    /// 所有受支持扩展名的集合（均为小写）
    nonisolated static let supportedExtensions: Set<String> = {
        let allExtensions = supportedFormats.flatMap(\.extensions)
        return Set(allExtensions.map { $0.lowercased() })
    }()

    /// 用户可见的格式列表（中文顿号分隔）
    nonisolated static var displayNameList: String {
        supportedFormats.map(\.displayName).joined(separator: "、")
    }

    /// 判断指定扩展名是否受支持
    nonisolated static func contains(extension fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }
}
