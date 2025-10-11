import SwiftUI
#if canImport(UIKit)
import UIKit

/// A lightweight SwiftUI wrapper around TextField/SecureField that accepts UIKit-centric parameters
/// used throughout the project, including focus control via `isFirstResponder`.
struct AssistantTextField: View {
    @Binding var text: String

    // Configuration
    let placeholder: String
    let keyboardType: UIKeyboardType
    let autocapitalizationType: UITextAutocapitalizationType
    let isSecure: Bool
    let textContentType: UITextContentType?
    let font: UIFont?
    let textColor: UIColor?
    let alignment: NSTextAlignment
    let onSubmit: () -> Void
    let showDismissButton: Bool  // New parameter to control toolbar visibility

    // Focus handling
    @Binding var isFirstResponder: Bool
    @FocusState private var focused: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        isSecure: Bool = false,
        textContentType: UITextContentType? = nil,
        font: UIFont? = nil,
        textColor: UIColor? = nil,
        alignment: NSTextAlignment = .natural,
        onSubmit: @escaping () -> Void = {},
        isFirstResponder: Binding<Bool>,
        showDismissButton: Bool = true  // Default to showing the dismiss button
    ) {
        self._text = text
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.isSecure = isSecure
        self.textContentType = textContentType
        self.font = font
        self.textColor = textColor
        self.alignment = alignment
        self.onSubmit = onSubmit
        self._isFirstResponder = isFirstResponder
        self.showDismissButton = showDismissButton
    }

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .textContentType(textContentType)
            }
        }
        .keyboardType(keyboardType)
        .textInputAutocapitalization(mapAutocapitalization(autocapitalizationType))
        .autocorrectionDisabled(true)
        .multilineTextAlignment(mapAlignment(alignment))
        .font(mapFont(font))
        .foregroundStyle(mapColor(textColor) ?? .primary)
        .focused($focused)
        .onChange(of: isFirstResponder) { _, newValue in
            if newValue != focused {
                focused = newValue
            }
        }
        .onChange(of: focused) { _, newValue in
            if newValue != isFirstResponder {
                isFirstResponder = newValue
            }
        }
        .onSubmit { onSubmit() }
        .onAppear {
            // Sync initial focus state
            focused = isFirstResponder
        }
        .toolbar {
            // Add keyboard dismiss toolbar when showDismissButton is true
            if showDismissButton {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        focused = false
                        isFirstResponder = false
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
}

// MARK: - Mappers
private func mapAutocapitalization(_ type: UITextAutocapitalizationType) -> TextInputAutocapitalization? {
    switch type {
    case .none: return .never
    case .words: return .words
    case .sentences: return .sentences
    case .allCharacters: return .characters
    @unknown default: return .sentences
    }
}

private func mapAlignment(_ alignment: NSTextAlignment) -> TextAlignment {
    switch alignment {
    case .left, .natural, .justified: return .leading
    case .right: return .trailing
    case .center: return .center
    @unknown default: return .leading
    }
}

private func mapFont(_ font: UIFont?) -> Font? {
    guard let font else { return nil }
    // Use SwiftUI Font initializer from UIFont when available
    return Font(font)
}

private func mapColor(_ color: UIColor?) -> Color? {
    guard let color else { return nil }
    return Color(color)
}

// MARK: - Simple custom text field with keyboard dismiss toolbar
struct CustomTextField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("Enter text", text: $text)
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        isFocused = false
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
    }
}

#endif
