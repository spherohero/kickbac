import SwiftUI

struct RecentGamesView: View {
    let session: AuthSession
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var history = RecentGamesStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if session.isRestoring {
                        loading
                    } else if !session.isSignedIn {
                        placeholder("Your games live here", detail: "Sign in to see your recent games.")
                        action("Sign in", perform: onSignIn)
                    } else if history.owner == session.profileOwner, let page = history.page {
                        if let message = history.message { retryNotice(message) }
                        if page.items.isEmpty {
                            placeholder("No games yet", detail: "Completed games will appear here.")
                        } else {
                            Text("Party unavailable")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(page.items) { game in
                                RecentGameRow(game: game)
                            }
                            if page.hasMore {
                                action(history.isLoading ? "Loading…" : "Load more") {
                                    Task { await load(loadMore: true) }
                                }
                            }
                        }
                    } else if let message = history.message, history.owner == session.profileOwner {
                        placeholder("Couldn't load your games", detail: message)
                        action("Try again") { Task { await load() } }
                    } else {
                        loading
                    }
                }
                .frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Recent games").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .onChange(of: session.profileOwner, initial: true) { history.switchOwner(session.profileOwner) }
        .task(id: session.profileOwner) {
            history.switchOwner(session.profileOwner)
            if session.isSignedIn { await load() }
        }
    }

    private func load(loadMore: Bool = false) async {
        await history.load(loadMore: loadMore) { offset in try await session.gameResults(offset: offset) }
    }

    private var loading: some View {
        ProgressView("Loading your games").frame(maxWidth: .infinity).padding(.top, 48)
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image("NavParty").resizable().scaledToFit().frame(width: 32, height: 32)
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func retryNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button("Try again") { Task { await load() } }
                .frame(minHeight: 44).disabled(history.isLoading)
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.black)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        .controlSize(.extraLarge).tint(.white).disabled(session.isBusy || history.isLoading)
    }
}

private struct RecentGameRow: View {
    let game: APIGameResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    gameImage
                    gameLabel
                    Spacer(minLength: 8)
                    points
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) { gameImage; gameLabel }
                    points
                }
            }
            HStack(spacing: 8) {
                Text(game.outcome.title).fontWeight(.medium)
                Text("·").accessibilityHidden(true)
                Text("Score \(game.score.formatted())")
            }
            .font(.system(.subheadline, design: .rounded))
            Text("Check-in unavailable")
                .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.white.opacity(0.045), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var gameImage: some View {
        if let knownGame = PartyGame(rawValue: game.gameID) {
            PartyGameIcon(game: knownGame)
        } else {
            Image("NavParty").resizable().scaledToFit().padding(18)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
        }
    }

    private var gameLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(game.gameTitle).font(.system(.headline, design: .rounded))
            if let date = game.recordedDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("Date unavailable")
            }
        }
        .font(.system(.footnote, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.awardedPoints, format: .number)
                .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
            Text("points").font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
