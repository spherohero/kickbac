import SwiftUI

struct TriviaInvitationSheet: View {
    let onJoin: () -> Void
    let onSkip: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 16) {
            PartyGameIcon(game: .trivia)
            Text("Trivia").font(.system(.title, design: .rounded, weight: .bold))
            Button("Join game", action: onJoin)
                .partyPrimaryAction()
                .accessibilityIdentifier("triviaJoinGame")
            Button("Skip game", action: onSkip).frame(minHeight: 44)
        }
        .padding(24).padding(.top, 8)
        .presentationDetents([.height(typeSize.isAccessibilitySize ? 420 : 310)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color("SplashBackground"))
        .preferredColorScheme(.dark)
    }
}

struct TriviaView: View {
    let game: TriviaPreview
    let session: AuthSession
    let isHost: Bool
    let playerName: String
    let photoData: Data?
    let onFinish: () -> Void
    var deviceFlow: DeviceSessionStore? = nil
    var checkInSessionID: String? = nil
    var checkInDeviceID: String? = nil
    var checkInMessage: String? = nil
    var nfcReadingID: UUID? = nil
    var onNFCReadingConsumed: () -> Void = { }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var wheelRotation = 0.0
    @State private var clockwise = true
    @State private var spinTurns = 3
    @State private var spinVelocity = 0.0
    @State private var wheelLanded = false

