import Foundation

public let BREAK_REPS = 6

/// One exercise in a break routine.
public struct Move: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var area: String
    public var camera: String
    public var stance: String
    public var howTo: String
    public var demoURL: String?
    public var target: Int

    public var id: String { key }

    public init(_ e: Exercise, target: Int = BREAK_REPS) {
        key = e.key; label = e.label; area = e.category; camera = e.camera
        stance = e.stance; howTo = e.how_to; demoURL = e.demo_url; self.target = target
    }

    /// Side-on and standing moves need the user to step back into frame first.
    public var needsPositioning: Bool { camera == "side" || stance == "standing" }
}

/// Up to three moves from the user's areas, rotating across breaks (`n` = break count).
/// No duplicates, and slot 1 is never the exercise that ended the previous break.
public func buildRoutine(_ catalog: [Exercise], areas: [String], lastKey: String?, n: Int) -> [Move] {
    var slots: [String] = []
    var i = 0
    while slots.count < 3 && !areas.isEmpty && i < 3 {
        slots.append(areas[(n + i) % areas.count])
        i += 1
    }
    var moves: [Move] = []
    for area in slots {
        let list = catalog.filter { $0.category == area }
        for k in 0..<list.count {
            let e = list[(n + k) % list.count]
            if moves.contains(where: { $0.key == e.key }) { continue }
            if moves.isEmpty && e.key == lastKey { continue }
            moves.append(Move(e))
            break
        }
    }
    return moves
}

/// Another exercise from the same area that isn't already in the routine, or nil.
public func swapMove(_ catalog: [Exercise], moves: [Move], at i: Int) -> Move? {
    let list = catalog.filter { $0.category == moves[i].area }
    guard let start = list.firstIndex(where: { $0.key == moves[i].key }) else { return nil }
    for step in 1..<max(list.count, 1) {
        let e = list[(start + step) % list.count]
        if !moves.enumerated().contains(where: { $0.offset != i && $0.element.key == e.key }) { return Move(e) }
    }
    return nil
}

/// The next move (after `from`, wrapping) that hasn't reached its target, or nil.
public func nextOpenMove(_ moves: [Move], reps: [Int], from: Int) -> Int? {
    guard !moves.isEmpty else { return nil }
    for step in 1...moves.count {
        let k = (from + step) % moves.count
        if reps[k] < moves[k].target { return k }
    }
    return nil
}
