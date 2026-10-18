import SwiftUI

struct ProfileHistoryView: View {
    let session: AuthSession
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeReadingStore.self) private var practice

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if session.isRestoring {
                        ProgressView("Loading your readings")
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    } else if !session.isSignedIn && practice.readings.isEmpty {
                        placeholder("Your readings live here", detail: "Sign in to see your saved readings.")
                        action("Sign in", perform: onSignIn)
                    } else if session.history != nil || !practice.readings.isEmpty {
                        let readings = savedReadings
                        if let message = session.apiMessage { retryNotice(message) }
                        if readings.isEmpty {
                            placeholder(session.history?.hasMore == true ? "No BAC readings loaded" : "No readings yet",
                                        detail: session.history?.hasMore == true ? "Load more to check earlier readings." : "Readings with a BAC estimate will appear here.")
                        } else {
                            ForEach(readings) { reading in
                                ProfileReadingRow(reading: reading)
                                if reading.id != readings.last?.id {
                                    Divider().overlay(.white.opacity(0.06))
                                }
                            }
                        }
                        if session.history?.hasMore == true {
                            action(session.isCheckingAPI ? "Loading…" : "Load more") {
                                Task { await session.checkAPI(loadMore: true) }
                            }
                            .padding(.top, 24)
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

    private var savedReadings: [HistoryReading] {
        let deviceReadings = (session.history?.items ?? []).compactMap { reading -> HistoryReading? in
            guard let value = reading.bacReading?.value, let date = reading.recordedDate else { return nil }
            return HistoryReading(id: "device-" + reading.id, value: value, date: date, isSimulated: false)
        }
        let localReadings = practice.readings.map {
            HistoryReading(id: "practice-" + $0.id.uuidString, value: $0.value, date: $0.date, isSimulated: true)
        }
        return (deviceReadings + localReadings).sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
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

private struct HistoryReading: Identifiable {
    let id: String
    let value: Double
    let date: Date
    let isSimulated: Bool
}

private struct ProfileReadingRow: View {
    let reading: HistoryReading
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(reading.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(reading.date, format: .dateTime.hour().minute())
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(reading.value, format: .number.precision(.fractionLength(3)))
                    .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
                Text("% BAC")
                    .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}
