import Foundation

nonisolated struct APIParty: Decodable, Identifiable, Sendable, Equatable {
    let partyID: String
    let name: String
    let state: String
    let role: String
    let memberCount: Int
    let deviceID: String?
    let joinCode: String?
    var id: String { partyID }
    var isHost: Bool { role == "host" }
    enum CodingKeys: String, CodingKey {
        case name, state, role
        case partyID = "party_id", memberCount = "member_count", deviceID = "device_id", joinCode = "join_code"
    }
}

nonisolated struct APIPartyGame: Decodable, Identifiable, Sendable {
    let gameInstanceID: String
    let partyID: String
    let gameID: String
    let state: String
    let deviceID: String?
    var id: String { gameInstanceID }
    enum CodingKeys: String, CodingKey {
        case state
        case gameInstanceID = "game_instance_id", partyID = "party_id", gameID = "game_id", deviceID = "device_id"
    }
}

nonisolated struct APICheckIn: Decodable, Identifiable, Sendable {
    let checkInID: String
    let partyID: String
    let gameInstanceID: String?
    let session: APITestSession
    var id: String { checkInID }
    enum CodingKeys: String, CodingKey {
        case session
        case checkInID = "check_in_id", partyID = "party_id", gameInstanceID = "game_instance_id"
    }
    func validate(owner: String) throws {
        guard UUID(uuidString: checkInID) != nil, UUID(uuidString: partyID) != nil,
              gameInstanceID.map({ UUID(uuidString: $0) != nil }) ?? true,
              session.userID == owner, UUID(uuidString: session.id) != nil,
              DeviceTarget.isValidID(session.deviceID),
              session.status != .complete || session.measurement != nil else { throw KickBACAPI.APIError.invalidResponse }
        if let reading = session.measurement {
            guard session.status == .complete, reading.sessionID == session.id,
                  reading.deviceID == session.deviceID, reading.hasValidAcquisition else { throw KickBACAPI.APIError.invalidResponse }
        }
    }
}

nonisolated struct PartyPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let limit: Int
    let offset: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case items, limit, offset; case hasMore = "has_more" }
}

