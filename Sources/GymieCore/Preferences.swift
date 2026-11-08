import Foundation

public enum Defaults {
    /// The pose engine always runs on this Mac (PoseServer/, started by Gymie). Camera frames never leave it.
    public static let poseServerURL = "ws://127.0.0.1:8765/ws"
    public static let intervalPresets = [30, 45, 60, 90, 120]
}

/// Only loopback pose servers are allowed: the only network service Gymie talks to is GitHub.
public func isLocalPoseURL(_ text: String) -> Bool {
    guard let url = URL(string: text), ["ws", "wss"].contains(url.scheme ?? ""), let host = url.host else { return false }
    return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased())
}

public struct Preferences: Codable, Equatable, Sendable {
    public var intervalMin = 60
    public var areas: [String] = []
    public var activeStart = "09:00"
    public var activeEnd = "17:00"
    /// 0 = Sunday ... 6 = Saturday.
    public var workdays: [Int] = [1, 2, 3, 4, 5]
    public var setupDone = false

    // Auto-pause signals
    public var autoPause = true
    public var pauseWhenCameraOrMicInUse = true
    public var pauseWhenFullscreen = true
    public var pauseForCalendarEvents = false

    // Break window
    public var blurCamera = true
    public var voice = true
    public var sounds = true
    public var poseServerURL = Defaults.poseServerURL
    /// Gymie starts and stops the bundled pose engine itself.
    public var managePoseServer = true

    // Mac extras
    public var headsUpNotification = true
    public var launchAtLogin = false
    public var hotKeyEnabled = true

    // GitHub stats repo
    public var displayName = ""
    public var githubRepo = ""          // "owner/name"
    /// "gh": token from the GitHub CLI for `githubAccount`; "token": a personal access token in the Keychain.
    public var githubAuth = "gh"
    public var githubAccount = ""
    public var githubSyncEnabled = false
    public var githubSyncMinutes = 30

    public init() {}

    public var hours: ActiveHours { ActiveHours(activeStart: activeStart, activeEnd: activeEnd, workdays: workdays) }

    public init(from decoder: Decoder) throws {
        // Every field optional on disk, so adding settings never breaks a saved file.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        intervalMin = v(.intervalMin, d.intervalMin)
        areas = currentAreas(v(.areas, d.areas))
        activeStart = v(.activeStart, d.activeStart)
        activeEnd = v(.activeEnd, d.activeEnd)
        workdays = v(.workdays, d.workdays)
        setupDone = v(.setupDone, d.setupDone)
        autoPause = v(.autoPause, d.autoPause)
        pauseWhenCameraOrMicInUse = v(.pauseWhenCameraOrMicInUse, d.pauseWhenCameraOrMicInUse)
        pauseWhenFullscreen = v(.pauseWhenFullscreen, d.pauseWhenFullscreen)
        pauseForCalendarEvents = v(.pauseForCalendarEvents, d.pauseForCalendarEvents)
        blurCamera = v(.blurCamera, d.blurCamera)
        voice = v(.voice, d.voice)
        sounds = v(.sounds, d.sounds)
        let savedURL = v(.poseServerURL, d.poseServerURL)
        poseServerURL = isLocalPoseURL(savedURL) ? savedURL : d.poseServerURL
        managePoseServer = v(.managePoseServer, d.managePoseServer)
        headsUpNotification = v(.headsUpNotification, d.headsUpNotification)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        hotKeyEnabled = v(.hotKeyEnabled, d.hotKeyEnabled)
        displayName = v(.displayName, d.displayName)
        githubRepo = v(.githubRepo, d.githubRepo)
        githubAuth = v(.githubAuth, d.githubAuth)
        githubAccount = v(.githubAccount, d.githubAccount)
        githubSyncEnabled = v(.githubSyncEnabled, d.githubSyncEnabled)
        githubSyncMinutes = v(.githubSyncMinutes, d.githubSyncMinutes)
    }

    /// True when a change should move the next break (interval, hours or workdays).
    public static func scheduleChanged(_ a: Preferences, _ b: Preferences) -> Bool {
        a.intervalMin != b.intervalMin || a.activeStart != b.activeStart || a.activeEnd != b.activeEnd
            || Set(a.workdays) != Set(b.workdays)
    }
}

public struct ActiveHours: Equatable, Sendable {
    public var activeStart: String
    public var activeEnd: String
    public var workdays: [Int]

    public init(activeStart: String, activeEnd: String, workdays: [Int]) {
        self.activeStart = activeStart
        self.activeEnd = activeEnd
        self.workdays = workdays
    }
}
