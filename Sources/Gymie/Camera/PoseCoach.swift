import AVFoundation
import CoreImage
import GymieCore
import Observation

/// Camera -> pose server -> rep events. Shows a mirrored (optionally blurred) preview with
/// the skeleton drawn on top. Keeps one frame in flight, like the extension's pose client.
@MainActor @Observable
final class PoseCoach {
    enum Status: Equatable {
        case idle, starting, live
        case offline(String)
        case cameraDenied
    }

    var status: Status = .idle
    var preview: CGImage?
    var landmarks: [[Double]]?
    var connections: [[Int]] = DEFAULT_CONNECTIONS
    var latencyMs: Double?
    var blur = true {
        didSet { pipeline.blur.set(blur) }
    }
    /// Frames for the current exercise only.
    var onFrame: ((PoseFrame) -> Void)?
    /// The engine's exercise catalog, sent when a session connects.
    var onCatalog: (([Exercise]) -> Void)?
    /// What's happening while `status == .starting`.
    var detail: String?

    private(set) var exercise: String?
    private let camera = CameraCapture()
    private let pipeline = FramePipeline()
    private var socket: URLSessionWebSocketTask?
    private var readyTimeout: Task<Void, Never>?
    private var ready = false

    /// `prepare` makes sure the local pose engine is running; it returns an error message or nil.
    func start(serverURL: String, exercise: String?, blur: Bool, prepare: () async -> String?) async {
        guard status != .live, status != .starting else { return }
        self.blur = blur
        self.exercise = exercise
        status = .starting
        detail = "Starting the camera…"
        guard await CameraCapture.authorize() else { status = .cameraDenied; return }
        do {
            try camera.start { [pipeline] buffer in pipeline.handle(buffer) }
        } catch {
            status = .offline("Camera unavailable: \(error.localizedDescription)")
            return
        }
        pipeline.onPreview = { [weak self] image in
            Task { @MainActor in self?.preview = image }
        }
        detail = "Starting the pose engine…"
        if let error = await prepare() {
            fail(error)
            return
        }
        guard status == .starting else { return } // stopped while waiting
        detail = "Connecting…"
        connect(serverURL)
    }

    func setExercise(_ key: String) {
        exercise = key
        landmarks = nil
        send(json: ["type": "config", "exercise": key])
    }

    func stop() {
        readyTimeout?.cancel()
        camera.stop()
        pipeline.onPreview = nil
        pipeline.send = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        ready = false
        if case .live = status { status = .idle }
        if status == .starting { status = .idle }
    }

    // MARK: Socket

    private func connect(_ serverURL: String) {
        guard isLocalPoseURL(serverURL), let url = URL(string: serverURL) else {
            status = .offline("Only a pose server on this Mac (ws://127.0.0.1:…) can be used.")
            return
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        socket = task
        task.resume()
        receive(task)
        // Hosted servers can take a few seconds to wake up.
        readyTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled, !self.ready else { return }
            self.fail("The pose engine didn't answer. See Settings → Break.")
        }
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let message):
                    let data: Data? = switch message {
                    case .string(let text): Data(text.utf8)
                    case .data(let data): data
                    @unknown default: nil
                    }
                    if let data, let msg = PoseMessage.decode(data) { self.handle(msg) }
                    self.receive(task)
                case .failure(let error):
                    self.fail(self.ready ? "Lost the pose engine: \(error.localizedDescription)"
                                         : "Couldn't reach the pose engine: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ msg: PoseMessage) {
        switch msg {
        case .ready(let exercises, let connections):
            ready = true
            detail = nil
            onCatalog?(exercises)
            readyTimeout?.cancel()
            if !connections.isEmpty { self.connections = connections }
            if let exercise { send(json: ["type": "config", "exercise": exercise]) }
            pipeline.send = { [weak self] jpeg in
                Task { @MainActor in self?.socket?.send(.data(jpeg)) { _ in } }
            }
            status = .live
        case .frame(let frame):
            pipeline.frameAnswered()
            latencyMs = frame.latency_ms
            landmarks = frame.landmarks
            if frame.exercise == exercise { onFrame?(frame) }
        case .error(let text):
            pipeline.frameAnswered()
            NSLog("Gymie pose server: \(text)")
        case .config, .other:
            break
        }
    }

    private func send(json: [String: Any]) {
        guard let socket, ready, let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func fail(_ reason: String) {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pipeline.send = nil
        ready = false
        landmarks = nil
        status = .offline(reason)
    }
}

/// Thread-safe value box.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ v: Value) { lock.withLock { value = v } }
    func update<T>(_ f: (inout Value) -> T) -> T { lock.withLock { f(&value) } }
}

/// Runs on the camera queue: makes the preview image and the JPEG for the server.
final class FramePipeline: @unchecked Sendable {
    let blur = Locked(true)
    private let inFlight = Locked<Date?>(nil)
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let callbacks = Locked<(preview: ((CGImage) -> Void)?, send: ((Data) -> Void)?)>((nil, nil))

    var onPreview: ((CGImage) -> Void)? {
        get { callbacks.get().preview }
        set { callbacks.update { $0.preview = newValue } }
    }
    var send: ((Data) -> Void)? {
        get { callbacks.get().send }
        set { callbacks.update { $0.send = newValue } }
    }

    func frameAnswered() { inFlight.set(nil) }

    func handle(_ buffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: buffer)
        let cb = callbacks.get()
        if let send = cb.send, claimSlot(),
           let jpeg = ci.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]) {
            send(jpeg)
        }
        guard let preview = cb.preview else { return }
        var shown = image.oriented(.upMirrored)
        if blur.get() {
            shown = shown.clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: image.extent)
        }
        if let cg = ci.createCGImage(shown, from: image.extent) { preview(cg) }
    }

    /// One frame in flight; a lost answer frees the slot after 3 s.
    private func claimSlot() -> Bool {
        inFlight.update { since in
            if let since, Date().timeIntervalSince(since) < 3 { return false }
            since = Date()
            return true
        }
    }
}

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "gymie.camera")
    private var handler: ((CVPixelBuffer) -> Void)?
    private var configured = false

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    struct NoCamera: LocalizedError { var errorDescription: String? { "No camera found" } }

    func start(_ handler: @escaping (CVPixelBuffer) -> Void) throws {
        queue.sync { self.handler = handler }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video) else { throw NoCamera() }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            configured = true
        }
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler?(buffer)
    }
}
