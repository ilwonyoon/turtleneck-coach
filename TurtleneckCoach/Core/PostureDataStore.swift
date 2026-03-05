import Foundation

struct SessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let averageScore: Double
    let goodPosturePercent: Double
    let averageCVA: Double
    let slouchEventCount: Int
    let badPostureSeconds: TimeInterval
    let resetCount: Int
    let longestSlouchSeconds: TimeInterval

    init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        averageScore: Double,
        goodPosturePercent: Double,
        averageCVA: Double,
        slouchEventCount: Int,
        badPostureSeconds: TimeInterval = 0,
        resetCount: Int = 0,
        longestSlouchSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.averageScore = averageScore
        self.goodPosturePercent = goodPosturePercent
        self.averageCVA = averageCVA
        self.slouchEventCount = slouchEventCount
        self.badPostureSeconds = badPostureSeconds
        self.resetCount = resetCount
        self.longestSlouchSeconds = longestSlouchSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startDate
        case endDate
        case duration
        case averageScore
        case goodPosturePercent
        case averageCVA
        case slouchEventCount
        case badPostureSeconds
        case resetCount
        case longestSlouchSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        averageScore = try container.decode(Double.self, forKey: .averageScore)
        goodPosturePercent = try container.decode(Double.self, forKey: .goodPosturePercent)
        averageCVA = try container.decode(Double.self, forKey: .averageCVA)
        slouchEventCount = try container.decodeIfPresent(Int.self, forKey: .slouchEventCount) ?? 0
        badPostureSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .badPostureSeconds) ?? 0
        resetCount = try container.decodeIfPresent(Int.self, forKey: .resetCount) ?? 0
        longestSlouchSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .longestSlouchSeconds) ?? 0
    }
}

struct DailyAggregate: Codable, Identifiable, Hashable {
    var id: Date { date }

    /// Normalized to local start-of-day.
    let date: Date
    let totalMonitoredMinutes: Double
    let averageScore: Double
    let goodPosturePercent: Double
    let sessionCount: Int
    let totalBadPostureMinutes: Double
    let resetCount: Int
    let longestSlouchMinutes: Double

    init(
        date: Date,
        totalMonitoredMinutes: Double,
        averageScore: Double,
        goodPosturePercent: Double,
        sessionCount: Int,
        totalBadPostureMinutes: Double = 0,
        resetCount: Int = 0,
        longestSlouchMinutes: Double = 0
    ) {
        self.date = date
        self.totalMonitoredMinutes = totalMonitoredMinutes
        self.averageScore = averageScore
        self.goodPosturePercent = goodPosturePercent
        self.sessionCount = sessionCount
        self.totalBadPostureMinutes = totalBadPostureMinutes
        self.resetCount = resetCount
        self.longestSlouchMinutes = longestSlouchMinutes
    }

    enum CodingKeys: String, CodingKey {
        case date
        case totalMonitoredMinutes
        case averageScore
        case goodPosturePercent
        case sessionCount
        case totalBadPostureMinutes
        case resetCount
        case longestSlouchMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        totalMonitoredMinutes = try container.decode(Double.self, forKey: .totalMonitoredMinutes)
        averageScore = try container.decode(Double.self, forKey: .averageScore)
        goodPosturePercent = try container.decode(Double.self, forKey: .goodPosturePercent)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        let fallbackBad = max(0, totalMonitoredMinutes * (100 - goodPosturePercent) / 100)
        totalBadPostureMinutes = try container.decodeIfPresent(Double.self, forKey: .totalBadPostureMinutes) ?? fallbackBad
        resetCount = try container.decodeIfPresent(Int.self, forKey: .resetCount) ?? 0
        longestSlouchMinutes = try container.decodeIfPresent(Double.self, forKey: .longestSlouchMinutes) ?? 0
    }
}

struct HourlyAggregate: Codable, Identifiable, Hashable {
    var id: Int { hour }

    /// Local hour bucket in 24-hour format.
    let hour: Int
    let averageScore: Double?
    let goodMinutes: Double
    let badMinutes: Double
    let totalMinutes: Double
}

final class PostureDataStore {
    private let fileManager: FileManager
    private var calendar: Calendar
    private let storeDirectory: URL
    private let sessionsFileURL: URL
    private let dailyAggregatesFileURL: URL
    private let sessionRetentionDays = 90
    private let ioQueue = DispatchQueue(label: "com.turtleneckdetector.posture-data-store")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar

