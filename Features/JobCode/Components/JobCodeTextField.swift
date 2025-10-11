import SwiftUI
import UIKit

struct JobCodeTextField: View {
    let title: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    // Default toolbar buttons - can be customized from settings
    @AppStorage("toolbarButtons") private var toolbarButtonsData: Data = {
        let defaultButtons = [
            ToolbarButton(title: "L", code: "L"),
            ToolbarButton(title: "C", code: "C")
        ]
        return (try? JSONEncoder().encode(defaultButtons)) ?? Data()
    }()
    
    private var toolbarButtons: [ToolbarButton] {
        guard !toolbarButtonsData.isEmpty,
              let buttons = try? JSONDecoder().decode([ToolbarButton].self, from: toolbarButtonsData)
        else {
            return [
                ToolbarButton(title: "L", code: "L"),
                ToolbarButton(title: "C", code: "C")
            ]
        }
        return buttons
    }

    var body: some View {
        Representable(text: $text, placeholder: title, toolbarButtons: toolbarButtons)
            .frame(minHeight: 34)
            .focused($isFocused)
            .onAppear { /* no-op */ }
    }

    // UIViewRepresentable that hosts a UITextField with inputAccessoryView toolbar
    private struct Representable: UIViewRepresentable {
        @Binding var text: String
        let placeholder: String
        let toolbarButtons: [ToolbarButton]

        func makeUIView(context: Context) -> UITextField {
            let tf = UITextField(frame: .zero)
            tf.placeholder = placeholder
            tf.borderStyle = .none
            tf.clearButtonMode = .whileEditing
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
            tf.spellCheckingType = .no
            tf.keyboardType = .numberPad // show numeric keypad
            
            context.coordinator.toolbarButtons = toolbarButtons
            context.coordinator.lastButtonsSignature = Coordinator.signature(for: toolbarButtons)
            tf.inputAccessoryView = context.coordinator.makeAccessoryToolbar(textField: tf)
            
            tf.delegate = context.coordinator
            tf.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
            return tf
        }

        func updateUIView(_ uiView: UITextField, context: Context) {
            if uiView.text != text { uiView.text = text }
            uiView.placeholder = placeholder
            
            // Update toolbar buttons if changed
            context.coordinator.toolbarButtons = toolbarButtons
            let newSig = Coordinator.signature(for: toolbarButtons)
            if newSig != context.coordinator.lastButtonsSignature {
                context.coordinator.lastButtonsSignature = newSig
                uiView.inputAccessoryView = context.coordinator.makeAccessoryToolbar(textField: uiView)
                uiView.reloadInputViews()
            }
        }

        func makeCoordinator() -> Coordinator { 
            Coordinator(text: $text, toolbarButtons: toolbarButtons) 
        }

        final class Coordinator: NSObject, UITextFieldDelegate {
            @Binding var text: String
            var toolbarButtons: [ToolbarButton]
            
            var lastButtonsSignature: String = ""

            static func signature(for buttons: [ToolbarButton]) -> String {
                buttons.map { "\($0.title)|\($0.code)" }.joined(separator: ";;")
            }
            
            init(text: Binding<String>, toolbarButtons: [ToolbarButton]) { 
                _text = text
                self.toolbarButtons = toolbarButtons
                self.lastButtonsSignature = Coordinator.signature(for: toolbarButtons)
            }

            // Build a toolbar with custom buttons and a keyboard dismiss button
            func makeAccessoryToolbar(textField: UITextField) -> UIToolbar {
                let toolbar = UIToolbar()
                toolbar.sizeToFit()

                // Appearance configuration
                if #available(iOS 15.0, *) {
                    let appearance = UIToolbarAppearance()
                    appearance.configureWithDefaultBackground()
                    appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
                    appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
                    toolbar.standardAppearance = appearance
                    toolbar.compactAppearance = appearance
                } else {
                    // Fallback for older iOS versions
                    toolbar.barStyle = .default
                    toolbar.isTranslucent = true
                    toolbar.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
                }
                // Ensure buttons use an adaptive color
                toolbar.tintColor = UIColor.label

                let isTightLayout = toolbarButtons.count >= 6
                let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
                let smallSpacingWidth: CGFloat = {
                    switch toolbarButtons.count {
                    case 0...5: return 12
                    case 6: return 2
                    case 7...8: return 2
                    default: return 1
                    }
                }()
                let edgeSpacingWidth: CGFloat = isTightLayout ? smallSpacingWidth : 0

                // Create custom toolbar buttons
                var toolbarItems: [UIBarButtonItem] = []
                if isTightLayout {
                    let leading = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
                    leading.width = edgeSpacingWidth
                    toolbarItems.append(leading)
                } else {
                    toolbarItems.append(flexible)
                }
                
                for (index, button) in toolbarButtons.enumerated() {
                    let barButton = UIBarButtonItem(
                        title: button.title,
                        style: .plain,
                        target: self,
                        action: #selector(customButtonTapped(_:))
                    )
                    let titleFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
                    let normalAttributes: [NSAttributedString.Key: Any] = [
                        .font: titleFont
                    ]
                    barButton.setTitleTextAttributes(normalAttributes, for: .normal)
                    barButton.setTitleTextAttributes(normalAttributes, for: .highlighted)
                    barButton.tag = index // Use tag to identify which button was tapped
                    barButton.accessibilityLabel = "Insert \(button.title)"
                    toolbarItems.append(barButton)
                    
                    // Add small flexible space between buttons
                    if index < toolbarButtons.count - 1 {
                        let smallSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
                        // Use minimal spacing between adjacent single-letter buttons in the set {L, C, K, P, J}
                        let minimalSet: Set<String> = ["L", "C", "K", "P", "J"]
                        let nextButton = toolbarButtons[index + 1]
                        let useMinimal = (button.title.count == 1 && nextButton.title.count == 1 &&
                                          minimalSet.contains(button.title) && minimalSet.contains(nextButton.title))
                        smallSpace.width = useMinimal ? 1 : smallSpacingWidth
                        toolbarItems.append(smallSpace)
                    }
                }

                if isTightLayout {
                    let trailing = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
                    trailing.width = edgeSpacingWidth
                    toolbarItems.append(trailing)
                } else {
                    toolbarItems.append(flexible)
                }

                let dismiss = UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(dismissKeyboard))
                dismiss.accessibilityLabel = "Dismiss Keyboard"
                
                toolbarItems.append(dismiss)

                toolbar.items = toolbarItems
                return toolbar
            }

            @objc func customButtonTapped(_ sender: UIBarButtonItem) {
                let index = sender.tag
                if index >= 0 && index < toolbarButtons.count {
                    let buttonCode = toolbarButtons[index].code
                    text = buttonCode
                }
            }

            @objc func dismissKeyboard() {
                // Resign first responder on the key window
                UIApplication.shared.sendAction(#selector(UIApplication.resignFirstResponder), to: nil, from: nil, for: nil)
            }

            @objc func textDidChange(_ sender: UITextField) {
                // Allow alphanumeric characters (letters and digits)
                let allowed = CharacterSet.alphanumerics
                let filtered = String((sender.text ?? "").unicodeScalars.filter { allowed.contains($0) })
                if filtered != sender.text { sender.text = filtered }
                text = filtered
            }
        }
    }
}

#if DEBUG
struct JobCodeTextField_Previews: PreviewProvider {
    struct PreviewHost: View {
        @State private var text = ""
        var body: some View {
            JobCodeTextField(title: "Job", text: $text)
                .padding()
        }
    }

    static var previews: some View {
        PreviewHost()
    }
}
#endif

