import SwiftUI

struct AccountView: View {
    let session: AuthSession
    let profile: ProfileStore
    let onSignIn: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(PracticeReadingStore.self) private var practice
    @State private var sheet: Destination?
    @State private var signInAfterDismiss = false

    private enum Destination: String, Identifiable {
        case edit, history, games, settings
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                profileHeader

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
                }

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

                if session.isSignedIn || session.isRestoring || !practice.readings.isEmpty {
                    VStack(spacing: 24) {
                        let columns = typeSize.isAccessibilitySize ? 1 : 2
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columns), spacing: 24) {
                            Button { sheet = .history } label: {
                                statistic("Saved readings", value: readingCount)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(ProfilePressStyle())
                            .accessibilityHint("Opens reading history.")
                            .accessibilityIdentifier("savedReadingsHistory")
                            Button { sheet = .history } label: {
                                statistic("Last check", value: lastCheck, isDate: true)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(ProfilePressStyle())
                            .accessibilityHint("Opens reading history.")
                            .accessibilityIdentifier("lastCheckHistory")
                            Button { sheet = .games } label: {
                                statistic("Games played", value: session.stats.map { String($0.gamesPlayed) } ?? "—")
                                    .contentShape(.rect)
                            }
                            .buttonStyle(ProfilePressStyle()).accessibilityHint("Opens recent games.")
                            .accessibilityIdentifier("gamesPlayedHistory")
                            Button { sheet = .games } label: {
                                statistic("Wins", value: session.stats.map { String($0.wins) } ?? "—")
                                    .contentShape(.rect)
                            }
                            .buttonStyle(ProfilePressStyle()).accessibilityHint("Opens recent games.")
                            .accessibilityIdentifier("winsHistory")
                        }
                        Button { sheet = .games } label: {
                            statistic("Points", value: session.stats.map { String($0.totalPoints) } ?? "—")
                                .contentShape(.rect)
                        }
                        .buttonStyle(ProfilePressStyle()).accessibilityHint("Opens recent games.")
                        .accessibilityIdentifier("pointsHistory")

                        if session.isLoadingStats && session.stats == nil { ProgressView("Loading game stats") }
                        if let message = session.statsMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if session.isCheckingAPI && session.history == nil {
                            ProgressView("Loading your readings")
                                .font(.system(.footnote, design: .rounded))
                        } else if let message = session.apiMessage {
                            Text(message).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                        }
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
            await session.loadStats()
        }
        .sheet(item: $sheet, onDismiss: {
            if signInAfterDismiss {
                signInAfterDismiss = false
                onSignIn()
            }
        }) { destination in
            switch destination {
            case .edit: ProfileEditorView(profile: profile, session: session)
            case .settings: ProfileSettingsView(session: session, onSignIn: queuedSignIn)
            case .history: ProfileHistoryView(session: session, onSignIn: queuedSignIn)
            case .games: RecentGamesView(session: session, onSignIn: queuedSignIn)
            }
        }
    }

    private var profileHeader: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

        return ZStack(alignment: .topTrailing) {
            layout {
                Button(action: editProfile) {
                    ProfileAvatar(photoData: profile.profile.photoData, side: 148)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                }
                .buttonStyle(ProfilePressStyle())
                .accessibilityLabel("Edit your profile photo")
                .disabled(session.isBusy || profile.isLoading || (session.isSignedIn && profile.remoteState == .unknown))

                Text(profile.profile.name.isEmpty ? "Your profile" : profile.profile.name)
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, typeSize.isAccessibilitySize ? 0 : 64)
                    .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? nil : 160,
                           alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if session.isSignedIn || session.isRestoring {
                        Button(action: editProfile) {
                            Image("ProfileEdit").resizable().scaledToFit()
                                .frame(width: 22, height: 22).accessibilityHidden(true)
                        }
                        .accessibilityLabel("Edit profile").accessibilityIdentifier("editProfile")
                        .disabled(session.isBusy || profile.isLoading || (session.isSignedIn && profile.remoteState == .unknown))
                    }
                    Button { sheet = .settings } label: {
                        Image("ProfileSettings").resizable().scaledToFit()
                            .frame(width: 22, height: 22).accessibilityHidden(true)
                    }
                    .accessibilityLabel("Settings").accessibilityIdentifier("profileSettings")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .fixedSize()
            }
        }
        .padding(.bottom, 4)
    }

    private var readingCount: String {
        guard session.history != nil || !practice.readings.isEmpty else { return "—" }
        let count = (session.history?.items.filter { $0.bacReading != nil }.count ?? 0) + practice.readings.count
        return "\(count)\(session.history?.hasMore == true ? "+" : "")"
    }

    private var lastCheck: String {
        let dates = (session.history?.items.compactMap(\.bacReading).map(\.date) ?? []) + practice.readings.map(\.date)
        guard let date = dates.max() else { return "—" }
        return Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func statistic(_ title: String, value: String, isDate: Bool = false) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(isDate ? .title2 : .largeTitle, design: .rounded, weight: .medium)).monospacedDigit()
                .frame(minHeight: 44)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 88).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
