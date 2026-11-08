import XCTest
@testable import GymieCore

// Ported from Squat Overflow's extension/tests/check.mjs so the Swift port behaves the same.

private let M: TimeInterval = 60
private let H: TimeInterval = 3600
private let DAY: TimeInterval = 86_400
private let fri = Clock.date(2026, 11, 6, 11)
private let mon = Clock.date(2026, 11, 9, 11)
private let WORKDAYS = [1, 2, 3, 4, 5]
private let T0 = Clock.date(2026, 11, 9, 9)
private let HOURS = ActiveHours(activeStart: "09:00", activeEnd: "17:00", workdays: WORKDAYS)

private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { Clock.date(2026, 11, d, h, m) }

private func full(scores: Int = 100) -> BreakResult {
    BreakResult(scored: true, countedReps: 18, targetReps: 18, scores: Array(repeating: scores, count: 18),
                moves: [.init(key: "neck_tilt", area: "Neck tension", completed: true)])
}

private func brk(_ areas: [String], completed: Bool = true) -> BreakResult {
    BreakResult(scored: true, countedReps: 18, targetReps: 18, scores: Array(repeating: 80, count: 18),
                moves: areas.enumerated().map { .init(key: "k\($0.offset)", area: $0.element, completed: completed) })
}

private func fired() -> Schedule { Schedule.initial(now: T0, intervalMin: 60).onFire(now: T0 + H, intervalMin: 60) }

private func sched(_ nextAt: Date) -> Schedule {
    var s = Schedule.initial(now: Date(timeIntervalSince1970: 0), intervalMin: 60)
    s.nextAt = nextAt; s.skipsInRow = 2; s.snoozesInRow = 1
    return s
}

private func dayWith(_ id: String, hour: Int = 11) -> Date {
    for k in 0..<60 {
        let t = Clock.date(2026, 11, 9 + k, hour)
        if dailyFor(t).contains(id) { return t }
    }
    fatalError("no day with \(id)")
}

private func ids(_ r: (profile: Profile, completed: [CompletedChallenge], newBadges: [String])) -> [String] {
    r.completed.map(\.id)
}

