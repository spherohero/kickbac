import SwiftUI

struct AccountView: View {
    let session: AuthSession
    let profile: ProfileStore
    let onSignIn: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: Destination?
    @State private var signInAfterDismiss = false

    private enum Destination: String, Identifiable {
        case edit, history, settings
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                HStack {
                    Text("Me")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { sheet = .settings } label: {
                        Image("ProfileSettings").resizable().scaledToFit()
                            .frame(width: 22, height: 22).accessibilityHidden(true)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel("Settings").accessibilityIdentifier("profileSettings")
                }

                VStack(spacing: 20) {
                    Button(action: editProfile) {
                        ProfileAvatar(photoData: profile.profile.photoData, side: 148)
                            .padding(6)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                    }
                    .buttonStyle(ProfilePressStyle())
                    .accessibilityLabel("Edit your profile photo")
                    .disabled(session.isBusy || profile.isLoading || (session.isSignedIn && profile.remoteState == .unknown))

                    VStack(spacing: 12) {
                        Text(profile.profile.name.isEmpty ? "Your profile" : profile.profile.name)
                            .font(.system(.title, design: .rounded, weight: .medium))
                            .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        if !session.isSignedIn && !session.isRestoring {
                            VStack(spacing: 16) {
                                Text("Sign in to set up your profile and see your readings.")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button(action: onSignIn) {
                                    Text("Sign in").font(.system(.headline, design: .rounded)).foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                                .controlSize(.extraLarge).tint(.white).disabled(session.isBusy)
                                .accessibilityIdentifier("profileSignIn")
                            }
                            .padding(.top, 4)
                        } else {
                            Button(action: editProfile) {
                                HStack(spacing: 7) {
                                    Image("ProfileEdit").resizable().scaledToFit().frame(width: 13, height: 13)
                                    Text("Edit profile").font(.system(.subheadline, design: .rounded, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                            .accessibilityIdentifier("editProfile")
                            .disabled(session.isBusy || profile.isLoading || (session.isSignedIn && profile.remoteState == .unknown))
                        }
                    }
                }
                .padding(.bottom, 4)

                if profile.isLoading {
                    ProgressView("Loading your profile")
                } else if let message = profile.message {
                    VStack(spacing: 12) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        if session.isSignedIn {
                            Button("Retry profile") {
                                Task { await profile.refresh { try await session.loadProfile() } }
                            }
                            .buttonStyle(.glass).controlSize(.large)
                        }
                    }
                }

                if session.isSignedIn || session.isRestoring {
                    VStack(spacing: 16) {
                        let columns = typeSize.isAccessibilitySize ? 1 : 2
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                            statistic("Saved readings", value: readingCount)
                            statistic("Last check", value: lastCheck)
                        }
                        if session.isCheckingAPI && session.history == nil {
                            ProgressView("Loading your readings")
                                .font(.system(.footnote, design: .rounded))
                        } else if let message = session.apiMessage {
                            Text(message).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                }

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        profileRow("ReadingClock", title: "Reading history", detail: "Your recent check-ins") { sheet = .history }
                        profileRow("ProfileSettings", title: "Settings", detail: "Account and permissions") { sheet = .settings }
                    }
                }

                if let message = session.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 480).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .font(.system(.body, design: .rounded)).scrollIndicators(.hidden)
        .refreshable {
            await profile.refresh { try await session.loadProfile() }
            await session.checkAPI()
        }
        .sheet(item: $sheet, onDismiss: {
            if signInAfterDismiss {
                signInAfterDismiss = false
                onSignIn()
            }
        }) { destination in
            switch destination {
            case .edit: ProfileEditorView(profile: profile, session: session)
            case .settings: ProfileSettingsView(session: session, profile: profile, onSignIn: queuedSignIn)
            case .history: ProfileHistoryView(session: session, onSignIn: queuedSignIn)
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--review-profile-editor") { sheet = .edit }
        }
        #endif
    }

    private var readingCount: String {
        guard let history = session.history else { return "—" }
        return "\(history.items.count)\(history.hasMore ? "+" : "")"
    }

    private var lastCheck: String {
        guard let date = session.history?.items.compactMap(\.recordedDate).max() else { return "—" }
        return Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(.footnote, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .medium)).monospacedDigit()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func profileRow(_ icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(icon).resizable().scaledToFit().frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.body, design: .rounded, weight: .semibold))
                    Text(detail).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image("ProfileChevron").resizable().scaledToFit().frame(width: 10, height: 10)
                    .foregroundStyle(.tertiary).flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 54).padding(18).contentShape(.rect(cornerRadius: 24))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(ProfilePressStyle())
    }

    private func editProfile() {
        guard !session.isBusy else { return }
        if session.isSignedIn && profile.owner != nil {
            guard !profile.isLoading, profile.remoteState != .unknown else { return }
            sheet = .edit
        }
        else { onSignIn() }
    }

    private func queuedSignIn() {
        signInAfterDismiss = true
        sheet = nil
    }
}

struct ProfilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
