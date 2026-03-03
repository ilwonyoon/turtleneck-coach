import Foundation

/// Manages calibration: sample collection, validation, and persistence.
/// Port of Python calibration.py.
final class CalibrationManager {

    static let requiredSamples = 20
    static let minCalibrationCVA: CGFloat = 40.0
    private static let userDefaultsKey = "calibrationData"

    private(set) var samples: [PostureMetrics] = []
    private(set) var isCalibrating = false

    var progress: CGFloat {
        guard isCalibrating else { return 0 }
        return CGFloat(samples.count) / CGFloat(Self.requiredSamples)
    }

    /// Start a new calibration session.
    func startCalibration() {
        samples = []
        isCalibrating = true
    }

    // Head pitch samples collected alongside posture metrics
    private var headPitchSamples: [CGFloat] = []

    /// Add a sample during calibration. Returns CalibrationResult when enough samples collected.
    func addSample(_ metrics: PostureMetrics, headPitch: CGFloat = 0) -> CalibrationResult? {
        guard isCalibrating, metrics.landmarksDetected else { return nil }

        samples.append(metrics)
        headPitchSamples.append(headPitch)

        guard samples.count >= Self.requiredSamples else { return nil }

        isCalibrating = false
        let result = collectCalibration(samples: samples, headPitchSamples: headPitchSamples)
        samples = []
        headPitchSamples = []

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

    // MARK: - Core Algorithm

    /// Average samples into baseline and validate posture quality.
    /// Port of collect_calibration() from calibration.py.
    private func collectCalibration(samples: [PostureMetrics], headPitchSamples: [CGFloat] = []) -> CalibrationResult {
        let valid = samples.filter { $0.landmarksDetected }
        guard !valid.isEmpty else {
            return CalibrationResult(
                data: nil,
                isValid: false,
                message: "No pose detected. Make sure your face and shoulders are visible.",
                measuredCVA: 0
            )
        }

        let n = CGFloat(valid.count)
        let earsVisibleCount = valid.filter { $0.earsVisible }.count
        let earsMostlyVisible = earsVisibleCount > valid.count / 2

        let avgCVA = valid.map(\.neckEarAngle).reduce(0, +) / n

        let avgHeadPitch: CGFloat
        if !headPitchSamples.isEmpty {
            avgHeadPitch = headPitchSamples.reduce(0, +) / CGFloat(headPitchSamples.count)
        } else {
            avgHeadPitch = 0
        }

        let data = CalibrationData(
            earShoulderDistanceLeft: valid.map(\.earShoulderDistanceLeft).reduce(0, +) / n,
            earShoulderDistanceRight: valid.map(\.earShoulderDistanceRight).reduce(0, +) / n,
            eyeShoulderDistanceLeft: valid.map(\.eyeShoulderDistanceLeft).reduce(0, +) / n,
            eyeShoulderDistanceRight: valid.map(\.eyeShoulderDistanceRight).reduce(0, +) / n,
            headForwardRatio: valid.map(\.headForwardRatio).reduce(0, +) / n,
            headTiltAngle: valid.map(\.headTiltAngle).reduce(0, +) / n,
            neckEarAngle: avgCVA,
            shoulderEvenness: valid.map(\.shoulderEvenness).reduce(0, +) / n,
            earsWereVisible: earsMostlyVisible,
            headPitch: avgHeadPitch
        )

        if avgCVA < Self.minCalibrationCVA {
            return CalibrationResult(
                data: data,
                isValid: false,
                message: String(format: "Posture too far forward (CVA ~%.0f\u{00B0}). Sit up straight: ears over shoulders, chin slightly tucked.", avgCVA),
                measuredCVA: avgCVA
            )
        }

        return CalibrationResult(
            data: data,
            isValid: true,
            message: String(format: "Calibration successful! (CVA ~%.0f\u{00B0})", avgCVA),
            measuredCVA: avgCVA
        )
    }
}