// Persist bytes before sending. New writes replay their exact route, UUID and JSON after relaunch.
// Legacy unbound creates are retained only for read-only recovery of their original UUID.
nonisolated struct PartyWrite: Codable, Equatable, Sendable {
    enum Kind: String, Codable { case create, resolve, game, checkIn }
    let kind: Kind
    let id: String
    let partyID: String?
    let name: String?
    let deviceID: String?
    let gameInstanceID: String?
    let body: Data

    static func create(name: String, id: String = UUID().uuidString) throws -> Self {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.unicodeScalars.count),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw KickBACAPI.APIError.invalidRequest }
        return try make(.create, id: id, name: name)
    }
    static func resolve(name: String, deviceID: String, id: String = UUID().uuidString) throws -> Self {
        let validated = try create(name: name, id: id)
        return try make(.resolve, id: validated.id, name: validated.name, deviceID: deviceID)
    }
    static func game(partyID: String, id: String = UUID().uuidString) throws -> Self {
        try make(.game, id: id, partyID: partyID)
    }
    static func checkIn(partyID: String, deviceID: String, gameInstanceID: String?, id: String = UUID().uuidString) throws -> Self {
        try make(.checkIn, id: id, partyID: partyID, deviceID: deviceID, gameInstanceID: gameInstanceID)
    }
    private static func make(_ kind: Kind, id: String, partyID: String? = nil, name: String? = nil,
                             deviceID: String? = nil, gameInstanceID: String? = nil) throws -> Self {
        guard UUID(uuidString: id) != nil,
              partyID.map({ UUID(uuidString: $0) != nil }) ?? (kind == .create || kind == .resolve),
              deviceID.map(DeviceTarget.isValidID) ?? (kind != .checkIn && kind != .resolve),
              gameInstanceID.map({ UUID(uuidString: $0) != nil }) ?? true else { throw KickBACAPI.APIError.invalidRequest }
        let id = id.lowercased()
        let partyID = partyID?.lowercased()
        let gameInstanceID = gameInstanceID?.lowercased()
        let object: [String: Any]
        switch kind {
        case .create: object = ["party_id": id, "name": name ?? ""]
        case .resolve: object = ["request_id": id, "name": name ?? "", "device_id": deviceID ?? ""]
        case .game: object = ["game_instance_id": id, "game_id": "trivia"]
        case .checkIn: object = ["check_in_id": id, "device_id": deviceID ?? "", "game_instance_id": gameInstanceID as Any? ?? NSNull()]
        }
        return Self(kind: kind, id: id, partyID: partyID, name: name, deviceID: deviceID, gameInstanceID: gameInstanceID,
                    body: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
    var path: String {
        switch kind {
        case .create: "v1/parties"
        case .resolve: "v1/parties/resolve"
        case .game: "v1/parties/\(partyID ?? "")/games"
        case .checkIn: "v1/parties/\(partyID ?? "")/check-ins"
        }
    }
    func validate() throws {
        let expected = try Self.make(kind, id: id, partyID: partyID, name: name, deviceID: deviceID, gameInstanceID: gameInstanceID)
        guard self == expected else { throw KickBACAPI.APIError.invalidRequest }
        if kind == .create { _ = try Self.create(name: name ?? "", id: id) }
        if kind == .resolve {
            guard self == (try Self.resolve(name: name ?? "", deviceID: deviceID ?? "", id: id)) else { throw KickBACAPI.APIError.invalidRequest }
        }
    }
}

nonisolated struct APIPartyResolution: Decodable, Sendable {
    enum Action: String, Decodable, Sendable { case created, joined }
    let action: Action
    let party: APIParty
}

enum PartyReply { case party(APIParty), resolved(APIPartyResolution), game(APIPartyGame), checkIn(APICheckIn) }

extension KickBACAPI {
    func partyWrite(_ write: PartyWrite, accessToken: String) async throws -> PartyReply {
        try write.validate()
        switch write.kind {
        // Legacy uncertain creates are recovered read-only. Never create another unbound party.
        case .create: return .party(try await party(write.id, accessToken: accessToken))
        case .resolve: return .resolved(try await get(write.path, accessToken: accessToken, method: "POST", body: write.body))
        case .game: return .game(try await get(write.path, accessToken: accessToken, method: "POST", body: write.body))
        case .checkIn: return .checkIn(try await get(write.path, accessToken: accessToken, method: "POST", body: write.body))
        }
    }
    func currentParty(accessToken: String) async throws -> APIParty? {
        try await get("v1/me/parties/current", accessToken: accessToken)
    }
    func parties(accessToken: String, offset: Int = 0) async throws -> PartyPage<APIParty> {
        try await partyPage("v1/me/parties", accessToken: accessToken, offset: offset)
    }
    func party(_ id: String, accessToken: String) async throws -> APIParty {
        guard UUID(uuidString: id) != nil else { throw APIError.invalidRequest }
        return try await get("v1/parties/\(id)", accessToken: accessToken)
    }
    func joinParty(code: String? = nil, deviceID: String? = nil, accessToken: String) async throws -> APIParty {
        guard (code != nil) != (deviceID != nil) else { throw APIError.invalidRequest }
        let object: [String: String]
        if let code {
            let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard code.count == 8, code.allSatisfy({ "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }) else { throw APIError.invalidRequest }
            object = ["join_code": code]
        } else {
            guard let deviceID, DeviceTarget.isValidID(deviceID) else { throw APIError.invalidRequest }
            object = ["device_id": deviceID]
        }
        return try await get("v1/parties/join", accessToken: accessToken, method: "POST", body: JSONEncoder().encode(object))
    }
    func updateParty(_ id: String, action: String, deviceID: String? = nil, accessToken: String) async throws -> APIParty {
        guard UUID(uuidString: id) != nil, ["leave", "close", "bind", "unbind"].contains(action) else { throw APIError.invalidRequest }
        if action == "bind", deviceID.map(DeviceTarget.isValidID) != true { throw APIError.invalidRequest }
        let path = "v1/parties/\(id)/\(["bind", "unbind"].contains(action) ? "device" : action)"
        return try await get(path, accessToken: accessToken, method: action == "bind" ? "PUT" : action == "unbind" ? "DELETE" : "POST",
                             body: action == "unbind" ? nil : JSONEncoder().encode(deviceID.map { ["device_id": $0] } ?? [:]))
    }
    func partyGames(_ id: String, accessToken: String, offset: Int = 0) async throws -> PartyPage<APIPartyGame> {
        guard UUID(uuidString: id) != nil else { throw APIError.invalidRequest }
        return try await partyPage("v1/parties/\(id)/games", accessToken: accessToken, offset: offset)
    }
    func closePartyGame(_ id: String, accessToken: String) async throws -> APIPartyGame {
        guard UUID(uuidString: id) != nil else { throw APIError.invalidRequest }
        return try await get("v1/party-games/\(id)/close", accessToken: accessToken, method: "POST", body: Data("{}".utf8))
    }
    func checkIns(accessToken: String, offset: Int = 0) async throws -> PartyPage<APICheckIn> {
        try await partyPage("v1/me/check-ins", accessToken: accessToken, offset: offset)
    }
    private func partyPage<T>(_ path: String, accessToken: String, offset: Int) async throws -> PartyPage<T> {
        guard offset >= 0 else { throw APIError.invalidRequest }
        return try await get(path, query: [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))], accessToken: accessToken)
    }
}
