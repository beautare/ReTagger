//
//  MetadataReviewView+Toolbar.swift
//  ReTagger
//
//  顶部工具栏展示与交互
//

import SwiftUI

extension MetadataReviewView {
    /// 多目录显示时，目录名累计字符数上限；超出后截断并追加省略标记
    private static let multiDirectoryNameMaxLength = 30

    @ViewBuilder
    var toolbarPrincipalContent: some View {
        let directories = coordinator.workspaceDirectories

        VStack(alignment: .center, spacing: 2) {
            if coordinator.isRestoringWorkspace {
                // 恢复中：旋转进度环 + 文件夹图标
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(height: 22)
            } else if directories.isEmpty {
                Text(localizationManager.string("toolbar.metadata_review"))
                    .font(.headline)
                    .fontWeight(.medium)
                Text(localizationManager.string("toolbar.select_directory"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if directories.count == 1,
                      let directory = directories.first {
                let directoryName = directory.lastPathComponent.isEmpty
                    ? directory.path
                    : directory.lastPathComponent
                HStack(spacing: 4) {
                    Text(localizationManager.string(
                        "toolbar.track_count",
                        arguments: directoryName, currentFiles.count
                    ))
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    
                    restoreBadge
                }
            } else {
                let displayLabel = truncatedDirectoryNames(directories)
                let tooltipText = fullDirectoryTooltip(directories)

                HStack(spacing: 4) {
                    Text(localizationManager.string(
                        "toolbar.track_count_multi",
                        arguments: displayLabel, currentFiles.count
                    ))
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(tooltipText)
                    
                    restoreBadge
                }
            }
        }
        .frame(maxWidth: 400)
    }
    
    /// 恢复完成后短暂展示的成功徽章（纯图标）
    @ViewBuilder
    private var restoreBadge: some View {
        if coordinator.showRestoreBadge {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: coordinator.showRestoreBadge)
        }
    }

    // MARK: - 多目录名称拼接与截断

    /// 将目录名列表拼接为可显示的字符串，超出字符限制时截断并标注剩余数量
    private func truncatedDirectoryNames(_ directories: [URL]) -> String {
        let separator = localizationManager.string("common.comma")
        let names = directories.map { dir -> String in
            dir.lastPathComponent.isEmpty ? dir.path : dir.lastPathComponent
        }

        var result = ""
        var includedCount = 0
        let maxLength = Self.multiDirectoryNameMaxLength

        for name in names {
            let candidate = includedCount == 0
                ? name
                : result + separator + name
            if candidate.count > maxLength, includedCount > 0 {
                break
            }
            result = candidate
            includedCount += 1
        }

        let remaining = names.count - includedCount
        if remaining == 1 {
            // 仅剩 1 个时直接拼上，避免"等 1 个目录"的尴尬措辞
            result += separator + names[includedCount]
        } else if remaining >= 2 {
            result += localizationManager.string("toolbar.directories_and_more", arguments: remaining)
        }

        return result
    }

    /// 构建完整目录列表的 tooltip 文本，每个目录独占一行
    private func fullDirectoryTooltip(_ directories: [URL]) -> String {
        let names = directories.map { dir -> String in
            dir.lastPathComponent.isEmpty ? dir.path : dir.lastPathComponent
        }
        let list = names.joined(separator: "\n")
        return localizationManager.string(
            "toolbar.track_count_multi_tooltip",
            arguments: directories.count, list
        )
    }

    @ViewBuilder
    var toolbarControls: some View {
        let isInteractionDisabled = isProcessing || 
                                    isApplyingCorrections || 
                                    pendingBulkAction != nil || 
                                    isShowingConflictResolution || 
                                    isShowingTrashConfirmation || 
                                    isShowingBackupAccessDeniedAlert

        Button {
            let total = currentFiles.count
            guard total > 0 else { return }
            let selection = Set(currentFiles.map(\.id))
            pendingBulkAction = PendingBulkAction(
                action: .aiProcess,
                count: total,
                selection: selection
            )
        } label: {
            Label(localizationManager.string("ai.tagging"), systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(isInteractionDisabled || currentFiles.isEmpty)
        .help(localizationManager.string("ai.tag_all_tracks"))

        let hasConfirmableTracks = currentFiles.contains { metadata in
            metadata.processingState == .awaitingConfirmation &&
            !MetadataField.relevantFields(for: metadata).isEmpty &&
            !pendingConfirmations.contains(metadata.id)
        }

        if hasConfirmableTracks {
            Button {
                let allConfirmable = currentFiles.filter { metadata in
                    metadata.processingState == .awaitingConfirmation &&
                    !MetadataField.relevantFields(for: metadata).isEmpty &&
                    !pendingConfirmations.contains(metadata.id)
                }
                guard !allConfirmable.isEmpty else { return }
                let selection = Set(allConfirmable.map(\.id))
                pendingBulkAction = PendingBulkAction(
                    action: .confirmWrite,
                    count: allConfirmable.count,
                    selection: selection
                )
            } label: {
                Label(localizationManager.string("action.confirm_write"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isInteractionDisabled)
            .help(localizationManager.string("ai.write_all_pending"))
        } else {
            Button {
                // No action
            } label: {
                Label(localizationManager.string("action.confirm_write"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .help(localizationManager.string("action.no_pending_confirmations"))
        }
    }
}
