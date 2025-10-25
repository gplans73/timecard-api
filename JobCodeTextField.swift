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
            tf.keyboardType = .decimalPad // show numeric keypad without phone-style letters
            
            context.coordinator.toolbarButtons = toolbarButtons
            context.coordinator.lastButtonsSignature = Coordinator.signature(for: toolbarButtons)
            tf.inputAccessoryView = context.coordinator.makeAccessoryToolbar(textField: tf)
            
            tf.delegate = context.coordinator
            tf.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
            
            context.coordinator.textField = tf
            
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

            enum KeyboardMode { case number, text }
            weak var textField: UITextField?
            var keyboardMode: KeyboardMode = .number

            static func signature(for buttons: [ToolbarButton]) -> String {
                buttons.map { "\($0.title)|\($0.code)" }.joined(separator: ";;")
            }
            
            init(text: Binding<String>, toolbarButtons: [ToolbarButton]) {
                _text = text
                self.toolbarButtons = toolbarButtons
                self.lastButtonsSignature = Coordinator.signature(for: toolbarButtons)
            }

            // Build a toolbar with custom buttons and a keyboard dismiss button
            func makeAccessoryToolbar(textField: UITextField) -> UIView {
                self.textField = textField
                
                // Use UIInputView instead of UIToolbar for proper keyboard-matching appearance
                let pointsPerMM: CGFloat = 163.0 / 25.4
                let desiredSpacing: CGFloat = 2.5 * pointsPerMM
                let inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44 + desiredSpacing), inputViewStyle: .keyboard)
                inputView.translatesAutoresizingMaskIntoConstraints = false
                inputView.allowsSelfSizing = true

                let isTightLayout = toolbarButtons.count >= 6
                let smallSpacingWidth: CGFloat = {
                    switch toolbarButtons.count {
                    case 0...5: return 12
                    case 6: return 2
                    case 7...8: return 2
                    default: return 1
                    }
                }()
                
                // Create a container view for centering
                let containerStack = UIStackView()
                containerStack.axis = .horizontal
                containerStack.alignment = .center
                containerStack.distribution = .equalSpacing
                containerStack.translatesAutoresizingMaskIntoConstraints = false
                
                if !isTightLayout {
                    containerStack.addArrangedSubview(UIView()) // flexible space
                }
                
                // Build one pill that contains all toolbar buttons
                if !toolbarButtons.isEmpty {
                    // Pill container with transparent background
                    let groupContainer = UIView()
                    groupContainer.backgroundColor = UIColor.white.withAlphaComponent(0.9)
                    groupContainer.layer.cornerRadius = 16
                    if #available(iOS 13.0, *) {
                        groupContainer.layer.cornerCurve = .continuous
                        // Adapt to dark mode
                        groupContainer.backgroundColor = UIColor { traitCollection in
                            if traitCollection.userInterfaceStyle == .dark {
                                return UIColor(white: 0.2, alpha: 0.9)
                            } else {
                                return UIColor.white.withAlphaComponent(0.9)
                            }
                        }
                    }
                    
                    // Subtle shadow
                    groupContainer.layer.shadowColor = UIColor.black.cgColor
                    groupContainer.layer.shadowOpacity = 0.15
                    groupContainer.layer.shadowRadius = 8
                    groupContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
                    
                    // Horizontal stack for inner buttons
                    let stack = UIStackView()
                    stack.axis = .horizontal
                    stack.alignment = .center
                    stack.distribution = .fillProportionally
                    stack.spacing = 6
                    stack.translatesAutoresizingMaskIntoConstraints = false
                    
                    stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                    // Create buttons inside the pill
                    for (index, model) in toolbarButtons.enumerated() {
                        let btn = UIButton(type: .system)
                        btn.setTitle(model.title, for: .normal)
                        btn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
                        
                        if #available(iOS 13.0, *) {
                            btn.setTitleColor(UIColor.label, for: .normal)
                        } else {
                            btn.setTitleColor(UIColor.darkGray, for: .normal)
                        }
                        
                        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
                        btn.tag = index
                        btn.addTarget(self, action: #selector(customButtonTappedFromButton(_:)), for: .touchUpInside)
                        stack.addArrangedSubview(btn)
                    }

                    // Keyboard mode segmented control (123 / ABC)
                    let kbToggle = UISegmentedControl(items: ["123", "ABC"])
                    kbToggle.selectedSegmentIndex = (keyboardMode == .number) ? 0 : 1
                    kbToggle.addTarget(self, action: #selector(segmentedChanged(_:)), for: .valueChanged)
                    stack.addArrangedSubview(kbToggle)

                    // Divider
                    let divider = UIView()
                    divider.backgroundColor = UIColor.label.withAlphaComponent(0.2)
                    divider.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        divider.widthAnchor.constraint(equalToConstant: 1)
                    ])
                    stack.addArrangedSubview(divider)

                    // Chevron button
                    let chevron = UIButton(type: .system)
                    let chevronConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
                    chevron.setImage(UIImage(systemName: "chevron.down", withConfiguration: chevronConfig), for: .normal)
                    
                    if #available(iOS 13.0, *) {
                        chevron.tintColor = UIColor.label
                    } else {
                        chevron.tintColor = UIColor.darkGray
                    }
                    
                    chevron.accessibilityLabel = "Dismiss Keyboard"
                    chevron.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
                    chevron.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
                    stack.addArrangedSubview(chevron)

                    // Add stack directly to container (no blur sublayer)
                    groupContainer.addSubview(stack)
                    
                    NSLayoutConstraint.activate([
                        stack.leadingAnchor.constraint(equalTo: groupContainer.leadingAnchor, constant: 14),
                        stack.trailingAnchor.constraint(equalTo: groupContainer.trailingAnchor, constant: -14),
                        stack.topAnchor.constraint(equalTo: groupContainer.topAnchor, constant: 6),
                        stack.bottomAnchor.constraint(equalTo: groupContainer.bottomAnchor, constant: -6)
                    ])

                    // Height constraint
                    let heightConstraint = groupContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
                    heightConstraint.priority = .defaultHigh
                    heightConstraint.isActive = true

                    let screenWidth = UIScreen.main.bounds.width
                    let sideMargin: CGFloat = 4.0 * pointsPerMM // 4mm on each side
                    let desiredWidth = max(0, screenWidth - (sideMargin * 2))

                    let minWidthConstraint = groupContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: desiredWidth)
                    minWidthConstraint.priority = .defaultLow
                    minWidthConstraint.isActive = true

                    let maxWidthConstraint = groupContainer.widthAnchor.constraint(lessThanOrEqualToConstant: desiredWidth)
                    maxWidthConstraint.priority = .defaultHigh
                    maxWidthConstraint.isActive = true

                    groupContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    groupContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                    containerStack.addArrangedSubview(groupContainer)
                }

                if !isTightLayout {
                    containerStack.addArrangedSubview(UIView()) // flexible space
                }

                inputView.addSubview(containerStack)
                NSLayoutConstraint.activate([
                    containerStack.leadingAnchor.constraint(equalTo: inputView.leadingAnchor, constant: 8),
                    containerStack.trailingAnchor.constraint(equalTo: inputView.trailingAnchor, constant: -8),
                    containerStack.centerYAnchor.constraint(equalTo: inputView.centerYAnchor),
                    containerStack.heightAnchor.constraint(lessThanOrEqualTo: inputView.heightAnchor, constant: -8)
                ])

                return inputView
            }

            @objc func segmentedChanged(_ sender: UISegmentedControl) {
                keyboardMode = (sender.selectedSegmentIndex == 0) ? .number : .text
                if let tf = textField {
                    tf.keyboardType = (keyboardMode == .number) ? .decimalPad : .asciiCapable
                    tf.reloadInputViews()
                }
            }

            @objc func customButtonTappedFromButton(_ sender: UIButton) {
                let index = sender.tag
                if index >= 0 && index < toolbarButtons.count {
                    let buttonCode = toolbarButtons[index].code
                    text = buttonCode
                }
            }

            @objc func customButtonTapped(_ sender: UIBarButtonItem) {
                let index = sender.tag
                if index >= 0 && index < toolbarButtons.count {
                    let buttonCode = toolbarButtons[index].code
                    text = buttonCode
                }
            }

            @objc func dismissKeyboard() {
                UIApplication.shared.sendAction(#selector(UIApplication.resignFirstResponder), to: nil, from: nil, for: nil)
            }

            @objc func textDidChange(_ sender: UITextField) {
                // Allow alphanumeric characters plus hyphen (e.g., codes like 26999-1)
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
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
