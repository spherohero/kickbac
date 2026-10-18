import SwiftUI

struct ProfileAvatar: View {
    let photoData: Data?
    let side: CGFloat

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("NavMe").resizable().scaledToFit().padding(side * 0.3)
                    .foregroundStyle(.secondary).background(.white.opacity(0.06))
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side * 0.12))
        .overlay { RoundedRectangle(cornerRadius: side * 0.12).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

struct ProfileEditorView: View {
    let profile: ProfileStore
    let session: AuthSession
    @State private var owner: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditingName: Bool
    @State private var name: String
    @State private var photoData: Data?
    @State private var showsCamera = false
    @State private var showsError = false
    @State private var errorMessage = ""

    init(profile: ProfileStore, session: AuthSession) {
        self.profile = profile
        self.session = session
        _owner = State(initialValue: profile.owner)
        _name = State(initialValue: profile.profile.name)
        _photoData = State(initialValue: profile.profile.photoData)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        ProfileAvatar(photoData: photoData, side: 168)
                        Button {
                            isEditingName = false
                            showsCamera = true
                        } label: {
                            HStack(spacing: 8) {
                                Image("OnboardingCamera").resizable().scaledToFit().frame(width: 18, height: 18)
                                Text(photoData == nil ? "Take a photo" : "Retake photo")
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                        if photoData != nil {
                            Button("Remove photo", role: .destructive) { photoData = nil }
                                .frame(minHeight: 44)
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What should we call you?")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        TextField("Name", text: $name)
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .textContentType(.givenName).textInputAutocapitalization(.words)
                            .autocorrectionDisabled().focused($isEditingName).submitLabel(.done)
                            .accessibilityLabel("Name")
                            .onSubmit { isEditingName = false }
                            .padding(20).background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
                        Text(!name.isEmpty && !PartyProfile.isValidName(name) ? "Use 1–80 characters, without control characters." : "This is the name your party will see.")
                            .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
            }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(profile.isSaving) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    HStack {
                        if profile.isSaving { ProgressView().tint(.secondary) }
                        Text(profile.isSaving ? "Saving…" : "Save changes")
                    }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(canSave ? Color.black : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                .controlSize(.extraLarge).tint(.white).disabled(!canSave)
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
                .background(Color("SplashBackground"))
            }
            .alert("Couldn't save your profile", isPresented: $showsError) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage) }
            .fullScreenCover(isPresented: $showsCamera) {
                ProfilePhotoCapture { image in
                    showsCamera = false
                    guard let data = image.jpegData(compressionQuality: 0.85) else {
                        errorMessage = ProfilePhoto.PreparationError.invalidImage.localizedDescription
                        showsError = true
                        return
                    }
                    photoData = data
                }
            }
            .disabled(profile.isSaving)
            .interactiveDismissDisabled(profile.isSaving)
        }
        .tint(.primary).preferredColorScheme(.dark).font(.system(.body, design: .rounded))
        .onChange(of: profile.owner) {
            if owner != profile.owner { dismiss() }
        }
    }

    private var canSave: Bool {
        PartyProfile.isValidName(name) && owner != nil && owner == profile.owner
            && !profile.isSaving && !profile.isLoading && profile.remoteState != .unknown
    }

    private func save() {
        guard canSave else { return }
        Task {
            do {
                guard owner == profile.owner else { throw ProfileStore.SaveError.signedOut }
                try await profile.save(name: name, photoData: photoData) { name, picture in
                    try await session.saveProfile(name: name, photoData: picture)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showsError = true
            }
        }
    }
}

private struct ProfilePhotoCapture: View {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = ProfileCamera()
    @State private var previewSize = CGSize.zero

    var body: some View {
        NavigationStack {
            CameraCapture(camera: camera, previewSize: $previewSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CameraCaptureControls(camera: camera, previewSize: previewSize, onContinue: onPhoto)
                }
                .background(Color("SplashBackground"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(.primary).preferredColorScheme(.dark)
    }
}
