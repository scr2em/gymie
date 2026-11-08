import AVFoundation
import GymieCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if !model.state.settings.setupDone { welcome }
            TabView {
                ScheduleTab().tabItem { Label("Schedule", systemImage: "clock") }
                AutoPauseTab().tabItem { Label("Auto-pause", systemImage: "hand.raised") }
                BreakTab().tabItem { Label("Break", systemImage: "camera") }
                SyncTab().tabItem { Label("Stats & leaderboard", systemImage: "chart.bar") }
                SystemTab().tabItem { Label("System", systemImage: "gearshape") }
            }
            .padding(12)
        }
        .frame(minWidth: 600, minHeight: 560)
    }

    private var welcome: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.cooldown").font(.system(size: 30)).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Gymie").font(.title3.weight(.semibold))
                Text("Pick at least one area that bothers you, check your hours, then start.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Get started") { model.finishSetup() }
                .buttonStyle(.borderedProminent).tint(.mint).controlSize(.large)
                .disabled(model.state.settings.areas.isEmpty)
        }
        .padding(16)
        .background(.mint.opacity(0.12))
    }
}

/// A binding that writes through AppModel.updateSettings (which reschedules when needed).
@MainActor
private func setting<T>(_ model: AppModel, _ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
    Binding(get: { model.state.settings[keyPath: key] }, set: { v in model.updateSettings { $0[keyPath: key] = v } })
}

private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// MARK: - Schedule

