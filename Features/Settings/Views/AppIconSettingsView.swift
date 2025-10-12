import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

struct AppIconSettingsView: View {
    @SwiftUI.State private var currentIcon: AppIcon = AppIconManager.shared.currentIcon
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Current Icon Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Icon")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        // Current icon display
                        IconPreviewView(icon: currentIcon, size: 80, isSelected: false)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentIcon.displayName)
                                .font(.title2)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct IconPreviewView: View {
    let icon: AppIcon
    let size: CGFloat
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Try to load actual icon image first
            if let uiImage = UIImage(named: icon.previewImage) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .cornerRadius(size * 0.225) // Standard iOS icon corner radius
            } else {
                // Fallback to generated preview
                GeneratedIconPreview(symbol: "doc.text")
                    .frame(width: size, height: size)
                    .cornerRadius(size * 0.225)
            }
            
            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: size * 0.225)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: size, height: size)
                
                // Checkmark
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    )
                    .offset(x: size/2 - 12, y: -size/2 + 12)
            }
        }
    }
}

struct GeneratedIconPreview: View {
    let symbol: String
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Document representation
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.9))
                .frame(width: 44, height: 36)
                .offset(y: 2)
            
            // Lines on document
            VStack(spacing: 3) {
                Rectangle().fill(Color.black.opacity(0.25)).frame(width: 30, height: 3)
                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 30, height: 3)
                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 30, height: 3)
            }
            
            // Symbol in corner
            Image(systemName: symbol)
                .foregroundStyle(.black.opacity(0.7))
                .font(.system(size: 16, weight: .bold))
                .offset(x: 12, y: -12)
        }
    }
}

#Preview {
    NavigationView {
        AppIconSettingsView()
    }
}
