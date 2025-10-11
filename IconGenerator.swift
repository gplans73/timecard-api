import SwiftUI

// MARK: - IconArt
struct IconArt: View {
    let colors: [Color]
    let symbol: String

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 140, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 760, height: 620)
                .offset(y: 40)
            VStack(spacing: 36) {
                Capsule().fill(Color.black.opacity(0.22)).frame(width: 520, height: 28)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 520, height: 24)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 520, height: 24)
            }
            .offset(y: 10)
            Image(systemName: symbol)
                .font(.system(size: 220, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .offset(x: 260, y: -260)
        }
    }
}
