import Foundation
import CoreGraphics

enum CameraContext: String, Codable, CaseIterable {
    case aboveEye = "desktop"
    case eyeLevel = "eyeLevel"
    case belowEye = "laptop"
    case unknown

    var displayName: String {
        switch self {
        case .aboveEye:
            return "Above Eye Level"
        case .eyeLevel:
            return "Eye Level"
        case .belowEye:
            return "Below Eye Level"
        case .unknown:
            return "Checking"
        }
    }

    var compactDisplayName: String {
        switch self {
        case .aboveEye:
            return "Above Eye"
        case .eyeLevel:
            return "Eye Level"
        case .belowEye:
            return "Below Eye"
        case .unknown:
            return "Checking"
        }
    }

    var exampleDescription: String {
        switch self {
        case .aboveEye:
            return "Usually a separate monitor or webcam above the screen."
        case .eyeLevel:
            return "Usually a raised laptop or monitor near your eye line."
        case .belowEye:
            return "Usually a laptop sitting on the desk."
        case .unknown:
            return "Choose the closest match for your usual working setup."
        }
    }
}

enum FramingState: String, Codable, CaseIterable {
    case stable
    case tiltedBack
    case tooNear
    case tooFar
    case checking

    var displayName: String {
        switch self {
        case .stable:
            return "Stable"
        case .tiltedBack:
            return "Tilted Back"
        case .tooNear:
            return "Too Near"
        case .tooFar:
            return "Too Far"
        case .checking:
            return "Checking"
        }
    }
}

struct CameraContextInference: Equatable {
    let context: CameraContext
    let confidence: CGFloat
    let framingState: FramingState
    let source: String
    let faceSizeRatio: CGFloat
    let reasons: [String]
}
