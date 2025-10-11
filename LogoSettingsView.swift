import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import PhotosUI
#endif

struct LogoSettingsView: View {
    @EnvironmentObject var store: TimecardStore
    @State private var showingRevertAlert = false

    #if canImport(UIKit)
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil
    @State private var showFileImporter = false
    #endif

    var body: some View {
        List {
            Section(header: Text("Current Logo").font(.headline)) {
                HStack {
                    Spacer()
                    if let img = store.companyLogoImage {
                        img.resizable().scaledToFit().frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.3)))
                    } else {
                        Text("No logo set")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            #if canImport(UIKit)
            Section(header: Text("Upload").font(.headline)) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose Image", systemImage: "photo.on.rectangle")
                }
                .onChange(of: pickerItem) { oldValue, newValue in
                    guard let item = newValue else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            pickedImageData = data
                            store.setCompanyLogo(data: data)
                        }
                    }
                }
                if pickedImageData != nil {
                    Text("Logo updated.").font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import From Files", systemImage: "folder")
                }
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.image], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            do {
                                let data = try Data(contentsOf: url)
                                pickedImageData = data
                                store.setCompanyLogo(data: data)
                            } catch {
                                print("Failed to load image data: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("File import failed: \(error)")
                    }
                }
            }
            #endif

            Section {
                Button(role: .destructive) {
                    showingRevertAlert = true
                } label: {
                    Label("Revert to Default", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .navigationTitle("Company Logo")
        .alert("Revert to Default Logo?", isPresented: $showingRevertAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) { store.resetCompanyLogoToDefault() }
        } message: {
            Text("This will stop using the custom image and show the bundled logo asset instead.")
        }
    }
}

#Preview {
    LogoSettingsView().environmentObject(TimecardStore.sampleStore)
}
