import Foundation

// Run from the repository root:
// swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/AuthConfiguration.swift ios/KickBAC/KickBACAPI.swift ios/checks/AuthContractChecks.swift -o /tmp/kickbac-auth-checks
// /tmp/kickbac-auth-checks ios/KickBAC/Auth0.plist
@main
struct AuthContractChecks {
    static func main() async throws {
        let data = try Data(contentsOf: URL(filePath: CommandLine.arguments[1]))
        let values = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        let configuration = try AuthConfiguration(values: values, bundleID: "com.liam.KickBAC")
        precondition(configuration.callbackURL.absoluteString == "com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback")
        precondition(configuration.connection == "sms")
        precondition(configuration.scope == "openid profile")
        precondition(configuration.clientID == "5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC")
        for (key, value) in [("Audience", "https://kickbac-api/"), ("APIBaseURL", "http://api.kickbac.vodka"), ("Domain", "invalid/path")] {
            var invalid = values
            invalid[key] = value
            do {
                _ = try AuthConfiguration(values: invalid, bundleID: "com.liam.KickBAC")
                preconditionFailure("Accepted invalid \(key)")
            } catch AuthConfiguration.ConfigurationError.invalid { }
        }

        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [APIStub.self]
        let session = URLSession(configuration: urlConfiguration)
        defer { session.invalidateAndCancel() }
        let api = KickBACAPI(baseURL: configuration.apiBaseURL, session: session)
        let token = "api-access-token-not-an-id-token"

        APIStub.payload = Data(#"{"user_id":"sms|opaque:subject/+not-a-phone"}"#.utf8)
        let user = try await api.currentUser(accessToken: token)
        precondition(user.userID == "sms|opaque:subject/+not-a-phone")
        checkRequest(path: "/v1/me", token: token)

        APIStub.payload = Data(#"{"items":[{"id":"026af7c9-d605-4291-a1db-5b230e10ef43","session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},"breath_duration_ms":2500,"source":"simulator","measured_at":null,"received_at":"2026-10-17T01:00:05+00:00","estimated_bac_percent":null}],"limit":25,"offset":50,"has_more":true}"#.utf8)
        let history = try await api.measurements(accessToken: token, limit: 25, offset: 50)
        checkRequest(path: "/v1/measurements", token: token)
        let query = URLComponents(url: APIStub.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.contains(URLQueryItem(name: "limit", value: "25")))
        precondition(query.contains(URLQueryItem(name: "offset", value: "50")))
        precondition(history.hasMore && history.offset == 50 && history.limit == 25)
        let measurement = history.items.first!
        precondition(measurement.raw.value == 1200 && measurement.raw.unit == "adc_counts")
        precondition(measurement.estimatedBACPercent == nil && measurement.measuredAt == nil)
        precondition(measurement.source == "simulator")

        APIStub.payload = Data(#"{"device_id":"kb-demo-01"}"#.utf8)
        let target = try await api.resolveDevice("kb-demo-01")
        precondition(target.deviceID == "kb-demo-01")
        precondition(APIStub.lastRequest!.value(forHTTPHeaderField: "Authorization") == nil)
        APIStub.payload = Data(#"{"id":"kb-demo-01","state":"AVAILABLE","online":false,"last_seen_at":null}"#.utf8)
        let device = try await api.device("kb-demo-01", accessToken: token)
        precondition(!device.online && device.state == "AVAILABLE")
        checkRequest(path: "/v1/devices/kb-demo-01", token: token)
        APIStub.payload = Data(#"{"id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","user_id":"sms|opaque:subject/+not-a-phone","status":"ARMED","created_at":"2026-10-17T23:00:00Z","expires_at":"2026-10-17T23:01:00Z","completed_at":null,"measurement":null}"#.utf8)
        let armed = try await api.armDevice("kb-demo-01", accessToken: token)
        precondition(armed.status == .armed && armed.measurement == nil)
        precondition(APIStub.lastRequest!.httpMethod == "POST" && APIStub.lastRequest!.url!.path == "/v1/devices/kb-demo-01/sessions")
        let armBody = try jsonBody(APIStub.lastRequest!)
        precondition(armBody.isEmpty)
        _ = try await api.testSession(armed.id, accessToken: token)
        checkRequest(path: "/v1/sessions/\(armed.id)", token: token)
        _ = try await api.cancelSession(armed.id, accessToken: token)
        precondition(APIStub.lastRequest!.httpMethod == "POST" && APIStub.lastRequest!.url!.path == "/v1/sessions/\(armed.id)/cancel")
        let cancelBody = try jsonBody(APIStub.lastRequest!)
        precondition(cancelBody.isEmpty)
        APIStub.payload = Data(#"{"user_id":"sms|opaque:subject/+not-a-phone","total_points":10,"games_played":1,"wins":1,"per_game":[]}"#.utf8)
        let stats = try await api.stats(accessToken: token)
        precondition(stats.totalPoints == 10 && stats.gamesPlayed == 1 && stats.wins == 1)
        checkRequest(path: "/v1/me/stats", token: token)

        APIStub.payload = Data(#"{"user_id":"sms|opaque:subject/+not-a-phone","display_name":null,"profile_picture":null,"created_at":null,"updated_at":null}"#.utf8)
        let empty = try await api.profile(accessToken: token)
        precondition(empty.displayName == nil && empty.profilePicture == nil)
        checkRequest(path: "/v1/me/profile", token: token)
        APIStub.payload = Data(#"{"user_id":"sms|opaque:subject/+not-a-phone","display_name":"Liam","profile_picture":null,"created_at":"2026-10-17T23:00:00+00:00","updated_at":"2026-10-17T23:00:00.125Z"}"#.utf8)
        let saved = try await api.saveProfile(name: "Liam", photoData: nil, accessToken: token)
        precondition(saved.displayName == "Liam" && saved.updatedAt!.hasSuffix("Z"))
        let put = APIStub.lastRequest!
        precondition(put.httpMethod == "PUT" && put.url!.path == "/v1/me/profile")
        precondition(put.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        precondition(put.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let withoutPhoto = try jsonBody(put)
        precondition(Set(withoutPhoto.keys) == ["display_name", "profile_picture"])
        precondition(withoutPhoto["profile_picture"] is NSNull)
        let image = Data([0xff, 0xd8, 0xff, 0xd9]) // Transport-only fixture; real image preparation is checked separately.
        APIStub.payload = Data(#"{"user_id":"sms|opaque:subject/+not-a-phone","display_name":"Liam","profile_picture":{"content_type":"image/jpeg","data_base64":"/9j/2Q=="},"created_at":null,"updated_at":null}"#.utf8)
        let pictured = try await api.saveProfile(name: "Liam", photoData: image, accessToken: token)
        let withPhoto = try jsonBody(APIStub.lastRequest!)
        let picture = withPhoto["profile_picture"] as! [String: Any]
        precondition(Set(picture.keys) == ["content_type", "data_base64"])
        precondition(picture["content_type"] as? String == "image/jpeg")
        precondition(picture["data_base64"] as? String == image.base64EncodedString())
        precondition(pictured.profilePicture?.data == image)
        for (status, code) in [(413, "payload_too_large"), (422, "validation_error"), (503, "auth_unavailable")] {
            APIStub.status = status
            APIStub.payload = try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": "Fixture"]])
            do {
                _ = try await api.saveProfile(name: "Liam", photoData: nil, accessToken: token)
                preconditionFailure("Accepted a rejected save")
            } catch let error as KickBACAPI.APIError {
                precondition(error == .server(status: status, code: code))
            }
        }
        APIStub.payload = Data("<html>Service unavailable</html>".utf8)

        for status in [401, 503] {
            APIStub.status = status
            do {
                _ = try await api.currentUser(accessToken: token)
                preconditionFailure("Accepted HTTP \(status)")
            } catch let error as KickBACAPI.APIError {
                precondition(error == (status == 401 ? .unauthorized : .http(status)))
            }
        }

        let count = APIStub.requestCount
        do {
            _ = try await api.currentUser(accessToken: "")
            preconditionFailure("Sent an empty token")
        } catch KickBACAPI.APIError.unauthorized { }
        do {
            _ = try await api.measurements(accessToken: token, limit: 101, offset: -1)
            preconditionFailure("Sent invalid pagination")
        } catch KickBACAPI.APIError.invalidRequest { }
        precondition(APIStub.requestCount == count)
        print("Auth contract checks passed: callback, scopes, access-token headers, opaque subjects, private history, null BAC, and error handling.")
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody {
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let stream = request.httpBodyStream!
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func checkRequest(path: String, token: String) {
        let request = APIStub.lastRequest!
        precondition(request.url?.path == path && request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
        precondition(request.httpBody == nil && request.cachePolicy == .reloadIgnoringLocalCacheData)
    }
}

// The check runs sequentially; each response is configured before starting its single request.
private final class APIStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
