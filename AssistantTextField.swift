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

    // Focus handling
    @Binding var isFirstResponder: Bool
    @State private var isPresentingPad: Bool = false

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
        isFirstResponder: Binding<Bool>
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
    }

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        #if os(iOS)
        .textInputAutocapitalization(mapAutocapitalization(autocapitalizationType))
        .keyboardType(KeyboardType(keyboardType))
        .textContentType(mapTextContentType(textContentType))
        #endif
        .foregroundStyle(text.isEmpty ? .secondary : (mapColor(textColor) ?? .primary))
        .frame(maxWidth: .infinity, alignment: mapAlignmentForFrame(alignment))
        .font(mapFont(font))
        .submitLabel(.done)
        .onSubmit { onSubmit() }
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

private func mapAlignmentForFrame(_ alignment: NSTextAlignment) -> Alignment {
    switch alignment {
    case .left, .natural, .justified:
        return Alignment(horizontal: .leading, vertical: .center)
    case .right:
        return Alignment(horizontal: .trailing, vertical: .center)
    case .center:
        return Alignment(horizontal: .center, vertical: .center)
    @unknown default:
        return Alignment(horizontal: .leading, vertical: .center)
    }
}

#if os(iOS)
private func mapTextContentType(_ type: UITextContentType?) -> UITextContentType? { type }

private func KeyboardType(_ type: UIKeyboardType) -> UIKeyboardType { type }
#endif

#endif
