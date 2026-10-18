import CryptoKit
import Foundation
import Observation

enum AppReadingTrigger {
    case nfc, touch

    func makeValue() -> Double {
        self == .nfc ? 0 : Double(Int.random(in: 10...120)) / 1000
    }
}

nonisolated struct PracticeReading: Codable, Identifiable, Sendable {
    let id: UUID
    let value: Double
    let date: Date
    let duration: TimeInterval

    var reading: BACReading { BACReading(value: value, date: date) }
    var isValid: Bool {
        value.isFinite && (0...0.3).contains(value)
            && duration.isFinite && (0.01...60).contains(duration)
            && date.timeIntervalSince1970.isFinite
    }
}

// Local simulated results never enter the device/session upload contract.
@MainActor @Observable
final class PracticeReadingStore {
    private(set) var readings: [PracticeReading] = []
    private(set) var owner: String?
    private(set) var message: String?
    private(set) var canSave = true
    private let directory: URL
    private var hasLoaded = false

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "PracticeReadings")) {
        self.directory = directory
        switchOwner(nil)
    }

    func switchOwner(_ owner: String?) {
        guard !hasLoaded || self.owner != owner else { return }
        hasLoaded = true
        self.owner = owner
        readings = []; message = nil; canSave = true
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode([PracticeReading].self, from: Data(contentsOf: url))
            guard saved.allSatisfy(\.isValid), Set(saved.map(\.id)).count == saved.count else { throw SaveError.invalid }
            readings = saved.sorted { $0.date > $1.date }
        } catch {
            canSave = false
            message = "Couldn't restore your readings. Reopen the app before saving another."
        }
    }

    @discardableResult
    func save(value: Double, duration: TimeInterval, date: Date = .now) throws -> PracticeReading {
        guard canSave else { throw SaveError.unavailable }
        let result = PracticeReading(id: UUID(), value: value, date: date, duration: duration)
        guard result.isValid else { throw SaveError.invalid }
        let updated = ([result] + readings).sorted { $0.date > $1.date }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            readings = updated
            message = nil
            return result
        } catch {
            message = "Couldn't save this reading."
            throw error
        }
    }

    private func fileURL() -> URL {
        let scope = owner.map { "user:" + $0 } ?? "guest"
        let key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }

    enum SaveError: Error { case invalid, unavailable }
}
