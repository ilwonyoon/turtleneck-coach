import Foundation

/// Camera placement relative to the user.
/// Port of Python CameraPosition from camera_position.py.
enum CameraPosition: String, CaseIterable, Codable {
    case center = "center"
    case left = "left"
    case right = "right"

    var isSideView: Bool {
        self == .left || self == .right
    }

    /// Which side of the body faces the camera more directly.
    var primarySide: String {
        switch self {
        case .left:
            return "right"  // user's right side faces left-placed camera
        case .right:
            return "left"   // user's left side faces right-placed camera
        case .center:
            return "both"
        }
    }
}