final class XPTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(LEVELS.count, 8)
        XCTAssertEqual(levelFor(0).name, "Desk Potato")
        XCTAssertEqual(levelFor(99).level, 1)
        XCTAssertEqual(levelFor(100).name, "Chair Escapee")
        XCTAssertEqual(levelFor(3000).name, "Movement Master")
        XCTAssertNil(levelFor(3000).next)
        XCTAssertEqual(levelFor(3000).progress, 1)
        XCTAssertEqual(levelFor(175).progress, 0.5)
    }

    func testBreakXp() {
        XCTAssertEqual(breakXp(countedReps: 18, targetReps: 18, scores: Array(repeating: 100, count: 18)), 10)
        XCTAssertEqual(breakXp(countedReps: 9, targetReps: 18, scores: Array(repeating: 80, count: 9)), 4)
        XCTAssertEqual(breakXp(countedReps: 0, targetReps: 18, scores: []), 0)
    }

    func testIsoWeekAndDayKey() {
        XCTAssertEqual(Clock.isoWeek(mon), "2026-W46")
        XCTAssertEqual(Clock.isoWeek(fri), "2026-W45")
        XCTAssertEqual(Clock.dayKey(fri), "2026-11-06")
    }

    func testFirstBreakBonusesAndStreak() {
        let dailyIds = dailyFor(mon)
        var p0 = Profile()
        p0.daily = .init(day: Clock.dayKey(mon), ids: dailyIds, areas: [], breaks: 0, run: 0, done: dailyIds)
        p0.weekly = .init(week: Clock.isoWeek(mon), area: featuredArea(mon), count: 10, done: true)
        p0.xp = 95; p0.streak = 2; p0.lastStreakDay = Clock.dayKey(fri)
        let r = award(p0, full(), now: mon, workdays: WORKDAYS)
        XCTAssertEqual(r.profile.streak, 3)
        XCTAssertEqual([r.breakdown.breakXp, r.breakdown.firstBreak, r.breakdown.streak], [10, 5, 3])
        XCTAssertEqual(r.breakdown.total, 18)
        XCTAssertEqual(r.profile.xp, 113)
        XCTAssertEqual(r.levelUp, LevelUp(from: 1, to: 2, name: "Chair Escapee"))
    }

    func testSecondBreakSameDayHasNoBonus() {
        let first = award(Profile(), full(), now: mon, workdays: WORKDAYS).profile
        let r = award(first, full(), now: mon + H, workdays: WORKDAYS)
        XCTAssertEqual(r.breakdown.total, 10)
        XCTAssertEqual(r.profile.streak, 1)
    }

    func testUnscoredDoneEarnsNothing() {
        var p0 = Profile(); p0.xp = 40; p0.streak = 4; p0.lastStreakDay = Clock.dayKey(fri)
        var result = full(); result.scored = false
        let r = award(p0, result, now: mon, workdays: WORKDAYS)
        XCTAssertEqual(r.breakdown.total, 0)
        XCTAssertEqual(r.profile.xp, 40)
        XCTAssertEqual(r.profile.streak, 4)
        XCTAssertEqual(r.profile.lastBreakDay, Clock.dayKey(mon))
        XCTAssertNil(r.levelUp)
    }

    func testWorkdayGapResetsStreak() {
        var p0 = Profile(); p0.streak = 5; p0.lastStreakDay = Clock.dayKey(fri - DAY)
        XCTAssertEqual(award(p0, full(), now: mon, workdays: WORKDAYS).profile.streak, 1)
    }

    func testNewWeekResetsWeekXp() {
        var p0 = Profile(); p0.week = "2026-W45"; p0.weekXp = 200
        let r = award(p0, full(), now: mon, workdays: WORKDAYS)
        XCTAssertEqual(r.profile.week, "2026-W46")
        XCTAssertEqual(r.profile.weekXp, r.breakdown.total)
    }

    func testWeekendBreakKeepsStreak() {
        let sat = Clock.date(2026, 11, 7, 11)
        var p0 = Profile(); p0.streak = 3; p0.lastStreakDay = Clock.dayKey(fri)
        let afterSat = award(p0, full(), now: sat, workdays: WORKDAYS).profile
        XCTAssertEqual(award(afterSat, full(), now: mon, workdays: WORKDAYS).profile.streak, afterSat.streak + 1)
    }

    func testAwardTotalIncludesChallengeBonuses() {
        let t = dayWith("clean_form")
        let r = award(Profile(), full(scores: 95), now: t, workdays: WORKDAYS)
        let bonus = r.breakdown.challenges.reduce(0) { $0 + $1.bonus }
        XCTAssertTrue(r.breakdown.challenges.contains { $0.id == "clean_form" })
        XCTAssertEqual(r.breakdown.total, r.breakdown.breakXp + r.breakdown.firstBreak + r.breakdown.streak + bonus)
    }
}

final class ChallengeTests: XCTestCase {
    func testDailyForIsStableAndVaries() {
        let a = dailyFor(mon)
        XCTAssertEqual(a, dailyFor(mon + H))
        XCTAssertTrue((2...5).contains(a.count))
        XCTAssertEqual(Set(a).count, a.count)
        let seen = Set((0..<7).map { dailyFor(mon + Double($0) * DAY).joined(separator: ",") })
        XCTAssertGreaterThan(seen.count, 1)
    }

    func testSeedHashMatchesJavaScript() {
        // JS: let h = 7; for (const ch of "2026-11-09") h = (h * 31 + ch.charCodeAt(0)) >>> 0;
        var h: UInt64 = 7
        for u in "2026-11-09".utf16 { h = (h * 31 + UInt64(u)) % 4_294_967_296 }
        XCTAssertEqual(UInt64(seedHash("2026-11-09")), h)
    }

