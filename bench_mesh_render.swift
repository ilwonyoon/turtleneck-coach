import Foundation

// MARK: - Data Types

struct Vec2 {
    let x: Double
    let y: Double
}

struct Edge {
    let from: Int
    let to: Int
}

struct LineSegment {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
}

// MARK: - Data Generation

func generateRandomPoints(count: Int) -> [Vec2] {
    return (0..<count).map { _ in
        Vec2(x: Double.random(in: 0...400), y: Double.random(in: 0...400))
    }
}

func generateRandomDepths(count: Int) -> [Double] {
    return (0..<count).map { _ in Double.random(in: 0.0...1.0) }
}

func generateRandomEdges(count: Int, maxIndex: Int) -> [Edge] {
    return (0..<count).map { _ in
        Edge(from: Int.random(in: 0..<maxIndex), to: Int.random(in: 0..<maxIndex))
    }
}

// MARK: - Depth Band Classification

enum DepthBand: Int, CaseIterable {
    case near = 0
    case mid  = 1
    case far  = 2
}

@inline(__always)
func classifyDepth(_ depth: Double) -> DepthBand {
    if depth < 0.33 { return .near }
    if depth < 0.66 { return .mid }
    return .far
}

@inline(__always)
func edgeDepth(edge: Edge, depths: [Double]) -> Double {
    return (depths[edge.from] + depths[edge.to]) * 0.5
}

// MARK: - Simulation: OLD per-edge approach

struct OldApproachResult {
    let pathsCreated: Int
    let strokeCalls: Int
}

func simulateOldApproach(edgeCount: Int) -> OldApproachResult {
    return OldApproachResult(pathsCreated: edgeCount, strokeCalls: edgeCount)
}

// MARK: - Simulation: NEW batched depth-band approach

struct NewApproachResult {
    let pathsCreated: Int
    let strokeCalls: Int
    let bandCounts: [(String, Int)]
}

func simulateNewApproach(
    tessellationEdges: [Edge],
    featureEdges: [Edge],
    depths: [Double]
) -> NewApproachResult {
    var tessNear = 0, tessMid = 0, tessFar = 0
    var featNear = 0, featMid = 0, featFar = 0

    for edge in tessellationEdges {
        let d = edgeDepth(edge: edge, depths: depths)
        switch classifyDepth(d) {
        case .near: tessNear += 1
        case .mid:  tessMid += 1
        case .far:  tessFar += 1
        }
    }

    for edge in featureEdges {
        let d = edgeDepth(edge: edge, depths: depths)
        switch classifyDepth(d) {
        case .near: featNear += 1
        case .mid:  featMid += 1
        case .far:  featFar += 1
        }
    }

    let pathsCreated = 6
    var strokeCalls = 0
    if tessNear > 0 { strokeCalls += 1 }
    if tessMid > 0  { strokeCalls += 1 }
    if tessFar > 0  { strokeCalls += 1 }
    if featNear > 0 { strokeCalls += 1 }
    if featMid > 0  { strokeCalls += 1 }
    if featFar > 0  { strokeCalls += 1 }

    let bandCounts: [(String, Int)] = [
        ("feat_near", featNear),
        ("feat_mid",  featMid),
        ("feat_far",  featFar),
        ("tess_near", tessNear),
        ("tess_mid",  tessMid),
        ("tess_far",  tessFar),
    ]

    return NewApproachResult(
        pathsCreated: pathsCreated,
        strokeCalls: strokeCalls,
        bandCounts: bandCounts
    )
}

// MARK: - Benchmark: edge classification + path accumulation

