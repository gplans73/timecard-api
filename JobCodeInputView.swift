import SwiftUI
import UIKit

struct JobCodeInputView: View {
    @State private var jobCode = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Enter Job Code")
                .font(.title2)

            TextField("Job Code", text: $jobCode)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.default)
            #endif
            .frame(height: 44)
            .padding(.horizontal)
            .textFieldStyle(.roundedBorder)

            Text("Current code: \(jobCode)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    JobCodeInputView()
}
