import SwiftUI
import Charts

@MainActor
struct DashboardView: View {
    @ObservedObject var engine: PostureEngine
    @Environment(\.dismiss) private var dismiss
    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @State private var selectedRange: DashboardRange = .day
    @State private var chartDays: [ChartDay] = []
    @State private var chartHours: [ChartHour] = []
    @State private var todaySummary = TodaySummary.empty
    @State private var refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
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
            .padding(DS.Space.xl)
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
                .font(DS.Font.titleLgBold)

            Spacer()

            Button("Done") {
                closeWindow()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: DS.Space.md) {
            summaryCard(title: "Monitored") {
                Text("\(Int(todaySummary.monitoredMinutes.rounded())) min")
                    .font(DS.Font.titleBold)
            }

            summaryCard(title: "Good Posture") {
                HStack(spacing: 10) {
                    CircularPercentView(percent: todaySummary.goodPosturePercent)
                    Text("\(Int(todaySummary.goodPosturePercent.rounded()))%")
                        .font(DS.Font.titleBold)
                }
            }

            summaryCard(title: "Average Score") {
                Text(String(format: "%.0f", todaySummary.averageScore))
                    .font(DS.Font.titleBold)
            }

            summaryCard(title: "Slouch Alerts") {
                Text("\(todaySummary.slouchAlerts)")
                    .font(DS.Font.titleBold)
            }
        }
    }

    private func summaryCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(DS.Font.caption)
                .foregroundColor(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .padding(14) // DS: one-off
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(cardBackground)
    }

    // MARK: - Charts

    private var scoreTrendCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Score Trend")
                .font(DS.Font.headline)

            Chart {
                if selectedRange == .day {
                    ForEach(hourlyScorePoints) { point in
                        if let score = point.averageScore {
                            AreaMark(
                                x: .value("Hour", point.hourStart, unit: .hour),
                                y: .value("Score", score)
                            )
                            .interpolationMethod(.catmullRom)
                            .alignsMarkStylesWithPlotArea()
                            .foregroundStyle(scoreAreaGradient)

                            LineMark(
                                x: .value("Hour", point.hourStart, unit: .hour),
                                y: .value("Score", score)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .foregroundStyle(scoreLineGradient)
                        }
                    }
                } else {
                    ForEach(chartDays) { day in
                        if let score = day.averageScore {
                            AreaMark(
                                x: .value("Date", day.date, unit: .day),
                                y: .value("Score", score)
                            )
                            .interpolationMethod(.catmullRom)
                            .alignsMarkStylesWithPlotArea()
                            .foregroundStyle(scoreAreaGradient)

                            LineMark(
                                x: .value("Date", day.date, unit: .day),
                                y: .value("Score", score)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .foregroundStyle(scoreLineGradient)
                        }
                    }

                    if selectedRange == .week {
                        ForEach(chartDays) { day in
                            if let movingAverage = day.movingAverage {
                                LineMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Score", movingAverage)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .foregroundStyle(Color.white.opacity(0.7))
                            }
                        }
                    }
                }

                RuleMark(y: .value("Good Threshold", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(DS.Severity.good.opacity(0.9))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                switch selectedRange {
                case .day:
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                case .week:
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                case .month:
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
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
                    .font(DS.Font.headline)
                Spacer()
                Text("\(Int(latestCompliancePercent.rounded()))% today")
                    .font(DS.Font.subheadBold)
                    .foregroundStyle(.secondary)
            }

            if selectedRange == .day {
                hourlyComplianceChart
            } else {
                dailyComplianceChart
            }
        }
        .padding(14) // DS: one-off
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
                .foregroundStyle(DS.Palette.mint.opacity(0.9))
        }
        .chartForegroundStyleScale([
            "Good": DS.Severity.good,
            "Bad": DS.Severity.moderate
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
            ForEach(hourlyComplianceBins) { bin in
                let ratio = complianceRatio(goodMinutes: bin.goodMinutes, badMinutes: bin.badMinutes, totalMinutes: bin.totalMinutes)
                if ratio.good > 0 || ratio.bad > 0 {
                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Ratio", ratio.good)
                    )
                    .foregroundStyle(by: .value("Posture", "Good"))

                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Ratio", ratio.bad)
                    )
                    .foregroundStyle(by: .value("Posture", "Bad"))
                }
            }

            RuleMark(y: .value("Goal", 0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(DS.Palette.mint.opacity(0.9))
        }
        .chartForegroundStyleScale([
            "Good": DS.Severity.good,
            "Bad": DS.Severity.moderate
        ])
        .chartXScale(domain: hourlyChartDomain)
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

    private var scoreLineGradient: LinearGradient {
        LinearGradient(
            colors: [.red, .orange, .green],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var scoreAreaGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.green.opacity(0.30), location: 0.0),
                .init(color: Color.green.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hourlyChartDomain: ClosedRange<Date> {
        let reference = chartHours.first?.hourStart ?? Date()
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(60 * 60 * 24)
        return dayStart...dayEnd
    }

    private func complianceRatio(goodMinutes: Double, badMinutes: Double, totalMinutes: Double) -> (good: Double, bad: Double) {
        let safeGood = goodMinutes.isFinite ? max(0, goodMinutes) : 0
        let safeBad = badMinutes.isFinite ? max(0, badMinutes) : 0
        let safeTotal = totalMinutes.isFinite ? max(0, totalMinutes) : 0
        let denominator = max(safeTotal, safeGood + safeBad)
        guard denominator > 0 else { return (0, 0) }

        let goodRatio = min(1, max(0, safeGood / denominator))
        return (goodRatio, max(0, 1 - goodRatio))
    }

    private var hourlyScorePoints: [ChartHour] {
        chartHours.filter { $0.totalMinutes > 0 && $0.averageScore != nil }
    }

    private var hourlyComplianceBins: [ChartHour] {
        chartHours.filter { $0.totalMinutes > 0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
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
        let hourlyAggregates = engine.dataStore.loadHourlyAggregates(for: todayStart, sessions: sessions)
        chartHours = makeChartHours(for: todayStart, using: hourlyAggregates)

        let range = selectedRange.dateRange(referenceDate: now, calendar: calendar)
        let storedAggregates = engine.dataStore.loadDailyAggregates(range: range)
        chartDays = makeChartDays(
            for: range,
            using: storedAggregates,
            liveTodaySessions: sessions
        )
    }

    private var latestCompliancePercent: Double {
        min(100, max(0, todaySummary.goodPosturePercent))
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

    private func makeChartHours(for day: Date, using aggregates: [HourlyAggregate]) -> [ChartHour] {
        let dayStart = calendar.startOfDay(for: day)

        return aggregates.compactMap { aggregate in
            guard let hourStart = calendar.date(byAdding: .hour, value: aggregate.hour, to: dayStart) else {
                return nil
            }

            return ChartHour(
                hourStart: hourStart,
                averageScore: aggregate.averageScore,
                goodMinutes: max(0, aggregate.goodMinutes),
                badMinutes: max(0, aggregate.badMinutes),
                totalMinutes: max(0, aggregate.totalMinutes)
            )
        }
        .sorted { $0.hourStart < $1.hourStart }
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
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var totalDuration = 0.0
        var weightedScore = 0.0
        var weightedGood = 0.0
        var sessionCount = 0

        for session in sessions {
            let overlapStart = max(session.startDate, dayStart)
            let overlapEnd = min(session.endDate, dayEnd)
            let overlapDuration = max(0, overlapEnd.timeIntervalSince(overlapStart))
            guard overlapDuration > 0 else { continue }

            totalDuration += overlapDuration
            weightedScore += session.averageScore * overlapDuration
            weightedGood += session.goodPosturePercent * overlapDuration
            sessionCount += 1
        }

        guard sessionCount > 0 else { return nil }
        guard totalDuration > 0 else {
            return DailyAggregate(
                date: dayStart,
                totalMonitoredMinutes: 0,
                averageScore: 0,
                goodPosturePercent: 0,
                sessionCount: sessionCount
            )
        }

        return DailyAggregate(
            date: dayStart,
            totalMonitoredMinutes: totalDuration / 60,
            averageScore: weightedScore / totalDuration,
            goodPosturePercent: weightedGood / totalDuration,
            sessionCount: sessionCount
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
            return .dateTime.hour(.defaultDigits(amPM: .abbreviated))
        case .week:
            return .dateTime.weekday(.abbreviated)
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

private struct ChartHour: Identifiable {
    var id: Date { hourStart }

    let hourStart: Date
    let averageScore: Double?
    let goodMinutes: Double
    let badMinutes: Double
    let totalMinutes: Double
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
