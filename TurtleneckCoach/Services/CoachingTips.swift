import Foundation

enum CoachingLevel: Int, CaseIterable {
    case foundation = 0
    case awareness = 1
    case build = 2
    case maintain = 3
}

struct CoachingTip: Identifiable {
    let id: String
    let level: CoachingLevel
    let title: String
    let body: String
    let searchKeyword: String

    var youtubeSearchURL: URL? {
        let query = searchKeyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(query)")
    }

    static func tips(for level: CoachingLevel) -> [CoachingTip] {
        switch level {
        case .foundation:
            return [
                CoachingTip(
                    id: "f1",
                    level: .foundation,
                    title: "What Turtle Neck Really Is",
                    body: "Neck angle is the symptom. Weak deep neck flexors and scapular support are often the real driver.",
                    searchKeyword: "forward head posture causes deep neck flexors scapular"
                ),
                CoachingTip(
                    id: "f2",
                    level: .foundation,
                    title: "Head Load Fact",
                    body: "Forward head angle can sharply increase cervical load in biomechanical models.",
                    searchKeyword: "text neck cervical load hansraj"
                ),
                CoachingTip(
                    id: "f3",
                    level: .foundation,
                    title: "Scapula Matters",
                    body: "Shoulder blade mechanics affect neck tension and upper-body control.",
                    searchKeyword: "scapular stabilization neck posture"
                ),
                CoachingTip(
                    id: "f4",
                    level: .foundation,
                    title: "1-Min Desk Reset",
                    body: "Ears over shoulders, shoulder blades gently down and back, 5 slow breaths.",
                    searchKeyword: "desk posture reset breathing"
                ),
                CoachingTip(
                    id: "f5",
                    level: .foundation,
                    title: "Eye Break Rule",
                    body: "Try 20-20-20 to reduce screen strain and neck guarding.",
                    searchKeyword: "20-20-20 rule eye strain"
                )
            ]
        case .awareness:
            return [
                CoachingTip(
                    id: "a1",
                    level: .awareness,
                    title: "Chin Tuck Starter",
                    body: "2 sets x 8 reps, slow and pain-free.",
                    searchKeyword: "chin tuck exercise physical therapy"
                ),
                CoachingTip(
                    id: "a2",
                    level: .awareness,
                    title: "Doorway Pec Stretch",
                    body: "2 x 30s each side to reduce shoulder-forward pull.",
                    searchKeyword: "doorway pectoral stretch posture"
                ),
                CoachingTip(
                    id: "a3",
                    level: .awareness,
                    title: "Wall Angel Prep",
                    body: "2 x 6 controlled reps, keep ribs down.",
                    searchKeyword: "wall angel exercise posture"
                ),
                CoachingTip(
                    id: "a4",
                    level: .awareness,
                    title: "30-Min Movement Trigger",
                    body: "Stand or walk 60-90s every 30 minutes of screen work.",
                    searchKeyword: "microbreaks desk work neck pain"
                ),
                CoachingTip(
                    id: "a5",
                    level: .awareness,
                    title: "Monitor Height Check",
                    body: "Top of screen at or slightly below eye level, arm's length distance.",
                    searchKeyword: "monitor eye level ergonomics"
                )
            ]
        case .build:
            return [
                CoachingTip(
                    id: "b1",
                    level: .build,
                    title: "Band Pull-Aparts",
                    body: "3 x 12, focus on lower trap and rhomboid control.",
                    searchKeyword: "band pull apart form scapular stability"
                ),
                CoachingTip(
                    id: "b2",
                    level: .build,
                    title: "Prone Y-T-W Series",
                    body: "2 rounds, 8 reps each letter, slow tempo.",
                    searchKeyword: "prone Y T W exercise neck posture"
                ),
                CoachingTip(
                    id: "b3",
                    level: .build,
                    title: "Scapular Push-Ups",
                    body: "3 x 10 for serratus and shoulder blade rhythm.",
                    searchKeyword: "scapular push up serratus"
                ),
                CoachingTip(
                    id: "b4",
                    level: .build,
                    title: "Thoracic Extension Drill",
                    body: "2 minutes daily to restore upper-back extension.",
                    searchKeyword: "thoracic mobility drill desk workers"
                ),
                CoachingTip(
                    id: "b5",
                    level: .build,
                    title: "Workstation Triple Fix",
                    body: "Monitor height + elbows at 90 degrees + feet stable before every session.",
                    searchKeyword: "office ergonomics neck pain setup"
                )
            ]
        case .maintain:
            return [
                CoachingTip(
                    id: "m1",
                    level: .maintain,
                    title: "Face Pull Quality Sets",
                    body: "3 x 12 with pause at end-range retraction and external rotation.",
                    searchKeyword: "face pull posture form"
                ),
                CoachingTip(
                    id: "m2",
                    level: .maintain,
                    title: "Dead Hang Progression",
                    body: "3 x 20s assisted or full hangs if shoulder-friendly.",
                    searchKeyword: "dead hang shoulder mobility progression"
                ),
                CoachingTip(
                    id: "m3",
                    level: .maintain,
                    title: "Posterior Chain Pairing",
                    body: "Pair row + hip hinge work 2-3x per week for full-chain support.",
                    searchKeyword: "posterior chain training desk posture"
                ),
                CoachingTip(
                    id: "m4",
                    level: .maintain,
                    title: "Weekly Mobility Flow",
                    body: "5-8 min: thoracic extension, pec stretch, neck control.",
                    searchKeyword: "upper body mobility routine posture"
                ),
                CoachingTip(
                    id: "m5",
                    level: .maintain,
                    title: "Relapse Prevention Audit",
                    body: "If trend declines for 3 days, temporarily return to Level 2 basics.",
                    searchKeyword: "posture habit maintenance strategy"
                )
            ]
        }
    }

    static func tipOfTheDay(for level: CoachingLevel, date: Date = Date()) -> CoachingTip {
        let levelTips = tips(for: level)
        guard !levelTips.isEmpty else {
            return CoachingTip(
                id: "fallback",
                level: level,
                title: "No Tip Available",
                body: "Try again later.",
                searchKeyword: "posture tips"
            )
        }

        let dayOfMonth = Calendar.current.component(.day, from: date)
        let index = max(0, dayOfMonth - 1) % levelTips.count
        return levelTips[index]
    }
}
