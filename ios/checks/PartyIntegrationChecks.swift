import Foundation

@main
struct PartyIntegrationChecks {
    static let partyID = "11111111-1111-4111-8111-111111111111"
    static let gameID = "22222222-2222-4222-8222-222222222222"
    static let sessionID = "33333333-3333-4333-8333-333333333333"
    static let owner = "sms|party-test-owner"
    static let device = "kb-demo-01"

    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "kickbac-party-checks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let flow = DeviceSessionStore(directory: directory.appending(path: "sessions"))
        flow.switchOwner(owner)
        let store = PartyStore(directory: directory.appending(path: "parties"))
        store.switchOwner(owner)
        let create = try PartyWrite.create(name: " Friday ", id: partyID)
        precondition(create.name == "Friday")
        var sends = 0
        let first = await store.submit(create, deviceFlow: flow) { write in
            sends += 1
            let restored = PartyStore(directory: directory.appending(path: "parties"))
            restored.switchOwner(owner)
            precondition(restored.pending == write, "UUID and exact bytes must be durable BEFORE network send")
            throw URLError(.timedOut)
        }
        precondition(!first && sends == 1 && store.pending == create)
        let replaced = await store.submit(try PartyWrite.create(name: "Changed"), deviceFlow: flow) { _ in
            preconditionFailure("A new UUID bypassed an ambiguous request")
        }
        precondition(!replaced && store.pending == create)
        let restored = PartyStore(directory: directory.appending(path: "parties"))
        restored.switchOwner(owner)
        let retry = await restored.submit(nil, deviceFlow: flow) { write in
            precondition(write == create && write.body == create.body)
            return .party(party())
        }
        precondition(retry && restored.pending == nil && restored.party?.id == partyID)

        let request = try PartyWrite.checkIn(partyID: partyID, deviceID: device, gameInstanceID: nil)
        let json = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        precondition(json.count == 3 && json["game_instance_id"] is NSNull, "Null must explicitly mean party-only")
        let uncertain = await restored.submit(request, deviceFlow: flow) { _ in throw URLError(.notConnectedToInternet) }
        precondition(!uncertain && restored.pending == request && flow.test == nil)
        restored.discardRejectedRequest()
        precondition(restored.pending == request && !restored.canDiscardPending,
                     "An ambiguous request cannot be discarded or replaced")
        let relaunched = PartyStore(directory: directory.appending(path: "parties"))
        relaunched.switchOwner(owner)
        let reserved = await relaunched.submit(nil, deviceFlow: flow) { write in
            precondition(write == request)
            return .checkIn(checkIn(write: write))
        }
        precondition(reserved && flow.sessionID == sessionID && flow.test?.status == .armed)
        let restoredFlow = DeviceSessionStore(directory: directory.appending(path: "sessions"))
        restoredFlow.switchOwner(owner)
        precondition(restoredFlow.sessionID == sessionID)
        var completions = 0
        await restoredFlow.poll(fetch: { id in
            precondition(id == sessionID)
            return test(.complete, measurement: try manualReading())
        }, onComplete: { completions += 1 })
        precondition(completions == 1 && !restoredFlow.hasActiveSession && restoredFlow.test?.measurement?.bacReading == nil)
        precondition(restoredFlow.test?.measurement?.durationText == "Sample window: 5.00 s")
        let terminal = checkIn(write: request, session: test(.expired))
        try restoredFlow.adoptCheckIn(terminal.session, expectedOwner: owner)
        precondition(restoredFlow.test?.status == .expired && !restoredFlow.hasActiveSession)
        try restoredFlow.adoptCheckIn(test(.cancelled), expectedOwner: owner)
        precondition(!restoredFlow.hasActiveSession)
        let otherSession = test(.armed, id: "44444444-4444-4444-8444-444444444444")
        try restoredFlow.adoptCheckIn(otherSession, expectedOwner: owner)
        do {
            try restoredFlow.adoptCheckIn(test(.armed), expectedOwner: owner)
            preconditionFailure("Replaced an unrelated active session")
        } catch DeviceSessionStore.FlowError.activeTest { }
        precondition(restoredFlow.sessionID == otherSession.id)

