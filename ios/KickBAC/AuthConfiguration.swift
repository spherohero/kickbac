import Foundation

nonisolated struct AuthConfiguration {
    let domain: String
    let clientID: String
    let audience: String
    let callbackURL: URL
    let apiBaseURL: URL
    let connection = "sms"
    let scope = "openid profile"

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "Auth0", withExtension: "plist"),
              let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String],
              let bundleID = bundle.bundleIdentifier else {
            throw ConfigurationError.invalid
        }
        return try Self(values: values, bundleID: bundleID)
    }

    init(values: [String: String], bundleID: String) throws {
        guard let domain = values["Domain"], !domain.isEmpty,
              let clientID = values["ClientId"], !clientID.isEmpty,
              let audience = values["Audience"], audience == "https://kickbac-api",
              bundleID == "com.liam.KickBAC",
              let issuer = URLComponents(string: "https://\(domain)"),
              issuer.host == domain, issuer.path.isEmpty, issuer.query == nil, issuer.fragment == nil,
              let callback = URL(string: "\(bundleID)://\(domain)/ios/\(bundleID)/callback"),
              let base = values["APIBaseURL"].flatMap(URL.init(string:)),
              base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else {
            throw ConfigurationError.invalid
        }
        self.domain = domain
        self.clientID = clientID
        self.audience = audience
        callbackURL = callback
        apiBaseURL = base
    }

    enum ConfigurationError: Error { case invalid }
}
