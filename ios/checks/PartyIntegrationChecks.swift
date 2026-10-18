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
        checkGameInvitations()
        try await checkSetupCancellation(in: directory, deviceFlow: flow)
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
        _ = try await api.joinParty(deviceID: device, accessToken: "synthetic-api-token")
        let deviceJoin = try JSONSerialization.jsonObject(with: PartyAPIStub.lastRequest!.httpBody!) as! [String: String]
        precondition(deviceJoin == ["device_id": device])
        precondition(PartyAPIStub.lastRequest?.url?.path == "/v1/parties/join")
        _ = try await api.updateParty(partyID, action: "bind", deviceID: device, accessToken: "synthetic-api-token")
        let deviceBind = try JSONSerialization.jsonObject(with: PartyAPIStub.lastRequest!.httpBody!) as! [String: String]
        precondition(deviceBind == ["device_id": device])
        precondition(PartyAPIStub.lastRequest?.httpMethod == "PUT")
        precondition(PartyAPIStub.lastRequest?.url?.path == "/v1/parties/\(partyID)/device")

        // New party setup is a single durable atomic resolve. No legacy create/bind fallback.
        let setup = try PartyWrite.resolve(name: " Friday ", deviceID: device)
        let setupJSON = try JSONSerialization.jsonObject(with: setup.body) as! [String: String]
        precondition(setupJSON == ["request_id": setup.id, "device_id": device, "name": "Friday"])
        precondition(setup.path == "v1/parties/resolve")
        let setupDirectory = directory.appending(path: "atomic-setup")
        let atomic = PartyStore(directory: setupDirectory)
        atomic.switchOwner(owner)
        let timedOut = await atomic.submit(setup, deviceFlow: flow) { write in
            let durable = PartyStore(directory: setupDirectory)
            durable.switchOwner(owner)
            precondition(durable.pending == write)
            throw URLError(.timedOut)
        }
        precondition(!timedOut && atomic.party == nil && !atomic.canDiscardPending)
        let atomicRetry = PartyStore(directory: setupDirectory)
        atomicRetry.switchOwner(owner)
        let unlinkedResponse = APIParty(partyID: partyID, name: "Friday", state: "OPEN", role: "host",
                                        memberCount: 1, deviceID: nil, joinCode: "ABCDEFGH")
        let unlinkedAccepted = await atomicRetry.submit(nil, deviceFlow: flow) { write in
            precondition(write == setup && write.body == setup.body)
            return .resolved(APIPartyResolution(action: .created, party: unlinkedResponse))
        }
        precondition(!unlinkedAccepted && atomicRetry.party == nil && atomicRetry.pending == setup,
                     "Unlinked atomic setup must never open a party or report success")
        let wrongDevice = APIParty(partyID: partyID, name: "Friday", state: "OPEN", role: "host",
                                   memberCount: 1, deviceID: "kb-other", joinCode: "ABCDEFGH")
        let mismatched = await atomicRetry.submit(nil, deviceFlow: flow) { _ in
            .resolved(APIPartyResolution(action: .created, party: wrongDevice))
        }
        precondition(!mismatched && atomicRetry.party == nil && atomicRetry.pending == setup)
        let existingRoom = APIParty(partyID: partyID, name: "Already running", state: "OPEN", role: "member",
                                    memberCount: 2, deviceID: device, joinCode: nil)
        PartyAPIStub.payload = try JSONSerialization.data(withJSONObject: ["action": "joined", "party": [
            "party_id": partyID, "name": existingRoom.name, "state": "OPEN", "role": "member",
            "member_count": 2, "device_id": device, "join_code": NSNull()]])
        let joinedExisting = await atomicRetry.submit(nil, deviceFlow: flow) { write in
            try await api.partyWrite(write, accessToken: "synthetic-api-token")
        }
        precondition(joinedExisting && atomicRetry.pending == nil && atomicRetry.party?.name == existingRoom.name
                     && atomicRetry.party?.role == "member" && atomicRetry.party?.deviceID == device)
        precondition(PartyAPIStub.lastRequest?.url?.path == "/v1/parties/resolve"
                     && PartyAPIStub.lastRequest?.httpMethod == "POST" && PartyAPIStub.lastRequest?.httpBody == setup.body)
        // Deployed server does not yet expose resolve: one rejected call, no orphan-producing fallback.
        let unavailable = PartyStore(directory: directory.appending(path: "resolve-unavailable"))
        unavailable.switchOwner(owner)
        PartyAPIStub.statusCode = 405
        PartyAPIStub.payload = Data("{\"error\":{\"code\":\"not_found\",\"message\":\"Resource not found.\"}}".utf8)
        let requestsBefore = PartyAPIStub.requestCount
        let unavailableResult = await unavailable.submit(setup, deviceFlow: flow) { write in
            try await api.partyWrite(write, accessToken: "synthetic-api-token")
        }
        precondition(!unavailableResult && unavailable.party == nil && unavailable.pending == setup
                     && unavailable.canDiscardPending && unavailable.message == "Couldn't set up a linked party.")
        precondition(PartyAPIStub.requestCount == requestsBefore + 1
                     && PartyAPIStub.lastRequest?.url?.path == "/v1/parties/resolve")
        PartyAPIStub.statusCode = 200
        let closed = APIParty(partyID: partyID, name: "Friday", state: "CLOSED", role: "host",
                              memberCount: 1, deviceID: nil, joinCode: nil)
        let ended = await unavailable.submit(nil, deviceFlow: flow) { _ in
            .resolved(APIPartyResolution(action: .created, party: closed))
        }
        precondition(ended && unavailable.party == nil && unavailable.pending == nil
                     && unavailable.message?.contains("ended") == true, "Closed replay must not create a replacement")
        // Old persisted creates can only read back their UUID, never POST an unbound party.
        PartyAPIStub.payload = try JSONSerialization.data(withJSONObject: ["party_id": partyID, "name": "Friday",
            "state": "OPEN", "role": "host", "member_count": 1, "device_id": NSNull(), "join_code": "ABCDEFGH"])
        _ = try await api.partyWrite(create, accessToken: "synthetic-api-token")
        precondition(PartyAPIStub.lastRequest?.httpMethod == "GET"
                     && PartyAPIStub.lastRequest?.url?.path == "/v1/parties/\(partyID)")

        let bindingStore = PartyStore(directory: directory.appending(path: "binding"))
        bindingStore.switchOwner(owner)
        let unbound = APIParty(partyID: partyID, name: "Friday", state: "OPEN", role: "host",
                               memberCount: 1, deviceID: nil, joinCode: "ABCDEFGH")
        let saved = await bindingStore.submit(create, deviceFlow: flow) { _ in .party(unbound) }
        precondition(saved && bindingStore.party?.id == partyID)
        let denied = await bindingStore.update(expectedID: partyID) { throw KickBACAPI.APIError.server(status: 404, code: "not_found") }
        precondition(!denied && bindingStore.party?.id == partyID && bindingStore.party?.joinCode == "ABCDEFGH"
                     && bindingStore.pending == nil, "Failed device linking discarded the server-created party")
        precondition(PartyStore.deviceFailure(KickBACAPI.APIError.http(404), linking: true) == "This existing party still needs its breathalyzer linked.")
        precondition(PartyStore.deviceFailure(KickBACAPI.APIError.http(404), linking: false).contains("No open party"))
        let linkedParty = await bindingStore.update(expectedID: partyID) { party() }
        precondition(linkedParty && bindingStore.party?.deviceID == device)
        bindingStore.showEntry()
        precondition(bindingStore.party == nil && bindingStore.lastCheckIn == nil)
        let reopenedEntry = PartyStore(directory: directory.appending(path: "binding"))
        reopenedEntry.switchOwner(owner)
        var restoredParties = 0
        await reopenedEntry.restore { id in
            precondition(id == partyID)
            restoredParties += 1
            return party()
        }
        precondition(restoredParties == 1 && reopenedEntry.party?.id == partyID
                     && reopenedEntry.party?.isHost == true && reopenedEntry.party?.deviceID == device,
                     "Returning to Party lost the saved party, host role or breathalyzer binding")
        let lateRoom = await reopenedEntry.update {
            reopenedEntry.showEntry()
            return party()
        }
        precondition(!lateRoom && reopenedEntry.party == nil && !reopenedEntry.isBusy,
                     "A late server response reopened a room after returning to entry")
        let uncertainCreate = try PartyWrite.create(name: "Friday")
        _ = await reopenedEntry.submit(uncertainCreate, deviceFlow: flow) { _ in throw URLError(.timedOut) }
        reopenedEntry.showEntry()
        precondition(reopenedEntry.party == nil && reopenedEntry.pending == uncertainCreate)
        let retryFromEntry = PartyStore(directory: directory.appending(path: "binding"))
        retryFromEntry.switchOwner(owner)
        precondition(retryFromEntry.pending == uncertainCreate, "Returning to entry discarded an uncertain server write")
        await retryFromEntry.restore { id in
            precondition(id == partyID)
            return party()
        }
        precondition(retryFromEntry.party?.id == partyID && retryFromEntry.pending == uncertainCreate,
                     "Restoring the selected party discarded an uncertain write")
        let partyList = PartyStore(directory: directory.appending(path: "party-list"))
        partyList.switchOwner(owner)
        await partyList.loadParties { offset in
            precondition(offset == 0)
            return PartyPage(items: [party()], limit: 1, offset: 0, hasMore: true)
        }
        precondition(partyList.parties.map(\.id) == [partyID] && partyList.hasMoreParties)
        await partyList.loadParties(more: true) { offset in
            precondition(offset == 1)
            throw URLError(.notConnectedToInternet)
        }
        precondition(partyList.parties.count == 1 && partyList.partiesMessage != nil,
                     "Failed party-list page erased saved parties")
        await partyList.loadParties(more: true) { offset in
            PartyPage(items: [party()], limit: 1, offset: offset, hasMore: false)
        }
        precondition(partyList.parties.count == 1 && !partyList.hasMoreParties && partyList.partiesMessage == nil)
        await partyList.loadParties { _ in
            partyList.switchOwner("sms|another-party-owner")
            return PartyPage(items: [party()], limit: 50, offset: 0, hasMore: false)
        }
        precondition(partyList.parties.isEmpty && !partyList.isLoadingParties,
                     "A late party list crossed accounts")
        let removalDirectory = directory.appending(path: "removal")
        let removal = PartyStore(directory: removalDirectory)
        removal.switchOwner(owner)
        _ = await removal.update { party() }
        await removal.loadParties { _ in PartyPage(items: [party()], limit: 50, offset: 0, hasMore: false) }
        let busyRemoval = await removal.removeHostedParty(partyID) { _ in
            throw KickBACAPI.APIError.server(status: 409, code: "device_busy")
        }
        precondition(!busyRemoval && removal.party?.id == partyID && removal.parties.count == 1,
                     "Failed deletion removed a live party")
        let unconfirmedRemoval = await removal.removeHostedParty(partyID) { _ in party() }
        precondition(!unconfirmedRemoval && removal.party?.id == partyID,
                     "An OPEN response was treated as successful deletion")
        let removed = await removal.removeHostedParty(partyID) { id in
            precondition(id == partyID)
            return APIParty(partyID: id, name: "Friday", state: "CLOSED", role: "host",
                            memberCount: 1, deviceID: nil, joinCode: nil)
        }
        precondition(removed && removal.party == nil && removal.parties.isEmpty,
                     "Confirmed deletion did not clear the selected party")
        let afterRemoval = PartyStore(directory: removalDirectory)
        afterRemoval.switchOwner(owner)
        await afterRemoval.restore { _ in preconditionFailure("Deleted party reopened after relaunch") }
        _ = await removal.update {
            APIParty(partyID: partyID, name: "Friday", state: "OPEN", role: "member",
                     memberCount: 2, deviceID: device, joinCode: nil)
        }
        let memberRemoval = await removal.removeHostedParty(partyID) { _ in
            preconditionFailure("A member attempted host-only deletion")
        }
        precondition(!memberRemoval && removal.party?.role == "member")
        print("Party integration checks passed: durable exact retries, relaunch, account fencing, shared-session adoption, expiry/cancel/busy, manual null BAC, pagination recovery, live wire/auth and code validation")
    }
    static func checkGameInvitations() {
        let game = APIPartyGame(gameInstanceID: gameID, partyID: partyID, gameID: "trivia", state: "OPEN", deviceID: device)
        var host = PartyGameInvitations()
        var guest = PartyGameInvitations()
        precondition(host.next(in: [game], partyID: partyID, canPresent: false) == nil,
                     "An invitation must wait for the current sheet to close")
        precondition(host.next(in: [game], partyID: partyID, canPresent: true)?.id == gameID)
        precondition(guest.next(in: [game], partyID: partyID, canPresent: true)?.id == gameID,
                     "Every phone must receive its own invitation")
        precondition(host.next(in: [game], partyID: partyID, canPresent: true) == nil,
                     "Polling must not reopen a dismissed invitation")
        var otherParty = PartyGameInvitations()
        precondition(otherParty.next(in: [game], partyID: sessionID, canPresent: true) == nil)
        let closed = APIPartyGame(gameInstanceID: gameID, partyID: partyID, gameID: "trivia", state: "CLOSED", deviceID: device)
        precondition(otherParty.next(in: [closed], partyID: partyID, canPresent: true) == nil)
    }

    @MainActor static func checkSetupCancellation(in directory: URL, deviceFlow: DeviceSessionStore) async throws {
        let cache = directory.appending(path: "cancelled-setup")
        let store = PartyStore(directory: cache)
        store.switchOwner(owner)
        let setup = try PartyWrite.resolve(name: "Friday", deviceID: device)
        _ = await store.submit(setup, deviceFlow: deviceFlow) { _ in throw URLError(.timedOut) }
        precondition(store.cancelSetup(), "Close must cancel an unfinished setup")
        precondition(store.pending == nil && store.message == nil && !store.isBusy,
                     "Closing creation left the join actions locked")
        let relaunched = PartyStore(directory: cache)
        relaunched.switchOwner(owner)
        precondition(relaunched.pending == nil, "Cancelled creation returned after relaunch")
        let joined = await store.update { party() }
        precondition(joined, "Joining must work after closing creation")
        precondition(store.cancelSetup() && store.party?.id == partyID,
                     "Closing an empty draft must preserve a confirmed party")

        let failedCache = directory.appending(path: "cancel-save-failure")
        let unsaved = PartyStore(directory: failedCache)
        unsaved.switchOwner(owner)
        _ = await unsaved.submit(setup, deviceFlow: deviceFlow) { _ in throw URLError(.timedOut) }
        try FileManager.default.removeItem(at: failedCache)
        try Data("blocked storage".utf8).write(to: failedCache)
        precondition(!unsaved.cancelSetup() && unsaved.pending == setup,
                     "A failed disk write must not pretend cancellation was saved")

        let late = PartyStore(directory: directory.appending(path: "cancelled-in-flight"))
        late.switchOwner(owner)
        let otherParty = APIParty(partyID: gameID, name: "Joined party", state: "OPEN", role: "member",
                                  memberCount: 2, deviceID: device, joinCode: nil)
        let accepted = await late.submit(setup, deviceFlow: deviceFlow) { _ in
            precondition(late.cancelSetup() && !late.isBusy)
            let joined = await late.update { otherParty }
            precondition(joined)
            return .resolved(APIPartyResolution(action: .created, party: party()))
        }
        precondition(!accepted && late.party?.id == otherParty.id && late.pending == nil && !late.isBusy,
                     "A late create response replaced the party joined after cancellation")

        let checkIn = try PartyWrite.checkIn(partyID: partyID, deviceID: device, gameInstanceID: nil)
        _ = await store.submit(checkIn, deviceFlow: deviceFlow) { _ in throw URLError(.timedOut) }
        precondition(!store.cancelSetup() && store.pending == checkIn,
                     "Cancelling creation discarded an unrelated check-in request")
        print("Party Close checks passed: reset, join after cancellation, relaunch, late responses, saved parties and storage failures")
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
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var requestCount = 0
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
        Self.requestCount += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
