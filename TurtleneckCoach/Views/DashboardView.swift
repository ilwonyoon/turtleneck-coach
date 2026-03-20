import SwiftUI
import Charts
import AppKit

@MainActor
struct DashboardView: View {
    @ObservedObject var engine: PostureEngine

    @State private var chartHours: [ChartHour] = []
    @State private var weeklyTrendDays: [WeeklyTrendDay] = []
    @State private var todaySummary = TodaySummary.empty
    @State private var coachMessage: DashboardMessage?
    @State private var lastMessageBucket: Int = -1
    @State private var lifetimeMonitoredMinutes: Double = 0
    @State private var sevenDayGoodPosturePercent: Double = 0
    @State private var coachingTipOffset: Int = 0
    @State private var refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var cardsVisible = false
    @State private var numbersVisible = false
    @State private var chartAnimateIn = false
    @State private var weeklyAnimateIn = false

    private var calendar: Calendar { .current }
    private var coachingTips: [CoachingTip] { CoachingTip.tips(for: coachingLevel) }
    private var coachingTipOfTheDay: CoachingTip { CoachingTip.tipOfTheDay(for: coachingLevel) }

    private var selectedCoachingTip: CoachingTip {
        guard !coachingTips.isEmpty else { return coachingTipOfTheDay }
        let baseIndex = coachingTips.firstIndex(where: { $0.id == coachingTipOfTheDay.id }) ?? 0
        let offset = coachingTipOffset % coachingTips.count
        let resolvedIndex = (baseIndex + offset + coachingTips.count) % coachingTips.count
        return coachingTips[resolvedIndex]
    }

