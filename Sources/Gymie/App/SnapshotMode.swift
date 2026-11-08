import AppKit
import CoreImage
import GymieCore
import SwiftUI

/// `Gymie --snapshots <dir>` renders the main screens offscreen with demo data and writes
/// light and dark PNGs for the README. It uses a temporary data folder, never opens the camera,
/// never starts the pose engine and makes no network calls.
@MainActor
enum SnapshotMode {
    nonisolated static var outputDir: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots") else { return nil }
        return URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "docs/screenshots")
    }

    nonisolated static var isActive: Bool { outputDir != nil }

    /// A fixed weekday late morning, so the screenshots don't depend on when they're made.
    static let demoNow = Clock.date(2026, 11, 5, 11, 37)

    // MARK: Demo data

    static func demoState() -> AppState {
        let now = demoNow
        var s = AppState()
        s.settings.setupDone = true
        s.settings.intervalMin = 45
        s.settings.areas = ["Neck tension", "Rounded shoulders", "Upper back", "Wrist & hand"]
        s.settings.pauseForCalendarEvents = true
        s.settings.displayName = "Alex Rivera"
        s.settings.githubRepo = "alex/gymie-data"
        s.settings.githubAuth = "gh"
        s.settings.githubAccount = "alex"
        s.settings.githubSyncEnabled = true
        s.sync.login = "alex"
        s.sync.lastPushAt = now.addingTimeInterval(-14 * 60)

        var p = Profile()
        p.xp = 742
        p.streak = 6
        p.lastStreakDay = Clock.dayKey(now)
        p.lastBreakDay = Clock.dayKey(now)
        p.week = Clock.isoWeek(now)
        p.weekXp = 118
        p.badges = ["daily:variety", "daily:early_mover", "daily:clean_form", "weekly:Neck tension", "weekly:Upper back"]
        let daily = dailyFor(now)
        p.daily = .init(day: Clock.dayKey(now), ids: daily, areas: ["Neck tension", "Upper back"], breaks: 3, run: 2,
                        done: Array(daily.prefix(1)))
        p.weekly = .init(week: Clock.isoWeek(now), area: featuredArea(now), count: 7, done: false)
        s.profile = p

        // 16 weeks of believable activity (deterministic).
        var seed: UInt64 = 42
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for back in 0..<112 {
            let day = Clock.addDays(-back, to: now)
            guard s.settings.workdays.contains(Clock.weekday(day)) else { continue }
            let breaks = back == 0 ? 3 : max(0, next() % 7 - (back > 80 ? 3 : 0))
            if breaks > 0 { s.activity[Clock.dayKey(day)] = DayActivity(breaks: breaks, xp: breaks * 9) }
        }

        var sched = Schedule()
        sched.nextAt = now.addingTimeInterval(23 * 60)
        sched.breakCount = 41
        s.schedule = sched
        return s
    }

    static func demoBoard(me: AppState) -> [PlayerStats] {
        let now = demoNow
        let others: [(String, String, Int, Int, Int)] = [
            ("sam", "Sam Chen", 1210, 164, 9), ("priya", "Priya Nair", 980, 131, 4),
            ("jordan", "Jordan Lee", 655, 142, 3), ("mia", "Mia Park", 430, 75, 2), ("chris", "Chris Okafor", 260, 38, 1),
        ]
        var players = [PlayerStats(login: "alex", name: "Alex Rivera", state: me, now: now, app: "demo")]
        for (login, name, xp, weekXp, streak) in others {
            var st = AppState()
            st.profile.xp = xp
            st.profile.weekXp = weekXp
            st.profile.week = Clock.isoWeek(now)
            st.profile.streak = streak
            players.append(PlayerStats(login: login, name: name, state: st, now: now, app: "demo"))
        }
        return players
    }

    // MARK: Run

    static func run() {
        guard let dir = outputDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        model.now = demoNow
        model.sync.model = model
        model.sync.board = demoBoard(me: model.state)
        model.sync.boardUpdated = demoNow
        model.sync.status = .ok("Pushed 11:23")

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            render(DashboardView(tab: .me, scrolls: false), model: model, width: 380, name: "dashboard-\(suffix)", dark: dark, panel: true)
            render(DashboardView(tab: .board, scrolls: false), model: model, width: 380, name: "leaderboard-\(suffix)", dark: dark, panel: true)
            render(BreakView(session: routineSession(model)), model: model, size: CGSize(width: 960, height: 640),
                   name: "break-\(suffix)", dark: dark)
            let xp = model.state.profile.xp
            let summary = summarySession(model)
            render(BreakView(session: summary), model: model, size: CGSize(width: 960, height: 640),
                   name: "summary-\(suffix)", dark: dark, settle: 1.6)
            model.state.profile.xp = xp
            render(SettingsView(tab: 1), model: model, size: CGSize(width: 640, height: 600), name: "settings-autopause-\(suffix)", dark: dark)
            render(SettingsView(tab: 3), model: model, size: CGSize(width: 640, height: 600), name: "settings-sync-\(suffix)", dark: dark)
        }
        print("Wrote screenshots to \(dir.path)")
        exit(0)
    }

    private static func routineSession(_ model: AppModel) -> BreakSession {
        let moves = buildRoutine(model.catalog, areas: ["Neck tension", "Rounded shoulders", "Upper back"], lastKey: nil, n: 0)
        let session = BreakSession(model: model, moves: moves, manual: false, warning: false, autoStart: false)
        session.reps = [4, 0, 0]
        session.scores = [[88, 94, 90, 92], [], []]
        session.lastScore = 92
        session.cue = "Great form"
        session.cueGood = true
        session.coach.status = .live
        session.coach.preview = cameraStandIn()
        session.coach.landmarks = demoLandmarks
        return session
    }

    private static func summarySession(_ model: AppModel) -> BreakSession {
        let moves = buildRoutine(model.catalog, areas: ["Neck tension", "Rounded shoulders", "Upper back"], lastKey: nil, n: 0)
        let session = BreakSession(model: model, moves: moves, manual: false, warning: false, autoStart: false)
        session.reps = moves.map(\.target)
        session.result = BreakResult(scored: true, countedReps: 18, targetReps: 18, scores: Array(repeating: 91, count: 18),
                                     moves: moves.map { .init(key: $0.key, area: $0.area, completed: true) })
        var breakdown = Breakdown()
        breakdown.breakXp = 9
        breakdown.challenges = [CompletedChallenge(id: "variety", name: "Variety pack", bonus: 25)]
        breakdown.total = 34
        model.state.profile.xp = 914
        session.award = Award(profile: model.state.profile, breakdown: breakdown,
                              levelUp: LevelUp(from: 4, to: 5, name: "Posture Pro"), newBadges: ["daily:variety"])
        session.phase = .summary
        return session
    }

    // MARK: Rendering

    private static func render(_ view: some View, model: AppModel, size: CGSize? = nil, width: CGFloat = 0,
                               name: String, dark: Bool, panel: Bool = false, settle: TimeInterval = 0.5) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let content = view
            .environment(model)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: panel ? 12 : 10))
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.appearance = appearance
        var frame = size ?? .zero
        if size == nil {
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
            frame = CGSize(width: width, height: hosting.fittingSize.height)
        }
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -30000, y: -30000), size: frame),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let url = outputDir!.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("  \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    /// A blurred stand-in for the camera: someone at a desk, as the privacy blur shows them.
    private static func cameraStandIn() -> CGImage? {
        let w = 640, h = 480
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1) // y grows downwards, like the landmarks
        let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        let wall = CGGradient(colorsSpace: nil, colors: [rgb(0.86, 0.82, 0.76), rgb(0.62, 0.58, 0.54)] as CFArray, locations: nil)!
        ctx.drawLinearGradient(wall, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(rgb(0.97, 0.96, 0.92)); ctx.fill(CGRect(x: 430, y: 40, width: 170, height: 210)) // window
        ctx.setFillColor(rgb(0.36, 0.42, 0.36)); ctx.fillEllipse(in: CGRect(x: 40, y: 150, width: 120, height: 170)) // plant
        ctx.setFillColor(rgb(0.20, 0.30, 0.46)) // shirt
        let shirt = CGMutablePath()
        shirt.move(to: CGPoint(x: 195, y: 480)); shirt.addLine(to: CGPoint(x: 205, y: 262))
        shirt.addQuadCurve(to: CGPoint(x: 320, y: 228), control: CGPoint(x: 230, y: 228))
        shirt.addQuadCurve(to: CGPoint(x: 435, y: 262), control: CGPoint(x: 410, y: 228))
        shirt.addLine(to: CGPoint(x: 445, y: 480)); shirt.closeSubpath()
        ctx.addPath(shirt); ctx.fillPath()
        ctx.setStrokeColor(rgb(0.20, 0.30, 0.46)); ctx.setLineWidth(46); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 215, y: 250)); ctx.addLine(to: CGPoint(x: 182, y: 338)); ctx.addLine(to: CGPoint(x: 215, y: 410))
        ctx.move(to: CGPoint(x: 425, y: 250)); ctx.addLine(to: CGPoint(x: 458, y: 338)); ctx.addLine(to: CGPoint(x: 425, y: 410))
        ctx.strokePath()
        ctx.setFillColor(rgb(0.80, 0.62, 0.50)); ctx.fill(CGRect(x: 300, y: 190, width: 40, height: 45)) // neck
        ctx.setFillColor(rgb(0.84, 0.66, 0.54)); ctx.fillEllipse(in: CGRect(x: 268, y: 92, width: 104, height: 120)) // head
        ctx.setFillColor(rgb(0.25, 0.18, 0.14)); ctx.fillEllipse(in: CGRect(x: 266, y: 84, width: 108, height: 56)) // hair
        guard let sharp = ctx.makeImage() else { return nil }
        let image = CIImage(cgImage: sharp)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: image.extent)
        return CIContext().createCGImage(blurred, from: image.extent)
    }

    /// MediaPipe-style landmarks (x, y, visibility) for a seated neck tilt, unmirrored.
    private static let demoLandmarks: [[Double]] = {
        var lm = Array(repeating: [0.5, 0.5, 0.0], count: 33)
        func set(_ i: Int, _ x: Double, _ y: Double, _ v: Double = 0.95) { lm[i] = [x, y, v] }
        set(0, 0.505, 0.33)                                              // nose
        set(1, 0.53, 0.295); set(2, 0.545, 0.29); set(3, 0.56, 0.29)     // left eye
        set(4, 0.48, 0.305); set(5, 0.465, 0.305); set(6, 0.45, 0.31)    // right eye
        set(7, 0.585, 0.29); set(8, 0.425, 0.335)                        // ears: head tilted
        set(9, 0.525, 0.37); set(10, 0.49, 0.375)                        // mouth
        set(11, 0.664, 0.52); set(12, 0.336, 0.52)                       // shoulders
        set(13, 0.716, 0.705); set(14, 0.284, 0.705)                     // elbows
        set(15, 0.664, 0.855); set(16, 0.336, 0.855)                     // wrists
        set(17, 0.655, 0.89, 0.7); set(18, 0.345, 0.89, 0.7)
        set(19, 0.645, 0.895, 0.7); set(20, 0.355, 0.895, 0.7)
        set(23, 0.61, 0.99, 0.6); set(24, 0.39, 0.99, 0.6)               // hips at the frame edge
        return lm
    }()
}