func benchmarkClassification(
    edges: [Edge],
    depths: [Double],
    iterations: Int
) -> (totalSeconds: Double, perIterationMicros: Double) {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        var nearSegments = [LineSegment]()
        var midSegments  = [LineSegment]()
        var farSegments  = [LineSegment]()
        nearSegments.reserveCapacity(edges.count / 3)
        midSegments.reserveCapacity(edges.count / 3)
        farSegments.reserveCapacity(edges.count / 3)

        for edge in edges {
            let d = edgeDepth(edge: edge, depths: depths)
            let seg = LineSegment(
                x1: Double(edge.from), y1: Double(edge.from),
                x2: Double(edge.to),   y2: Double(edge.to)
            )
            switch classifyDepth(d) {
            case .near: nearSegments.append(seg)
            case .mid:  midSegments.append(seg)
            case .far:  farSegments.append(seg)
            }
        }
        // Prevent optimizer from eliminating the work
        _blackHole(nearSegments.count + midSegments.count + farSegments.count)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let perIteration = (elapsed / Double(iterations)) * 1_000_000
    return (elapsed, perIteration)
}

// MARK: - Benchmark: path object creation overhead

func benchmarkPathCreation(
    edges: [Edge],
    points: [Vec2],
    depths: [Double],
    iterations: Int
) -> (oldMicros: Double, newMicros: Double) {
    // OLD: one array (simulating Path) per edge, add 2 points each
    let startOld = CFAbsoluteTimeGetCurrent()
    var oldSink = 0
    for _ in 0..<iterations {
        for edge in edges {
            var path = [Vec2]()
            path.reserveCapacity(2)
            path.append(points[edge.from])
            path.append(points[edge.to])
            oldSink += path.count
        }
    }
    let elapsedOld = CFAbsoluteTimeGetCurrent() - startOld
    let oldMicros = (elapsedOld / Double(iterations)) * 1_000_000
    _blackHole(oldSink)

    // NEW: 3 shared arrays, append all segments
    let startNew = CFAbsoluteTimeGetCurrent()
    var newSink = 0
    for _ in 0..<iterations {
        var nearPath = [Vec2]()
        var midPath  = [Vec2]()
        var farPath  = [Vec2]()
        nearPath.reserveCapacity(edges.count * 2 / 3)
        midPath.reserveCapacity(edges.count * 2 / 3)
        farPath.reserveCapacity(edges.count * 2 / 3)

        for edge in edges {
            let d = edgeDepth(edge: edge, depths: depths)
            let p1 = points[edge.from]
            let p2 = points[edge.to]
            switch classifyDepth(d) {
            case .near:
                nearPath.append(p1)
                nearPath.append(p2)
            case .mid:
                midPath.append(p1)
                midPath.append(p2)
            case .far:
                farPath.append(p1)
                farPath.append(p2)
            }
        }
        newSink += nearPath.count + midPath.count + farPath.count
    }
    let elapsedNew = CFAbsoluteTimeGetCurrent() - startNew
    let newMicros = (elapsedNew / Double(iterations)) * 1_000_000
    _blackHole(newSink)

    return (oldMicros, newMicros)
}

// Prevent dead-code elimination
@inline(never)
func _blackHole(_ x: Int) {
    // Optimizer cannot eliminate this
    if x == Int.min { print("unreachable") }
}

// MARK: - Utility

func line(_ char: String, _ width: Int) -> String {
    return String(repeating: char, count: width)
}

// MARK: - Main

