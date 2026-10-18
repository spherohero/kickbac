import SwiftUI

struct HomeView: View {
    let session: AuthSession
    let deviceFlow: DeviceSessionStore
    var onRetryTest: () -> Void = { }
    var isGameCheckIn = false
    var checkInSessionID: String? = nil
    var nfcReadingID: UUID? = nil
    var onNFCReadingConsumed: () -> Void = { }
    var onPracticeComplete: ((PracticeReading) -> Void)? = nil
    @Environment(PracticeReadingStore.self) private var practice
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var readings: [BACReading] = []
    @State private var isShowingPractice = false
    @State private var reading: BACReading?
    @State private var phase: ReadingPhase = .ready
    @State private var startedAt: Date?
    @State private var runID: UUID?
    @State private var resultReveal: CGFloat = 0
    @State private var completionFeedback = 0
    @State private var stopFeedback = 0
    @State private var isHolding = false
    @State private var sampledDuration = 0.01
    @State private var practiceError: String?
    @State private var readingTrigger: AppReadingTrigger = .touch
    @State private var practiceWasCancelled = false

    private let sampleDuration = 6.0
    private var summary: DailyBACSummary {
        DailyBACSummary(readings: isShowingPractice || isGameCheckIn ? readings : (session.history?.items.compactMap(\.bacReading) ?? []))
    }
    private var displayedTest: APITestSession? {
        guard !isGameCheckIn || deviceFlow.test?.id == checkInSessionID else { return nil }
        return deviceFlow.test
    }
    private var displayReading: BACReading? { isShowingPractice ? reading : displayedTest?.measurement?.bacReading }
    private var visibleReveal: CGFloat { isShowingPractice ? resultReveal : (displayReading == nil ? 0 : 1) }
    private var visiblePhase: ReadingPhase {
        guard !isShowingPractice else { return phase }
        switch displayedTest?.status {
        case .armed: return .preparing
        case .sampling: return .sampling
        case .complete: return .result
        default: return .ready
        }
    }
    private let background = Color("SplashBackground")

    var body: some View {
        VStack(spacing: 0) {
            if !isGameCheckIn {
                HStack {
                    Spacer(minLength: 8)
                    if !isShowingPractice, deviceFlow.message != nil {
                        Button("Retry") {
                            if deviceFlow.hasActiveSession { deviceFlow.retryPolling() }
                            else { onRetryTest() }
                        }
                        .buttonStyle(.glass).controlSize(.large).disabled(deviceFlow.isBusy)
                    }
                    if deviceFlow.isBusy { ProgressView().accessibilityLabel("Starting your test") }
                }
                .frame(minHeight: 44).padding(.horizontal, 24).padding(.top, 12)
            } else {
                Color.clear.frame(height: 56).accessibilityHidden(true)
            }

            if let message = practiceError ?? (isGameCheckIn && displayedTest == nil ? nil : deviceFlow.message) ?? practice.message {
                Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
            }

            if !isShowingPractice, let measurement = displayedTest?.measurement,
               let notice = measurement.acquisitionNotice {
                Text(notice)
                    .font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.top, 8)
                    .accessibilityIdentifier("homeAcquisitionNotice")
            }

            GeometryReader { geometry in
                let metricSize = min(52, max(30, geometry.size.height * 0.1))
                let gaugeSide = max(0, min(geometry.size.width - 64, 300, geometry.size.height - 220))
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    metric("Avg BAC", value: summary.average, size: metricSize)
                    Spacer(minLength: 14)

                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isShowingPractice || visiblePhase != .sampling)) { timeline in
                        gauge(progress: progress(at: timeline.date))
                    }
                    .frame(width: gaugeSide, height: gaugeSide)

