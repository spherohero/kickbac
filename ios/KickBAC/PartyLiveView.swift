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
    @FocusState private var entryFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private enum Destination: String, Identifiable {
        case create, join, deviceJoin, bind, invite, history, reading, gameInvite, games, preview
        var id: Self { self }
    }
    private var locked: Bool { store.isBusy || store.pending != nil }

    var body: some View {
        page
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
            Text("Reserve the breathalyzer for your test for up to 60 seconds. The operator starts the reading separately.")
        }
        .confirmationDialog("End this party?", isPresented: $showsClose, titleVisibility: .visible) {
            Button("End party", role: .destructive) { Task { await changeParty(action: "close", clear: true) } }
        } message: { Text("This ends the party and any game in progress.") }
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

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 16) {
                    Text(store.party?.name ?? "Party")
                        .font(.system(.largeTitle, design: .rounded, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    options
                }
                if let message = error ?? store.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if store.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else if store.pending != nil {
                    VStack(spacing: 12) {
                        Button("Try again") { Task { await submit(nil); await loadContext() } }
                            .partySecondaryAction()
                        if store.canDiscardPending {
                            Button("Change request") { store.discardRejectedRequest() }.frame(minHeight: 44)
                        }
                    }
                }
                if session.isSignedIn {
                    if let party = store.party { room(party) }
                    else { entry }
                    Button { open(.history) } label: {
                        HStack(spacing: 14) {
                            Image("ReadingClock").resizable().scaledToFit().frame(width: 22, height: 22)
                            Text("My check-ins").font(.system(.headline, design: .rounded))
                            Spacer(minLength: 8)
                            Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
                        }.frame(maxWidth: .infinity, minHeight: 56).contentShape(.rect)
                    }.buttonStyle(ProfilePressStyle())
                } else {
                    Text("Sign in to create or join a party.").foregroundStyle(.secondary)
                    Button("Sign in", action: onSignIn).partyPrimaryAction()
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color("SplashBackground").ignoresSafeArea())
        .refreshable { await refresh() }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 32) {
            Button { open(.deviceJoin) } label: {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Image("PartyNFC").resizable().scaledToFit().frame(width: 36, height: 36)
                        Spacer(minLength: 8)
                        Image("ProfileChevron").resizable().scaledToFit().frame(width: 22, height: 22)
                    }.accessibilityHidden(true)
                    Text("Join a party").font(.system(.title, design: .rounded, weight: .medium))
                }
                .padding(24).frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
                .foregroundStyle(.black)
                .background(Color(red: 0.68, green: 0.84, blue: 0.80), in: .rect(cornerRadius: 28))
                .contentShape(.rect(cornerRadius: 28))
            }
            .buttonStyle(ProfilePressStyle()).disabled(locked)
            .accessibilityHint("Join using a breathalyzer QR code or device link.")
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    Button("Join with code") { open(.join) }.partySecondaryAction().disabled(locked)
                    Button("Create a party") { open(.create) }.partyPrimaryAction().disabled(locked)
                }
            }
            if !parties.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your parties").font(.system(.title2, design: .rounded, weight: .medium))
                    ForEach(parties) { party in
                        Button {
                            Task { _ = await store.update(expectedID: party.id) { try await session.party(party.id) }; await loadContext() }
                        } label: {
                            HStack(spacing: 12) {
                                Text(party.name).font(.headline)
                                Spacer(minLength: 8)
                                if party.state != "OPEN" { Text("Ended").font(.subheadline).foregroundStyle(.secondary) }
                                Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
                            }.frame(maxWidth: .infinity, minHeight: 52).contentShape(.rect)
                        }.buttonStyle(ProfilePressStyle()).disabled(locked)
                    }
                    if moreParties { Button("Load more parties") { Task { await loadParties(more: true) } }.frame(minHeight: 44) }
                }
            }
        }
    }

    private var options: some View {
        Menu {
            Button("Refresh") { Task { await refresh() } }.disabled(store.isBusy)
            if let party = store.party {
                Button("All parties") { store.switchOwner(nil); store.switchOwner(owner); Task { await loadParties() } }.disabled(store.isBusy)
                if party.state == "OPEN" {
                    if party.isHost {
                        Button("Link breathalyzer") { open(.bind) }.disabled(locked)
                        if party.deviceID != nil {
                            Button("Unlink breathalyzer") { Task { await changeParty(action: "unbind") } }.disabled(locked)
                        }
                        ForEach(games.filter { $0.state == "OPEN" }) { game in
                            Button("End \(game.gameID.capitalized)", role: .destructive) { Task { await endGame(game) } }.disabled(locked)
                        }
                        Button("End party", role: .destructive) { showsClose = true }.disabled(locked)
                    } else {
                        Button("Leave party", role: .destructive) { Task { await changeParty(action: "leave", clear: true) } }.disabled(locked)
                    }
                }
            }
            #if DEBUG
            Button("Party layout") { open(.preview) }
            #endif
        } label: {
            Image("ProfileSettings").resizable().scaledToFit().frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large).fixedSize()
        .accessibilityLabel("Party options")
    }

    @ViewBuilder private func room(_ party: APIParty) -> some View {
        if let code = party.joinCode {
            Button { open(.invite) } label: {
                HStack(spacing: 12) {
                    Text("Party code").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(code).fontWeight(.medium).monospaced()
                    Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
                }.frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 18)).controlSize(.large)
        }
        if party.state == "OPEN" {
            if !games.filter({ $0.state == "OPEN" }).isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ongoing games").font(.system(.title2, design: .rounded, weight: .medium))
                    ForEach(games.filter { $0.state == "OPEN" }) { game in ongoingGame(game) }
                }
            }
            if party.isHost {
                if party.deviceID == nil {
                    Button("Link breathalyzer") { open(.bind) }.partyPrimaryAction().disabled(locked)
                } else if !games.contains(where: { $0.state == "OPEN" }) {
                    Button("Start a game") { open(.games) }.partyPrimaryAction().disabled(locked)
                }
            }
            if party.deviceID != nil {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("Breathalyzer").font(.headline)
                        Spacer(minLength: 8)
                        if let device { Text(device.online ? "Online" : "Offline").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if deviceFlow.hasActiveSession {
                        Button("View my test") { open(.reading) }.partySecondaryAction()
                    } else {
                        Button("Start my test") { showsStartTest = true }.partySecondaryAction().disabled(locked)
                    }
                }
            } else if !party.isHost {
                Text("Waiting for a breathalyzer").foregroundStyle(.secondary)
            }
        } else {
            Text("Party ended").foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("People").font(.system(.title2, design: .rounded, weight: .medium))
                Spacer(minLength: 8)
                Text("\(party.memberCount)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ProfileAvatar(photoData: owner != nil && profile.owner == owner ? profile.profile.photoData : nil, side: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(playerName).font(.headline)
                    Text(party.isHost ? "Host" : "Member").font(.subheadline).foregroundStyle(.secondary)
                }
            }.accessibilityElement(children: .combine)
        }
    }

    private var playerName: String {
        owner != nil && profile.owner == owner && !profile.profile.name.isEmpty ? profile.profile.name : "Player"
    }

    private func ongoingGame(_ game: APIPartyGame) -> some View {
        Button {
            if trivia != nil && gameContext?.id == game.id {
                if trivia?.phase == .invitation { open(.gameInvite) }
                else { showsTrivia = true }
            } else {
                gameContext = game; trivia = TriviaPreview(); open(.gameInvite)
            }
        } label: {
            HStack(spacing: 16) {
                PartyGameIcon(game: game.gameID == "pictionary" ? .pictionary : .trivia)
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.gameID.capitalized).font(.system(.title3, design: .rounded, weight: .medium))
                    Text(game.gameID != "trivia" ? "Coming soon" : trivia != nil && gameContext?.id == game.id ? "Return to game" : "Join game")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
            }
            .padding(20).frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(ProfilePressStyle()).disabled(locked || game.gameID != "trivia")
    }

    private func endGame(_ game: APIPartyGame) async {
        do { _ = try await session.closePartyGame(game.id); await loadContext() }
        catch { self.error = PartyStore.failure(error) }
    }

    @ViewBuilder private func sheet(_ target: Destination) -> some View {
        switch target {
        case .preview:
            #if DEBUG
            PartyPreviewView(profile: profile, owner: owner, session: session)
            #else
            EmptyView()
            #endif
        case .games:
            PartyGamePicker(onStart: { game in
                guard game == .trivia, let party = store.party else { return }
                Task {
                    do { await submit(try PartyWrite.game(partyID: party.id)); await loadContext() }
                    catch { self.error = PartyStore.failure(error) }
                }
            }, availableGames: [.trivia])
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
        default: entrySheet(target)
        }
    }

    private func entrySheet(_ target: Destination) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if target == .invite {
                        VStack(spacing: 20) {
                            Text("Party code").font(.subheadline).foregroundStyle(.secondary)
                            Text(store.party?.joinCode ?? "—")
                                .font(.system(.largeTitle, design: .rounded, weight: .medium)).monospaced()
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                        }.frame(maxWidth: .infinity)
                        if let code = store.party?.joinCode {
                            ShareLink(item: code) { Text("Share code") }.partyPrimaryAction()
                        }
                    } else {
                        let label = target == .create ? "Party name" : target == .join ? "Party code" : "Device link or ID"
                        VStack(alignment: .leading, spacing: 10) {
                            Text(label).font(.system(.subheadline, design: .rounded, weight: .medium))
                            TextField(label, text: $input, prompt: Text(target == .create ? "Friday night" : target == .join ? "Eight-character code" : "Link or printed ID"))
                                .focused($entryFocused)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(target == .create ? .sentences : target == .join ? .characters : .never)
                                .autocorrectionDisabled()
                                .padding(18).background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
                        }
                        if target == .bind || target == .deviceJoin {
                            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                                Button("Scan QR code") { entryFocused = false; showsScanner = true }.partySecondaryAction()
                            }
                        }
                        if let message = error ?? store.message { Text(message).foregroundStyle(.secondary).font(.footnote) }
                        if store.pending != nil {
                            Button("Try again") { Task {
                                await submit(nil)
                                if store.pending == nil { destination = nil; await loadContext() }
                            } }.partySecondaryAction().disabled(store.isBusy)
                            if store.canDiscardPending {
                                Button("Change request") { store.discardRejectedRequest() }.frame(minHeight: 44)
                            }
                        }
                        Button(target == .create ? "Create party" : target == .bind ? "Link breathalyzer" : "Join party") {
                            entryFocused = false
                            Task { await submitForm(target) }
                        }.partyPrimaryAction().disabled(locked || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle(target == .create ? "Create a party" : target == .bind ? "Link breathalyzer" : target == .invite ? "Invite people" : "Join a party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { destination = nil } } }
            .sheet(isPresented: $showsScanner) {
                NavigationStack {
                    DeviceQRScanner { input = $0; showsScanner = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsScanner = false } } }
                }
            }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
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
