import Foundation

nonisolated struct APIProfile: Decodable, Sendable {
    let userID: String
    let displayName: String?
    let profilePicture: APIProfilePicture?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", displayName = "display_name", profilePicture = "profile_picture"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

nonisolated struct APIProfilePicture: Codable, Sendable {
    let contentType: String
    let data: Data
    enum CodingKeys: String, CodingKey { case contentType = "content_type", data = "data_base64" }
}

nonisolated private struct ProfilePut: Encodable {
    let displayName: String
    let profilePicture: APIProfilePicture?
    enum CodingKeys: String, CodingKey { case displayName = "display_name", profilePicture = "profile_picture" }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        // PUT replaces both fields; an omitted picture key is invalid.
        try container.encode(profilePicture, forKey: .profilePicture)
    }
}

struct APIUser: Decodable {
    // Auth0 subjects are opaque strings, including their provider prefix.
    let userID: String
    enum CodingKeys: String, CodingKey { case userID = "user_id" }
}

struct MeasurementPage: Decodable {
    let items: [APIMeasurement]
    let limit: Int
    let offset: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case items, limit, offset
        case hasMore = "has_more"
    }
}

nonisolated struct GameResultPage: Decodable, Sendable {
    let items: [APIGameResult]
    let limit: Int
    let offset: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case items, limit, offset
        case hasMore = "has_more"
    }
}

