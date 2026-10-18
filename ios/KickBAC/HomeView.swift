import SwiftUI

struct HomeView: View {
    var onOnboarding: () -> Void = { }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    // Sample readings remain separate from any future breathalyzer connection.
    @State private var readings = [0.04, 0.05, 0.09].map { BACReading(value: $0, date: .now) }
    @State private var reading: BACReading?
    @State private var phase: ReadingPhase = .ready
    @State private var startedAt: Date?
    @State private var runID: UUID?
    @State private var resultReveal: CGFloat = 0
    @State private var completionFeedback = 0
    @State private var stopFeedback = 0

    private let preparationDuration = 2.0
    private let sampleDuration = 6.0
    private var summary: DailyBACSummary { DailyBACSummary(readings: readings) }
    private let background = Color("SplashBackground")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Home")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                #if DEBUG
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Demo", action: startReading)
                            .disabled(phase.isRunning)
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

            GeometryReader { geometry in
                let metricSize = min(52, max(30, geometry.size.height * 0.1))
                let gaugeSide = max(0, min(geometry.size.width - 64, 300, geometry.size.height - 220))
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    metric("Avg BAC", value: summary.average, size: metricSize)
                    Spacer(minLength: 14)

                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: phase != .sampling)) { timeline in
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
        .safeAreaInset(edge: .bottom, spacing: 0) { readingControls }
        .background(background.ignoresSafeArea())
        .task(id: runID) { await runDemoReading() }
        .onDisappear { interruptReading() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { interruptReading() }
        }
        .sensoryFeedback(.success, trigger: completionFeedback)
        .sensoryFeedback(.warning, trigger: stopFeedback)
        .sensoryFeedback(.selection, trigger: phase) { _, next in next == .sampling }
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
        .accessibilityLabel(title == "Avg BAC" ? "Today's average BAC" : "Today's highest BAC")
        .accessibilityValue(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "No readings today")
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
                            .opacity(phase == .ready ? 0 : 1 - resultReveal)
                    }

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().fill(reading?.band.color ?? .gray).padding(4)
                    }
                    .frame(width: 18, height: 18)
                    .scaleEffect(reduceMotion ? 1 : 0.85 + 0.15 * resultReveal)
                    .offset(x: radius)
                    .rotationEffect(.degrees(reading.map { $0.band.angle(for: $0.value) } ?? 135))
                    .opacity(resultReveal)

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
            .opacity(resultReveal)

            Color.clear
                .glassEffect(solid ? .identity : .regular, in: outline)
                .opacity(1 - 0.65 * resultReveal)

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
            .opacity(phase.showsResult ? 0 : 1)
            .blur(radius: reduceMotion || !phase.showsResult ? 0 : 2)
            .animation(.easeOut(duration: 0.12).delay(phase == .sampling && !reduceMotion ? 0.13 : 0), value: phase)

            if let reading {
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
                .opacity(resultReveal)
                .animation(.easeOut(duration: resultReveal == 0 ? 0.12 : 0.22), value: resultReveal)
                .offset(y: reduceMotion ? -8 : -4 - 4 * resultReveal)
            }
        }
        .frame(width: side * 0.78)
        .allowsHitTesting(false)
    }

    private var readingControls: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: phase != .sampling)) { timeline in
            HStack(spacing: 10) {
                Image("ReadingClock").resizable().scaledToFit().frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("\(elapsedTime(at: timeline.date), format: .number.precision(.fractionLength(2))) s")
                    .monospacedDigit()
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
        switch phase {
        case .ready: "Ready"
        case .preparing: "Starting in two seconds"
        case .sampling: "Reading in progress"
        case .stopping, .revealing, .result: "6 seconds"
        }
    }

    private func progress(at date: Date) -> Double {
        guard phase == .sampling, let startedAt else { return phase == .stopping || phase.showsResult ? 1 : 0 }
        return min(max(date.timeIntervalSince(startedAt) / sampleDuration, 0), 1)
    }

    private var instruction: String {
        switch phase {
        case .ready: "Tap the breathalyzer"
        case .preparing: "Start blowing"
        case .sampling: "Keep blowing"
        case .stopping: "Stop blowing"
        case .revealing, .result: "Your reading"
        }
    }

    // Route the confirmed NFC tap here when tag handling is connected.
    private func startReading() {
        guard !phase.isRunning else { return }
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
        guard let currentRun = runID, phase == .preparing else { return }
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

    private func gaugeAccessibilityValue(progress: Double) -> String {
        if phase.showsResult, let reading {
            return "\(reading.value.formatted(.number.precision(.fractionLength(2)))) grams per deciliter. \(reading.band.title)."
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

#Preview("Home · Dark") { HomeView().preferredColorScheme(.dark) }
