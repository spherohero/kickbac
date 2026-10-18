import SwiftUI

struct ProfileHistoryView: View {
    let session: AuthSession
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if session.isRestoring {
                        ProgressView("Loading your readings")
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    } else if !session.isSignedIn {
                        placeholder("Your readings live here", detail: "Sign in to see your saved readings.")
                        action("Sign in", perform: onSignIn)
                    } else if let history = session.history {
                        if let message = session.apiMessage { retryNotice(message) }
                        if history.items.isEmpty {
                            placeholder("No readings yet", detail: "Your breathalyzer check-ins will show up here.")
                        } else {
                            Text("Your saved breathalyzer check-ins.")
                                .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                            ForEach(history.items.sorted {
                                ($0.recordedDate ?? .distantPast) > ($1.recordedDate ?? .distantPast)
                            }) { reading in
                                ProfileReadingRow(reading: reading)
                            }
                            if history.hasMore {
                                action(session.isCheckingAPI ? "Loading…" : "Load more") {
                                    Task { await session.checkAPI(loadMore: true) }
                                }
                            }
                        }
                    } else if let message = session.apiMessage {
                        placeholder("Couldn't load your readings", detail: message)
                        action("Try again") { Task { await session.checkAPI() } }
                    } else {
                        ProgressView("Loading your readings")
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    }
                }
                .frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable { await session.checkAPI() }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Reading history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .task {
            if session.history == nil && session.apiMessage == nil { await session.checkAPI() }
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image("ReadingClock").resizable().scaledToFit().frame(width: 32, height: 32)
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func retryNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
            Button("Try again") { Task { await session.checkAPI() } }
                .frame(minHeight: 44).disabled(session.isCheckingAPI)
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.black)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        .controlSize(.extraLarge).tint(.white).disabled(session.isBusy || session.isCheckingAPI)
    }
}

private struct ProfileReadingRow: View {
    let reading: APIMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { dateLabel; Spacer(minLength: 0); sourceLabel }
                VStack(alignment: .leading, spacing: 8) { dateLabel; sourceLabel }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let value = reading.estimatedBACPercent, value.isFinite, value >= 0 {
                    Text(value, format: .number.precision(.fractionLength(3)))
                        .font(.system(.title, design: .rounded, weight: .medium)).monospacedDigit()
                    Text("% BAC · estimated").font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No BAC estimate")
                        .font(.system(.headline, design: .rounded))
                    Text("Sensor reading: \(reading.raw.value.formatted()) \(reading.raw.unit.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(.white.opacity(0.045), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var dateLabel: some View {
        Group {
            if let date = reading.recordedDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("Date unavailable")
            }
        }
        .font(.system(.subheadline, design: .rounded, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var sourceLabel: some View {
        if reading.isTestReading {
            Text("Test reading").font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.06), in: .capsule)
        }
    }
}
