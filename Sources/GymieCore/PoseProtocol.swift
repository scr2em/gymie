import Foundation

/// Messages from the pose server (server/app.py, `ws://.../ws`).
/// Client sends `{"type":"config","exercise":key}` then binary JPEG frames, one in flight at a time.
public enum PoseMessage: Equatable, Sendable {
    case ready(exercises: [Exercise], connections: [[Int]])
    case config(exercise: String)
    case frame(PoseFrame)
    case error(String)
    case other(String)

    public static func decode(_ data: Data) -> PoseMessage? {
        struct Head: Decodable { var type: String }
        guard let head = try? JSONDecoder().decode(Head.self, from: data) else { return nil }
        switch head.type {
        case "ready":
            struct Ready: Decodable { var connections: [[Int]]? }
            let r = try? JSONDecoder().decode(Ready.self, from: data)
            return .ready(exercises: Catalog.parse(serverPayload: data) ?? [], connections: r?.connections ?? [])
        case "config":
            struct C: Decodable { var exercise: String }
            return (try? JSONDecoder().decode(C.self, from: data)).map { .config(exercise: $0.exercise) }
        case "frame":
            return (try? JSONDecoder().decode(PoseFrame.self, from: data)).map { .frame($0) }
        case "error":
            struct E: Decodable { var message: String? }
            return .error((try? JSONDecoder().decode(E.self, from: data))?.message ?? "error")
        default:
            return .other(head.type)
        }
    }
}

public struct PoseFrame: Decodable, Equatable, Sendable {
    public struct Feedback: Decodable, Equatable, Sendable {
        public var code: String
        public var text: String
    }
    public struct RepEvent: Decodable, Equatable, Sendable {
        public var index: Int
        public var score: Int
        public var partial: Bool
        public var issues: [String]
        public var issue_text: [String]?
    }
    public struct Summary: Decodable, Equatable, Sendable {
        public var reps: Int
        public var partial_reps: Int?
        public var avg_score: Double?
    }

    public var exercise: String
    public var stage: String?
    public var angle: Double?
    public var feedback: [Feedback]
    public var rep_event: RepEvent?
    public var summary: Summary
    /// Normalized [x, y, visibility] per MediaPipe landmark (33), in the sent image's coordinates.
    public var landmarks: [[Double]]?
    public var latency_ms: Double?

    public var notVisible: Bool { landmarks == nil || feedback.contains { $0.code == "not_visible" } }
}

/// MediaPipe pose connections, used until the server's `ready` message provides its own.
public let DEFAULT_CONNECTIONS: [[Int]] = [
    [11, 12], [11, 13], [13, 15], [12, 14], [14, 16], [11, 23], [12, 24], [23, 24],
    [23, 25], [25, 27], [24, 26], [26, 28], [27, 29], [28, 30], [29, 31], [30, 32],
    [0, 7], [0, 8], [15, 17], [16, 18],
]