@main
struct BenchMeshRender {
    static func main() {
        let landmarkCount = 478
        let tessellationEdgeCount = 1322
        let featureEdgeCount = 120
        let classifyIterations = 1000
        let pathIterations = 500

        print(line("=", 64))
        print("  Face Mesh Render Benchmark")
        print("  Per-Edge Stroke vs Batched Depth-Band Approach")
        print(line("=", 64))
        print()
        print("Configuration:")
        print("  Landmarks:          \(landmarkCount)")
        print("  Tessellation edges: \(tessellationEdgeCount)")
        print("  Feature edges:      \(featureEdgeCount)")
        print("  Total edges:        \(tessellationEdgeCount + featureEdgeCount)")
        print()

        // Generate test data
        let points = generateRandomPoints(count: landmarkCount)
        let depths = generateRandomDepths(count: landmarkCount)
        let tessEdges = generateRandomEdges(count: tessellationEdgeCount, maxIndex: landmarkCount)
        let featEdges = generateRandomEdges(count: featureEdgeCount, maxIndex: landmarkCount)

        // ── Stroke Call Comparison ──────────────────────────────────

        let totalEdges = tessellationEdgeCount + featureEdgeCount
        let oldResult = simulateOldApproach(edgeCount: totalEdges)
        let newResult = simulateNewApproach(
            tessellationEdges: tessEdges,
            featureEdges: featEdges,
            depths: depths
        )

        print(line("-", 64))
        print("  STROKE CALL COMPARISON")
        print(line("-", 64))
        print()
        print("  Metric                OLD (per-edge)    NEW (batched)")
        print("  " + line("-", 54))
        print(String(format: "  Paths created         %-18d%d",
                      oldResult.pathsCreated, newResult.pathsCreated))
        print(String(format: "  context.stroke()      %-18d%d",
                      oldResult.strokeCalls, newResult.strokeCalls))
        let reduction = Double(oldResult.strokeCalls - newResult.strokeCalls)
            / Double(oldResult.strokeCalls) * 100.0
        print(String(format: "  Reduction                               %.1f%%", reduction))
        print()

        print("  Depth band distribution:")
        for (band, count) in newResult.bandCounts {
            let bar = String(repeating: "#", count: max(1, count / 20))
            print("    \(band.padding(toLength: 12, withPad: " ", startingAt: 0)) \(String(format: "%4d", count)) edges  \(bar)")
        }
        print()

        // ── Classification Timing ──────────────────────────────────

        print(line("-", 64))
        print("  CLASSIFICATION OVERHEAD (\(classifyIterations) iterations)")
        print(line("-", 64))
        print()

        let classResult = benchmarkClassification(
            edges: tessEdges,
            depths: depths,
            iterations: classifyIterations
        )
        print(String(format: "  Total time:           %.4f s", classResult.totalSeconds))
        print(String(format: "  Per frame:            %.1f us", classResult.perIterationMicros))
        let frameBudget = 1_000_000.0 / 60.0
        let pctBudget = classResult.perIterationMicros / frameBudget * 100.0
        print(String(format: "  %% of 60fps budget:    %.3f%%", pctBudget))
        print()

        // ── Path Construction Timing ───────────────────────────────

        print(line("-", 64))
        print("  PATH CONSTRUCTION BENCHMARK (\(pathIterations) iterations)")
        print(line("-", 64))
        print()

        let pathResult = benchmarkPathCreation(
            edges: tessEdges,
            points: points,
            depths: depths,
            iterations: pathIterations
        )
        print(String(format: "  OLD (1 path per edge):  %8.1f us/frame", pathResult.oldMicros))
        print(String(format: "  NEW (3 batched paths):  %8.1f us/frame", pathResult.newMicros))
        if pathResult.newMicros > 0 {
            let speedup = pathResult.oldMicros / pathResult.newMicros
            print(String(format: "  Speedup:                %8.2fx", speedup))
        }
        print()
        print("  Note: Real GPU savings from fewer context.stroke() calls are")
        print("  far greater than path-construction savings measured here.")
        print("  Each stroke() triggers a GPU pipeline flush and state change.")
        print()

        // ── Summary ────────────────────────────────────────────────

        print(line("=", 64))
        print("  SUMMARY")
        print(line("=", 64))
        print()
        print("  The batched depth-band approach reduces draw calls from")
        print("  \(oldResult.strokeCalls) individual strokes to \(newResult.strokeCalls) batched strokes.")
        print(String(format: "  That is a %.0f:1 reduction in context.stroke() calls.",
                      Double(oldResult.strokeCalls) / Double(max(1, newResult.strokeCalls))))
        print()
        print(String(format: "  Classification overhead is ~%.0f us per frame (%.3f%% of",
                      classResult.perIterationMicros, pctBudget))
        print("  a 60fps frame budget), making it effectively free.")
        print()
        print("  Path object allocation drops from \(oldResult.pathsCreated) to \(newResult.pathsCreated),")
        print("  eliminating \(oldResult.pathsCreated - newResult.pathsCreated) temporary allocations per frame.")
        print()
    }
}