    func testVarietyOnThirdArea() {
        let t = dayWith("variety")
        var r = updateChallenges(Profile(), brk(["Neck tension", "Shoulder & rotator cuff"]), avgForm: 80, now: t)
        XCTAssertFalse(ids(r).contains("variety"))
        r = updateChallenges(r.profile, brk(["Neck tension", "Wrist & hand"]), avgForm: 80, now: t + M)
        XCTAssertTrue(ids(r).contains("variety"))
        XCTAssertTrue(r.newBadges.contains("daily:variety"))
        r = updateChallenges(r.profile, brk(["Lower back"]), avgForm: 80, now: t + 2 * M)
        XCTAssertFalse(ids(r).contains("variety"))
    }

    func testNoExcusesResetsAfterSkip() {
        let t = dayWith("no_excuses")
        var r = updateChallenges(Profile(), brk(["Neck tension"]), avgForm: 80, now: t)
        r = updateChallenges(r.profile, brk(["Neck tension"]), avgForm: 80, now: t + M)
        let p = noteAction(r.profile, .skip, now: t + 2 * M)
        r = updateChallenges(p, brk(["Neck tension"]), avgForm: 80, now: t + 3 * M)
        XCTAssertFalse(ids(r).contains("no_excuses"))
        r = updateChallenges(r.profile, brk(["Neck tension"]), avgForm: 80, now: t + 4 * M)
        r = updateChallenges(r.profile, brk(["Neck tension"]), avgForm: 80, now: t + 5 * M)
        XCTAssertTrue(ids(r).contains("no_excuses"))
    }

    func testEarlyMover() {
        let t = dayWith("early_mover", hour: 9)
        let at959 = Clock.at(minutes: 9 * 60 + 59, on: t)
        let at1000 = Clock.at(minutes: 10 * 60, on: t)
        XCTAssertTrue(ids(updateChallenges(Profile(), brk(["Neck tension"]), avgForm: 80, now: at959)).contains("early_mover"))
        XCTAssertFalse(ids(updateChallenges(Profile(), brk(["Neck tension"]), avgForm: 80, now: at1000)).contains("early_mover"))
    }

    func testCleanForm() {
        let t = dayWith("clean_form")
        XCTAssertTrue(ids(updateChallenges(Profile(), brk(["Neck tension"]), avgForm: 90, now: t)).contains("clean_form"))
        XCTAssertFalse(ids(updateChallenges(Profile(), brk(["Neck tension"]), avgForm: 89, now: t)).contains("clean_form"))
    }

    func testWeeklyFeaturedArea() {
        let area = featuredArea(mon)
        var r = updateChallenges(Profile(), brk(Array(repeating: area, count: 9)), avgForm: 80, now: mon)
        XCTAssertEqual(r.profile.weekly?.count, 9)
        r = updateChallenges(r.profile, brk([area, "Neck tension"]), avgForm: 80, now: mon + M)
        XCTAssertEqual(r.completed.first { $0.id == "weekly" }?.bonus, WeeklyRules.bonus)
        XCTAssertTrue(r.newBadges.contains("weekly:\(area)"))
        let next = updateChallenges(r.profile, brk(["Neck tension"], completed: false), avgForm: 80, now: mon + 7 * DAY)
        XCTAssertEqual(next.profile.weekly?.count, 0)
        XCTAssertEqual(next.profile.weekly?.area, featuredArea(mon + 7 * DAY))
    }

    func testFeaturedAreaSkipsEyes() {
        let seen = Set((0..<14).map { featuredArea(mon + Double($0) * 7 * DAY) })
        XCTAssertEqual(seen, Set(FEATURED_AREAS))
        XCTAssertFalse(seen.contains("Eyes"))
    }
}

