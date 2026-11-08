import Foundation

/// Levels, XP and awards, ported from extension/lib/xp.js. XP only ever goes up.
public struct Level: Equatable, Sendable {
    public var level: Int
    public var name: String
    public var xp: Int
}

public let LEVELS: [Level] = [
    Level(level: 1, name: "Desk Potato", xp: 0),
    Level(level: 2, name: "Chair Escapee", xp: 100),
    Level(level: 3, name: "Stretch Rookie", xp: 250),
    Level(level: 4, name: "Desk Mover", xp: 500),
    Level(level: 5, name: "Posture Pro", xp: 900),
    Level(level: 6, name: "Flow Stretcher", xp: 1400),
    Level(level: 7, name: "Mobility Ninja", xp: 2000),
    Level(level: 8, name: "Movement Master", xp: 3000),
]

public enum XPRules {
    public static let base = 10
    public static let firstBreak = 5
    public static let streakPerDay = 1
    public static let streakMax = 10
}

public struct LevelInfo: Equatable, Sendable {
    public var level: Int
    public var name: String
    public var floor: Int
    public var next: Int?
    public var progress: Double
}

public func levelFor(_ xp: Int) -> LevelInfo {
    var i = LEVELS.count - 1
    while i > 0 && xp < LEVELS[i].xp { i -= 1 }
    let cur = LEVELS[i]
    let next = i + 1 < LEVELS.count ? LEVELS[i + 1] : nil
    let progress = next.map { Double(xp - cur.xp) / Double($0.xp - cur.xp) } ?? 1
    return LevelInfo(level: cur.level, name: cur.name, floor: cur.xp, next: next?.xp, progress: progress)
}

/// What a finished break reports.
public struct BreakResult: Codable, Equatable, Sendable {
    public struct MoveResult: Codable, Equatable, Sendable {
        public var key: String
        public var area: String
        public var completed: Bool
        public init(key: String, area: String, completed: Bool) { self.key = key; self.area = area; self.completed = completed }
    }
    /// False when the camera or pose server was unavailable: Done counts for the schedule but earns no XP.
    public var scored: Bool
    public var countedReps: Int
    public var targetReps: Int
    public var scores: [Int]
    public var moves: [MoveResult]

    public init(scored: Bool, countedReps: Int, targetReps: Int, scores: [Int], moves: [MoveResult]) {
        self.scored = scored; self.countedReps = countedReps; self.targetReps = targetReps
        self.scores = scores; self.moves = moves
    }

    public var averageForm: Double { scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count) }
}

public func breakXp(countedReps: Int, targetReps: Int, scores: [Int]) -> Int {
    guard !scores.isEmpty, targetReps > 0 else { return 0 }
    let completion = min(1, Double(countedReps) / Double(targetReps))
    let form = Double(scores.reduce(0, +)) / Double(scores.count) / 100
    return Int((Double(XPRules.base) * completion * form).rounded())
}

public struct Profile: Codable, Equatable, Sendable {
    public var xp = 0
    public var streak = 0
    public var lastStreakDay: String?
    public var lastBreakDay: String?
    public var weekXp = 0
    public var week: String?
    public var badges: [String] = []
    public var daily: Daily?
    public var weekly: Weekly?

    public init() {}

    public struct Daily: Codable, Equatable, Sendable {
        public var day: String
        public var ids: [String]
        public var areas: [String]
        public var breaks: Int
        public var run: Int
        public var done: [String]

        public init(day: String, ids: [String], areas: [String], breaks: Int, run: Int, done: [String]) {
            self.day = day; self.ids = ids; self.areas = areas; self.breaks = breaks; self.run = run; self.done = done
        }
    }

    public struct Weekly: Codable, Equatable, Sendable {
        public var week: String
        public var area: String
        public var count: Int
        public var done: Bool

        public init(week: String, area: String, count: Int, done: Bool) {
            self.week = week; self.area = area; self.count = count; self.done = done
        }
    }

    /// Week XP for the current ISO week (0 if the stored week is stale).
    public func currentWeekXp(now: Date) -> Int { week == Clock.isoWeek(now) ? weekXp : 0 }
}

public struct Breakdown: Codable, Equatable, Sendable {
    public var breakXp = 0
    public var firstBreak = 0
    public var streak = 0
    public var challenges: [CompletedChallenge] = []
    public var total = 0

    public init() {}
}

public struct LevelUp: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var name: String

    public init(from: Int, to: Int, name: String) { self.from = from; self.to = to; self.name = name }
}

public struct Award: Equatable, Sendable {
    public var profile: Profile
    public var breakdown: Breakdown
    public var levelUp: LevelUp?
    public var newBadges: [String]

    public init(profile: Profile, breakdown: Breakdown, levelUp: LevelUp?, newBadges: [String]) {
        self.profile = profile; self.breakdown = breakdown; self.levelUp = levelUp; self.newBadges = newBadges
    }
}

func previousWorkday(_ now: Date, workdays: [Int]) -> String? {
    var d = now
    for _ in 0..<7 {
        d = Clock.addDays(-1, to: d)
        if workdays.contains(Clock.weekday(d)) { return Clock.dayKey(d) }
    }
    return nil
}

public func award(_ profile: Profile, _ result: BreakResult, now: Date, workdays: [Int]) -> Award {
    var p = profile
    let today = Clock.dayKey(now)
    let week = Clock.isoWeek(now)
    let before = levelFor(p.xp).level
    if p.week != week {
        p.week = week
        p.weekXp = 0
    }
    var breakdown = Breakdown()
    p.lastBreakDay = today
    guard result.scored else { return Award(profile: p, breakdown: breakdown, levelUp: nil, newBadges: []) }

    breakdown.breakXp = breakXp(countedReps: result.countedReps, targetReps: result.targetReps, scores: result.scores)
    if breakdown.breakXp > 0 && p.lastStreakDay != today {
        let prev = previousWorkday(now, workdays: workdays)
        if let last = p.lastStreakDay, let prev, last >= prev { p.streak += 1 } else { p.streak = 1 }
        p.lastStreakDay = today
        breakdown.firstBreak = XPRules.firstBreak
        breakdown.streak = min(p.streak * XPRules.streakPerDay, XPRules.streakMax)
    }
    let ch = updateChallenges(p, result, avgForm: result.averageForm, now: now)
    var out = ch.profile
    breakdown.challenges = ch.completed
    let bonus = ch.completed.reduce(0) { $0 + $1.bonus }
    breakdown.total = breakdown.breakXp + breakdown.firstBreak + breakdown.streak + bonus
    out.xp += breakdown.total
    out.weekXp += breakdown.total
    let after = levelFor(out.xp)
    let levelUp = after.level > before ? LevelUp(from: before, to: after.level, name: after.name) : nil
    return Award(profile: out, breakdown: breakdown, levelUp: levelUp, newBadges: ch.newBadges)
}
