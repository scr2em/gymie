import Foundation
import GymieCore

/// The local GitHub CLI (`gh`). Gymie borrows the token of an account you're already
/// logged in to with `gh auth login`, so no personal access token is needed.
enum GitHubCLI {
    typealias Account = GhAccount

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// GUI apps don't inherit the shell PATH, so look in the usual install places.
    static var path: String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", "\(NSHomeDirectory())/.local/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { path != nil }

    /// Accounts from `gh auth status` for github.com.
    static func accounts() async -> [Account] {
        guard let out = try? await run(["auth", "status", "--hostname", "github.com"], allowFailure: true) else { return [] }
        return parseGhAuthStatus(out)
    }

    /// `gh auth token --user <login>`: the OAuth token gh stored for that account.
    static func token(for login: String) async throws -> String {
        let out = try await run(["auth", "token", "--hostname", "github.com", "--user", login])
        let token = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(" ") else { throw Failure(message: "gh returned no token for \(login).") }
        return token
    }

    private static func run(_ args: [String], allowFailure: Bool = false) async throws -> String {
        guard let path else { throw Failure(message: "GitHub CLI (gh) isn't installed.") }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["GH_PROMPT_DISABLED"] = "1"
                env["NO_COLOR"] = "1"
                env.removeValue(forKey: "GH_TOKEN")
                env.removeValue(forKey: "GITHUB_TOKEN")
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                if p.terminationStatus == 0 || allowFailure {
                    cont.resume(returning: text)
                } else {
                    cont.resume(throwing: Failure(message: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }
}
