import CoreImage
import SwiftUI

// MARK: - 胶片外观参数

/// 一套「胶片外观」的完整参数。渲染顺序：
/// 黑白 → 白平衡 → 曝光 → 通道混合 → 曲线 → 饱和/自然饱和度 → 光晕 → 颗粒 → 暗角
struct FilmProfile {
    /// 一句话风格说明
    var tagline: String = ""

    /// 通道混合矩阵，列主序，对应 CIColorMatrix 的 R/G/B 向量：
    /// [R→R, R→G, R→B,  G→R, G→G, G→B,  B→R, B→G, B→B]
    var matrix: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    /// 加性偏移，用来做「阴影偏青」「高光偏暖」这类整体色偏
    var bias: [Double] = [0, 0, 0]

    /// CIToneCurve 的 5 个控制点 y 值（x 固定为 0 / 0.25 / 0.5 / 0.75 / 1）
    var curve: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var saturation: Double = 1
    var vibrance: Double = 0

    /// 内置黑白滤镜（CIPhotoEffectNoir 等），nil 表示彩色
    var monochromeFilter: String? = nil

    /// 胶片自带的色温倾向：+1 偏暖，-1 偏冷
    var warmth: Double = 0

    /// 0…1，最终会乘以用户颗粒强度
    var grain: Double = 0.32
    /// 0…1，最终会乘以用户暗角强度
    var vignette: Double = 0.18
    /// 0…1，高光溢出（halation）强度
    var halation: Double = 0

    /// 组装成 CIColorMatrix 参数字典
    var colorMatrixParameters: [String: Any] {
        let m = matrix.count == 9 ? matrix : [1, 0, 0, 0, 1, 0, 0, 0, 1]
        let b = bias.count == 3 ? bias : [0, 0, 0]
        return [
            "inputRVector": CIVector(x: m[0], y: m[1], z: m[2], w: 0),
            "inputGVector": CIVector(x: m[3], y: m[4], z: m[5], w: 0),
            "inputBVector": CIVector(x: m[6], y: m[7], z: m[8], w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: b[0], y: b[1], z: b[2], w: 0)
        ]
    }
}

// MARK: - 胶片种类

enum FilmStock: String, CaseIterable, Identifiable, Codable {
    case provia
    case velvia
    case astia
    case classicChrome
    case classicNeg
    case proNegHi
    case proNegStd
    case eterna
    case acros
    case monochrome
    case sepia

    var id: String { rawValue }

    /// 拨盘上的英文名（仿胶片盒标识）
    var name: String {
        switch self {
        case .provia:          return "PROVIA"
        case .velvia:          return "VELVIA"
        case .astia:           return "ASTIA"
        case .classicChrome:   return "CLASSIC CHROME"
        case .classicNeg:      return "CLASSIC NEG"
        case .proNegHi:        return "PRO NEG Hi"
        case .proNegStd:       return "PRO NEG Std"
        case .eterna:          return "ETERNA"
        case .acros:           return "ACROS"
        case .monochrome:      return "MONOCHROME"
        case .sepia:           return "SEPIA"
        }
    }

    var chineseName: String {
        switch self {
        case .provia:          return "标准"
        case .velvia:          return "鲜艳"
        case .astia:           return "柔和"
        case .classicChrome:   return "经典铬"
        case .classicNeg:      return "经典负片"
        case .proNegHi:        return "人像高反差"
        case .proNegStd:       return "人像标准"
        case .eterna:          return "电影"
        case .acros:           return "黑白 ACROS"
        case .monochrome:      return "单色"
        case .sepia:           return "棕褐"
        }
    }

    /// 拨盘高亮色
    var accent: Color {
        switch self {
        case .provia:          return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .velvia:          return Color(red: 0.95, green: 0.35, blue: 0.22)
        case .astia:           return Color(red: 0.96, green: 0.72, blue: 0.62)
        case .classicChrome:   return Color(red: 0.55, green: 0.72, blue: 0.80)
        case .classicNeg:      return Color(red: 0.93, green: 0.68, blue: 0.30)
        case .proNegHi:        return Color(red: 0.94, green: 0.62, blue: 0.55)
        case .proNegStd:       return Color(red: 0.85, green: 0.80, blue: 0.70)
        case .eterna:          return Color(red: 0.42, green: 0.72, blue: 0.70)
        case .acros:           return Color(red: 0.82, green: 0.82, blue: 0.82)
        case .monochrome:      return Color(red: 0.68, green: 0.68, blue: 0.68)
        case .sepia:           return Color(red: 0.75, green: 0.60, blue: 0.42)
        }
    }

