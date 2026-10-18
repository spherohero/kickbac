import AVFoundation
import SwiftUI

struct ProfileSettingsView: View {
    let session: AuthSession
    let profile: ProfileStore
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsEditor = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if session.isSignedIn {
                        Button { showsEditor = true } label: {
                            HStack(spacing: 16) {
                                ProfileAvatar(photoData: profile.profile.photoData, side: 56)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profile.profile.name.isEmpty ? "Your profile" : profile.profile.name)
                                        .fontWeight(.medium)
                                    Text("Edit name and photo").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                chevron
                            }
                            .padding(.vertical, 8).contentShape(.rect)
                        }
                        .disabled(profile.owner == nil || profile.isLoading || profile.remoteState == .unknown)
                    } else {
                        Button("Sign in", action: onSignIn).disabled(session.isBusy)
                    }
                } header: { Text("Profile") } footer: {
                    Text("Your name and photo are saved to your account and restored when you sign in.")
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        HStack(spacing: 14) {
                            Image("OnboardingCamera").resizable().scaledToFit().frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Camera")
                                Text(cameraAccess).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            chevron
                        }
                        .frame(minHeight: 54).contentShape(.rect)
                    }
                    .accessibilityHint("Opens kickBAC settings on your iPhone.")
                } header: { Text("Permissions") } footer: {
                    Text("Camera access is used to take your profile photo.")
                }

                if session.isSignedIn {
                    Section {
                        Button {
                            Task {
                                await profile.refresh { try await session.loadProfile() }
                                await session.checkAPI()
                                await session.loadStats()
                            }
                        } label: {
                            HStack {
                                Text(session.isCheckingAPI || profile.isLoading ? "Refreshing…" : "Refresh account")
                                Spacer()
                                if session.isCheckingAPI { ProgressView() }
                            }
                            .frame(minHeight: 32).contentShape(.rect)
                        }
                        .disabled(session.isBusy || session.isCheckingAPI || profile.isLoading || profile.isSaving)
                        if let message = profile.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let message = session.apiMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        } else if session.history != nil {
                            Text("Readings loaded.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Sign out", role: .destructive) {
                            Task {
                                await session.signOut()
                                if !session.isSignedIn { dismiss() }
                            }
                        }
                        .frame(minHeight: 32).disabled(session.isBusy)
                        if let message = session.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text("Account") }
                }

                Section {
                    LabeledContent("Version", value: version)
                } header: { Text("About") }
            }
            .scrollContentBackground(.hidden)
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showsEditor) { ProfileEditorView(profile: profile, session: session) }
        }
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .onChange(of: scenePhase) {
            if scenePhase == .active { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private var chevron: some View {
        Image("ProfileChevron").resizable().scaledToFit().frame(width: 10, height: 10)
            .foregroundStyle(.tertiary).flipsForRightToLeftLayoutDirection(true).accessibilityHidden(true)
    }

    private var cameraAccess: String {
        switch cameraStatus {
        case .authorized: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested yet"
        @unknown default: "Manage in Settings"
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
