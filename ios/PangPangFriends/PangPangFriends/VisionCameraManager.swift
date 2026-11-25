import AVFoundation
import SwiftUI
import Vision

/// On-device Apple Vision 1~2P body pose tracker + AVCaptureSession front camera.
/// Uses iOS 17+ `AVCaptureDevice.RotationCoordinator` so BOTH the camera preview AND
/// Vision pose coordinates stay 100% upright & mirrored in LandscapeLeft AND LandscapeRight!
final class VisionCameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var players: [PlayerPose] = []
    @Published var statusText: String = "카메라 준비 중..."
    @Published var isUsingCamera: Bool = false

    private let sessionQueue = DispatchQueue(label: "pp.camera.session")
    private let visionQueue = DispatchQueue(label: "pp.camera.vision", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    private var cameraDevice: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObs: NSKeyValueObservation?
    private var captureRotationObs: NSKeyValueObservation?

    private var prevHands: [Int: (CGPoint, CGPoint, CGPoint)] = [:]
    private var smoothedHands: [Int: (CGPoint, CGPoint, CGPoint)] = [:]
    private var expectedPlayers: Int = 2
    private var isConfigured = false
    private var viewSize: CGSize = CGSize(width: 852, height: 393)

    // Developer touch/drag test mode state
    private var devPointer = CGPoint(x: 0.5, y: 0.5)
    private var devVelocity: CGFloat = 0

    func updateViewSize(_ size: CGSize) {
        if size.width > 10 && size.height > 10 {
            viewSize = size
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard previewLayer !== layer else { return }
        previewLayer = layer
        sessionQueue.async { [weak self] in
            self?.setupRotationCoordinatorIfPossible(force: true)
        }
    }

    func start(expectedPlayers: Int, devMode: Bool) {
        self.expectedPlayers = expectedPlayers
        self.prevHands.removeAll()
        self.smoothedHands.removeAll()

        if devMode {
            stopCamera()
            DispatchQueue.main.async {
                self.isUsingCamera = false
                self.statusText = "🛠️ 개발자 모드 · 화면을 드래그해 테스트하세요!"
                self.updateDevPlayers()
            }
            return
        }

        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            self.isUsingCamera = false
            self.statusText = "🛠️ 시뮬레이터 마우스·드래그 테스트 모드"
            self.updateDevPlayers()
        }
        #else
        checkPermissionAndStartCamera()
        #endif
    }

    func stopCamera() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func setDevPointer(normalized point: CGPoint) {
        let dx = point.x - devPointer.x
        let dy = point.y - devPointer.y
        devVelocity = hypot(dx, dy)
        devPointer = CGPoint(
            x: max(0.02, min(0.98, point.x)),
            y: max(0.02, min(0.98, point.y))
        )
        updateDevPlayers()
    }

    func tickDevMode() {
        guard !isUsingCamera else { return }
        devVelocity *= 0.78
        updateDevPlayers()
    }

    private func updateDevPlayers() {
        let px = devPointer.x
        let py = devPointer.y
        let t = CACurrentMediaTime()

        if expectedPlayers == 1 {
            players = [
                PlayerPose(
                    id: 0,
                    centerX: 0.5,
                    centerY: 0.62,
                    head: CGPoint(x: 0.5, y: 0.44),
                    leftHand: CGPoint(x: max(0.05, px - 0.05), y: py),
                    rightHand: CGPoint(x: min(0.95, px + 0.05), y: py),
                    handsUp: py < 0.48,
                    motion: devVelocity
                )
            ]
        } else {
            let p1Active = px < 0.55
            players = [
                PlayerPose(
                    id: 0,
                    centerX: 0.28,
                    centerY: 0.62,
                    head: CGPoint(x: 0.28, y: 0.44),
                    leftHand: p1Active ? CGPoint(x: px, y: py) : CGPoint(x: 0.22 + sin(t * 2.5) * 0.04, y: 0.46),
                    rightHand: p1Active ? CGPoint(x: min(0.55, px + 0.07), y: py) : CGPoint(x: 0.35, y: 0.48),
                    handsUp: py < 0.48,
                    motion: devVelocity
                ),
                PlayerPose(
                    id: 1,
                    centerX: 0.72,
                    centerY: 0.66,
                    head: CGPoint(x: 0.72, y: 0.50),
                    leftHand: !p1Active ? CGPoint(x: px, y: py) : CGPoint(x: 0.65, y: 0.48),
                    rightHand: !p1Active ? CGPoint(x: min(0.95, px + 0.07), y: py) : CGPoint(x: 0.78 + cos(t * 2.6) * 0.04, y: 0.46),
                    handsUp: py < 0.48,
                    motion: devVelocity
                )
            ]
        }
    }

    private func checkPermissionAndStartCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRunCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndRunCamera()
                } else {
                    DispatchQueue.main.async {
                        self?.isUsingCamera = false
                        self?.statusText = "카메라 권한 없음 · 터치 테스트 모드"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isUsingCamera = false
                self.statusText = "설정에서 카메라 권한을 허용해 주세요"
            }
        }
    }

    private func configureAndRunCamera() {
        sessionQueue.async {
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720

                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.cameraDevice = device
                }

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }

                self.session.commitConfiguration()
                self.isConfigured = true
            }

            self.setupRotationCoordinatorIfPossible()

            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.isUsingCamera = true
                self.statusText = "카메라 인식 대기 중 · 화면에 전신이 보이게 서 주세요"
            }
        }
    }

    /// Automatically keeps preview layer AND videoOutput capture buffers upright & mirrored
    /// regardless of whether the iPhone is held LandscapeLeft or LandscapeRight!
    private func setupRotationCoordinatorIfPossible(force: Bool = false) {
        guard let device = self.cameraDevice else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !force, self.rotationCoordinator != nil { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: self.previewLayer)
            self.rotationCoordinator = coordinator

            self.applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            self.applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)

            self.previewRotationObs = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                if let angle = change.newValue {
                    DispatchQueue.main.async { self?.applyPreviewRotation(angle) }
                }
            }
            self.captureRotationObs = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
                if let angle = change.newValue {
                    self?.sessionQueue.async { self?.applyCaptureRotation(angle) }
                }
            }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let conn = previewLayer?.connection else { return }
        if conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        guard let conn = videoOutput.connection(with: .video) else { return }
        if conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
    }

    /// Maps normalized [0..1] coordinates from 16:9 camera buffer into the aspect-filled screen coordinates
    /// so glowing hand halos sit accurately on top of the kid's actual hands on wide iPhones!
    private func mapAspectFill(_ pt: CGPoint, bufferWidth: CGFloat, bufferHeight: CGFloat) -> CGPoint {
        guard bufferWidth > 0, bufferHeight > 0, viewSize.width > 0, viewSize.height > 0 else {
            return pt
        }
        let videoAspect = bufferWidth / bufferHeight
        let screenAspect = viewSize.width / viewSize.height
        var x = pt.x
        var y = pt.y

        if screenAspect > videoAspect {
            // Wider screen (e.g., iPhone 19.5:9) -> top/bottom of 16:9 camera frame are cropped
            let scale = screenAspect / videoAspect
            y = (y - 0.5) * scale + 0.5
        } else {
            // Taller screen (e.g., iPad 4:3) -> left/right of 16:9 camera frame are cropped
            let scale = videoAspect / screenAspect
            x = (x - 0.5) * scale + 0.5
        }
        return CGPoint(x: max(0.0, min(1.0, x)), y: max(0.0, min(1.0, y)))
    }
}

