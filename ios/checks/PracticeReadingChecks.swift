import Foundation

@main
struct PracticeReadingChecks {
    @MainActor static func main() throws {
        precondition(AppReadingTrigger.nfc.makeValue() == 0,
                     "An NFC tap must produce a simulated 0.00 app reading")
        precondition((0.01...0.12).contains(AppReadingTrigger.touch.makeValue()),
                     "Holding the circle must run the random-value demo")
        let directory = FileManager.default.temporaryDirectory.appending(path: "kickbac-practice-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PracticeReadingStore(directory: directory)
        store.switchOwner("account-a")
        let first = try store.save(value: 0.04, duration: 1.25, date: Date(timeIntervalSince1970: 1000))
        let second = try store.save(value: 0.09, duration: 6, date: Date(timeIntervalSince1970: 2000))
        precondition(first.id != second.id && store.readings.map(\.id) == [second.id, first.id])
        let restored = PracticeReadingStore(directory: directory)
        restored.switchOwner("account-a")
        precondition(restored.readings.map(\.id) == [second.id, first.id])
        precondition(restored.readings.last?.duration == 1.25)
        restored.switchOwner("account-b")
        precondition(restored.readings.isEmpty)
        try restored.save(value: 0.02, duration: 2)
        restored.switchOwner(nil)
        precondition(restored.readings.isEmpty, "Account readings leaked into guest mode")
        let guest = try restored.save(value: 0.03, duration: 0.2)
        restored.switchOwner("account-a")
        precondition(restored.readings.count == 2)
        restored.switchOwner(nil)
        precondition(restored.readings.map(\.id) == [guest.id])
        restored.switchOwner("account-a")
        for value in [-0.1, 0.31, Double.nan, Double.infinity] {
            do { try restored.save(value: value, duration: 2); preconditionFailure("Invalid practice value was saved") }
            catch PracticeReadingStore.SaveError.invalid { }
        }
        for duration in [0, -1, 61, Double.nan, Double.infinity] {
            do { try restored.save(value: 0.04, duration: duration); preconditionFailure("Invalid duration was saved") }
            catch PracticeReadingStore.SaveError.invalid { }
        }
        precondition(restored.readings.count == 2)

        let blocked = directory.appending(path: "blocked")
        try Data("keep".utf8).write(to: blocked)
        let failedStore = PracticeReadingStore(directory: blocked)
        do { try failedStore.save(value: 0.04, duration: 1); preconditionFailure("Unwritable result reported as saved") }
        catch { precondition(failedStore.readings.isEmpty && failedStore.message != nil) }

        let damagedDirectory = directory.appending(path: "damaged")
        let original = PracticeReadingStore(directory: damagedDirectory)
        try original.save(value: 0.04, duration: 1)
        let file = try FileManager.default.contentsOfDirectory(at: damagedDirectory, includingPropertiesForKeys: nil).first!
        let damaged = Data("unreadable fixture".utf8)
        try damaged.write(to: file)
        let damagedStore = PracticeReadingStore(directory: damagedDirectory)
        precondition(!damagedStore.canSave && damagedStore.message != nil)
        do { try damagedStore.save(value: 0.04, duration: 1); preconditionFailure("Overwrote unreadable history") }
        catch PracticeReadingStore.SaveError.unavailable { }
        let retained = try Data(contentsOf: file)
        precondition(retained == damaged)
        print("Practice checks passed: durable local saves, actual gesture duration, account/guest isolation, invalid data, write failures and unreadable-cache preservation.")
    }
}
