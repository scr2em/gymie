import Foundation

/// Pain areas, matching the pose server's exercise categories (five exercises each).
public let AREAS = [
    "Neck tension",
    "Rounded shoulders",
    "Upper back",
    "Shoulder & rotator cuff",
    "Lower back",
    "Wrist & hand",
    "Knees",
    "Eyes",
]

/// Eyes is opt-in, so it never becomes the weekly featured area.
public let FEATURED_AREAS = AREAS.filter { $0 != "Eyes" }

public let AREA_SYMBOLS: [String: String] = [
    "Neck tension": "person.bust",
    "Rounded shoulders": "figure.arms.open",
    "Upper back": "figure.rower",
    "Shoulder & rotator cuff": "figure.strengthtraining.functional",
    "Lower back": "figure.flexibility",
    "Wrist & hand": "hand.raised",
    "Knees": "figure.step.training",
    "Eyes": "eye",
]

/// Area names from before the pain areas, so old saved settings keep working.
private let LEGACY_AREAS: [String: [String]] = [
    "Neck": ["Neck tension"],
    "Shoulders": ["Shoulder & rotator cuff"],
    "Upper back & posture": ["Upper back", "Rounded shoulders"],
    "Arms & wrists": ["Wrist & hand"],
    "Lower back & core": ["Lower back"],
    "Hips & glutes": ["Lower back", "Knees"],
    "Legs & circulation": ["Knees"],
]

/// Saved areas -> current area names, in AREAS order. Unknown names are dropped.
public func currentAreas(_ areas: [String]) -> [String] {
    let named = Set(areas.flatMap { LEGACY_AREAS[$0] ?? [$0] })
    return AREAS.filter { named.contains($0) }
}

public func featuredArea(_ date: Date) -> String {
    FEATURED_AREAS[Clock.isoWeekNumber(date) % FEATURED_AREAS.count]
}

public struct Exercise: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var category: String
    public var camera: String
    public var stance: String
    public var how_to: String
    public var demo_url: String?

    public var id: String { key }

    public init(key: String, label: String, category: String, camera: String = "front", stance: String = "seated", how_to: String = "", demo_url: String? = nil) {
        self.key = key; self.label = label; self.category = category
        self.camera = camera; self.stance = stance; self.how_to = how_to; self.demo_url = demo_url
    }
}

public enum Catalog {
    public static let bundled: [Exercise] = {
        (try? JSONDecoder().decode([Exercise].self, from: Data(BundledCatalog.json.utf8))) ?? []
    }()

    /// Parses the pose server's `/health` (or `ready`) payload.
    public static func parse(serverPayload data: Data) -> [Exercise]? {
        struct Demo: Decodable { var url: String? }
        struct Raw: Decodable {
            var key: String; var label: String; var category: String
            var camera: String?; var stance: String?; var how_to: String?; var demo: Demo?
        }
        struct Body: Decodable { var exercises: [Raw] }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), !body.exercises.isEmpty else { return nil }
        return body.exercises.map {
            Exercise(key: $0.key, label: $0.label, category: $0.category, camera: $0.camera ?? "front",
                     stance: $0.stance ?? "seated", how_to: $0.how_to ?? "", demo_url: $0.demo?.url)
        }
    }

    /// ws://host:port/ws -> http://host:port/health (wss -> https).
    public static func healthURL(forPoseServer ws: String) -> URL? {
        guard var c = URLComponents(string: ws) else { return nil }
        switch c.scheme {
        case "ws": c.scheme = "http"
        case "wss": c.scheme = "https"
        case "http", "https": break
        default: return nil
        }
        c.path = "/health"
        c.query = nil
        return c.url
    }
}
