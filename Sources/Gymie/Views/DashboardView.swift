import GymieCore
import SwiftUI

/// The menu bar panel.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab
    /// The menu bar panel keeps a fixed height (MenuBarExtra windows don't resize cleanly when
    /// content changes), so the tab content scrolls. Snapshots render it unclipped.
    private let scrolls: Bool
    static let tabHeight: CGFloat = 380

    init(tab: Tab = .me, scrolls: Bool = true) {
        _tab = State(initialValue: tab)
        self.scrolls = scrolls
    }
    @State private var period = BoardPeriod.week

    enum Tab: String, CaseIterable { case me = "Today", board = "Leaderboard" }

    var body: some View {
        VStack(spacing: 12) {
            LevelHeader(xp: model.state.profile.xp)
            if !model.state.settings.setupDone {
                setupCard
            } else {
                nextBreakCard
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if scrolls {
                    ScrollView {
                        tabContent.padding(.bottom, 4)
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: Self.tabHeight)
                } else {
                    tabContent
                }
            }
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 380)
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .me: meTab
        case .board: boardTab
        }
    }

    // MARK: Cards

    private var setupCard: some View {
        Card {
            Text("Pick the areas that bother you and how often to move.").font(.callout)
            Button("Finish setup") { model.windows.showSettings(model: model) }
                .buttonStyle(.borderedProminent).tint(.mint)
        }
    }

    private var nextBreakCard: some View {
        let s = model.state.schedule
        let interval = model.state.settings.intervalMin
        return Card {
            if model.breakSession != nil {
                Label("Break in progress", systemImage: "figure.cooldown").font(.headline)
            } else if model.isPaused, let until = s.pausedUntil {
                HStack {
                    Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle.fill")
                        .font(.headline)
                    Spacer()
                    Button("Resume") { model.resume() }
                }
            } else if let next = s.nextAt {
                let left = next.timeIntervalSince(model.now)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Next break").foregroundStyle(.secondary)
                        Text(next.formatted(date: Clock.dayKey(next) == Clock.dayKey(model.now) ? .omitted : .abbreviated, time: .shortened))
                            .font(.headline)
                        Spacer()
                        Text(left > 0 ? "in \(countdownLong(left))" : "now").monospacedDigit().foregroundStyle(.secondary)
                    }
                    if s.shiftedBy > 0 {
                        Text("Shifted +\(s.shiftedBy) min: " + s.upcoming(intervalMin: interval).map {
                            $0.formatted(date: .omitted, time: .shortened)
                        }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    if !isActive(model.now, model.state.settings.hours) {
                        Text("Outside your active hours").font(.caption).foregroundStyle(.secondary)
                    }
                    if let reason = model.holdReason {
                        Label(reason, systemImage: "hand.raised.fill").font(.caption).foregroundStyle(.orange)
                    }
                    if let meeting = model.nextMeeting {
                        Label("Next meeting \(meeting.start.formatted(date: .omitted, time: .shortened)): \(meeting.title)",
                              systemImage: "calendar").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var meTab: some View {
        let profile = model.profileForToday
        return VStack(spacing: 10) {
            Card {
                HStack {
                    Stat(value: "\(model.todayBreaks)", label: "breaks today", symbol: "figure.cooldown")
                    Stat(value: "\(profile.streak)", label: "day streak", symbol: "flame.fill")
                    Stat(value: "\(model.state.schedule.skipsInRow)", label: "skips in a row", symbol: "forward.fill")
                }
            }
            Card(title: "Challenges") {
                if let daily = profile.daily {
                    ForEach(daily.ids, id: \.self) { id in
                        if let c = DAILY_POOL.first(where: { $0.id == id }) {
                            challengeRow(symbol: c.symbol, name: c.name, detail: c.detail, bonus: c.bonus, done: daily.done.contains(id))
                        }
                    }
                }
                if let weekly = profile.weekly {
                    challengeRow(symbol: AREA_SYMBOLS[weekly.area] ?? "star.fill", name: "\(weekly.area) week",
                                 detail: "\(weekly.count)/\(WeeklyRules.target) \(weekly.area.lowercased()) exercises",
                                 bonus: WeeklyRules.bonus, done: weekly.done)
                    ProgressView(value: Double(weekly.count), total: Double(WeeklyRules.target)).tint(.mint)
                }
            }
            Card(title: "Last 16 weeks") {
                let weeks = heatmapWeeks(model.state.activity, now: model.now, weeks: 16, workdays: model.state.settings.workdays)
                let totals = activityTotals(model.state.activity, now: model.now, weeks: 16)
                HeatmapView(cells: weeks)
                Text("\(totals.breaks) breaks · \(totals.xp) XP · \(totals.activeDays) active days")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.state.profile.badges.isEmpty {
                Card(title: "Badges") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.state.profile.badges, id: \.self) { id in
                                Image(systemName: badgeSymbol(id))
                                    .font(.title3).foregroundStyle(.mint)
                                    .frame(width: 34, height: 34)
                                    .background(.mint.opacity(0.15), in: Circle())
                                    .help(badgeLabel(id))
                            }
                        }
                    }
                }
            }
        }
    }

    private func challengeRow(symbol: String, name: String, detail: String, bonus: Int, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .foregroundStyle(done ? .mint : .secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium)).strikethrough(done)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(bonus)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var boardTab: some View {
        let sync = model.sync
        if !sync.isConnected {
            Card {
                Text("Connect a private GitHub repo in Settings → Stats & leaderboard. Your stats are pushed there on a schedule, and everyone with access to the repo shows up here.")
                    .font(.callout)
                Button("Open Settings") { model.windows.showSettings(model: model) }
            }
        } else {
            VStack(spacing: 8) {
                Picker("", selection: $period) {
                    Text("This week").tag(BoardPeriod.week)
                    Text("All time").tag(BoardPeriod.all)
                }
                .pickerStyle(.segmented).labelsHidden()
                let rows = rankBoard(sync.board, period: period, me: model.state.sync.login, now: model.now)
                Card {
                    if rows.isEmpty {
                        Text(sync.boardError ?? "No players yet.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(rows.prefix(15)) { row in
                        HStack(spacing: 8) {
                            Text("\(row.rank)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 22, alignment: .trailing)
                            LevelBadge(level: row.level, size: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.name).font(.callout.weight(row.isMe ? .bold : .regular)).lineLimit(1)
                                Text(row.levelName).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if row.streak > 0 { Label("\(row.streak)", systemImage: "flame.fill").font(.caption).foregroundStyle(.orange) }
                            Text("\(row.xp) XP").font(.callout.monospacedDigit())
                        }
                        .padding(.vertical, 2).padding(.horizontal, 4)
                        .background(row.isMe ? Color.mint.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                HStack {
                    Text(syncLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { Task { await sync.push(force: false); await sync.refreshBoard(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless).help("Push my stats and refresh")
                }
            }
            .task { await sync.refreshBoard() }
        }
    }

    private var syncLine: String {
        switch model.sync.status {
        case .working(let t): t
        case .failed(let t): "⚠︎ " + t
        case .ok(let t): t
        case .idle: model.sync.boardUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.breakNow() } label: { Label("Break now", systemImage: "figure.run") }
                .buttonStyle(.borderedProminent).tint(.mint)
                .help("Start a break now (\(HotKey.display))")
                .disabled(!model.state.settings.setupDone)
            if model.isPaused {
                Button { model.resume() } label: { Label("Resume", systemImage: "play.fill") }
            } else {
                Button { model.pause() } label: { Label("Pause 1 hr", systemImage: "pause.fill") }
                    .disabled(!model.state.settings.setupDone)
            }
            Spacer()
            Button { model.windows.showPractice(model: model) } label: { Image(systemName: "dumbbell.fill") }
                .help("Practice")
            Button { model.windows.showSettings(model: model) } label: { Image(systemName: "gearshape.fill") }
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Gymie")
        }
        .buttonStyle(.bordered)
    }

    private func countdownLong(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded(.up)))s" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
