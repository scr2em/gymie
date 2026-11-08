import Foundation

/// Everything the app persists locally.
public struct AppState: Codable, Equatable, Sendable {
    public var settings = Preferences()
    public var profile = Profile()
    public var schedule = Schedule()
    public var activity: ActivityLog = [:]
    public var log: [BreakLogEntry] = []
    public var sync = SyncInfo()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(Preferences.self, forKey: .settings)) ?? Preferences()
        profile = (try? c.decodeIfPresent(Profile.self, forKey: .profile)) ?? Profile()
        schedule = (try? c.decodeIfPresent(Schedule.self, forKey: .schedule)) ?? Schedule()
        activity = (try? c.decodeIfPresent(ActivityLog.self, forKey: .activity)) ?? [:]
        log = (try? c.decodeIfPresent([BreakLogEntry].self, forKey: .log)) ?? []
        sync = (try? c.decodeIfPresent(SyncInfo.self, forKey: .sync)) ?? SyncInfo()
    }

    public static let logMax = 500
}

/// GitHub sync bookkeeping (the token itself lives in the Keychain).
public struct SyncInfo: Codable, Equatable, Sendable {
    public var login: String?
    public var githubName: String?
    public var lastPushAt: Date?
    public var lastAttemptAt: Date?
    public var lastFingerprint: String?
    public init() {}
}

public struct BreakLogEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var reps: Int
    public var moves: Int
    public var score: Int?
    public var xp: Int
    public var scored: Bool
    public var completed: Bool

    public init(at: Date, reps: Int, moves: Int, score: Int?, xp: Int, scored: Bool, completed: Bool) {
        self.at = at; self.reps = reps; self.moves = moves; self.score = score
        self.xp = xp; self.scored = scored; self.completed = completed
    }

    public init(_ result: BreakResult, xp: Int, at: Date) {
        self.init(
            at: at,
            reps: result.countedReps,
            moves: result.moves.filter(\.completed).count,
            score: result.scores.isEmpty ? nil : Int((result.averageForm).rounded()),
            xp: xp,
            scored: result.scored,
            completed: !result.moves.isEmpty && result.moves.allSatisfy(\.completed)
        )
    }
}

// MARK: - GitHub stats file

/// One player's file in the stats repo: `players/<github-login>.json`.
/// Each player only ever writes their own file, so pushes never conflict; the leaderboard
/// is built by reading every file in `players/`.
public struct PlayerStats: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schema: Int
    public var login: String
    public var name: String
    public var xp: Int
    public var level: Int
    public var levelName: String
    public var streak: Int
    public var week: String
    public var weekXp: Int
    public var breaksToday: Int
    public var totalBreaks: Int
    public var badges: [String]
    public var activity: ActivityLog
    public var profile: Profile
    public var updatedAt: Date
    public var app: String

    public init(login: String, name: String, state: AppState, now: Date, app: String) {
        let level = levelFor(state.profile.xp)
        schema = PlayerStats.schemaVersion
        self.login = login
        self.name = name.isEmpty ? login : name
        xp = state.profile.xp
        self.level = level.level
        levelName = level.name
        streak = state.profile.streak
        week = Clock.isoWeek(now)
        weekXp = state.profile.currentWeekXp(now: now)
        breaksToday = state.activity[Clock.dayKey(now)]?.breaks ?? 0
        totalBreaks = state.activity.values.reduce(0) { $0 + $1.breaks }
        badges = state.profile.badges
        activity = state.activity
        profile = state.profile
        updatedAt = now
        self.app = app
    }

    /// The same stats without the timestamp, to skip pushes when nothing changed.
    public func fingerprint() -> String {
        var copy = self
        copy.updatedAt = Date(timeIntervalSince1970: 0)
        copy.breaksToday = 0
        return (try? String(decoding: PlayerStats.encoder.encode(copy), as: UTF8.self)) ?? ""
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public struct BoardRow: Equatable, Sendable, Identifiable {
    public var rank: Int
    public var login: String
    public var name: String
    public var level: Int
    public var levelName: String
    public var xp: Int
    public var streak: Int
    public var isMe: Bool
    public var id: String { login }
}

public enum BoardPeriod: String, CaseIterable, Sendable { case week, all }

/// Ranks players by all-time XP or by this ISO week's XP (stale weeks count as 0).
public func rankBoard(_ players: [PlayerStats], period: BoardPeriod, me: String?, now: Date) -> [BoardRow] {
    let week = Clock.isoWeek(now)
    let score = { (p: PlayerStats) in period == .all ? p.xp : (p.week == week ? p.weekXp : 0) }
    let sorted = players.sorted {
        let a = score($0), b = score($1)
        return a != b ? a > b : $0.login.lowercased() < $1.login.lowercased()
    }
    var rows: [BoardRow] = []
    var rank = 0
    var lastScore: Int?
    for (i, p) in sorted.enumerated() {
        let s = score(p)
        if s != lastScore { rank = i + 1; lastScore = s }
        rows.append(BoardRow(rank: rank, login: p.login, name: p.name, level: p.level, levelName: p.levelName,
                             xp: s, streak: p.streak, isMe: p.login.lowercased() == me?.lowercased()))
    }
    return rows
}

/// "owner/name" or a github.com URL -> (owner, name).
public func parseRepo(_ text: String) -> (owner: String, name: String)? {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["https://github.com/", "http://github.com/", "github.com/", "git@github.com:"] where t.hasPrefix(prefix) {
        t = String(t.dropFirst(prefix.count))
    }
    if t.hasSuffix(".git") { t = String(t.dropLast(4)) }
    let parts = t.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count == 2 else { return nil }
    let ok = parts.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }
    return ok ? (String(parts[0]), String(parts[1])) : nil
}
