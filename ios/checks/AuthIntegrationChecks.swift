import Auth0
import Foundation

// Uses the real Auth0.swift request builders with a local transport stub and in-memory storage.
// Run with: bash ios/checks/run-authentication-checks.sh
@main
struct AuthIntegrationChecks {
    @MainActor
    static func main() async throws {
        let configuration = try AuthConfiguration(values: [
            "Domain": "dev-c87oxm4dkbyatvrn.us.auth0.com",
            "ClientId": "5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC",
            "Audience": "https://kickbac-api", "APIBaseURL": "https://api.kickbac.vodka"
        ], bundleID: "com.liam.KickBAC")
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [AuthStub.self]
        let transport = URLSession(configuration: network)
        defer { transport.invalidateAndCancel() }
        let storage = MemoryCredentialsStorage()
        let session = AuthSession(configuration: configuration, transport: transport, storage: storage)
        await session.restore()
        precondition(!session.isSignedIn && !session.isBusy && AuthStub.requests.isEmpty)

        do {
            try await session.sendCode(to: "not-a-phone")
            preconditionFailure("Accepted invalid phone")
        } catch AuthSession.SignInError.invalidPhone { }
        precondition(AuthStub.requests.isEmpty)

        AuthStub.status = 403
        AuthStub.payload = Data(#"{"error":"invalid_request","error_description":"the connection is not enabled"}"#.utf8)
        do {
            try await session.sendCode(to: "+12025550135")
            preconditionFailure("Accepted disabled connection")
        } catch AuthSession.SignInError.connectionUnavailable { }
        precondition(session.pendingPhoneNumber == nil && !session.isBusy)

        AuthStub.status = 200
        AuthStub.payload = Data("{}".utf8)
        try await session.sendCode(to: "+12025550135")
        precondition(session.pendingPhoneNumber == "+12025550135" && !session.isSignedIn)
        let send = try body(AuthStub.requests.last!)
        precondition(AuthStub.requests.last!.url?.path == "/passwordless/start")
        precondition(send["phone_number"] as? String == "+12025550135")
        precondition(send["connection"] as? String == "sms" && send["send"] as? String == "code")
        precondition(send["client_id"] as? String == configuration.clientID && send["client_secret"] == nil)
        precondition(session.resendAvailableAt! > .now)
        let sentRequests = AuthStub.requests.count
        do {
            try await session.sendCode(to: "+12025550135")
            preconditionFailure("Resent during cooldown")
        } catch AuthSession.SignInError.cooldown { }
        do {
            try await session.verifyCode("12")
            preconditionFailure("Accepted incomplete code")
        } catch AuthSession.SignInError.invalidCode { }
        precondition(AuthStub.requests.count == sentRequests)

        AuthStub.status = 403
        AuthStub.payload = Data(#"{"error":"unauthorized_client","error_description":"Passwordless OTP grant is not enabled"}"#.utf8)
        do {
            try await session.verifyCode("654321")
            preconditionFailure("Accepted disabled grant")
        } catch AuthSession.SignInError.grantUnavailable { }
        let verify = try body(AuthStub.requests.last!)
        precondition(AuthStub.requests.last!.url?.path == "/oauth/token")
        precondition(verify["grant_type"] as? String == "http://auth0.com/oauth/grant-type/passwordless/otp")
        precondition(verify["username"] as? String == "+12025550135" && verify["otp"] as? String == "654321")
        precondition(verify["realm"] as? String == "sms")
        precondition(verify["audience"] as? String == configuration.audience)
        precondition(Set((verify["scope"] as! String).split(separator: " ")) == ["openid", "profile"])
        precondition(verify["client_secret"] == nil)

        AuthStub.status = 400
        AuthStub.payload = Data(#"{"error":"invalid_grant","error_description":"Wrong phone number or verification code."}"#.utf8)
        do {
            try await session.verifyCode("654321")
            preconditionFailure("Accepted incorrect code")
        } catch AuthSession.SignInError.invalidCode { }
        precondition(!session.isSignedIn && session.pendingPhoneNumber != nil && !session.isBusy)

        AuthStub.status = 200
        AuthStub.payload = Data(#"{"access_token":"SIMULATED-ACCESS-TOKEN","id_token":"invalid-token","token_type":"Bearer","expires_in":3600}"#.utf8)
        do {
            try await session.verifyCode("654321")
            preconditionFailure("Accepted an invalid ID token")
        } catch { }
        precondition(!session.isSignedIn && storage.isEmpty)

        session.clearPhoneChallenge()
        AuthStub.status = 429
        AuthStub.payload = Data(#"{"error":"too_many_attempts","error_description":"Rate limited"}"#.utf8)
        do {
            try await session.sendCode(to: "+12025550135")
            preconditionFailure("Accepted rate-limited request")
        } catch AuthSession.SignInError.rateLimited { }
        precondition(session.pendingPhoneNumber == nil && !session.isBusy)
        await session.signOut()
        precondition(storage.isEmpty && session.user == nil && session.history == nil)
        try await checkPrivateHistory(configuration: configuration, transport: transport)
        print("Native SMS checks passed: real SDK payloads, connection/grant errors, resend cooldown, invalid codes, token validation, and no saved credentials on failure. No real SMS or network requests were sent.")
    }

    @MainActor
    private static func checkPrivateHistory(configuration: AuthConfiguration, transport: URLSession) async throws {
        let storage = MemoryCredentialsStorage()
        let authentication = Auth0.authentication(clientId: configuration.clientID, domain: configuration.domain, session: transport)
        let manager = CredentialsManager(authentication: authentication, storage: storage)
        // This fixture represents credentials already validated at login; storage is memory-only.
        let payload = Data(#"{"sub":"sms|opaque-profile-owner"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        try manager.store(credentials: Credentials(accessToken: "PRIVATE-READINGS-TEST", tokenType: "Bearer",
                                                  idToken: "eyJhbGciOiJSUzI1NiJ9.\(payload).fixture", expiresAt: .now.addingTimeInterval(3600)))
        let session = AuthSession(configuration: configuration, transport: transport, storage: storage)
        await session.restore()
        precondition(session.isSignedIn && session.profileOwner == "sms|opaque-profile-owner")
        AuthStub.status = 200
        AuthStub.payload = try historyPage(ids: ["a", "b"], offset: 0, hasMore: true)
        await session.checkAPI()
        precondition(session.history?.items.map(\.id) == ["a", "b"] && session.apiMessage == nil)
        AuthStub.payload = try historyPage(ids: ["b", "c"], offset: 2, hasMore: false)
        await session.checkAPI(loadMore: true)
        precondition(session.history?.items.map(\.id) == ["a", "b", "c"])
        let query = URLComponents(url: AuthStub.requests.last!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.contains(URLQueryItem(name: "offset", value: "2")))
        let count = AuthStub.requests.count
        await session.checkAPI(loadMore: true)
        precondition(AuthStub.requests.count == count)
        AuthStub.status = 503
        await session.checkAPI()
        precondition(session.isSignedIn && session.history?.items.count == 3 && session.apiMessage != nil)
        do {
            _ = try await session.loadProfile()
            preconditionFailure("Accepted unavailable profile")
        } catch { }
        precondition(session.isSignedIn && session.profileOwner != nil && !storage.isEmpty)
        AuthStub.status = 200
        AuthStub.payload = Data(#"{"user_id":"sms|opaque-profile-owner","display_name":null,"profile_picture":null,"created_at":null,"updated_at":null}"#.utf8)
        let emptyProfile = try await session.loadProfile()
        precondition(emptyProfile.displayName == nil)
        precondition(AuthStub.requests.last!.value(forHTTPHeaderField: "Authorization") == "Bearer PRIVATE-READINGS-TEST")
        AuthStub.payload = Data(#"{"user_id":"sms|opaque-profile-owner","display_name":"Liam","profile_picture":null,"created_at":null,"updated_at":null}"#.utf8)
        let savedProfile = try await session.saveProfile(name: "Liam", photoData: nil)
        precondition(savedProfile.displayName == "Liam" && AuthStub.requests.last!.httpMethod == "PUT")
        let profilePut = try body(AuthStub.requests.last!)
        precondition(profilePut["profile_picture"] is NSNull && profilePut["user_id"] == nil)
        AuthStub.payload = Data(#"{"user_id":"sms|foreign-owner","display_name":"Foreign","profile_picture":null,"created_at":null,"updated_at":null}"#.utf8)
        do {
            _ = try await session.loadProfile()
            preconditionFailure("Accepted a profile for a different subject")
        } catch KickBACAPI.APIError.invalidResponse { }
        precondition(session.isSignedIn)
        AuthStub.status = 401
        do {
            _ = try await session.loadProfile()
            preconditionFailure("Accepted unauthorized profile")
        } catch KickBACAPI.APIError.unauthorized { }
        precondition(!session.isSignedIn && session.history == nil && session.profileOwner == nil && storage.isEmpty)
        // Repeat the history-specific expiry path with a newly restored session.
        try manager.store(credentials: Credentials(accessToken: "PRIVATE-READINGS-TEST", tokenType: "Bearer",
                                                  idToken: "eyJhbGciOiJSUzI1NiJ9.\(payload).fixture", expiresAt: .now.addingTimeInterval(3600)))
        let historySession = AuthSession(configuration: configuration, transport: transport, storage: storage)
        await historySession.restore()
        AuthStub.status = 401
        await historySession.checkAPI()
        precondition(!historySession.isSignedIn && historySession.history == nil && historySession.profileOwner == nil && storage.isEmpty)
        print("Private API checks passed: restored owner, profile load/save/access-token headers, owner mismatch, pagination, API downtime, and clearing private data after profile/history expiry.")
    }

    private static func historyPage(ids: [String], offset: Int, hasMore: Bool) throws -> Data {
        let items: [[String: Any]] = ids.map { id in
            ["id": id, "session_id": "session", "device_id": "test-device",
             "raw": ["sensor": "mq3", "value": 1200, "unit": "adc_counts"],
             "breath_duration_ms": 2500, "source": "simulator", "received_at": "2026-10-17T01:00:05Z"]
        }
        return try JSONSerialization.data(withJSONObject: ["items": items, "offset": offset, "limit": 2, "has_more": hasMore])
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                bytes.append(buffer, count: count)
            }
            data = bytes
        } else {
            preconditionFailure("Missing JSON request body")
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

// The checks issue one awaited request at a time.
private final class AuthStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = request.url?.path == "/v1/me" ? Data(#"{"user_id":"sms|opaque-profile-owner"}"#.utf8) : Self.payload
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class MemoryCredentialsStorage: CredentialsStorage {
    private let lock = NSLock()
    private var entries: [String: Data] = [:]
    var isEmpty: Bool { lock.withLock { entries.isEmpty } }
    func getEntry(forKey key: String) throws -> Data {
        try lock.withLock {
            guard let data = entries[key] else { throw Missing.entry }
            return data
        }
    }
    func setEntry(_ data: Data, forKey key: String) throws { lock.withLock { entries[key] = data } }
    func deleteEntry(forKey key: String) throws { lock.withLock { _ = entries.removeValue(forKey: key) } }
    func deleteAllEntries() throws { lock.withLock { entries.removeAll() } }
    private enum Missing: Error { case entry }
}
