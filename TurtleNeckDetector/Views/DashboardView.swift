import SwiftUI
import Charts

@MainActor
struct DashboardView: View {
    @ObservedObject var engine: PostureEngine

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @State private var chartHours: [ChartHour] = []
    @State private var weeklyTrendDays: [WeeklyTrendDay] = []
    @State private var todaySummary = TodaySummary.empty
    @State private var refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                header

                summaryCards

                postureTimelineCard

                weeklyTrendCard
            }
            .padding(DS.Space.xl)
        }
        .frame(minWidth: 600, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: reloadData)
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
            summaryCard(title: "Bad Posture Time") {
                Text(formattedDuration(minutes: todaySummary.badPostureMinutes))
                    .font(DS.Font.titleBold)
                    .foregroundStyle(DS.Severity.moderate)
            }

            summaryCard(title: "Good Posture %") {
                HStack(spacing: 10) {
                    CircularPercentView(percent: todaySummary.goodPosturePercent)
                    Text("\(Int(todaySummary.goodPosturePercent.rounded()))%")
                        .font(DS.Font.titleBold)
                }
            }

            summaryCard(title: "Resets") {
                Text("\(todaySummary.resets)")
                    .font(DS.Font.titleBold)
            }

            summaryCard(title: "Longest Slouch") {
                Text(formattedDuration(minutes: todaySummary.longestSlouchMinutes))
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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(cardBackground)
    }

    // MARK: - Charts

    private var postureTimelineCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Posture Timeline")
                    .font(DS.Font.headline)
                Spacer()
                Text("Today")
                    .font(DS.Font.subheadBold)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(hourlyTimelineBins) { bin in
                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Minutes", bin.goodMinutes)
                    )
                    .foregroundStyle(by: .value("Posture", "Good"))

                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Minutes", bin.badMinutes)
                    )
                    .foregroundStyle(by: .value("Posture", "Bad"))
                }
            }
            .chartForegroundStyleScale([
                "Good": DS.Severity.good,
                "Bad": DS.Severity.moderate
            ])
            .chartXScale(domain: hourlyChartDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .frame(height: 220)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var weeklyTrendCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Weekly Trend")
                    .font(DS.Font.headline)
                Spacer()
                Text("Bad posture time")
                    .font(DS.Font.subheadBold)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(weeklyTrendDays) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Bad Posture", day.badMinutes)
                    )
                    .foregroundStyle(DS.Severity.moderate)
                    .annotation(position: .top) {
                        if day.badMinutes > 0 {
                            Text(formattedDurationCompact(minutes: day.badMinutes))
                                .font(DS.Font.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 200)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var hourlyTimelineBins: [ChartHour] {
        chartHours.filter { $0.totalMinutes > 0 }
    }

    private var hourlyChartDomain: ClosedRange<Date> {
        let reference = chartHours.first?.hourStart ?? Date()
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(60 * 60 * 24)
        return dayStart...dayEnd
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

        let weeklyRange = weekDateRange(referenceDate: now)
        let storedAggregates = engine.dataStore.loadDailyAggregates(range: weeklyRange)
        weeklyTrendDays = makeWeeklyTrendDays(
            for: weeklyRange,
            using: storedAggregates,
            liveTodaySessions: sessions
        )
    }

    private func summarizeToday(from sessions: [SessionRecord]) -> TodaySummary {
        let totalDuration = sessions.reduce(0) { partial, session in
            partial + max(0, session.duration)
        }

        guard totalDuration > 0 else { return .empty }

        let weightedGoodSum = sessions.reduce(0.0) { partial, session in
            partial + (session.goodPosturePercent * max(0, session.duration))
        }

        let totalBadPostureMinutes = sessions.reduce(0.0) { partial, session in
            let explicitBadMinutes = max(0, session.badPostureSeconds) / 60.0
            if explicitBadMinutes > 0 {
                return partial + explicitBadMinutes
            }

            let durationMinutes = max(0, session.duration) / 60.0
            let fallbackBadRatio = 1 - (min(100, max(0, session.goodPosturePercent)) / 100)
            return partial + max(0, durationMinutes * fallbackBadRatio)
        }

        let resets = sessions.reduce(0) { partial, session in
            partial + max(0, session.resetCount)
        }

        let longestSlouchMinutes = sessions
            .map { max(0, $0.longestSlouchSeconds) / 60.0 }
            .max() ?? 0

        return TodaySummary(
            badPostureMinutes: max(0, totalBadPostureMinutes),
            goodPosturePercent: weightedGoodSum / totalDuration,
            resets: max(0, resets),
            longestSlouchMinutes: max(0, longestSlouchMinutes)
        )
    }

    private func makeWeeklyTrendDays(
        for range: ClosedRange<Date>,
        using aggregates: [DailyAggregate],
        liveTodaySessions: [SessionRecord]
    ) -> [WeeklyTrendDay] {
        var byDay = Dictionary(uniqueKeysWithValues: aggregates.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        if let liveToday = aggregate(forDay: calendar.startOfDay(for: Date()), sessions: liveTodaySessions) {
            byDay[liveToday.date] = liveToday
        }

        return allDays(in: range).map { day in
            let key = calendar.startOfDay(for: day)
            let aggregate = byDay[key]

            let badMinutes: Double
            if let aggregate {
                if aggregate.totalBadPostureMinutes > 0 {
                    badMinutes = aggregate.totalBadPostureMinutes
                } else {
                    let fallbackRatio = 1 - (min(100, max(0, aggregate.goodPosturePercent)) / 100)
                    badMinutes = max(0, aggregate.totalMonitoredMinutes * fallbackRatio)
                }
            } else {
                badMinutes = 0
            }

            return WeeklyTrendDay(date: key, badMinutes: max(0, badMinutes))
        }
    }

    private func makeChartHours(for day: Date, using aggregates: [HourlyAggregate]) -> [ChartHour] {
        let dayStart = calendar.startOfDay(for: day)

        return aggregates.compactMap { aggregate in
            guard let hourStart = calendar.date(byAdding: .hour, value: aggregate.hour, to: dayStart) else {
                return nil
            }

            return ChartHour(
                hourStart: hourStart,
                goodMinutes: max(0, aggregate.goodMinutes),
                badMinutes: max(0, aggregate.badMinutes),
                totalMinutes: max(0, aggregate.totalMinutes)
            )
        }
        .sorted { $0.hourStart < $1.hourStart }
    }

    private func aggregate(forDay day: Date, sessions: [SessionRecord]) -> DailyAggregate? {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var totalDuration = 0.0
        var weightedScore = 0.0
        var weightedGood = 0.0
        var sessionCount = 0
        var totalBadSeconds = 0.0
        var totalResets = 0
        var longestSlouchSeconds = 0.0

        for session in sessions {
            let overlapStart = max(session.startDate, dayStart)
            let overlapEnd = min(session.endDate, dayEnd)
            let overlapDuration = max(0, overlapEnd.timeIntervalSince(overlapStart))
            guard overlapDuration > 0 else { continue }

            totalDuration += overlapDuration
            weightedScore += session.averageScore * overlapDuration
            weightedGood += session.goodPosturePercent * overlapDuration
            sessionCount += 1

            totalBadSeconds += max(0, session.badPostureSeconds)
            totalResets += max(0, session.resetCount)
            longestSlouchSeconds = max(longestSlouchSeconds, max(0, session.longestSlouchSeconds))
        }

        guard sessionCount > 0 else { return nil }
        guard totalDuration > 0 else {
            return DailyAggregate(
                date: dayStart,
                totalMonitoredMinutes: 0,
                averageScore: 0,
                goodPosturePercent: 0,
                sessionCount: sessionCount,
                totalBadPostureMinutes: 0,
                resetCount: totalResets,
                longestSlouchMinutes: longestSlouchSeconds / 60.0
            )
        }

        return DailyAggregate(
            date: dayStart,
            totalMonitoredMinutes: totalDuration / 60,
            averageScore: weightedScore / totalDuration,
            goodPosturePercent: weightedGood / totalDuration,
            sessionCount: sessionCount,
            totalBadPostureMinutes: max(0, totalBadSeconds / 60.0),
            resetCount: max(0, totalResets),
            longestSlouchMinutes: max(0, longestSlouchSeconds / 60.0)
        )
    }

    private func weekDateRange(referenceDate: Date) -> ClosedRange<Date> {
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) ?? endDay
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: endDay)?.addingTimeInterval(-1) ?? referenceDate
        return startDay...endOfDay
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

    private func formattedDuration(minutes: Double) -> String {
        let safeMinutes = Int(max(0, minutes).rounded())
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    private func formattedDurationCompact(minutes: Double) -> String {
        let safeMinutes = Int(max(0, minutes).rounded())
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60

        if hours > 0 {
            return "\(hours)h\(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
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
                        colors: [DS.Severity.good, DS.Palette.yellow, DS.Severity.moderate],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 42, height: 42)
    }
}

private struct ChartHour: Identifiable {
    var id: Date { hourStart }

    let hourStart: Date
    let goodMinutes: Double
    let badMinutes: Double
    let totalMinutes: Double
}

private struct WeeklyTrendDay: Identifiable {
    var id: Date { date }

    let date: Date
    let badMinutes: Double
}

private struct TodaySummary {
    let badPostureMinutes: Double
    let goodPosturePercent: Double
    let resets: Int
    let longestSlouchMinutes: Double

    static let empty = TodaySummary(
        badPostureMinutes: 0,
        goodPosturePercent: 0,
        resets: 0,
        longestSlouchMinutes: 0
    )
}
