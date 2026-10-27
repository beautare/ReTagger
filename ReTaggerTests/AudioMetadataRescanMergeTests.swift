//
//  AudioMetadataRescanMergeTests.swift
//  ReTaggerTests
//
//  验证目录重扫合并只按路径继承审阅状态，不同专辑的同名文件不会互相串用 AI 修正
//

import Testing
import Foundation
@testable import ReTagger

@MainActor
struct AudioMetadataRescanMergeTests {

    private func track(_ path: String, title: String? = nil) -> AudioMetadata {
        let url = URL(fileURLWithPath: path)
        return AudioMetadata(filePath: url, fileName: url.lastPathComponent, originalTitle: title)
    }

    @Test func sameFileNameInAnotherAlbumDoesNotInheritCorrections() {
        var reviewed = track("/Music/Album A/01.flac", title: "track 1")
        reviewed.correctedTitle = "Song A"
        reviewed.processingState = .awaitingConfirmation

        let rescanned = [
            track("/Music/Album A/01.flac", title: "track 1"),
            track("/Music/Album B/01.flac", title: "intro")
        ]

        let merged = AudioMetadata.mergeRescanned(rescanned, preservingReviewStateFrom: [reviewed])

        #expect(merged[0].correctedTitle == "Song A")
        #expect(merged[0].processingState == .awaitingConfirmation)
        #expect(merged[1].correctedTitle == nil)
        #expect(merged[1].processingState == .pending)
    }

    @Test func fileRenamedByAppKeepsReviewStateAtNewPath() {
        // 应用改名后，内存条目路径已更新，但 ID 仍由旧路径生成
        var renamed = track("/Music/Album A/01.flac")
        renamed.filePath = URL(fileURLWithPath: "/Music/Album A/Song A - Artist.flac")
        renamed.fileName = "Song A - Artist.flac"
        renamed.processingState = .completed

        let rescanned = [track("/Music/Album A/Song A - Artist.flac", title: "Song A")]
        let merged = AudioMetadata.mergeRescanned(rescanned, preservingReviewStateFrom: [renamed])

        #expect(merged.count == 1)
        #expect(merged[0].processingState == .completed)
    }

    @Test func freshTagsFromDiskWinOverPreviousOriginals() {
        var previous = track("/Music/Album A/02.flac", title: "old title")
        previous.processingState = .completed

        let rescanned = [track("/Music/Album A/02.flac", title: "edited elsewhere")]
        let merged = AudioMetadata.mergeRescanned(rescanned, preservingReviewStateFrom: [previous])

        #expect(merged[0].originalTitle == "edited elsewhere")
        #expect(merged[0].processingState == .completed)
    }
}
