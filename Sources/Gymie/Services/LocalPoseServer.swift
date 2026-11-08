import Foundation
import GymieCore
import Observation

/// Runs the bundled pose engine (PoseServer/: FastAPI + MediaPipe) on 127.0.0.1.
/// Started on demand when a break or practice needs it, stopped when Gymie quits.
/// The Python environment lives in ~/Library/Application Support/Gymie/pose-venv and is
/// created once by setup-pose-server.sh (from Settings or `make pose-server`).
@MainActor @Observable
final class LocalPoseServer {
    enum State: Equatable {
        case unknown, notInstalled, stopped, starting, installing
        case running(managed: Bool)
        case failed(String)
    }

    var state: State = .unknown
    var installLog = ""

    private var process: Process?
    private var installer: Process?
    private let supportDir: URL

    init(supportDir: URL) {
        self.supportDir = supportDir
        state = isInstalled ? .stopped : .notInstalled
    }

    var python: URL { supportDir.appendingPathComponent("pose-venv/bin/python") }
    var logURL: URL { supportDir.appendingPathComponent("pose-server.log") }
    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: python.path) }

    /// The PoseServer folder: inside Gymie.app, or the source tree when run with `swift run`.
    var serverDir: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("PoseServer")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../PoseServer").standardizedFileURL
        return [bundled, source].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("app.py").path)
        }
    }

    var setupScript: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("setup-pose-server.sh")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../scripts/setup-pose-server.sh").standardizedFileURL
        return [bundled, source].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Running

    /// Makes sure a pose server answers at `url`. Returns an error message, or nil when ready.
    func ensureRunning(url: String, manage: Bool) async -> String? {
        guard isLocalPoseURL(url), let health = Catalog.healthURL(forPoseServer: url) else {
            return "Only a pose server on this Mac (ws://127.0.0.1:…) can be used."
        }
        if await healthy(health) {
            state = .running(managed: process?.isRunning == true)
            return nil
        }
        guard manage else {
            return "No pose server is answering at \(url). Start it, or let Gymie run it (Settings → Break)."
        }
        guard isInstalled else {
            state = .notInstalled
            return "The pose engine isn't installed yet. Open Settings → Break and click Install pose engine (one time, about 2 minutes)."
        }
        guard let dir = serverDir else { return "The pose engine files are missing from Gymie.app." }
        if process?.isRunning != true {
            do { try launch(dir: dir, port: URL(string: url)?.port ?? 8765) } catch {
                state = .failed(error.localizedDescription)
                return "Couldn't start the pose engine: \(error.localizedDescription)"
            }
        }
        state = .starting
        // First start imports MediaPipe and loads the model; give it up to 40 s.
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(500))
            if await healthy(health) {
                state = .running(managed: true)
                return nil
            }
            if process?.isRunning != true { break }
        }
        let tail = lastLogLines()
        state = .failed(tail)
        return "The pose engine didn't start. \(tail)"
    }

    private func launch(dir: URL, port: Int) throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = python
        p.arguments = [dir.appendingPathComponent("app.py").path]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["FORMCOACH_PORT"] = String(port)
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1" // never write __pycache__ into the signed app bundle
        env.removeValue(forKey: "FORMCOACH_ALLOWED_ORIGINS")
        p.environment = env
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.process = nil
                if case .running = self.state { self.state = .stopped }
            }
        }
        try p.run()
        process = p
    }

    func stop() {
        process?.terminate()
        process = nil
        if case .running = state { state = .stopped }
    }

    private func healthy(_ url: URL) async -> Bool {
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func lastLogLines() -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(3).joined(separator: " · ")
    }

    // MARK: Install

    /// Creates the Python environment with MediaPipe (needs Python 3.10–3.12, e.g. Homebrew's python@3.12).
    func install() {
        guard installer == nil, let script = setupScript, let dir = serverDir else {
            installLog = "Setup files are missing from Gymie.app."
            return
        }
        state = .installing
        installLog = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, dir.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.installLog = String((self.installLog + text).suffix(4000))
            }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.installer = nil
                if proc.terminationStatus == 0 && self.isInstalled {
                    self.state = .stopped
                } else {
                    self.state = .failed("Setup failed (exit \(proc.terminationStatus)). See the log above.")
                }
            }
        }
        do {
            try p.run()
            installer = p
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
