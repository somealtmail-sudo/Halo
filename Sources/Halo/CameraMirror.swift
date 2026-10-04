import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Only the visible Mirror tab owns a live session. No recording outputs are added.
@MainActor
final class CameraMirror: ObservableObject {
    enum State: Equatable {
        case idle, permission, starting, running, denied, unavailable, failed
    }

    @Published private(set) var state: State = .idle
    private let capture = MirrorCapture()
    private var active = false
    private var generation = 0
    private var requestingPermission = false
    private var observers: [NSObjectProtocol] = []
    var session: AVCaptureSession { capture.session }

    init() {
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: capture.session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }
                    self.generation += 1
                    self.capture.stop()
                    self.state = .failed
                }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        capture.stop()
    }

    func reconcile(active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active { start() }
        else {
            generation += 1
            capture.stop()
            state = .idle
        }
    }

    func enable() {
        guard active, !requestingPermission else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { start(); return }
        requestingPermission = true
        state = .starting
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.requestingPermission = false
                if self.active { self.start() }
            }
        }
    }

    private func start() {
        guard active else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: state = requestingPermission ? .starting : .permission; return
        case .denied, .restricted: state = .denied; return
        case .authorized: break
        @unknown default: state = .denied; return
        }
        generation += 1
        let request = generation
        state = .starting
        capture.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == request else { return }
                self.state = result
            }
        }
    }

    func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Session configuration and blocking start/stop operations stay off the UI thread.
private final class MirrorCapture {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.kevin.halo.camera", qos: .userInitiated)

    func start(completion: @escaping (CameraMirror.State) -> Void) {
        queue.async { [self] in
            if session.isRunning { completion(.running); return }
            guard let device = AVCaptureDevice.default(for: .video) else { completion(.unavailable); return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                for old in session.inputs { session.removeInput(old) }
                if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(.failed)
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
                session.startRunning()
                completion(session.isRunning ? .running : .failed)
            } catch { completion(.failed) }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
    }
}

struct CameraMirrorView: View {
    @ObservedObject var camera: CameraMirror

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session, running: camera.state == .running)
                .opacity(camera.state == .running ? 1 : 0)
                .accessibilityLabel("Live mirrored camera view")
            if camera.state != .running {
                VStack(spacing: 8) {
                    Image(systemName: "camera").font(.system(size: 22)).foregroundStyle(haloSecondary)
                    Text(message).font(.system(size: 11)).multilineTextAlignment(.center)
                    switch camera.state {
                    case .permission:
                        Button("Enable Camera") { camera.enable() }
                    case .denied:
                        HStack {
                            Button("Camera Settings") { camera.openCameraSettings() }
                            Button("Retry") { camera.enable() }
                        }
                    case .unavailable, .failed:
                        Button("Retry") { camera.enable() }
                    case .starting: ProgressView().controlSize(.small)
                    default: EmptyView()
                    }
                }
                .font(.system(size: 11)).padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 4)
    }

    private var message: String {
        switch camera.state {
        case .idle: "Camera off"
        case .permission: "See yourself in the notch."
        case .starting: "Starting camera…"
        case .denied: "Allow Halo camera access in System Settings."
        case .unavailable: "No camera connected."
        case .failed: "Camera unavailable. Try again."
        case .running: ""
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let running: Bool

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.preview.session = session
        return view
    }

    func updateNSView(_ view: MirrorPreviewView, context: Context) {
        if running, let connection = view.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    static func dismantleNSView(_ view: MirrorPreviewView, coordinator: ()) {
        view.preview.session = nil
    }
}

private final class MirrorPreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}
