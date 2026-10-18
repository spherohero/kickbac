import SwiftUI

struct PartyView: View {
    let profile: ProfileStore
    let owner: String?
    let session: AuthSession
    let deviceFlow: DeviceSessionStore
    let onSignIn: () -> Void
    @Binding var deviceLink: PartyDeviceLink?
    var isSelected = true
    @State private var isRestoring = true
    @State private var hasLoadedOwner = false
    @State private var store = PartyStore()
    @State private var games: [APIPartyGame] = []
    @State private var destination: Destination?
    @State private var sheetIsVisible = false
    @State private var gameInvitations = PartyGameInvitations()
    @State private var contextRevision = UUID()
    @State private var nfcReadingID: UUID?
    @State private var input = ""
    @State private var error: String?
    @State private var createdPartyID: String?
    @State private var scannedDevice: APIDevice?
    @State private var isCheckingDevice = false
    @State private var scanRevision = UUID()
    @State private var showsDeleteParty = false
    @State private var showsResolveConflict = false
    @State private var partyToDelete: APIParty?
    @State private var trivia: TriviaPreview?
    @State private var nearbyTrivia: NearbyTrivia?
    @State private var nearbyParty: NearbyTrivia?
    @State private var nearbyPartyModel: TriviaPreview?
    @State private var gameContext: APIPartyGame?
    @State private var showsTrivia = false
    @State private var opensTrivia = false
    @State private var creationTask: Task<Void, Never>?
    @FocusState private var entryFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private enum Destination: String, Identifiable {
        case create, join, deviceJoin, invite, gameInvite, games
        var id: Self { self }
    }
    private var locked: Bool { store.isBusy || store.pending != nil }
    private var hasPendingSetup: Bool {
        store.pending?.kind == .resolve || store.pending?.kind == .create
    }

