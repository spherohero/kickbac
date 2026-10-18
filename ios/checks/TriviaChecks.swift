import Foundation

@main
struct TriviaChecks {
    @MainActor
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        let game = joinedGame()
        assert(game.begin(isHost: true))
        assert(game.spinnerID == "you")
        assert(!game.spin(playerID: "someone-else", category: .science))
        assert(game.spin(playerID: "you", category: .science))
        assert(!game.spin(playerID: "you", category: .history))
        assert(game.showQuestion(now: now))
        assert(game.answer(2, now: now.addingTimeInterval(2)))
        assert(game.phase == .waiting && game.totalPoints == 0 && game.earnedPoints == 0,
               "An answer locks without revealing correctness or points")
        assert(!game.answer(2, now: now.addingTimeInterval(3)))
        assert(game.revealIfReady(now: now.addingTimeInterval(3)))
        assert(game.phase == .reveal && game.totalPoints == 1000 && game.correctCount == 1)
        assert(!game.revealIfReady(now: now.addingTimeInterval(4)))
        assert(game.totalPoints == 1000)
        assert(!game.next(isHost: false))
        assert(game.next(isHost: true))
        assert(!game.spin(playerID: "you", category: .science))
        for category in TriviaCategory.allCases where category != .science {
            assert(game.spin(playerID: "you", category: category))
            assert(game.showQuestion(now: now))
            assert(game.revealExpired(now: now.addingTimeInterval(20)))
            assert(!game.answer(0, now: now.addingTimeInterval(21)))
            assert(game.next(isHost: true))
        }
        assert(game.phase == .results && game.totalPoints == 1000)
        let rows = game.standings(playerName: "Liam")
        assert(rows.count == 1 && rows[0].name == "Liam" && rows[0].bac == nil)

        let shared = joinedGame()
        shared.setExamplePlayers(true)
        assert(shared.begin(isHost: true))
        assert(shared.spin(playerID: "you", category: .world) && shared.showQuestion(now: now))
        assert(shared.answer(1, now: now.addingTimeInterval(1)))
        assert(!shared.revealIfReady(now: now.addingTimeInterval(2)), "Wait for the other players")
        assert(shared.recordAnswer(playerID: "example-0", index: 1, now: now.addingTimeInterval(3)))
        assert(!shared.recordAnswer(playerID: "example-0", index: 1, now: now.addingTimeInterval(4)))
        assert(!shared.revealIfReady(now: now.addingTimeInterval(5)))
        shared.submitExampleAnswers(now: now.addingTimeInterval(6))
        assert(shared.revealIfReady(now: now.addingTimeInterval(6)))
        let round = shared.standings(playerName: "Liam")
        assert(round.first { $0.isYou }?.lastPoints == 1000)
        assert(round.first { $0.id == "example-1" }?.lastPoints == 0)
        assert(shared.next(isHost: true) && shared.spinnerID == "example-0")
        assert(!shared.spin(playerID: "you", category: .history), "Only the selected player spins")
        assert(shared.spin(playerID: "example-0", category: .history))
        assert(shared.showQuestion(now: now))
        assert(shared.answer(0, now: now.addingTimeInterval(1)))
        assert(shared.revealExpired(now: now.addingTimeInterval(20)))
        assert(shared.totalPoints == 2000, "A timely answer is still scored when peers time out")
        assert(shared.standings(playerName: "Liam").filter { !$0.isYou }.allSatisfy { $0.lastPoints == 0 })

        let spectator = TriviaPreview()
        spectator.skip()
        assert(spectator.participantRows(playerName: "Liam").first?.status == .sittingOut)
        assert(!spectator.begin(isHost: true))
        spectator.setExamplePlayers(true)
        assert(spectator.begin(isHost: true) && spectator.spinnerID == "example-0")
        assert(!spectator.spin(playerID: "you", category: .arts))
        assert(spectator.spin(playerID: "example-0", category: .arts) && spectator.showQuestion(now: now))
        assert(!spectator.answer(1, now: now))
        assert(spectator.standings(playerName: "Liam").allSatisfy { !$0.isYou && $0.isExample && $0.bac == nil })

        let retry = joinedGame()
        assert(retry.begin(isHost: true) && retry.spin(playerID: "you", category: .world))
        assert(retry.showQuestion(now: now))
        assert(!retry.answer(99, now: now) && retry.phase == .question)
        assert(!retry.answer(1, now: now.addingTimeInterval(20)))
        assert(retry.revealExpired(now: now.addingTimeInterval(20)))
        assert(retry.totalPoints == 0)
        assert(Set(TriviaQuestion.bank.map(\.category)) == Set(TriviaCategory.allCases))
        assert(TriviaQuestion.bank.allSatisfy { $0.answers.count == 4 && (0..<4).contains($0.correctIndex) })
        assert(retry.remainingFraction(now: now.addingTimeInterval(-1)) == 1)
        assert(retry.remainingFraction(now: now.addingTimeInterval(10)) == 0.5)
        assert(retry.remainingFraction(now: now.addingTimeInterval(21)) == 0)
        assert(TriviaWheelMotion.delta(from: 179, to: -179) == 2)
        assert(TriviaWheelMotion.delta(from: -179, to: 179) == -2)
        for index in 0..<6 {
            for clockwise in [true, false] {
                let origin = 725.0
                let target = TriviaWheelMotion.target(from: origin, categoryIndex: index, clockwise: clockwise, turns: 3)
                assert(clockwise ? target > origin : target < origin)
                let landing = (target + Double(index) * 60 + 30).truncatingRemainder(dividingBy: 360)
                assert(abs(landing) < 0.001, "Selected wedge must stop under the pointer")
            }
        }
        print("Trivia checks passed: check-in, readiness, rotating spinner, locked answers, all-voted/deadline reveal, per-player awards, replay and privacy")
    }

    @MainActor
    static func joinedGame() -> TriviaPreview {
        let game = TriviaPreview()
        assert(game.phase == .invitation && !game.begin(isHost: true))
        game.skip()
        assert(game.join())
        assert(game.participantRows(playerName: "Liam").first?.status == .checkingIn)
        assert(!game.completePreviewBreath())
        assert(game.previewTap() && game.completePreviewBreath())
        assert(game.phase == .lobby && game.participation == .joined && game.bac == nil)
        assert(game.participantRows(playerName: "Liam").first?.status == .ready)
        assert(!game.begin(isHost: false))
        return game
    }
}