    private var coachingLevel: CoachingLevel {
        if lifetimeMonitoredMinutes < 90 {
            return .foundation
        }

        if sevenDayGoodPosturePercent < 30 {
            return .awareness
        }
        if sevenDayGoodPosturePercent < 70 {
            return .build
        }
        return .maintain
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.sm) {
                summaryCards

                postureTimelineCard
                    .offset(y: chartAnimateIn ? 0 : 8)
                    .opacity(chartAnimateIn ? 1 : 0)

                weeklyTrendCard
                    .offset(y: weeklyAnimateIn ? 0 : 8)
                    .opacity(weeklyAnimateIn ? 1 : 0)
            }
            .padding(DS.Space.lg)
        }
        .frame(minWidth: 500, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reloadData()
            // Stagger: cards → numbers → today chart → weekly chart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    cardsVisible = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                numbersVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    chartAnimateIn = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    weeklyAnimateIn = true
                }
            }
        }
        .onChange(of: engine.isMonitoring) { _, _ in
            reloadData()
        }
        .onChange(of: engine.bodyDetected) { _, _ in
            reloadData()
        }
        .onChange(of: engine.powerState) { _, _ in
            reloadData()
        }
        .onReceive(refreshTimer) { _ in
            reloadData()
        }
        .onChange(of: coachingLevel) { _, _ in
            coachingTipOffset = 0
        }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: DS.Space.sm) {
            goodPostureHeroCard
                .frame(maxHeight: .infinity)
                .offset(y: cardsVisible ? 0 : 8)
                .opacity(cardsVisible ? 1 : 0)

            coachingTipCard
                .frame(maxHeight: .infinity)
                .offset(y: cardsVisible ? 0 : 8)
                .opacity(cardsVisible ? 1 : 0)
        }
    }

    private var goodPostureHeroCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .center) {
                Text("Good Posture")
                    .font(DS.Font.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(engine.dashboardLiveStatusText)
                    .font(DS.Font.mini)
                    .foregroundStyle(engine.dashboardLiveStatusColor)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, 3) // DS: one-off
                    .background(
                        engine.dashboardLiveStatusColor.opacity(0.12),
                        in: Capsule()
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(formattedDuration(minutes: numbersVisible ? todaySummary.goodPostureMinutes : 0))
                    .font(DS.Font.scoreLg)
                    .foregroundStyle(DS.Severity.good)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: numbersVisible)
                Text("/ " + formattedDuration(minutes: numbersVisible ? todaySummary.totalMonitoredMinutes : 0))
                    .font(DS.Font.subhead)
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: numbersVisible)
            }

            Spacer(minLength: 0)

            Text(coachMessage?.main ?? "")
                .font(DS.Font.subhead)
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(coachMessage?.sub ?? "")
                .font(DS.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private var coachingTipCard: some View {
        let tip = selectedCoachingTip

        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(levelBadgeText(for: coachingLevel))
                .font(DS.Font.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xs)
                .background(
                    Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                )

            Text(tip.title)
                .font(DS.Font.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(tip.body)
                .font(DS.Font.subhead)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: DS.Space.sm) {
                Button {
                    if let url = tip.youtubeSearchURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Search on YouTube", systemImage: "play.rectangle.fill")
                        .font(DS.Font.subheadMedium)
                        .foregroundStyle(DS.Severity.good)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            DS.Severity.good.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    coachingTipOffset += 1
                } label: {
                    Text("Next Tip")
                        .font(DS.Font.subheadMedium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Text("Educational only")
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private func levelBadgeText(for level: CoachingLevel) -> String {
        switch level {
        case .foundation:
            return "Level 0 - Foundation"
        case .awareness:
            return "Level 1 - Awareness"
        case .build:
            return "Level 2 - Build"
        case .maintain:
            return "Level 3 - Maintain"
        }
    }

    // MARK: - Charts

    private var postureTimelineCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Today's Activity")
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
                        y: .value("Minutes", chartAnimateIn ? bin.goodMinutes : 0)
                    )
                    .foregroundStyle(by: .value("Posture", "Good"))

                    BarMark(
                        x: .value("Hour", bin.hourStart, unit: .hour),
                        y: .value("Minutes", chartAnimateIn ? bin.badMinutes : 0)
                    )
                    .foregroundStyle(by: .value("Posture", "Bad"))
                }
            }
            .chartForegroundStyleScale([
                "Good": DS.Severity.good,
                "Bad": DS.Severity.moderate
            ])
            .chartYScale(domain: 0...60)
            .chartXScale(domain: hourlyChartDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .frame(height: 160)
        }
        .padding(DS.Space.md)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private var weeklyTrendCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Weekly Progress")
                    .font(DS.Font.headline)
                Spacer()
                Text("Posture score")
                    .font(DS.Font.subheadBold)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(weeklyTrendDays) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Posture Score", chartAnimateIn ? day.score : 0)
                    )
                    .foregroundStyle(DS.Severity.good)
                    .annotation(position: .top) {
                        if chartAnimateIn && day.score > 0 {
                            Text("\(Int(day.score.rounded()))")
                                .font(DS.Font.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 150)
        }
        .padding(DS.Space.md)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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

    // MARK: - Data

    private func reloadData() {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }
        let todayRange = todayStart...tomorrow.addingTimeInterval(-1)
        let liveSession = engine.currentSessionSnapshot()

        var sessions = engine.dataStore.loadSessions(range: todayRange)
        if let liveSession,
           calendar.isDate(liveSession.startDate, inSameDayAs: todayStart),
           !sessions.contains(where: { $0.id == liveSession.id }) {
            sessions.append(liveSession)
        }
        sessions.sort { $0.startDate < $1.startDate }

        todaySummary = summarizeToday(from: sessions)

        let goodPercent = todaySummary.totalMonitoredMinutes > 0
            ? (todaySummary.goodPostureMinutes / todaySummary.totalMonitoredMinutes) * 100
            : 0
        let currentBucket: Int
        let trend: TrendDirection
        if todaySummary.totalMonitoredMinutes <= 0 {
            currentBucket = -1
            trend = .newUser
        } else if goodPercent < 30 {
            currentBucket = 0
            trend = .stable
        } else if goodPercent < 70 {
            currentBucket = 1
            trend = .stable
        } else {
            currentBucket = 2
            trend = .stable
        }
        if currentBucket != lastMessageBucket {
            lastMessageBucket = currentBucket
            coachMessage = DashboardMessages.message(forProgress: goodPercent, trend: trend)
        }

        let hourlyAggregates = engine.dataStore.loadHourlyAggregates(for: todayStart, sessions: sessions)
        chartHours = makeChartHours(for: todayStart, using: hourlyAggregates)

        let weeklyRange = weekDateRange(referenceDate: now)
        let storedAggregates = engine.dataStore.loadDailyAggregates(range: weeklyRange)
        weeklyTrendDays = makeWeeklyTrendDays(
            for: weeklyRange,
            using: storedAggregates,
            liveTodaySessions: sessions
        )

        var weeklySessions = engine.dataStore.loadSessions(range: weeklyRange)
        if let liveSession,
           !weeklySessions.contains(where: { $0.id == liveSession.id }) {
            weeklySessions.append(liveSession)
        }
        sevenDayGoodPosturePercent = weightedGoodPosturePercent(from: weeklySessions)

        let lifetimeRange = Date(timeIntervalSince1970: 0)...now
        var lifetimeSessions = engine.dataStore.loadSessions(range: lifetimeRange)
        if let liveSession,
           !lifetimeSessions.contains(where: { $0.id == liveSession.id }) {
            lifetimeSessions.append(liveSession)
        }
        lifetimeMonitoredMinutes = lifetimeSessions.reduce(0) { partial, session in
            partial + max(0, session.duration)
        } / 60.0
    }

    private func weightedGoodPosturePercent(from sessions: [SessionRecord]) -> Double {
        let totalDuration = sessions.reduce(0.0) { partial, session in
            partial + max(0, session.duration)
        }

        guard totalDuration > 0 else { return 0 }

        let weightedGood = sessions.reduce(0.0) { partial, session in
            let safePercent = min(100, max(0, session.goodPosturePercent))
            return partial + (safePercent * max(0, session.duration))
        }

        return weightedGood / totalDuration
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

        let totalMonitoredMinutes = totalDuration / 60.0
        let badPostureMinutes = max(0, totalBadPostureMinutes)
        let goodPostureMinutes = max(0, totalMonitoredMinutes - badPostureMinutes)

        return TodaySummary(
            goodPostureMinutes: goodPostureMinutes,
            averageScore: max(0, min(100, weightedScoreSum / totalDuration)),
            totalMonitoredMinutes: max(0, totalMonitoredMinutes),
            badPostureMinutes: badPostureMinutes,
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
            let score = max(0, min(100, aggregate?.averageScore ?? 0))
            return WeeklyTrendDay(date: key, score: score)
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
        return String(format: "%d:%02d", hours, remainingMinutes)
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
                .stroke(Color.primary.opacity(0.1), lineWidth: DS.Size.scoreStroke)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [DS.Severity.good, DS.Palette.yellow, DS.Severity.moderate],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: DS.Size.scoreStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: -1, y: 1)
                .animation(.spring(response: 0.8, dampingFraction: 0.75), value: progress)
        }
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
    let score: Double
}

private struct TodaySummary {
    let goodPostureMinutes: Double
    let averageScore: Double
    let totalMonitoredMinutes: Double
    let badPostureMinutes: Double
    let goodPosturePercent: Double
    let resets: Int
    let longestSlouchMinutes: Double

    static let empty = TodaySummary(
        goodPostureMinutes: 0,
        averageScore: 0,
        totalMonitoredMinutes: 0,
        badPostureMinutes: 0,
        goodPosturePercent: 0,
        resets: 0,
        longestSlouchMinutes: 0
    )
}
