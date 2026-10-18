import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSession.self) private var session
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var step: Step = .welcome
    @State private var birthday = Date()
    @State private var phone = ""
    @State private var phoneCountry = PhoneCountry.unitedStates
    @State private var showsCountryPicker = false
    @State private var code = ""
    @State private var name = ""
    @State private var photo: UIImage?
    @State private var camera = ProfileCamera()
    @State private var cameraPreviewSize: CGSize = .zero
    @State private var error: String?
    @State private var showsSaveError = false
    @State private var profileOwner: String?
    @State private var isLoadingProfile = false
    @State private var profileLoadFailed = false
    @FocusState private var focusedStep: Step?

    init() {
        #if DEBUG
        // Exercise text entry in Simulator without repeating the birthday step.
        if ProcessInfo.processInfo.arguments.contains("--test-onboarding-fields") {
            _step = State(initialValue: .phone)
        }
        if ProcessInfo.processInfo.arguments.contains("--test-onboarding-camera") {
            _step = State(initialValue: .photo)
        }
        #endif
    }

    private enum Step: Int {
        case welcome, birthday, phone, code, name, photo, complete

        var title: String {
            switch self {
            case .welcome: ""
            case .birthday: "When's your birthday?"
            case .phone: "What's your number?"
            case .code: "What's your code?"
            case .name: "What should we call you?"
            case .photo: "Ready for a photo?"
            case .complete: "You're all set"
            }
        }

        var detail: String {
            switch self {
            case .welcome, .birthday, .complete: ""
            case .phone: "Enter your phone number to continue."
            case .code: "Enter the six-digit code."
            case .name: "This is the name your party will see."
            case .photo: "Take a fresh photo for your party profile."
            }
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if isLoadingProfile {
                ProgressView("Loading your profile").tint(.black)
            } else if profileLoadFailed {
                VStack(spacing: 24) {
                    Text(error ?? "Couldn't load your saved profile.").multilineTextAlignment(.center)
                    Button(session.isSignedIn ? "Retry" : "Sign in again") {
                        if session.isSignedIn { Task { await loadSavedProfile() } }
                        else { profileLoadFailed = false; move(to: .phone) }
                    }
                    Button("Close") { dismiss() }
                }
                .padding(24)
                .foregroundStyle(.black)
            } else if step == .welcome {
                WelcomeView { move(to: .birthday) }
            } else {
                form
            }
        }
        .tint(.black)
        .preferredColorScheme(step == .welcome ? .dark : .light)
        .interactiveDismissDisabled()
        .task {
            if session.isSignedIn { await loadSavedProfile() }
        }
        .onChange(of: session.profileOwner) {
            if profileOwner != nil && profileOwner != session.profileOwner {
                profileOwner = nil
                name = ""
                photo = nil
                move(to: .phone)
            }
        }
        .alert("Couldn't save your profile", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(error ?? "Please try again.")
        }
        .sheet(isPresented: $showsCountryPicker, onDismiss: {
            if step == .phone { focusedStep = .phone }
        }) {
            PhoneCountryPicker(selection: $phoneCountry)
        }
        .onChange(of: phoneCountry) {
            phone = phoneCountry.formatted(phone)
            code = ""
            session.clearPhoneChallenge()
            error = nil
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    page(.birthday, in: geometry.size) {
                        birthdayContent
                    }

                    ForEach([Step.phone, .code, .name], id: \.self) { entryStep in
                        page(entryStep, in: geometry.size) {
                            entryContent(for: entryStep)
                        }
                    }

                    page(.photo, in: geometry.size) {
                        CameraCapture(camera: camera, previewSize: $cameraPreviewSize, isActive: step == .photo)
                    }

                    page(.complete, in: geometry.size) {
                        completionContent
                    }
                }
            }
            .clipped()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if step == .photo {
                    VStack(spacing: 0) {
                        CameraCaptureControls(camera: camera, previewSize: cameraPreviewSize) { image in
                            photo = image
                            move(to: .complete)
                        }
                        Button("Skip photo") {
                            photo = nil
                            move(to: .complete)
                        }
                        .frame(minHeight: 44).padding(.bottom, 12)
                    }
                } else {
                    footer(for: step)
                }
            }
            .transaction { $0.animation = nil }
        }
        .foregroundStyle(.black)
        .task {
            focusedStep = [.phone, .code, .name].contains(step) ? step : nil
        }
    }

    private func page<Content: View>(_ page: Step, in size: CGSize,
                                     @ViewBuilder content: () -> Content) -> some View {
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1

        return content()
            .frame(width: size.width, height: size.height, alignment: .top)
            .transaction { $0.animation = nil }
            .offset(x: CGFloat(page.rawValue - step.rawValue) * size.width * direction)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: step)
            .allowsHitTesting(step == page)
            .accessibilityHidden(step != page)
    }

    private var header: some View {
        ZStack {
            HStack {
                backButton
                Spacer()
            }

            if step != .complete {
                ProgressView(value: Double(step.rawValue), total: 5)
                    .progressViewStyle(OnboardingProgressStyle())
                    .accessibilityLabel("Onboarding progress")
                    .accessibilityValue("Step \(step.rawValue) of 5")
                    .accessibilityIdentifier("onboardingProgress")
            }
        }
        .frame(minHeight: 60)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private var backButton: some View {
        Button {
            if step == .name && session.pendingPhoneNumber == nil {
                move(to: .phone)
            } else {
                move(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
            }
        } label: {
            Image("OnboardingBack")
                .resizable().scaledToFit()
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: 16, height: 16)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("onboardingBack")
        .disabled(session.isAuthenticating || profileStore.isSaving)
    }

    private var birthdayContent: some View {
        birthdayFields
            .padding(.top, 32)
            .padding(.bottom, 24)
    }

    private var birthdayFields: some View {
        VStack(spacing: 16) {
            Text(Step.birthday.title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            BirthdayPicker(selection: $birthday)
                .frame(maxWidth: 320)
                .frame(height: 168)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.3),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityIdentifier("birthdayPicker")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var isOldEnough: Bool {
        let calendar = Calendar.current
        let age = calendar.dateComponents(
            [.year],
            from: calendar.startOfDay(for: birthday),
            to: calendar.startOfDay(for: .now)
        ).year ?? 0
        return age >= 21
    }

    private func entryContent(for entryStep: Step) -> some View {
        entryFields(for: entryStep)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .allowsHitTesting(!session.isAuthenticating)
    }

    private func entryFields(for entryStep: Step) -> some View {
        VStack(spacing: 32) {
            Text(entryStep.title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Stable pages keep the fields mounted while focus moves between them.
            switch entryStep {
            case .phone: phoneInput
            case .code: verificationFields
            case .name: nameInput
            default: EmptyView()
            }

        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private var completionContent: some View {
        VStack(spacing: 32) {
            Text(Step.complete.title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 20) {
                avatar
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 32)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private var nameInput: some View {
        TextField("Name", text: $name, prompt: Text("(e.g. John)").foregroundStyle(Color(white: 0.77)))
            .textFieldStyle(.plain)
            .font(.system(.largeTitle, design: .rounded, weight: .medium))
            .multilineTextAlignment(.center)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.continue)
            .focused($focusedStep, equals: .name)
            .onSubmit { if canContinue { advance() } }
            .frame(minHeight: 76)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityLabel("Name")
            .accessibilityIdentifier("onboardingField")
    }

    private var verificationFields: some View {
        VStack(spacing: 12) {
            Text(session.pendingPhoneNumber ?? "")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

            codeInput

            HStack {
                Button("Change number") {
                    code = ""
                    move(to: .phone)
                }
                .accessibilityIdentifier("changePhoneNumberButton")

                Spacer()

                if step == .code {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = max(0, Int(ceil((session.resendAvailableAt ?? .distantPast).timeIntervalSince(timeline.date))))
                        Button(remaining > 0 ? "Resend in \(remaining)s" : "Resend code") {
                            if let number = session.pendingPhoneNumber { requestCode(to: number) }
                        }
                        .disabled(remaining > 0 || session.isBusy)
                        .accessibilityIdentifier("resendCodeButton")
                    }
                }
            }
            .font(.system(.callout, design: .rounded, weight: .medium))
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
    }

    private var codeInput: some View {
        let digits = Array(code)

        return ZStack {
            TextField("", text: Binding(get: { code }, set: { if !session.isAuthenticating { code = $0 } }))
                .textFieldStyle(.plain)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 64)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedStep, equals: .code)
                .onChange(of: code) {
                    let normalized = String(code.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if code != normalized { code = normalized }
                    error = nil
                }
                .accessibilityLabel("Verification code")
                .accessibilityIdentifier("onboardingField")

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { slot in
                    Text(slot < digits.count ? String(digits[slot]) : "")
                        .font(.system(.title, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color(white: 0.96), in: .rect(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.black.opacity(focusedStep == .code && slot == digits.count ? 0.22 : 0), lineWidth: 1)
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 64)
        .contentShape(.rect)
    }

    private var phoneInput: some View {
        HStack(spacing: 12) {
            Button {
                focusedStep = nil
                showsCountryPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text("+" + phoneCountry.dialingCode)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Image("OnboardingBack")
                        .resizable().scaledToFit()
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(-90))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Color(white: 0.96), in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Country code")
            .accessibilityValue("\(phoneCountry.name), +\(phoneCountry.dialingCode)")
            .accessibilityHint("Choose a country.")
            .accessibilityIdentifier("countryCodeButton")

            TextField("Phone number", text: Binding(get: { phone }, set: { if !session.isAuthenticating { phone = $0 } }),
                      prompt: Text(phoneCountry.placeholder).foregroundStyle(Color(white: 0.77)))
                .textFieldStyle(.plain)
                .font(.system(.title2, design: .rounded, weight: .medium))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled()
                .focused($focusedStep, equals: .phone)
                .onChange(of: phone) {
                    let formatted = phoneCountry.formatted(phone)
                    if phone != formatted { phone = formatted }
                    code = ""
                    session.clearPhoneChallenge()
                    error = nil
                }
                .frame(minHeight: 76)
                .accessibilityLabel("Phone number")
                .accessibilityIdentifier("onboardingField")
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var avatar: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
            } else {
                Image("OnboardingCamera")
                    .resizable().scaledToFit()
                    .padding(52)
                    .background(Color(white: 0.96))
            }
        }
        .frame(width: 168, height: 168)
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityLabel(photo == nil ? "Take a profile photo" : "Profile photo")
    }

    private func footer(for page: Step) -> some View {
        VStack(spacing: 16) {
            if page == .birthday || [.phone, .code, .name].contains(page) {
                Text(page == .birthday ? "You must be 21 or older to continue." : error ??
                     (page == .name && !name.isEmpty && !PartyProfile.isValidName(name)
                      ? "Use 1–80 characters, without control characters." : page.detail))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: page == .phone || page == .code)
                    .accessibilityIdentifier(page == .birthday ? "birthdayAgeRequirement" : "onboardingInstruction")
            }

            Button(action: advance) {
                ZStack {
                    Text(page == .complete ? "Get started" : "Continue")
                        .opacity(session.isAuthenticating || profileStore.isSaving ? 0 : 1)
                    if session.isAuthenticating || profileStore.isSaving { ProgressView().tint(.white) }
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(canContinue(for: page) ? .black : Color(white: 0.72), in: .capsule)
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(!canContinue(for: page))
            .accessibilityIdentifier("onboardingContinue")
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(.white)
    }

    private var isPhoneNumberValid: Bool {
        phoneCountry.isPossibleNumber(phone)
    }

    private var canContinue: Bool {
        canContinue(for: step)
    }

    private func canContinue(for page: Step) -> Bool {
        guard !session.isBusy, !profileStore.isSaving, !isLoadingProfile else { return false }
        return switch page {
        case .birthday: isOldEnough
        case .phone: isPhoneNumberValid
        case .code: code.count == 6 && session.pendingPhoneNumber != nil
        case .name: PartyProfile.isValidName(name)
        default: true
        }
    }

    private func move(to next: Step) {
        error = nil
        focusedStep = [.phone, .code, .name].contains(next) ? next : nil
        step = next
    }

    private func advance() {
        switch step {
        case .welcome: break
        case .birthday:
            guard isOldEnough else { return }
            move(to: .phone)
        case .phone:
            guard isPhoneNumberValid else {
                error = "Enter a phone number for \(phoneCountry.name)."
                return
            }
            guard let digits = phoneCountry.nationalDigits(in: phone) else { return }
            let number = "+\(phoneCountry.dialingCode)\(digits)"
            if session.pendingPhoneNumber == number {
                move(to: .code)
            } else {
                requestCode(to: number)
            }
        case .code:
            guard canContinue else { return }
            error = nil
            Task {
                do {
                    try await session.verifyCode(code)
                    code = ""
                    await loadSavedProfile()
                } catch {
                    self.error = error.localizedDescription
                    focusedStep = .code
                }
            }
        case .name:
            guard PartyProfile.isValidName(name) else {
                error = "Use a name between 1 and 80 characters, without control characters."
                return
            }
            move(to: .photo)
        case .photo: break
        case .complete:
            guard canContinue else { return }
            Task {
                do {
                    guard profileOwner != nil, profileOwner == session.profileOwner,
                          profileOwner == profileStore.owner else { throw ProfileStore.SaveError.signedOut }
                    let data: Data?
                    if let photo {
                        guard let jpeg = photo.jpegData(compressionQuality: 0.85) else {
                            throw ProfilePhoto.PreparationError.invalidImage
                        }
                        data = jpeg
                    } else { data = nil }
                    try await profileStore.save(name: name, photoData: data) { name, picture in
                        try await session.saveProfile(name: name, photoData: picture)
                    }
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                    showsSaveError = true
                }
            }
        }
    }

    private func loadSavedProfile() async {
        guard !isLoadingProfile else { return }
        isLoadingProfile = true
        profileLoadFailed = false
        defer { isLoadingProfile = false }
        profileOwner = session.profileOwner
        profileStore.load(owner: profileOwner)
        if profileStore.remoteState == .unknown {
            await profileStore.refresh { try await session.loadProfile() }
        }
        guard profileStore.remoteState != .unknown, session.isSignedIn,
              profileOwner == session.profileOwner else {
            error = session.message ?? profileStore.message ?? "Couldn't load your saved profile. Please retry."
            profileLoadFailed = true
            return
        }
        if profileStore.remoteState == .saved {
            dismiss()
        } else {
            name = profileStore.profile.name
            photo = profileStore.profile.photoData.flatMap { UIImage(data: $0) }
            move(to: .name)
        }
    }

    private func requestCode(to number: String) {
        error = nil
        Task {
            do {
                try await session.sendCode(to: number)
                code = ""
                move(to: .code)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct OnboardingProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let currentStep = Int(((configuration.fractionCompleted ?? 0) * 5).rounded())

        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { marker in
                Capsule()
                    .fill(marker <= currentStep ? .black : Color(white: 0.55))
                    .frame(width: marker == currentStep ? 28 : 16, height: 5)
            }
        }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(AuthSession())
        .environment(ProfileStore())
}
