import Foundation

nonisolated enum DeviceTarget {
    static func isValidID(_ id: String) -> Bool {
        // Matches the backend device slug; never interpolate arbitrary paths into authenticated requests.
        id.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\\z", options: .regularExpression) != nil
    }

    static func parse(_ input: String, baseURL: URL) throws -> String {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidID(input) { return input }
        guard let url = URLComponents(string: input),
              url.scheme == "https", url.host == baseURL.host,
              url.port == baseURL.port, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw TargetError.invalid }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty, parts[1] == "d", isValidID(String(parts[2])),
              url.percentEncodedPath == url.path else { throw TargetError.invalid }
        return String(parts[2])
    }

    enum TargetError: LocalizedError {
        case invalid
        var errorDescription: String? { "Enter a kickBAC device ID or its official device link." }
    }
}

nonisolated struct DeviceResolution: Decodable, Sendable {
    let deviceID: String
    enum CodingKeys: String, CodingKey { case deviceID = "device_id" }
}

nonisolated struct APIDevice: Decodable, Sendable {
    let id: String
    let state: String
    let online: Bool
    let lastSeenAt: String?
    enum CodingKeys: String, CodingKey { case id, state, online; case lastSeenAt = "last_seen_at" }
}

nonisolated struct APITestSession: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case armed = "ARMED", sampling = "SAMPLING", complete = "COMPLETE"
        case cancelled = "CANCELLED", expired = "EXPIRED"
        var isActive: Bool { self == .armed || self == .sampling }
    }
    let id: String
    let deviceID: String
    let userID: String
    let status: Status
    let createdAt: String
    let expiresAt: String
    let completedAt: String?
    let measurement: APIMeasurement?
    enum CodingKeys: String, CodingKey {
        case id, status, measurement
        case deviceID = "device_id", userID = "user_id", createdAt = "created_at"
        case expiresAt = "expires_at", completedAt = "completed_at"
    }
}

nonisolated struct APIStats: Decodable, Sendable {
    let userID: String
    let totalPoints: Int
    let gamesPlayed: Int
    let wins: Int
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", totalPoints = "total_points", gamesPlayed = "games_played", wins
    }
}