final class ScheduleTests: XCTestCase {
    func testInitialAndOnFireKeepGrid() {
        XCTAssertEqual(Schedule.initial(now: T0, intervalMin: 60).nextAt, T0 + H)
        XCTAssertEqual(fired().nextAt, T0 + 2 * H)
    }

    func testDoneKeepsGrid() {
        XCTAssertEqual(fired().apply(.done, now: T0 + H + 5 * M, intervalMin: 60).nextAt, T0 + 2 * H)
    }

    func testSnoozeShiftsAndCaps() {
        let s1 = fired().apply(.snooze, now: T0 + H + M, intervalMin: 60)
        XCTAssertEqual(s1.nextAt, T0 + H + 21 * M)
        XCTAssertEqual(s1.snoozesInRow, 1)
        XCTAssertEqual(s1.shiftedBy, 20)
        let s2 = s1.onFire(now: s1.nextAt!, intervalMin: 60).apply(.snooze, now: s1.nextAt! + M, intervalMin: 60)
        XCTAssertEqual(s2.snoozesInRow, Schedule.snoozeCap)
        XCTAssertFalse(s2.canSnooze)
        let s3 = s2.apply(.snooze, now: s2.nextAt! + M, intervalMin: 60)
        XCTAssertEqual(s3.nextAt, s2.nextAt)
        XCTAssertEqual(s3.snoozesInRow, 2)
    }

    func testSkipKeepsGridAndCounts() {
        var f = fired(); f.snoozesInRow = 1
        let s = f.apply(.skip, now: T0 + H + M, intervalMin: 60)
        XCTAssertEqual(s.nextAt, T0 + 2 * H)
        XCTAssertEqual(s.skipsInRow, 1)
        XCTAssertEqual(s.snoozesInRow, 0)
    }

    func testCloseCountsAsSkipOnce() {
        var f = fired(); f.reminderOpen = true
        let s = f.apply(.close, now: T0 + H + M, intervalMin: 60)
        XCTAssertEqual(s.skipsInRow, 1)
        XCTAssertFalse(s.reminderOpen)
        XCTAssertEqual(s.apply(.close, now: T0 + H + M, intervalMin: 60).skipsInRow, 1)
    }

    func testCloseAfterDoneIgnored() {
        var f = fired(); f.reminderOpen = true
        let done = f.apply(.done, now: T0 + H + M, intervalMin: 60)
        XCTAssertEqual(done.apply(.close, now: T0 + H + 2 * M, intervalMin: 60).skipsInRow, 0)
    }

    func testWarning() {
        var f = fired(); f.skipsInRow = 2
        XCTAssertFalse(f.showWarning)
        f.skipsInRow = 3
        XCTAssertTrue(f.showWarning)
        XCTAssertEqual(Schedule.warningHours(skips: 3, intervalMin: 60), 3)
        XCTAssertEqual(Schedule.warningHours(skips: 3, intervalMin: 45), 2.5)
        XCTAssertEqual(Schedule.warningHours(skips: 3, intervalMin: 30), 1.5)
    }

    func testPauseKeepsCounters() {
        var f = fired(); f.skipsInRow = 3; f.snoozesInRow = 1
        let s = f.apply(.pause, now: T0 + H + M, intervalMin: 60)
        XCTAssertEqual(s.nextAt, T0 + H + 61 * M)
        XCTAssertEqual(s.pausedUntil, T0 + H + 61 * M)
        XCTAssertEqual([s.skipsInRow, s.snoozesInRow], [3, 1])
    }

    func testRescheduleAndUpcoming() {
        XCTAssertEqual(fired().rescheduled(now: T0 + H + 10 * M, intervalMin: 30).nextAt, T0 + H + 40 * M)
        let now = T0 + H + M
        let s = fired().apply(.snooze, now: now, intervalMin: 60)
        XCTAssertEqual(s.upcoming(intervalMin: 60), [now + 20 * M, now + 80 * M, now + 140 * M])
    }

