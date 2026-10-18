import SwiftUI
import VisionKit
import Vision

struct DeviceConnectionView: View {
    let session: AuthSession
    let flow: DeviceSessionStore
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var inputError: String?
    @State private var showsConfirmation = false
    @State private var showsScanner = false

    var body: some View {
        NavigationStack {
            Form {
                if !flow.hasActiveSession {
                    Section {
                        TextField("Device link or ID", text: $input, prompt: Text("kb-demo-01"))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("deviceTarget")
                        Button("Find device", action: findDevice)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || flow.isBusy)
                        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                            Button("Scan QR code") { showsScanner = true }
                        }
                    } header: { Text("Breathalyzer") } footer: {
                        Text("Use the device's QR code, official link, or printed ID.")
                    }
                }

                if let target = flow.targetID {
                    Section {
                        LabeledContent("Device", value: target)
                        if let device = flow.device {
                            LabeledContent("Connection", value: device.online ? "Online" : "Offline")
                            if !device.online {
                                Text("The device hasn't sent a recent heartbeat. A test can time out while it's offline.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if flow.hasActiveSession {
                            Text(flow.test?.status == .sampling
                                 ? "Sensor acquisition in progress — breath not validated."
                                 : "Armed for your account. The operator must start the sample separately over USB.")
                            if flow.test?.status == .armed {
                                Button("Cancel test", role: .destructive) {
                                    Task { await flow.cancel { try await session.cancelSession($0) } }
                                }
                            }
                            if flow.message != nil {
                                Button("Reload test status") { flow.retryPolling() }
                            }
                        } else if !session.isSignedIn {
                            Button("Sign in to continue", action: onSignIn).disabled(session.isBusy)
                        } else if flow.device != nil {
                            Button("Arm test") { showsConfirmation = true }
                        }
                        if flow.isBusy { ProgressView("Connecting") }
                    } header: { Text(flow.hasActiveSession ? "Current test" : "Confirm device") }
                }

                if let message = inputError ?? flow.message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                        if !flow.hasActiveSession && flow.targetID != nil {
                            Button("Retry device lookup") { inspect() }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("SplashBackground").ignoresSafeArea())
            .navigationTitle("Connect device").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .disabled(flow.isBusy)
            .confirmationDialog("Start a test on \(flow.targetID ?? "this device")?", isPresented: $showsConfirmation, titleVisibility: .visible) {
                Button("Arm test") { Task { await flow.arm { try await session.armDevice($0) } } }
            } message: {
                Text("This reserves the device for your account for up to 60 seconds. Arming alone does not measure: the operator starts the timed sensor sample separately over USB. Breath is not validated.")
            }
            .sheet(isPresented: $showsScanner) {
                NavigationStack {
                    DeviceQRScanner { code in
                        showsScanner = false
                        input = code
                        findDevice()
                    }
                    .ignoresSafeArea()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsScanner = false } } }
                }
            }
        }
        .font(.system(.body, design: .rounded)).tint(.primary).preferredColorScheme(.dark)
        .task {
            input = flow.targetID ?? ""
            if flow.targetID != nil && !flow.hasActiveSession { inspect() }
        }
    }

    private func findDevice() {
        do {
            guard let baseURL = session.apiBaseURL else { throw AuthSession.SignInError.configuration }
            try flow.select(input, baseURL: baseURL)
            inputError = nil
            inspect()
        } catch { inputError = error.localizedDescription }
    }

    private func inspect() {
        Task {
            await flow.inspect(resolve: { try await session.resolveDevice($0) }, fetch: {
                session.isSignedIn ? try await session.device($0) : nil
            })
        }
    }
}

private struct DeviceQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                recognizesMultipleItems: false, isGuidanceEnabled: true,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) { }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var didRead = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didRead else { return }
            for case .barcode(let barcode) in items {
                if let value = barcode.payloadStringValue {
                    didRead = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