                    Spacer(minLength: 14)
                    metric("Max BAC", value: summary.high, size: metricSize * 0.92)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(.body, design: .rounded))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !practiceWasCancelled { readingControls }
                if isGameCheckIn, isShowingPractice, (phase == .sampling || phase == .stopping) {
                    Button("Cancel test", action: cancelPracticeReading).frame(minHeight: 44)
                }
            }
        }
        .background(background.ignoresSafeArea())
        .task(id: runID) { await runPracticeReading() }
        .onChange(of: nfcReadingID, initial: true) {
            guard nfcReadingID != nil else { return }
            startReading(trigger: .nfc)
            onNFCReadingConsumed()
        }
        .onDisappear {
            if isGameCheckIn { exitPractice() }
            else { interruptReading() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                if isGameCheckIn { exitPractice() }
                else { interruptReading() }
            }
        }
        .onChange(of: session.generation) { exitPractice() }
        .onChange(of: deviceFlow.hasActiveSession) {
            if deviceFlow.hasActiveSession, readingTrigger != .nfc { exitPractice() }
        }
        .sensoryFeedback(.success, trigger: completionFeedback)
        .sensoryFeedback(.warning, trigger: stopFeedback)
        .sensoryFeedback(.selection, trigger: visiblePhase) { _, next in next == .sampling }
    }

    private func metric(_ title: String, value: Double?, size: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            if let value {
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: size, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
            } else {
                Text("—").font(.system(size: size, weight: .medium, design: .rounded))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isShowingPractice ? "App readings. " : "Loaded device readings today. ")\(title)")
        .accessibilityValue(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "No BAC estimates available")
    }

    private func gauge(progress: Double) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2 - 8

            ZStack {
                gaugeTrack
                    .overlay {
                        // Keep visible fill outside the glass material's compositing layer.
                        GaugeArc(progress: progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .opacity(visiblePhase == .ready ? 0 : 1 - visibleReveal)
                    }

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().fill(displayReading?.band.color ?? .gray).padding(4)
                    }
                    .frame(width: 18, height: 18)
                    .scaleEffect(reduceMotion ? 1 : 0.85 + 0.15 * visibleReveal)
                    .offset(x: radius)
                    .rotationEffect(.degrees(displayReading.map { $0.band.angle(for: $0.value) } ?? 135))
                    .opacity(visibleReveal)

                gaugeContent(progress: progress, side: side)
            }
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Breath reading")
        .accessibilityValue(gaugeAccessibilityValue(progress: progress))
        .accessibilityIdentifier("homeBACGauge")
    }

    private var gaugeTrack: some View {
        let outline = GaugeArc(progress: 1).stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
        let solid = reduceTransparency || contrast == .increased
        return ZStack {
            outline.fill(.white.opacity(solid ? 0.4 : 0.06))

            ZStack {
                ForEach(BACBand.allCases, id: \.rawValue) { band in
                    GaugeSegment(index: band.rawValue)
                        .stroke(band.color, style: StrokeStyle(lineWidth: 48, lineCap: .round))
                }
            }
            .blur(radius: solid ? 0 : 3)
            .opacity(visibleReveal)

            Color.clear
                .glassEffect(solid ? .identity : .regular, in: outline)
                .opacity(1 - 0.65 * visibleReveal)

            outline.stroke(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.6
            )
        }
        .mask(outline)
        .allowsHitTesting(false)
    }

    private func gaugeContent(progress: Double, side: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 16) {
                KickBACStar(progress: 0, size: 48, isExpanding: false)
                    .rotationEffect(.degrees(reduceMotion ? 0 : progress * 60))
                if !typeSize.isAccessibilitySize {
                    Text(instruction)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .contentTransition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .opacity(visiblePhase.showsResult ? 0 : 1)
            .blur(radius: reduceMotion || !visiblePhase.showsResult ? 0 : 2)
            .animation(.easeOut(duration: 0.12).delay(visiblePhase == .sampling && !reduceMotion ? 0.13 : 0), value: visiblePhase)

            if let reading = displayReading {
                VStack(spacing: 20) {
                    if !typeSize.isAccessibilitySize {
                        Text(isShowingPractice ? "App reading" : reading.band.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(reading.band.color)
                            .multilineTextAlignment(.center)
                    }
                    Text(reading.value, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: side * 0.32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .frame(maxWidth: side * 0.76)
                .opacity(visibleReveal)
                .animation(.easeOut(duration: visibleReveal == 0 ? 0.12 : 0.22), value: visibleReveal)
                .offset(y: reduceMotion ? -8 : -4 - 4 * visibleReveal)
            }
            if !isShowingPractice, let measurement = displayedTest?.measurement, displayReading == nil {
                VStack(spacing: 10) {
                    Text(measurement.sourceTitle)
                        .font(.system(.headline, design: .rounded))
                    Text("No BAC estimate").font(.system(.subheadline, design: .rounded))
                    Text("\(measurement.raw.value) \(measurement.raw.unit.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            Button(action: practiceTap) {
                Circle().fill(.clear).frame(width: side * 0.78, height: side * 0.78)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(deviceFlow.hasActiveSession || deviceFlow.isBusy || !practice.canSave)
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding { isHolding = true; startReading() }
                }
                .onEnded { _ in
                    isHolding = false
                    if readingTrigger == .touch { finishPractice() }
                })
            .accessibilityLabel("App reading")
            .accessibilityHint("Hold for a random demo reading; release to save. Tap the NFC tag for a simulated 0.00 reading.")
            .accessibilityValue(gaugeAccessibilityValue(progress: progress))
        }
        .frame(width: side * 0.78)
    }

    private var readingControls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return GlassEffectContainer(spacing: 12) {
            layout {
                readingDuration
                if canTestAgain {
                    Button("Test again", action: prepareForNextTest)
                        .font(.system(.headline, design: .rounded))
                        .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                        .frame(minHeight: 54)
                        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                        .accessibilityHint("Resets the circle. Tap the breathalyzer's NFC tag to start a new test.")
                        .accessibilityIdentifier("homeTestAgainButton")
                }
            }
        }
        .padding(12)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var canTestAgain: Bool {
        !isGameCheckIn && !deviceFlow.isBusy && !deviceFlow.hasActiveSession
            && (isShowingPractice ? phase == .result : deviceFlow.test?.status == .complete)
    }

    private func prepareForNextTest() {
        guard canTestAgain else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            deviceFlow.resetCompletedTest()
            exitPractice()
        }
    }

    private var readingDuration: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isShowingPractice || visiblePhase != .sampling)) { timeline in
            HStack(spacing: 10) {
                if isShowingPractice, visiblePhase != .ready {
                    Image("ReadingClock").resizable().scaledToFit().frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text("\(visiblePhase == .sampling ? max(0, sampleDuration - elapsedTime(at: timeline.date)) : sampledDuration, format: .number.precision(.fractionLength(2))) s")
                        .monospacedDigit()
                } else {
                    Text(readingStatus)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(.title3, design: .rounded, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .background {
            if reduceTransparency || contrast == .increased {
                Capsule().fill(Color(white: 0.16))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
            }
        }
        .glassEffect(reduceTransparency || contrast == .increased ? .identity : .regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isShowingPractice && visiblePhase == .sampling ? "Time remaining" : (isShowingPractice && visiblePhase != .ready ? "Reading duration" : "Reading status"))
        .accessibilityValue(timerAccessibilityValue)
    }

    private var readingStatus: String {
        if isShowingPractice { return "Connect a breathalyzer" }
        switch displayedTest?.status {
        case .armed: return "Waiting for the breathalyzer"
        case .sampling: return "Taking a reading"
        case .complete: return displayedTest?.measurement?.durationText ?? "Duration unavailable"
        default: return "Connect a breathalyzer"
        }
    }

    private var timerAccessibilityValue: String {
        if isShowingPractice, visiblePhase != .ready {
            if visiblePhase == .sampling { return "Countdown in progress" }
            return "\(sampledDuration.formatted(.number.precision(.fractionLength(2)))) seconds"
        }
        return readingStatus
    }

    private func progress(at date: Date) -> Double {
        guard isShowingPractice else { return 0 }
        guard visiblePhase == .sampling, let startedAt else { return visiblePhase == .stopping || visiblePhase.showsResult ? 1 : 0 }
        return min(max(date.timeIntervalSince(startedAt) / sampleDuration, 0), 1)
    }

    private var instruction: String {
        if practiceWasCancelled { return "Test cancelled" }
        if !isShowingPractice {
            switch displayedTest?.status {
            case .armed: return "Waiting for the breathalyzer"
            case .sampling: return "Sensor acquisition · breath not validated"
            case .complete: return "Your saved reading"
            case .cancelled: return "Test cancelled"
            case .expired: return "Test expired"
            default: return "Tap your phone to the breathalyzer"
            }
        }
        return switch visiblePhase {
        case .ready: "Tap your phone to the breathalyzer"
        case .preparing: "Start blowing"
        case .sampling: readingTrigger == .nfc ? "Keep blowing" : "Release to finish"
        case .stopping: "Finishing reading"
        case .revealing, .result: "App reading"
        }
    }

    private func practiceTap() {
        guard !phase.isRunning else { return }
        startReading()
        finishPractice()
    }

    private func startReading(trigger: AppReadingTrigger = .touch) {
        guard !phase.isRunning, practice.canSave,
              trigger == .nfc || (!deviceFlow.hasActiveSession && !deviceFlow.isBusy) else { return }
        readingTrigger = trigger
        practiceWasCancelled = false
        isShowingPractice = true
        practiceError = nil
        readings = practice.readings.map(\.reading)
        reading = nil
        startedAt = .now
        sampledDuration = 0.01
        resultReveal = 0
        phase = .sampling
        runID = UUID()
    }

    private func finishPractice() {
        guard isShowingPractice, phase == .sampling, let startedAt else { return }
        sampledDuration = min(sampleDuration, max(0.01, Date.now.timeIntervalSince(startedAt)))
        phase = .stopping
        stopFeedback += 1
        runID = UUID()
    }

    private func elapsedTime(at date: Date) -> Double {
        if phase == .sampling, let startedAt { return min(sampleDuration, max(0, date.timeIntervalSince(startedAt))) }
        return phase == .stopping || phase.showsResult ? sampledDuration : 0
    }

    private func runPracticeReading() async {
        guard isShowingPractice, let currentRun = runID else { return }
        do {
            if phase == .sampling {
                try await Task.sleep(for: .seconds(sampleDuration))
                guard !Task.isCancelled, runID == currentRun else { return }
                finishPractice()
                return
            }
            guard phase == .stopping else { return }
            try await Task.sleep(for: .milliseconds(450))
            try Task.checkCancellation()
            guard runID == currentRun, readingTrigger == .nfc || !deviceFlow.hasActiveSession else { return }
            let sample = try practice.save(value: readingTrigger.makeValue(),
                                           duration: sampledDuration)
            let completed = sample.reading
            reading = completed
            phase = .revealing
            withAnimation(.easeOut(duration: 0.22)) { readings.append(completed); resultReveal = 1 }
            completionFeedback += 1
            try await Task.sleep(for: .milliseconds(240))
            guard runID == currentRun else { return }
            phase = .result
            if let onPracticeComplete {
                try await Task.sleep(for: .milliseconds(1200))
                guard runID == currentRun else { return }
                onPracticeComplete(sample)
            }
        } catch is CancellationError {
            // Navigation/backgrounding cancels an unfinished practice reading.
        } catch {
            practiceError = practice.message ?? "Couldn't save this reading."
            interruptReading()
        }
    }

    private func interruptReading() {
        isHolding = false
        guard phase.isRunning else { return }
        runID = nil
        startedAt = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2)) {
            phase = reading == nil ? .ready : .result
            resultReveal = reading == nil ? 0 : 1
        }
    }

    private func cancelPracticeReading() {
        guard isShowingPractice, phase == .sampling || phase == .stopping else { return }
        isHolding = false
        runID = nil
        startedAt = nil
        reading = nil
        phase = .ready
        practiceWasCancelled = true
    }

    private func exitPractice() {
        practiceWasCancelled = false
        isHolding = false
        practiceError = nil
        runID = nil
        isShowingPractice = false
        readings = []
        reading = nil
        phase = .ready
        resultReveal = 0
        startedAt = nil
    }

    private func gaugeAccessibilityValue(progress: Double) -> String {
        if !isShowingPractice {
            if let measurement = displayedTest?.measurement {
                if let reading = measurement.bacReading { return "Estimated BAC \(reading.value.formatted())." }
                return "\(measurement.durationAccessibilityValue). No BAC estimate. Raw sensor reading \(measurement.raw.value) \(measurement.raw.unit)."
            }
            return instruction
        }
        if phase.showsResult, let reading {
            return "App reading. \(reading.value.formatted(.number.precision(.fractionLength(2)))) grams per deciliter. \(reading.band.title)."
        }
        return phase == .sampling ? "Keep blowing. \(Int(progress * 100)) percent complete" : instruction
    }
}

private enum ReadingPhase {
    case ready, preparing, sampling, stopping, revealing, result
    var showsResult: Bool { self == .revealing || self == .result }
    var isRunning: Bool { self != .ready && self != .result }
}

private extension BACBand {
    var color: Color {
        let components: (Double, Double, Double) = switch self {
        case .notDetected: (0.72, 0.76, 0.84)
        case .detected: (0.00, 0.86, 0.88)
        case .judgmentAffected: (0.18, 0.60, 1.00)
        case .coordinationAffected: (1.00, 0.82, 0.08)
        case .impaired: (1.00, 0.46, 0.08)
        case .highImpairment: (1.00, 0.32, 0.40)
        }
        return Color(red: components.0, green: components.1, blue: components.2)
    }
}

#Preview("Home · Dark") { HomeView(session: AuthSession(configuration: nil), deviceFlow: DeviceSessionStore()).environment(PracticeReadingStore(directory: .temporaryDirectory.appending(path: "KickBACPracticePreview"))).preferredColorScheme(.dark) }
