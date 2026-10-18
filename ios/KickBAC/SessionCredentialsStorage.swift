import Auth0
import Foundation
import Security
import SimpleKeychain

nonisolated struct SessionCredentialsStorage: CredentialsStorage {
    let base: any CredentialsStorage

    func getEntry(forKey key: String) throws -> Data { try base.getEntry(forKey: key) }
    func setEntry(_ data: Data, forKey key: String) throws { try base.setEntry(data, forKey: key) }

    func deleteEntry(forKey key: String) throws {
        do {
            try base.deleteEntry(forKey: key)
        } catch let error as SimpleKeychainError where error.status == errSecItemNotFound {
            // Empty is already cleared. Continue so the SDK also removes old session metadata.
        }
    }

    func deleteAllEntries() throws { try base.deleteAllEntries() }
}
