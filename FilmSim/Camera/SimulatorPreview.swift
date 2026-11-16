#if targetEnvironment(simulator)
import CoreImage
import UIKit

/// 模拟器没有相机硬件，用一张测试图代替取景画面，
/// 这样在云 Mac 上不接真机也能检查界面布局和各档胶片的效果。
/// 只在 Simulator 目标里编译，真机构建完全不受影响。
enum SimulatorPreview {

    static func testImage() -> CIImage? {
        let size = CGSize(width: 1080, height: 1440)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // 天空渐变
            let skyColors = [
                UIColor(red: 0.26, green: 0.42, blue: 0.72, alpha: 1).cgColor,
                UIColor(red: 0.96, green: 0.84, blue: 0.68, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: skyColors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: 0, y: size.height * 0.62),
                                      options: [])
            }

            // 地面
            UIColor(red: 0.30, green: 0.26, blue: 0.22, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))

            // 色彩样本：肤色 / 红 / 绿 / 蓝 / 白 / 黑
            let swatch = CGSize(width: 150, height: 150)
            let colors: [UIColor] = [
                UIColor(red: 0.94, green: 0.78, blue: 0.67, alpha: 1),
                UIColor(red: 0.80, green: 0.30, blue: 0.26, alpha: 1),
                UIColor(red: 0.26, green: 0.52, blue: 0.30, alpha: 1),
                UIColor(red: 0.22, green: 0.34, blue: 0.62, alpha: 1),
                UIColor(white: 0.93, alpha: 1),
                UIColor(white: 0.14, alpha: 1)
            ]
            for (index, color) in colors.enumerated() {
                let column = index % 3
                let row = index / 3
                let origin = CGPoint(x: 120 + CGFloat(column) * (swatch.width + 30),
                                     y: size.height * 0.66 + CGFloat(row) * (swatch.height + 30))
                color.setFill()
                cg.fill(CGRect(origin: origin, size: swatch))
            }

            // 灰阶条
            for step in 0..<8 {
                let value = CGFloat(step) / 7.0
                UIColor(white: value, alpha: 1).setFill()
                cg.fill(CGRect(x: 120 + CGFloat(step) * 105,
                               y: size.height * 0.92,
                               width: 100,
                               height: 56))
            }

            let title = "SIMULATOR TEST IMAGE" as NSString
            title.draw(at: CGPoint(x: 120, y: 120), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ])

            let subtitle = "no camera on simulator · use TestFlight on device" as NSString
            subtitle.draw(at: CGPoint(x: 120, y: 175), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ])
        }

        return CIImage(image: image)
    }
}
#endif
