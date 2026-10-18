import Foundation

struct BACReading: Identifiable {
    let id = UUID()
    let value: Double
    let date: Date

    var band: BACBand { BACBand(value: value) }
}

struct DailyBACSummary {
    let average: Double?
    let high: Double?

    init(readings: [BACReading], day: Date = .now, calendar: Calendar = .current) {
        let today = readings.filter { calendar.isDate($0.date, inSameDayAs: day) }
        average = today.isEmpty ? nil : today.reduce(0) { $0 + $1.value } / Double(today.count)
        high = today.map(\.value).max()
    }
}

// Display bands follow NHTSA's published BAC effects, not a drinking target or driving clearance.
// https://www.nhtsa.gov/risky-driving/drunk-driving
enum BACBand: Int, CaseIterable {
    case notDetected, detected, judgmentAffected, coordinationAffected, impaired, highImpairment

    init(value: Double) {
        switch value {
        case ...0: self = .notDetected
        case ..<0.02: self = .detected
        case ..<0.05: self = .judgmentAffected
        case ..<0.08: self = .coordinationAffected
        case ..<0.15: self = .impaired
        default: self = .highImpairment
        }
    }

    var title: String {
        switch self {
        case .notDetected: "Not detected"
        case .detected: "Alcohol detected"
        case .judgmentAffected: "Judgment affected"
        case .coordinationAffected: "Coordination affected"
        case .impaired: "Impaired"
        case .highImpairment: "High impairment"
        }
    }

    func angle(for value: Double) -> Double {
        let limits: (Double, Double)
        switch self {
        case .notDetected: limits = (0, 0)
        case .detected: limits = (0, 0.02)
        case .judgmentAffected: limits = (0.02, 0.05)
        case .coordinationAffected: limits = (0.05, 0.08)
        case .impaired: limits = (0.08, 0.15)
        case .highImpairment: limits = (0.15, 0.30)
        }
        let fraction = limits.1 > limits.0 ? min(max((value - limits.0) / (limits.1 - limits.0), 0), 1) : 0.5
        return 135 + Double(rawValue) * 45 + 5 + fraction * 35
    }
}
