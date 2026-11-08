import Foundation
import GymieCore

/// JSON files in ~/Library/Application Support/Gymie.
struct Persistence {
    let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Gymie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var stateURL: URL { dir.appendingPathComponent("state.json") }
    private var catalogURL: URL { dir.appendingPathComponent("catalog.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> AppState {
        guard let data = try? Data(contentsOf: stateURL) else { return AppState() }
        do {
            return try Persistence.decoder.decode(AppState.self, from: data)
        } catch {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            let backup = dir.appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: stateURL, to: backup)
            NSLog("Gymie: could not read state.json (\(error)); saved a copy to \(backup.path)")
            return AppState()
        }
    }

    func save(_ state: AppState) {
        guard let data = try? Persistence.encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func loadCatalog() -> [Exercise]? {
        guard let data = try? Data(contentsOf: catalogURL),
              let list = try? Persistence.decoder.decode([Exercise].self, from: data), !list.isEmpty else { return nil }
        return list
    }

    func saveCatalog(_ exercises: [Exercise]) {
        guard let data = try? Persistence.encoder.encode(exercises) else { return }
        try? data.write(to: catalogURL, options: .atomic)
    }
}
