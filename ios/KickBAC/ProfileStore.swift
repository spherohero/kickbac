import CryptoKit
import Foundation
import Observation

nonisolated struct PartyProfile: Codable, Equatable, Sendable {
    var name = ""
    var photoData: Data?

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(trimmed.unicodeScalars.count)
            && !trimmed.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

@MainActor @Observable
final class ProfileStore {
    private(set) var profile = PartyProfile()
    private(set) var owner: String?
    private(set) var message: String?
    private(set) var remoteState: RemoteState = .unknown
    private(set) var isLoading = false
    private(set) var isSaving = false
    private var generation = UUID()
    private let directory: URL

    enum RemoteState: Equatable { case unknown, missing, saved }
    var needsOnboarding: Bool { remoteState == .missing }

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Profiles")) {
        self.directory = directory
    }

    func load(owner: String?) {
        guard self.owner != owner else { return }
        generation = UUID()
        self.owner = owner
        profile = PartyProfile()
        message = nil
        remoteState = .unknown
        isLoading = false
        isSaving = false
        guard let owner else { return }
        let url = fileURL(for: owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            profile = try JSONDecoder().decode(PartyProfile.self, from: Data(contentsOf: url))
        } catch {
            message = "Couldn't load your profile on this iPhone."
        }
    }

    func refresh(fetch: () async throws -> APIProfile) async {
        guard owner != nil, !isLoading, !isSaving else { return }
        let requestGeneration = generation
        isLoading = true
        message = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let response = try await fetch()
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            try accept(response)
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            message = "Couldn't load your saved profile. Check your connection and retry."
        }
    }

    func save(name: String, photoData: Data?, persist: (String, Data?) async throws -> APIProfile) async throws {
        guard owner != nil else { throw SaveError.signedOut }
        guard !isSaving, !isLoading, remoteState != .unknown else { throw SaveError.notReady }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PartyProfile.isValidName(name) else { throw SaveError.invalidName }
        generation = UUID()
        let requestGeneration = generation
        isSaving = true
        message = nil
        defer { if generation == requestGeneration { isSaving = false } }
        let prepared: Data?
        if remoteState == .saved, photoData == profile.photoData {
            // Keep the server's sanitized bytes for name-only edits, avoiding repeated JPEG loss.
            prepared = photoData
        } else if let photoData {
            prepared = try await Task.detached(priority: .userInitiated) { try ProfilePhoto.prepare(photoData) }.value
        } else {
            prepared = nil
        }
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw SaveError.signedOut }
        let response = try await persist(name, prepared)
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw SaveError.signedOut }
        guard response.displayName != nil else { throw KickBACAPI.APIError.invalidResponse }
        try accept(response)
    }

    private func accept(_ response: APIProfile) throws {
        guard let owner, response.userID == owner else { throw SaveError.signedOut }
        // Keep an older local-only profile as an onboarding draft; never upload it automatically.
        guard let name = response.displayName else { remoteState = .missing; return }
        guard PartyProfile.isValidName(name),
              response.profilePicture.map({ $0.contentType == "image/jpeg" && $0.data.count <= 524_288 }) ?? true else {
            throw KickBACAPI.APIError.invalidResponse
        }
        remoteState = .saved
        let updated = PartyProfile(name: name, photoData: response.profilePicture?.data)
        profile = updated
        do {
            try cache(updated, owner: owner)
        } catch {
            // The server save succeeded; a cache failure must not report an unsuccessful save.
            message = "Your profile is saved online, but couldn't be cached on this iPhone."
        }
    }

    private func cache(_ updated: PartyProfile, owner: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: fileURL(for: owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func fileURL(for owner: String) -> URL {
        // Auth0 subjects are opaque; never use them as paths or link by phone number.
        let key = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".json")
    }

    enum SaveError: LocalizedError {
        case signedOut, invalidName, notReady
        var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in to save your profile."
            case .invalidName: "Use a name between 1 and 80 characters, without control characters."
            case .notReady: "Load your saved profile before making changes. Please retry."
            }
        }
    }
}
