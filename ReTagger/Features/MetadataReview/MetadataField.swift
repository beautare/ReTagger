//
//  MetadataField.swift
//  ReTagger
//
//  定义元数据字段枚举以及状态徽章视图
//

import SwiftUI

enum MetadataField: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case genre
    case year
    case fileName

    var id: String { rawValue }

    var displayName: String {
        // Fallback for non-localized contexts or legacy usage
        return localizationKey
    }

    var localizationKey: String {
        switch self {
        case .title: return "column.title"
        case .artist: return "column.artist"
        case .album: return "column.album"
        case .genre: return "column.genre"
        case .year: return "column.year"
        case .fileName: return "column.filename"
        }
    }

    func originalValue(for metadata: AudioMetadata) -> String? {
        switch self {
        case .title: return metadata.originalTitle
        case .artist: return metadata.originalArtist
        case .album: return metadata.originalAlbum
        case .genre: return metadata.originalGenre
        case .year: return metadata.originalYear
        case .fileName: return metadata.fileName
        }
    }

    func correctedValue(for metadata: AudioMetadata) -> String? {
        switch self {
        case .title: return metadata.correctedTitle
        case .artist: return metadata.correctedArtist
        case .album: return metadata.correctedAlbum
        case .genre: return metadata.correctedGenre
        case .year: return metadata.correctedYear
        case .fileName: return metadata.suggestedFileName
        }
    }

    func applySelection(to metadata: inout AudioMetadata) {
        switch self {
        case .title:
            if let corrected = metadata.correctedTitle {
                metadata.originalTitle = corrected
            }
            metadata.correctedTitle = nil
        case .artist:
            if let corrected = metadata.correctedArtist {
                metadata.originalArtist = corrected
            }
            metadata.correctedArtist = nil
        case .album:
            if let corrected = metadata.correctedAlbum {
                metadata.originalAlbum = corrected
            }
            metadata.correctedAlbum = nil
        case .genre:
            if let corrected = metadata.correctedGenre {
                metadata.originalGenre = corrected
            }
            metadata.correctedGenre = nil
        case .year:
            if let corrected = metadata.correctedYear {
                metadata.originalYear = corrected
            }
            metadata.correctedYear = nil
        case .fileName:
            metadata.suggestedFileName = nil
        }
    }

    func discardSuggestion(on metadata: inout AudioMetadata) {
        switch self {
        case .title:
            metadata.correctedTitle = nil
        case .artist:
            metadata.correctedArtist = nil
        case .album:
            metadata.correctedAlbum = nil
        case .genre:
            metadata.correctedGenre = nil
        case .year:
            metadata.correctedYear = nil
        case .fileName:
            metadata.suggestedFileName = nil
        }
    }

    func hasChange(in metadata: AudioMetadata) -> Bool {
        AudioMetadata.hasMeaningfulChange(
            original: originalValue(for: metadata),
            corrected: correctedValue(for: metadata)
        )
    }

    func isRelevant(for metadata: AudioMetadata) -> Bool {
        hasChange(in: metadata)
    }

    static func relevantFields(for metadata: AudioMetadata) -> [MetadataField] {
        allCases.filter { $0.isRelevant(for: metadata) }
    }
}

// MARK: - Status Badge

extension AudioMetadata.ProcessingState {
    var localizationKey: String {
        switch self {
        case .pending: return "state.pending"
        case .processing: return "state.processing"
        case .awaitingConfirmation: return "state.awaiting_confirmation"
        case .completed: return "state.completed"
        case .failed: return "state.failed"
        case .userModified: return "state.user_modified"
        }
    }
}

struct StatusBadge: View {
    let state: AudioMetadata.ProcessingState
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(localizationManager.string(state.localizationKey))
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .cornerRadius(4)
    }

    private var iconName: String {
        switch state {
        case .pending: return "clock"
        case .processing: return "hourglass"
        case .awaitingConfirmation: return "exclamationmark.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .userModified: return "pencil.circle"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .pending: return Color.gray.opacity(0.2)
        case .processing: return Color.blue.opacity(0.2)
        case .awaitingConfirmation: return Color.orange.opacity(0.2)
        case .completed: return Color.green.opacity(0.2)
        case .failed: return Color.red.opacity(0.2)
        case .userModified: return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .pending: return .gray
        case .processing: return .blue
        case .awaitingConfirmation: return .orange
        case .completed: return .green
        case .failed: return .red
        case .userModified: return .orange
        }
    }
}
