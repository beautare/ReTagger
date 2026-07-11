//
//  AIResponse.swift
//  ReTagger
//
//  Data models for AI metadata correction responses
//

import Foundation
import Combine

/// Response payload from batch AI metadata processing
struct AIBatchResponse: Codable {
    let results: [CorrectedMetadata]
    let processingTime: TimeInterval
    let tokensUsed: Int?

    // MARK: - Nested Types

    struct CorrectedMetadata: Codable {
        let filePath: String
        let title: String?
        let artist: String?
        let album: String?
        let genre: String?
        let year: String?
        let suggestedFileName: String?
        let suggestedFolderPath: String?
        let confidence: Double?
        let notes: String?

        /// Apply corrections to AudioMetadata object
        func apply(to metadata: inout AudioMetadata) {
            metadata.correctedTitle = title
            metadata.correctedArtist = artist
            metadata.correctedAlbum = album
            metadata.correctedGenre = genre
            metadata.correctedYear = year
            metadata.suggestedFileName = suggestedFileName
            metadata.suggestedFolderPath = suggestedFolderPath
            metadata.confidence = confidence
            metadata.aiNotes = notes
            metadata.processingState = metadata.hasEffectiveCorrections ? .awaitingConfirmation : .completed
        }
    }
}

// MARK: - Helper Methods

extension AIBatchResponse {
    /// Find corrected metadata for a specific file path
    func correctedMetadata(for filePath: String) -> CorrectedMetadata? {
        return results.first { $0.filePath == filePath }
    }
}
