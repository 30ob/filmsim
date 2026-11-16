import CoreImage
import Metal
import UIKit

// MARK: - 用户可调参数 + 胶片选择

struct FilmLook: Equatable {
    var stock: FilmStock = .provia
    /// 曝光补偿，单位 EV
    var exposureEV: Double = 0
    /// 白平衡偏移：x = 红↔青（-1…1），y = 蓝↔黄（-1…1）
    var wbShift: CGPoint = .zero
    /// 颗粒强度倍率
    var grain: Double = 1
    /// 褪色（提黑位）
    var fade: Double = 0
    /// 暗角倍率
    var vignette: Double = 1
    /// 饱和倍率
    var saturation: Double = 1
    /// 是否走 Apple Log 的近似显示（仅预览用，不影响录制）
    var logPreview: Bool = false
}

// MARK: - 渲染器

/// 把 CIImage 渲染成带胶片外观的 CIImage。
/// 同一个 `CIContext` 同时给实时预览和照片输出使用，保证「所见即所得」。
final class FilmRenderer {
    let context: CIContext
    /// sRGB，用于最终输出（相册里颜色不会漂）
    let srgbColorSpace: CGColorSpace
    /// DeviceRGB，用于 Metal 预览贴图
    let previewColorSpace: CGColorSpace

    init() {
        srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        previewColorSpace = CGColorSpaceCreateDeviceRGB()
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.useSoftwareRenderer: true])
        }
    }

    // MARK: 主入口

    func render(_ input: CIImage, look: FilmLook) -> CIImage {
        let extent = input.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width >= 1, extent.height >= 1 else {
            return input
        }

        if look.logPreview {
            return logDisplayTransform(input).cropped(to: extent)
        }

        let profile = look.stock.profile
        var image = input

        // 1. 黑白底板
        if let mono = profile.monochromeFilter {
            image = image.applyingFilter(mono)
        }

        // 2. 白平衡（胶片自带的色温 + 用户 R/B 偏移）
        image = image.applyingFilter("CIColorMatrix", parameters: whiteBalanceParameters(profile: profile, shift: look.wbShift))

        // 3. 曝光
        if abs(look.exposureEV) > 0.01 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": look.exposureEV])
        }

        // 4. 通道混合（色彩串扰 / 色相性格）
        image = image.applyingFilter("CIColorMatrix", parameters: profile.colorMatrixParameters)

        // 5. 特性曲线（含褪色提黑位）
        image = image.applyingFilter("CIToneCurve", parameters: toneCurveParameters(profile: profile, fade: look.fade))

        // 6. 饱和度 / 自然饱和度
        let saturation = max(0.0, profile.saturation * look.saturation)
        image = image.applyingFilter("CIColorControls", parameters: ["inputSaturation": saturation])
        if abs(profile.vibrance) > 0.001 {
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": profile.vibrance * look.saturation])
        }

        // 7. 高光溢出（halation）
        if profile.halation > 0.01, image.extent.width > 1 {
            let radius = Float(min(extent.width, extent.height) * 0.015)
            image = image.applyingFilter("CIBloom", parameters: [
                "inputRadius": radius,
                "inputIntensity": profile.halation
            ])
        }

        // 8. 颗粒
        if let grain = grainLayer(extent: extent, amount: profile.grain * look.grain) {
            image = grain.applyingFilter("CISoftLightBlendMode", parameters: ["inputBackgroundImage": image])
        }

        // 9. 暗角
        if let vignette = vignetteLayer(extent: extent, strength: profile.vignette * look.vignette) {
            image = vignette.applyingFilter("CIMultiplyCompositing", parameters: ["inputBackgroundImage": image])
        }

        // 10. 收尾：裁掉负值、限制在 0…1
        image = image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])

        return image.cropped(to: extent)
    }

    // MARK: 编码

    func jpegData(_ image: CIImage, quality: CGFloat = 0.95) -> Data? {
        let rect = image.extent
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        guard let cg = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: srgbColorSpace) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    // MARK: - 内部参数

    private func whiteBalanceParameters(profile: FilmProfile, shift: CGPoint) -> [String: Any] {
        let red = 1.0 + profile.warmth * 0.5 + Double(shift.x) * 0.15
        let blue = 1.0 - profile.warmth * 0.5 + Double(shift.y) * 0.15
        return gainMatrix(red: red, green: 1.0, blue: blue)
    }

    private func gainMatrix(red: Double, green: Double, blue: Double) -> [String: Any] {
        let r = min(max(red, 0.5), 1.6)
        let g = min(max(green, 0.5), 1.6)
        let b = min(max(blue, 0.5), 1.6)
        return [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]
    }

    private func toneCurveParameters(profile: FilmProfile, fade: Double) -> [String: Any] {
        let points = profile.curve.count == 5 ? profile.curve : [0, 0.25, 0.5, 0.75, 1]
        let xs: [Double] = [0, 0.25, 0.5, 0.75, 1]
        // 褪色 = 把整条曲线向上抬一点，黑位不再死黑
        let lift = 0.10 * min(max(fade, 0), 1)
        var parameters: [String: Any] = [:]
        for index in 0..<5 {
            let y = min(max(lift + points[index] * (1 - lift), 0), 1)
            parameters["inputPoint\(index)"] = CIVector(x: xs[index], y: y)
        }
        return parameters
    }

    /// 生成一层灰度噪点，并压到 0.5 附近，方便用柔光叠加
    private func grainLayer(extent: CGRect, amount: Double) -> CIImage? {
        let strength = min(max(amount, 0), 1)
        guard strength > 0.01 else { return nil }
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }

        // 放大噪点 → 更像胶片颗粒而不是数码噪点
        let scaled = noise.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        let luma = scaled.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.34, y: 0.34, z: 0.34, w: 0),
            "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        let amplitude = 0.5 * strength
        let bias = 0.5 - amplitude * 0.5
        let adjusted = luma.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amplitude, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ])
        return adjusted.cropped(to: extent)
    }

    /// 径向渐变当暗角遮罩，中心白、边角压暗
    private func vignetteLayer(extent: CGRect, strength: Double) -> CIImage? {
        let s = min(max(strength, 0), 1)
        guard s > 0.01 else { return nil }
        let level = 1.0 - s * 0.55
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputRadius0": Float(min(extent.width, extent.height) * 0.45),
            "inputRadius1": Float(max(extent.width, extent.height) * 0.72),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputColor1": CIColor(red: level, green: level, blue: level, alpha: 1)
        ]) else { return nil }
        return gradient.outputImage?.cropped(to: extent)
    }

    /// Apple Log 的近似显示变换（只给预览看，录制文件保持原始 Log）
    private func logDisplayTransform(_ input: CIImage) -> CIImage {
        var image = input.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0.02),
            "inputPoint1": CIVector(x: 0.25, y: 0.30),
            "inputPoint2": CIVector(x: 0.5, y: 0.55),
            "inputPoint3": CIVector(x: 0.75, y: 0.80),
            "inputPoint4": CIVector(x: 1, y: 1.0)
        ])
        image = image.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 1.15,
            "inputContrast": 1.02
        ])
        return image
    }
}