    func testNextActiveSlot() {
        XCTAssertEqual(nextActiveSlot(at(9, 11), intervalMin: 60, hours: HOURS), at(9, 11))
        XCTAssertEqual(nextActiveSlot(at(13, 17, 30), intervalMin: 60, hours: HOURS), at(16, 10))
        XCTAssertEqual(nextActiveSlot(at(14, 11), intervalMin: 60, hours: HOURS), at(16, 10))
        XCTAssertEqual(nextActiveSlot(at(9, 7), intervalMin: 60, hours: HOURS), at(9, 10))
        XCTAssertTrue(isActive(at(9, 16, 59), HOURS))
        XCTAssertFalse(isActive(at(9, 17), HOURS))
    }

    private func decide(_ s: Schedule, _ now: Date, idle: IdleState = .active, meeting: Bool = false, autoPause: Bool = true) -> FireDecision {
        decideFire(s, now: now, intervalMin: 60, idle: idle, meeting: meeting, autoPause: autoPause, hours: HOURS)
    }

    func testWeekendIsOutside() {
        let r = decide(sched(at(14, 11)), at(14, 11))
        XCTAssertEqual(r.kind, .outside)
        XCTAssertEqual(r.schedule.nextAt, at(16, 10))
    }

    func testLateAlarmDropped() {
        let r = decide(sched(at(9, 11)), at(9, 11, 11))
        XCTAssertEqual(r.kind, .late)
        XCTAssertEqual(r.schedule.nextAt, at(9, 12, 11))
        XCTAssertEqual([r.schedule.skipsInRow, r.schedule.snoozesInRow], [2, 1])
    }

    func testMeetingDefersRepeatedly() {
        let r1 = decide(sched(at(9, 11)), at(9, 11), meeting: true)
        XCTAssertEqual(r1.kind, .defer)
        XCTAssertEqual(r1.schedule.nextAt, at(9, 11, 5))
        let r2 = decide(r1.schedule, at(9, 11, 40), meeting: true)
        XCTAssertEqual(r2.kind, .defer)
        XCTAssertEqual(r2.schedule.nextAt, at(9, 11, 45))
        XCTAssertEqual([r2.schedule.skipsInRow, r2.schedule.snoozesInRow], [2, 1])
    }

    func testMeetingClearsOpensOnceGridNotStacked() {
        let r1 = decide(sched(at(9, 11)), at(9, 11), meeting: true)
        var s = r1.schedule; s.nextAt = at(9, 12, 10)
        let r2 = decide(s, at(9, 12, 10))
        XCTAssertEqual(r2.kind, .open)
        XCTAssertEqual(r2.schedule.nextAt, at(9, 13))
        XCTAssertNil(r2.schedule.deferredFrom)
    }

    func testMeetingIgnoredWithoutAutoPause() {
        XCTAssertEqual(decide(sched(at(9, 11)), at(9, 11), meeting: true, autoPause: false).kind, .open)
    }

    func testIdleIsAway() {
        let r = decide(sched(at(9, 11)), at(9, 11), idle: .idle)
        XCTAssertEqual(r.kind, .away)
        XCTAssertEqual(r.schedule.nextAt, at(9, 12))
        XCTAssertEqual([r.schedule.skipsInRow, r.schedule.snoozesInRow], [2, 1])
    }

    func testNormalFireOpens() {
        let r = decide(sched(at(9, 11)), at(9, 11) + 30)
        XCTAssertEqual(r.kind, .open)
        XCTAssertEqual(r.schedule.nextAt, at(9, 12))
    }

    func testLastSlotRollsToNextMorning() {
        let r = decide(sched(at(13, 16, 30)), at(13, 16, 30))
        XCTAssertEqual(r.kind, .open)
        XCTAssertEqual(r.schedule.nextAt, at(16, 10))
    }

    func testCountdownText() {
        XCTAssertEqual(countdownText(0), "move")
        XCTAssertEqual(countdownText(44.2), "45s")
        XCTAssertEqual(countdownText(23 * 60), "23m")
        XCTAssertEqual(countdownText(150 * 60), "3h")
    }

