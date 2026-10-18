import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class PartyStore {
    private(set) var owner: String?
    private(set) var party: APIParty?
    private(set) var pending: PartyWrite?
    private(set) var lastCheckIn: APICheckIn?
    private(set) var message: String?
    private(set) var isBusy = false
    private(set) var canDiscardPending = false
    private var generation = UUID()
    private let directory: URL
    private var selectedID: String?
    private struct Saved: Codable { let selectedID: String?; let pending: PartyWrite? }

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Parties")) { self.directory = directory }
    func switchOwner(_ owner: String?) {
        guard self.owner != owner else { return }
        generation = UUID(); self.owner = owner
        party = nil; pending = nil; lastCheckIn = nil; message = nil; isBusy = false; selectedID = nil; canDiscardPending = false
        guard let owner else { return }
        do {
            let url = cacheURL(owner)
            if FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
                try saved.pending?.validate()
                guard saved.selectedID.map({ UUID(uuidString: $0) != nil }) ?? true else { throw KickBACAPI.APIError.invalidResponse }
                selectedID = saved.selectedID; pending = saved.pending
            }
        } catch { message = "Couldn't restore party requests. Reopen the app before starting a new request."; isBusy = true }
    }

    func restore(fetch: (String) async throws -> APIParty) async {
        guard let selectedID else { return }
        await update(expectedID: selectedID, allowPendingRead: true) { try await fetch(selectedID) }
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
            if generation == ticket { message = Self.failure(error) }
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
                message = Self.failure(error)
                switch error as? KickBACAPI.APIError {
                case .server(404, "not_found"), .server(409, "device_busy"), .server(409, "invalid_state"),
                     .server(410, "session_expired"), .server(422, "validation_error"):
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
    static func failure(_ error: Error) -> String {
        if error is DeviceSessionStore.FlowError { return error.localizedDescription }
        switch error as? KickBACAPI.APIError {
        case .unauthorized: return "Sign in to continue."
        case .server(409, "device_busy"): return "The breathalyzer is busy. Wait for the current test to finish, then retry."
        case .server(409, "device_assigned"): return "This breathalyzer is assigned to another party."
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
