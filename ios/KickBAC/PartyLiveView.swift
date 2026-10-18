import SwiftUI
import VisionKit

struct PartyView: View {
    let profile: ProfileStore
    let owner: String?
    let session: AuthSession
    let deviceFlow: DeviceSessionStore
    let onSignIn: () -> Void
    @State private var store = PartyStore()
    @State private var history = CheckInHistoryStore()
    @State private var parties: [APIParty] = []
    @State private var partiesOffset = 0
    @State private var moreParties = false
    @State private var games: [APIPartyGame] = []
    @State private var device: APIDevice?
    @State private var destination: Destination?
    @State private var input = ""
    @State private var error: String?
    @State private var showsScanner = false
    @State private var showsStartTest = false
    @State private var showsClose = false
    @State private var trivia: TriviaPreview?
    @State private var gameContext: APIPartyGame?
    @State private var showsTrivia = false
    @State private var opensTrivia = false
    @Environment(\.scenePhase) private var scenePhase
    private enum Destination: String, Identifiable {
        case create, join, deviceJoin, bind, invite, history, reading, gameInvite, preview
        var id: Self { self }
    }
    private var locked: Bool { store.isBusy || store.pending != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !session.isSignedIn {
                        Text("Sign in to create or join a party.")
                        Button("Sign in", action: onSignIn).buttonStyle(.glassProminent)
                    } else {
                        if let pending = store.pending {
                            Text("Saved \(pending.kind == .checkIn ? "check-in" : pending.kind == .game ? "game session" : "party creation") request. Retry to recover the same request; a timeout may already have been accepted.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Retry saved request") { Task { await submit(nil); await loadContext() } }.disabled(store.isBusy)
                            if store.canDiscardPending {
                                Text("The server rejected this attempt. Discard it to change the request.").font(.footnote)
                                Button("Discard rejected request") { store.discardRejectedRequest() }.disabled(store.isBusy)
                            }
                        }
                        if let message = error ?? store.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        if let party = store.party {
                            room(party)
                        } else {
                            Text("Party").font(.system(.largeTitle, design: .rounded, weight: .medium))
                            Button("Create a party") { open(.create) }.buttonStyle(.glassProminent).disabled(locked)
                            Button("Join with code") { open(.join) }.buttonStyle(.glass).disabled(locked)
                            Button("Join by QR or device link") { open(.deviceJoin) }.disabled(locked)
                            Text("NFC isn't available in this build. Use a party code, QR code or printed device ID. Joining never starts a test.")
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(parties) { party in
                                Button {
                                    Task { _ = await store.update(expectedID: party.id) { try await session.party(party.id) }; await loadContext() }
                                } label: {
                                    HStack { Text(party.name); Spacer(); Text(party.state == "OPEN" ? "Open" : "Closed").foregroundStyle(.secondary) }
                                }.disabled(locked)
                            }
                            if moreParties { Button("Load more parties") { Task { await loadParties(more: true) } } }
                        }
                        Button("My check-ins") { open(.history) }
                    }
                    #if DEBUG
                    Button("Local party preview · unsaved") { open(.preview) }.font(.footnote)
                    #endif
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color("SplashBackground").ignoresSafeArea())
            .refreshable { await refresh() }
            .toolbar {
                if store.party != nil { ToolbarItem(placement: .topBarTrailing) { Button("Back") { store.switchOwner(nil); store.switchOwner(owner); Task { await loadParties() } } } }
            }
        }
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .sheet(item: $destination, onDismiss: {
            if opensTrivia { opensTrivia = false; showsTrivia = true }
        }) { target in sheet(target) }
        .fullScreenCover(isPresented: $showsTrivia) {
            if let trivia, let gameContext {
                TriviaView(game: trivia, session: session, isHost: true,
                           playerName: owner != nil && profile.owner == owner ? profile.profile.name : "You",
                           photoData: owner != nil && profile.owner == owner ? profile.profile.photoData : nil, onFinish: { },
                           deviceFlow: deviceFlow,
                           checkInSessionID: matchingCheckIn?.session.id,
                           checkInDeviceID: gameContext.deviceID,
                           checkInMessage: store.message,
                           onStartCheckIn: { await startCheckIn(game: gameContext) })
            }
        }
        .confirmationDialog("Start your test?", isPresented: $showsStartTest, titleVisibility: .visible) {
            Button("Start my test") { Task { if await startCheckIn(game: nil) { open(.reading) } } }
        } message: {
            Text("Reserve \(store.party?.deviceID ?? "the assigned device") for your account for up to 60 seconds. This is a party-only check-in. The operator starts acquisition separately over USB; breath is not validated.")
        }
        .confirmationDialog("Close this party?", isPresented: $showsClose, titleVisibility: .visible) {
            Button("Close party", role: .destructive) { Task { await changeParty(action: "close", clear: true) } }
        } message: { Text("This closes its open game session and releases its device. Existing private check-ins remain saved.") }
        .task(id: owner) {
            store.switchOwner(owner); history.switchOwner(owner)
            parties = []; games = []; device = nil; trivia = nil; gameContext = nil; showsTrivia = false; destination = nil
            guard owner != nil else { return }
            await store.restore { try await session.party($0) }
            await loadParties(); await loadContext()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, owner != nil { Task { await refresh() } }
        }
    }

    @ViewBuilder private func room(_ party: APIParty) -> some View {
        Text(party.name).font(.system(.largeTitle, design: .rounded, weight: .medium))
        Text("\(party.memberCount) members · \(party.state == "OPEN" ? "Open" : "Closed")").foregroundStyle(.secondary)
        Text("Member names and shared scores aren't available yet.").font(.footnote).foregroundStyle(.secondary)
        if let code = party.joinCode {
            Button { open(.invite) } label: { LabeledContent("Party code", value: code) }.buttonStyle(.glass)
        }
        if party.state == "OPEN" {
            if let id = party.deviceID {
                Text("Breathalyzer: \(id)").font(.subheadline)
                if let device { Text(device.online ? "Device online" : "Device offline · a test may time out").font(.footnote).foregroundStyle(.secondary) }
                Button("Start my test") { showsStartTest = true }.buttonStyle(.glassProminent).disabled(locked || deviceFlow.hasActiveSession)
            } else {
                Text("No breathalyzer linked. A host with operator approval must link one before check-in.").font(.footnote)
            }
            if deviceFlow.hasActiveSession {
                Button("View my current test") { open(.reading) }
            }
            if party.isHost {
                Button("Link breathalyzer") { open(.bind) }.disabled(locked)
                if party.deviceID != nil { Button("Unlink breathalyzer") { Task { await changeParty(action: "unbind") } }.disabled(locked) }
            }
            Text("Local games").font(.title2.bold())
            Text("Game sessions are saved on the server. Questions, turns, scores and standings are local to this iPhone and aren't saved or shared.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(games.filter { $0.state == "OPEN" }) { game in
                HStack(spacing: 12) {
                    PartyGameIcon(game: game.gameID == "pictionary" ? .pictionary : .trivia)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(game.gameID.capitalized).font(.headline)
                        if game.gameID == "trivia" {
                            Button(trivia != nil && gameContext?.id == game.id ? "Return to local Trivia" : "Play local Trivia") {
                                if trivia != nil && gameContext?.id == game.id {
                                    if trivia?.phase == .invitation { open(.gameInvite) }
                                    else { showsTrivia = true }
                                } else {
                                    gameContext = game; trivia = TriviaPreview(); open(.gameInvite)
                                }
                            }.disabled(locked)
                        } else { Text("Gameplay unavailable").font(.footnote) }
                        if party.isHost {
                            Button("Close game session") { Task {
                                do { _ = try await session.closePartyGame(game.id); await loadContext() }
                                catch { self.error = PartyStore.failure(error) }
                            } }.disabled(locked)
                        }
                    }
                }
            }
            if party.isHost && !games.contains(where: { $0.state == "OPEN" }) {
                Button("Create Trivia session") { Task {
                    do { await submit(try PartyWrite.game(partyID: party.id)); await loadContext() }
                    catch { self.error = PartyStore.failure(error) }
                } }.disabled(locked)
            }
            if party.isHost {
                Button("Close party", role: .destructive) { showsClose = true }.disabled(locked)
            } else {
                Button("Leave party", role: .destructive) { Task { await changeParty(action: "leave", clear: true) } }.disabled(locked)
            }
        }
        Button("Refresh party") { Task { await refresh() } }.disabled(store.isBusy)
    }

    @ViewBuilder private func sheet(_ target: Destination) -> some View {
        switch target {
        case .preview:
            #if DEBUG
            PartyPreviewView(profile: profile, owner: owner, session: session)
            #else
            Text("Local preview unavailable")
            #endif
        case .gameInvite:
            TriviaInvitationSheet {
                trivia?.join(); opensTrivia = true; destination = nil
            } onSkip: { trivia?.skip(); destination = nil }
        case .reading:
            NavigationStack {
                VStack {
                    HomeView(session: session, deviceFlow: deviceFlow, isGameCheckIn: true)
                    if deviceFlow.test?.status == .armed {
                        Button("Cancel test") { Task { await deviceFlow.cancel { try await session.cancelSession($0) } } }.frame(minHeight: 44)
                    }
                    if deviceFlow.message != nil { Button("Retry test status") { deviceFlow.retryPolling() }.frame(minHeight: 44) }
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
        case .history:
            NavigationStack {
                List {
                    Text("Private check-ins · only your own sessions and readings").font(.footnote)
                    ForEach(history.page?.items ?? []) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.session.createdAt).font(.caption).foregroundStyle(.secondary)
                            Text(item.gameInstanceID == nil ? "Party check-in" : "Game check-in").font(.headline)
                            Text(item.session.status.rawValue.capitalized)
                            if let reading = item.session.measurement {
                                Text(reading.sourceTitle)
                                if let notice = reading.acquisitionNotice { Text(notice) }
                                Text(reading.durationText)
                                Text(reading.bacReading.map { "BAC \($0.value.formatted(.number.precision(.fractionLength(3))))" } ?? "BAC unavailable")
                            }
                            if item.session.status.isActive {
                                Button("Resume my test") {
                                    do { try deviceFlow.adoptCheckIn(item.session, expectedOwner: owner ?? ""); destination = .reading }
                                    catch { self.error = PartyStore.failure(error) }
                                }
                            }
                        }.accessibilityElement(children: .contain)
                    }
                    if let message = history.message { Text(message); Button("Retry") { Task { await loadHistory() } } }
                    if history.page?.items.isEmpty == true { Text("No check-ins yet.") }
                    if history.page?.hasMore == true { Button("Load more") { Task { await loadHistory(more: true) } } }
                    if history.isLoading { ProgressView() }
                }.navigationTitle("My check-ins")
                    .refreshable { await loadHistory() }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }.task { await loadHistory() }
        default:
            NavigationStack {
                Form {
                    if target == .invite {
                        Text("Share this server-issued code to invite people.").font(.footnote)
                        Text(store.party?.joinCode ?? "Code unavailable").font(.largeTitle).monospaced().textSelection(.enabled)
                        Text("NFC isn't configured. Joining with this code doesn't start a test.").font(.footnote)
                    } else {
                        let label = target == .create ? "Party name" : target == .join ? "Party code" : "Device link or ID"
                        Text(label).font(.subheadline)
                        TextField(label, text: $input, prompt: Text(target == .create ? "Friday night" : target == .join ? "Eight-character code" : "Official link or printed ID"))
                            .textInputAutocapitalization(target == .create ? .sentences : target == .join ? .characters : .never)
                            .autocorrectionDisabled()
                        if target == .bind || target == .deviceJoin {
                            Text("NFC isn't available. Enter the printed ID or scan its QR code. Linking requires a backend operator grant; the app cannot grant permission.")
                                .font(.footnote)
                            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                                Button("Scan QR code") { showsScanner = true }
                            }
                        }
                        if let message = error ?? store.message { Text(message).font(.footnote) }
                        if store.pending != nil {
                            Button("Retry saved request") { Task {
                                await submit(nil)
                                if store.pending == nil { destination = nil; await loadContext() }
                            } }.disabled(store.isBusy)
                            if store.canDiscardPending {
                                Button("Discard rejected request") { store.discardRejectedRequest() }.disabled(store.isBusy)
                            }
                        }
                        Button(target == .create ? "Create party" : target == .bind ? "Confirm link" : "Join party") { Task { await submitForm(target) } }
                            .disabled(locked || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.navigationTitle(target == .create ? "Create a party" : target == .bind ? "Link breathalyzer" : target == .invite ? "Invite people" : "Join a party")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { destination = nil } } }
                    .sheet(isPresented: $showsScanner) {
                        NavigationStack {
                            DeviceQRScanner { input = $0; showsScanner = false }
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsScanner = false } } }
                        }
                    }
            }
        }
    }

    private var matchingCheckIn: APICheckIn? {
        guard let item = store.lastCheckIn, item.partyID == gameContext?.partyID,
              item.gameInstanceID == gameContext?.id else { return nil }
        return item
    }
    private func open(_ destination: Destination) { input = ""; error = nil; self.destination = destination }
    private func submit(_ request: PartyWrite?) async {
        _ = await store.submit(request, deviceFlow: deviceFlow) { try await session.partyWrite($0) }
    }
    private func startCheckIn(game: APIPartyGame?) async -> Bool {
        guard let party = store.party, let id = game?.deviceID ?? party.deviceID else { return false }
        do {
            let pending = store.pending
            if let pending {
                guard pending.kind == .checkIn, pending.partyID == party.id,
                      pending.gameInstanceID == game?.id else { return false }
            }
            return await store.submit(pending == nil ? try PartyWrite.checkIn(partyID: party.id, deviceID: id, gameInstanceID: game?.id) : nil,
                                      deviceFlow: deviceFlow) { try await session.partyWrite($0) }
        } catch { self.error = PartyStore.failure(error); return false }
    }
    private func submitForm(_ target: Destination) async {
        do {
            if target == .create {
                await submit(try PartyWrite.create(name: input))
                if store.pending == nil, store.party != nil { destination = nil }
            } else if target == .join {
                if await store.update(send: { try await session.joinParty(code: input) }) { destination = nil }
            } else {
                guard let base = session.apiBaseURL else { return }
                let id = try DeviceTarget.parse(input, baseURL: base)
                let resolved = try await session.resolveDevice(id)
                guard resolved.deviceID == id else { throw KickBACAPI.APIError.invalidResponse }
                if target == .bind {
                    guard let party = store.party else { return }
                    if await store.update(expectedID: party.id, send: { try await session.updateParty(party.id, action: "bind", deviceID: id) }) { destination = nil }
                } else if await store.update(send: { try await session.joinParty(deviceID: id) }) { destination = nil }
            }
            await loadContext()
        } catch { self.error = PartyStore.failure(error) }
    }
    private func changeParty(action: String, clear: Bool = false) async {
        guard let party = store.party else { return }
        _ = await store.update(expectedID: party.id, clear: clear) { try await session.updateParty(party.id, action: action) }
        await loadParties(); await loadContext()
    }
    private func refresh() async {
        if store.pending == nil { await store.restore { try await session.party($0) } }
        await loadParties(); await loadContext()
    }
    private func loadContext() async {
        guard let party = store.party else { games = []; device = nil; return }
        do {
            var loaded: [APIPartyGame] = []
            var offset = 0
            while true {
                let page = try await session.partyGames(party.id, offset: offset)
                guard page.offset == offset, (1...100).contains(page.limit),
                      page.items.allSatisfy({ $0.partyID == party.id && UUID(uuidString: $0.id) != nil }),
                      !page.hasMore || !page.items.isEmpty else { throw KickBACAPI.APIError.invalidResponse }
                loaded += page.items
                if !page.hasMore { break }
                offset += page.limit
            }
            guard store.party?.id == party.id else { return }
            games = loaded
            if let id = party.deviceID {
                let device = try await session.device(id)
                guard store.party?.id == party.id, device.id == id else { return }
                self.device = device
            } else { device = nil }
        } catch { self.error = PartyStore.failure(error) }
    }
    private func loadParties(more: Bool = false) async {
        guard owner != nil else { return }
        do {
            let offset = more ? partiesOffset : 0
            let page = try await session.parties(offset: offset)
            guard page.offset == offset, (1...100).contains(page.limit), !page.hasMore || !page.items.isEmpty else { throw KickBACAPI.APIError.invalidResponse }
            var seen = Set<String>()
            parties = ((more ? parties : []) + page.items).filter { seen.insert($0.id).inserted }
            partiesOffset = page.offset + page.limit; moreParties = page.hasMore
        } catch { self.error = PartyStore.failure(error) }
    }
    private func loadHistory(more: Bool = false) async { await history.load(more: more) { try await session.checkIns(offset: $0) } }
}
