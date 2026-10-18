import Foundation
import Observation

/// Local state only. Device events and peer answers remain explicit fixtures.
@MainActor @Observable
final class TriviaPreview: Identifiable {
    enum Phase: Equatable { case invitation, tap, breath, lobby, wheel, question, waiting, reveal, results }
    enum Participation { case undecided, checkingIn, joined, skipped }

    let id = UUID()
    // Local check-in fixture only; never a server measurement or a ranking input.
    private(set) var bac: Double?
    let roundCount = TriviaCategory.allCases.count
    let answerDuration: TimeInterval = 20
    private(set) var phase: Phase = .invitation
    private(set) var participation: Participation = .undecided
    private(set) var roundNumber = 1
    private(set) var category: TriviaCategory?
    private(set) var question: TriviaQuestion?
    private(set) var deadline: Date?
    private(set) var correctCount = 0
    private(set) var includesExamplePlayers = false
    private var usedCategories: Set<TriviaCategory> = []
    private var joinedIDs: [String] = []
    private var answers: [String: Int] = [:]
    private var scores: [String: Int] = [:]
    private var awards: [String: Int] = [:]

    private var readyIDs: [String] {
        (participation == .joined ? ["you"] : []) + (includesExamplePlayers ? ["example-0", "example-1", "example-2"] : [])
    }
    var availableCategories: [TriviaCategory] { TriviaCategory.allCases.filter { !usedCategories.contains($0) } }
    var playerCount: Int { joinedIDs.isEmpty ? readyIDs.count : joinedIDs.count }
    var selectedAnswer: Int? { answers["you"] }
    var totalPoints: Int { scores["you", default: 0] }
    var earnedPoints: Int { awards["you", default: 0] }
    var answeredCount: Int { answers.count }
    var spinnerID: String? { joinedIDs.isEmpty ? nil : joinedIDs[(roundNumber - 1) % joinedIDs.count] }
    var everyoneAnswered: Bool { !joinedIDs.isEmpty && joinedIDs.allSatisfy { answers[$0] != nil } }

    func setExamplePlayers(_ enabled: Bool) {
        guard phase == .invitation || phase == .lobby else { return }
        includesExamplePlayers = enabled
    }

    @discardableResult
    func join() -> Bool {
        guard phase == .invitation || (phase == .lobby && participation == .skipped) else { return false }
        participation = .checkingIn
        bac = nil
        phase = .tap
        return true
    }

    func skip() {
        guard [.invitation, .tap, .breath, .lobby].contains(phase) else { return }
        participation = .skipped
        bac = nil
        phase = .lobby
    }

    @discardableResult
    func previewTap() -> Bool {
        guard phase == .tap else { return false }
        phase = .breath
        return true
    }

    @discardableResult
    func completePreviewBreath(bac: Double? = nil) -> Bool {
        guard phase == .breath else { return false }
        if let bac, !bac.isFinite || bac < 0 { return false }
        self.bac = bac
        participation = .joined
        phase = .lobby
        return true
    }

    @discardableResult
    func begin(isHost: Bool) -> Bool {
        guard isHost, phase == .lobby, participation != .undecided,
              participation != .checkingIn, !readyIDs.isEmpty else { return false }
        joinedIDs = readyIDs
        phase = .wheel
        return true
    }

    @discardableResult
    func spin(playerID: String, category requested: TriviaCategory? = nil) -> Bool {
        guard playerID == spinnerID, phase == .wheel, category == nil,
              let next = requested ?? availableCategories.randomElement(),
              availableCategories.contains(next) else { return false }
        category = next
        usedCategories.insert(next)
        return true
    }

    @discardableResult
    func showQuestion(now: Date = .now) -> Bool {
        guard phase == .wheel, let category,
              let next = TriviaQuestion.bank.first(where: { $0.category == category }) else { return false }
        question = next
        deadline = now.addingTimeInterval(answerDuration)
        phase = .question
        return true
    }

    @discardableResult
    func answer(_ index: Int, now: Date = .now) -> Bool {
        recordAnswer(playerID: "you", index: index, now: now)
    }

    @discardableResult
    func recordAnswer(playerID: String, index: Int, now: Date = .now) -> Bool {
        guard phase == .question || phase == .waiting,
              joinedIDs.contains(playerID), answers[playerID] == nil,
              let question, question.choices.contains(where: { $0.id == index }),
              let deadline, now < deadline else { return false }
        answers[playerID] = index
        if playerID == "you" { phase = .waiting }
        return true
    }

    /// Called only by the explicit example-roster driver, never as network data.
    func submitExampleAnswers(now: Date = .now) {
        guard includesExamplePlayers, let question else { return }
        for (index, playerID) in joinedIDs.filter({ $0 != "you" }).enumerated() {
            let answer = index == 1 ? (question.correctIndex + 1) % 4 : question.correctIndex
            recordAnswer(playerID: playerID, index: answer, now: now)
        }
    }

    @discardableResult
    func revealIfReady(now: Date = .now) -> Bool {
        guard phase == .question || phase == .waiting, let question, let deadline,
              everyoneAnswered || now >= deadline else { return false }
        for playerID in joinedIDs {
            let award = answers[playerID] == question.correctIndex ? 1000 : 0
            awards[playerID] = award
            scores[playerID, default: 0] += award
        }
        if earnedPoints > 0 { correctCount += 1 }
        phase = .reveal
        return true
    }

    @discardableResult
    func revealExpired(now: Date = .now) -> Bool {
        guard let deadline, now >= deadline else { return false }
        return revealIfReady(now: now)
    }

