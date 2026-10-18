import Foundation

@main struct RecentGamesChecks {
    @MainActor static func main() async throws {
        let store = RecentGamesStore()
        let owner = "sms|games-owner"
        store.switchOwner(owner)
        let fixture = Data(#"{"items":[{"result_id":"a","user_id":"sms|games-owner","game_id":"trivia","score":8,"outcome":"win","data":{"arbitrary_party_name":"Not a verified party"},"awarded_points":10,"source":"client_reported","scoring_policy":"completion_v1","created_at":"2026-10-18T03:00:05.123Z"}],"limit":2,"offset":0,"has_more":true}"#.utf8)
        let decoded = try JSONDecoder().decode(GameResultPage.self, from: fixture)
        precondition(decoded.items[0].score == 8 && decoded.items[0].awardedPoints == 10)
        precondition(decoded.items[0].gameTitle == "Trivia" && decoded.items[0].outcome.title == "Won")
        precondition(decoded.items[0].recordedDate != nil)
        await store.load { offset in precondition(offset == 0); return decoded }
        await store.load(loadMore: true) { offset in
            precondition(offset == 2)
            return page([game("a", owner), game("b", owner)], offset: 2)
        }
        precondition(store.page?.items.map(\.id) == ["a", "b"])
        await store.load(loadMore: true) { _ in preconditionFailure("Requested past final page") }
        await store.load { _ in throw URLError(.notConnectedToInternet) }
        precondition(store.page?.items.count == 2 && store.message != nil && !store.isLoading)
        await store.load { _ in page([game("foreign", "another-owner")]) }
        precondition(store.page?.items.map(\.id) == ["a", "b"] && store.message != nil)
        await store.load { _ in page([], offset: 100) }
        precondition(store.page?.items.count == 2 && store.message != nil)
        await store.load { _ in page([]) }
        precondition(store.page?.items.isEmpty == true && store.message == nil)

        var resume: CheckedContinuation<GameResultPage, Never>?
        let oldLoad = Task {
            await store.load { _ in await withCheckedContinuation { resume = $0 } }
        }
        while resume == nil { await Task.yield() }
        await store.load { _ in preconditionFailure("Duplicated in-flight request") }
        store.switchOwner("new-owner")
        precondition(store.page == nil && store.message == nil && !store.isLoading)
        await store.load { _ in page([game("new", "new-owner")]) }
        resume!.resume(returning: page([game("old", owner)]))
        await oldLoad.value
        precondition(store.page?.items.map(\.id) == ["new"] && !store.isLoading)
        store.switchOwner(nil)
        precondition(store.page == nil && store.owner == nil)
        await store.load { _ in preconditionFailure("Fetched while signed out") }
        print("Recent games checks passed: decoding, awarded points vs score, pagination/deduplication, retries, empty state, owner isolation, stale loads and sign-out. No party/check-in data invented.")
    }

    private static func game(_ id: String, _ owner: String) -> APIGameResult {
        APIGameResult(id: id, userID: owner, gameID: "pictionary", score: 2,
                      outcome: .completed, awardedPoints: 10, createdAt: "2026-10-18T03:00:05Z")
    }

    private static func page(_ games: [APIGameResult], offset: Int = 0) -> GameResultPage {
        GameResultPage(items: games, limit: 2, offset: offset, hasMore: false)
    }
}
