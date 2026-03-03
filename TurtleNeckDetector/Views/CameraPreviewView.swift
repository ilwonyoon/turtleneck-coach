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

/// Draws pose skeleton and face mesh on top of camera feed.
/// When MediaPipe face mesh is available, renders full 478-point tessellation wireframe.
/// Falls back to simple joint dots + lines for Vision framework.
struct SkeletonOverlay: View {
    let joints: DetectedJoints

    // Key landmark groups for feature highlighting
    private static let leftEyeIndices = [33, 7, 163, 144, 145, 153, 154, 155, 133]
    private static let rightEyeIndices = [362, 382, 381, 380, 374, 373, 390, 249, 263]
    private static let lipsOuterIndices = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185, 61]
    private static let lipsInnerIndices = [78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95, 78]
    private static let faceOvalIndices = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10,
    ]

    /// Build a set of edges that belong to highlighted features (eyes, lips, oval)
    /// so we can draw them with different colors/widths.
    private static let featureEdges: Set<UInt64> = {
        var set = Set<UInt64>()
        func addPolyEdges(_ indices: [Int]) {
            for i in 0..<(indices.count - 1) {
                let a = min(indices[i], indices[i + 1])
                let b = max(indices[i], indices[i + 1])
                set.insert(UInt64(a) << 16 | UInt64(b))
            }
        }
        addPolyEdges(leftEyeIndices)
        addPolyEdges(rightEyeIndices)
        addPolyEdges(lipsOuterIndices)
        addPolyEdges(lipsInnerIndices)
        addPolyEdges(faceOvalIndices)
        return set
    }()

    private static func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
        let lo = min(a, b)
        let hi = max(a, b)
        return UInt64(lo) << 16 | UInt64(hi)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { context, _ in
                // Helper: convert normalized point to screen coords (mirrored)
                let toScreen: (CGPoint) -> CGPoint = { pt in
                    CGPoint(x: (1 - pt.x) * w, y: pt.y * h)
                }

                let pointMap = Dictionary(uniqueKeysWithValues: joints.allPoints.map { (name, pt) in
                    (name, toScreen(pt))
                })

                // --- Full Face Mesh Tessellation (MediaPipe) with depth-aware rendering ---
                if let mesh = joints.faceMesh, mesh.landmarks.count >= 468 {
                    // Pre-compute all screen points from landmarks
                    let screenPts = mesh.landmarks.map { toScreen($0) }

                    // Compute depth normalization range for 3D-aware rendering
                    let hasDepth = !mesh.depthValues.isEmpty
                    let minZ = hasDepth ? (mesh.depthValues.min() ?? 0) : 0
                    let maxZ = hasDepth ? (mesh.depthValues.max() ?? 1) : 1
                    let zRange = max(0.001, maxZ - minZ)

                    // Draw tessellation edges with depth-based opacity and line width
                    // Closer edges are brighter/thicker, far edges (back of head) are culled
                    var tessPath = Path()
                    var featurePath = Path()

                    for (a, b) in FaceMeshData.tessellationEdges {
                        guard a < screenPts.count, b < screenPts.count else { continue }

                        // Depth-based back-face culling: skip edges on far side of face
                        if hasDepth, a < mesh.depthValues.count, b < mesh.depthValues.count {
                            let avgZ = (mesh.depthValues[a] + mesh.depthValues[b]) / 2
                            let depthNorm = (avgZ - minZ) / zRange  // 0=closest, 1=farthest
                            if depthNorm > 0.85 { continue }

                            let p1 = screenPts[a]
                            let p2 = screenPts[b]

                            if Self.featureEdges.contains(Self.edgeKey(a, b)) {
                                // Feature edges: depth modulates opacity (0.4–0.8)
                                let opacity = 0.4 + (1.0 - depthNorm) * 0.4
                                let lineWidth = 0.8 + (1.0 - depthNorm) * 0.6
                                var path = Path()
                                path.move(to: p1)
                                path.addLine(to: p2)
                                context.stroke(path, with: .color(Color.cyan.opacity(opacity)), lineWidth: lineWidth)
                            } else {
                                // Tessellation edges: depth modulates opacity (0.1–0.35)
                                let opacity = 0.1 + (1.0 - depthNorm) * 0.25
                                let lineWidth = 0.3 + (1.0 - depthNorm) * 0.4
                                var path = Path()
                                path.move(to: p1)
                                path.addLine(to: p2)
                                context.stroke(path, with: .color(Color.cyan.opacity(opacity)), lineWidth: lineWidth)
                            }
                        } else {
                            // No depth data — fall back to flat rendering
                            let p1 = screenPts[a]
                            let p2 = screenPts[b]
                            if Self.featureEdges.contains(Self.edgeKey(a, b)) {
                                featurePath.move(to: p1)
                                featurePath.addLine(to: p2)
                            } else {
                                tessPath.move(to: p1)
                                tessPath.addLine(to: p2)
                            }
                        }
                    }

                    // Render any remaining flat paths (fallback when no depth)
                    if !tessPath.isEmpty {
                        context.stroke(tessPath, with: .color(Color.cyan.opacity(0.25)), lineWidth: 0.5)
                    }
                    if !featurePath.isEmpty {
                        context.stroke(featurePath, with: .color(Color.cyan.opacity(0.7)), lineWidth: 1.2)
                    }

                    // Body skeleton — styled to match face mesh aesthetic
                    let bodyConnections: [(from: String, to: String)] = [
                        ("nose", "neck"),
                        ("neck", "leftShoulder"),
                        ("neck", "rightShoulder"),
                        ("leftShoulder", "rightShoulder"),
                        ("leftEar", "leftEye"),
                        ("rightEar", "rightEye"),
                    ]

                    // Glow layer (wider, translucent cyan)
                    for conn in bodyConnections {
                        guard let p1 = pointMap[conn.from], let p2 = pointMap[conn.to] else { continue }
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        context.stroke(path, with: .color(Color.cyan.opacity(0.15)), lineWidth: 6)
                    }

                    // Main body lines (solid cyan, matching mesh color)
                    for conn in bodyConnections {
                        guard let p1 = pointMap[conn.from], let p2 = pointMap[conn.to] else { continue }
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        context.stroke(path, with: .color(Color.cyan.opacity(0.7)), lineWidth: 2.5)
                    }

                    // Joint dots with glow — larger for key joints, smaller for secondary
                    let majorJoints = ["neck", "leftShoulder", "rightShoulder"]
                    let minorJoints = ["nose", "leftEar", "rightEar", "leftEye", "rightEye"]

                    for name in majorJoints {
                        guard let pt = pointMap[name] else { continue }
                        // Outer glow
                        let glowRect = CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)
                        context.fill(Path(ellipseIn: glowRect), with: .color(Color.cyan.opacity(0.15)))
                        // Dot
                        let dotRect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                        context.fill(Path(ellipseIn: dotRect), with: .color(Color.cyan.opacity(0.8)))
                        // Inner bright center
                        let innerRect = CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.9)))
                    }

                    for name in minorJoints {
                        guard let pt = pointMap[name] else { continue }
                        let dotRect = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: dotRect), with: .color(Color.cyan.opacity(0.6)))
                        let innerRect = CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)
                        context.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.7)))
                    }

                } else {
                    // --- Fallback: simple skeleton (Vision framework) ---
                    for (from, to) in DetectedJoints.connections {
                        guard let p1 = pointMap[from], let p2 = pointMap[to] else { continue }
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 2)
                    }

                    for (_, point) in pointMap {
                        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)))
                        let outerRect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                        context.stroke(Path(ellipseIn: outerRect), with: .color(.white.opacity(0.4)), lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