    var body: some View {
        page
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .sheet(item: sheetDestination, onDismiss: {
            sheetIsVisible = false
            if opensTrivia { opensTrivia = false; showsTrivia = true }
            else { offerGameInvitation() }
        }) { target in sheet(target).onAppear { sheetIsVisible = true } }
        .fullScreenCover(isPresented: $showsTrivia) {
            if let trivia, let gameContext {
                TriviaView(game: trivia, session: session, isHost: store.party?.isHost == true,
                           playerName: owner != nil && profile.owner == owner ? profile.profile.name : "You",
                           photoData: owner != nil && profile.owner == owner ? profile.profile.photoData : nil, onFinish: { },
                           deviceFlow: deviceFlow,
                           checkInDeviceID: gameContext.deviceID,
                           checkInMessage: error,
                           nfcReadingID: nfcReadingID, onNFCReadingConsumed: { nfcReadingID = nil })
            }
        }
        .onChange(of: showsTrivia) {
            if !showsTrivia {
                error = nil
                offerGameInvitation()
            }
        }
        .onChange(of: store.party?.id) {
            nearbyParty?.stop(); nearbyParty = nil; nearbyPartyModel = nil
            guard let party = store.party, party.state == "OPEN" else { return }
            let model = TriviaPreview()
            model.sharedPartyCode = party.joinCode
            nearbyPartyModel = model
            nearbyParty = NearbyTrivia(game: model, partyID: party.id, gameID: "party",
                                       name: playerName, isHost: party.isHost)
        }
        .task(id: gamePollingID) {
            guard gamePollingID != nil else { return }
            while !Task.isCancelled {
                if !store.isBusy {
                    if destination == nil, store.pending == nil {
                        await store.restoreCurrent(quiet: true) { try await session.currentParty() }
                    }
                    await loadContext(reportErrors: false)
                }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
        .confirmationDialog("Leave your previous parties?", isPresented: $showsResolveConflict, titleVisibility: .visible) {
            Button("Leave previous parties", role: .destructive) {
                Task {
                    if await store.endConflictingParties(send: { row in
                        try await session.updateParty(row.id, action: row.isHost ? "close" : "leave")
                    }) { error = nil; destination = nil; await refresh() }
                    else { error = store.message }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Parties you host will end for everyone. Your saved readings and game history are kept. Then tap the tag again to join a new party.")
        }
        .confirmationDialog("Delete \(partyToDelete?.name ?? "party")?", isPresented: $showsDeleteParty, titleVisibility: .visible) {
            if let partyToDelete {
                Button("Delete party", role: .destructive) { Task { await deleteParty(partyToDelete) } }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This ends the party for everyone and removes it from your Party page. Saved readings and game history are kept.")
        }
        .task(id: owner) {
            guard !hasLoadedOwner || store.owner != owner else { return }
            hasLoadedOwner = true
            isRestoring = true
            store.switchOwner(owner)
            resetPresentation()
            guard owner != nil else { isRestoring = false; return }
            await refresh()
            isRestoring = false
            receiveDeviceLink()
        }
        .onChange(of: isSelected) {
            if isSelected {
                Task { await refresh(); receiveDeviceLink() }
            }
        }
        .onChange(of: deviceLink) { receiveDeviceLink() }
        .onChange(of: store.isBusy) {
            if !store.isBusy { receiveDeviceLink() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, owner != nil {
                receiveDeviceLink()
                Task { await refresh() }
            }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if isRestoring {
                    ProgressView("Loading party").frame(maxWidth: .infinity)
                }
                if store.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if !store.conflictingParties.isEmpty, destination == nil {
                    conflictRecovery
                }
                if session.isSignedIn {
                    if let party = store.party { room(party) }
                    else if !isRestoring { entry }
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

    private var conflictRecovery: some View {
        VStack(spacing: 12) {
            Text("Leave your previous parties before joining this one.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Leave previous parties") { showsResolveConflict = true }
                .partySecondaryAction().disabled(store.isBusy || store.conflictsHaveMore)
        }.frame(maxWidth: .infinity)
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
            .accessibilityHint("Tap your phone to the breathalyzer's NFC tag to join.")
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    Button("Join with code") { open(.join) }.partySecondaryAction().disabled(locked)
                    Button("Create a party") { open(.create) }.partyPrimaryAction()
                        .disabled(store.isBusy || (store.pending != nil && !hasPendingSetup))
                }
            }
        }
    }

    @ViewBuilder private func room(_ party: APIParty) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(party.name).font(.system(.largeTitle, design: .rounded, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if party.isHost {
                Menu {
                    Button("Delete party", role: .destructive) {
                        partyToDelete = party
                        showsDeleteParty = true
                    }
                } label: {
                    Image("ProfileSettings").resizable().scaledToFit().frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large).fixedSize()
                .accessibilityLabel("Party settings")
                .disabled(locked)
            }
        }
        if let code = party.joinCode ?? nearbyPartyModel?.sharedPartyCode ?? trivia?.sharedPartyCode, party.deviceID != nil {
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
                    Button("Link breathalyzer") { openSetup(party) }.partyPrimaryAction().disabled(locked)
                    Text("Link a breathalyzer to start a game.").font(.footnote).foregroundStyle(.secondary)
                }
                if !games.contains(where: { $0.state == "OPEN" }) {
                    Button("Start a game") { open(.games) }.partyPrimaryAction()
                        .disabled(locked || party.deviceID == nil)
                }
                if store.pending?.kind == .game, store.pending?.partyID == party.id {
                    Button("Try again") { Task {
                        await submit(nil)
                        await loadContext()
                    } }.partySecondaryAction().disabled(store.isBusy)
                }
            }
            if party.deviceID == nil, !party.isHost {
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
            if let model = nearbyPartyModel {
                ForEach(model.nearbyPlayers.filter { $0.id != model.localPlayerID }, id: \.id) { player in
                    HStack(spacing: 16) {
                        ProfileAvatar(photoData: nil, side: 56)
                        Text(player.name).font(.headline)
                    }.accessibilityElement(children: .combine)
                }
            }
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
                gameContext = game; configureTrivia(game); open(.gameInvite)
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

    @ViewBuilder private func sheet(_ target: Destination) -> some View {
        switch target {
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
                trivia?.join(); trivia?.previewTap()
                error = nil; store.clearMessage()
                opensTrivia = true; destination = nil
            } onSkip: { trivia?.skip(); destination = nil }
        default: entrySheet(target)
        }
    }

    private func entrySheet(_ target: Destination) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if target == .invite {
                        PartyTapIllustration(device: scannedDevice, isChecking: isCheckingDevice)
                        Text("Or enter code to join")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Text(store.party?.joinCode ?? "—")
                            .font(.system(.largeTitle, design: .rounded, weight: .medium)).monospaced()
                            .textSelection(.enabled).padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    } else {
                        if target == .create || target == .join {
                            let label = target == .create ? "Party name" : "Party code"
                            VStack(alignment: .leading, spacing: 10) {
                                Text(label).font(.system(.subheadline, design: .rounded, weight: .medium))
                                TextField(label, text: $input, prompt: Text(target == .create ? "Friday night" : "Eight-character code"))
                                    .disabled(store.pending != nil || (target == .create && createdPartyID != nil))
                                    .focused($entryFocused)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(target == .create ? .sentences : .characters)
                                    .autocorrectionDisabled()
                                    .padding(18).background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
                            }
                        }
                        if target != .join {
                            if target == .deviceJoin {
                                PartyTapIllustration()
                                if store.isBusy {
                                    ProgressView("Joining party…").frame(maxWidth: .infinity)
                                }
                            } else {
                                PartyTapIllustration(device: scannedDevice, isChecking: isCheckingDevice)
                            }
                        }
                        if target != .deviceJoin, let message = error ?? store.message {
                            Text(message).foregroundStyle(.secondary).font(.footnote)
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        if !store.conflictingParties.isEmpty { conflictRecovery }
                        if store.pending != nil {
                            Button("Try again") {
                                let task = Task { await retryEntry() }
                                if target == .create { creationTask = task }
                            }.partySecondaryAction().disabled(store.isBusy)
                        }
                        if target != .deviceJoin {
                            Button(target == .create ? (createdPartyID == nil ? "Create party" : "Retry linking") : "Join with code") {
                                entryFocused = false
                                let task = Task { await submitForm(target) }
                                if target == .create { creationTask = task }
                            }.partyPrimaryAction().disabled(locked || isCheckingDevice
                                || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || (target == .create && scannedDevice == nil))
                        }
                        if target == .deviceJoin {
                            VStack(spacing: 12) {
                                Button("Join with code") { open(.join) }.partySecondaryAction().disabled(locked)
                                if let message = error {
                                    Text(message).foregroundStyle(.secondary).font(.footnote)
                                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                }
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle(target == .create ? "Create a party" : target == .invite ? "Invite people" : "Join a party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: closeEntrySheet) } }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
    }


    private var sheetDestination: Binding<Destination?> {
        Binding(get: { destination }, set: { next in
            if next == nil { closeEntrySheet() }
            else { destination = next }
        })
    }

    private func closeEntrySheet() {
        guard let destination else { return }
        if destination == .create {
            guard store.cancelSetup() else { error = store.message; return }
            creationTask?.cancel(); creationTask = nil
            deviceLink = nil
        }
        entryFocused = false
        createdPartyID = nil; input = ""; scannedDevice = nil; error = nil
        scanRevision = UUID(); isCheckingDevice = false
        self.destination = nil
    }
    private func resetPresentation() {
        creationTask?.cancel(); creationTask = nil
        nearbyTrivia?.stop(); nearbyTrivia = nil
        gameInvitations = PartyGameInvitations()
        contextRevision = UUID()
        nfcReadingID = nil
        showsDeleteParty = false; partyToDelete = nil
        createdPartyID = nil
        error = nil; input = ""; scannedDevice = nil
        scanRevision = UUID(); isCheckingDevice = false
        games = []; trivia = nil; gameContext = nil
        showsTrivia = false; opensTrivia = false; destination = nil
    }

    private func open(_ destination: Destination) {
        if store.pending == nil { store.clearMessage() }
        createdPartyID = nil
        input = destination == .create && hasPendingSetup ? store.pending?.name ?? "" : ""
        error = nil; scannedDevice = nil
        scanRevision = UUID(); isCheckingDevice = false; self.destination = destination
    }
    private func receiveDeviceLink() {
        guard let link = deviceLink, owner != nil, !isRestoring, scenePhase == .active else { return }
        if showsTrivia, let trivia, trivia.phase == .breath, gameContext != nil {
            deviceLink = nil
            error = nil
            nfcReadingID = UUID()
            return
        }
        guard !store.isBusy else { return }
        guard !locked, !showsTrivia,
              destination == nil || destination == .create || destination == .deviceJoin || destination == .invite else {
            deviceLink = nil
            return
        }
        if destination == .create {
            inspectScan(link.deviceID)
            deviceLink = nil
            return
        }
        if destination == .invite, !link.linkAsHost {
            inspectScan(link.deviceID)
            deviceLink = nil
            return
        }
        if link.linkAsHost {
            guard let party = store.party, party.isHost, party.state == "OPEN" else {
                error = "Create or open a party you host to finish its setup."
                deviceLink = nil
                return
            }
            openSetup(party)
            inspectScan(link.deviceID)
            deviceLink = nil
            return
        }
        if destination != .deviceJoin { open(.deviceJoin) }
        input = link.deviceID
        Task { await joinScannedParty(link.deviceID) }
        deviceLink = nil
    }
    private func openSetup(_ party: APIParty) {
        open(.create)
        input = party.name
        createdPartyID = party.id
    }
    private func joinScannedParty(_ id: String) async {
        guard !locked, destination == .deviceJoin else { return }
        do {
            await submit(try PartyWrite.resolve(name: "Party", deviceID: id))
            error = store.message
            if store.pending == nil { await loadContext() }
        } catch { self.error = PartyStore.failure(error) }
    }
    private func inspectScan(_ id: String) {
        let revision = UUID()
        let requestOwner = owner
        scannedDevice = nil; scanRevision = revision
        isCheckingDevice = true; error = nil
        Task {
            defer { if scanRevision == revision { isCheckingDevice = false } }
            do {
                let resolved = try await session.resolveDevice(id)
                guard resolved.deviceID == id else { throw KickBACAPI.APIError.invalidResponse }
                let loaded = try await session.device(id)
                guard loaded.id == id else { throw KickBACAPI.APIError.invalidResponse }
                guard scanRevision == revision, owner == requestOwner, session.profileOwner == requestOwner else { return }
                scannedDevice = loaded
            } catch {
                if scanRevision == revision, owner == requestOwner { self.error = PartyStore.failure(error) }
            }
        }
    }
    private func submit(_ request: PartyWrite?) async {
        guard !Task.isCancelled else { return }
        let revision = scanRevision
        let kind = store.pending?.kind ?? request?.kind
        let accepted = await store.submit(request, deviceFlow: deviceFlow) { try await session.partyWrite($0) }
        guard scanRevision == revision else { return }
        if accepted, kind == .resolve, store.party?.deviceID != nil {
            destination = nil
        }
    }
    private func retryEntry() async {
        guard !Task.isCancelled else { return }
        let revision = scanRevision
        let wasCreation = store.pending?.kind == .create
        await submit(nil)
        guard scanRevision == revision, !Task.isCancelled else { return }
        if store.pending == nil {
            if wasCreation { await finishCreation() }
            else { destination = nil }
            await loadContext()
        }
    }
    private func submitForm(_ target: Destination) async {
        guard !Task.isCancelled else { return }
        let revision = scanRevision
        error = nil
        do {
            if target == .create {
                guard let scannedDevice else { return }
                if let createdPartyID, createdPartyID == store.party?.id {
                    // Repair an existing legacy party without creating another one.
                    await finishCreation()
                } else {
                    await submit(try PartyWrite.resolve(name: input, deviceID: scannedDevice.id))
                }
            } else if target == .join {
                if await store.update(send: { try await session.joinParty(code: input) }) { destination = nil }
            }
            guard scanRevision == revision, !Task.isCancelled else { return }
            await loadContext()
        } catch {
            if scanRevision == revision { self.error = PartyStore.failure(error) }
        }
    }
    private func finishCreation() async {
        guard let party = store.party, party.isHost else { return }
        createdPartyID = party.id
        input = party.name
        if let scannedDevice {
            await bindDevice(scannedDevice.id)
        } else {
            destination = .create
            error = "Tap the breathalyzer to link this existing party."
        }
    }
    private func bindDevice(_ id: String) async {
        guard let party = store.party else { return }
        let revision = scanRevision
        error = nil
        if await store.update(expectedID: party.id, send: {
            do {
                let linked = try await session.updateParty(party.id, action: "bind", deviceID: id)
                guard linked.state == "OPEN", linked.isHost, linked.deviceID == id else {
                    throw KickBACAPI.APIError.invalidResponse
                }
                return linked
            }
            catch {
                if scanRevision == revision { self.error = PartyStore.deviceFailure(error, linking: true) }
                throw error
            }
        }), scanRevision == revision { destination = nil }
    }
    private func deleteParty(_ party: APIParty) async {
        error = nil
        if await store.removeHostedParty(party.id, send: { try await session.updateParty($0, action: "close") }) {
            resetPresentation()
        }
    }
    private func refresh() async {
        guard destination == nil, !showsTrivia else { return }
        if store.pending == nil { await store.restoreCurrent { try await session.currentParty() } }
        await loadContext(reportErrors: false)
    }
    private var gamePollingID: String? {
        guard isSelected, !isRestoring, scenePhase == .active, let owner,
              let party = store.party, party.state == "OPEN" else { return nil }
        return "\(owner)|\(party.id)"
    }

    private func configureTrivia(_ game: APIPartyGame) {
        guard let party = store.party else { return }
        nearbyTrivia?.stop()
        let model = TriviaPreview()
        model.sharedPartyCode = party.joinCode
        trivia = model
        nearbyTrivia = NearbyTrivia(game: model, partyID: party.id, gameID: game.id,
                                    name: playerName, isHost: party.isHost)
    }

    private func offerGameInvitation() {
        guard let party = store.party,
              let game = gameInvitations.next(in: games, partyID: party.id,
                  canPresent: isSelected && scenePhase == .active && !isRestoring && !store.isBusy
                      && destination == nil && !sheetIsVisible && !showsTrivia && !opensTrivia) else { return }
        gameContext = game
        configureTrivia(game)
        open(.gameInvite)
    }

    private func loadContext(reportErrors: Bool = true) async {
        guard let party = store.party else { games = []; return }
        let revision = UUID()
        let requestOwner = owner
        contextRevision = revision
        do {
            var loaded: [APIPartyGame] = []
            var offset = 0
            while true {
                let page = try await session.partyGames(party.id, offset: offset)
                try Task.checkCancellation()
                guard page.offset == offset, (1...100).contains(page.limit),
                      page.items.allSatisfy({ $0.partyID == party.id && UUID(uuidString: $0.id) != nil }),
                      !page.hasMore || !page.items.isEmpty else { throw KickBACAPI.APIError.invalidResponse }
                loaded += page.items
                if !page.hasMore { break }
                offset += page.limit
            }
            guard contextRevision == revision, owner == requestOwner, session.profileOwner == requestOwner,
                  store.party?.id == party.id else { return }
            games = loaded
            offerGameInvitation()
        } catch {
            if reportErrors && !Task.isCancelled && contextRevision == revision && owner == requestOwner {
                self.error = PartyStore.failure(error)
            }
        }
    }
}