private struct ScheduleTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Remind me every") {
                Picker("Interval", selection: setting(model, \.intervalMin)) {
                    ForEach(Defaults.intervalPresets, id: \.self) { Text("\($0) min").tag($0) }
                    if !Defaults.intervalPresets.contains(model.state.settings.intervalMin) {
                        Text("\(model.state.settings.intervalMin) min").tag(model.state.settings.intervalMin)
                    }
                }
                Stepper("Custom: \(model.state.settings.intervalMin) min", value: setting(model, \.intervalMin), in: 1...240)
            }
            Section("Where do you feel it?") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(AREAS, id: \.self) { area in
                        Toggle(isOn: Binding(
                            get: { model.state.settings.areas.contains(area) },
                            set: { on in model.updateSettings { s in
                                s.areas = currentAreas(on ? s.areas + [area] : s.areas.filter { $0 != area })
                            } }
                        )) {
                            Label(area, systemImage: AREA_SYMBOLS[area] ?? "circle")
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                if model.state.settings.areas.isEmpty {
                    Text("Pick at least one area.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Active hours") {
                HStack {
                    TimeField(title: "From", value: setting(model, \.activeStart))
                    TimeField(title: "To", value: setting(model, \.activeEnd))
                }
                HStack(spacing: 6) {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                        let on = model.state.settings.workdays.contains(day)
                        Button(weekdayNames[day]) {
                            model.updateSettings { s in
                                s.workdays = on ? s.workdays.filter { $0 != day } : (s.workdays + [day]).sorted()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .mint : .gray)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// "HH:mm" string edited with a DatePicker.
private struct TimeField: View {
    let title: String
    @Binding var value: String

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Clock.at(minutes: minutesOf(value), on: Date()) },
            set: { d in
                let m = Clock.minutesIntoDay(d)
                value = String(format: "%02d:%02d", m / 60, m % 60)
            }
        ), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Auto-pause

private struct AutoPauseTab: View {
    @Environment(AppModel.self) private var model
    @State private var calendarMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Hold reminders during meetings and presentations", isOn: setting(model, \.autoPause))
            } footer: {
                Text("A held reminder is rechecked every 5 minutes and fires as soon as you're free. It never counts as a skip.")
            }
            Section("Signals") {
                Toggle("Camera or microphone in use by any app (Zoom, Teams, Meet, FaceTime…)", isOn: setting(model, \.pauseWhenCameraOrMicInUse))
                Toggle("An app is fullscreen (presenting, watching)", isOn: setting(model, \.pauseWhenFullscreen))
                Toggle("Busy events in Calendar", isOn: Binding(
                    get: { model.state.settings.pauseForCalendarEvents },
                    set: { on in
                        if on && !model.calendar.authorized {
                            Task {
                                let ok = await model.calendar.requestAccess()
                                calendarMessage = ok ? nil : "Gymie can't read your calendars. Allow it in System Settings → Privacy & Security → Calendars."
                                model.updateSettings { $0.pauseForCalendarEvents = ok }
                            }
                        } else {
                            model.updateSettings { $0.pauseForCalendarEvents = on }
                        }
                    }
                ))
                if let calendarMessage { Text(calendarMessage).font(.caption).foregroundStyle(.orange) }
                Text("Uses the macOS Calendar app, including Google and Exchange accounts added in System Settings → Internet Accounts. Events marked free, all-day events and ones you declined are ignored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!model.state.settings.autoPause)
            Section("Also") {
                Text("If you've been away from the keyboard for 5 minutes or the screen is locked when a break is due, Gymie lets it pass without counting a skip.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Break

private struct BreakTab: View {
    @Environment(AppModel.self) private var model
    @State private var cameraNote: String?
    @State private var engineNote: String?
    @State private var urlDraft = ""

    var body: some View {
        let engine = model.poseServer
        Form {
            Section("Camera") {
                Toggle("Blur my camera preview", isOn: setting(model, \.blurCamera))
                Text("Your camera is only used to count reps and is never recorded. Frames go to the pose engine running on this Mac and never leave it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check camera permission") {
                    Task {
                        let ok = await CameraCapture.authorize()
                        cameraNote = ok ? "Camera access is allowed." : "Camera access is off. Allow Gymie in System Settings → Privacy & Security → Camera."
                    }
                }
                if let cameraNote { Text(cameraNote).font(.caption) }
            }
            Section("Coaching") {
                Toggle("Spoken cues (exercise names, rep counts)", isOn: setting(model, \.voice))
                Toggle("Sounds", isOn: setting(model, \.sounds))
            }
            Section {
                LabeledContent("Status") { engineStatus(engine.state) }
                if !engine.isInstalled || engine.state == .installing {
                    Button(engine.state == .installing ? "Installing…" : "Install pose engine") { engine.install() }
                        .disabled(engine.state == .installing)
                    Text("One-time setup: creates a Python environment with MediaPipe in ~/Library/Application Support/Gymie (about 300 MB). Needs Python 3.10–3.12, for example brew install python@3.12.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !engine.installLog.isEmpty {
                    ScrollView {
                        Text(engine.installLog).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 90)
                }
                Toggle("Gymie starts and stops the pose engine", isOn: setting(model, \.managePoseServer))
                HStack {
                    TextField("Address", text: $urlDraft)
                        .onSubmit(applyURL)
                    Button("Apply", action: applyURL).disabled(urlDraft == model.state.settings.poseServerURL)
                }
                HStack {
                    Button("Start / test now") {
                        Task {
                            engineNote = "Checking…"
                            engineNote = await model.preparePoseEngine() ?? "The pose engine is running."
                        }
                    }
                    if case .running(managed: true) = engine.state {
                        Button("Stop") { engine.stop() }
                    }
                    Spacer()
                    Button("Show log") { NSWorkspace.shared.open(engine.logURL) }
                        .disabled(!FileManager.default.fileExists(atPath: engine.logURL.path))
                }
                if let engineNote { Text(engineNote).font(.caption) }
            } header: {
                Text("Pose engine (local)")
            } footer: {
                Text("Rep counting and form scores come from PoseServer/ (MediaPipe), running on 127.0.0.1. Only addresses on this Mac are accepted. GitHub sync is Gymie's only network connection.")
            }
        }
        .formStyle(.grouped)
        .onAppear { urlDraft = model.state.settings.poseServerURL }
    }

    private func applyURL() {
        guard isLocalPoseURL(urlDraft) else {
            engineNote = "Use a local address like ws://127.0.0.1:8765/ws."
            urlDraft = model.state.settings.poseServerURL
            return
        }
        engineNote = nil
        model.updateSettings { $0.poseServerURL = urlDraft }
    }

    @ViewBuilder private func engineStatus(_ state: LocalPoseServer.State) -> some View {
        switch state {
        case .unknown, .stopped: Label("Installed, starts with your next break", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .notInstalled: Label("Not installed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .installing: Label("Installing…", systemImage: "arrow.down.circle")
        case .starting: Label("Starting…", systemImage: "hourglass")
        case .running(let managed): Label(managed ? "Running (started by Gymie)" : "Running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let why): Label(why, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
        }
    }
}

// MARK: - GitHub stats

private struct SyncTab: View {
    @Environment(AppModel.self) private var model
    @State private var repo = ""
    @State private var account = ""
    @State private var token = ""
    @State private var useToken = false

    var body: some View {
        let sync = model.sync
        Form {
            Section {
                Text("Your private GitHub repo is Gymie's database. Each person's stats live in players/<github-login>.json and are pushed on a schedule. The leaderboard reads every file in players/, so everyone with access to the repo (you and any collaborators you add) shows up on the same board.")
                    .font(.callout)
            }
            if sync.isConnected {
                connected(sync)
            } else {
                connect(sync)
            }
            Section {
                switch sync.status {
                case .idle: EmptyView()
                case .working(let t): Label(t, systemImage: "arrow.triangle.2.circlepath")
                case .ok(let t): Label(t, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let t): Label(t, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if let missing = sync.missingRepo {
                    Button("Create private repo \(missing)") { Task { await sync.createMissingRepo() } }
                        .buttonStyle(.borderedProminent).tint(.mint)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await sync.loadAccounts()
            useToken = !GitHubCLI.isInstalled
            if account.isEmpty {
                account = model.state.settings.githubAccount.isEmpty
                    ? (sync.ghAccounts.first(where: \.active) ?? sync.ghAccounts.first)?.login ?? ""
                    : model.state.settings.githubAccount
            }
            if repo.isEmpty {
                repo = model.state.settings.githubRepo.isEmpty && !account.isEmpty ? "\(account)/gymie-data" : model.state.settings.githubRepo
            }
        }
    }

    @ViewBuilder private func connected(_ sync: StatsSync) -> some View {
        Section("Connected") {
            LabeledContent("Repo", value: model.state.settings.githubRepo)
            LabeledContent("Signed in as", value: sync.usesGitHubCLI
                           ? "\(model.state.settings.githubAccount) (GitHub CLI)" : "\(model.state.sync.login ?? "?") (token)")
            LabeledContent("Player file", value: "players/\(model.state.sync.login ?? "?").json")
            TextField("Display name", text: setting(model, \.displayName))
            Toggle("Push my stats automatically", isOn: setting(model, \.githubSyncEnabled))
            Picker("Every", selection: setting(model, \.githubSyncMinutes)) {
                ForEach([15, 30, 60, 120, 240], id: \.self) { Text("\($0) min").tag($0) }
            }
            Text("Pushes only when something changed, plus once shortly after each break that earns XP. Each push is a commit, so the repo history is your stats log.")
                .font(.caption).foregroundStyle(.secondary)
            if let last = model.state.sync.lastPushAt {
                LabeledContent("Last push", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            HStack {
                Button("Push now") { Task { await sync.push(force: true) } }
                Spacer()
                Button("Disconnect", role: .destructive) { sync.disconnect() }
            }
        }
        if let remote = sync.restorable {
            Section("Found your stats in the repo") {
                Text("The repo has \(remote.xp) XP (level \(remote.level), \(remote.totalBreaks) breaks) for \(remote.login), more than this Mac's \(model.state.profile.xp) XP.")
                HStack {
                    Button("Restore from GitHub") { sync.restore() }.buttonStyle(.borderedProminent).tint(.mint)
                    Button("Keep this Mac's stats") { sync.keepLocal() }
                }
            }
        }
    }

    @ViewBuilder private func connect(_ sync: StatsSync) -> some View {
        Section("Connect") {
            if GitHubCLI.isInstalled && !useToken {
                if sync.ghAccounts.isEmpty {
                    Text("The GitHub CLI isn't logged in. Run gh auth login in Terminal, then reopen this tab.")
                        .font(.callout).foregroundStyle(.orange)
                } else {
                    Picker("GitHub CLI account", selection: $account) {
                        ForEach(sync.ghAccounts) { a in
                            Text(a.login + (a.active ? " (active)" : "") + (a.ok ? "" : " (needs gh auth refresh)")).tag(a.login)
                        }
                    }
                    .onChange(of: account) { old, new in
                        if repo.isEmpty || repo == "\(old)/gymie-data" { repo = "\(new)/gymie-data" }
                    }
                }
                TextField("Repository (owner/name)", text: $repo, prompt: Text("\(account.isEmpty ? "you" : account)/gymie-data"))
                Text("Gymie asks gh for this account's token each time it starts and keeps it in memory only. If the repo doesn't exist yet, you can create it as private from here.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Connect") { Task { await sync.connect(repo: repo, account: account, token: nil) } }
                        .buttonStyle(.borderedProminent).tint(.mint)
                        .disabled(repo.isEmpty || account.isEmpty)
                    Spacer()
                    Button("Use a token instead") { useToken = true }.buttonStyle(.link)
                }
            } else {
                TextField("Repository (owner/name)", text: $repo, prompt: Text("your-login/gymie-data"))
                SecureField("Personal access token", text: $token)
                Text(GitHubCLI.isInstalled
                     ? "Fine-grained token with access to this repo only and Contents: Read and write. Stored in your Keychain."
                     : "Install the GitHub CLI (brew install gh, then gh auth login) to skip tokens. Otherwise use a fine-grained token with Contents: Read and write on this repo; it's stored in your Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Connect") { Task { await sync.connect(repo: repo, account: nil, token: token) } }
                        .buttonStyle(.borderedProminent).tint(.mint)
                        .disabled(repo.isEmpty || token.isEmpty)
                    Spacer()
                    if GitHubCLI.isInstalled { Button("Use GitHub CLI instead") { useToken = false }.buttonStyle(.link) }
                }
            }
        }
    }
}

// MARK: - System

private struct SystemTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Notify me 1 minute before a break", isOn: setting(model, \.headsUpNotification))
                Toggle("Open Gymie at login", isOn: setting(model, \.launchAtLogin))
                Toggle("Global shortcut \(HotKey.display) starts a break", isOn: setting(model, \.hotKeyEnabled))
            }
            Section("Data") {
                LabeledContent("Stored in", value: model.persistence.dir.path)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.persistence.dir]) }
            }
        }
        .formStyle(.grouped)
    }
}
