import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class DeviceSessionStore {
    private(set) var targetID: String?
    private(set) var device: APIDevice?
    private(set) var test: APITestSession?
    private(set) var sessionID: String?
    private(set) var owner: String?
    private(set) var message: String?
    private(set) var isBusy = false
    private(set) var pollID = UUID()
    private var generation = UUID()
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "DeviceSessions")) {
        self.directory = directory
    }

    var hasActiveSession: Bool { sessionID != nil }

    func switchOwner(_ owner: String?) {
        guard self.owner != owner else { return }
        generation = UUID()
        pollID = UUID()
        self.owner = owner
        sessionID = nil
        test = nil
        device = nil
        message = nil
        isBusy = false
        if let owner, let data = try? Data(contentsOf: cacheURL(owner)),
           let pending = try? JSONDecoder().decode(Pending.self, from: data),
           UUID(uuidString: pending.id) != nil, DeviceTarget.isValidID(pending.deviceID) {
            sessionID = pending.id
            targetID = pending.deviceID
        }
    }

    func select(_ input: String, baseURL: URL) throws {
        guard !hasActiveSession, !isBusy else { throw FlowError.activeTest }
        let id = try DeviceTarget.parse(input, baseURL: baseURL)
        generation = UUID()
        targetID = id
        device = nil
        test = nil
        message = nil
    }

    func inspect(resolve: (String) async throws -> DeviceResolution,
                 fetch: (String) async throws -> APIDevice?) async {
        guard let targetID, !isBusy, !hasActiveSession else { return }
        let requestGeneration = generation
        isBusy = true
        message = nil
        defer { if generation == requestGeneration { isBusy = false } }
        do {
            let resolved = try await resolve(targetID)
            guard generation == requestGeneration else { return }
            guard resolved.deviceID == targetID else { throw KickBACAPI.APIError.invalidResponse }
            let loaded = try await fetch(targetID)
            guard generation == requestGeneration else { return }
            if let loaded, loaded.id != targetID { throw KickBACAPI.APIError.invalidResponse }
            device = loaded
        } catch {
            guard generation == requestGeneration else { return }
            message = failureMessage(error)
        }
    }

    func arm(create: (String) async throws -> APITestSession) async {
        guard owner != nil, let targetID, device != nil, !isBusy, !hasActiveSession else { return }
        generation = UUID()
        let requestGeneration = generation
        isBusy = true
        message = nil
        defer {
            if generation == requestGeneration { isBusy = false; pollID = UUID() }
        }
        do {
            let started = try await create(targetID)
            guard generation == requestGeneration else { return }
            guard started.deviceID == targetID, started.userID == owner, UUID(uuidString: started.id) != nil,
                  started.status.isActive, started.measurement == nil else {
                throw KickBACAPI.APIError.invalidResponse
            }
            test = started
            sessionID = started.status.isActive ? started.id : nil
            try persist()
        } catch {
            guard generation == requestGeneration else { return }
            message = hasActiveSession ? "Test started. Keep this app open; its session couldn't be saved on this iPhone." : failureMessage(error)
        }
    }

    func poll(fetch: (String) async throws -> APITestSession, onComplete: () async -> Void) async {
        guard let id = sessionID, !isBusy else { return }
        let requestGeneration = generation
        var failures = 0
        while !Task.isCancelled, generation == requestGeneration, sessionID == id {
            do {
                let loaded = try await fetch(id)
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                try accept(loaded, id: id)
                failures = 0
                message = nil
                if !loaded.status.isActive {
                    if loaded.status == .complete { await onComplete() }
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == requestGeneration else { return }
                message = failureMessage(error)
                clearMissingSession(error)
                if isPermanent(error) { return }
                failures += 1
            }
            do { try await Task.sleep(for: .seconds(min(8, 1 << min(failures, 3)))) }
            catch { return }
        }
    }

    func cancel(send: (String) async throws -> APITestSession) async {
        guard let id = sessionID, !isBusy else { return }
        generation = UUID()
        let requestGeneration = generation
        isBusy = true
        message = nil
        defer { if generation == requestGeneration { isBusy = false; pollID = UUID() } }
        do {
            let cancelled = try await send(id)
            guard generation == requestGeneration else { return }
            try accept(cancelled, id: id)
        } catch {
            guard generation == requestGeneration else { return }
            // Retain the session and reload its state; never silently start another test.
            message = failureMessage(error)
            clearMissingSession(error)
        }
    }

    func retryPolling() { pollID = UUID() }

    private func clearMissingSession(_ error: Error) {
        guard let error = error as? KickBACAPI.APIError else { return }
        switch error {
        case .http(404), .server(404, _):
            // The server confirms this private session is unavailable. Release local tracking only.
            sessionID = nil
            test = nil
            try? persist()
        default: break
        }
    }

    private func accept(_ loaded: APITestSession, id: String) throws {
        guard loaded.id == id, loaded.deviceID == targetID, loaded.userID == owner else {
            throw KickBACAPI.APIError.invalidResponse
        }
        guard loaded.status != .complete || loaded.measurement != nil else { throw KickBACAPI.APIError.invalidResponse }
        if let reading = loaded.measurement {
            guard reading.sessionID == id, reading.deviceID == targetID,
                  loaded.status == .complete, reading.hasValidAcquisition else { throw KickBACAPI.APIError.invalidResponse }
        }
        test = loaded
        if !loaded.status.isActive {
            sessionID = nil
            // Cache cleanup cannot turn a successful terminal response into a failed test.
            try? persist()
        }
    }

    private struct Pending: Codable { let id: String; let deviceID: String }

    private func cacheURL(_ owner: String) -> URL {
        let key = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }

    private func persist() throws {
        guard let owner else { return }
        let url = cacheURL(owner)
        if let sessionID, let targetID {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Pending(id: sessionID, deviceID: targetID)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func isPermanent(_ error: Error) -> Bool {
        guard let error = error as? KickBACAPI.APIError else { return false }
        switch error {
        case .unauthorized, .invalidRequest, .invalidResponse: return true
        case .http(let status), .server(let status, _): return [401, 404, 409, 410, 422].contains(status)
        }
    }

    private func failureMessage(_ error: Error) -> String {
        if let error = error as? KickBACAPI.APIError {
            switch error {
            case .unauthorized: return "Sign in again to continue."
            case .http(404), .server(404, _): return "That device or test couldn't be found. Check the device ID."
            case .server(409, "device_busy"): return "This device is being used. Wait for its current test to finish."
            case .http(409), .server(409, _): return "This test has changed. Reload its status before continuing."
            case .http(410), .server(410, _): return "This test expired. Start a new test when you're ready."
            case .invalidResponse: return "Couldn't read the device response. Try reloading its status."
            default: break
            }
        }
        return "Couldn't reach the device service. Check your connection and retry."
    }

    enum FlowError: LocalizedError {
        case activeTest
        var errorDescription: String? { "Finish or cancel the current test before choosing another device." }
    }
}