        let accountStore = PartyStore(directory: directory.appending(path: "account-switch"))
        accountStore.switchOwner(owner)
        let switched = await accountStore.submit(create, deviceFlow: flow) { _ in
            accountStore.switchOwner("sms|another-owner")
            return .party(party())
        }
        precondition(!switched && accountStore.party == nil && accountStore.pending == nil)
        accountStore.switchOwner(owner)
        precondition(accountStore.pending == create, "Previous owner's uncertain request remains recoverable")
        let foreignStore = PartyStore(directory: directory.appending(path: "foreign"))
        foreignStore.switchOwner(owner)
        let foreignFlow = DeviceSessionStore(directory: directory.appending(path: "foreign-sessions"))
        foreignFlow.switchOwner(owner)
        let foreign = await foreignStore.submit(request, deviceFlow: foreignFlow) { _ in
            .checkIn(checkIn(write: request, session: test(.armed, owner: "sms|foreign")))
        }
        precondition(!foreign && foreignStore.pending == request && foreignFlow.test == nil)
        let rejected = await foreignStore.submit(nil, deviceFlow: foreignFlow) { _ in
            throw KickBACAPI.APIError.server(status: 409, code: "device_busy")
        }
        precondition(!rejected && foreignStore.canDiscardPending)
        foreignStore.discardRejectedRequest()
        precondition(foreignStore.pending == nil)
        let fresh = try PartyWrite.checkIn(partyID: partyID, deviceID: device, gameInstanceID: nil)
        precondition(fresh.id != request.id, "A new deliberate attempt gets a new UUID")
        let conflict = await foreignStore.submit(fresh, deviceFlow: foreignFlow) { _ in
            throw KickBACAPI.APIError.server(status: 409, code: "idempotency_conflict")
        }
        precondition(!conflict && !foreignStore.canDiscardPending)
        foreignStore.discardRejectedRequest()
        precondition(foreignStore.pending == fresh, "Never use a new UUID to bypass a retry conflict")
        let canonical = try PartyWrite.create(name: "Friday", id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
        precondition(canonical.id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

        let failedDirectory = directory.appending(path: "not-a-directory")
        try Data("fixture".utf8).write(to: failedDirectory)
        let diskFailure = PartyStore(directory: failedDirectory)
        diskFailure.switchOwner(owner)
        let unsaved = await diskFailure.submit(create, deviceFlow: flow) { _ in preconditionFailure("Sent without durable retry bytes") }
        precondition(!unsaved)

        let history = CheckInHistoryStore()
        history.switchOwner(owner)
        let item = checkIn(write: request, session: test(.complete, measurement: try manualReading()))
        await history.load { offset in
            precondition(offset == 0)
            return PartyPage(items: [item], limit: 1, offset: 0, hasMore: true)
        }
        await history.load(more: true) { offset in
            precondition(offset == 1)
            throw URLError(.timedOut)
        }
        precondition(history.page?.items.count == 1 && history.page?.hasMore == true && history.message != nil)
        await history.load(more: true) { offset in PartyPage(items: [item], limit: 1, offset: offset, hasMore: false) }
        precondition(history.page?.items.count == 1 && history.page?.hasMore == false)
        await history.load { _ in
            PartyPage(items: [checkIn(write: request, session: test(.complete, measurement: try manualReading(), owner: "sms|foreign"))], limit: 1, offset: 0, hasMore: false)
        }
        precondition(history.page?.items.first?.session.userID == owner && history.message != nil)
        await history.load { _ in
            history.switchOwner("sms|another-owner")
            return PartyPage(items: [item], limit: 1, offset: 0, hasMore: false)
        }
        precondition(history.page == nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PartyAPIStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let api = KickBACAPI(baseURL: URL(string: "https://api.kickbac.vodka")!, session: transport)
        PartyAPIStub.payload = try JSONSerialization.data(withJSONObject: [
            "check_in_id": request.id, "party_id": partyID, "game_instance_id": NSNull(),
            "session": ["id": sessionID, "device_id": device, "user_id": owner, "status": "ARMED",
                        "created_at": "2026-10-18T10:00:00Z", "expires_at": "2026-10-18T10:01:00Z", "completed_at": NSNull(), "measurement": NSNull()]
        ])
        guard case .checkIn(let decoded) = try await api.partyWrite(request, accessToken: "synthetic-api-token") else { preconditionFailure() }
        precondition(decoded.id == request.id && decoded.session.id == sessionID && decoded.gameInstanceID == nil)
        precondition(PartyAPIStub.lastRequest?.httpBody == request.body)
        precondition(PartyAPIStub.lastRequest?.url?.path == "/v1/parties/\(partyID)/check-ins")
        precondition(PartyAPIStub.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-api-token")
        PartyAPIStub.payload = try JSONSerialization.data(withJSONObject: ["party_id": partyID, "name": "Friday", "state": "OPEN", "role": "host", "member_count": 1, "device_id": NSNull(), "join_code": "ABCDEFGH"])
        _ = try await api.joinParty(code: " abcdefgh ", accessToken: "synthetic-api-token")
        let joined = try JSONSerialization.jsonObject(with: PartyAPIStub.lastRequest!.httpBody!) as! [String: String]
        precondition(joined == ["join_code": "ABCDEFGH"])
        precondition(PartyAPIStub.lastRequest?.url?.path == "/v1/parties/join")
        do { _ = try await api.joinParty(code: "KICK26", accessToken: "synthetic-api-token"); preconditionFailure("Accepted debug fixture as live code") }
        catch KickBACAPI.APIError.invalidRequest { }
        print("Party integration checks passed: durable exact retries, relaunch, account fencing, shared-session adoption, expiry/cancel/busy, manual null BAC, pagination recovery, live wire/auth and code validation")
    }
    static func party() -> APIParty { APIParty(partyID: partyID, name: "Friday", state: "OPEN", role: "host", memberCount: 1, deviceID: device, joinCode: "ABCDEFGH") }
    static func test(_ status: APITestSession.Status, measurement: APIMeasurement? = nil, owner: String = owner, id: String = sessionID) -> APITestSession {
        APITestSession(id: id, deviceID: device, userID: owner, status: status, createdAt: "2026-10-18T10:00:00Z", expiresAt: "2026-10-18T10:01:00Z", completedAt: nil, measurement: measurement)
    }
    static func checkIn(write: PartyWrite, session: APITestSession = test(.armed)) -> APICheckIn {
        APICheckIn(checkInID: write.id, partyID: partyID, gameInstanceID: write.gameInstanceID, session: session)
    }
    static func manualReading() throws -> APIMeasurement {
        let url = URL(filePath: "ios/checks/fixtures/acquisition.json")
        let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var manual = fixtures["manual"] as! [String: Any]
        manual["session_id"] = sessionID; manual["device_id"] = device
        return try JSONDecoder().decode(APIMeasurement.self, from: JSONSerialization.data(withJSONObject: manual))
    }
}

final class PartyAPIStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
            captured.httpBody = data
        }
        Self.lastRequest = captured
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
