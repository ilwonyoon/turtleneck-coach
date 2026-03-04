import SwiftUI
import Charts

@MainActor
struct DashboardView: View {
    @ObservedObject var engine: PostureEngine
    @Environment(\.dismiss) private var dismiss
    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @State private var selectedRange: DashboardRange = .week
    @State private var chartDays: [ChartDay] = []
    @State private var rangeSessions: [SessionRecord] = []
    @State private var todaySummary = TodaySummary.empty
    @State private var refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                summaryCards

                Picker("Range", selection: $selectedRange) {
                    ForEach(DashboardRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                scoreTrendCard

                complianceCard
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: reloadData)
        .onChange(of: selectedRange) { _, _ in
            reloadData()
        }
        .onChange(of: engine.isMonitoring) { _, _ in
            reloadData()
        }
        .onReceive(refreshTimer) { _ in
            reloadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Posture Dashboard")
                .font(.title2.weight(.semibold))

            Spacer()

            Button("Done") {
                closeWindow()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Monitored") {
                Text("\(Int(todaySummary.monitoredMinutes.rounded())) min")
                    .font(.title3.weight(.semibold))
            }

            summaryCard(title: "Good Posture") {
                HStack(spacing: 10) {
                    CircularPercentView(percent: todaySummary.goodPosturePercent)
                    Text("\(Int(todaySummary.goodPosturePercent.rounded()))%")
                        .font(.title3.weight(.semibold))
                }
            }

            summaryCard(title: "Average Score") {
                Text(String(format: "%.0f", todaySummary.averageScore))
                    .font(.title3.weight(.semibold))
            }

            summaryCard(title: "Slouch Alerts") {
                Text("\(todaySummary.slouchAlerts)")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    private func summaryCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(cardBackground)
    }

    // MARK: - Charts

    private var scoreTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Trend")
                .font(.headline)

            Chart {
                ForEach(chartDays) { day in
                    if let score = day.averageScore {
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Score", score)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Series", "Daily Score"))

                        PointMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Score", score)
                        )
                        .foregroundStyle(by: .value("Series", "Daily Score"))
                    }

                    if let movingAverage = day.movingAverage {
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Score", movingAverage)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(by: .value("Series", "7-Day Average"))
                    }
                }

