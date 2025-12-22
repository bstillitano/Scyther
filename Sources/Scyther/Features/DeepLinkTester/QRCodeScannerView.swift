//
//  QRCodeScannerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI
import AVFoundation

/// A SwiftUI view that scans QR codes using the device camera.
///
/// This view presents a camera preview with a QR code scanning overlay.
/// When a valid QR code containing a URL is detected, it calls the completion handler.
struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = QRCodeScannerViewModel()

    /// Called when a URL is successfully scanned.
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.permissionGranted {
                    CameraPreviewView(session: viewModel.session)
                        .ignoresSafeArea()

                    // Scanning overlay
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 250, height: 250)
                            .overlay {
                                if viewModel.isScanning {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                }
                            }

                        Text("Point camera at QR code")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.top, 20)

                        Spacer()
                    }
                } else if viewModel.permissionDenied {
                    permissionDeniedView
                } else {
                    ProgressView("Requesting camera access...")
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.checkPermissions()
            }
            .onDisappear {
                viewModel.stopScanning()
            }
            .onChange(of: viewModel.scannedURL) { newValue in
                if let url = newValue {
                    onScan(url)
                }
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.headline)

            Text("Please enable camera access in Settings to scan QR codes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// View model for the QR code scanner.
@MainActor
class QRCodeScannerViewModel: NSObject, ObservableObject {
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var isScanning = false
    @Published var scannedURL: String?

    let session = AVCaptureSession()
    private var hasScanned = false

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            startScanning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.permissionGranted = true
                        self?.startScanning()
                    } else {
                        self?.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    func startScanning() {
        guard !session.isRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureSession()
        }
    }

    func stopScanning() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return
        }

        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        session.commitConfiguration()
        session.startRunning()

        Task { @MainActor in
            self.isScanning = true
        }
    }
}

extension QRCodeScannerViewModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else {
            return
        }

        // Validate it looks like a URL
        guard URL(string: stringValue) != nil else { return }

        Task { @MainActor in
            // Prevent multiple scans
            guard !self.hasScanned else { return }
            self.hasScanned = true

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            self.scannedURL = stringValue
            self.stopScanning()
        }
    }
}

/// A UIViewRepresentable wrapper for the camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.session = session
    }
}

/// A UIView subclass that displays the camera preview.
class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            previewLayer.session = session
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

#Preview {
    QRCodeScannerView { url in
        print("Scanned: \(url)")
    }
}
#endif
