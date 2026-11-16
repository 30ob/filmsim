import Foundation
import Photos
import UIKit

// MARK: - 保存到相册

enum PhotoLibrarySaver {

    enum SaverError: LocalizedError {
        case denied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "没有相册权限，请在「设置 → 胶片模拟 → 照片」里允许添加"
            case .saveFailed(let message):
                return "保存失败：\(message)"
            }
        }
    }

    /// 照片数据（JPEG）
    static func savePhoto(_ data: Data) async throws {
        guard await ensureAuthorization() else { throw SaverError.denied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = "public.jpeg"
                request.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaverError.saveFailed(error?.localizedDescription ?? "未知错误"))
                }
            }
        }
    }

    /// 视频文件
    static func saveVideo(at url: URL) async throws {
        guard await ensureAuthorization() else { throw SaverError.denied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaverError.saveFailed(error?.localizedDescription ?? "未知错误"))
                }
            }
        }
    }

    private static func ensureAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let newStatus = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }
}
