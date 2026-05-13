import AppKit
import AVFoundation
import Observation
import SwiftUI

/// Shared camera session for the notch mirror (used from `ClockModule`).
@MainActor
@Observable
final class NotchMirrorCapture {
    enum Phase: Equatable {
        case idle
        case unauthorized
        case noCamera
        case configuring
        case running
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var session: AVCaptureSession?

    private let sessionQueue = DispatchQueue(label: "com.echo.notch.mirror.session")

    func startIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            phase = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.phase = .unauthorized
                    }
                }
            }
            return
        case .denied, .restricted:
            phase = .unauthorized
            return
        @unknown default:
            phase = .unauthorized
            return
        }
        configureAndStart()
    }

    func stop() {
        guard let session else {
            phase = .idle
            return
        }
        let s = session
        self.session = nil
        phase = .idle
        sessionQueue.async {
            if s.isRunning {
                s.stopRunning()
            }
            s.beginConfiguration()
            for input in s.inputs {
                s.removeInput(input)
            }
            s.commitConfiguration()
        }
    }

    private func configureAndStart() {
        guard session == nil else { return }

        guard let device = AVCaptureDevice.default(for: .video) else {
            phase = .noCamera
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                phase = .failed("Cannot open camera")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            phase = .failed(error.localizedDescription)
            return
        }

        session.commitConfiguration()
        self.session = session
        phase = .running

        sessionQueue.async {
            session.startRunning()
        }
    }
}

// MARK: - Preview layer

struct NotchMirrorCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NotchCameraPreviewHost {
        let v = NotchCameraPreviewHost()
        v.attach(session: session)
        return v
    }

    func updateNSView(_ nsView: NotchCameraPreviewHost, context: Context) {
        nsView.attach(session: session)
    }
}

final class NotchCameraPreviewHost: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { nil }

    func attach(session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