nonisolated struct APIGameResult: Decodable, Identifiable, Sendable {
    enum Outcome: String, Decodable, Sendable {
        case win, loss, draw, completed
        var title: String {
            switch self {
            case .win: "Won"
            case .loss: "Lost"
            case .draw: "Draw"
            case .completed: "Completed"
            }
        }
    }
    let id: String
    let userID: String
    let gameID: String
    let score: Int
    let outcome: Outcome
    let awardedPoints: Int
    let createdAt: String

    var gameTitle: String {
        gameID.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }

    var recordedDate: Date? {
        (try? Date(createdAt, strategy: .iso8601)) ??
            (try? Date(createdAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    enum CodingKeys: String, CodingKey {
        case score, outcome
        case id = "result_id", userID = "user_id", gameID = "game_id"
        case awardedPoints = "awarded_points", createdAt = "created_at"
    }
}

nonisolated struct APIMeasurement: Decodable, Identifiable, Sendable {
    struct Raw: Decodable, Sendable {
        let sensor: String
        let value: Int
        let unit: String
    }

    let id: String
    let sessionID: String
    let deviceID: String
    let raw: Raw
    let breathDurationMS: Int?
    let acquisitionMethod: String?
    let sampleDurationMS: Int?
    let source: String
    let measuredAt: String?
    let receivedAt: String
    let estimatedBACPercent: Double?

    var recordedDate: Date? {
        for timestamp in [measuredAt, receivedAt].compactMap({ $0 }) {
            if let date = try? Date(timestamp, strategy: .iso8601),
               date.timeIntervalSince1970.isFinite { return date }
            if let date = try? Date(timestamp, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
               date.timeIntervalSince1970.isFinite { return date }
        }
        return nil
    }

    var isTestReading: Bool { source == "simulator" }
    var isManualTimed: Bool { acquisitionMethod == "manual_timed" }

    // A sensor acquisition window is never a measured breath duration.
    var hasValidAcquisition: Bool {
        if isManualTimed {
            return breathDurationMS == nil && sampleDurationMS.map { (1...60000).contains($0) } == true
                && estimatedBACPercent == nil
        }
        return acquisitionMethod == nil && sampleDurationMS == nil
            && breathDurationMS.map { (1...60000).contains($0) } == true
    }

    var acquisitionNotice: String? {
        if isManualTimed { return "Timed sensor sample — breath not validated" }
        return hasValidAcquisition ? nil : "Acquisition details unavailable"
    }

    var sourceTitle: String {
        switch source {
        case "simulator": "Simulated sensor reading"
        case "device": "Device sensor reading"
        default: "Unknown reading source"
        }
    }

    var durationText: String {
        guard hasValidAcquisition, let duration = isManualTimed ? sampleDurationMS : breathDurationMS else {
            return "Duration unavailable"
        }
        let seconds = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(duration) / 1000)
        return "\(isManualTimed ? "Sample window" : "Breath duration"): \(seconds) s"
    }

    var durationAccessibilityValue: String {
        [sourceTitle, acquisitionNotice, durationText].compactMap { $0 }.joined(separator: ". ")
    }

    var bacReading: BACReading? {
        guard hasValidAcquisition, !isManualTimed, !isTestReading, source == "device", let value = estimatedBACPercent, value.isFinite, value >= 0,
              let date = recordedDate else { return nil }
        return BACReading(value: value, date: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, raw, source
        case sessionID = "session_id"
        case deviceID = "device_id"
        case breathDurationMS = "breath_duration_ms"
        case acquisitionMethod = "acquisition_method"
        case sampleDurationMS = "sample_duration_ms"
        case measuredAt = "measured_at"
        case receivedAt = "received_at"
        case estimatedBACPercent = "estimated_bac_percent"
    }
}

struct KickBACAPI {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func currentUser(accessToken: String) async throws -> APIUser {
        try await get("v1/me", accessToken: accessToken)
    }

    func profile(accessToken: String) async throws -> APIProfile {
        try await get("v1/me/profile", accessToken: accessToken)
    }

    func resolveDevice(_ id: String) async throws -> DeviceResolution {
        guard DeviceTarget.isValidID(id) else { throw APIError.invalidRequest }
        return try await get("d/\(id)", accessToken: nil)
    }

    func device(_ id: String, accessToken: String) async throws -> APIDevice {
        guard DeviceTarget.isValidID(id) else { throw APIError.invalidRequest }
        return try await get("v1/devices/\(id)", accessToken: accessToken)
    }

    func armDevice(_ id: String, accessToken: String) async throws -> APITestSession {
        guard DeviceTarget.isValidID(id) else { throw APIError.invalidRequest }
        return try await get("v1/devices/\(id)/sessions", accessToken: accessToken, method: "POST", body: Data("{}".utf8))
    }

    func testSession(_ id: String, accessToken: String) async throws -> APITestSession {
        guard UUID(uuidString: id) != nil else { throw APIError.invalidRequest }
        return try await get("v1/sessions/\(id)", accessToken: accessToken)
    }

    func cancelSession(_ id: String, accessToken: String) async throws -> APITestSession {
        guard UUID(uuidString: id) != nil else { throw APIError.invalidRequest }
        return try await get("v1/sessions/\(id)/cancel", accessToken: accessToken, method: "POST", body: Data("{}".utf8))
    }

    func stats(accessToken: String) async throws -> APIStats {
        try await get("v1/me/stats", accessToken: accessToken)
    }

    func gameResults(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> GameResultPage {
        guard (1...100).contains(limit), offset >= 0 else { throw APIError.invalidRequest }
        return try await get("v1/me/game-results", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ], accessToken: accessToken)
    }

    func saveProfile(name: String, photoData: Data?, accessToken: String) async throws -> APIProfile {
        guard photoData.map({ $0.count <= 524_288 }) ?? true else { throw APIError.http(413) }
        let picture = photoData.map { APIProfilePicture(contentType: "image/jpeg", data: $0) }
        let body = try JSONEncoder().encode(ProfilePut(displayName: name, profilePicture: picture))
        guard body.count <= 1_048_576 else { throw APIError.http(413) }
        return try await get("v1/me/profile", accessToken: accessToken, method: "PUT", body: body)
    }

    func measurements(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> MeasurementPage {
        guard (1...100).contains(limit), offset >= 0 else { throw APIError.invalidRequest }
        return try await get("v1/measurements", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ], accessToken: accessToken)
    }

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [],
                                          accessToken: String?, method: String = "GET", body: Data? = nil) async throws -> Response {
        if let accessToken, accessToken.isEmpty { throw APIError.unauthorized }
        guard baseURL.scheme == "https", baseURL.host != nil,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if response.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(response.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(status: response.statusCode, code: envelope.error.code)
            }
            throw APIError.http(response.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }

    enum APIError: LocalizedError, Equatable {
        case unauthorized, invalidRequest, invalidResponse
        case http(Int)
        case server(status: Int, code: String)

        var errorDescription: String? {
            let status: Int?
            switch self {
            case .unauthorized: return "Please sign in again."
            case .invalidRequest, .invalidResponse: return "Couldn't read your profile. Please try again."
            case .http(let value), .server(let value, _): status = value
            }
            switch status {
            case 413: return "That photo is too large. Try taking another photo."
            case 422: return "Check your name and photo, then try again."
            default: return "Can't reach KickBAC right now. Your changes haven't been saved. Try again."
            }
        }
    }
}