        let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        self.storeDirectory = appSupportRoot.appendingPathComponent("TurtleneckCoach", isDirectory: true)
        self.sessionsFileURL = storeDirectory.appendingPathComponent("sessions.json")
        self.dailyAggregatesFileURL = storeDirectory.appendingPathComponent("daily_aggregates.json")

        migrateFromLegacyDirectory(appSupportRoot: appSupportRoot)
        ensureStoreDirectoryExists()
    }

    /// Migrate data from the old "TurtleNeckDetector" directory if it exists.
    private func migrateFromLegacyDirectory(appSupportRoot: URL) {
        let legacyDir = appSupportRoot.appendingPathComponent("TurtleNeckDetector", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyDir.path),
              !fileManager.fileExists(atPath: storeDirectory.path) else { return }
        do {
            try fileManager.moveItem(at: legacyDir, to: storeDirectory)
        } catch {
            // Migration failed — the app will start fresh. Legacy data is preserved.
        }
    }

    func saveSession(_ session: SessionRecord) {
        ioQueue.sync {
            var sessions = loadSessionsFromDisk()
            var affectedDates = Set<Date>()

            if let existingIndex = sessions.firstIndex(where: { $0.id == session.id }) {
                let previous = sessions[existingIndex]
                affectedDates.insert(normalizedDay(previous.startDate))
                sessions[existingIndex] = session
            } else {
                sessions.append(session)
            }

            affectedDates.insert(normalizedDay(session.startDate))

            let pruned = pruneOldSessions(from: sessions)
            saveSessionsToDisk(pruned)

            var dailyAggregates = loadDailyAggregatesFromDisk()
            for day in affectedDates {
                if let aggregate = computeDailyAggregate(for: day, from: pruned) {
                    if let existing = dailyAggregates.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                        dailyAggregates[existing] = aggregate
                    } else {
                        dailyAggregates.append(aggregate)
                    }
                }
            }
            saveDailyAggregatesToDisk(dailyAggregates)
        }
    }

    func loadSessions(range: ClosedRange<Date>) -> [SessionRecord] {
        ioQueue.sync {
            var sessions = loadSessionsFromDisk()
            let pruned = pruneOldSessions(from: sessions)
            if pruned.count != sessions.count {
                sessions = pruned
                saveSessionsToDisk(pruned)
            }

            return sessions
                .filter { $0.startDate <= range.upperBound && $0.endDate >= range.lowerBound }
                .sorted { $0.startDate < $1.startDate }
        }
    }

    func loadDailyAggregates(range: ClosedRange<Date>) -> [DailyAggregate] {
        ioQueue.sync {
            loadDailyAggregatesFromDisk()
                .filter { $0.date >= normalizedDay(range.lowerBound) && $0.date <= normalizedDay(range.upperBound) }
                .sorted { $0.date < $1.date }
        }
    }

    func loadHourlyAggregates(for date: Date, sessions overrideSessions: [SessionRecord]? = nil) -> [HourlyAggregate] {
        ioQueue.sync {
            let sessions = overrideSessions ?? loadSessionsFromDisk()
            return computeHourlyAggregates(for: date, from: sessions)
        }
    }

    func computeDailyAggregate(for date: Date) -> DailyAggregate? {
        ioQueue.sync {
            computeDailyAggregate(for: date, from: loadSessionsFromDisk())
        }
    }

    // MARK: - Private Helpers

    private func computeDailyAggregate(for date: Date, from sessions: [SessionRecord]) -> DailyAggregate? {
        let day = normalizedDay(date)
        let daySessions = sessions.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        guard !daySessions.isEmpty else { return nil }

        let totalDuration = daySessions.reduce(0) { $0 + max(0, $1.duration) }
        let totalMinutes = totalDuration / 60.0

        let weightedScoreSum = daySessions.reduce(0.0) {
            $0 + ($1.averageScore * max(0, $1.duration))
        }
        let weightedGoodPercentSum = daySessions.reduce(0.0) {
            $0 + ($1.goodPosturePercent * max(0, $1.duration))
        }

        let averageScore = totalDuration > 0 ? weightedScoreSum / totalDuration : 0
        let goodPosturePercent = totalDuration > 0 ? weightedGoodPercentSum / totalDuration : 0
        let totalBadPostureMinutes = daySessions.reduce(0.0) { partial, session in
            let badMinutesFromField = max(0, session.badPostureSeconds) / 60.0
            if badMinutesFromField > 0 {
                return partial + badMinutesFromField
            }

            let durationMinutes = max(0, session.duration) / 60.0
            let fallbackBadRatio = 1 - (clampToPercent(session.goodPosturePercent) / 100.0)
            return partial + max(0, durationMinutes * fallbackBadRatio)
        }
        let resetCount = daySessions.reduce(0) { partial, session in
            partial + max(0, session.resetCount)
        }
        let longestSlouchMinutes = daySessions
            .map { max(0, $0.longestSlouchSeconds) / 60.0 }
            .max() ?? 0

        return DailyAggregate(
            date: day,
            totalMonitoredMinutes: totalMinutes,
            averageScore: clampToPercent(averageScore),
            goodPosturePercent: clampToPercent(goodPosturePercent),
            sessionCount: daySessions.count,
            totalBadPostureMinutes: max(0, totalBadPostureMinutes),
            resetCount: max(0, resetCount),
            longestSlouchMinutes: max(0, longestSlouchMinutes)
        )
    }

    private func computeHourlyAggregates(for date: Date, from sessions: [SessionRecord]) -> [HourlyAggregate] {
        let dayStart = normalizedDay(date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var totalSecondsByHour = Array(repeating: 0.0, count: 24)
        var goodSecondsByHour = Array(repeating: 0.0, count: 24)
        var weightedScoreSecondsByHour = Array(repeating: 0.0, count: 24)

        for session in sessions {
            let sessionStart = max(session.startDate, dayStart)
            let sessionEnd = min(session.endDate, dayEnd)
            guard sessionEnd > sessionStart else { continue }

            let clampedScore = clampToPercent(session.averageScore)
            let clampedGoodRatio = clampToPercent(session.goodPosturePercent) / 100.0

            var cursor = sessionStart
            while cursor < sessionEnd {
                guard let hourInterval = calendar.dateInterval(of: .hour, for: cursor) else { break }
                let hourStart = max(hourInterval.start, dayStart)
                let hourEnd = min(hourInterval.end, dayEnd)
                let segmentEnd = min(sessionEnd, hourEnd)
                let overlapSeconds = segmentEnd.timeIntervalSince(cursor)
                guard overlapSeconds > 0 else {
                    cursor = segmentEnd
                    continue
                }

                let hour = calendar.component(.hour, from: hourStart)
                guard (0..<24).contains(hour) else {
                    cursor = segmentEnd
                    continue
                }

                totalSecondsByHour[hour] += overlapSeconds
                goodSecondsByHour[hour] += overlapSeconds * clampedGoodRatio
                weightedScoreSecondsByHour[hour] += clampedScore * overlapSeconds
                cursor = segmentEnd
            }
        }

        return (0..<24).map { hour in
            let totalSeconds = max(0, totalSecondsByHour[hour])
            let totalMinutes = totalSeconds / 60.0
            let goodMinutes = max(0, goodSecondsByHour[hour] / 60.0)
            let badMinutes = max(0, totalMinutes - goodMinutes)
            let averageScore: Double? = totalSeconds > 0
                ? clampToPercent(weightedScoreSecondsByHour[hour] / totalSeconds)
                : nil

            return HourlyAggregate(
                hour: hour,
                averageScore: averageScore,
                goodMinutes: goodMinutes,
                badMinutes: badMinutes,
                totalMinutes: totalMinutes
            )
        }
    }

    private func pruneOldSessions(from sessions: [SessionRecord]) -> [SessionRecord] {
        guard let cutoff = calendar.date(byAdding: .day, value: -sessionRetentionDays, to: Date()) else {
            return sessions
        }

        return sessions
            .filter { $0.endDate >= cutoff }
            .sorted { $0.startDate < $1.startDate }
    }

    private func loadSessionsFromDisk() -> [SessionRecord] {
        loadArray(from: sessionsFileURL, as: SessionRecord.self)
    }

    private func saveSessionsToDisk(_ sessions: [SessionRecord]) {
        saveArray(sessions.sorted { $0.startDate < $1.startDate }, to: sessionsFileURL)
    }

    private func loadDailyAggregatesFromDisk() -> [DailyAggregate] {
        loadArray(from: dailyAggregatesFileURL, as: DailyAggregate.self)
    }

    private func saveDailyAggregatesToDisk(_ aggregates: [DailyAggregate]) {
        saveArray(aggregates.sorted { $0.date < $1.date }, to: dailyAggregatesFileURL)
    }

    private func loadArray<T: Decodable>(from url: URL, as _: T.Type) -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([T].self, from: data)) ?? []
    }

    private func saveArray<T: Encodable>(_ values: [T], to url: URL) {
        ensureStoreDirectoryExists()
        guard let data = try? encoder.encode(values) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensureStoreDirectoryExists() {
        guard !fileManager.fileExists(atPath: storeDirectory.path) else { return }
        try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    private func normalizedDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func clampToPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