extension VisionCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Because `videoOutput` connection is ALREADY rotated upright & mirrored via RotationCoordinator,
        // Vision receives an upright, mirrored image directly (.up)!
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([poseRequest])
            guard let observations = poseRequest.results, !observations.isEmpty else {
                DispatchQueue.main.async {
                    self.players = []
                    if self.isUsingCamera {
                        self.statusText = "인식됨: 0/\(self.expectedPlayers)명 · 카메라 앞으로 서 주세요"
                    }
                }
                return
            }

            var parsed: [PlayerPose] = []
            for obs in observations {
                guard let points = try? obs.recognizedPoints(.all) else { continue }

                func rawPt(_ key: VNHumanBodyPoseObservation.JointName, minConf: Float = 0.18) -> CGPoint? {
                    guard let p = points[key], p.confidence >= minConf else { return nil }
                    // Vision origin is bottom-left -> convert to top-left [0..1] -> adjust for resizeAspectFill
                    let topLeft = CGPoint(x: p.location.x, y: 1.0 - p.location.y)
                    return mapAspectFill(topLeft, bufferWidth: bufW, bufferHeight: bufH)
                }

                // Require at least upper body visibility (neck, nose, or shoulders)
                let neck = rawPt(.neck)
                let nose = rawPt(.nose) ?? neck
                guard let anchor = nose ?? rawPt(.leftShoulder) ?? rawPt(.rightShoulder) else { continue }

                let shL = rawPt(.leftShoulder) ?? CGPoint(x: anchor.x - 0.08, y: anchor.y + 0.12)
                let shR = rawPt(.rightShoulder) ?? CGPoint(x: anchor.x + 0.08, y: anchor.y + 0.12)
                let elL = rawPt(.leftElbow)
                let elR = rawPt(.rightElbow)
                // Because image is mirrored, anatomical left/right still both act as active hands
                let wrL = rawPt(.leftWrist) ?? elL ?? shL
                let wrR = rawPt(.rightWrist) ?? elR ?? shR

                let cx = (shL.x + shR.x) * 0.5
                let sy = (shL.y + shR.y) * 0.5
                let handsUp = wrL.y < sy - 0.02 || wrR.y < sy - 0.02

                parsed.append(PlayerPose(
                    id: 0,
                    centerX: cx,
                    centerY: sy,
                    head: anchor,
                    leftHand: wrL,
                    rightHand: wrR,
                    handsUp: handsUp,
                    motion: 0
                ))
            }

            // Sort left-to-right on screen so P1 = Left (Momo), P2 = Right (Popo)
            parsed.sort { $0.centerX < $1.centerX }

            let limited = Array(parsed.prefix(expectedPlayers)).enumerated().map { idx, item -> PlayerPose in
                // Lightweight smoothing (alpha = 0.65) cuts Vision jitter while staying ultra-responsive
                let alpha: CGFloat = 0.65
                let sL: CGPoint
                let sR: CGPoint
                let sH: CGPoint
                if let sm = self.smoothedHands[idx] {
                    sL = CGPoint(x: sm.0.x + (item.leftHand.x - sm.0.x) * alpha, y: sm.0.y + (item.leftHand.y - sm.0.y) * alpha)
                    sR = CGPoint(x: sm.1.x + (item.rightHand.x - sm.1.x) * alpha, y: sm.1.y + (item.rightHand.y - sm.1.y) * alpha)
                    sH = CGPoint(x: sm.2.x + (item.head.x - sm.2.x) * alpha, y: sm.2.y + (item.head.y - sm.2.y) * alpha)
                } else {
                    sL = item.leftHand
                    sR = item.rightHand
                    sH = item.head
                }
                self.smoothedHands[idx] = (sL, sR, sH)

                var motion: CGFloat = 0
                if let prev = self.prevHands[idx] {
                    motion = hypot(sL.x - prev.0.x, sL.y - prev.0.y)
                        + hypot(sR.x - prev.1.x, sR.y - prev.1.y)
                        + hypot(sH.x - prev.2.x, sH.y - prev.2.y) * 0.6
                }
                self.prevHands[idx] = (sL, sR, sH)

                return PlayerPose(
                    id: idx,
                    centerX: item.centerX,
                    centerY: item.centerY,
                    head: sH,
                    leftHand: sL,
                    rightHand: sR,
                    handsUp: item.handsUp,
                    motion: motion
                )
            }

            DispatchQueue.main.async {
                self.players = limited
                if self.isUsingCamera {
                    self.statusText = "인식됨: \(limited.count)/\(self.expectedPlayers)명 · 실시간 추적 중"
                }
            }
        } catch {
            // Ignore transient Vision errors
        }
    }
}

/// SwiftUI wrapper for live mirrored front camera preview wired directly to RotationCoordinator.
struct CameraPreviewView: UIViewRepresentable {
    let manager: VisionCameraManager

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = manager.session
        view.previewLayer.videoGravity = .resizeAspectFill
        manager.attachPreviewLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        manager.attachPreviewLayer(uiView.previewLayer)
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
