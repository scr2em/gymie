import Foundation
import GymieCore
import Observation

/// Minimal GitHub REST client for the stats repo (Contents API only).
struct GitHubClient {
    let token: String
    let owner: String
    let repo: String

    struct APIError: LocalizedError {
        var status: Int
        var message: String
        var errorDescription: String? {
            switch status {
            case 401: "GitHub rejected the token (401). Check it hasn't expired."
            case 403: "The token can't write to this repo (403). Give it Contents: Read and write."
            case 404: "Repo not found (404). Check the name and that the token can access it."
            default: "GitHub error \(status): \(message)"
            }
        }
    }

    struct User: Decodable { var login: String; var name: String? }
    struct Repo: Decodable {
        struct Permissions: Decodable { var push: Bool? }
        var full_name: String
        var `private`: Bool
        var permissions: Permissions?
    }
    struct Item: Decodable { var name: String; var path: String; var sha: String; var type: String }
    private struct FileBody: Decodable { var sha: String; var content: String? }
    private struct PutResult: Decodable { struct Content: Decodable { var sha: String }; var content: Content }

    func user() async throws -> User {
        try JSONDecoder().decode(User.self, from: try await send("GET", "/user"))
    }

    func repoInfo() async throws -> Repo {
        try JSONDecoder().decode(Repo.self, from: try await send("GET", "/repos/\(owner)/\(repo)"))
    }

    /// Creates a private repo under the token's user, or under an organization when `owner` isn't the user.
    func createRepo(asUser login: String) async throws -> Repo {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": repo, "private": true, "auto_init": true,
            "description": "Gymie stats: one JSON file per player in players/, pushed by the Gymie menu bar app.",
        ])
        let path = owner.lowercased() == login.lowercased() ? "/user/repos" : "/orgs/\(owner)/repos"
        return try JSONDecoder().decode(Repo.self, from: try await send("POST", path, body: body))
    }

    /// Contents of a file and its blob sha, or nil if it doesn't exist.
    func file(_ path: String) async throws -> (data: Data, sha: String)? {
        do {
            let body = try JSONDecoder().decode(FileBody.self, from: try await send("GET", contents(path)))
            let base64 = (body.content ?? "").replacingOccurrences(of: "\n", with: "")
            return (Data(base64Encoded: base64) ?? Data(), body.sha)
        } catch let e as APIError where e.status == 404 {
            return nil
        }
    }

    /// Lists a directory; an empty list if it doesn't exist yet.
    func list(_ path: String) async throws -> [Item] {
        do {
            return try JSONDecoder().decode([Item].self, from: try await send("GET", contents(path)))
        } catch let e as APIError where e.status == 404 {
            return []
        }
    }

    /// Creates or updates a file; returns the new blob sha.
    func put(_ path: String, data: Data, sha: String?, message: String) async throws -> String {
        var body: [String: Any] = ["message": message, "content": data.base64EncodedString()]
        if let sha { body["sha"] = sha }
        let out = try await send("PUT", contents(path), body: try JSONSerialization.data(withJSONObject: body))
        return try JSONDecoder().decode(PutResult.self, from: out).content.sha
    }

    private func contents(_ path: String) -> String {
        let escaped = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
        return "/repos/\(owner)/\(repo)/contents/" + escaped.joined(separator: "/")
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!, timeoutInterval: 30)
        req.httpMethod = method
        req.httpBody = body
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Gymie-macOS", forHTTPHeaderField: "User-Agent")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError(status: status, message: message ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return data
    }
}

/// Uses a private GitHub repo as the stats database:
/// - pushes `players/<login>.json` on a schedule (and shortly after a break that earned XP),
///   only when something changed, so the repo history doubles as a stats log;
/// - builds the leaderboard by reading every file in `players/`.
/// Auth comes from the GitHub CLI account you pick (`gh auth token --user`), or a token in the Keychain.
@MainActor @Observable
final class StatsSync {
    weak var model: AppModel?

    enum Status: Equatable { case idle, working(String), ok(String), failed(String) }
    var status: Status = .idle
    var board: [PlayerStats] = []
    var boardUpdated: Date?
    var boardError: String?
    /// A copy of your stats found in the repo with more XP than this Mac has (e.g. a new Mac).
    var restorable: PlayerStats?
    /// Set when the chosen repo doesn't exist yet, so the UI can offer to create it.
    var missingRepo: String?
    /// Accounts the GitHub CLI is logged in to.
    var ghAccounts: [GitHubCLI.Account] = []

