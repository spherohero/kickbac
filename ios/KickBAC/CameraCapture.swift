import AVFoundation
import Observation
import SwiftUI

struct CameraCapture: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    let camera: ProfileCamera
    @Binding var previewSize: CGSize
    var isActive = true
    @State private var previewOwner = UUID()

    var body: some View {
        VStack(spacing: 20) {
            Text("Ready for a photo?")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            ZStack {
                Color(white: colorScheme == .dark ? 0.1 : 0.95)

                if camera.previewSource != nil || camera.photo != nil {
                    CameraPreview(source: camera.previewSource, image: camera.photo)
                } else {
                    cameraPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 36))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { previewSize = $0 }
            .overlay(alignment: .bottom) {
                if let error = camera.error {
                    Text(error)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
                        .padding(16)
                }
            }
            .overlay {
                if !camera.isReady && camera.photo == nil {
                    Button(action: camera.requestAccess) {
                        Color.clear
                            .contentShape(.rect(cornerRadius: 36))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Allow camera access")
                    .accessibilityHint(camera.needsSettings ? "Opens camera permission settings." : "Starts your camera.")
                    .accessibilityIdentifier("cameraPermissionButton")
                }
            }
            .accessibilityIdentifier("profileCameraPreview")
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .onChange(of: isActive && scenePhase == .active, initial: true) {
            camera.setActive(isActive && scenePhase == .active, owner: previewOwner)
        }
        .onDisappear { camera.setActive(false, owner: previewOwner) }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 16) {
            Image("OnboardingCamera")
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            if camera.needsSettings {
                Text("Allow camera access to take your photo.")
                    .multilineTextAlignment(.center)
            } else if camera.isUnavailable {
                Text("Camera unavailable")
                    .font(.headline)
            } else {
                ProgressView("Starting camera")
            }
        }
        .padding(24)
    }
}

struct CameraCaptureControls: View {
    @Environment(\.colorScheme) private var colorScheme
    let camera: ProfileCamera
    let previewSize: CGSize
    let onContinue: (UIImage) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if camera.photo != nil {
                Button("Retake") {
                    Task { await camera.retake() }
                }
                .font(.system(.headline, design: .rounded))
                .frame(minWidth: 100, minHeight: 54)
                .overlay { Capsule().strokeBorder(Color(white: 0.85)) }
                .accessibilityIdentifier("retakeProfilePhoto")
            }

            Button {
                if let photo = camera.photo {
                    onContinue(CameraFraming.crop(photo, viewport: previewSize))
                } else if camera.isReady {
                    Task { await camera.capture() }
                } else {
                    camera.requestAccess()
                }
            } label: {
                Text(camera.photo == nil ? "Take photo" : "Use photo")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .background(canTakePhoto ? (colorScheme == .dark ? .white : .black) : Color(white: colorScheme == .dark ? 0.45 : 0.72), in: .capsule)
            }
            .disabled(camera.isCapturing)
            .accessibilityHint(camera.isReady || camera.photo != nil ? "" : "Allow camera access to take your photo.")
            .accessibilityIdentifier("onboardingContinue")
        }
        .buttonStyle(.plain)
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color("SplashBackground") : .white)
    }

    private var canTakePhoto: Bool {
        camera.photo != nil || (camera.isReady && !camera.isCapturing)
    }
}

@MainActor @Observable
final class ProfileCamera {
    private let session = ProfileCameraSession()
    private var activity = CameraActivity()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private(set) var previewSource: CameraPreviewSource?
    private(set) var photo: UIImage?
    private(set) var isReady = false
    private(set) var isCapturing = false
    private(set) var needsSettings = false
    private(set) var isUnavailable = false
    private(set) var error: String?

    func setActive(_ active: Bool, owner: UUID) {
        if active {
            let revision = activity.activate(owner: owner)
            if photo == nil {
                Task { await start(revision: revision) }
            } else {
                Task { await session.stop(revision: revision) }
            }
        } else if let revision = activity.deactivate(owner: owner) {
            isReady = false
            Task { await session.stop(revision: revision) }
        }
    }

    func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            Task { await start() }
        }
    }

    func start() async {
        guard let revision = activity.nextRequest() else { return }
        await start(revision: revision)
    }

    private func start(revision: Int) async {
        guard activity.isCurrent(revision), activity.owner != nil else { return }
        isReady = false
        isUnavailable = false
        error = nil
        var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard activity.isCurrent(revision), activity.owner != nil else { return }
        needsSettings = !authorized
        guard authorized else {
            previewSource = nil
            return
        }
        do {
            guard let source = try await session.start(revision: revision), activity.isCurrent(revision) else { return }
            previewSource = source
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: source.device, previewLayer: nil)
            isReady = true
        } catch CameraFailure.unavailable {
            guard activity.isCurrent(revision) else { return }
            previewSource = nil
            isUnavailable = true
        } catch {
            guard activity.isCurrent(revision) else { return }
            previewSource = nil
            self.error = "The camera couldn't start. Go back and try again."
            isUnavailable = true
        }
    }

    func stop() async {
        guard let revision = activity.nextRequest() else { return }
        isReady = false
        await session.stop(revision: revision)
    }

    func capture() async {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        let revision = activity.revision
        error = nil
        defer { isCapturing = false }
        do {
            let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
            let data = try await session.capture(rotation: angle)
            guard activity.isCurrent(revision) else { return }
            guard let image = UIImage(data: data) else { throw CameraFailure.noPhoto }
            photo = image
            await stop()
        } catch {
            guard activity.isCurrent(revision) else { return }
            self.error = "Couldn't take your photo. Try again."
        }
    }

    func retake() async {
        photo = nil
        await start()
    }
}

