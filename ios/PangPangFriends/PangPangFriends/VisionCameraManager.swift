import AVFoundation
import SwiftUI
import Vision

/// On-device Apple Vision 1~2P body pose tracker + AVCaptureSession front camera.
/// Uses iOS 17+ `AVCaptureDevice.RotationCoordinator` so BOTH the camera preview AND
/// Vision pose coordinates stay 100% upright & mirrored in LandscapeLeft AND LandscapeRight!
final class VisionCameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var players: [PlayerPose] = []
    @Published var airCursor = AirCursorState()
    @Published var statusText: String = "카메라 준비 중..."
    @Published var isUsingCamera: Bool = false

    private var dominantHandKey: String? = nil
    private var acCandidateKey: String? = nil
    private var acCandidateHold: CGFloat = 0
    private var acLostTimer: CGFloat = 0
    private var acPrevTime: CFTimeInterval = 0

    private let sessionQueue = DispatchQueue(label: "pp.camera.session")
    private let visionQueue = DispatchQueue(label: "pp.camera.vision", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    private var cameraDevice: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObs: NSKeyValueObservation?
    private var captureRotationObs: NSKeyValueObservation?

    // Commercial Zero-Flicker 14-Joint Pose Engine (True One-Euro + Confidence Hysteresis/EMA + 0.45s Occlusion Persistence + Bone Clamping)
    private enum JointKey: Int, CaseIterable {
        case head, neck
        case lShoulder, rShoulder
        case lElbow, rElbow
        case lWrist, rWrist
        case lHip, rHip
        case lKnee, rKnee
        case lAnkle, rAnkle

        var isHand: Bool { self == .lWrist || self == .rWrist }
    }

    private struct OneEuroFilter2D {
        let minCutoff: CGFloat
        let betaNorm: CGFloat
        let dCutoff: CGFloat = 1.0
        var xPrev: CGPoint? = nil
        var dxPrev: CGPoint = .zero

        private func alpha(fc: CGFloat, dt: CGFloat) -> CGFloat {
            let tau = 1.0 / (2.0 * .pi * max(0.001, fc))
            return 1.0 / (1.0 + tau / dt)
        }

        mutating func filter(_ x: CGPoint, dt: CGFloat) -> CGPoint {
            guard let prev = xPrev else {
                xPrev = x
                dxPrev = .zero
                return x
            }
            let rawDx = CGPoint(x: (x.x - prev.x) / dt, y: (x.y - prev.y) / dt)
            let aD = alpha(fc: dCutoff, dt: dt)
            let dxHat = CGPoint(
                x: dxPrev.x + (rawDx.x - dxPrev.x) * aD,
                y: dxPrev.y + (rawDx.y - dxPrev.y) * aD
            )
            let v = hypot(dxHat.x, dxHat.y)
            let fc = minCutoff + betaNorm * v
            let a = alpha(fc: fc, dt: dt)
            let xHat = CGPoint(
                x: prev.x + (x.x - prev.x) * a,
                y: prev.y + (x.y - prev.y) * a
            )
            xPrev = xHat
            dxPrev = dxHat
            return xHat
        }

        mutating func overrideState(_ pt: CGPoint) {
            xPrev = pt
        }
    }

    private struct JointTrackerState {
        var filter: OneEuroFilter2D
        var pos: CGPoint = CGPoint(x: 0.5, y: 0.5)
        var hasEverBeenSeen: Bool = false
        var smoothConf: CGFloat = 0.0
        var rawConf: CGFloat = 0.0
        var isTracked: Bool = false
        var missingTime: CGFloat = 0.0
        var relOffset: CGPoint = .zero
        var outlierFrames: Int = 0

        init(isHand: Bool) {
            // iOS 60fps commercial tuning: hands snappy (1.5 / 10.0), body/legs rock-solid calm (1.1 / 5.0)
            self.filter = OneEuroFilter2D(
                minCutoff: isHand ? 1.5 : 1.1,
                betaNorm: isHand ? 10.0 : 5.0
            )
        }
    }

    private struct PlayerTrackerState {
        var joints: [JointKey: JointTrackerState]
        var smoothTorsoH: CGFloat = 0.28
        var lastCenterX: CGFloat = 0.5
        var torsoAnchor: CGPoint = CGPoint(x: 0.5, y: 0.55)
        var prevTime: CFTimeInterval = 0
        var lastSeenTime: CFTimeInterval = 0
        var prevMotionPos: (CGPoint, CGPoint, CGPoint)? = nil

        init(initialCenterX: CGFloat = 0.5, initialTorsoH: CGFloat = 0.28) {
            var map: [JointKey: JointTrackerState] = [:]
            for k in JointKey.allCases {
                map[k] = JointTrackerState(isHand: k.isHand)
            }
            self.joints = map
            self.lastCenterX = initialCenterX
            self.smoothTorsoH = initialTorsoH
        }
    }

    private var playerStates: [Int: PlayerTrackerState] = [:]
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

    func setExpectedPlayers(_ count: Int) {
        let clamped = max(1, min(2, count))
        visionQueue.async { [weak self] in
            self?.expectedPlayers = clamped
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.expectedPlayers = clamped
            if !self.isUsingCamera {
                self.updateDevPlayers()
            }
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
        visionQueue.async { [weak self] in
            self?.playerStates.removeAll()
        }

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

    private func makeDevMetrics(centerX: CGFloat, px: CGFloat, py: CGFloat, t: TimeInterval, active: Bool) -> (head: CGPoint, leftHand: CGPoint, rightHand: CGPoint, handsUp: Bool, metrics: FullBodyMetrics) {
        let isSquatting = active && py > 0.66
        let isJumping = active && py < 0.26
        let leanSigned: CGFloat = active ? max(-0.42, min(0.42, (px - centerX) * 1.45)) : 0.0
        let headY: CGFloat = isSquatting ? 0.58 : (isJumping ? 0.32 : 0.43)
        let shY: CGFloat = headY + 0.09
        let hipY: CGFloat = shY + (isSquatting ? 0.17 : 0.22)
        let torsoH: CGFloat = max(0.14, hipY - shY)
        let shW: CGFloat = 0.15
        let headX = max(0.08, min(0.92, centerX + leanSigned * torsoH))
        let shL = CGPoint(x: headX - shW * 0.5, y: shY)
        let shR = CGPoint(x: headX + shW * 0.5, y: shY)

        let lHand: CGPoint
        let rHand: CGPoint
        if active {
            let wideSpread = (py > 0.30 && py < 0.60) ? max(0.08, abs(px - centerX) * 0.8 + 0.11) : 0.07
            lHand = CGPoint(x: max(0.04, px - wideSpread), y: py)
            rHand = CGPoint(x: min(0.96, px + wideSpread), y: py)
        } else {
            lHand = CGPoint(x: centerX - 0.09 + sin(t * 2.5) * 0.03, y: 0.48)
            rHand = CGPoint(x: centerX + 0.09 + cos(t * 2.6) * 0.03, y: 0.48)
        }
        let elL = CGPoint(x: (shL.x + lHand.x) * 0.5, y: (shL.y + lHand.y) * 0.5 + 0.03)
        let elR = CGPoint(x: (shR.x + rHand.x) * 0.5, y: (shR.y + rHand.y) * 0.5 + 0.03)

        let hipL = CGPoint(x: centerX - 0.055, y: hipY)
        let hipR = CGPoint(x: centerX + 0.055, y: hipY)

        // When dragging low (lower mole holes or running), move nearest foot toward pointer for smooth dev testing!
        let runLift: CGFloat = (active && devVelocity > 0.015) ? abs(sin(t * 14.0)) * 0.10 : 0.0
        let oneLegLift: CGFloat = (active && abs(px - centerX) > 0.18 && py > 0.35 && py < 0.65) ? 0.12 : 0.0
        let kickLeft = active && py > 0.68 && px <= centerX
        let kickRight = active && py > 0.68 && px > centerX

        let kneeYBase = hipY + (isSquatting ? 0.09 : 0.14)
        let ankleYBase = min(0.95, kneeYBase + (isSquatting ? 0.12 : 0.14))

        let knL = CGPoint(x: hipL.x - (isSquatting ? 0.05 : 0.01), y: kneeYBase - (kickLeft ? 0.04 : runLift))
        let knR = CGPoint(x: hipR.x + (isSquatting ? 0.05 : 0.01), y: kneeYBase - (kickRight ? 0.04 : oneLegLift))
        let anL = kickLeft
            ? CGPoint(x: px, y: min(0.94, py))
            : CGPoint(x: hipL.x - 0.02, y: max(kneeYBase + 0.04, ankleYBase - runLift))
        let anR = kickRight
            ? CGPoint(x: px, y: min(0.94, py))
            : CGPoint(x: hipR.x + 0.02, y: max(kneeYBase + 0.04, ankleYBase - oneLegLift))

        let footLift = max(abs(anL.y - anR.y), abs(knL.y - knR.y))
        let kneeAngle: CGFloat = isSquatting ? 108 : 172

        let metrics = FullBodyMetrics(
            torsoH: torsoH,
            shoulderW: shW,
            shoulderY: shY,
            hipY: hipY,
            lElbowAngle: 155,
            rElbowAngle: 155,
            lKneeAngle: kneeAngle,
            rKneeAngle: kneeAngle,
            wristSpan: abs(lHand.x - rHand.x),
            ankleSpan: abs(anL.x - anR.x),
            footLift: footLift,
            torsoLean: abs(leanSigned),
            torsoLeanSigned: leanSigned,
            isSquatting: isSquatting,
            lShoulder: shL,
            rShoulder: shR,
            lElbow: elL,
            rElbow: elR,
            lHip: hipL,
            rHip: hipR,
            lKnee: knL,
            rKnee: knR,
            lAnkle: anL,
            rAnkle: anR,
            neck: CGPoint(x: headX, y: shY - 0.015),
            headConf: 1.0,
            neckConf: 1.0,
            lShoulderConf: 1.0,
            rShoulderConf: 1.0,
            lElbowConf: 1.0,
            rElbowConf: 1.0,
            lWristConf: 1.0,
            rWristConf: 1.0,
            lHipConf: 1.0,
            rHipConf: 1.0,
            lKneeConf: 1.0,
            rKneeConf: 1.0,
            lAnkleConf: 1.0,
            rAnkleConf: 1.0
        )
        let head = CGPoint(x: headX, y: headY)
        let handsUp = lHand.y < shY - 0.02 || rHand.y < shY - 0.02
        return (head, lHand, rHand, handsUp, metrics)
    }

    private func updateDevPlayers() {
        let px = devPointer.x
        let py = devPointer.y
        let t = CACurrentMediaTime()

        if expectedPlayers == 1 {
            let d = makeDevMetrics(centerX: 0.5, px: px, py: py, t: t, active: true)
            players = [
                PlayerPose(
                    id: 0,
                    centerX: 0.5,
                    centerY: d.metrics.shoulderY,
                    head: d.head,
                    leftHand: d.leftHand,
                    rightHand: d.rightHand,
                    handsUp: d.handsUp,
                    motion: devVelocity,
                    metrics: d.metrics
                )
            ]
        } else {
            let p1Active = px < 0.55
            let d1 = makeDevMetrics(centerX: 0.28, px: px, py: py, t: t, active: p1Active)
            let d2 = makeDevMetrics(centerX: 0.72, px: px, py: py, t: t, active: !p1Active)
            players = [
                PlayerPose(
                    id: 0,
                    centerX: 0.28,
                    centerY: d1.metrics.shoulderY,
                    head: d1.head,
                    leftHand: d1.leftHand,
                    rightHand: d1.rightHand,
                    handsUp: d1.handsUp,
                    motion: p1Active ? devVelocity : 0,
                    metrics: d1.metrics
                ),
                PlayerPose(
                    id: 1,
                    centerX: 0.72,
                    centerY: d2.metrics.shoulderY,
                    head: d2.head,
                    leftHand: d2.leftHand,
                    rightHand: d2.rightHand,
                    handsUp: d2.handsUp,
                    motion: !p1Active ? devVelocity : 0,
                    metrics: d2.metrics
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
    /// Keeps off-screen values softly in [-0.5, 1.5] so elbows/hips outside the frame preserve true limb angles.
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
        return CGPoint(x: max(-0.5, min(1.5, x)), y: max(-0.5, min(1.5, y)))
    }
}

extension VisionCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let screenAspect: CGFloat = (viewSize.width > 10 && viewSize.height > 10)
            ? (viewSize.width / viewSize.height)
            : (bufW > 0 && bufH > 0 ? bufW / bufH : 16.0 / 9.0)

        // Because `videoOutput` connection is ALREADY rotated upright & mirrored via RotationCoordinator,
        // Vision receives an upright, mirrored image directly (.up)!
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([poseRequest])
            guard let observations = poseRequest.results, !observations.isEmpty else {
                let nextCursor = self.computeAirCursor(from: [])
                DispatchQueue.main.async {
                    self.players = []
                    self.airCursor = nextCursor
                    if self.isUsingCamera {
                        self.statusText = "인식됨: 0/\(self.expectedPlayers)명 · 카메라 앞으로 서 주세요"
                    }
                }
                return
            }

            let now = CACurrentMediaTime()

            // Step 1: Extract raw detections + quality score + upper-body bbox for Pose NMS deduplication
            struct RawDetection {
                let sortX: CGFloat
                let centerY: CGFloat
                let shW: CGFloat
                let qualityScore: CGFloat
                let bbox: CGRect
                let anchor: CGPoint
                let rawJoints: [JointKey: (pt: CGPoint, conf: CGFloat)]
            }

            var rawDetections: [RawDetection] = []
            for obs in observations {
                guard let points = try? obs.recognizedPoints(.all) else { continue }

                func rawSample(_ key: VNHumanBodyPoseObservation.JointName) -> (pt: CGPoint, conf: CGFloat)? {
                    guard let p = points[key], p.confidence > 0.02 else { return nil }
                    // Vision origin is bottom-left -> convert to top-left [0..1] -> adjust for resizeAspectFill
                    let topLeft = CGPoint(x: p.location.x, y: 1.0 - p.location.y)
                    let mapped = mapAspectFill(topLeft, bufferWidth: bufW, bufferHeight: bufH)
                    return (mapped, CGFloat(p.confidence))
                }

                let noseS = rawSample(.nose)
                let neckS = rawSample(.neck)
                let shLS = rawSample(.leftShoulder)
                let shRS = rawSample(.rightShoulder)
                let elLS = rawSample(.leftElbow)
                let elRS = rawSample(.rightElbow)
                let wrLS = rawSample(.leftWrist)
                let wrRS = rawSample(.rightWrist)
                let hipLS = rawSample(.leftHip)
                let hipRS = rawSample(.rightHip)

                let headSample: (pt: CGPoint, conf: CGFloat)? = {
                    if let n = noseS, n.conf >= 0.18 { return n }
                    if let nk = neckS, nk.conf >= 0.18 { return nk }
                    return noseS ?? neckS
                }()
                let anchorPt: CGPoint? = headSample?.pt
                    ?? (shLS != nil && shLS!.conf >= 0.18 ? shLS!.pt : nil)
                    ?? (shRS != nil && shRS!.conf >= 0.18 ? shRS!.pt : nil)
                guard let anchor = anchorPt else { continue }

                // Quality gate: require at least 2 strong upper-body landmarks (or close-up head + hand)
                let upperSamples = [headSample, shLS, shRS].compactMap { $0 }
                let strongUpperCount = upperSamples.filter { $0.conf >= 0.24 }.count
                let upperAvg = upperSamples.reduce(CGFloat(0)) { $0 + $1.conf } / 3.0
                let hasCloseUpHand = (headSample?.conf ?? 0) >= 0.30 && ((wrLS?.conf ?? 0) >= 0.30 || (wrRS?.conf ?? 0) >= 0.30)
                if strongUpperCount < 2 && !hasCloseUpHand { continue }
                if upperAvg < 0.18 && !hasCloseUpHand { continue }

                var map: [JointKey: (pt: CGPoint, conf: CGFloat)] = [:]
                if let h = headSample { map[.head] = h }
                if let s = neckS { map[.neck] = s }
                if let s = shLS { map[.lShoulder] = s }
                if let s = shRS { map[.rShoulder] = s }
                if let s = elLS { map[.lElbow] = s }
                if let s = elRS { map[.rElbow] = s }
                if let s = wrLS { map[.lWrist] = s }
                if let s = wrRS { map[.rWrist] = s }
                if let s = hipLS { map[.lHip] = s }
                if let s = hipRS { map[.rHip] = s }
                if let s = rawSample(.leftKnee) { map[.lKnee] = s }
                if let s = rawSample(.rightKnee) { map[.rKnee] = s }
                if let s = rawSample(.leftAnkle) { map[.lAnkle] = s }
                if let s = rawSample(.rightAnkle) { map[.rAnkle] = s }

                let bothSh = (shLS?.conf ?? 0) >= 0.20 && (shRS?.conf ?? 0) >= 0.20
                let sortX: CGFloat = bothSh ? (shLS!.pt.x + shRS!.pt.x) * 0.5 : anchor.x
                let centerY: CGFloat = bothSh ? (shLS!.pt.y + shRS!.pt.y) * 0.5 : anchor.y + 0.14
                let shW: CGFloat = bothSh
                    ? max(0.06, hypot((shLS!.pt.x - shRS!.pt.x) * screenAspect, shLS!.pt.y - shRS!.pt.y))
                    : 0.24

                let boxPts = [headSample, shLS, shRS, elLS, elRS, hipLS, hipRS]
                    .compactMap { ($0 != nil && $0!.conf >= 0.18) ? $0!.pt : nil }
                let bbox: CGRect
                if boxPts.count >= 2 {
                    let minX = (boxPts.map(\.x).min() ?? sortX) - 0.04
                    let maxX = (boxPts.map(\.x).max() ?? sortX) + 0.04
                    let minY = (boxPts.map(\.y).min() ?? centerY) - 0.04
                    let maxY = (boxPts.map(\.y).max() ?? centerY) + 0.04
                    bbox = CGRect(x: minX, y: minY, width: max(0.05, maxX - minX), height: max(0.05, maxY - minY))
                } else {
                    bbox = CGRect(x: sortX - 0.08, y: centerY - 0.12, width: 0.16, height: 0.30)
                }

                let qualityScore = upperAvg + 0.22 * min(1.0, shW * 2.4)
                rawDetections.append(RawDetection(
                    sortX: sortX,
                    centerY: centerY,
                    shW: shW,
                    qualityScore: qualityScore,
                    bbox: bbox,
                    anchor: anchor,
                    rawJoints: map
                ))
            }

            // Step 1b: Pose NMS Deduplication — prevents 1 person in 2P mode from spawning duplicate 4-dot skeletons!
            let ranked = rawDetections.sorted { $0.qualityScore > $1.qualityScore }
            var deduped: [RawDetection] = []
            for cand in ranked {
                var isDup = false
                for k in deduped {
                    let refShW = max(0.14, max(cand.shW, k.shW))
                    let cDist = hypot((cand.sortX - k.sortX) * screenAspect, cand.centerY - k.centerY)
                    if cDist < max(0.18, 0.88 * refShW) { isDup = true; break }

                    if let ch = cand.rawJoints[.head], ch.conf >= 0.22,
                       let kh = k.rawJoints[.head], kh.conf >= 0.22 {
                        let hDist = hypot((ch.pt.x - kh.pt.x) * screenAspect, ch.pt.y - kh.pt.y)
                        if hDist < max(0.14, 0.58 * refShW) { isDup = true; break }
                    }

                    let inter = cand.bbox.intersection(k.bbox)
                    if !inter.isNull && !inter.isEmpty {
                        let interArea = inter.width * inter.height
                        let aA = max(1e-5, cand.bbox.width * cand.bbox.height)
                        let aB = max(1e-5, k.bbox.width * k.bbox.height)
                        let iou = interArea / max(1e-5, aA + aB - interArea)
                        let contain = interArea / min(aA, aB)
                        if iou > 0.28 || contain > 0.48 { isDup = true; break }
                    }
                }
                if !isDup { deduped.append(cand) }
            }

            // Expire stale player slots absent > 1.2s so re-entry snaps cleanly
            for (slotIdx, st) in playerStates where now - st.lastSeenTime > 1.2 {
                playerStates.removeValue(forKey: slotIdx)
            }

            // Step 1c: Persistent slot assignment (0 = P1 Momo left, 1 = P2 Popo right)
            var assigned: [(slotId: Int, det: RawDetection)] = []
            if !deduped.isEmpty {
                if expectedPlayers <= 1 {
                    var pick = deduped[0]
                    if deduped.count > 1, let prev0 = playerStates[0], now - prev0.lastSeenTime < 0.9 {
                        pick = deduped.min(by: { abs($0.sortX - prev0.lastCenterX) < abs($1.sortX - prev0.lastCenterX) }) ?? deduped[0]
                    }
                    assigned = [(0, pick)]
                } else {
                    let top2 = Array(deduped.prefix(2))
                    if top2.count == 2 {
                        let lr = top2.sorted { $0.sortX < $1.sortX }
                        assigned = [(0, lr[0]), (1, lr[1])]
                    } else {
                        let single = top2[0]
                        let has0 = (playerStates[0] != nil) && (now - playerStates[0]!.lastSeenTime < 0.7)
                        let has1 = (playerStates[1] != nil) && (now - playerStates[1]!.lastSeenTime < 0.7)
                        if has1 && !has0 && abs(single.sortX - playerStates[1]!.lastCenterX) < 0.26 {
                            assigned = [(1, single)]
                        } else {
                            assigned = [(0, single)]
                        }
                    }
                }
            }

            // Step 2: Filter ALL 14 joints FIRST (One-Euro + Confidence Hysteresis/EMA + 0.45s Persistence + Aspect-Corrected Non-Destructive Clamping + Palm Projection)
            let enterConf: CGFloat = 0.28
            let exitConf: CGFloat = 0.14
            let tauRise: CGFloat = 0.08
            let tauFall: CGFloat = 0.22
            let occlusionHoldSec: CGFloat = 0.45

            func clampBone(parent: CGPoint, child: CGPoint, maxLen: CGFloat) -> CGPoint {
                let dx = (child.x - parent.x) * screenAspect
                let dy = child.y - parent.y
                let dist = hypot(dx, dy)
                if dist > maxLen && dist > 1e-4 {
                    let s = maxLen / dist
                    return CGPoint(x: parent.x + (dx * s) / screenAspect, y: parent.y + dy * s)
                }
                return child
            }

            func projectPalm(wrist: CGPoint, elbow: CGPoint, elbowConf: CGFloat) -> CGPoint {
                let blend = max(0, min(1, (elbowConf - 0.18) / 0.26))
                guard blend > 0.01 else { return wrist }
                let vx = wrist.x - elbow.x
                let vy = wrist.y - elbow.y
                let lenReal = hypot(vx * screenAspect, vy)
                guard lenReal > 0.02 else { return wrist }
                // Project ~0.28x forearm length past wrist onto the visual palm center (max 0.10 screen-height units)
                let desired = min(0.10, lenReal * 0.28) * blend
                let s = desired / lenReal
                return CGPoint(x: wrist.x + vx * s, y: wrist.y + vy * s)
            }

            func angleDeg(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
                let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
                let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
                let m1 = hypot(v1.x, v1.y), m2 = hypot(v2.x, v2.y)
                if m1 < 1e-4 || m2 < 1e-4 { return 180 }
                let cosVal = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / (m1 * m2)))
                return acos(cosVal) * 180.0 / .pi
            }

            var limited: [PlayerPose] = []
            for (idx, det) in assigned {
                var state: PlayerTrackerState
                if let existing = playerStates[idx],
                   now - existing.lastSeenTime <= 1.2,
                   abs(det.sortX - existing.lastCenterX) <= 0.36 {
                    state = existing
                } else {
                    let initTorso = max(0.18, min(1.25, det.shW * 1.48))
                    state = PlayerTrackerState(initialCenterX: det.sortX, initialTorsoH: initTorso)
                }
                let dt = CGFloat(max(0.008, min(0.10, state.prevTime > 0 ? (now - state.prevTime) : 0.016)))
                state.prevTime = now
                state.lastSeenTime = now
                state.lastCenterX = det.sortX

                // Helper to update a single joint through Hysteresis + Asymmetric EMA + Outlier Gate + 0.45s Torso-Relative Persistence + True One-Euro Filter
                func updateJoint(_ key: JointKey, fallbackPos: CGPoint, torsoAnchor: CGPoint, torsoH: CGFloat) {
                    var j = state.joints[key] ?? JointTrackerState(isHand: key.isHand)
                    let sample = det.rawJoints[key]
                    let rawConf = sample?.conf ?? 0.0
                    j.rawConf = rawConf

                    // Confidence hysteresis (ENTER = 0.28, EXIT = 0.14)
                    if j.isTracked {
                        if sample == nil || rawConf < exitConf { j.isTracked = false }
                    } else {
                        if sample != nil && rawConf >= enterConf { j.isTracked = true }
                    }

                    if j.isTracked, let rawPt = sample?.pt {
                        j.missingTime = 0
                        let targetConf = min(1.0, rawConf)
                        let tau = targetConf >= j.smoothConf ? tauRise : tauFall
                        let aConf = 1.0 - exp(-dt / tau)
                        j.smoothConf += (targetConf - j.smoothConf) * aConf

                        // Single-frame teleport / outlier gate (high-confidence hands pass fast slashes immediately!)
                        let maxJump = key.isHand ? max(0.45, 1.85 * torsoH) : max(0.12, 0.45 * torsoH)
                        let inputPt: CGPoint
                        if j.hasEverBeenSeen {
                            let dist = hypot(rawPt.x - j.pos.x, rawPt.y - j.pos.y)
                            let rejectSpike = dist > maxJump && j.outlierFrames < 1 && (!key.isHand || rawConf < 0.55)
                            if rejectSpike {
                                j.outlierFrames += 1
                                inputPt = CGPoint(
                                    x: j.pos.x + (rawPt.x - j.pos.x) * 0.18,
                                    y: j.pos.y + (rawPt.y - j.pos.y) * 0.18
                                )
                            } else {
                                j.outlierFrames = 0
                                inputPt = rawPt
                            }
                        } else {
                            j.hasEverBeenSeen = true
                            j.outlierFrames = 0
                            inputPt = rawPt
                        }

                        j.pos = j.filter.filter(inputPt, dt: dt)
                        let safeH = max(0.14, torsoH)
                        j.relOffset = CGPoint(
                            x: (j.pos.x - torsoAnchor.x) / safeH,
                            y: (j.pos.y - torsoAnchor.y) / safeH
                        )
                    } else {
                        j.outlierFrames = 0
                        j.missingTime += dt
                        if j.hasEverBeenSeen {
                            let held = CGPoint(
                                x: max(-0.2, min(1.2, torsoAnchor.x + j.relOffset.x * torsoH)),
                                y: max(-0.2, min(1.2, torsoAnchor.y + j.relOffset.y * torsoH))
                            )
                            j.pos = j.filter.filter(held, dt: dt)
                            if j.missingTime <= occlusionHoldSec {
                                j.smoothConf *= exp(-dt / 0.28)
                            } else {
                                j.smoothConf = max(0.0, j.smoothConf - dt * 2.4)
                            }
                        } else {
                            j.pos = fallbackPos
                            j.smoothConf = 0.0
                        }
                    }

                    state.joints[key] = j
                }

                // Pass A: Core torso joints first so we have a rock-solid torsoAnchor & smoothTorsoH (including close-up upper-body seating!)
                let prevAnchor = state.joints[.lShoulder]?.hasEverBeenSeen == true ? state.torsoAnchor : CGPoint(x: det.anchor.x, y: det.anchor.y + 0.20)
                let prevTorsoH = state.smoothTorsoH

                updateJoint(.lShoulder, fallbackPos: CGPoint(x: det.anchor.x - 0.08, y: det.anchor.y + 0.11), torsoAnchor: prevAnchor, torsoH: prevTorsoH)
                updateJoint(.rShoulder, fallbackPos: CGPoint(x: det.anchor.x + 0.08, y: det.anchor.y + 0.11), torsoAnchor: prevAnchor, torsoH: prevTorsoH)

                let shLJ0 = state.joints[.lShoulder]!
                let shRJ0 = state.joints[.rShoulder]!
                let shLPos = shLJ0.pos
                let shRPos = shRJ0.pos
                let shMid = CGPoint(x: (shLPos.x + shRPos.x) * 0.5, y: (shLPos.y + shRPos.y) * 0.5)

                updateJoint(.lHip, fallbackPos: CGPoint(x: shLPos.x, y: shMid.y + prevTorsoH), torsoAnchor: prevAnchor, torsoH: prevTorsoH)
                updateJoint(.rHip, fallbackPos: CGPoint(x: shRPos.x, y: shMid.y + prevTorsoH), torsoAnchor: prevAnchor, torsoH: prevTorsoH)

                let hipLJ = state.joints[.lHip]!
                let hipRJ = state.joints[.rHip]!
                let hipsVisible = hipLJ.smoothConf > 0.20 && hipRJ.smoothConf > 0.20 &&
                    hipLJ.pos.y > 0.02 && hipLJ.pos.y < 0.96 && hipRJ.pos.y > 0.02 && hipRJ.pos.y < 0.96
                let hipMid = hipsVisible
                    ? CGPoint(x: (hipLJ.pos.x + hipRJ.pos.x) * 0.5, y: (hipLJ.pos.y + hipRJ.pos.y) * 0.5)
                    : CGPoint(x: shMid.x, y: shMid.y + prevTorsoH)

                let estTorsoH: CGFloat
                if hipsVisible {
                    estTorsoH = max(0.14, min(1.30, hypot((shMid.x - hipMid.x) * screenAspect, shMid.y - hipMid.y)))
                } else if shLJ0.smoothConf > 0.20 && shRJ0.smoothConf > 0.20 {
                    let shWReal = hypot((shLPos.x - shRPos.x) * screenAspect, shLPos.y - shRPos.y)
                    estTorsoH = max(0.18, min(1.30, shWReal * 1.48))
                } else {
                    estTorsoH = prevTorsoH
                }
                let aTorso = 1.0 - exp(-dt / 0.20)
                state.smoothTorsoH = max(0.14, min(1.30, state.smoothTorsoH + (estTorsoH - state.smoothTorsoH) * aTorso))
                let smoothTorsoH = state.smoothTorsoH
                let torsoAnchor = CGPoint(x: (shMid.x + hipMid.x) * 0.5, y: (shMid.y + hipMid.y) * 0.5)
                state.torsoAnchor = torsoAnchor

                // Pass B: Remaining 10 joints (head, neck, arms, legs) anchored to smooth torso!
                updateJoint(.head, fallbackPos: det.anchor, torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.neck, fallbackPos: CGPoint(x: shMid.x, y: shMid.y - smoothTorsoH * 0.08), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.lElbow, fallbackPos: CGPoint(x: shLPos.x - 0.02, y: shLPos.y + smoothTorsoH * 0.45), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.rElbow, fallbackPos: CGPoint(x: shRPos.x + 0.02, y: shRPos.y + smoothTorsoH * 0.45), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.lWrist, fallbackPos: state.joints[.lElbow]!.pos, torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.rWrist, fallbackPos: state.joints[.rElbow]!.pos, torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.lKnee, fallbackPos: CGPoint(x: hipLJ.pos.x, y: hipMid.y + smoothTorsoH * 0.65), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.rKnee, fallbackPos: CGPoint(x: hipRJ.pos.x, y: hipMid.y + smoothTorsoH * 0.65), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.lAnkle, fallbackPos: CGPoint(x: hipLJ.pos.x, y: hipMid.y + smoothTorsoH * 1.25), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)
                updateJoint(.rAnkle, fallbackPos: CGPoint(x: hipRJ.pos.x, y: hipMid.y + smoothTorsoH * 1.25), torsoAnchor: torsoAnchor, torsoH: smoothTorsoH)

                // Pass C: Aspect-corrected non-destructive upper-bound bone clamping
                let elLJ0 = state.joints[.lElbow]!
                let elRJ0 = state.joints[.rElbow]!
                let wrLJ0 = state.joints[.lWrist]!
                let wrRJ0 = state.joints[.rWrist]!

                let maxUpperArmL = (elLJ0.rawConf >= 0.28 ? 1.55 : 1.05) * smoothTorsoH
                let maxUpperArmR = (elRJ0.rawConf >= 0.28 ? 1.55 : 1.05) * smoothTorsoH
                let maxForearmL  = (wrLJ0.rawConf >= 0.28 ? 1.75 : 1.05) * smoothTorsoH
                let maxForearmR  = (wrRJ0.rawConf >= 0.28 ? 1.75 : 1.05) * smoothTorsoH
                let maxLeg       = 1.40 * smoothTorsoH

                let clampedElL = clampBone(parent: shLPos, child: elLJ0.pos, maxLen: maxUpperArmL)
                let clampedElR = clampBone(parent: shRPos, child: elRJ0.pos, maxLen: maxUpperArmR)
                let clampedWrL = clampBone(parent: clampedElL, child: wrLJ0.pos, maxLen: maxForearmL)
                let clampedWrR = clampBone(parent: clampedElR, child: wrRJ0.pos, maxLen: maxForearmR)
                let clampedKnL = clampBone(parent: hipLJ.pos, child: state.joints[.lKnee]!.pos, maxLen: maxLeg)
                let clampedKnR = clampBone(parent: hipRJ.pos, child: state.joints[.rKnee]!.pos, maxLen: maxLeg)
                let clampedAnL = clampBone(parent: clampedKnL, child: state.joints[.lAnkle]!.pos, maxLen: maxLeg)
                let clampedAnR = clampBone(parent: clampedKnR, child: state.joints[.rAnkle]!.pos, maxLen: maxLeg)

                state.joints[.lElbow]!.pos = clampedElL; state.joints[.lElbow]!.filter.overrideState(clampedElL)
                state.joints[.rElbow]!.pos = clampedElR; state.joints[.rElbow]!.filter.overrideState(clampedElR)
                state.joints[.lWrist]!.pos = clampedWrL; state.joints[.lWrist]!.filter.overrideState(clampedWrL)
                state.joints[.rWrist]!.pos = clampedWrR; state.joints[.rWrist]!.filter.overrideState(clampedWrR)
                state.joints[.lKnee]!.pos  = clampedKnL; state.joints[.lKnee]!.filter.overrideState(clampedKnL)
                state.joints[.rKnee]!.pos  = clampedKnR; state.joints[.rKnee]!.filter.overrideState(clampedKnR)
                state.joints[.lAnkle]!.pos = clampedAnL; state.joints[.lAnkle]!.filter.overrideState(clampedAnL)
                state.joints[.rAnkle]!.pos = clampedAnR; state.joints[.rAnkle]!.filter.overrideState(clampedAnR)

                // Step 3: Compute palm center + ALL FullBodyMetrics from the filtered & clamped 14 joints!
                let headJ = state.joints[.head]!
                let neckJ = state.joints[.neck]!
                let shLJ  = state.joints[.lShoulder]!
                let shRJ  = state.joints[.rShoulder]!
                let elLJ  = state.joints[.lElbow]!
                let elRJ  = state.joints[.rElbow]!
                let wrLJ  = state.joints[.lWrist]!
                let wrRJ  = state.joints[.rWrist]!
                let knLJ  = state.joints[.lKnee]!
                let knRJ  = state.joints[.rKnee]!
                let anLJ  = state.joints[.lAnkle]!
                let anRJ  = state.joints[.rAnkle]!

                let palmL = projectPalm(wrist: clampedWrL, elbow: clampedElL, elbowConf: elLJ.smoothConf)
                let palmR = projectPalm(wrist: clampedWrR, elbow: clampedElR, elbowConf: elRJ.smoothConf)

                let cx = shMid.x
                let sy = shMid.y
                let hipX = hipMid.x
                let hipY = hipMid.y
                let metricTorsoH = hipsVisible
                    ? max(0.12, hypot(cx - hipX, sy - hipY))
                    : max(0.14, min(0.65, smoothTorsoH))
                let shoulderW = max(0.08, hypot(shLPos.x - shRPos.x, shLPos.y - shRPos.y))
                let handsUp = (wrLJ.smoothConf >= 0.25 && palmL.y < sy - 0.03) ||
                    (wrRJ.smoothConf >= 0.25 && palmR.y < sy - 0.03)

                let lElbowAng = angleDeg(shLPos, clampedElL, palmL)
                let rElbowAng = angleDeg(shRPos, clampedElR, palmR)

                let lHipOpt: CGPoint? = hipLJ.smoothConf > 0.04 ? hipLJ.pos : nil
                let rHipOpt: CGPoint? = hipRJ.smoothConf > 0.04 ? hipRJ.pos : nil
                let lKneeOpt: CGPoint? = knLJ.smoothConf > 0.04 ? clampedKnL : nil
                let rKneeOpt: CGPoint? = knRJ.smoothConf > 0.04 ? clampedKnR : nil
                let lAnkleOpt: CGPoint? = anLJ.smoothConf > 0.04 ? clampedAnL : nil
                let rAnkleOpt: CGPoint? = anRJ.smoothConf > 0.04 ? clampedAnR : nil
                let neckOpt: CGPoint? = neckJ.smoothConf > 0.04 ? neckJ.pos : CGPoint(x: shMid.x, y: shMid.y - metricTorsoH * 0.06)

                let lLegTracked = hipLJ.smoothConf >= 0.14 && knLJ.smoothConf >= 0.14 && anLJ.smoothConf >= 0.14
                let rLegTracked = hipRJ.smoothConf >= 0.14 && knRJ.smoothConf >= 0.14 && anRJ.smoothConf >= 0.14
                let lKneeAng: CGFloat = lLegTracked ? angleDeg(hipLJ.pos, clampedKnL, clampedAnL) : 175
                let rKneeAng: CGFloat = rLegTracked ? angleDeg(hipRJ.pos, clampedKnR, clampedAnR) : 175

                let anklesTracked = anLJ.smoothConf >= 0.14 && anRJ.smoothConf >= 0.14
                let kneesTracked = knLJ.smoothConf >= 0.14 && knRJ.smoothConf >= 0.14
                let footLift: CGFloat = max(
                    anklesTracked ? abs(clampedAnL.y - clampedAnR.y) : 0,
                    kneesTracked ? abs(clampedKnL.y - clampedKnR.y) : 0
                )
                let ankleSpan: CGFloat = anklesTracked ? abs(clampedAnL.x - clampedAnR.x) : shoulderW
                let lowerVisible = hipsVisible && kneesTracked
                let kneeYAvg: CGFloat = kneesTracked ? (clampedKnL.y + clampedKnR.y) * 0.5 : (hipY + metricTorsoH * 0.8)
                let isSquatting = (lowerVisible && (min(lKneeAng, rKneeAng) < 138 || (kneeYAvg - hipY) < metricTorsoH * 0.48)) || headJ.pos.y > 0.56

                let signedLean = (cx - hipX) / metricTorsoH
                let metrics = FullBodyMetrics(
                    torsoH: metricTorsoH,
                    shoulderW: shoulderW,
                    shoulderY: sy,
                    hipY: hipY,
                    lElbowAngle: lElbowAng,
                    rElbowAngle: rElbowAng,
                    lKneeAngle: lKneeAng,
                    rKneeAngle: rKneeAng,
                    wristSpan: abs(palmL.x - palmR.x),
                    ankleSpan: ankleSpan,
                    footLift: footLift,
                    torsoLean: abs(signedLean),
                    torsoLeanSigned: signedLean,
                    isSquatting: isSquatting,
                    lShoulder: shLPos,
                    rShoulder: shRPos,
                    lElbow: clampedElL,
                    rElbow: clampedElR,
                    lHip: lHipOpt,
                    rHip: rHipOpt,
                    lKnee: lKneeOpt,
                    rKnee: rKneeOpt,
                    lAnkle: lAnkleOpt,
                    rAnkle: rAnkleOpt,
                    neck: neckOpt,
                    headConf: max(headJ.smoothConf, shLJ.smoothConf * 0.8),
                    neckConf: neckJ.smoothConf > 0.04 ? neckJ.smoothConf : min(shLJ.smoothConf, shRJ.smoothConf),
                    lShoulderConf: shLJ.smoothConf,
                    rShoulderConf: shRJ.smoothConf,
                    lElbowConf: elLJ.smoothConf,
                    rElbowConf: elRJ.smoothConf,
                    lWristConf: wrLJ.smoothConf,
                    rWristConf: wrRJ.smoothConf,
                    lHipConf: hipLJ.smoothConf,
                    rHipConf: hipRJ.smoothConf,
                    lKneeConf: knLJ.smoothConf,
                    rKneeConf: knRJ.smoothConf,
                    lAnkleConf: anLJ.smoothConf,
                    rAnkleConf: anRJ.smoothConf
                )

                var motion: CGFloat = 0
                if let prev = state.prevMotionPos {
                    motion = (wrLJ.smoothConf >= 0.20 ? hypot(palmL.x - prev.0.x, palmL.y - prev.0.y) : 0)
                        + (wrRJ.smoothConf >= 0.20 ? hypot(palmR.x - prev.1.x, palmR.y - prev.1.y) : 0)
                        + hypot(headJ.pos.x - prev.2.x, headJ.pos.y - prev.2.y) * 0.6
                }
                state.prevMotionPos = (palmL, palmR, headJ.pos)
                playerStates[idx] = state

                limited.append(PlayerPose(
                    id: idx,
                    centerX: cx,
                    centerY: sy,
                    head: headJ.pos,
                    leftHand: palmL,
                    rightHand: palmR,
                    handsUp: handsUp,
                    motion: motion,
                    metrics: metrics
                ))
            }

            let nextCursor = self.computeAirCursor(from: limited)
            DispatchQueue.main.async {
                self.players = limited
                self.airCursor = nextCursor
                if self.isUsingCamera {
                    self.statusText = "인식됨: \(limited.count)/\(self.expectedPlayers)명 · 실시간 추적 중"
                }
            }
        } catch {
            // Ignore transient Vision errors
        }
    }

    /// 1:1 Mirror-Aligned Single Dominant Hand Air Cursor across ALL valid players:
    /// - Requires real hand confidence (`smoothConf >= 0.34`) so off-screen/hallucinated hands NEVER hijack focus
    /// - Strong dominant-hand lock (`0.12` height margin + `0.22s` hold + `0.18s` dropout grace)
    /// - Exact 1:1 mirror mapping + calm micro-deadzone (`0.0045`) for rock-solid UI hover
    private func computeAirCursor(from players: [PlayerPose]) -> AirCursorState {
        let now = CACurrentMediaTime()
        let dt = CGFloat(max(0.008, min(0.1, now - (acPrevTime > 0 ? acPrevTime : now - 0.016))))
        acPrevTime = now

        struct HandCand {
            let key: String
            let pt: CGPoint
            let conf: CGFloat
            let isCurrent: Bool
        }

        var candidates: [HandCand] = []
        for p in players {
            let shY = p.centerY
            let torsoH = min(0.45, p.metrics.torsoH)
            let activeLineY: CGFloat = shY > 0.62 ? 0.88 : min(0.88, shY + torsoH * 0.32)

            let sides: [(String, CGPoint, CGFloat)] = [
                ("left", p.leftHand, p.metrics.lWristConf),
                ("right", p.rightHand, p.metrics.rWristConf)
            ]
            for (side, pt, conf) in sides {
                let key = "\(p.id):\(side)"
                let isCurrent = (key == dominantHandKey)
                let minConf: CGFloat = isCurrent ? 0.22 : 0.34
                let maxY: CGFloat = isCurrent ? min(0.94, activeLineY + 0.06) : activeLineY
                let inView = pt.x >= -0.02 && pt.x <= 1.02 && pt.y >= -0.02 && pt.y <= 1.02
                if inView && conf >= minConf && pt.y < maxY {
                    candidates.append(HandCand(key: key, pt: pt, conf: conf, isCurrent: isCurrent))
                }
            }
        }

        guard !candidates.isEmpty else {
            acLostTimer += dt
            acCandidateKey = nil
            acCandidateHold = 0
            if acLostTimer > 0.18 {
                dominantHandKey = nil
                return AirCursorState(active: false, x: airCursor.x, y: airCursor.y)
            }
            return airCursor
        }
        acLostTimer = 0

        candidates.sort { $0.pt.y < $1.pt.y }
        let highest = candidates[0]
        let current = candidates.first(where: { $0.isCurrent })

        var chosen = current ?? highest
        if let cur = current, highest.key != cur.key {
            if cur.pt.y - highest.pt.y > 0.12 && highest.conf >= 0.40 {
                if acCandidateKey == highest.key {
                    acCandidateHold += dt
                    if acCandidateHold >= 0.22 {
                        chosen = highest
                        acCandidateKey = nil
                        acCandidateHold = 0
                    }
                } else {
                    acCandidateKey = highest.key
                    acCandidateHold = 0
                }
            } else {
                acCandidateKey = nil
                acCandidateHold = 0
            }
        } else {
            acCandidateKey = nil
            acCandidateHold = 0
        }

        let switched = (dominantHandKey != chosen.key)
        dominantHandKey = chosen.key

        let mx = max(0.02, min(0.98, chosen.pt.x))
        let my = max(0.02, min(0.98, chosen.pt.y))

        if !airCursor.active || switched {
            return AirCursorState(active: true, x: mx, y: my)
        }

        let moveDist = hypot(mx - airCursor.x, my - airCursor.y)
        if moveDist < 0.0045 {
            return airCursor
        }
        let alpha: CGFloat = moveDist > 0.03 ? 0.82 : max(0.28, min(0.82, (moveDist - 0.0045) / 0.0255))
        let sx = airCursor.x + (mx - airCursor.x) * alpha
        let sy = airCursor.y + (my - airCursor.y) * alpha
        return AirCursorState(active: true, x: sx, y: sy)
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
