//
//  PlaybackQueuePanel.swift
//  ReTagger
//
//  播放队列侧边面板
//

import SwiftUI

struct PlaybackQueuePanel: View {
    @EnvironmentObject private var playbackController: PlaybackController
    @EnvironmentObject private var localizationManager: LocalizationManager

    private let panelWidth: CGFloat = DesignSystem.Layout.queuePanelWidth

    private var state: PlaybackState { playbackController.state }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.08))
            queueList
        }
        .frame(width: panelWidth, alignment: .top)
        .frame(maxHeight: DesignSystem.Layout.queuePanelMaxHeight, alignment: .top)
        .background(panelBackground)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .shadow(
            color: Color.black.opacity(0.28),
            radius: DesignSystem.Shadows.medium.radius,
            x: DesignSystem.Shadows.medium.x,
            y: DesignSystem.Shadows.medium.y
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(panelBorder, lineWidth: 1)
        )
        .padding(DesignSystem.Spacing.md)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(DesignSystem.Animation.normal, value: playbackController.isQueuePanelVisible)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                Text(localizationManager.string("playback.queue.title"))
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(.white.opacity(0.94))
                Text(localizationManager.string("playback.queue.count", arguments: state.queueIDs.count))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Button(action: { playbackController.updateQueueVisibility(false) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(DesignSystem.Spacing.xs)
                    .background(
                        Circle()
                            .fill(panelChipGradient)
                    )
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("playback.queue.close"))
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.sm)
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                if state.queueIDs.isEmpty {
                    Text(localizationManager.string("playback.queue.empty"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(DesignSystem.Spacing.md)
                } else {
                    ForEach(Array(state.queueIDs.enumerated()), id: \.element) { index, trackID in
                        if let metadata = state.metadataLookup[trackID] {
                            queueRow(for: metadata, index: index)
                        }
                    }
                }
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    @ViewBuilder
    private func queueRow(for metadata: AudioMetadata, index: Int) -> some View {
        let isCurrent = metadata.id == state.currentTrackID
        let isSelected = playbackController.queueSelection == metadata.id

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
            HStack {
                Text("\(index + 1).")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.white.opacity(0.65))

                Text(metadata.finalTitle ?? metadata.fileName)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(isCurrent ? 0.98 : 0.92))
            }

            Text(trackSubtitle(for: metadata))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(rowBackground(isCurrent: isCurrent, isSelected: isSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(rowBorder(isCurrent: isCurrent, isSelected: isSelected), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .background(Color.clear)
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                playbackController.queueSelection = metadata.id
                playbackController.jumpAndPlay(metadata)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                playbackController.queueSelection = metadata.id
            }
        )
        .contextMenu {
            Button(localizationManager.string("playback.queue.play_here")) {
                playbackController.queueSelection = metadata.id
                playbackController.jumpAndPlay(metadata)
            }
            Button(localizationManager.string("playback.queue.remove")) {
                playbackController.remove(metadata)
            }
        }
    }

    private func trackSubtitle(for metadata: AudioMetadata) -> String {
        let artist = metadata.finalArtist ?? localizationManager.string("common.unknown_artist")
        let album = metadata.finalAlbum ?? ""
        if album.isEmpty {
            return artist
        }
        if artist.isEmpty {
            return album
        }
        return "\(artist) / \(album)"
    }

    private var panelBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.32, blue: 0.92),
                    Color(red: 0.36, green: 0.81, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.black.opacity(0.28)
        }
    }

    private var panelBorder: Color {
        Color.white.opacity(0.22)
    }

    private var panelChipGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.31, green: 0.52, blue: 1.0),
                Color(red: 0.46, green: 0.82, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func rowBackground(isCurrent: Bool, isSelected: Bool) -> LinearGradient {
        if isCurrent {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isSelected {
            return LinearGradient(
                colors: [
                    Color(red: 0.3, green: 0.48, blue: 0.99).opacity(0.45),
                    Color(red: 0.44, green: 0.82, blue: 1.0).opacity(0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(0.04),
                Color.white.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func rowBorder(isCurrent: Bool, isSelected: Bool) -> Color {
        if isCurrent {
            return Color.white.opacity(0.35)
        }
        if isSelected {
            return Color.white.opacity(0.28)
        }
        return Color.clear
    }
}
