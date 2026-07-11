//
//  ASCIISecureField.swift
//  ReTagger
//
//  自定义密码输入框，禁用输入法以避免密码输入冲突
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

/// 仅接受 ASCII 字符的密码输入框，自动禁用非英文输入法
struct ASCIISecureField: View {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false
    
    var body: some View {
        ASCIISecureFieldRepresentable(
            placeholder: placeholder,
            text: $text,
            isDisabled: isDisabled
        )
        .frame(height: 22)
    }
}

/// NSSecureTextField 的 SwiftUI 包装，禁用输入法
private struct ASCIISecureFieldRepresentable: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool
    
    func makeNSView(context: Context) -> ASCIISecureTextField {
        let textField = ASCIISecureTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.isEnabled = !isDisabled
        return textField
    }
    
    func updateNSView(_ nsView: ASCIISecureTextField, context: Context) {
        // 只在外部值变化时更新（避免循环更新）
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.isEnabled = !isDisabled
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSSecureTextField else { return }
            text = textField.stringValue
        }
    }
}

/// 自定义 NSSecureTextField，禁用非 ASCII 输入法
final class ASCIISecureTextField: NSSecureTextField {
    
    // 强制禁用输入法上下文，防止出现中文候选词窗口
    override var inputContext: NSTextInputContext? {
        return nil
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // 当获取焦点时，切换到 ASCII 输入模式
            switchToASCIIInputSource()
        }
        return result
    }
    
    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        // 开始编辑时确保使用 ASCII 输入
        switchToASCIIInputSource()
    }
    
    /// 切换到 ASCII 输入源（系统英文键盘）
    private func switchToASCIIInputSource() {
        // 获取当前输入源
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              !inputSources.isEmpty else {
            return
        }
        
        // 查找 ASCII 兼容的输入源
        for source in inputSources {
            // 检查是否是 ASCII 兼容的键盘输入源
            if let categoryRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory),
               let category = Unmanaged<CFString>.fromOpaque(categoryRef).takeUnretainedValue() as String?,
               category == kTISCategoryKeyboardInputSource as String {
                
                // 检查是否是 ASCII 兼容
                if let asciiRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) {
                    let isASCII = Unmanaged<CFBoolean>.fromOpaque(asciiRef).takeUnretainedValue()
                    if CFBooleanGetValue(isASCII) {
                        // 检查是否可选择
                        if let selectableRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                            let isSelectable = Unmanaged<CFBoolean>.fromOpaque(selectableRef).takeUnretainedValue()
                            if CFBooleanGetValue(isSelectable) {
                                // 选择这个输入源
                                TISSelectInputSource(source)
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}