    @discardableResult
    func next(isHost: Bool) -> Bool {
        guard isHost, phase == .reveal else { return false }
        if roundNumber == roundCount {
            phase = .results
        } else {
            roundNumber += 1
            category = nil
            question = nil
            deadline = nil
            answers = [:]
            awards = [:]
            phase = .wheel
        }
        return true
    }

    func secondsRemaining(now: Date) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    func remainingFraction(now: Date) -> Double {
        guard let deadline else { return 0 }
        return min(1, max(0, deadline.timeIntervalSince(now) / answerDuration))
    }

    func playerName(for id: String, currentName: String) -> String {
        if id == "you" { return currentName.isEmpty ? "You" : currentName }
        if let index = Int(id.replacingOccurrences(of: "example-", with: "")) { return "Example \(index + 1)" }
        return "Player"
    }

    func participantRows(playerName: String) -> [TriviaReadyPlayer] {
        let status: TriviaReadiness = switch participation {
        case .undecided: .notReady
        case .checkingIn: .checkingIn
        case .joined: .ready
        case .skipped: .sittingOut
        }
        var rows = [TriviaReadyPlayer(id: "you", name: self.playerName(for: "you", currentName: playerName), status: status, isYou: true)]
        if includesExamplePlayers {
            rows += ["example-0", "example-1", "example-2"].map {
                TriviaReadyPlayer(id: $0, name: self.playerName(for: $0, currentName: playerName), status: .ready, isYou: false)
            }
        }
        return rows
    }

    func standings(playerName: String) -> [TriviaStanding] {
        let ids = joinedIDs.isEmpty ? readyIDs : joinedIDs
        return ids.map {
            TriviaStanding(id: $0, name: self.playerName(for: $0, currentName: playerName),
                           points: scores[$0, default: 0], bac: $0 == "you" ? bac : nil,
                           isYou: $0 == "you", isExample: $0 != "you",
                           lastPoints: awards[$0, default: 0])
        }.sorted { $0.points == $1.points ? $0.id < $1.id : $0.points > $1.points }
    }
}

nonisolated enum TriviaReadiness {
    case ready, checkingIn, sittingOut, notReady
    var title: String {
        switch self {
        case .ready: "Ready"
        case .checkingIn: "Checking in"
        case .sittingOut: "Sitting out"
        case .notReady: "Not ready"
        }
    }
}

nonisolated struct TriviaReadyPlayer: Identifiable {
    let id: String
    let name: String
    let status: TriviaReadiness
    let isYou: Bool
}

nonisolated enum TriviaCategory: String, CaseIterable, Identifiable, Sendable {
    case world, science, history, sports, arts, entertainment
    var id: Self { self }
    var title: String {
        switch self {
        case .world: "Geography"
        case .science: "Science"
        case .history: "History"
        case .sports: "Sports"
        case .arts: "Arts"
        case .entertainment: "Entertainment"
        }
    }
    var shortTitle: String { self == .entertainment ? "Pop culture" : title }
}

nonisolated enum TriviaWheelMotion {
    static func delta(from start: Double, to end: Double) -> Double {
        let value = (end - start).truncatingRemainder(dividingBy: 360)
        return value > 180 ? value - 360 : value < -180 ? value + 360 : value
    }

    static func target(from rotation: Double, categoryIndex: Int, clockwise: Bool, turns: Int) -> Double {
        let landing = -Double(categoryIndex) * 60 - 30
        let revolutions = clockwise ? floor(rotation / 360) + Double(turns + 1) : ceil(rotation / 360) - Double(turns + 1)
        return revolutions * 360 + landing
    }
}

nonisolated struct TriviaStanding: Identifiable {
    let id: String
    let name: String
    let points: Int
    let bac: Double?
    let isYou: Bool
    let isExample: Bool
    let lastPoints: Int
}

nonisolated struct TriviaQuestion: Identifiable, Sendable {
    struct Choice: Identifiable, Sendable { let id: Int; let text: String }
    let category: TriviaCategory
    let prompt: String
    let answers: [String]
    let correctIndex: Int
    let explanation: String
    var id: TriviaCategory { category }
    var choices: [Choice] { answers.enumerated().map { Choice(id: $0.offset, text: $0.element) } }

    // Bundled general-knowledge questions for the local preview, not a live question service.
    static let bank: [Self] = [
        Self(category: .world, prompt: "Which is the largest ocean on Earth?",
             answers: ["Atlantic", "Pacific", "Indian", "Arctic"], correctIndex: 1,
             explanation: "The Pacific is the largest and deepest ocean on Earth."),
        Self(category: .science, prompt: "Which planet is the largest in our solar system?",
             answers: ["Earth", "Neptune", "Jupiter", "Saturn"], correctIndex: 2,
             explanation: "Jupiter is the largest planet in our solar system."),
        Self(category: .history, prompt: "Which civilization built Machu Picchu?",
             answers: ["Inca", "Maya", "Aztec", "Roman"], correctIndex: 0,
             explanation: "Machu Picchu was built by the Inca in the Andes."),
        Self(category: .sports, prompt: "How many players start on a soccer team?",
             answers: ["Nine", "Ten", "Twelve", "Eleven"], correctIndex: 3,
             explanation: "Each team starts with eleven players, including the goalkeeper."),
        Self(category: .arts, prompt: "Who painted The Starry Night?",
             answers: ["Claude Monet", "Vincent van Gogh", "Pablo Picasso", "Salvador Dalí"], correctIndex: 1,
             explanation: "Vincent van Gogh painted The Starry Night in 1889."),
        Self(category: .entertainment, prompt: "Which movie introduced Woody and Buzz Lightyear?",
             answers: ["Monsters, Inc.", "Finding Nemo", "Toy Story", "Cars"], correctIndex: 2,
             explanation: "Woody and Buzz first appeared together in Toy Story.")
    ]
}
