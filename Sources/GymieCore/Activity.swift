import Foundation

/// Per-day break counts for the heatmap, ported from extension/lib/activity.js.
public struct DayActivity: Codable, Equatable, Sendable {
    public var breaks: Int
    public var xp: Int
    public init(breaks: Int, xp: Int) { self.breaks = breaks; self.xp = xp }
}

public typealias ActivityLog = [String: DayActivity]

private let keepDays = 371

public func activityLevel(_ breaks: Int) -> Int {
    switch breaks {
    case ...0: 0
    case 1...2: 1
    case 3...4: 2
    case 5...6: 3
    default: 4
    }
}

public func recordActivity(_ activity: ActivityLog, now: Date, xp: Int) -> ActivityLog {
    let key = Clock.dayKey(now)
    let cutoff = Clock.dayKey(now - Double(keepDays) * .day)
    var next = activity.filter { $0.key >= cutoff }
    let prev = next[key] ?? DayActivity(breaks: 0, xp: 0)
    next[key] = DayActivity(breaks: prev.breaks + 1, xp: prev.xp + max(0, xp))
    return next
}

public struct HeatCell: Equatable, Sendable, Identifiable {
    public var day: String
    public var date: Date
    public var breaks: Int
    public var xp: Int
    public var level: Int
    public var future: Bool
    public var offday: Bool
    public var id: String { day }
}

private func firstMonday(_ now: Date, weeks: Int) -> Date {
    let today = Clock.startOfDay(now)
    let sinceMonday = (Clock.weekday(today) + 6) % 7
    return Clock.addDays(-sinceMonday - 7 * (weeks - 1), to: today)
}

/// `weeks` columns of Monday...Sunday cells, ending with the current week.
public func heatmapWeeks(_ activity: ActivityLog, now: Date, weeks: Int, workdays: [Int]) -> [[HeatCell]] {
    let today = Clock.dayKey(now)
    var d = firstMonday(now, weeks: weeks)
    return (0..<weeks).map { _ in
        (0..<7).map { _ in
            let day = Clock.dayKey(d)
            let entry = activity[day] ?? DayActivity(breaks: 0, xp: 0)
            let cell = HeatCell(day: day, date: d, breaks: entry.breaks, xp: entry.xp, level: activityLevel(entry.breaks),
                                future: day > today, offday: !workdays.contains(Clock.weekday(d)))
            d = Clock.addDays(1, to: d)
            return cell
        }
    }
}

public struct ActivityTotals: Equatable, Sendable {
    public var breaks: Int
    public var xp: Int
    public var activeDays: Int
}

public func activityTotals(_ activity: ActivityLog, now: Date, weeks: Int) -> ActivityTotals {
    let start = Clock.dayKey(firstMonday(now, weeks: weeks))
    let today = Clock.dayKey(now)
    let days = activity.filter { $0.key >= start && $0.key <= today }.map(\.value)
    return ActivityTotals(breaks: days.reduce(0) { $0 + $1.breaks }, xp: days.reduce(0) { $0 + $1.xp },
                          activeDays: days.filter { $0.breaks > 0 }.count)
}
