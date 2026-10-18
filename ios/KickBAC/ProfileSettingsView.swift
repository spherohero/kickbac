import AVFoundation
import SwiftUI

struct ProfileSettingsView: View {
    let session: AuthSession
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showsDeletionUnavailable = false

    var body: some View {
        NavigationStack {
            Form {
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
                    .accessibilityHint("Opens KickBAC settings on your iPhone.")
                } header: { Text("Permissions") }

                if session.isSignedIn {
                    Section {
                        Button("Sign out", role: .destructive) {
                            Task {
                                await session.signOut()
                                if !session.isSignedIn { dismiss() }
                            }
                        }
                        .frame(minHeight: 32).disabled(session.isBusy)
                        Button("Delete account", role: .destructive) {
                            showsDeletionUnavailable = true
                        }
                        .frame(minHeight: 32).disabled(session.isBusy)
                        .accessibilityIdentifier("deleteAccount")
                        if let message = session.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text("Account") }
                } else {
                    Section {
                        Button("Sign in", action: onSignIn).disabled(session.isBusy)
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
            .alert("Account deletion unavailable", isPresented: $showsDeletionUnavailable) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Account deletion isn't available yet. Your account hasn't been changed.")
            }
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
