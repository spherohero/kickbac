import SwiftUI

struct HomeView: View {
    let session: AuthSession
    let deviceFlow: DeviceSessionStore
    var onConnect: () -> Void = { }
    var onOnboarding: () -> Void = { }
    var isGameCheckIn = false
    var onGameCheckInComplete: (Double) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var readings: [BACReading] = []
    @State private var isShowingDemo = false
    @State private var reading: BACReading?
    @State private var phase: ReadingPhase = .ready
    @State private var startedAt: Date?
    @State private var runID: UUID?
    @State private var resultReveal: CGFloat = 0
    @State private var completionFeedback = 0
    @State private var stopFeedback = 0

    private let preparationDuration = 2.0
    private let sampleDuration = 6.0
    private var showsDemoLabels: Bool { isShowingDemo && !isGameCheckIn }
    private var summary: DailyBACSummary {
        DailyBACSummary(readings: isShowingDemo || isGameCheckIn ? readings : (session.history?.items.compactMap(\.bacReading) ?? []))
    }
    private var displayReading: BACReading? { isShowingDemo ? reading : deviceFlow.test?.measurement?.bacReading }
    private var visibleReveal: CGFloat { isShowingDemo ? resultReveal : (displayReading == nil ? 0 : 1) }
    private var visiblePhase: ReadingPhase {
        guard !isShowingDemo else { return phase }
        switch deviceFlow.test?.status {
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
                    Button(deviceFlow.hasActiveSession ? "View test" : "Connect") {
                        exitDemo()
                        onConnect()
                    }
                    .buttonStyle(.glass).controlSize(.large)
                    #if DEBUG
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Demo", action: startReading)
                                .disabled(visiblePhase.isRunning)
                                .accessibilityLabel("Demo reading").accessibilityIdentifier("homeDemoButton")
                            Button("Onboarding") {
                                interruptReading()
                                onOnboarding()
                            }
                            .accessibilityIdentifier("onboardingButton")
                        }
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    }
                    #endif
                }
                .frame(minHeight: 44).padding(.horizontal, 24).padding(.top, 12)
            } else {
                Color.clear.frame(height: 56).accessibilityHidden(true)
            }

            if showsDemoLabels {
                HStack {
                    Text("Simulated demo · not a measured BAC")
                    Spacer(minLength: 4)
                    Button("Exit demo", action: exitDemo)
                }
                .font(.system(.caption, design: .rounded)).padding(.horizontal, 24).padding(.top, 8)
                .accessibilityIdentifier("homeDemoNotice")
            } else if let message = deviceFlow.message {
                Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
            }

            GeometryReader { geometry in
                let metricSize = min(52, max(30, geometry.size.height * 0.1))
                let gaugeSide = max(0, min(geometry.size.width - 64, 300, geometry.size.height - 220))
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    metric(showsDemoLabels ? "Demo avg BAC" : "Avg BAC", value: summary.average, size: metricSize)
                    Spacer(minLength: 14)

                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isShowingDemo || visiblePhase != .sampling)) { timeline in
                        gauge(progress: progress(at: timeline.date))
                    }
                    .frame(width: gaugeSide, height: gaugeSide)

                    Spacer(minLength: 14)
                    metric(showsDemoLabels ? "Demo max BAC" : "Max BAC", value: summary.high, size: metricSize * 0.92)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(.body, design: .rounded))
        .safeAreaInset(edge: .bottom, spacing: 0) { readingControls }
        .background(background.ignoresSafeArea())
        .task(id: runID) { await runDemoReading() }
        .task(id: scenePhase) {
            if isGameCheckIn && scenePhase == .active && phase == .ready { startReading() }
        }
        .onDisappear {
            if isGameCheckIn { exitDemo() }
            else { interruptReading() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                if isGameCheckIn { exitDemo() }
                else { interruptReading() }
            }
        }
        .onChange(of: session.generation) { exitDemo() }
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
        .accessibilityLabel("\(isGameCheckIn ? "" : isShowingDemo ? "Simulated demo. " : "Loaded real readings today. ")\(title)")
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
        .accessibilityElement(children: .ignore)
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
                        Text(reading.band.title)
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
            if !isShowingDemo, let measurement = deviceFlow.test?.measurement, displayReading == nil {
                VStack(spacing: 10) {
                    Text(measurement.isTestReading ? "Test reading saved" : "Reading saved")
                        .font(.system(.headline, design: .rounded))
                    Text("No BAC estimate").font(.system(.subheadline, design: .rounded))
                    Text("\(measurement.raw.value) \(measurement.raw.unit.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .frame(width: side * 0.78)
        .allowsHitTesting(false)
    }

    private var readingControls: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isShowingDemo || visiblePhase != .sampling)) { timeline in
            HStack(spacing: 10) {
                Image("ReadingClock").resizable().scaledToFit().frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                if isShowingDemo {
                    if isGameCheckIn {
                        Text("\(elapsedTime(at: timeline.date), format: .number.precision(.fractionLength(2))) s").monospacedDigit()
                    } else {
                        Text("Demo · \(elapsedTime(at: timeline.date), format: .number.precision(.fractionLength(2))) s").monospacedDigit()
                    }
                } else if let measurement = deviceFlow.test?.measurement {
                    Text("\(Double(measurement.breathDurationMS) / 1000, format: .number.precision(.fractionLength(2))) s").monospacedDigit()
                } else if isGameCheckIn {
                    Text("— s")
                } else {
                    Text(deviceFlow.hasActiveSession ? "Waiting for a reading" : "No active test")
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
        .accessibilityLabel("Reading duration")
        .accessibilityValue(timerAccessibilityValue)
        .padding(12)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var timerAccessibilityValue: String {
        if isGameCheckIn && !isShowingDemo && deviceFlow.test?.measurement == nil { return "Breath test duration unavailable" }
        if !isShowingDemo {
            if let measurement = deviceFlow.test?.measurement { return "Recorded breath duration: \(measurement.breathDurationMS) milliseconds" }
            return deviceFlow.hasActiveSession ? "Waiting for a device reading" : "No active test"
        }
        return switch visiblePhase {
        case .ready: "Ready"
        case .preparing: "Starting in two seconds"
        case .sampling: "Reading in progress"
        case .stopping, .revealing, .result: "6 seconds"
        }
    }

    private func progress(at date: Date) -> Double {
        guard isShowingDemo else { return 0 }
        guard visiblePhase == .sampling, let startedAt else { return visiblePhase == .stopping || visiblePhase.showsResult ? 1 : 0 }
        return min(max(date.timeIntervalSince(startedAt) / sampleDuration, 0), 1)
    }

    private var instruction: String {
        if isGameCheckIn && !isShowingDemo && deviceFlow.test == nil { return "Take your breath test" }
        if !isShowingDemo {
            switch deviceFlow.test?.status {
            case .armed: return "Waiting for device"
            case .sampling: return "Device is sampling"
            case .complete: return "Your saved reading"
            case .cancelled: return "Test cancelled"
            case .expired: return "Test expired"
            default: return "Connect a device"
            }
        }
        return switch visiblePhase {
        case .ready: isGameCheckIn ? "Take your breath test" : "Demo reading"
        case .preparing: "Start blowing"
        case .sampling: "Keep blowing"
        case .stopping: "Stop blowing"
        case .revealing, .result: "Your reading"
        }
    }

    // Home's Debug action and the local game check-in share this in-memory sequence.
    // These readings never enter authenticated history; game completion retains only a local fixture.
    private func startReading() {
        guard !phase.isRunning, !deviceFlow.hasActiveSession else { return }
        isShowingDemo = true
        readings = [0.04, 0.05, 0.09].map { BACReading(value: $0, date: .now) }
        startedAt = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.24)) {
            resultReveal = 0
            phase = .preparing
        }
        runID = UUID()
    }

    private func elapsedTime(at date: Date) -> Double {
        if phase == .sampling { return sampleDuration * progress(at: date) }
        return phase == .stopping || phase.showsResult ? sampleDuration : 0
    }

    private func runDemoReading() async {
        guard isShowingDemo, let currentRun = runID, phase == .preparing else { return }
        do {
            try await Task.sleep(for: .seconds(preparationDuration))
            try Task.checkCancellation()
            guard runID == currentRun else { return }
            startedAt = .now
            phase = .sampling
            try await Task.sleep(for: .seconds(sampleDuration))
            try Task.checkCancellation()
            guard runID == currentRun else { return }
            phase = .stopping
            stopFeedback += 1
            // Keep the stop cue visible before revealing the result.
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            guard runID == currentRun else { return }
            // Demo only. Replace this sample with a completed hardware measurement.
            let completed = BACReading(value: 0.08, date: .now)
            reading = completed
            phase = .revealing
            withAnimation(.easeOut(duration: 0.22)) { readings.append(completed) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.24)) {
                resultReveal = 1
            }
            completionFeedback += 1
            try await Task.sleep(for: .milliseconds(240))
            guard runID == currentRun else { return }
            phase = .result
            if isGameCheckIn {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                guard runID == currentRun, scenePhase == .active else { return }
                onGameCheckInComplete(completed.value)
            }
        } catch is CancellationError {
            // Leaving Home discards an incomplete sample.
        } catch {
            interruptReading()
        }
    }

    private func interruptReading() {
        guard phase.isRunning else { return }
        runID = nil
        startedAt = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2)) {
            phase = reading == nil ? .ready : .result
            resultReveal = reading == nil ? 0 : 1
        }
    }

    private func exitDemo() {
        runID = nil
        isShowingDemo = false
        readings = []
        reading = nil
        phase = .ready
        resultReveal = 0
        startedAt = nil
    }

    private func gaugeAccessibilityValue(progress: Double) -> String {
        if !isShowingDemo {
            if let measurement = deviceFlow.test?.measurement {
                if let reading = measurement.bacReading { return "Estimated BAC \(reading.value.formatted())." }
                return "\(measurement.isTestReading ? "Simulated test reading. " : "")No BAC estimate. Raw sensor reading \(measurement.raw.value) \(measurement.raw.unit)."
            }
            return instruction
        }
        if phase.showsResult, let reading {
            return "\(isGameCheckIn ? "" : "Simulated demo. ")\(reading.value.formatted(.number.precision(.fractionLength(2)))) grams per deciliter. \(reading.band.title)."
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

#Preview("Home · Dark") { HomeView(session: AuthSession(configuration: nil), deviceFlow: DeviceSessionStore()).preferredColorScheme(.dark) }
