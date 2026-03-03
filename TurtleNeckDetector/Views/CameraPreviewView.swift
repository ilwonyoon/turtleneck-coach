import SwiftUI

/// Shows the latest camera frame with skeleton overlay drawn on top.
struct CameraPreviewView: View {
    let frame: CGImage?
    let joints: DetectedJoints?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Camera frame (already rotated to landscape by CameraManager)
                if let frame {
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .scaleEffect(x: -1, y: 1)  // Mirror horizontally for selfie view
                } else {
                    Rectangle()
                        .fill(Color.black)
                    Text("Starting camera...")
                        .foregroundColor(.gray)
                        .font(.caption)
                }

                // Skeleton overlay
                if let joints {
                    SkeletonOverlay(joints: joints)
                }
            }
        }
    }
}

/// Draws pose skeleton lines and joint dots on top of camera feed.
struct SkeletonOverlay: View {
    let joints: DetectedJoints

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Mirror X to match the horizontally-mirrored camera image
            let pointMap = Dictionary(uniqueKeysWithValues: joints.allPoints.map { (name, pt) in
                (name, CGPoint(x: (1 - pt.x) * w, y: pt.y * h))
            })

            Canvas { context, size in
                // Draw connection lines
                for (from, to) in DetectedJoints.connections {
                    guard let p1 = pointMap[from], let p2 = pointMap[to] else { continue }
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 2)
                }

                // Draw joint dots
                for (_, point) in pointMap {
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)))
                    let outerRect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                    context.stroke(Path(ellipseIn: outerRect), with: .color(.white.opacity(0.4)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
