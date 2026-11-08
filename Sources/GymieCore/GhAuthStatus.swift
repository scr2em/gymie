import Foundation

/// An account the GitHub CLI is logged in to.
public struct GhAccount: Hashable, Identifiable, Sendable {
    public var login: String
    public var active: Bool
    public var ok: Bool
    public var id: String { login }
    public init(login: String, active: Bool, ok: Bool) { self.login = login; self.active = active; self.ok = ok }
}

/// Parses `gh auth status` output: "✓ Logged in to github.com account octocat (keyring)"
/// (or "X Failed to log in to github.com account octocat") followed by "- Active account: true".
public func parseGhAuthStatus(_ text: String) -> [GhAccount] {
    var accounts: [GhAccount] = []
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.contains(" to github.com"), let range = line.range(of: " account ") {
            let login = line[range.upperBound...].split(separator: " ").first.map(String.init) ?? ""
            guard !login.isEmpty else { continue }
            accounts.append(GhAccount(login: login, active: false, ok: line.hasPrefix("✓")))
        } else if line.hasPrefix("- Active account: true"), !accounts.isEmpty {
            accounts[accounts.count - 1].active = true
        }
    }
    return accounts
}
