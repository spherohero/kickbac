import SwiftUI

struct TriviaPodium: View {
    let rows: [TriviaStanding]
    let photoData: Data?
    let includesExamples: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The podium").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                if includesExamples {
                    Text("Example roster · local points only").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .bottom, spacing: 10) {
                    pillar(player(at: 1), place: 2, height: 124, color: Color(red: 0.72, green: 0.75, blue: 0.82))
                    pillar(player(at: 0), place: 1, height: 172, color: Color(red: 0.94, green: 0.80, blue: 0.32))
                    pillar(player(at: 2), place: 3, height: 98, color: Color(red: 0.83, green: 0.57, blue: 0.40))
                }
                .padding(.top, 12)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Leaderboard").font(.system(.title2, design: .rounded, weight: .semibold))
                    Spacer(minLength: 0)
                }
                ForEach(rows) { row in standingRow(row) }
            }
        }
    }

    private func player(at index: Int) -> TriviaStanding? {
        rows.indices.contains(index) ? rows[index] : nil
    }

    private func rank(_ row: TriviaStanding) -> Int {
        (rows.firstIndex { $0.points == row.points } ?? 0) + 1
    }

    private func pillar(_ row: TriviaStanding?, place: Int, height: CGFloat, color: Color) -> some View {
        VStack(spacing: 12) {
            Group {
                if let row {
                    ProfileAvatar(photoData: row.isYou ? photoData : nil, side: place == 1 ? 60 : 48)
                    Text(row.name).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(2).multilineTextAlignment(.center)
                } else {
                    Color.clear.frame(height: place == 1 ? 60 : 48)
                    Text("—").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 12) {
                Text(row.map { String(rank($0)) } ?? String(place))
                    .font(.system(size: place == 1 ? 54 : 42, weight: .bold, design: .rounded))
                Text(row.map { $0.points.formatted() } ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                if row != nil { Text("points").font(.caption) }
            }
            .foregroundStyle(row == nil ? color.opacity(0.45) : .black)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .top).padding(.top, 20)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                    .fill(LinearGradient(colors: [color.opacity(row == nil ? 0.1 : 1), color.opacity(row == nil ? 0.04 : 0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: -3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.map {
            "\($0.name), rank \(rank($0)), \($0.points) points, \($0.bac.map { "BAC \($0.formatted(.number.precision(.fractionLength(3))))" } ?? "BAC unavailable")"
        } ?? "Place \(place), no player")
    }

    private func standingRow(_ row: TriviaStanding) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                playerLabel(row)
                Spacer(minLength: 8)
                statistic("Points", value: row.points.formatted())
                statistic("BAC", value: row.bac.map { $0.formatted(.number.precision(.fractionLength(3))) } ?? "—")
            }
            VStack(alignment: .leading, spacing: 16) {
                playerLabel(row)
                HStack(spacing: 24) {
                    statistic("Points", value: row.points.formatted())
                    statistic("BAC", value: row.bac.map { $0.formatted(.number.precision(.fractionLength(3))) } ?? "—")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(row.isYou ? 0.09 : 0.035), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func playerLabel(_ row: TriviaStanding) -> some View {
        HStack(spacing: 10) {
            Text("\(rank(row))").font(.headline).monospacedDigit().frame(minWidth: 18)
            ProfileAvatar(photoData: row.isYou ? photoData : nil, side: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                if row.isYou { Text("You").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
