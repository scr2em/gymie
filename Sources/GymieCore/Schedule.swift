import Foundation

/// The break schedule, ported from extension/lib/schedule.js.
/// Reminders sit on a grid: after a reminder at slot S the next one is S + interval,
/// unless an action (snooze, pause) re-anchors it.
public struct Schedule: Codable, Equatable, Sendable {
    public var nextAt: Date?
    public var skipsInRow = 0
    public var snoozesInRow = 0
    public var pausedUntil: Date?
    /// A scheduled reminder window is open; closing it without acting counts as a skip.
    /// Manual "Break now" windows never set this.
    public var reminderOpen = false
    public var lastKey: String?
    public var breakCount = 0
    public var shiftedBy = 0
    public var deferredFrom: Date?

    public init() {}

    public static let snoozeMin = 20
    public static let snoozeCap = 2
    public static let warnSkips = 3
    public static let pauseMin = 60
    public static let lateAfter: TimeInterval = 10 * .minute
    public static let deferMin = 5
    public static let idleSeconds: TimeInterval = 300

    public static func initial(now: Date, intervalMin: Int) -> Schedule {
        var s = Schedule()
        s.nextAt = now + Double(intervalMin) * .minute
        return s
    }

    public var canSnooze: Bool { snoozesInRow < Schedule.snoozeCap }
    public var showWarning: Bool { skipsInRow >= Schedule.warnSkips }

    /// "~N hours without moving", rounded to the nearest half hour.
    public static func warningHours(skips: Int, intervalMin: Int) -> Double {
        (Double(skips * intervalMin) / 30).rounded() / 2
    }

    public func onFire(now: Date, intervalMin: Int) -> Schedule {
        let step = Double(intervalMin) * .minute
        var next = (nextAt ?? now) + step
        while next <= now { next += step }
        var s = self
        s.nextAt = next
        return s
    }

    public enum Action: String, Codable, Sendable { case done, skip, close, snooze, pause }

    public func apply(_ action: Action, now: Date, intervalMin: Int) -> Schedule {
        var s = self
        switch action {
        case .done:
            s.skipsInRow = 0; s.snoozesInRow = 0; s.shiftedBy = 0; s.reminderOpen = false
        case .skip:
            s.skipsInRow += 1; s.snoozesInRow = 0; s.shiftedBy = 0; s.reminderOpen = false
        case .close:
            return reminderOpen ? apply(.skip, now: now, intervalMin: intervalMin) : self
        case .snooze:
            guard canSnooze else { return self }
            s.nextAt = now + Double(Schedule.snoozeMin) * .minute
            s.snoozesInRow += 1; s.shiftedBy = Schedule.snoozeMin; s.reminderOpen = false
        case .pause:
            let until = now + Double(Schedule.pauseMin) * .minute
            s.nextAt = until; s.pausedUntil = until; s.reminderOpen = false
        }
        return s
    }

    public func upcoming(intervalMin: Int, count: Int = 3) -> [Date] {
        guard let nextAt else { return [] }
        return (0..<count).map { nextAt + Double($0 * intervalMin) * .minute }
    }

    public func rescheduled(now: Date, intervalMin: Int) -> Schedule {
        var s = self
        s.nextAt = now + Double(intervalMin) * .minute
        return s
    }
}

// MARK: - Active hours

public func isActive(_ t: Date, _ hours: ActiveHours) -> Bool {
    let mins = Clock.minutesIntoDay(t)
    return hours.workdays.contains(Clock.weekday(t)) && mins >= minutesOf(hours.activeStart) && mins < minutesOf(hours.activeEnd)
}

/// `t` if it's inside active hours, otherwise the next active window's start + interval.
public func nextActiveSlot(_ t: Date, intervalMin: Int, hours: ActiveHours) -> Date {
    if isActive(t, hours) { return t }
    let start = minutesOf(hours.activeStart)
    let step = Double(intervalMin) * .minute
    for k in 0..<8 {
        let day = Clock.addDays(k, to: t)
        let opens = Clock.at(minutes: start, on: day)
        if hours.workdays.contains(Clock.weekday(day)) && opens > t { return opens + step }
    }
    return t + step
}

// MARK: - Firing

public enum IdleState: String, Sendable { case active, idle, locked }

public struct FireDecision: Equatable, Sendable {
    public enum Kind: String, Sendable { case outside, late, `defer`, open, away }
    public var kind: Kind
    public var schedule: Schedule
}

public func decideFire(_ s: Schedule, now: Date, intervalMin: Int, idle: IdleState, meeting: Bool, autoPause: Bool, hours: ActiveHours) -> FireDecision {
    let slot = { (t: Date) in nextActiveSlot(t, intervalMin: intervalMin, hours: hours) }
    var out = s
    if !isActive(now, hours) {
        out.nextAt = slot(now); out.deferredFrom = nil
        return FireDecision(kind: .outside, schedule: out)
    }
    let deferred = s.deferredFrom != nil
    if !deferred, let nextAt = s.nextAt, now.timeIntervalSince(nextAt) > Schedule.lateAfter {
        out.nextAt = slot(now + Double(intervalMin) * .minute)
        return FireDecision(kind: .late, schedule: out)
    }
    if autoPause && meeting {
        out.nextAt = now + Double(Schedule.deferMin) * .minute
        out.deferredFrom = deferred ? s.deferredFrom : s.nextAt
        return FireDecision(kind: .defer, schedule: out)
    }
    var base = s
    if deferred { base.nextAt = s.deferredFrom }
    var fired = base.onFire(now: now, intervalMin: intervalMin)
    fired.nextAt = slot(fired.nextAt!)
    fired.deferredFrom = nil
    return FireDecision(kind: idle == .active ? .open : .away, schedule: fired)
}

/// Menu bar countdown: "23m", "45s", "2h", or "move" when due.
public func countdownText(_ secondsLeft: TimeInterval) -> String {
    if secondsLeft <= 0 { return "move" }
    if secondsLeft < 60 { return "\(Int(secondsLeft.rounded(.up)))s" }
    let minutes = Int((secondsLeft / 60).rounded(.up))
    return minutes >= 100 ? "\(Int((Double(minutes) / 60).rounded()))h" : "\(minutes)m"
}