// Only the preview connection crosses actors; session operations stay in the actor.
nonisolated final class CameraPreviewSource: @unchecked Sendable {
    let session: AVCaptureSession
    let device: AVCaptureDevice

    init(session: AVCaptureSession, device: AVCaptureDevice) {
        self.session = session
        self.device = device
    }
}

private actor ProfileCameraSession {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewSource: CameraPreviewSource?
    private var captureDelegate: ProfilePhotoDelegate?
    private var requestOrder = CameraRequestOrder()

    func start(revision: Int) throws -> CameraPreviewSource? {
        guard requestOrder.accept(revision) else { return nil }
        let source: CameraPreviewSource
        if let previewSource {
            source = previewSource
        } else {
            source = try configure()
            previewSource = source
        }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning, !session.isInterrupted else { throw CameraFailure.unavailable }
        return source
    }

    private func configure() throws -> CameraPreviewSource {
        let camera: AVCaptureDevice?
        if ProcessInfo.processInfo.isiOSAppOnMac {
            camera = AVCaptureDevice.default(for: .video)
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        guard let device = camera else { throw CameraFailure.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else {
            throw CameraFailure.unavailable
        }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraFailure.unavailable }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return CameraPreviewSource(session: session, device: device)
    }

    func stop(revision: Int) {
        guard requestOrder.accept(revision) else { return }
        if session.isRunning { session.stopRunning() }
    }

    func capture(rotation: CGFloat) async throws -> Data {
        guard session.isRunning, captureDelegate == nil,
              let connection = output.connection(with: .video), connection.isActive else { throw CameraFailure.unavailable }
        if connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
        defer { captureDelegate = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ProfilePhotoDelegate(continuation: continuation)
            captureDelegate = delegate
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

private nonisolated enum CameraFailure: Error {
    case unavailable, noPhoto
}

private nonisolated final class ProfilePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Data, any Error>
    private var result: Result<Data, any Error> = .failure(CameraFailure.noPhoto)

    init(continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        continuation.resume(with: error.map { .failure($0) } ?? result)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let source: CameraPreviewSource?
    let image: UIImage?

    func makeUIView(context: Context) -> CameraPreviewView {
        CameraPreviewView(source: source)
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.bind(source)
        view.photoView.image = image
        view.photoView.isHidden = image == nil
        view.accessibilityLabel = image == nil ? "Front camera preview" : "Your photo"
        view.accessibilityHint = "Center your face in the clear area."
    }

    static func dismantleUIView(_ view: CameraPreviewView, coordinator: ()) {
        view.disconnect()
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    let photoView = UIImageView()
    private let blurView = UIVisualEffectView(effect: nil)
    private let blurMaskView = UIImageView()
    private let dimmingLayer = CAShapeLayer()
    private var blurAnimator: UIViewPropertyAnimator?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var boundSource: CameraPreviewSource?

    init(source: CameraPreviewSource?) {
        super.init(frame: .zero)
        clipsToBounds = true
        isAccessibilityElement = true
        previewLayer.videoGravity = .resizeAspectFill
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        addSubview(photoView)
        addSubview(blurView)
        blurView.isUserInteractionEnabled = false
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.12).cgColor
        layer.addSublayer(dimmingLayer)
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [blurView] in
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        }
        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = 0.08
        blurAnimator = animator
        bind(source)
    }

    func bind(_ source: CameraPreviewSource?) {
        guard boundSource !== source else { return }
        rotationObservation = nil
        rotationCoordinator = nil
        boundSource = source
        previewLayer.session = source?.session
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        guard let source else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: source.device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor [weak self] in
                guard let connection = self?.previewLayer.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func disconnect() {
        blurAnimator?.stopAnimation(true)
        blurAnimator = nil
        rotationObservation = nil
        rotationCoordinator = nil
        boundSource = nil
        previewLayer.session = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        photoView.frame = bounds
        guard !bounds.isEmpty, blurView.frame != bounds else { return }
        blurView.frame = bounds
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 36)
        let face = CameraFraming.faceRect(in: bounds.size)
        path.append(UIBezierPath(roundedRect: face, cornerRadius: face.width * 0.12))
        path.usesEvenOddFillRule = true
        // A bitmap mask preserves the transparent hole when UIKit copies the effect's mask.
        blurMaskView.image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            UIColor.black.setFill()
            path.fill()
        }
        blurMaskView.frame = blurView.bounds
        blurView.mask = blurMaskView
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimmingLayer.frame = bounds
        dimmingLayer.path = path.cgPath
        CATransaction.commit()
    }
}

private enum CameraFraming {
    static func faceRect(in viewport: CGSize) -> CGRect {
        let side = min(viewport.width, viewport.height) * 0.82
        return CGRect(x: (viewport.width - side) / 2,
                      y: viewport.height * 0.44 - side / 2,
                      width: side, height: side)
    }

    static func sourceRect(imageSize: CGSize, viewport: CGSize) -> CGRect {
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let face = faceRect(in: viewport)
        let offset = CGPoint(x: (viewport.width - imageSize.width * scale) / 2,
                             y: (viewport.height - imageSize.height * scale) / 2)
        return CGRect(x: (face.minX - offset.x) / scale,
                      y: (face.minY - offset.y) / scale,
                      width: face.width / scale, height: face.height / scale)
    }

    static func crop(_ image: UIImage, viewport: CGSize) -> UIImage {
        guard viewport.width > 0, viewport.height > 0, image.size.width > 0, image.size.height > 0 else { return image }
        let crop = sourceRect(imageSize: image.size, viewport: viewport)
        let side = min(crop.width * image.scale, 1024)
        let scale = side / crop.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
    }
}