                RuleMark(y: .value("Good Threshold", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.green.opacity(0.8))
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale([
                "Daily Score": Color.cyan,
                "7-Day Average": Color.white.opacity(0.7)
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: selectedRange.axisStride)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: selectedRange.axisDateFormat)
                }
            }
            .frame(height: 220)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var complianceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compliance")
                    .font(.headline)
                Spacer()
                Text("\(Int(latestCompliancePercent.rounded()))% today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if selectedRange == .day {
                hourlyComplianceChart
            } else {
                dailyComplianceChart
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var dailyComplianceChart: some View {
        Chart {
            ForEach(chartDays) { day in
                if day.totalMinutes > 0 {
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Minutes", day.goodMinutes),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Posture", "Good"))

                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Minutes", day.badMinutes),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Posture", "Bad"))
                }
            }

            RuleMark(y: .value("Goal", 0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(Color.mint.opacity(0.9))
        }
        .chartForegroundStyleScale([
            "Good": Color.green,
            "Bad": Color.orange
        ])
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: .stride(by: 0.2)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0)))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedRange.axisStride)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: selectedRange.axisDateFormat)
            }
        }
        .frame(height: 220)
    }

    private var hourlyComplianceChart: some View {
        Chart {
            ForEach(hourBins) { bin in
                if bin.totalMinutes > 0 {
                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Minutes", bin.goodMinutes),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Posture", "Good"))

                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Minutes", bin.badMinutes),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Posture", "Bad"))
                }
            }

            RuleMark(y: .value("Goal", 0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(Color.mint.opacity(0.9))
        }
        .chartForegroundStyleScale([
            "Good": Color.green,
            "Bad": Color.orange
        ])
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: .stride(by: 0.2)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0)))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
            }
        }
        .frame(height: 220)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: - Data

    private func reloadData() {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }
        let todayRange = todayStart...tomorrow.addingTimeInterval(-1)

        var sessions = engine.dataStore.loadSessions(range: todayRange)
        if let liveSession = engine.currentSessionSnapshot(),
           calendar.isDate(liveSession.startDate, inSameDayAs: todayStart),
           !sessions.contains(where: { $0.id == liveSession.id }) {
            sessions.append(liveSession)
        }
        sessions.sort { $0.startDate < $1.startDate }

        todaySummary = summarizeToday(from: sessions)

        let range = selectedRange.dateRange(referenceDate: now, calendar: calendar)
        var sessionsForRange = engine.dataStore.loadSessions(range: range)
        if let liveSession = engine.currentSessionSnapshot(),
           liveSession.startDate <= range.upperBound,
           liveSession.endDate >= range.lowerBound,
           !sessionsForRange.contains(where: { $0.id == liveSession.id }) {
            sessionsForRange.append(liveSession)
        }
        sessionsForRange.sort { $0.startDate < $1.startDate }
        rangeSessions = sessionsForRange

        let storedAggregates = engine.dataStore.loadDailyAggregates(range: range)
        chartDays = makeChartDays(
            for: range,
            using: storedAggregates,
            liveTodaySessions: sessions
        )
    }

    private var latestCompliancePercent: Double {
        guard let lastDay = chartDays.last, lastDay.totalMinutes > 0 else { return 0 }
        return min(100, max(0, (lastDay.goodMinutes / lastDay.totalMinutes) * 100))
    }

    private var hourBins: [HourBin] {
        let targetDay = chartDays.last?.date ?? calendar.startOfDay(for: Date())
        return makeHourBins(for: targetDay, sessions: rangeSessions)
    }

    private func makeChartDays(
        for range: ClosedRange<Date>,
        using aggregates: [DailyAggregate],
        liveTodaySessions: [SessionRecord]
    ) -> [ChartDay] {
        var byDay = Dictionary(uniqueKeysWithValues: aggregates.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        if let liveToday = aggregate(forDay: calendar.startOfDay(for: Date()), sessions: liveTodaySessions) {
            byDay[liveToday.date] = liveToday
        }

        let days = allDays(in: range)
        var chartDays = days.map { day -> ChartDay in
            let key = calendar.startOfDay(for: day)
            let aggregate = byDay[key]
            let totalMinutes = aggregate?.totalMonitoredMinutes ?? 0
            let goodMinutes = totalMinutes * ((aggregate?.goodPosturePercent ?? 0) / 100)

            return ChartDay(
                date: key,
                averageScore: (aggregate?.sessionCount ?? 0) > 0 ? aggregate?.averageScore : nil,
                movingAverage: nil,
                totalMinutes: totalMinutes,
                goodMinutes: max(0, goodMinutes),
                badMinutes: max(0, totalMinutes - goodMinutes)
            )
        }

        for index in chartDays.indices {
            let start = max(0, index - 6)
            let windowScores = chartDays[start...index].compactMap(\.averageScore)
            chartDays[index].movingAverage = windowScores.isEmpty
                ? nil
                : windowScores.reduce(0, +) / Double(windowScores.count)
        }

        return chartDays
    }

    private func summarizeToday(from sessions: [SessionRecord]) -> TodaySummary {
        let totalDuration = sessions.reduce(0) { partial, session in
            partial + max(0, session.duration)
        }

        guard totalDuration > 0 else { return .empty }

        let weightedScoreSum = sessions.reduce(0.0) { partial, session in
            partial + (session.averageScore * max(0, session.duration))
        }

        let weightedGoodSum = sessions.reduce(0.0) { partial, session in
            partial + (session.goodPosturePercent * max(0, session.duration))
        }

        let slouchAlerts = sessions.reduce(0) { partial, session in
            partial + max(0, session.slouchEventCount)
        }

        return TodaySummary(
            monitoredMinutes: totalDuration / 60,
            averageScore: weightedScoreSum / totalDuration,
            goodPosturePercent: weightedGoodSum / totalDuration,
            slouchAlerts: slouchAlerts
        )
    }

    private func aggregate(forDay day: Date, sessions: [SessionRecord]) -> DailyAggregate? {
        let daySessions = sessions.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        guard !daySessions.isEmpty else { return nil }

        let totalDuration = daySessions.reduce(0) { $0 + max(0, $1.duration) }
        guard totalDuration > 0 else {
            return DailyAggregate(
                date: day,
                totalMonitoredMinutes: 0,
                averageScore: 0,
                goodPosturePercent: 0,
                sessionCount: daySessions.count
            )
        }

        let weightedScore = daySessions.reduce(0.0) { $0 + ($1.averageScore * max(0, $1.duration)) }
        let weightedGood = daySessions.reduce(0.0) { $0 + ($1.goodPosturePercent * max(0, $1.duration)) }

        return DailyAggregate(
            date: day,
            totalMonitoredMinutes: totalDuration / 60,
            averageScore: weightedScore / totalDuration,
            goodPosturePercent: weightedGood / totalDuration,
            sessionCount: daySessions.count
        )
    }

    private func allDays(in range: ClosedRange<Date>) -> [Date] {
        var dates: [Date] = []
        var current = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)

        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    private func makeHourBins(for day: Date, sessions: [SessionRecord]) -> [HourBin] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var goodMinutesByHour = Array(repeating: 0.0, count: 24)
        var badMinutesByHour = Array(repeating: 0.0, count: 24)

        for session in sessions {
            let sessionStart = max(session.startDate, dayStart)
            let sessionEnd = min(session.endDate, dayEnd)
            guard sessionEnd > sessionStart else { continue }

            let clampedGoodPercent = min(100, max(0, session.goodPosturePercent))

            for hourIndex in 0..<24 {
                guard let hourStart = calendar.date(byAdding: .hour, value: hourIndex, to: dayStart),
                      let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else {
                    continue
                }

                let overlapStart = max(sessionStart, hourStart)
                let overlapEnd = min(sessionEnd, hourEnd)
                let overlapSeconds = overlapEnd.timeIntervalSince(overlapStart)
                guard overlapSeconds > 0 else { continue }

                let overlapMinutes = overlapSeconds / 60
                let goodMinutes = overlapMinutes * (clampedGoodPercent / 100)
                goodMinutesByHour[hourIndex] += goodMinutes
                badMinutesByHour[hourIndex] += max(0, overlapMinutes - goodMinutes)
            }
        }

        return (0..<24).compactMap { hourIndex in
            guard let hourStart = calendar.date(byAdding: .hour, value: hourIndex, to: dayStart) else {
                return nil
            }

            return HourBin(
                hourStart: hourStart,
                goodMinutes: max(0, goodMinutesByHour[hourIndex]),
                badMinutes: max(0, badMinutesByHour[hourIndex])
            )
        }
    }
}