    static let appVersion = "gymie-macos/0.1.0"
    private var fileSha: String?
    private var boardCache: [String: (sha: String, stats: PlayerStats)] = [:]
    private var pushTask: Task<Void, Never>?
    private var pushing = false
    private var cachedToken: String?
    private var hasKeychainToken = Keychain.read() != nil

    private var prefs: Preferences? { model?.state.settings }

    var usesGitHubCLI: Bool { prefs?.githubAuth != "token" }

    var isConnected: Bool {
        guard let model, let prefs, model.state.sync.login != nil, parseRepo(prefs.githubRepo) != nil else { return false }
        return usesGitHubCLI ? !prefs.githubAccount.isEmpty : hasKeychainToken
    }

    func loadAccounts() async {
        ghAccounts = await GitHubCLI.accounts()
    }

    private func token() async throws -> String {
        if let cachedToken { return cachedToken }
        guard let prefs else { throw GitHubCLI.Failure(message: "Not ready") }
        let token: String
        if usesGitHubCLI {
            guard !prefs.githubAccount.isEmpty else { throw GitHubCLI.Failure(message: "Pick a GitHub CLI account.") }
            token = try await GitHubCLI.token(for: prefs.githubAccount)
        } else {
            guard let stored = Keychain.read() else { throw GitHubCLI.Failure(message: "No token saved.") }
            token = stored
        }
        cachedToken = token
        return token
    }

    private func client() async throws -> GitHubClient {
        guard let prefs, let repo = parseRepo(prefs.githubRepo) else { throw GitHubCLI.Failure(message: "No repo set.") }
        return GitHubClient(token: try await token(), owner: repo.owner, repo: repo.name)
    }

    private var path: String? { model?.state.sync.login.map { "players/\($0).json" } }

    // MARK: Connect

