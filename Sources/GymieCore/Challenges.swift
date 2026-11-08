import Foundation

/// Daily challenges and the weekly featured area, ported from extension/lib/challenges.js.
/// The daily pick is seeded by the date with the same hash as the extension, so everyone
/// (Chrome or Mac) gets the same challenges on the same day.
public struct Challenge: Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var bonus: Int
    public var symbol: String
}

public let DAILY_POOL: [Challenge] = [
    Challenge(id: "variety", name: "Variety pack", detail: "Exercises from 3 different areas today", bonus: 25, symbol: "square.grid.3x3.fill"),
    Challenge(id: "high_five", name: "High five", detail: "5 breaks done today", bonus: 30, symbol: "hand.raised.fill"),
    Challenge(id: "clean_form", name: "Clean form", detail: "One break with average form 90+", bonus: 20, symbol: "sparkles"),
    Challenge(id: "early_mover", name: "Early mover", detail: "A break before 10:00", bonus: 15, symbol: "sunrise.fill"),
    Challenge(id: "no_excuses", name: "No excuses", detail: "3 breaks in a row, no snooze or skip", bonus: 25, symbol: "flame.fill"),
]

public enum WeeklyRules {
    public static let target = 10
    public static let bonus = 100
}

public struct CompletedChallenge: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bonus: Int

    public init(id: String, name: String, bonus: Int) { self.id = id; self.name = name; self.bonus = bonus }
}

private let dailyMin = 2
private let dailyMax = 5
private let earlyHour = 10

func seedHash(_ text: String) -> UInt32 {
    var h: UInt32 = 7
    for unit in text.utf16 { h = h &* 31 &+ UInt32(unit) }
    return h
}

public func dailyFor(_ now: Date) -> [String] {
    let day = Clock.dayKey(now)
    let offset = Int(seedHash(day) % UInt32(DAILY_POOL.count))
    let count = dailyMin + Int(seedHash("\(day):count") % UInt32(dailyMax - dailyMin + 1))
    return (0..<count).map { DAILY_POOL[(offset + $0) % DAILY_POOL.count].id }
}

/// Rolls the daily and weekly challenge state over when the day or week changed.
public func withPeriods(_ profile: Profile, now: Date) -> Profile {
    var p = profile
    let day = Clock.dayKey(now)
    let week = Clock.isoWeek(now)
    if p.daily?.day != day {
        p.daily = Profile.Daily(day: day, ids: dailyFor(now), areas: [], breaks: 0, run: 0, done: [])
    }
    if p.weekly?.week != week {
        p.weekly = Profile.Weekly(week: week, area: featuredArea(now), count: 0, done: false)
    } else if let w = p.weekly, !AREAS.contains(w.area) {
        p.weekly!.area = featuredArea(now)
    }
    return p
}

public func updateChallenges(_ profile: Profile, _ result: BreakResult, avgForm: Double, now: Date)
    -> (profile: Profile, completed: [CompletedChallenge], newBadges: [String])
{
    var p = withPeriods(profile, now: now)
    var d = p.daily!
    var w = p.weekly!
    let completedMoves = result.moves.filter(\.completed)
    var areas = d.areas
    for m in completedMoves where !areas.contains(m.area) { areas.append(m.area) }
    d.areas = areas
    d.breaks += 1
    d.run += 1
    let meets: [String: Bool] = [
        "variety": d.areas.count >= 3,
        "high_five": d.breaks >= 5,
        "clean_form": avgForm >= 90,
        "early_mover": Clock.hour(now) < earlyHour,
        "no_excuses": d.run >= 3,
    ]
    var completed: [CompletedChallenge] = []
    var newBadges: [String] = []
    func badge(_ id: String) {
        guard !p.badges.contains(id) else { return }
        p.badges.append(id)
        newBadges.append(id)
    }
    for id in d.ids where !d.done.contains(id) && meets[id] == true {
        d.done.append(id)
        let c = DAILY_POOL.first { $0.id == id }!
        completed.append(CompletedChallenge(id: id, name: c.name, bonus: c.bonus))
        badge("daily:\(id)")
    }
    w.count = min(WeeklyRules.target, w.count + completedMoves.filter { $0.area == w.area }.count)
    if !w.done && w.count >= WeeklyRules.target {
        w.done = true
        completed.append(CompletedChallenge(id: "weekly", name: "\(w.area) week", bonus: WeeklyRules.bonus))
        badge("weekly:\(w.area)")
    }
    p.daily = d
    p.weekly = w
    return (p, completed, newBadges)
}

/// Snooze, skip and close break the "no excuses" run.
public func noteAction(_ profile: Profile, _ action: Schedule.Action, now: Date) -> Profile {
    var p = withPeriods(profile, now: now)
    if [.snooze, .skip, .close].contains(action) { p.daily!.run = 0 }
    return p
}

public func badgeLabel(_ id: String) -> String {
    if id.hasPrefix("daily:") {
        let key = String(id.dropFirst(6))
        return DAILY_POOL.first { $0.id == key }?.name ?? key
    }
    if id.hasPrefix("weekly:") { return "\(id.dropFirst(7)) week" }
    return id
}

public func badgeSymbol(_ id: String) -> String {
    if id.hasPrefix("daily:") {
        let key = String(id.dropFirst(6))
        return DAILY_POOL.first { $0.id == key }?.symbol ?? "rosette"
    }
    if id.hasPrefix("weekly:") { return AREA_SYMBOLS[String(id.dropFirst(7))] ?? "star.fill" }
    return "rosette"
}
