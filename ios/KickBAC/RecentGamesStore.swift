import Foundation
import Observation

@MainActor @Observable
final class RecentGamesStore {
    private(set) var owner: String?
    private(set) var page: GameResultPage?
    private(set) var message: String?
    private(set) var isLoading = false
    private var generation = UUID()

    func switchOwner(_ owner: String?) {
        guard self.owner != owner else { return }
        generation = UUID()
        self.owner = owner
        page = nil
        message = nil
        isLoading = false
    }

    func load(loadMore: Bool = false, fetch: (Int) async throws -> GameResultPage) async {
        guard let owner, !isLoading else { return }
        if loadMore && page?.hasMore != true { return }
        let previous = loadMore ? page : nil
        let offset = previous.map { $0.offset + $0.limit } ?? 0
        let requestGeneration = generation
        isLoading = true
        message = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let loaded = try await fetch(offset)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            guard loaded.items.allSatisfy({ $0.userID == owner }),
                  loaded.offset == offset, (1...100).contains(loaded.limit) else {
                throw KickBACAPI.APIError.invalidResponse
            }
            var seen = Set<String>()
            let items = ((previous?.items ?? []) + loaded.items).filter { seen.insert($0.id).inserted }
            page = GameResultPage(items: items, limit: loaded.limit, offset: loaded.offset, hasMore: loaded.hasMore)
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            message = "Couldn't load your games. Try again."
        }
    }
}