    var body: some View {
        presentation
        .task(id: game.category) { await animateSpin() }
        .task(id: game.deadline) { await runRoundClock() }
        .task(id: game.answeredCount) {
            guard game.everyoneAnswered else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                game.revealIfReady()
            } catch { }
        }
        .task(id: game.phase) { await driveLocalRound() }
        .onChange(of: deviceFlow?.test?.status, initial: true) { acceptCheckIn() }
        .onChange(of: checkInSessionID) { acceptCheckIn() }
        .onChange(of: game.phase, initial: true) {
            if game.phase == .tap { game.previewTap() }
            acceptCheckIn()
        }
    }

    private var presentation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                page
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color("SplashBackground").ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .navigationTitle("Trivia").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    #if DEBUG
                    ToolbarItem(placement: .primaryAction) { developmentMenu }
                    #endif
                }
        }
        .font(.system(.body, design: .rounded)).preferredColorScheme(.dark).tint(.primary)
        .sensoryFeedback(.selection, trigger: game.selectedAnswer) { _, next in next != nil }
        .sensoryFeedback(.success, trigger: game.correctCount)
        .sensoryFeedback(.error, trigger: game.phase) { _, next in
            next == .reveal && game.earnedPoints == 0 && game.participation == .joined
        }
    }

    @ViewBuilder private var page: some View {
        switch game.phase {
        case .invitation:
            // The normal entry uses the compact sheet in PartyView.
            TriviaInvitationSheet(onJoin: { game.join() }, onSkip: { game.skip(); dismiss() })
        case .tap, .breath: breathPage
        case .lobby:
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heading("Who’s ready?")
                    if let message = game.connectionMessage {
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(game.participantRows(playerName: playerName)) { row in readyRow(row) }
                }.padding(24).frame(maxWidth: 480)
            }.scrollIndicators(.hidden)
        case .wheel: wheelPage
        case .question, .waiting: questionPage
        case .reveal:
            ScrollView {
                roundResults.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        case .results:
            ScrollView {
                TriviaPodium(rows: game.standings(playerName: playerName), photoData: photoData)
                    .padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
    }

    private var breathPage: some View {
            VStack {
                if let checkInMessage { Text(checkInMessage).font(.footnote).padding(.horizontal, 24) }
                if let deviceFlow {
                    HomeView(session: session, deviceFlow: deviceFlow, isGameCheckIn: true,
                             checkInSessionID: checkInSessionID,
                             nfcReadingID: nfcReadingID, onNFCReadingConsumed: onNFCReadingConsumed,
                             onPracticeComplete: {
                                 if game.phase == .tap { game.previewTap() }
                                 game.completePracticeReading(value: $0.value)
                             })
                } else {
                    Text("No test connected.").foregroundStyle(.secondary)
                    Button("Continue without a test") { game.completePreviewBreath() }.frame(minHeight: 44)
                }
                if let test = deviceFlow?.test, test.id == checkInSessionID, test.status == .expired {
                    Text("Test expired. Tap the breathalyzer to try again.")
                        .font(.footnote).padding()
                }
                if deviceFlow?.test?.id == checkInSessionID, deviceFlow?.test?.status == .armed {
                    Button("Cancel test") { Task { await deviceFlow?.cancel { try await session.cancelSession($0) } } }
                        .frame(minHeight: 44)
                }
                if deviceFlow?.message != nil {
                    Button("Retry test status") { deviceFlow?.retryPolling() }.frame(minHeight: 44)
                }
                if deviceFlow?.hasActiveSession != true {
                    Button("Continue without a test") {
                        if game.phase == .tap { game.previewTap() }
                        game.completePreviewBreath()
                    }.frame(minHeight: 44)
                }
            }
    }

    private func readyRow(_ row: TriviaReadyPlayer) -> some View {
        HStack(spacing: 14) {
            ProfileAvatar(photoData: row.isYou ? photoData : nil, side: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.name).font(.headline)
                Text(row.status.title).font(.subheadline)
                    .foregroundStyle(row.status == .ready ? Color.green : row.status == .checkingIn ? .yellow : .secondary)
            }
            Spacer(minLength: 0)
            if row.status == .ready {
                Image("OnboardingCheck").resizable().scaledToFit().frame(width: 24, height: 24)
                    .foregroundStyle(.green).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .combine)
    }

    private func acceptCheckIn() {
        guard game.phase == .breath, let checkInSessionID, let test = deviceFlow?.test,
              test.id == checkInSessionID, test.userID == session.profileOwner,
              test.deviceID == checkInDeviceID, test.status == .complete,
              let measurement = test.measurement, measurement.hasValidAcquisition,
              measurement.sessionID == test.id, measurement.deviceID == test.deviceID else { return }
        game.completePreviewBreath(bac: measurement.bacReading?.value)
    }

    private var wheelPage: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.2
            let side = min(geometry.size.width, 360, wide ? geometry.size.height : max(100, geometry.size.height - (typeSize.isAccessibilitySize ? 250 : 180)))
            let layout = wide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 16) {
                    roundLabel
                    heading(game.spinnerID == game.localPlayerID ? "You’re up" : "\(spinnerName)’s turn")
                        .lineLimit(2).minimumScaleFactor(0.6)
                    if wide { wheelInstruction }
                }
                if !wide { Spacer(minLength: 0) }
                TriviaWheel(rotation: $wheelRotation, isEnabled: game.spinnerID == game.localPlayerID && game.category == nil,
                            onSpin: spin)
                    .frame(width: side, height: side).frame(maxWidth: .infinity)
                if !wide {
                    Spacer(minLength: 0)
                    wheelInstruction
                }
            }
        }.padding(24).frame(maxWidth: 760)
    }

    private var wheelInstruction: some View {
        Text(game.category.map { wheelLanded ? $0.title : "Spinning…" } ?? (game.spinnerID == game.localPlayerID ? "Tap or swipe to spin" : "Waiting for \(spinnerName)"))
            .font(.system(.headline, design: .rounded)).foregroundStyle(.secondary)
            .lineLimit(2).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private var spinnerName: String {
        game.playerName(for: game.spinnerID ?? game.localPlayerID, currentName: playerName)
    }

    private var roundLabel: some View {
        HStack {
            Text("Round \(game.roundNumber) of \(game.roundCount)")
            Spacer(minLength: 8)
            Text("\(game.totalPoints.formatted()) pts").monospacedDigit()
        }.font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    @ViewBuilder private var questionPage: some View {
        if let question = game.question {
            GeometryReader { geometry in
                let compact = geometry.size.height < 520
                if geometry.size.width > geometry.size.height * 1.2 {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            countdown(category: question.category)
                            questionHeading(question, compact: true).frame(maxHeight: .infinity)
                            answerStatus
                        }.frame(maxWidth: .infinity)
                        answerGrid(question, singleColumn: false).frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                        if !typeSize.isAccessibilitySize { roundLabel }
                        countdown(category: question.category)
                        questionHeading(question, compact: compact)
                            .frame(maxHeight: geometry.size.height * 0.29, alignment: .leading)
                        answerGrid(question, singleColumn: typeSize.isAccessibilitySize && geometry.size.height >= 500)
                            .frame(maxHeight: .infinity)
                        answerStatus
                    }
                }
            }.padding(24).frame(maxWidth: 760)
        }
    }

    private func questionHeading(_ question: TriviaQuestion, compact: Bool) -> some View {
        Text(question.prompt)
            .font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold))
            .lineLimit(4).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }

    private func answerGrid(_ question: TriviaQuestion, singleColumn: Bool) -> some View {
        VStack(spacing: 12) {
            if singleColumn {
                ForEach(question.choices) { answer($0) }
            } else {
                HStack(spacing: 12) { answer(question.choices[0]); answer(question.choices[1]) }
                HStack(spacing: 12) { answer(question.choices[2]); answer(question.choices[3]) }
            }
        }
    }

    private var answerStatus: some View {
        let showsStatus = game.phase == .waiting || game.participation == .skipped
        return Text(game.participation == .skipped ? "Sitting out" : "Answer locked")
            .font(.system(.headline, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .opacity(showsStatus ? 1 : 0)
            .accessibilityHidden(!showsStatus)
    }

    private func countdown(category: TriviaCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title).font(.system(.headline, design: .rounded)).foregroundStyle(category.color)
                .lineLimit(1).minimumScaleFactor(0.7)
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(category.color)
                                .frame(width: geometry.size.width * game.remainingFraction(now: context.date))
                        }
                }.frame(height: 6)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Time remaining")
                    .accessibilityValue("\(game.secondsRemaining(now: context.date)) seconds")
            }
        }
    }

    private func answer(_ choice: TriviaQuestion.Choice) -> some View {
        let selected = game.selectedAnswer == choice.id
        let color = Self.answerColors[choice.id]
        return Button { game.answer(choice.id) } label: {
            Text(choice.text).font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14).frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(.black)
            .background(color, in: .rect(cornerRadius: 22))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 22).strokeBorder(.black, lineWidth: 3) }
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(ProfilePressStyle())
        .disabled(game.phase == .waiting || game.participation != .joined)
        .accessibilityLabel(choice.text).accessibilityValue(selected ? "Your answer, locked" : "")
        .accessibilityIdentifier("triviaAnswer_\(choice.id)")
    }

    private var roundResults: some View {
        VStack(alignment: .leading, spacing: 28) {
            roundLabel
            heading(game.participation == .skipped ? "Round results" : game.earnedPoints > 0 ? "You got it!" : game.selectedAnswer == nil ? "Time’s up" : "Not this time")
            if let question = game.question {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Correct answer").font(.subheadline).foregroundStyle(.secondary)
                    Text(question.answers[question.correctIndex])
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                }.accessibilityElement(children: .combine)
            }
            VStack(spacing: 22) {
                ForEach(game.standings(playerName: playerName)) { row in
                    HStack(spacing: 14) {
                        ProfileAvatar(photoData: row.isYou ? photoData : nil, side: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.headline)
                            Text("\(row.points.formatted()) total").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("+\(row.lastPoints.formatted())")
                            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                            .foregroundStyle(row.lastPoints > 0 ? Color.green : .secondary)
                            .accessibilityLabel("\(row.lastPoints) points this round")
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch game.phase {
        case .tap:
            Button("Skip game") { game.skip() }.frame(minHeight: 44).padding(.bottom, 12)
        case .lobby:
            VStack(spacing: 8) {
                Button("Leave game") {
                    game.skip()
                    dismiss()
                }.frame(minHeight: 44)
                if isHost {
                    primary("Start trivia") { game.begin(isHost: true) }.disabled(!game.canStart)
                } else {
                    Text("Waiting for the host").foregroundStyle(.secondary).frame(minHeight: 44)
                }
                if game.participation == .skipped {
                    Button("Join game") { game.join() }.frame(minHeight: 44)
                }
            }.padding(24)
        case .reveal:
            if !game.usesNearby || isHost {
                primary(game.roundNumber == game.roundCount ? "See podium" : "Next round") { game.next(isHost: true) }
                    .padding(24)
            } else {
                Text("Waiting for the next round").foregroundStyle(.secondary).padding(24)
            }
        case .results:
            primary("Back to party") { onFinish(); dismiss() }.padding(24)
        default: EmptyView()
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54).background(.white, in: .capsule)
        }.buttonStyle(ProfilePressStyle()).frame(maxWidth: 432)
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
    }

    #if DEBUG
    private var developmentMenu: some View {
        Menu {
            Section("Game options") {
                if game.phase == .tap { Button("Continue without a test") { game.previewTap(); game.completePreviewBreath() } }
                if game.phase == .breath { Button("Continue without a test") { game.completePreviewBreath() } }
                Toggle("Players", isOn: Binding(get: { game.includesExamplePlayers }, set: { game.setExamplePlayers($0) }))
                    .disabled(game.phase != .invitation && game.phase != .lobby)
            }
        } label: {
            Image("ProfileSettings").resizable().scaledToFit().frame(width: 24, height: 24)
        }.accessibilityLabel("Trivia options")
    }
    #endif

    private func spin(_ clockwise: Bool, _ turns: Int, _ velocity: Double) {
        self.clockwise = clockwise
        spinTurns = turns
        spinVelocity = velocity
        game.spin(playerID: game.localPlayerID)
    }

    private func animateSpin() async {
        wheelLanded = false
        guard game.phase == .wheel, let category = game.category,
              let index = TriviaCategory.allCases.firstIndex(of: category) else { return }
        let target = TriviaWheelMotion.target(from: wheelRotation, categoryIndex: index, clockwise: clockwise, turns: spinTurns)
        let distance = target - wheelRotation
        let velocity = distance == 0 ? 0 : spinVelocity / distance
        withAnimation(reduceMotion ? nil : .interpolatingSpring(duration: 1.25, bounce: 0, initialVelocity: velocity)) {
            wheelRotation = target
        }
        do {
            if !reduceMotion { try await Task.sleep(for: .seconds(1.25)) }
            try Task.checkCancellation()
            wheelLanded = true
            try await Task.sleep(for: .milliseconds(450))
            try Task.checkCancellation()
            game.showQuestion()
        } catch { }
    }

    private func runRoundClock() async {
        guard let deadline = game.deadline, game.phase == .question || game.phase == .waiting else { return }
        do {
            #if DEBUG
            if game.includesExamplePlayers {
                try await Task.sleep(for: .seconds(min(2, max(0, deadline.timeIntervalSinceNow))))
                try Task.checkCancellation()
                game.submitExampleAnswers()
            }
            #endif
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            try Task.checkCancellation()
            game.revealExpired()
        } catch { }
    }

    private func driveLocalRound() async {
        do {
            if game.phase == .reveal && !voiceOver {
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                game.next(isHost: true)
                return
            }
            #if DEBUG
            if game.phase == .wheel && game.includesExamplePlayers, let spinner = game.spinnerID, spinner != game.localPlayerID {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                clockwise = true
                spinTurns = 3
                spinVelocity = 0
                game.spin(playerID: spinner)
            }
            #endif
        } catch { }
    }

    private static let answerColors: [Color] = [
        Color(red: 0.97, green: 0.55, blue: 0.53), Color(red: 0.55, green: 0.72, blue: 1),
        Color(red: 0.96, green: 0.81, blue: 0.36), Color(red: 0.62, green: 0.84, blue: 0.69)
    ]
}
