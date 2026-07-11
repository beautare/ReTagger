//
//  ColumnConfigurationView.swift
//  ReTagger
//
//  Created by Claude Code
//

import SwiftUI

/// 列配置视图：支持拖拽重排和可见性切换
struct ColumnConfigurationView: View {
    @EnvironmentObject var localizationManager: LocalizationManager
    @Binding var configuration: TableColumnConfiguration
    let columnDescriptors: [MetadataColumnDescriptor]
    let onSave: (TableColumnConfiguration) -> Void

    @State private var orderedColumns: [MetadataColumn]
    @State private var visibleColumns: Set<MetadataColumn>

    init(
        configuration: Binding<TableColumnConfiguration>,
        columnDescriptors: [MetadataColumnDescriptor],
        onSave: @escaping (TableColumnConfiguration) -> Void
    ) {
        self._configuration = configuration
        self.columnDescriptors = columnDescriptors
        self.onSave = onSave

        // 初始化状态
        _orderedColumns = State(initialValue: configuration.wrappedValue.columnOrder)
        _visibleColumns = State(initialValue: configuration.wrappedValue.visibleColumns)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 列列表（带动画的拖拽列表）
            List {
                ForEach(orderedColumns, id: \.self) { column in
                    columnRow(for: column)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .onMove { from, to in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        orderedColumns.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .listStyle(.plain)
            .hideListBackgroundIfAvailable()
            .background(Color(NSColor.textBackgroundColor))
            .environment(\.defaultMinListRowHeight, 44)

            Divider()

            // 底部按钮
            footerView
        }
        .frame(width: 380, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Column Row

    private func columnRow(for column: MetadataColumn) -> some View {
        let descriptor = columnDescriptors.first { $0.column == column }
        let isRequired = descriptor?.isRequired ?? false
        let isVisible = visibleColumns.contains(column) || isRequired

        return HStack(spacing: 12) {
            // 可见性开关
            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { newValue in
                    if !isRequired {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if newValue {
                                visibleColumns.insert(column)
                            } else {
                                visibleColumns.remove(column)
                            }
                        }
                    }
                }
            ))
            .labelsHidden()
            .disabled(isRequired)
            .help(isRequired ? localizationManager.string("config.mandatory_column") : (isVisible ? localizationManager.string("config.hide_column_hint") : localizationManager.string("config.show_column_hint")))

            // 列信息
            HStack(spacing: 12) {
                // 列名
                Text(localizationManager.string(column.localizationKey))
                    .foregroundColor(isRequired ? .secondary : .primary)
                    .font(.system(size: 13))

                // 必须列标记
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.caption)
                        .help(localizationManager.string("config.mandatory_column"))
                }
            }

            Spacer()

            // 拖拽手柄
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))
                .help(localizationManager.string("config.drag_reorder_hint"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isVisible ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .contentShape(Rectangle()) // 确保整行可拖拽
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            Button(localizationManager.string("config.restore_defaults")) {
                applyPreset(.default)
            }
            .help(localizationManager.string("config.restore_help"))

            Spacer()

            Button(localizationManager.string("config.apply")) {
                var newConfig = configuration
                newConfig.columnOrder = orderedColumns
                newConfig.visibleColumns = visibleColumns
                onSave(newConfig)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help(localizationManager.string("config.save_help"))
        }
        .padding()
    }

    // MARK: - Actions

    private func applyPreset(_ preset: TableColumnConfiguration) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            orderedColumns = preset.columnOrder
            visibleColumns = preset.visibleColumns
        }
    }
}

private extension View {
    @ViewBuilder
    func hideListBackgroundIfAvailable() -> some View {
        if #available(macOS 13, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    ColumnConfigurationView(
        configuration: .constant(.default),
        columnDescriptors: MetadataColumnRegistry.descriptors,
        onSave: { _ in }
    )
}
