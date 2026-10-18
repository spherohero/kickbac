import SwiftUI

struct PartyView: View {
    let profile: ProfileStore
    let owner: String?
    let session: AuthSession
    @State private var preview = PartyPreview()
    @State private var sheet: Destination?
    @State private var showsTrivia = false
    @State private var opensTriviaAfterSheet = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Destination: String, Identifiable {
        case create, join, code, games, invite, triviaInvite
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let room = preview.room {
                    roomHeader(room)
                    if let game = preview.ongoingGame {
                        ongoingGame(game)
                    }
                    if room.role == .host {
                        Button { sheet = .games } label: {
                            Label {
                                Text("Start a game")
                            } icon: {
                                Image("PartyPlus").resizable().scaledToFit().frame(width: 20, height: 20)
                            }
                                .frame(maxWidth: .infinity)
                        }
                        .partyPrimaryAction()
                        .disabled(preview.ongoingGame != nil)
                        .accessibilityIdentifier("partyChooseGame")
                    }
                    leaderboard
                    people(role: room.role)
                } else {
                    introduction
                }
            }
            .frame(maxWidth: 480).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .font(.system(.body, design: .rounded))
        .scrollIndicators(.hidden)
        .background(Color("SplashBackground").ignoresSafeArea())
        .sheet(item: $sheet, onDismiss: {
            if opensTriviaAfterSheet {
                opensTriviaAfterSheet = false
                if preview.trivia?.phase == .invitation { sheet = .triviaInvite }
                else { showsTrivia = preview.trivia != nil }
            }
        }) { destination in
            switch destination {
            case .create: PartyEntrySheet(preview: preview, mode: .create)
            case .join: PartyEntrySheet(preview: preview, mode: .tap)
            case .code: PartyEntrySheet(preview: preview, mode: .code)
            case .games: PartyGamePicker(preview: preview)
            case .invite: PartyInviteSheet()
            case .triviaInvite:
                if let trivia = preview.trivia {
                    TriviaInvitationSheet {
                        if trivia.join() {
                            opensTriviaAfterSheet = true
                            sheet = nil
                        }
                    } onSkip: {
                        trivia.skip()
                        sheet = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showsTrivia) {
            if let trivia = preview.trivia, let room = preview.room {
                TriviaView(game: trivia, session: session, isHost: room.role == .host,
                           playerName: currentPlayerName, photoData: currentPlayerPhoto) {
                    preview.finishTrivia()
                }
            }
        }
        .onChange(of: preview.trivia?.id) {
            guard preview.trivia != nil else { return }
            if sheet == nil { sheet = .triviaInvite }
            else if sheet == .games { opensTriviaAfterSheet = true }
        }
        .onChange(of: owner) {
            sheet = nil
            showsTrivia = false
            opensTriviaAfterSheet = false
            preview.leave()
        }
    }

    private func partyOptions(_ room: PartyPreview.Room) -> some View {
        Menu {
            Section("Preview as") {
                ForEach(PartyPreview.Role.allCases) { role in
                    Button(role.rawValue) {
                        preview.viewAs(role)
                    }
                    .accessibilityValue(room.role == role ? "Selected" : "")
                }
            }
            Section("Example state") {
                Button("Show ongoing Trivia") { preview.showExampleGame(.trivia) }
                Button("Show no ongoing games") { preview.showExampleGame(nil) }
            }
            Button("Exit preview", role: .destructive) { preview.leave() }
        } label: {
            Image("ProfileSettings").resizable().scaledToFit()
                .frame(width: 22, height: 22).accessibilityHidden(true)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large).fixedSize()
        .accessibilityLabel("Party options")
        .accessibilityIdentifier("partyPreviewOptions")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 32) {
            Button { sheet = .join } label: {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Image("PartyNFC").resizable().scaledToFit().frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        Spacer()
                        Image("ProfileChevron").resizable().scaledToFit().frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tap to join").font(.system(.title, design: .rounded, weight: .medium))
                    }
                }
                .foregroundStyle(Color.black).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.68, green: 0.84, blue: 0.80), in: .rect(cornerRadius: 28))
                .contentShape(.rect(cornerRadius: 28))
            }
            .buttonStyle(ProfilePressStyle()).accessibilityIdentifier("partyJoin")

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    Button("Join with code") { sheet = .code }.partySecondaryAction()
                    Button("Create a party") { sheet = .create }.partyPrimaryAction()
                }
            }
        }
    }

    private func roomHeader(_ room: PartyPreview.Room) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Text(room.name).font(.system(.largeTitle, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                partyOptions(room)
            }
            Button { sheet = .invite } label: {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Text("Party code").foregroundStyle(.secondary)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(PartyPreview.code).fontWeight(.medium).monospaced()
                    Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 18))
            .accessibilityLabel("Party code, \(PartyPreview.code). Show invite details.")
        }
    }

    private func ongoingGame(_ game: PartyGame) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Ongoing games")
            Button {
                if game == .trivia {
                    if preview.trivia?.phase == .invitation { sheet = .triviaInvite }
                    else { showsTrivia = true }
                }
            } label: {
                HStack(spacing: 16) {
                    PartyGameIcon(game: game)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(game.title).font(.system(.title3, design: .rounded, weight: .medium))
                        Text(game == .trivia ? "Join or return to the game" : "Example game in progress")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if game == .trivia {
                        Image("ProfileChevron").resizable().scaledToFit().frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 24))
            }
            .buttonStyle(ProfilePressStyle()).disabled(game != .trivia)
            .accessibilityElement(children: .combine)
        }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Leaderboard")
            if let trivia = preview.trivia, trivia.phase == .results {
                Button("View trivia podium") { showsTrivia = true }
                    .partySecondaryAction()
                ForEach(trivia.standings(playerName: currentPlayerName)) { row in
                    HStack {
                        Text(row.name).font(.headline)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(row.points.formatted()) pts").font(.headline).monospacedDigit()
                            Text("BAC —").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No scores yet.").font(.system(.title3, design: .rounded, weight: .medium))
                    Text("Scores will appear here after a game.")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func people(role: PartyPreview.Role) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("People")
            HStack(alignment: .center, spacing: 16) {
                ProfileAvatar(photoData: owner != nil && profile.owner == owner ? profile.profile.photoData : nil, side: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(owner != nil && profile.owner == owner && !profile.profile.name.isEmpty ? profile.profile.name : "You")
                        .font(.system(.headline, design: .rounded))
                    Text("You · \(role.rawValue)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(.title2, design: .rounded, weight: .medium)).accessibilityAddTraits(.isHeader)
    }

    private var currentPlayerName: String {
        owner != nil && profile.owner == owner && !profile.profile.name.isEmpty ? profile.profile.name : "You"
    }

    private var currentPlayerPhoto: Data? {
        owner != nil && profile.owner == owner ? profile.profile.photoData : nil
    }
}

private struct PartyEntrySheet: View {
    enum Mode { case create, tap, code }
    let preview: PartyPreview
    let mode: Mode
    @State private var name = ""
    @State private var code = ""
    @State private var message: String?
    @FocusState private var focusedField: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if mode == .create {
                        field("Party name", placeholder: "Friday night", text: $name)
                        if !name.isEmpty && !PartyPreview.validName(name) {
                            Text("Use 1–80 characters on one line.").font(.footnote).foregroundStyle(.secondary)
                        }
                        PartyTapIllustration { deviceID in
                            if preview.create(name: name, deviceID: deviceID) { dismiss() }
                            else { message = "Enter a party name first." }
                        }
                        if let message {
                            Text(message).foregroundStyle(.secondary).font(.footnote)
                        }
                        Button("Create party") {
                            if preview.create(name: name) { dismiss() }
                        }
                        .partyPrimaryAction()
                        .disabled(!PartyPreview.validName(name))
                    } else {
                        if mode == .tap {
                            PartyTapIllustration { _ in
                                preview.previewTap()
                                dismiss()
                            }
                        }
                        field("Party code", placeholder: PartyPreview.code, text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        if let message {
                            Text(message).foregroundStyle(.secondary).font(.footnote)
                        }
                        Button("Join with code") {
                            if preview.join(code: code) { dismiss() }
                            else { message = "That code wasn't found. Check it and try again." }
                        }
                        .partySecondaryAction().disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle(mode == .create ? "Create a party" : "Join a party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.subheadline, design: .rounded, weight: .medium))
            TextField(placeholder, text: text)
                .focused($focusedField, equals: title)
                .textFieldStyle(.plain)
                .padding(18).background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
                .accessibilityLabel(title)
        }
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded { focusedField = title })
    }
}

private struct PartyGamePicker: View {
    let preview: PartyPreview
    @State private var selectedGame: PartyGame?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose a game").font(.system(.largeTitle, design: .rounded, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: typeSize.isAccessibilitySize ? 16 : -56) {
                        ForEach(PartyGame.allCases) { game in
                            Button { selectedGame = game } label: {
                                PartyGameCard(game: game, overlapsNext: !typeSize.isAccessibilitySize && game != PartyGame.allCases.last)
                            }
                                .buttonStyle(ProfilePressStyle())
                                .zIndex(game == .pictionary ? 1 : 0)
                                .accessibilityHint("Shows game details.")
                                .accessibilityIdentifier("partyGame_\(game.rawValue)")
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Start a game").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(item: $selectedGame) { game in
                PartyGameDetail(game: game) {
                    preview.showExampleGame(game)
                    dismiss()
                }
            }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
    }
}

private struct PartyGameCard: View {
    let game: PartyGame
    var overlapsNext = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(game.title).font(.system(.title, design: .rounded, weight: .semibold))
                Text(game.invitation).font(.system(.subheadline, design: .rounded))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            PartyGameIcon(game: game, showsBackground: false)
                .offset(x: 8, y: -8)
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(.black)
        .padding(.horizontal, 24).padding(.top, 24)
        .padding(.bottom, overlapsNext ? 68 : 24)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(game.color)
                .shadow(color: .black.opacity(0.26), radius: 4, x: 0, y: -4)
        }
        .contentShape(.rect(cornerRadius: 28))
    }
}

private struct PartyGameDetail: View {
    let game: PartyGame
    let onPreview: () -> Void

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PartyGameCard(game: game)
                    Text(game.detail).font(.system(.title3, design: .rounded))
                    Button("Start game", action: onPreview)
                        .partyPrimaryAction()
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle(game.title).navigationBarTitleDisplayMode(.inline)
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
    }
}

