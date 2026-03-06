import Foundation
import CoreGraphics

enum CameraContext: String, Codable, CaseIterable {
    case desktop
    case laptop
    case unknown

    var displayName: String {
        switch self {
        case .desktop: return "Desktop"
        case .laptop: return "Laptop"
        case .unknown: return "Unknown"
        }
    }
}

enum LaptopSubcontext: String, Codable, CaseIterable {
    case neutral
    case tiltBack
    case tooNear
    case tooFar
    case unknown

    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .tiltBack: return "Tilt Back"
        case .tooNear: return "Too Near"
        case .tooFar: return "Too Far"
        case .unknown: return "Unknown"
        }
    }
}

enum CameraContextSelection: String, Codable, CaseIterable {
    case auto
    case desktop
    case laptop

    var displayName: String {
        switch self {
        case .auto: return "Auto (Recommended)"
        case .desktop: return "Desktop (Manual)"
        case .laptop: return "Laptop (Manual)"
        }
    }
}

struct CameraContextInference: Equatable {
    let context: CameraContext
    let confidence: CGFloat
    let subcontext: LaptopSubcontext
    let source: String
    let faceSizeRatio: CGFloat
    let reasons: [String]
}