    var profile: FilmProfile {
        switch self {
        // 通用标准：中性、轻微 S 曲线、细腻颗粒
        case .provia:
            return FilmProfile(
                tagline: "中性通透，最接近人眼所见的万能档",
                matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                curve: [0.010, 0.245, 0.500, 0.762, 0.990],
                saturation: 1.04, vibrance: 0.04,
                warmth: 0.00, grain: 0.30, vignette: 0.18
            )

        // 高饱和风光：红绿更厚、蓝更透，反差强
        case .velvia:
            return FilmProfile(
                tagline: "高饱和风光档，红绿浓郁、天空更蓝",
                matrix: [1.10, -0.03, -0.02,
                         -0.05, 1.06, -0.03,
                         -0.02, -0.05, 1.12],
                curve: [0.000, 0.192, 0.487, 0.838, 1.000],
                saturation: 1.20, vibrance: 0.16,
                warmth: 0.03, grain: 0.26, vignette: 0.22, halation: 0.06
            )

        // 柔和：低反差、肤色友好
        case .astia:
            return FilmProfile(
                tagline: "柔和人像档，肤色干净、反差克制",
                matrix: [1.02, 0.00, 0.00,
                         0.02, 0.99, 0.00,
                         0.00, 0.01, 1.01],
                curve: [0.022, 0.262, 0.508, 0.748, 0.982],
                saturation: 0.96, vibrance: 0.05,
                warmth: 0.05, grain: 0.30, vignette: 0.14
            )

        // 经典铬：低饱和、青调阴影、数码感弱
        case .classicChrome:
            return FilmProfile(
                tagline: "褪色纪录片感，青调阴影、红黄内敛",
                matrix: [0.96, 0.02, 0.01,
                         0.01, 0.98, 0.03,
                         0.00, 0.04, 1.02],
                curve: [0.030, 0.212, 0.478, 0.792, 0.968],
                saturation: 0.72, vibrance: -0.05,
                warmth: -0.04, grain: 0.40, vignette: 0.28
            )

        // 经典负片：琥珀高光 + 洋红阴影，反差大
        case .classicNeg:
            return FilmProfile(
                tagline: "复古负片味，琥珀高光、洋红阴影",
                matrix: [1.03, -0.02, 0.01,
                         -0.01, 1.00, 0.00,
                         0.00, -0.03, 1.06],
                curve: [0.048, 0.198, 0.468, 0.802, 0.982],
                saturation: 0.88, vibrance: 0.02,
                warmth: 0.10, grain: 0.46, vignette: 0.30, halation: 0.10
            )

        // 人像高反差
        case .proNegHi:
            return FilmProfile(
                tagline: "人像工作室档，肤色微暖、立体感强",
                matrix: [1.03, 0.01, 0.00,
                         0.00, 1.00, 0.00,
                         -0.01, 0.01, 0.99],
                curve: [0.015, 0.238, 0.500, 0.778, 0.988],
                saturation: 1.02, vibrance: 0.04,
                warmth: 0.05, grain: 0.26, vignette: 0.14
            )

        // 人像标准：平、软、留后期空间
        case .proNegStd:
            return FilmProfile(
                tagline: "平缓低反差，给后期留足空间",
                matrix: [1.01, 0.00, 0.00,
                         0.00, 1.00, 0.00,
                         0.00, 0.00, 0.99],
                curve: [0.032, 0.268, 0.518, 0.738, 0.952],
                saturation: 0.90, vibrance: 0.00,
                warmth: 0.01, grain: 0.24, vignette: 0.12
            )

        // 电影：青绿阴影、低饱和、柔和滚降
        case .eterna:
            return FilmProfile(
                tagline: "电影胶片感，青绿阴影、柔和滚降",
                matrix: [0.98, 0.02, 0.02,
                         0.01, 1.00, 0.02,
                         0.00, 0.05, 1.03],
                curve: [0.078, 0.300, 0.528, 0.720, 0.895],
                saturation: 0.78, vibrance: 0.00,
                warmth: -0.03, grain: 0.32, vignette: 0.18, halation: 0.12
            )

        // 黑白 ACROS：厚重中间调
        case .acros:
            return FilmProfile(
                tagline: "ACROS 黑白，深中间调、极细腻颗粒",
                curve: [0.000, 0.222, 0.488, 0.788, 1.000],
                saturation: 1.0, vibrance: 0.0,
                monochromeFilter: "CIPhotoEffectNoir",
                warmth: 0.02, grain: 0.50, vignette: 0.26
            )

        // 普通单色
        case .monochrome:
            return FilmProfile(
                tagline: "标准黑白，反差中性",
                curve: [0.018, 0.252, 0.500, 0.748, 0.978],
                saturation: 1.0, vibrance: 0.0,
                monochromeFilter: "CIPhotoEffectMono",
                warmth: 0.00, grain: 0.42, vignette: 0.22
            )

        // 棕褐
        case .sepia:
            return FilmProfile(
                tagline: "棕褐调，老照片的暖色余韵",
                matrix: [1.04, 0.01, 0.00,
                         0.01, 1.00, 0.00,
                         0.00, 0.00, 0.96],
                curve: [0.060, 0.270, 0.512, 0.742, 0.940],
                saturation: 1.0, vibrance: 0.0,
                monochromeFilter: "CIPhotoEffectTransfer",
                warmth: 0.06, grain: 0.44, vignette: 0.26
            )
        }
    }
}