private struct PartyInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    PartyTapIllustration()
                    Text("Or enter code to join")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    Text(PartyPreview.code).font(.system(.largeTitle, design: .rounded, weight: .medium)).monospaced()
                        .textSelection(.enabled).padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Invite people").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark)
    }
}

struct PartyGameIcon: View {
    let game: PartyGame
    var showsBackground = true

    var body: some View {
        Image(game.iconAsset).renderingMode(.original).resizable().scaledToFit()
            .frame(width: 64, height: 64)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 14).fill(game.color)
                }
            }
            .accessibilityHidden(true)
    }
}

private extension PartyGame {
    var color: Color {
        self == .trivia ? Color(red: 0.94, green: 0.80, blue: 0.32) : Color(red: 0.72, green: 0.65, blue: 0.91)
    }
}

private extension View {
    func partyPrimaryAction() -> some View {
        font(.system(.headline, design: .rounded)).foregroundStyle(.black)
            .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.extraLarge).tint(.white)
            .buttonSizing(.flexible)
    }

    func partySecondaryAction() -> some View {
        font(.system(.headline, design: .rounded))
            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.extraLarge)
            .buttonSizing(.flexible)
    }
}

#Preview("Party") {
    PartyView(profile: ProfileStore(), owner: nil, session: AuthSession(configuration: nil)).preferredColorScheme(.dark)
}
