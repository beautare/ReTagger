//
//  AIRequest.swift
//  ReTagger
//
//  Data models for AI metadata correction requests
//

import Foundation
import Combine

/// Request payload for batch AI metadata processing
struct AIBatchRequest: Codable {
    let files: [FileMetadata]
    let provider: AIProvider
    let options: RequestOptions

    // MARK: - Nested Types

    struct FileMetadata: Codable {
        let filePath: String
        let fileName: String
        let title: String?
        let artist: String?
        let album: String?
        let genre: String?
        let year: String?

        /// Initialize from AudioMetadata
        init(from metadata: AudioMetadata) {
            self.filePath = metadata.filePath.path
            self.fileName = metadata.fileName
            self.title = metadata.originalTitle
            self.artist = metadata.originalArtist
            self.album = metadata.originalAlbum
            self.genre = metadata.originalGenre
            self.year = metadata.originalYear
        }

        init(
            filePath: String,
            fileName: String,
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            genre: String? = nil,
            year: String? = nil
        ) {
            self.filePath = filePath
            self.fileName = fileName
            self.title = title
            self.artist = artist
            self.album = album
            self.genre = genre
            self.year = year
        }
    }

    struct RequestOptions: Codable {
        let includeFileRenaming: Bool
        let includeFolderReorganization: Bool
        let preserveOriginalFiles: Bool
        let language: String

        init(
            includeFileRenaming: Bool = true,
            includeFolderReorganization: Bool = true,
            preserveOriginalFiles: Bool = true,
            language: String = "en"
        ) {
            self.includeFileRenaming = includeFileRenaming
            self.includeFolderReorganization = includeFolderReorganization
            self.preserveOriginalFiles = preserveOriginalFiles
            self.language = language
        }
    }
}
