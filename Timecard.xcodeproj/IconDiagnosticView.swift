import SwiftUI

struct IconDiagnosticView: View {
    @State private var diagnosticResults = ""
    @State private var showingIconGenerator = false
    @State private var generatedIcons: [URL] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("App Icon Diagnostics")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        Button("Run Diagnostics") {
                            runDiagnostics()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Generate Missing Icons") {
                            generateMissingIcons()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if !diagnosticResults.isEmpty {
                        Text(diagnosticResults)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    if !generatedIcons.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Generated Icons")
                                .font(.headline)
                            Text("Icons generated in temporary directory. You'll need to manually add them to your Xcode project.")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            ForEach(generatedIcons, id: \.absoluteString) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBlue).opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingIconGenerator) {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Icons Generated Successfully!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Your icons have been generated and saved to:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Temporary Directory (for this session)", systemImage: "folder.badge.gearshape")
                        Label("Documents/GeneratedIcons/ (permanent)", systemImage: "folder.badge.person.crop")
                    }
                    .padding(.leading)
                    
                    Text("Generated Files:")
                        .font(.headline)
                        .padding(.top)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(generatedIcons, id: \.absoluteString) { url in
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundColor(.blue)
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    if #available(iOS 16.0, *) {
                        HStack {
                            ShareLink("Share Icon Files", items: generatedIcons)
                                .buttonStyle(.borderedProminent)
                            
                            Button("Open Documents Folder") {
                                openDocumentsFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button("Open Documents Folder") {
                            openDocumentsFolder()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Icon Generation Complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingIconGenerator = false
                        }
                    }
                }
            }
        }
    }
    
    
    private func openDocumentsFolder() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let iconsFolderURL = documentsPath.appendingPathComponent("GeneratedIcons", isDirectory: true)
        
        // On iOS, we can't directly open Finder, but we can share the folder URL
        // This will open the Files app or allow the user to choose how to handle it
        if UIApplication.shared.canOpenURL(iconsFolderURL) {
            UIApplication.shared.open(iconsFolderURL)
        } else {
            // Fallback: copy the path to pasteboard
            UIPasteboard.general.string = iconsFolderURL.path
            print("📋 Documents path copied to pasteboard: \(iconsFolderURL.path)")
        }
    }
    
    private func copyIconsToDocuments() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let iconsFolderURL = documentsPath.appendingPathComponent("GeneratedIcons", isDirectory: true)
        
        // Create the folder if it doesn't exist
        try? FileManager.default.createDirectory(at: iconsFolderURL, withIntermediateDirectories: true)
        
        // Copy files to Documents folder
        for url in generatedIcons {
            let destinationURL = iconsFolderURL.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destinationURL) // Remove if exists
            try? FileManager.default.copyItem(at: url, to: destinationURL)
        }
        
        print("📱 Icons also copied to Documents/GeneratedIcons/")
        print("📍 Path: \(iconsFolderURL.path)")
    }
    
    private func generateMissingIcons() {
        diagnosticResults = "Generating icons...\n"
        
        do {
            // Generate icons using the existing IconGenerator
            generatedIcons = IconGenerator.generateAll()
            
            if !generatedIcons.isEmpty {
                let message = "✅ Generated \(generatedIcons.count) icon files:\n" + 
                             generatedIcons.map { "  📁 \(url.lastPathComponent)" }.joined(separator: "\n")
                print(message)
                diagnosticResults += message + "\n"
                
                showingIconGenerator = true
                
                // Copy to Documents directory for easier access
                copyIconsToDocuments()
            } else {
                let errorMessage = "❌ No icons were generated. Check console for errors."
                diagnosticResults += errorMessage
                print(errorMessage)
            }
        } catch {
            let errorMessage = "❌ Error generating icons: \(error.localizedDescription)"
            diagnosticResults += errorMessage
            print(errorMessage)
        }
    }
    
    private func runDiagnostics() {
        // Capture the diagnostic output
        var output = ""
        
        // Check Info.plist configuration
        output += "=== INFO.PLIST CONFIGURATION ===\n"
        if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any] {
            output += "✅ CFBundleIcons found\n"
            
            // Check primary icon
            if let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any] {
                output += "✅ CFBundlePrimaryIcon configured\n"
                if let iconName = primary["CFBundleIconName"] as? String {
                    output += "  Primary icon name: \(iconName)\n"
                }
                if let iconFiles = primary["CFBundleIconFiles"] as? [String] {
                    output += "  Primary icon files: \(iconFiles)\n"
                }
            } else {
                output += "❌ CFBundlePrimaryIcon missing\n"
            }
            
            // Check alternate icons
            if let alternates = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
                output += "✅ CFBundleAlternateIcons found with \(alternates.keys.count) entries\n"
                for key in alternates.keys.sorted() {
                    if let altDict = alternates[key] as? [String: Any],
                       let files = altDict["CFBundleIconFiles"] as? [String] {
                        output += "  \(key): \(files)\n"
                    }
                }
            } else {
                output += "❌ CFBundleAlternateIcons missing\n"
            }
        } else {
            output += "❌ CFBundleIcons not found in Info.plist\n"
        }
        
        // Check asset availability
        output += "\n=== ASSET AVAILABILITY ===\n"
        output += "Primary icon (AppIcon): \(UIImage(named: "AppIcon") != nil ? "✅" : "❌")\n"
        
        for icon in AppIcon.allCases {
            if icon != .primary {
                let iconName = icon.iconName ?? "nil"
                let previewAvailable = UIImage(named: icon.previewImage) != nil
                let iconAvailable = icon.iconName != nil ? UIImage(named: icon.iconName!) != nil : false
                output += "\(icon.displayName):\n"
                output += "  Icon name: \(iconName)\n"
                output += "  Preview image (\(icon.previewImage)): \(previewAvailable ? "✅" : "❌")\n"
                output += "  Icon asset: \(iconAvailable ? "✅" : "❌")\n"
            }
        }
        
        // Check current icon status
        output += "\n=== CURRENT STATUS ===\n"
        output += "Supports alternate icons: \(UIApplication.shared.supportsAlternateIcons)\n"
        output += "Current alternate icon: \(UIApplication.shared.alternateIconName ?? "nil (primary)")\n"
        
        diagnosticResults = output
    }
}

#Preview {
    IconDiagnosticView()
}