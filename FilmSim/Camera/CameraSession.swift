import AVFoundation
import Combine
import CoreImage
import SwiftUI
import UIKit

// MARK: - 错误

enum CameraError: LocalizedError {
    case noDevice
    case cannotAddInput
    case cannotAddOutput
    case formatUnavailable
    case photoProcessingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noDevice:            return "找不到可用的摄像头"
        case .cannotAddInput:      return "无法添加摄像头输入"
        case .cannotAddOutput:     return "无法添加相机输出"
        case .formatUnavailable:   return "这台设备没有可用的拍摄格式"
        case .photoProcessingFailed: return "照片处理失败"
        case .saveFailed:          return "保存到相册失败"
        }
    }
}

// MARK: - 相机会话

/// 相机管线：
///  - `videoOutput`  → 实时取景（每帧套胶片模拟）+ 对焦辅助
///  - `photoOutput`  → 全分辨率照片，拍完再用同一套渲染器烘焙胶片
///  - `movieOutput`  → 视频录制（可开 Apple Log，录制时按需挂载）
/// 手动曝光（快门 / ISO）通过 `setExposureModeCustom` 实现。
final class CameraSession: NSObject, ObservableObject {

    // MARK: 流水线

    let renderer = FilmRenderer()
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "filmsim.capture.session")
    private let videoQueue = DispatchQueue(label: "filmsim.capture.video", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var activeProcessors: [Int64: PhotoCaptureProcessor] = [:]
    private var recordTimer: Timer?
    private var recordStartedAt: Date?
    private var isZooming = false
    private var zoomBase: CGFloat = 1

    private weak var preview: PreviewRenderer?

    // MARK: 状态（给 UI 用）

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var toast: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordSeconds = 0
    @Published private(set) var videoSize = CGSize(width: 1080, height: 1440)
    @Published private(set) var appleLogSupported = false
    @Published private(set) var supportsCustomExposure = true
    @Published private(set) var isFrontCamera = false
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var maxZoomFactor: CGFloat = 5
    @Published private(set) var focusIndicator: CGPoint?
    /// 手动快门实际生效的时长（秒），部分机型会被帧率上限夹住
    @Published private(set) var actualExposureSeconds: Double?

    @Published var mode: CaptureMode = .photo {
        didSet {
            guard oldValue != mode else { return }
            applyVideoPipeline()
        }
    }

    @Published var shutter: ShutterSpeed = .auto {
        didSet {
            guard oldValue != shutter else { return }
            applyExposure()
        }
    }

    @Published var isoMode: ISOMode = .auto {
        didSet {
            guard oldValue != isoMode else { return }
            applyExposure()
        }
    }

    @Published var manualISO: Double = 100 {
        didSet {
            guard abs(oldValue - manualISO) > 0.5 else { return }
            applyExposure()
        }
    }

    @Published var exposureBias: Double = 0 {
        didSet {
            guard abs(oldValue - exposureBias) > 0.01 else { return }
            applyExposureBias()
        }
    }

    @Published var look = FilmLook()

    @Published var appleLogEnabled = false {
        didSet {
            guard oldValue != appleLogEnabled else { return }
            if appleLogEnabled { mode = .video }
            applyVideoPipeline()
        }
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.publish { self.permissionDenied = true }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                self.configureAndRun()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.publish { self.isRunning = false }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    #if targetEnvironment(simulator)
                    self.publish {
                        self.isRunning = true
                        self.statusMessage = "模拟器模式：没有真实相机，画面是测试图；真机请在 TestFlight 里测"
                    }
                    #else
                    let message = error.localizedDescription
                    self.publish { self.statusMessage = message }
                    #endif
                    return
                }
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            let logSupported = self.device.map {
                self.bestFormat(for: $0, needsAppleLog: true) != nil
            } ?? false
            let customExposure = self.device?.isExposureModeSupported(.custom) ?? false
            let maxZoom = self.device.map { min($0.activeFormat.videoMaxZoomFactor, 6) } ?? 1
            self.publish {
                self.isRunning = running
                self.appleLogSupported = logSupported
                self.supportsCustomExposure = customExposure
                self.maxZoomFactor = maxZoom
            }
            self.applyExposure()
        }
    }

    // MARK: - 配置

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority

        guard let device = makeDevice(position: .back) else { throw CameraError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        videoInput = input
        self.device = device

        try configureFormat(device: device, appleLog: false)

        // 照片输出：全分辨率
        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            photoOutput.maxPhotoDimensions = largest
        }

        // 视频数据输出：预览 + 对焦辅助
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        // 录音
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            audioInput = micInput
        }

        // movieOutput 只在真正录像时挂载，避免影响预览链路
        configureConnections()
    }

    /// 选一个「能拍最大照片 + 支持 30fps +（需要时）支持 Apple Log」的格式
    private func bestFormat(for device: AVCaptureDevice, needsAppleLog: Bool) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let supports30fps = format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }
            let hasPhoto = !format.supportedMaxPhotoDimensions.isEmpty
            let logOK = !needsAppleLog || format.supportedColorSpaces.contains(.appleLog)
            return supports30fps && hasPhoto && logOK
        }
        return candidates.max { lhs, rhs in
            photoArea(lhs) < photoArea(rhs)
        }
    }

    private func photoArea(_ format: AVCaptureDevice.Format) -> Int {
        format.supportedMaxPhotoDimensions.reduce(0) { partial, dimensions in
            max(partial, Int(dimensions.width) * Int(dimensions.height))
        }
    }

    private func configureFormat(device: AVCaptureDevice, appleLog: Bool) throws {
        guard let format = bestFormat(for: device, needsAppleLog: appleLog) else {
            throw CameraError.formatUnavailable
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = format

        if appleLog, format.supportedColorSpaces.contains(.appleLog) {
            device.activeColorSpace = .appleLog
        } else if format.supportedColorSpaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
        }

        // 先把帧率钉到 30fps，后面手动快门才有稳定的帧时长基准
        if let range = format.videoSupportedFrameRateRanges.first(where: {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }) {
            let duration = CMTime(value: 1, timescale: 30)
            if CMTimeCompare(duration, range.minFrameDuration) >= 0,
               CMTimeCompare(duration, range.maxFrameDuration) <= 0 {
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
        }

        device.videoZoomFactor = 1
    }

    private func configureConnections() {
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.isVideoMirrored = false
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    // MARK: - 手动曝光（快门 / ISO）

    private func applyExposure() {
        let shutter = self.shutter
        let isoMode = self.isoMode
        let manualISO = Float(self.manualISO)

        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            defer { device.unlockForConfiguration() }

            let format = device.activeFormat
            let wantsManual = shutter != .auto || isoMode == .manual

            guard wantsManual else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                self.publish { self.actualExposureSeconds = nil }
                return
            }

            guard device.isExposureModeSupported(.custom) else { return }

            // 快门：拨盘指定，或（只锁 ISO 时）沿用当前自动快门
            let duration: CMTime
            if let seconds = shutter.seconds {
                duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
            } else {
                duration = device.exposureDuration
            }
            self.adjustFrameDuration(device: device, exposure: duration)

            // ISO：手动值，或沿用当前自动值并锁住
            var iso = isoMode == .manual ? manualISO : device.iso
            iso = min(max(iso, format.minISO), format.maxISO)

            device.setExposureModeCustom(duration: duration, iso: iso) { [weak self] actual in
                let seconds = CMTimeGetSeconds(actual)
                guard seconds.isFinite, seconds > 0 else { return }
                DispatchQueue.main.async {
                    self?.actualExposureSeconds = seconds
                }
            }
        }
    }

    /// 快门慢于 1/30 时必须同时拉长帧时长，否则设备会把曝光夹回帧间隔
    private func adjustFrameDuration(device: AVCaptureDevice, exposure: CMTime) {
        guard let range = device.activeFormat.videoSupportedFrameRateRanges.first else { return }
        var duration = CMTime(value: 1, timescale: 30)
        if CMTimeCompare(exposure, duration) > 0 {
            duration = exposure
        }
        if CMTimeCompare(duration, range.maxFrameDuration) > 0 {
            duration = range.maxFrameDuration
        }
        if CMTimeCompare(duration, range.minFrameDuration) < 0 {
            duration = range.minFrameDuration
        }
        if CMTimeCompare(device.activeVideoMinFrameDuration, duration) != 0 {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    private func applyExposureBias() {
        let bias = Float(exposureBias)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            defer { device.unlockForConfiguration() }
            guard device.isExposureModeSupported(.continuousAutoExposure) else { return }
            if device.exposureMode != .custom {
                device.setExposureTargetBias(bias, completionHandler: nil)
            }
        }
    }

    // MARK: - Apple Log / 模式切换

    private func applyVideoPipeline() {
        let wantLog = (mode == .video && appleLogEnabled && appleLogSupported)
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, let device = self.device else { return }
            guard !self.movieOutput.isRecording else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            do {
                try self.configureFormat(device: device, appleLog: wantLog)
            } catch {
                let message = error.localizedDescription
                self.publish { self.statusMessage = message }
                return
            }
            if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) {
                self.photoOutput.maxPhotoDimensions = largest
            }
            self.configureConnections()
            self.applyExposure()
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        guard isRunning, !isCapturing else { return }
        let look = self.look
        publish { self.isCapturing = true }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.photoOutput.connection(with: .video) != nil else {
                self.publish {
                    self.isCapturing = false
                    self.statusMessage = "相机还没准备好，稍等一下再按快门"
                }
                return
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.flashMode = .off
            settings.photoQualityPrioritization = .quality
            if self.photoOutput.maxPhotoDimensions.width > 0 {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }

            let processor = PhotoCaptureProcessor(look: look, renderer: self.renderer) { [weak self] result in
                guard let self else { return }
                self.publish {
                    self.isCapturing = false
                    switch result {
                    case .success:
                        self.showToast("已保存到相册")
                    case .failure(let error):
                        self.statusMessage = error.localizedDescription
                    }
                }
                self.sessionQueue.async {
                    self.activeProcessors.removeValue(forKey: settings.uniqueID)
                }
            }
            self.activeProcessors[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: - 录像

    func toggleRecording() {
        if isRecording {
            sessionQueue.async { [weak self] in
                guard let self, self.movieOutput.isRecording else { return }
                self.movieOutput.stopRecording()
            }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            guard !self.movieOutput.isRecording else { return }

            if self.movieOutput.connection(with: .video) == nil {
                self.session.beginConfiguration()
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
                self.session.commitConfiguration()
                self.configureConnections()
            }

            guard let connection = self.movieOutput.connection(with: .video) else {
                self.publish { self.statusMessage = "无法建立录像连接" }
                return
            }
            if self.movieOutput.availableVideoCodecTypes.contains(.hevc) {
                self.movieOutput.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.hevc],
                    for: connection
                )
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("FilmSim-\(UUID().uuidString).mov")
            self.movieOutput.maxRecordedDuration = CMTime(value: 600, timescale: 1)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func startRecordTimer() {
        recordTimer?.invalidate()
        recordTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordStartedAt else { return }
            let seconds = Int(Date().timeIntervalSince(start))
            if self.recordSeconds != seconds {
                self.recordSeconds = seconds
            }
        }
    }

    // MARK: - 对焦 / 变焦 / 换镜头

    func focus(atViewPoint point: CGPoint, viewSize: CGSize) {
        let devicePoint = convertToDevicePoint(point, viewSize: viewSize)
        let autoExposure = (shutter == .auto && isoMode == .auto)

        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                if autoExposure, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
        }

        publish {
            self.focusIndicator = point
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.focusIndicator == point else { return }
            self.focusIndicator = nil
        }
    }

    func beginZoomGesture() {
        guard !isZooming else { return }
        isZooming = true
        zoomBase = zoomFactor
    }

    func updateZoom(magnification: CGFloat) {
        let factor = min(max(zoomBase * magnification, 1), maxZoomFactor)
        applyZoom(factor)
    }

    func endZoomGesture() {
        isZooming = false
    }

    private func applyZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            // 每台设备 / 每个格式的上限不同，越界会把 AVFoundation 抛异常
            let upper = max(1, min(device.activeFormat.videoMaxZoomFactor, 6))
            let target = min(max(factor, 1), upper)
            device.videoZoomFactor = target
            device.unlockForConfiguration()
            self.publish { self.zoomFactor = target }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoInput else { return }
            guard !self.movieOutput.isRecording else { return }

            let target: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
            guard let newDevice = self.makeDevice(position: target),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            guard self.session.canAddInput(newInput) else {
                self.session.addInput(currentInput)
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(newInput)
            self.videoInput = newInput
            self.device = newDevice
            try? self.configureFormat(device: newDevice, appleLog: false)
            self.session.commitConfiguration()
            self.configureConnections()
            self.applyExposure()

            let logSupported = self.bestFormat(for: newDevice, needsAppleLog: true) != nil
            let customExposure = newDevice.isExposureModeSupported(.custom)
            let maxZoom = min(newDevice.activeFormat.videoMaxZoomFactor, 6)
            let isFront = target == .front
            self.publish {
                self.appleLogSupported = logSupported
                self.supportsCustomExposure = customExposure
                self.isFrontCamera = isFront
                self.zoomFactor = 1
                self.maxZoomFactor = maxZoom
                if !logSupported {
                    self.appleLogEnabled = false
                }
            }
        }
    }

    // MARK: - 预览挂载

    func attach(preview: PreviewRenderer) {
        self.preview = preview
        #if targetEnvironment(simulator)
        // 模拟器没有相机，推一张测试图，至少能看清界面和胶片效果
        if let image = SimulatorPreview.testImage() {
            preview.push(image)
        }
        #endif
    }

    /// 取景时使用的 look（视频 + Log 时走近似显示）
    var previewLook: FilmLook {
        var current = look
        current.logPreview = (mode == .video && appleLogEnabled && appleLogSupported)
        return current
    }

    // MARK: - 工具

    private func makeDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// 屏幕坐标 → 设备归一化坐标（考虑预览是 aspect fill 裁切过的）
    private func convertToDevicePoint(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        let videoWidth = max(videoSize.width, 1)
        let videoHeight = max(videoSize.height, 1)
        let scale = max(viewSize.width / videoWidth, viewSize.height / videoHeight)
        let displayWidth = videoWidth * scale
        let displayHeight = videoHeight * scale
        let originX = (viewSize.width - displayWidth) * 0.5
        let originY = (viewSize.height - displayHeight) * 0.5
        let x = (point.x - originX) / displayWidth
        let y = (point.y - originY) / displayHeight
        return CGPoint(x: min(max(x, 0.02), 0.98), y: min(max(y, 0.02), 0.98))
    }

    private func publish(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func showToast(_ text: String) {
        publish { self.toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.toast == text else { return }
            self.toast = nil
        }
    }

    func clearStatus() {
        statusMessage = nil
    }
}

// MARK: - 视频数据回调（实时预览）

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        // CIImage 会持有这个 CVPixelBuffer，跨线程渲染是安全的
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.videoSize != size {
                self.videoSize = size
            }
            self.preview?.push(image)
        }
    }
}

// MARK: - 录像回调

extension CameraSession: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        publish {
            self.isRecording = true
            self.recordSeconds = 0
            self.recordStartedAt = Date()
        }
        DispatchQueue.main.async { self.startRecordTimer() }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasLog = self.appleLogEnabled

            self.recordTimer?.invalidate()
            self.recordTimer = nil
            self.isRecording = false
            self.recordSeconds = 0
            self.recordStartedAt = nil

            if let error {
                // 录制被中断时文件通常仍然可用，这里只提示，不阻断保存
                self.statusMessage = "录像中断：\(error.localizedDescription)"
            }

            Task {
                do {
                    try await PhotoLibrarySaver.saveVideo(at: outputFileURL)
                    try? FileManager.default.removeItem(at: outputFileURL)
                    self.showToast(wasLog ? "Apple Log 视频已保存" : "视频已保存")
                } catch {
                    self.publish {
                        self.statusMessage = "视频保存失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
