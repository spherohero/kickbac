import Auth0
import Foundation
import Observation
import JWTDecode
import SimpleKeychain

@MainActor @Observable
final class AuthSession {
    private(set) var isSignedIn = false
    private(set) var isRestoring = true
    private(set) var isAuthenticating = false
    private(set) var isCheckingAPI = false
    private(set) var user: APIUser?
    private(set) var history: MeasurementPage?
    private(set) var stats: APIStats?
    private(set) var statsMessage: String?
    private(set) var isLoadingStats = false
    private(set) var message: String?
    private(set) var apiMessage: String?
    private(set) var generation = UUID()
    private(set) var profileOwner: String?
    private(set) var pendingPhoneNumber: String?
    private(set) var resendAvailableAt: Date?

    @ObservationIgnored private let configuration: AuthConfiguration?
    @ObservationIgnored private let credentialsManager: CredentialsManager?
    @ObservationIgnored private let api: KickBACAPI?
    @ObservationIgnored private let authentication: (any Authentication)?
    @ObservationIgnored private var didRestore = false

    var isBusy: Bool { isRestoring || isAuthenticating }

    init(configuration: AuthConfiguration? = try? AuthConfiguration.load(),
         transport: URLSession? = nil, storage: (any CredentialsStorage)? = nil) {
        self.configuration = configuration
        if let configuration {
            let authentication = Auth0.authentication(clientId: configuration.clientID,
                                                      domain: configuration.domain, session: transport ?? .shared)
            self.authentication = authentication
            let safeStorage = SessionCredentialsStorage(base: storage ?? SimpleKeychain())
            credentialsManager = CredentialsManager(authentication: authentication, storage: safeStorage)
            api = KickBACAPI(baseURL: configuration.apiBaseURL, session: transport)
        } else {
            credentialsManager = nil
            api = nil
            authentication = nil
        }
    }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        defer { isRestoring = false }
        guard let credentialsManager else { return }
        do {
            let credentials = try await credentialsManager.credentials(minTTL: 30)
            resetPrivateData()
            profileOwner = try? decode(jwt: credentials.idToken).subject
            isSignedIn = true
        } catch {
            // No stored session or an expired token without offline_access requires login again.
            isSignedIn = false
            return
        }
    }

    func sendCode(to phoneNumber: String) async throws {
        guard !isBusy else { throw SignInError.busy }
        guard let configuration, let authentication else { throw SignInError.configuration }
        let digits = phoneNumber.dropFirst()
        guard phoneNumber.first == "+", (2...15).contains(digits.count), digits.first != "0",
              digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw SignInError.invalidPhone }
        if pendingPhoneNumber == phoneNumber, let resendAvailableAt, resendAvailableAt > .now {
            throw SignInError.cooldown
        }
        isAuthenticating = true
        message = nil
        defer { isAuthenticating = false }
        do {
            try await authentication
                .startPasswordless(phoneNumber: phoneNumber, type: .code, connection: configuration.connection)
                .start()
        } catch let error as AuthenticationError {
            throw Self.loginError(error, sendingCode: true)
        } catch {
            throw SignInError.sendFailed
        }
        pendingPhoneNumber = phoneNumber
        resendAvailableAt = .now.addingTimeInterval(30)
    }

    func verifyCode(_ code: String) async throws {
        guard !isBusy else { throw SignInError.busy }
        guard let configuration, let authentication, credentialsManager != nil else { throw SignInError.configuration }
        guard let phoneNumber = pendingPhoneNumber else { throw SignInError.missingCode }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw SignInError.invalidCode }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let credentials: Credentials
        do {
            // Auth0 verifies the OTP and issues tokens; no browser or Twilio secret is involved.
            credentials = try await authentication
                .login(phoneNumber: phoneNumber, code: code, audience: configuration.audience, scope: configuration.scope)
                .validateClaims()
                .start()
        } catch let error as AuthenticationError {
            throw Self.loginError(error, sendingCode: false)
        } catch {
            throw SignInError.verificationFailed
        }
        try storeValidatedCredentials(credentials)
    }

    // Called only after Auth0's code exchange and ID-token claims validation succeed.
    func storeValidatedCredentials(_ credentials: Credentials) throws {
        guard let credentialsManager else { throw SignInError.configuration }
        resetPrivateData()
        isSignedIn = false
        do {
            // Clear prior account-bound SDK metadata before saving a new login.
            try credentialsManager.clear()
            try credentialsManager.store(credentials: credentials)
        } catch {
            throw SignInError.storage((error as? SimpleKeychainError)?.status)
        }
        clearPhoneChallenge()
        profileOwner = try? decode(jwt: credentials.idToken).subject
        isSignedIn = true
        // The root view loads the API independently so deployment failures never block onboarding.
    }

    func clearPhoneChallenge() {
        pendingPhoneNumber = nil
        resendAvailableAt = nil
    }

    func loadProfile() async throws -> APIProfile {
        try await userRequest({ api, token in try await api.profile(accessToken: token) }, owner: { $0.userID })
    }

    func saveProfile(name: String, photoData: Data?) async throws -> APIProfile {
        try await userRequest({ api, token in
            try await api.saveProfile(name: name, photoData: photoData, accessToken: token)
        }, owner: { $0.userID })
    }

    func resolveDevice(_ id: String) async throws -> DeviceResolution {
        guard let api else { throw SignInError.configuration }
        return try await api.resolveDevice(id)
    }

    var apiBaseURL: URL? { configuration?.apiBaseURL }

    func device(_ id: String) async throws -> APIDevice {
        try await userRequest { api, token in try await api.device(id, accessToken: token) }
    }

    func armDevice(_ id: String) async throws -> APITestSession {
        try await userRequest({ api, token in try await api.armDevice(id, accessToken: token) }, owner: { $0.userID })
    }

    func testSession(_ id: String) async throws -> APITestSession {
        try await userRequest({ api, token in try await api.testSession(id, accessToken: token) }, owner: { $0.userID })
    }

    func cancelSession(_ id: String) async throws -> APITestSession {
        try await userRequest({ api, token in try await api.cancelSession(id, accessToken: token) }, owner: { $0.userID })
    }

    func loadStats() async {
        guard isSignedIn, !isLoadingStats else { return }
        let requestGeneration = generation
        isLoadingStats = true
        statsMessage = nil
        defer { if generation == requestGeneration { isLoadingStats = false } }
        do {
            let loaded = try await userRequest({ api, token in try await api.stats(accessToken: token) }, owner: { $0.userID })
            guard generation == requestGeneration else { return }
            stats = loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            statsMessage = "Couldn't load your game stats. Pull to refresh and try again."
        }
    }

    private func userRequest<Response>(_ operation: (KickBACAPI, String) async throws -> Response,
                                       owner: (Response) -> String? = { _ in nil }) async throws -> Response {
        guard isSignedIn, let credentialsManager, let api, let profileOwner else { throw KickBACAPI.APIError.unauthorized }
        let requestGeneration = generation
        do {
            let credentials = try await credentialsManager.credentials(minTTL: 30)
            guard generation == requestGeneration, isSignedIn else { throw CancellationError() }
            let response = try await operation(api, credentials.accessToken)
            guard generation == requestGeneration, isSignedIn else { throw CancellationError() }
            if let responseOwner = owner(response), responseOwner != profileOwner { throw KickBACAPI.APIError.invalidResponse }
            return response
        } catch {
            if generation == requestGeneration,
               (error as? KickBACAPI.APIError == .unauthorized || error is CredentialsManagerError) {
                try? credentialsManager.clear()
                resetPrivateData()
                isSignedIn = false
                message = "Please sign in again."
            }
            throw error
        }
    }

    private static func loginError(_ error: AuthenticationError, sendingCode: Bool) -> SignInError {
        let detail = (error.info["error_description"] as? String ?? "").lowercased()
        if detail.contains("connection is not enabled") { return .connectionUnavailable }
        if error.code == "unauthorized_client" || error.code == "unsupported_grant_type" { return .grantUnavailable }
        if error.statusCode == 429 || error.isTooManyAttempts { return .rateLimited }
        if !sendingCode && (error.code == "invalid_grant" || error.code == "expired_token" || error.isInvalidCredentials) {
            return .invalidCode
        }
        return sendingCode ? .sendFailed : .verificationFailed
    }

    func checkAPI(loadMore: Bool = false) async {
        guard isSignedIn, !isCheckingAPI, let credentialsManager, let api else { return }
        if loadMore && history?.hasMore != true { return }
        let previousPage = loadMore ? history : nil
        let requestGeneration = generation
        isCheckingAPI = true
        apiMessage = nil
        defer { if generation == requestGeneration { isCheckingAPI = false } }

        do {
            let credentials = try await credentialsManager.credentials(minTTL: 30)
            let currentUser = try await api.currentUser(accessToken: credentials.accessToken)
            let privateHistory = try await api.measurements(
                accessToken: credentials.accessToken,
                offset: previousPage.map { $0.offset + $0.limit } ?? 0
            )
            guard generation == requestGeneration, isSignedIn else { return }
            user = currentUser
            if let previousPage {
                var seen = Set(previousPage.items.map(\.id))
                let newItems = privateHistory.items.filter { seen.insert($0.id).inserted }
                history = MeasurementPage(items: previousPage.items + newItems, limit: privateHistory.limit,
                                          offset: privateHistory.offset, hasMore: privateHistory.hasMore)
            } else {
                history = privateHistory
            }
        } catch KickBACAPI.APIError.unauthorized {
            guard generation == requestGeneration else { return }
            try? credentialsManager.clear()
            resetPrivateData()
            isSignedIn = false
            message = "Please sign in again."
        } catch is CredentialsManagerError {
            guard generation == requestGeneration else { return }
            resetPrivateData()
            isSignedIn = false
            message = "Your session has expired. Sign in again."
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            apiMessage = "Can't reach kickBAC right now. Your sign-in is saved."
        }
    }

    func signOut() async {
        guard !isBusy, let credentialsManager else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            // Native SMS login has no browser session to clear.
            try credentialsManager.clear()
            clearPhoneChallenge()
            resetPrivateData()
            isSignedIn = false
            message = nil
        } catch {
            message = "Couldn't sign out securely. Please try again."
        }
    }

    private func resetPrivateData() {
        generation = UUID()
        user = nil
        profileOwner = nil
        history = nil
        stats = nil
        statsMessage = nil
        isLoadingStats = false
        apiMessage = nil
        isCheckingAPI = false
    }

    enum SignInError: LocalizedError {
        case busy, configuration, connectionUnavailable, grantUnavailable, invalidPhone
        case cooldown, rateLimited, missingCode, invalidCode, sendFailed, verificationFailed
        case storage(Int32?)
        var errorDescription: String? {
            switch self {
            case .busy: "Please wait for sign-in to finish."
            case .configuration: "Sign-in isn't configured. Please try again later."
            case .connectionUnavailable: "SMS sign-in isn't enabled for this app yet."
            case .grantUnavailable: "SMS sign-in isn't configured yet. Please try again later."
            case .invalidPhone: "Enter a valid phone number."
            case .cooldown: "Wait a moment before requesting another code."
            case .rateLimited: "Too many attempts. Wait a little, then try again."
            case .missingCode: "Request a new code to continue."
            case .invalidCode: "That code is incorrect or expired. Try again or resend it."
            case .sendFailed: "Couldn't send your code. Please try again."
            case .verificationFailed: "Couldn't verify your code. Please try again."
            case .storage(let status): "Couldn't save your sign-in securely. Please try again." + (status.map { " (Keychain \($0))" } ?? "")
            }
        }
    }
}
