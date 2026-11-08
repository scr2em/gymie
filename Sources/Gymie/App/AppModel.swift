import AppKit
import GymieCore
import Observation

/// The app's brain: owns persisted state, drives the break schedule from a 1-second
/// wall-clock tick (so it survives sleep), and routes actions from the views.
@MainActor @Observable
final class AppModel {
    static let shared = SnapshotMode.isActive ? AppModel(demo: SnapshotMode.demoState()) : AppModel()

    var state: AppState {
        didSet { if state != oldValue { persistence.save(state) } }
    }
    /// Updated every second; views that show countdowns read it.
    var now = Date()
    var catalog: [Exercise] = Catalog.bundled
    /// Why the last reminder was held back, for the dashboard ("In a meeting until 15:00").
    var holdReason: String?
    var nextMeeting: CalendarBusy.Event?

    let persistence: Persistence
    /// Snapshot mode: in-memory demo data, no network, no camera.
    let isDemo: Bool
    let presence = Presence()
    let calendar = CalendarBusy()
    let notifier = Notifier()
    let hotKey = HotKey()
    let windows = WindowManager()
    let sync: StatsSync
    let poseServer: LocalPoseServer

    private var ticker: Timer?
    private var firing = false
    private var headsUpFor: Date?
    private var lastMinuteWork = Date.distantPast
    private(set) var breakSession: BreakSession?

    private init(demo: AppState? = nil) {
        isDemo = demo != nil
        persistence = demo == nil ? Persistence()
            : Persistence(dir: FileManager.default.temporaryDirectory.appendingPathComponent("gymie-snapshots-\(ProcessInfo.processInfo.processIdentifier)"))
        state = demo ?? persistence.load()
        sync = StatsSync()
        poseServer = LocalPoseServer(supportDir: persistence.dir)
        catalog = persistence.loadCatalog() ?? Catalog.bundled
    }

    // MARK: - Lifecycle

    func start() {
        sync.model = self
        state.schedule.reminderOpen = false
        ensureSchedule()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.2
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        notifier.setUp(onStart: { [weak self] in self?.startScheduledBreakNow() },
                       onSnooze: { [weak self] in self?.snoozeUpcoming() })
        hotKey.action = { [weak self] in self?.breakNow() }
        applySystemSettings()
        refreshCalendar()
        if !state.settings.setupDone { windows.showSettings(model: self) }
        sync.pushIfDue(force: false)
    }

    private func tick() {
        now = Date()
        guard state.settings.setupDone, let nextAt = state.schedule.nextAt else { return }
        let left = nextAt.timeIntervalSince(now)
        if left <= 0, !firing {
            Task { await fire() }
        } else if left <= 60, left > 0, state.settings.headsUpNotification, state.settings.intervalMin >= 5,
                  headsUpFor != nextAt, breakSession == nil {
            headsUpFor = nextAt
            notifier.headsUp(at: nextAt, canSnooze: state.schedule.canSnooze)
        }
        if now.timeIntervalSince(lastMinuteWork) >= 60 {
            lastMinuteWork = now
            refreshCalendar()
            sync.pushIfDue(force: false)
        }
    }

    private func ensureSchedule() {
        guard state.settings.setupDone else { return }
        if state.schedule.nextAt == nil {
            var s = Schedule.initial(now: Date(), intervalMin: state.settings.intervalMin)
            s.lastKey = state.schedule.lastKey
            s.breakCount = state.schedule.breakCount
            saveSchedule(s)
        }
    }

    /// Every stored next time is moved into active hours, as the extension's saveSchedule does.
    private func saveSchedule(_ schedule: Schedule) {
        var s = schedule
        if let next = s.nextAt {
            s.nextAt = nextActiveSlot(next, intervalMin: state.settings.intervalMin, hours: state.settings.hours)
        }
        state.schedule = s
    }

    // MARK: - Firing

    private func fire() async {
        firing = true
        defer { firing = false }
        let settings = state.settings
        let at = Date()
        let idle = presence.idleState()
        let held = settings.autoPause ? presence.meetingReason(settings: settings) : nil
        let block = settings.autoPause && settings.pauseForCalendarEvents ? calendar.currentBlock(now: at) : nil
        let meeting = held != nil || block != nil
        var decision = decideFire(state.schedule, now: at, intervalMin: settings.intervalMin, idle: idle,
                                  meeting: meeting, autoPause: settings.autoPause, hours: settings.hours)
        if decision.kind == .defer, let block {
            decision.schedule.nextAt = max(decision.schedule.nextAt!, block.end + 60)
        }
        switch decision.kind {
        case .defer: holdReason = held ?? block.map { "In “\($0.title)” until \($0.end.formatted(date: .omitted, time: .shortened))" }
        case .away: holdReason = idle == .locked ? "Skipped: screen was locked" : "Skipped: you were away"
        default: holdReason = nil
        }
        saveSchedule(decision.schedule)
        guard decision.kind == .open, breakSession == nil else { return }
        openBreak(manual: false)
    }

    // MARK: - Break windows

    func breakNow() {
        if breakSession != nil { windows.focusBreak(); return }
        openBreak(manual: true)
    }

    /// "Start now" from the heads-up notification: fire the scheduled reminder early.
    func startScheduledBreakNow() {
        guard breakSession == nil else { windows.focusBreak(); return }
        state.schedule.nextAt = Date()
        tick()
    }

    func snoozeUpcoming() {
        let at = Date()
        state.profile = noteAction(state.profile, .snooze, now: at)
        saveSchedule(state.schedule.apply(.snooze, now: at, intervalMin: state.settings.intervalMin))
    }

