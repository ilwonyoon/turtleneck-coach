import Foundation

/// Manages calibration: sample collection, validation, and persistence.
/// Port of Python calibration.py.
final class CalibrationManager {

    static let requiredSamples = 20
    private static let userDefaultsKey = "calibrationData"

    // Quality gates for calibration validation
    private static let maxCVAStdDev: CGFloat = 3.0       // reject if too much movement
    private static let minLandmarkConfidence: CGFloat = 0.7 // reject if detection too sparse
    private static let minPlausibleCVA: CGFloat = 5.0     // reject if CVA unmeasurable

    private(set) var samples: [PostureMetrics] = []
    private(set) var isCalibrating = false

    var progress: CGFloat {
        guard isCalibrating else { return 0 }
        return CGFloat(samples.count) / CGFloat(Self.requiredSamples)
    }

    /// Start a new calibration session.
    func startCalibration() {
        samples = []
        headPitchSamples = []
        faceSizeSamples = []
        forwardDepthSamples = []
        irisGazeSamples = []
        isCalibrating = true
    }

    // Head pitch samples collected alongside posture metrics
    private var headPitchSamples: [CGFloat] = []
    // Face size samples collected alongside posture metrics
    private var faceSizeSamples: [CGFloat] = []
    // Forward depth samples (Z-depth nose vs shoulders)
    private var forwardDepthSamples: [CGFloat] = []
    // Iris gaze offset samples
    private var irisGazeSamples: [CGFloat] = []

    /// Add a sample during calibration. Returns CalibrationResult when enough samples collected.
    func addSample(_ metrics: PostureMetrics, headPitch: CGFloat = 0) -> CalibrationResult? {
        guard isCalibrating, metrics.landmarksDetected else { return nil }

        samples.append(metrics)
        headPitchSamples.append(headPitch)
        faceSizeSamples.append(metrics.faceSizeNormalized)
        forwardDepthSamples.append(metrics.forwardDepth)
        irisGazeSamples.append(metrics.irisGazeOffset)

        guard samples.count >= Self.requiredSamples else { return nil }

        isCalibrating = false
        let result = collectCalibration(samples: samples, headPitchSamples: headPitchSamples, faceSizeSamples: faceSizeSamples, forwardDepthSamples: forwardDepthSamples, irisGazeSamples: irisGazeSamples)
        samples = []
        headPitchSamples = []
        faceSizeSamples = []
        forwardDepthSamples = []
        irisGazeSamples = []

        if result.isValid, let data = result.data {
            save(data)
        }

        return result
    }

    /// Cancel an in-progress calibration.
    func cancelCalibration() {
        isCalibrating = false
        samples = []
        headPitchSamples = []
        faceSizeSamples = []
        forwardDepthSamples = []
        irisGazeSamples = []
    }

    /// Load saved calibration from UserDefaults.
    static func loadSaved() -> CalibrationData? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CalibrationData.self, from: data)
    }

    /// Save calibration to UserDefaults.
    func save(_ data: CalibrationData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Clear saved calibration.
    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Helpers

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let count = sorted.count
        if count == 0 { return 0 }
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

    private func stdDev(_ values: [CGFloat], median med: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let variance = values.map { ($0 - med) * ($0 - med) }.reduce(0, +) / CGFloat(values.count)
        return sqrt(variance)
    }

    // MARK: - Core Algorithm

    /// Collect median baseline from samples and validate calibration quality.
    private func collectCalibration(
        samples: [PostureMetrics],
        headPitchSamples: [CGFloat] = [],
        faceSizeSamples: [CGFloat] = [],
        forwardDepthSamples: [CGFloat] = [],
        irisGazeSamples: [CGFloat] = []
    ) -> CalibrationResult {
        let valid = samples.filter { $0.landmarksDetected }
        guard !valid.isEmpty else {
            return CalibrationResult(
                data: nil,
                isValid: false,
                message: "No pose detected. Make sure your face and shoulders are visible.",
                measuredCVA: 0
            )
        }

        let earsVisibleCount = valid.filter { $0.earsVisible }.count
        let earsMostlyVisible = earsVisibleCount > valid.count / 2

        // Median aggregation (outlier-robust)
        let cvaValues = valid.map(\.neckEarAngle)
        let medianCVA = median(cvaValues)
        let cvaSD = stdDev(cvaValues, median: medianCVA)
        let confidence = CGFloat(valid.count) / CGFloat(samples.count)

        let medianHeadPitch = headPitchSamples.isEmpty ? CGFloat(0) : median(headPitchSamples)
        let medianFaceSize = faceSizeSamples.isEmpty ? CGFloat(0) : median(faceSizeSamples)
        let medianForwardDepth = forwardDepthSamples.isEmpty ? CGFloat(0) : median(forwardDepthSamples)
        let medianIrisGaze = irisGazeSamples.isEmpty ? CGFloat(0) : median(irisGazeSamples)

        let data = CalibrationData(
            earShoulderDistanceLeft: median(valid.map(\.earShoulderDistanceLeft)),
            earShoulderDistanceRight: median(valid.map(\.earShoulderDistanceRight)),
            eyeShoulderDistanceLeft: median(valid.map(\.eyeShoulderDistanceLeft)),
            eyeShoulderDistanceRight: median(valid.map(\.eyeShoulderDistanceRight)),
            headForwardRatio: median(valid.map(\.headForwardRatio)),
            headTiltAngle: median(valid.map(\.headTiltAngle)),
            neckEarAngle: medianCVA,
            shoulderEvenness: median(valid.map(\.shoulderEvenness)),
            earsWereVisible: earsMostlyVisible,
            headPitch: medianHeadPitch,
            baselineFaceSize: medianFaceSize,
            forwardDepth: medianForwardDepth,
            irisGazeOffset: medianIrisGaze,
            cvaStdDev: cvaSD,
            landmarkConfidence: confidence,
            schemaVersion: 2
        )

        // Quality gates (variance-based, not absolute CVA)
        if cvaSD > Self.maxCVAStdDev {
            return CalibrationResult(
                data: data,
                isValid: false,
                message: "Too much movement. Hold still during calibration.",
                measuredCVA: medianCVA
            )
        }

        if confidence < Self.minLandmarkConfidence {
            return CalibrationResult(
                data: data,
                isValid: false,
                message: "Couldn't detect your pose reliably. Check lighting and camera angle.",
                measuredCVA: medianCVA
            )
        }

        if medianCVA < Self.minPlausibleCVA {
            return CalibrationResult(
                data: data,
                isValid: false,
                message: "Couldn't measure your neck angle. Make sure face and shoulders are visible.",
                measuredCVA: medianCVA
            )
        }

        return CalibrationResult(
            data: data,
            isValid: true,
            message: String(format: "Calibrated! (baseline CVA ~%.0f\u{00B0})", medianCVA),
            measuredCVA: medianCVA
        )
    }
}
