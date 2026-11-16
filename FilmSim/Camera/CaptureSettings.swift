import Foundation

// MARK: - 快门速度

/// 快门档位，整档排列，和胶片机拨盘一致（另有 A 自动档）
enum ShutterSpeed: String, CaseIterable, Identifiable, Hashable {
    case auto
    case s1, s2, s4, s8, s15, s30, s60, s125, s250, s500, s1000, s2000, s4000, s8000

    var id: String { rawValue }

    /// 分母（秒的倒数）。自动档为 nil
    var denominator: Int? {
        switch self {
        case .auto:   return nil
        case .s1:     return 1
        case .s2:     return 2
        case .s4:     return 4
        case .s8:     return 8
        case .s15:    return 15
        case .s30:    return 30
        case .s60:    return 60
        case .s125:   return 125
        case .s250:   return 250
        case .s500:   return 500
        case .s1000:  return 1000
        case .s2000:  return 2000
        case .s4000:  return 4000
        case .s8000:  return 8000
        }
    }

    /// 曝光时长（秒）。自动档返回 nil
    var seconds: Double? {
        guard let d = denominator else { return nil }
        return 1.0 / Double(d)
    }

    /// 拨盘标题
    var label: String {
        guard let d = denominator else { return "A" }
        return d == 1 ? "1″" : "1/\(d)"
    }

    /// 拨盘副标题
    var caption: String {
        guard let d = denominator else { return "AUTO" }
        if d == 1 { return "1 秒" }
        if d <= 30 { return "长曝" }
        return " "
    }

    /// 快门越慢越靠前，方便在拨盘上从左到右由慢到快
    static var dialOrder: [ShutterSpeed] {
        [.auto, .s1, .s2, .s4, .s8, .s15, .s30, .s60, .s125, .s250, .s500, .s1000, .s2000, .s4000, .s8000]
    }
}

// MARK: - ISO

enum ISOMode: String, CaseIterable, Identifiable, Hashable {
    case auto
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "AUTO"
        case .manual: return "手动"
        }
    }
}

// MARK: - 拍摄模式

enum CaptureMode: String, CaseIterable, Identifiable, Hashable {
    case photo
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "照片"
        case .video: return "视频"
        }
    }
}
