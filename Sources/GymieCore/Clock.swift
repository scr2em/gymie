import Foundation

/// Local-time calendar helpers. Weekdays use the extension's numbering (0 = Sunday ... 6 = Saturday)
/// so settings and challenge seeds match the Chrome extension.
public enum Clock {
    public static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    static var iso: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }

    /// "2026-11-08" in local time. Sorts lexically by date.
    public static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func isoWeekNumber(_ date: Date) -> Int {
        iso.component(.weekOfYear, from: date)
    }

    /// "2026-W45".
    public static func isoWeek(_ date: Date) -> String {
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }

    /// 0 = Sunday ... 6 = Saturday.
    public static func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    public static func hour(_ date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    public static func minutesIntoDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date)!
    }

    /// Local midnight of `day` plus `minutes`.
    public static func at(minutes: Int, on day: Date) -> Date {
        startOfDay(day).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Convenience for tests and previews: a local date.
    public static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}

/// "09:00" -> 540.
public func minutesOf(_ hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return parts[0] * 60 + parts[1]
}

public extension TimeInterval {
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86_400
}
