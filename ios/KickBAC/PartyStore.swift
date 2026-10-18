import CryptoKit
import Foundation
import Observation

struct PartyGameInvitations {
    private var presented: Set<String> = []

    mutating func next(in games: [APIPartyGame], partyID: String, canPresent: Bool) -> APIPartyGame? {
        guard canPresent, let game = games.first(where: {
            $0.partyID == partyID && $0.state == "OPEN" && $0.gameID == "trivia"
                && $0.deviceID != nil && !presented.contains($0.id)
        }) else { return nil }
        presented.insert(game.id)
        return game
    }
}

@MainActor @Observable
final class PartyStore {
    private(set) var owner: String?
    private(set) var party: APIParty?
    private(set) var conflictingParties: [APIParty] = []
    private(set) var conflictsHaveMore = false
    private(set) var pending: PartyWrite?
    private(set) var lastCheckIn: APICheckIn?
    private(set) var message: String?
    private(set) var isBusy = false
    private(set) var canDiscardPending = false
    private(set) var parties: [APIParty] = []
    private(set) var hasMoreParties = false
    private(set) var isLoadingParties = false
    private(set) var partiesMessage: String?
    private var partiesOffset = 0
    private var generation = UUID()
    private let directory: URL
    private var selectedID: String?
    private var cacheUnavailable = false
    private struct Saved: Codable { let selectedID: String?; let pending: PartyWrite? }

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Parties")) { self.directory = directory }
    func switchOwner(_ owner: String?) {
        guard self.owner != owner else { return }
        generation = UUID(); self.owner = owner
        cacheUnavailable = false
        conflictingParties = []; conflictsHaveMore = false
        party = nil; pending = nil; lastCheckIn = nil; message = nil; isBusy = false; selectedID = nil; canDiscardPending = false
        parties = []; hasMoreParties = false; isLoadingParties = false; partiesMessage = nil; partiesOffset = 0
        guard let owner else { return }
        do {
            let url = cacheURL(owner)
            if FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
                try saved.pending?.validate()
                guard saved.selectedID.map({ UUID(uuidString: $0) != nil }) ?? true else { throw KickBACAPI.APIError.invalidResponse }
                selectedID = saved.selectedID; pending = saved.pending
            }
        } catch {
            cacheUnavailable = true
            message = "Couldn't restore party requests. Reopen the app before starting a new request."; isBusy = true
        }
    }

    func restoreCurrent(quiet: Bool = false, fetch: () async throws -> APIParty?) async {
        guard owner != nil, !isBusy, pending == nil else { return }
        let ticket = generation
        if !quiet { isBusy = true }
        defer { if !quiet, generation == ticket { isBusy = false } }
        do {
            let loaded = try await fetch()
            guard generation == ticket, !quiet || (!isBusy && pending == nil) else { return }
            if let loaded { try validateParty(loaded); guard loaded.state == "OPEN" else { throw KickBACAPI.APIError.invalidResponse } }
            if party?.id != loaded?.id { lastCheckIn = nil }
            party = loaded; selectedID = loaded?.id
            conflictingParties = []; conflictsHaveMore = false
            try persist()
        } catch { if generation == ticket { captureConflict(error); message = Self.failure(error) } }
    }

    private func captureConflict(_ error: Error) {
        guard case .activePartyConflict(let rows, let more) = error as? KickBACAPI.APIError,
              rows.allSatisfy({ $0.state == "OPEN" && UUID(uuidString: $0.id) != nil }) else { return }
        conflictingParties = rows; conflictsHaveMore = more
    }

    @discardableResult
    func endConflictingParties(send: (APIParty) async throws -> APIParty) async -> Bool {
        guard owner != nil, !isBusy, !conflictingParties.isEmpty, !conflictsHaveMore,
              pending == nil || canDiscardPending else { return false }
        if pending != nil { discardRejectedRequest(); guard pending == nil else { return false } }
        let ticket = generation
        isBusy = true
        defer { if generation == ticket { isBusy = false } }
        do {
            for row in conflictingParties {
                let result = try await send(row)
                guard generation == ticket else { return false }
                guard result.id == row.id,
                      row.isHost ? (result.state == "CLOSED" && result.deviceID == nil) : result.role == "member" else { throw KickBACAPI.APIError.invalidResponse }
                conflictingParties.removeAll { $0.id == row.id }
            }
            party = nil; selectedID = nil; lastCheckIn = nil; message = nil
            try persist()
            return true
        } catch { if generation == ticket { message = Self.failure(error) }; return false }
    }

    func restore(fetch: (String) async throws -> APIParty) async {
        guard let selectedID else { return }
        await update(expectedID: selectedID, allowPendingRead: true) { try await fetch(selectedID) }
    }

    func loadParties(more: Bool = false, fetch: (Int) async throws -> PartyPage<APIParty>) async {
        guard owner != nil, !isLoadingParties, !more || hasMoreParties else { return }
        let ticket = generation
        let offset = more ? partiesOffset : 0
        isLoadingParties = true; partiesMessage = nil
        defer { if generation == ticket { isLoadingParties = false } }
        do {
            let page = try await fetch(offset)
            guard generation == ticket else { return }
            try Task.checkCancellation()
            guard page.offset == offset, (1...100).contains(page.limit),
                  !page.hasMore || !page.items.isEmpty else { throw KickBACAPI.APIError.invalidResponse }
            try page.items.forEach(validateParty)
            var seen = Set<String>()
            parties = ((more ? parties : []) + page.items).filter { seen.insert($0.id).inserted }
            hasMoreParties = page.hasMore
            partiesOffset = page.offset + page.limit
        } catch {
            if generation == ticket { partiesMessage = Self.failure(error) }
        }
    }

    func showEntry() {
        guard !cacheUnavailable else { return }
        generation = UUID()
        party = nil; lastCheckIn = nil; message = nil; isBusy = false; isLoadingParties = false
        guard owner != nil else { return }
        // Navigation must retain the last selected party and any uncertain write.
        do { try persist() }
        catch { message = "Couldn't save the party page position. Any pending request is retained." }
    }

    func clearMessage() {
        if !cacheUnavailable { message = nil }
    }

    @discardableResult
    func cancelSetup() -> Bool {
        guard !cacheUnavailable, pending == nil || pending?.kind == .resolve || pending?.kind == .create else { return false }
        let previous = pending
        pending = nil
        if previous != nil {
            do { try persist() }
            catch { pending = previous; message = Self.failure(error); return false }
        }
        // Explicit cancellation abandons this setup, including any late response.
        generation = UUID()
        isBusy = false; isLoadingParties = false; canDiscardPending = false; message = nil
        return true
    }

    // The current API ends parties rather than erasing their saved history.
    @discardableResult
    func removeHostedParty(_ id: String, send: (String) async throws -> APIParty) async -> Bool {
        guard let party, party.id == id, party.isHost else { return false }
        let removed = await update(expectedID: id, clear: true) {
            let closed = try await send(id)
            guard closed.state == "CLOSED", closed.isHost, closed.deviceID == nil else { throw KickBACAPI.APIError.invalidResponse }
            return closed
        }
        if removed { parties.removeAll { $0.id == id } }
        return removed
    }

    @discardableResult
    func update(expectedID: String? = nil, clear: Bool = false, allowPendingRead: Bool = false,
                send: () async throws -> APIParty) async -> Bool {
        guard owner != nil, !isBusy, pending == nil || allowPendingRead else { return false }
        let ticket = generation
        isBusy = true; message = nil
        defer { if generation == ticket { isBusy = false } }
        do {
            let loaded = try await send()
            guard generation == ticket else { return false }
            try validateParty(loaded)
            if let expectedID, loaded.id != expectedID { throw KickBACAPI.APIError.invalidResponse }
            if clear || party?.id != loaded.id { lastCheckIn = nil }
            party = clear ? nil : loaded; selectedID = party?.id
            try persist()
            return true
        } catch {
            if generation == ticket { captureConflict(error); message = Self.failure(error) }
            return false
        }
    }

    @discardableResult
    func submit(_ requested: PartyWrite?, deviceFlow: DeviceSessionStore,
                send: (PartyWrite) async throws -> PartyReply) async -> Bool {
        guard let owner, !isBusy else { return false }
        let ticket = generation
        isBusy = true; message = nil; canDiscardPending = false
        defer { if generation == ticket { isBusy = false } }
        do {
            let write: PartyWrite
            if let pending {
                guard requested == nil || requested == pending else { throw KickBACAPI.APIError.invalidRequest }
                write = pending
            } else {
                guard let requested else { return false }
                write = requested
            }
            try write.validate()
            if write.kind == .checkIn, deviceFlow.hasActiveSession {
                // An uncertain retry can recover its original session; a fresh request cannot arm over it.
                guard pending != nil else { throw DeviceSessionStore.FlowError.activeTest }
            }
            pending = write
            try persist() // No network send is allowed if durable storage failed.
            let reply = try await send(write)
            guard generation == ticket else { return false }
            switch (write.kind, reply) {
            case (.create, .party(let loaded)):
                try validateParty(loaded)
                guard loaded.id == write.id, loaded.name == write.name, loaded.isHost else { throw KickBACAPI.APIError.invalidResponse }
                party = loaded; selectedID = loaded.id
            case (.resolve, .resolved(let result)):
                let loaded = result.party
                try validateParty(loaded)
                guard result.action != .created || loaded.isHost,
                      (loaded.state == "OPEN" && loaded.deviceID == write.deviceID
                        && (!loaded.isHost || loaded.joinCode != nil))
                        || (loaded.state == "CLOSED" && loaded.deviceID == nil && loaded.joinCode == nil) else {
                    throw KickBACAPI.APIError.invalidResponse
                }
                // A replay may return its original, now closed party. Never create a replacement implicitly.
                party = loaded.state == "OPEN" ? loaded : nil
                selectedID = party?.id
                lastCheckIn = nil
                if party == nil { message = "That party has ended. Start a new request to create another party." }
            case (.game, .game(let loaded)):
                guard loaded.id == write.id, loaded.partyID == write.partyID, loaded.gameID == "trivia" else { throw KickBACAPI.APIError.invalidResponse }
            case (.checkIn, .checkIn(let loaded)):
                try loaded.validate(owner: owner)
                guard loaded.id == write.id, loaded.partyID == write.partyID,
                      loaded.gameInstanceID == write.gameInstanceID, loaded.session.deviceID == write.deviceID else { throw KickBACAPI.APIError.invalidResponse }
                try deviceFlow.adoptCheckIn(loaded.session, expectedOwner: owner)
                lastCheckIn = loaded
            default: throw KickBACAPI.APIError.invalidResponse
            }
            pending = nil
            do { try persist() } catch { pending = write; throw error }
            return true
        } catch {
            if generation == ticket {
                captureConflict(error)
                message = pending?.kind == .resolve ? Self.setupFailure(error) : Self.failure(error)
                switch error as? KickBACAPI.APIError {
                case .activePartyConflict, .server(404, "not_found"), .server(409, "device_busy"), .server(409, "invalid_state"),
                     .server(410, "session_expired"), .server(422, "validation_error"),
                     .server(409, "active_party_conflict"), .http(404), .server(405, _), .http(405):
                    canDiscardPending = pending != nil
                default: break // Ambiguous failures and idempotency conflicts must retain the request.
                }
            }
            return false
        }
    }

    func discardRejectedRequest() {
        guard canDiscardPending, !isBusy, let previous = pending else { return }
        pending = nil
        do { try persist(); canDiscardPending = false; message = nil }
        catch { pending = previous; message = Self.failure(error) }
    }

    private func validateParty(_ party: APIParty) throws {
        guard UUID(uuidString: party.id) != nil, ["host", "member"].contains(party.role),
              ["OPEN", "CLOSED"].contains(party.state), party.memberCount >= 0,
              party.deviceID.map(DeviceTarget.isValidID) ?? true else { throw KickBACAPI.APIError.invalidResponse }
    }
    private func cacheURL(_ owner: String) -> URL {
        let key = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }
    private func persist() throws {
        guard let owner else { throw KickBACAPI.APIError.unauthorized }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Saved(selectedID: selectedID, pending: pending))
            .write(to: cacheURL(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func deviceFailure(_ error: Error, linking: Bool) -> String {
        switch error as? KickBACAPI.APIError {
        case .server(404, _), .http(404):
            return linking
                ? "This existing party still needs its breathalyzer linked."
                : "No open party is available through this breathalyzer. Ask the host to link it, or join with the party code."
        default: return failure(error)
        }
    }
    static func setupFailure(_ error: Error) -> String {
        switch error as? KickBACAPI.APIError {
        case .server(404, _), .http(404), .server(405, _), .http(405):
            return "Couldn't set up a linked party."
        default: return failure(error)
        }
    }
    static func failure(_ error: Error) -> String {
        if error is DeviceSessionStore.FlowError { return error.localizedDescription }
        switch error as? KickBACAPI.APIError {
        case .unauthorized: return "Sign in to continue."
        case .server(409, "device_busy"): return "The breathalyzer is busy. Wait for the current test to finish, then retry."
        case .server(409, "device_assigned"): return "This breathalyzer is assigned to another party."
        case .activePartyConflict, .server(409, "active_party_conflict"): return "You already have an open party. Open it, or end or leave it before creating another."
        case .server(409, "idempotency_conflict"): return "This saved request conflicts with the server. Keep it for recovery; don't start another attempt."
        case .server(409, _), .http(409): return "The party or game has changed. Refresh its status before retrying."
        case .server(404, _), .http(404): return "Party or device unavailable. Check the code, membership and device binding. Linking also requires operator approval."
        case .server(410, _), .http(410): return "The test expired. Recover its status before starting a new test."
        case .server(429, _), .http(429): return "Too many join attempts. Wait a minute before retrying."
        case .invalidRequest, .server(422, _), .http(422): return "Check the party name, eight-character code or device link. Retry an existing saved request without changing it."
        case .invalidResponse: return "Couldn't verify the server response. Retry the saved request."
        default: return "Couldn't reach KickBAC or save the request on this iPhone. Any pending request is retained for an exact retry."
        }
    }
}

@MainActor @Observable
final class CheckInHistoryStore {
    private(set) var owner: String?
    private(set) var page: PartyPage<APICheckIn>?
    private(set) var message: String?
    private(set) var isLoading = false
    private var generation = UUID()
    func switchOwner(_ owner: String?) {
        guard self.owner != owner else { return }
        self.owner = owner; generation = UUID(); page = nil; message = nil; isLoading = false
    }
    func load(more: Bool = false, fetch: (Int) async throws -> PartyPage<APICheckIn>) async {
        guard let owner, !isLoading, !more || page?.hasMore == true else { return }
        let ticket = generation
        let previous = more ? page : nil
        let offset = previous.map { $0.offset + $0.limit } ?? 0
        isLoading = true; message = nil
        defer { if generation == ticket { isLoading = false } }
        do {
            let loaded = try await fetch(offset)
            guard generation == ticket else { return }
            try Task.checkCancellation()
            guard loaded.offset == offset, (1...100).contains(loaded.limit), !loaded.hasMore || !loaded.items.isEmpty else { throw KickBACAPI.APIError.invalidResponse }
            try loaded.items.forEach { try $0.validate(owner: owner) }
            var seen = Set<String>()
            let items = ((previous?.items ?? []) + loaded.items).filter { seen.insert($0.id).inserted }
            page = PartyPage(items: items, limit: loaded.limit, offset: loaded.offset, hasMore: loaded.hasMore)
        } catch {
            if generation == ticket { message = PartyStore.failure(error) }
        }
    }
}
