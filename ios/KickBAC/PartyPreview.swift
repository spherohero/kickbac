import Foundation
import Observation

// Deliberately local and ephemeral. Never arm a device, submit a result, or cache membership here.
@MainActor @Observable
final class PartyPreview {
    enum Role: String, CaseIterable, Identifiable {
        case host = "Host", guest = "Guest"
        var id: Self { self }
    }

    struct Room: Equatable {
        var name: String
        var deviceID: String
        var role: Role
    }

    static let code = "KICK26"
    private(set) var room: Room?
    private(set) var ongoingGame: PartyGame?
    private(set) var trivia: TriviaPreview?

    static func validName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.unicodeScalars.count)
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    @discardableResult
    func create(name: String, deviceID: String = "kb-demo-01") -> Bool {
        let deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validName(name), DeviceTarget.isValidID(deviceID) else { return false }
        room = Room(name: name.trimmingCharacters(in: .whitespacesAndNewlines), deviceID: deviceID, role: .host)
        ongoingGame = nil
        trivia = nil
        return true
    }

    @discardableResult
    func join(code: String) -> Bool {
        guard code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.code else { return false }
        previewTap()
        return true
    }

    func previewTap() {
        room = Room(name: "Party", deviceID: "kb-demo-01", role: .guest)
        ongoingGame = nil
        trivia = nil
    }

    func viewAs(_ role: Role) { room?.role = role }
    func showExampleGame(_ game: PartyGame?) {
        ongoingGame = room == nil ? nil : game
        trivia = ongoingGame == .trivia ? TriviaPreview() : nil
    }

    func finishTrivia() {
        guard trivia?.phase == .results else { return }
        ongoingGame = nil
    }

    func leave() {
        room = nil
        ongoingGame = nil
        trivia = nil
    }
}

nonisolated enum PartyGame: String, CaseIterable, Identifiable {
    case trivia, pictionary
    var id: Self { self }
    var title: String { self == .trivia ? "Trivia" : "Pictionary" }
    var iconAsset: String { self == .trivia ? "PartyTrivia" : "PartyPictionary" }
    var invitation: String { self == .trivia ? "Who knows it all?" : "Draw a little. Guess a lot." }
    var detail: String { self == .trivia ? "Questions, answers, and a little friendly competition." : "One person draws. Everyone else takes a guess." }
}