    func testScheduleSettingsChanged() {
        var a = Preferences(), b = Preferences()
        b.blurCamera.toggle()
        XCTAssertFalse(Preferences.scheduleChanged(a, b))
        b.workdays = [5, 4, 3, 2, 1]
        XCTAssertFalse(Preferences.scheduleChanged(a, b))
        a.intervalMin = 45
        XCTAssertTrue(Preferences.scheduleChanged(a, b))
    }
}

final class RoutineTests: XCTestCase {
    let catalog = Catalog.bundled

    func testBundledCatalogHasFivePerArea() {
        for area in AREAS { XCTAssertEqual(catalog.filter { $0.category == area }.count, 5, area) }
    }

    func testOnlySelectedAreasNoDupes() {
        let moves = buildRoutine(catalog, areas: ["Neck tension", "Knees"], lastKey: nil, n: 0)
        XCTAssertEqual(moves.count, 3)
        XCTAssertTrue(moves.allSatisfy { ["Neck tension", "Knees"].contains($0.area) })
        XCTAssertEqual(Set(moves.map(\.key)).count, 3)
    }

    func testAvoidsLastKeyInSlotOne() {
        let first = buildRoutine(catalog, areas: ["Neck tension"], lastKey: nil, n: 0)[0]
        XCTAssertNotEqual(buildRoutine(catalog, areas: ["Neck tension"], lastKey: first.key, n: 0)[0].key, first.key)
    }

    func testSwapMove() {
        let moves = buildRoutine(catalog, areas: ["Neck tension"], lastKey: nil, n: 0)
        let swapped = swapMove(catalog, moves: moves, at: 0)
        XCTAssertEqual(swapped?.area, "Neck tension")
        XCTAssertFalse(moves.contains { $0.key == swapped?.key })
    }

    func testNextOpenMove() {
        let moves = buildRoutine(catalog, areas: ["Neck tension"], lastKey: nil, n: 0)
        XCTAssertEqual(nextOpenMove(moves, reps: [6, 0, 0], from: 0), 1)
        XCTAssertEqual(nextOpenMove(moves, reps: [6, 6, 0], from: 1), 2)
        XCTAssertNil(nextOpenMove(moves, reps: [6, 6, 6], from: 2))
    }

    func testCurrentAreasMapsLegacyNames() {
        XCTAssertEqual(currentAreas(["Neck", "Upper back & posture", "Bogus"]), ["Neck tension", "Rounded shoulders", "Upper back"])
    }

    func testHealthURL() {
        XCTAssertEqual(Catalog.healthURL(forPoseServer: "ws://127.0.0.1:8765/ws")?.absoluteString, "http://127.0.0.1:8765/health")
    }

    func testOnlyLocalPoseServers() {
        XCTAssertTrue(isLocalPoseURL("ws://127.0.0.1:8765/ws"))
        XCTAssertTrue(isLocalPoseURL("ws://localhost:9000/ws"))
        XCTAssertFalse(isLocalPoseURL("wss://squat-overflow-pose.fly.dev/ws"))
        XCTAssertFalse(isLocalPoseURL("ws://192.168.1.5:8765/ws"))
    }

    func testSavedRemotePoseURLFallsBackToLocal() throws {
        let json = #"{"poseServerURL":"wss://squat-overflow-pose.fly.dev/ws","intervalMin":45}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.poseServerURL, Defaults.poseServerURL)
        XCTAssertEqual(prefs.intervalMin, 45)
    }
}

