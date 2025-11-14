import SwiftUI

struct SoundTestView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Sound Test")
                .font(.headline)
            Button("Play MailSwish") {
                SoundEffects.play(.send, overrideSilent: true)
            }
            .buttonStyle(.borderedProminent)

            Text("Ensure a file named MailSwish.m4a (or .wav) is in Copy Bundle Resources, or add a Data Asset named 'MailSwish'.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    SoundTestView()
}
