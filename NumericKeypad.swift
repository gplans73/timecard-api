import SwiftUI

struct NumericKeypad: View {
    let insert: (String) -> Void
    let backspace: () -> Void
    let done: () -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        let label = rows[r][c]
                        if label.isEmpty {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        } else if label == "⌫" {
                            Button(action: backspace) {
                                Text(label)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(KeyButtonStyle())
                            .accessibilityLabel("Backspace")
                        } else {
                            Button {
                                insert(label)
                            } label: {
                                Text(label)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(KeyButtonStyle())
                            .accessibilityLabel("Digit \(label)")
                        }
                    }
                }
            }

            Button(action: done) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(KeyButtonStyle(filled: true))
            .accessibilityLabel("Done")
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 2)
    }
}

private struct KeyButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .background(filled ? Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1.0) : Color.secondary.opacity(configuration.isPressed ? 0.2 : 0.1))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    VStack {
        NumericKeypad(
            insert: { _ in },
            backspace: {},
            done: {}
        )
    }
    .padding()
}
