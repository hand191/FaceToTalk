@preconcurrency import AVFoundation
import CoreImage
import Foundation
@preconcurrency import Vision

struct FacingAngleThresholds: Equatable, Sendable {
    let enterYaw: Double
    let enterPitch: Double
    let exitYaw: Double
    let exitPitch: Double

    init(
        enterYawDegrees: Double,
        enterPitchDegrees: Double,
        exitYawDegrees: Double,
        exitPitchDegrees: Double
    ) {
        enterYaw = enterYawDegrees * .pi / 180
        enterPitch = enterPitchDegrees * .pi / 180
        exitYaw = exitYawDegrees * .pi / 180
        exitPitch = exitPitchDegrees * .pi / 180
    }

    static let standard = FacingAngleThresholds(
        enterYawDegrees: 16,
        enterPitchDegrees: 14,
        exitYawDegrees: 24,
        exitPitchDegrees: 21
    )
}

struct HeadPoseClassifier: Sendable {
    var thresholds: FacingAngleThresholds
    private(set) var wasFacing = false

    init(thresholds: FacingAngleThresholds = .standard) {
        self.thresholds = thresholds
    }

    mutating func classify(yaw: Double, pitch: Double) -> VisualState {
        let yawLimit = wasFacing ? thresholds.exitYaw : thresholds.enterYaw
        let pitchLimit = wasFacing ? thresholds.exitPitch : thresholds.enterPitch
        let facing = abs(yaw) <= yawLimit && abs(pitch) <= pitchLimit
        wasFacing = facing
        return facing ? .facing : .away
    }

    mutating func reset() {
        wasFacing = false
    }
}

final class VisionCameraService: NSObject, @unchecked Sendable {
    var onEvent: (@Sendable (CameraEvent) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "FaceToTalk.camera.session")
    private let analysisQueue = DispatchQueue(label: "FaceToTalk.camera.analysis", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectFaceRectanglesRequest()
    private var configured = false
    private var intentionallyStopped = false
    private var lastAnalysisTime: TimeInterval = 0
    private var poseClassifier = HeadPoseClassifier()
    private var notificationTokens: [NSObjectProtocol] = []

    private let analysisInterval: TimeInterval = 0.125
    override init() {
        super.init()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        installSessionObservers()
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func currentPermission() -> CameraPermissionState {
        permissionState(for: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func updateFacingAngleThresholds(_ thresholds: FacingAngleThresholds) {
        analysisQueue.async { [weak self] in
            self?.poseClassifier = HeadPoseClassifier(thresholds: thresholds)
        }
    }

    func start() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        onEvent?(.permission(permissionState(for: authorization)))

        switch authorization {
        case .authorized:
            startAuthorizedSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.onEvent?(.permission(granted ? .allowed : .denied))
                if granted {
                    self.startAuthorizedSession()
                }
            }
        case .denied:
            onEvent?(.failed("摄像头权限已拒绝，请在系统设置中允许 FaceToTalk。"))
        case .restricted:
            onEvent?(.failed("摄像头访问受到系统限制。"))
        @unknown default:
            onEvent?(.failed("无法识别当前摄像头权限状态。"))
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.intentionallyStopped = true
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.analysisQueue.async { [weak self] in
                self?.poseClassifier.reset()
            }
        }
    }

    private func startAuthorizedSession() {
        onEvent?(.starting)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.intentionallyStopped = false
            do {
                if !self.configured {
                    try self.configureSession()
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.onEvent?(.running)
            } catch {
                self.onEvent?(.failed("摄像头启动失败：\(error.localizedDescription)"))
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .low

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .unspecified
        ) else {
            throw CameraServiceError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraServiceError.cannotAddInput
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: analysisQueue)
        guard session.canAddOutput(output) else {
            throw CameraServiceError.cannotAddOutput
        }
        session.addOutput(output)
        configured = true
    }

    private func installSessionObservers() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.onEvent?(.interrupted("摄像头被系统中断"))
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.intentionallyStopped else { return }
            self.startAuthorizedSession()
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? "未知错误"
            self?.onEvent?(.interrupted("摄像头运行错误：\(detail)"))
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.didStopRunningNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.intentionallyStopped else { return }
            self.onEvent?(.interrupted("摄像头会话意外停止"))
        })
    }

    private func permissionState(for status: AVAuthorizationStatus) -> CameraPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}

extension VisionCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysisTime >= analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastAnalysisTime = now

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([request])
            let faces = request.results ?? []

            guard let face = faces.max(by: {
                ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
            }) else {
                poseClassifier.reset()
                onEvent?(.sample(VisionSample(state: .noFace, yaw: nil, pitch: nil, timestamp: now)))
                return
            }

            guard let yaw = face.yaw?.doubleValue,
                  let pitch = face.pitch?.doubleValue else {
                poseClassifier.reset()
                onEvent?(.sample(VisionSample(state: .uncertain, yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, timestamp: now)))
                return
            }

            let visualState = poseClassifier.classify(yaw: yaw, pitch: pitch)
            onEvent?(.sample(VisionSample(
                state: visualState,
                yaw: yaw,
                pitch: pitch,
                timestamp: now
            )))
        } catch {
            poseClassifier.reset()
            onEvent?(.sample(VisionSample(state: .uncertain, yaw: nil, pitch: nil, timestamp: now)))
        }
    }
}

private enum CameraServiceError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: "没有找到可用的内建摄像头"
        case .cannotAddInput: "无法添加摄像头视频输入"
        case .cannotAddOutput: "无法添加低分辨率视频分析输出"
        }
    }
}
