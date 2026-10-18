import Foundation

@main
struct NearbyTriviaChecks {
    @MainActor static func main() throws {
        let host = TriviaPreview()
        host.usesNearby = true; host.isNearbyHost = true; host.localPlayerID = "host"
        host.nearbyPlayers = [.init(id: "host", name: "Liam", participation: .undecided)]
        let guest = TriviaPreview()
        guest.usesNearby = true; guest.localPlayerID = "guest"
        guest.nearbyPlayers = [.init(id: "guest", name: "Nicholas", participation: .undecided)]
        host.nearbyDidChange = {
            let data = try! JSONEncoder().encode(host.snapshot())
            guest.apply(try! JSONDecoder().decode(TriviaPreview.Snapshot.self, from: data))
        }
        guest.sendNearbyAction = { kind, index in
            host.updateNearbyPlayer(id: "guest", name: "Nicholas", participation: guest.participation)
            if kind == "spin" { host.spin(playerID: "guest") }
            if kind == "answer", let index { host.recordAnswer(playerID: "guest", index: index) }
        }
        precondition(host.join() && host.previewTap() && host.completePreviewBreath())
        precondition(!host.canStart && !host.begin(isHost: true), "Host must wait for a second real player")
        precondition(guest.join() && guest.previewTap() && guest.completePreviewBreath())
        precondition(host.canStart && host.participantRows(playerName: "Liam").count == 2)
        precondition(host.begin(isHost: true) && guest.phase == .wheel)
        for round in 1...6 {
            precondition(host.roundNumber == round && guest.roundNumber == round)
            if host.spinnerID == "host" { precondition(host.spin(playerID: "host")) }
            else { precondition(guest.spin(playerID: "guest")) }
            precondition(host.category == guest.category && host.category != nil)
            precondition(host.showQuestion() && guest.phase == .question)
            precondition(host.question?.prompt == guest.question?.prompt && host.deadline == guest.deadline)
            let correct = host.question!.correctIndex
            // Exercise guest-first and host-first answer ordering.
            if round % 2 == 0 {
                precondition(host.answer(correct)); precondition(guest.answer((correct + 1) % 4))
            } else {
                precondition(guest.answer((correct + 1) % 4)); precondition(host.answer(correct))
            }
            precondition(host.everyoneAnswered && host.revealIfReady())
            precondition(guest.phase == .reveal && host.totalPoints == round * 1000 && guest.totalPoints == 0)
            precondition(!guest.next(isHost: true), "Guest cannot advance the authoritative round")
            precondition(host.next(isHost: true))
        }
        precondition(host.phase == .results && guest.phase == .results)
        precondition(host.standings(playerName: "Liam").map(\.points) == guest.standings(playerName: "Nicholas").map(\.points))
        precondition(guest.standings(playerName: "Nicholas").contains { $0.name == "Liam" && !$0.isExample })
        print("Nearby trivia checks passed: two real players, encoded snapshots, alternating turns, both answer orders, shared deadlines, scores and podium")
    }
}