final class ActivityAndStatsTests: XCTestCase {
    func testActivityLevels() {
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 7].map(activityLevel), [0, 1, 1, 2, 2, 3, 3, 4])
    }

    func testRecordActivityDropsOldDays() {
        let old = Clock.dayKey(mon - 400 * DAY)
        let a = recordActivity([old: DayActivity(breaks: 1, xp: 1)], now: mon, xp: 12)
        XCTAssertNil(a[old])
        XCTAssertEqual(a[Clock.dayKey(mon)], DayActivity(breaks: 1, xp: 12))
    }

    func testHeatmapShape() {
        let weeks = heatmapWeeks([:], now: mon, weeks: 4, workdays: WORKDAYS)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(Clock.weekday(weeks[0][0].date), 1) // Monday
        XCTAssertEqual(weeks[3][0].day, Clock.dayKey(mon))
        XCTAssertTrue(weeks[3][1].future)
        XCTAssertTrue(weeks[3][5].offday)
    }

    func testRankBoard() {
        var state = AppState()
        state.profile.xp = 300; state.profile.week = Clock.isoWeek(mon); state.profile.weekXp = 40
        let a = PlayerStats(login: "alice", name: "Alice", state: state, now: mon, app: "t")
        state.profile.xp = 500; state.profile.week = "2026-W40"; state.profile.weekXp = 90
        let b = PlayerStats(login: "bob", name: "", state: state, now: mon, app: "t")
        XCTAssertEqual(b.weekXp, 0) // stale week
        XCTAssertEqual(rankBoard([a, b], period: .all, me: "Alice", now: mon).map(\.login), ["bob", "alice"])
        let week = rankBoard([a, b], period: .week, me: "alice", now: mon)
        XCTAssertEqual(week.map(\.login), ["alice", "bob"])
        XCTAssertTrue(week[0].isMe)
        XCTAssertEqual(b.name, "bob")
    }

    func testStatsRoundTripAndFingerprint() throws {
        let s = PlayerStats(login: "me", name: "Me", state: AppState(), now: mon, app: "t")
        let data = try PlayerStats.encoder.encode(s)
        let back = try PlayerStats.decoder.decode(PlayerStats.self, from: data)
        XCTAssertEqual(back.login, "me")
        var later = s; later.updatedAt = mon + H
        XCTAssertEqual(s.fingerprint(), later.fingerprint())
    }

    func testParseGhAuthStatus() {
        let out = """
        github.com
          ✓ Logged in to github.com account octocat (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'gist', 'read:org', 'repo', 'workflow'

          ✓ Logged in to github.com account hubot (keyring)
          - Active account: false
          - Token scopes: 'gist', 'repo'

          X Failed to log in to github.com account old-me (keyring)
          - Active account: false
        """
        let accounts = parseGhAuthStatus(out)
        XCTAssertEqual(accounts.map(\.login), ["octocat", "hubot", "old-me"])
        XCTAssertEqual(accounts.map(\.active), [true, false, false])
        XCTAssertEqual(accounts.map(\.ok), [true, true, false])
    }

    func testParseRepo() {
        XCTAssertEqual(parseRepo("me/gymie-data")?.name, "gymie-data")
        XCTAssertEqual(parseRepo("https://github.com/me/gymie-data.git")?.owner, "me")
        XCTAssertNil(parseRepo("nope"))
    }

    func testPoseFrameDecodes() throws {
        let json = #"{"type":"frame","exercise":"neck_tilt","stage":"rest","angle":12.5,"feedback":[],"rep_event":{"index":1,"duration_s":1.2,"peak_angle":30,"rom":20,"issues":[],"score":85,"partial":false,"issue_text":[]},"summary":{"reps":1,"good_reps":1,"partial_reps":0,"avg_duration_s":1.2,"avg_rom":20,"avg_score":85,"top_issues":[]},"landmarks":[[0.5,0.5,0.9]],"latency_ms":20}"#
        guard case .frame(let f) = PoseMessage.decode(Data(json.utf8)) else { return XCTFail("not a frame") }
        XCTAssertEqual(f.rep_event?.score, 85)
        XCTAssertEqual(f.summary.reps, 1)
        XCTAssertFalse(f.notVisible)
    }
}
