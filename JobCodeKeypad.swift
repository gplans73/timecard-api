import SwiftUI

public struct JobCodeKeypadView: View {
    @Binding var text: String
    var onDone: (() -> Void)?

    public init(text: Binding<String>, onDone: (() -> Void)? = nil) {
        self._text = text
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 8) {
            numberRow(["1","2","3"])
            numberRow(["4","5","6"])
            numberRow(["7","8","9"])
            numberRow(["L","0","S"]) // L and S on bottom row per spec
            HStack(spacing: 8) {
                keyButton(systemName: "delete.left") {
                    if !text.isEmpty { _ = text.removeLast() }
                }
                .accessibilityLabel("Backspace")

                Spacer(minLength: 8)

                Button(action: { onDone?() }) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 4)
    }

    @ViewBuilder
    private func numberRow(_ items: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { label in
                keyButton(label: label) {
                    text.append(label)
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title2).bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.secondary)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func keyButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 56, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }
}

#Preview {
    StatefulPreviewWrapper("") { binding in
        VStack(spacing: 20) {
            Text("Job Code: \(binding.wrappedValue)")
            JobCodeKeypadView(text: binding)
        }
        .padding()
    }
}

// Helper for previews
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value: Value
    var content: (Binding<Value>) -> Content

    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }

    var body: some View { content($value) }
}