    /// Connects with a GitHub CLI account (`account`) or a personal access token (`token`).
    func connect(repo repoText: String, account: String?, token tokenText: String?) async {
        guard let repo = parseRepo(repoText) else { status = .failed("Use the form owner/repo."); return }
        missingRepo = nil
        status = .working("Checking access to \(repo.owner)/\(repo.name)…")
        do {
            let token: String
            if let account {
                token = try await GitHubCLI.token(for: account)
            } else {
                token = (tokenText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { status = .failed("Paste a GitHub token."); return }
            }
            let client = GitHubClient(token: token, owner: repo.owner, repo: repo.name)
            let user = try await client.user()
            let info: GitHubClient.Repo
            do {
                info = try await client.repoInfo()
            } catch let e as GitHubClient.APIError where e.status == 404 {
                missingRepo = "\(repo.owner)/\(repo.name)"
                status = .failed("\(repo.owner)/\(repo.name) doesn't exist yet (or \(user.login) can't see it).")
                pendingAuth = (account, account == nil ? token : nil)
                return
            }
            try await finishConnect(client: client, user: user, info: info, account: account, token: account == nil ? token : nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private var pendingAuth: (account: String?, token: String?)?

    /// Creates the missing repo as private, then connects to it.
    func createMissingRepo() async {
        guard let name = missingRepo, let repo = parseRepo(name), let auth = pendingAuth else { return }
        status = .working("Creating private repo \(name)…")
        do {
            let token: String
            if let account = auth.account { token = try await GitHubCLI.token(for: account) } else { token = auth.token ?? "" }
            let client = GitHubClient(token: token, owner: repo.owner, repo: repo.name)
            let user = try await client.user()
            let info = try await client.createRepo(asUser: user.login)
            missingRepo = nil
            try await finishConnect(client: client, user: user, info: info, account: auth.account, token: auth.token)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func finishConnect(client: GitHubClient, user: GitHubClient.User, info: GitHubClient.Repo,
                               account: String?, token: String?) async throws {
        guard let model else { return }
        guard info.permissions?.push != false else {
            status = .failed("\(user.login) can read \(info.full_name) but can't write to it.")
            return
        }
        if let token {
            Keychain.save(token)
            hasKeychainToken = true
        }
        cachedToken = account == nil ? token : try await GitHubCLI.token(for: account!)
        model.updateSettings {
            $0.githubRepo = info.full_name
            $0.githubAuth = account == nil ? "token" : "gh"
            $0.githubAccount = account ?? ""
            $0.githubSyncEnabled = true
            if $0.displayName.isEmpty { $0.displayName = user.name ?? user.login }
        }
        model.state.sync.login = user.login
        model.state.sync.githubName = user.name
        model.state.sync.lastFingerprint = nil
        fileSha = nil
        boardCache = [:]
        pendingAuth = nil
        let note = info.private ? "" : " Note: this repo is public, so anyone can see the stats."
        status = .ok("Connected as \(user.login) to \(info.full_name).\(note)")
        if let remote = try await client.file("players/\(user.login).json"),
           let stats = try? PlayerStats.decoder.decode(PlayerStats.self, from: remote.data) {
            fileSha = remote.sha
            if stats.xp > model.state.profile.xp { restorable = stats }
        }
        if restorable == nil { await push(force: true) }
        await refreshBoard(force: true)
    }

    func disconnect() {
        Keychain.delete()
        hasKeychainToken = false
        cachedToken = nil
        model?.updateSettings {
            $0.githubSyncEnabled = false
            $0.githubAccount = ""
        }
        model?.state.sync = SyncInfo()
        fileSha = nil
        board = []
        boardCache = [:]
        restorable = nil
        missingRepo = nil
        status = .idle
    }

    /// Adopts the repo's copy of your profile and merges its activity history.
    func restore() {
        guard let model, let remote = restorable else { return }
        model.state.profile = remote.profile
        var activity = model.state.activity
        for (day, entry) in remote.activity {
            let local = activity[day] ?? DayActivity(breaks: 0, xp: 0)
            activity[day] = DayActivity(breaks: max(local.breaks, entry.breaks), xp: max(local.xp, entry.xp))
        }
        model.state.activity = activity
        restorable = nil
        Task { await push(force: true) }
    }

    func keepLocal() {
        restorable = nil
        Task { await push(force: true) }
    }

    // MARK: Push

    func pushIfDue(force: Bool) {
        guard let model, model.state.settings.githubSyncEnabled, isConnected, restorable == nil else { return }
        let every = TimeInterval(max(5, model.state.settings.githubSyncMinutes)) * 60
        let last = model.state.sync.lastAttemptAt ?? .distantPast
        guard force || Date().timeIntervalSince(last) >= every else { return }
        Task { await push(force: force) }
    }

    /// Pushes ~10 s after a break, so the summary screen isn't waiting on the network.
    func pushSoon() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            pushIfDue(force: true)
        }
    }

    func push(force: Bool) async {
        guard let model, isConnected, let path, let login = model.state.sync.login, !pushing else { return }
        pushing = true
        defer { pushing = false }
        let now = Date()
        model.state.sync.lastAttemptAt = now
        let name = model.state.settings.displayName.isEmpty ? (model.state.sync.githubName ?? login) : model.state.settings.displayName
        let stats = PlayerStats(login: login, name: name, state: model.state, now: now, app: Self.appVersion)
        let fingerprint = stats.fingerprint()
        if !force, fingerprint == model.state.sync.lastFingerprint {
            status = .ok("Up to date · checked \(now.formatted(date: .omitted, time: .shortened))")
            return
        }
        status = .working("Pushing stats…")
        do {
            let client = try await client()
            let data = try PlayerStats.encoder.encode(stats)
            let message = "\(login): \(stats.xp) XP, level \(stats.level), streak \(stats.streak)"
            if fileSha == nil { fileSha = try await client.file(path)?.sha }
            do {
                fileSha = try await client.put(path, data: data, sha: fileSha, message: message)
            } catch let e as GitHubClient.APIError where e.status == 409 || e.status == 422 {
                // Another Mac updated the file: take its sha and write ours on top.
                fileSha = try await client.file(path)?.sha
                fileSha = try await client.put(path, data: data, sha: fileSha, message: message)
            }
            model.state.sync.lastFingerprint = fingerprint
            model.state.sync.lastPushAt = now
            status = .ok("Pushed \(now.formatted(date: .omitted, time: .shortened))")
        } catch {
            if (error as? GitHubClient.APIError)?.status == 401 { cachedToken = nil } // gh may have refreshed it
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Leaderboard

    func refreshBoard(force: Bool = false) async {
        guard isConnected else { return }
        if !force, let boardUpdated, Date().timeIntervalSince(boardUpdated) < 120 { return }
        do {
            let client = try await client()
            let items = try await client.list("players").filter { $0.type == "file" && $0.name.hasSuffix(".json") }
            var next: [String: (sha: String, stats: PlayerStats)] = [:]
            for item in items {
                if let cached = boardCache[item.path], cached.sha == item.sha {
                    next[item.path] = cached
                } else if let file = try await client.file(item.path),
                          let stats = try? PlayerStats.decoder.decode(PlayerStats.self, from: file.data) {
                    next[item.path] = (file.sha, stats)
                }
            }
            boardCache = next
            board = next.values.map(\.stats)
            boardUpdated = Date()
            boardError = nil
        } catch {
            if (error as? GitHubClient.APIError)?.status == 401 { cachedToken = nil }
            boardError = error.localizedDescription
        }
    }
}