private struct CircularPercentView: View {
    let percent: Double

    private var progress: Double {
        min(1, max(0, percent / 100))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .orange],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 42, height: 42)
    }
}

private enum DashboardRange: String, CaseIterable, Identifiable {
    case day = "D"
    case week = "W"
    case month = "M"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    var axisStride: Int {
        switch self {
        case .day, .week: return 1
        case .month: return 5
        }
    }

    var axisDateFormat: Date.FormatStyle {
        switch self {
        case .day:
            return .dateTime.month().day()
        case .week:
            return .dateTime.weekday(.narrow)
        case .month:
            return .dateTime.month(.abbreviated).day()
        }
    }

    func dateRange(referenceDate: Date, calendar: Calendar) -> ClosedRange<Date> {
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: endDay)?.addingTimeInterval(-1) ?? referenceDate
        return startDay...endOfDay
    }
}

private struct ChartDay: Identifiable {
    var id: Date { date }

    let date: Date
    let averageScore: Double?
    var movingAverage: Double?
    let totalMinutes: Double
    let goodMinutes: Double
    let badMinutes: Double
}

private struct HourBin: Identifiable {
    var id: Date { hourStart }

    let hourStart: Date
    let goodMinutes: Double
    let badMinutes: Double

    var totalMinutes: Double {
        goodMinutes + badMinutes
    }
}

private struct TodaySummary {
    let monitoredMinutes: Double
    let averageScore: Double
    let goodPosturePercent: Double
    let slouchAlerts: Int

    static let empty = TodaySummary(
        monitoredMinutes: 0,
        averageScore: 0,
        goodPosturePercent: 0,
        slouchAlerts: 0
    )
}
