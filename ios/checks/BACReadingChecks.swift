import Foundation

// swiftc ios/KickBAC/BACReading.swift ios/checks/BACReadingChecks.swift -o /tmp/kickbac-bac-checks
@main
struct BACReadingChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let readings = [
            BACReading(value: 0.04, date: day), BACReading(value: 0.05, date: day),
            BACReading(value: 0.09, date: day), BACReading(value: 0.20, date: yesterday),
            BACReading(value: 0.25, date: tomorrow)
        ]
        let summary = DailyBACSummary(readings: readings, day: day, calendar: calendar)
        precondition(abs(summary.average! - 0.06) < 0.000001)
        precondition(summary.high == 0.09)
        let empty = DailyBACSummary(readings: [], day: day, calendar: calendar)
        precondition(empty.average == nil && empty.high == nil)
        let zero = DailyBACSummary(readings: [BACReading(value: 0, date: day)], day: day, calendar: calendar)
        precondition(zero.average == 0 && zero.high == 0)

        let boundaries: [(Double, BACBand)] = [
            (0, .notDetected), (0.001, .detected), (0.0199, .detected),
            (0.02, .judgmentAffected), (0.0499, .judgmentAffected),
            (0.05, .coordinationAffected), (0.0799, .coordinationAffected),
            (0.08, .impaired), (0.1499, .impaired), (0.15, .highImpairment), (0.40, .highImpairment)
        ]
        for (value, band) in boundaries {
            precondition(BACBand(value: value) == band)
            let angle = band.angle(for: value)
            let start = 135 + Double(band.rawValue) * 45
            precondition(angle >= start + 5 && angle <= start + 40)
        }
        print("BAC checks passed: daily summaries, empty readings, band boundaries, and gauge positions.")
    }
}