    private func openBreak(manual: Bool) {
        let showWarning = !manual && state.schedule.showWarning
        let moves = buildRoutine(catalog, areas: state.settings.areas.isEmpty ? Array(AREAS.prefix(2)) : state.settings.areas,
                                 lastKey: state.schedule.lastKey, n: state.schedule.breakCount)
        let session = BreakSession(model: self, moves: moves, manual: manual, warning: showWarning)
        breakSession = session
        if !manual { state.schedule.reminderOpen = true }
        notifier.clearHeadsUp()
        windows.showBreak(session: session) { [weak self] in self?.breakWindowClosed() }
    }

    private func breakWindowClosed() {
        breakSession?.stop()
        breakSession = nil
        guard state.schedule.reminderOpen else { return }
        let at = Date()
        state.profile = noteAction(state.profile, .close, now: at)
        saveSchedule(state.schedule.apply(.close, now: at, intervalMin: state.settings.intervalMin))
    }

    /// Done: award XP, log the break, keep the grid. Returns what the summary screen shows.
    func completeBreak(_ result: BreakResult, lastKey: String?) -> Award {
        let at = Date()
        let award = GymieCore.award(state.profile, result, now: at, workdays: state.settings.workdays)
        var next = state
        next.profile = award.profile
        next.activity = recordActivity(state.activity, now: at, xp: award.breakdown.total)
        next.log = Array((state.log + [BreakLogEntry(result, xp: award.breakdown.total, at: at)]).suffix(AppState.logMax))
        var s = state.schedule.apply(.done, now: at, intervalMin: state.settings.intervalMin)
        s.lastKey = lastKey ?? s.lastKey
        s.breakCount += 1
        next.schedule = s
        state = next
        saveSchedule(state.schedule)
        holdReason = nil
        if award.breakdown.total > 0 { sync.pushSoon() }
        return award
    }

    func breakAction(_ action: Schedule.Action) {
        let at = Date()
        state.profile = noteAction(state.profile, action, now: at)
        saveSchedule(state.schedule.apply(action, now: at, intervalMin: state.settings.intervalMin))
    }

    func closeBreakWindow() { windows.closeBreak() }

    // MARK: - Pause / resume

    var isPaused: Bool { (state.schedule.pausedUntil ?? .distantPast) > now }

    func pause() {
        breakAction(.pause)
    }

    func resume() {
        var s = state.schedule.rescheduled(now: Date(), intervalMin: state.settings.intervalMin)
        s.pausedUntil = nil
        saveSchedule(s)
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout Preferences) -> Void) {
        let before = state.settings
        var after = before
        change(&after)
        guard after != before else { return }
        state.settings = after
        if after.setupDone {
            if state.schedule.nextAt == nil || !before.setupDone {
                var s = Schedule.initial(now: Date(), intervalMin: after.intervalMin)
                s.lastKey = state.schedule.lastKey
                s.breakCount = state.schedule.breakCount
                s.skipsInRow = state.schedule.skipsInRow
                saveSchedule(s)
            } else if Preferences.scheduleChanged(before, after) {
                saveSchedule(state.schedule.rescheduled(now: Date(), intervalMin: after.intervalMin))
            }
        }
        if before.launchAtLogin != after.launchAtLogin || before.hotKeyEnabled != after.hotKeyEnabled
            || before.headsUpNotification != after.headsUpNotification {
            applySystemSettings()
        }
        if before.pauseForCalendarEvents != after.pauseForCalendarEvents { refreshCalendar() }
        if before.displayName != after.displayName { sync.pushSoon() }
    }

    func finishSetup() {
        updateSettings { $0.setupDone = true }
        notifier.requestAuthorization()
    }

    private func applySystemSettings() {
        let s = state.settings
        if s.hotKeyEnabled { hotKey.register() } else { hotKey.unregister() }
        LaunchAtLogin.set(s.launchAtLogin)
        if s.headsUpNotification && s.setupDone { notifier.requestAuthorization() }
    }

    func refreshCalendar() {
        guard state.settings.pauseForCalendarEvents, calendar.authorized else { nextMeeting = nil; return }
        nextMeeting = calendar.nextMeeting(now: Date())
    }

    // MARK: - Pose engine and catalog

    /// Starts (or finds) the local pose engine; returns an error message or nil.
    func preparePoseEngine() async -> String? {
        await poseServer.ensureRunning(url: state.settings.poseServerURL, manage: state.settings.managePoseServer)
    }

    /// The local pose engine sends its exercise catalog when a session connects.
    func updateCatalog(_ exercises: [Exercise]) {
        guard !exercises.isEmpty, exercises != catalog else { return }
        catalog = exercises
        persistence.saveCatalog(exercises)
    }

    func shutdown() {
        breakSession?.stop()
        poseServer.stop()
    }

    // MARK: - Derived values for the dashboard

    var level: LevelInfo { levelFor(state.profile.xp) }
    var todayBreaks: Int { state.activity[Clock.dayKey(now)]?.breaks ?? 0 }
    var profileForToday: Profile { withPeriods(state.profile, now: now) }

    var menuTitle: String {
        guard state.settings.setupDone else { return "Set up" }
        if isPaused { return "paused" }
        guard let next = state.schedule.nextAt else { return "" }
        return countdownText(next.timeIntervalSince(now))
    }

    var menuSymbol: String {
        guard let next = state.schedule.nextAt, state.settings.setupDone else { return "figure.stand" }
        if breakSession != nil { return "figure.cooldown" }
        if isPaused { return "pause.circle" }
        return next.timeIntervalSince(now) <= 60 ? "figure.run" : "figure.stand"
    }
}
