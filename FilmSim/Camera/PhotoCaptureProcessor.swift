import AVFoundation
import CoreImage
import Foundation

/// 拿到一张全分辨率照片 → 套胶片模拟 → 编码 JPEG → 存相册。
/// 每次拍照都会新建一个实例，拍完即弃。
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let look: FilmLook
    private let renderer: FilmRenderer
    private let completion: (Result<Void, Error>) -> Void
    private var hasFinished = false

    init(look: FilmLook,
         renderer: FilmRenderer,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.look = look
        self.renderer = renderer
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              var source = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            finish(.failure(CameraError.photoProcessingFailed))
            return
        }

        // 内存保护：超过 3000 万像素先等比降采样（4800 万像素的 RAW/HEIF 在旧机器上会吃爆内存）
        let maxPixels: CGFloat = 30_000_000
        let pixels = source.extent.width * source.extent.height
        if pixels > maxPixels {
            let scale = (maxPixels / pixels).squareRoot()
            source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let look = self.look
        let renderer = self.renderer

        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = renderer.render(source, look: look)
            guard let jpeg = renderer.jpegData(rendered) else {
                self.finish(.failure(CameraError.photoProcessingFailed))
                return
            }
            Task {
                do {
                    try await PhotoLibrarySaver.savePhoto(jpeg)
                    self.finish(.success(()))
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        completion(result)
    }
}
