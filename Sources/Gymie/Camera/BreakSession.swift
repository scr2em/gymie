import AppKit
import AVFoundation
import GymieCore
import Observation

/// One break: optional 3-skip warning, the camera-coached routine, then the summary.
@MainActor @Observable
final class BreakSession {
    enum Phase { case warning, routine, summary }

    let manual: Bool
    var phase: Phase
    var moves: [Move]
    var reps: [Int]
    var scores: [[Int]]
    var index = 0
    var positioning = false
    var lastScore: Int?
    var cue: String?
    var cueGood = false
    var award: Award?
    var result: BreakResult?

    let coach = PoseCoach()
    private weak var model: AppModel?
    private var base: [Int]
    private var positionTimer: Task<Void, Never>?
    private let voice = Voice()

    static let positionTimeout: Duration = .seconds(15)

    init(model: AppModel, moves: [Move], manual: Bool, warning: Bool) {
        self.model = model
        self.moves = moves
        self.manual = manual
        reps = moves.map { _ in 0 }
        base = moves.map { _ in 0 }
        scores = moves.map { _ in [] }
        phase = warning ? .warning : .routine
        coach.onFrame = { [weak self] frame in self?.onFrame(frame) }
        if !warning { Task { await begin() } }
    }

    var move: Move? { moves.indices.contains(index) ? moves[index] : nil }
    var settings: Preferences { model?.state.settings ?? Preferences() }
    var canSnooze: Bool { model?.state.schedule.canSnooze ?? false }
    var skips: Int { model?.state.schedule.skipsInRow ?? 0 }
    var totalReps: Int { reps.reduce(0, +) }
    var targetReps: Int { moves.reduce(0) { $0 + $1.target } }
    var liveXp: Int { breakXp(countedReps: totalReps, targetReps: targetReps, scores: scores.flatMap { $0 }) }
    var canSwap: Bool { model.map { swapMove($0.catalog, moves: moves, at: index) != nil } ?? false }

    var isOffline: Bool {
        switch coach.status {
        case .offline, .cameraDenied: true
        default: false
        }
    }

    // MARK: Flow

    func startFromWarning() {
        phase = .routine
        Task { await begin() }
    }

    private func begin() async {
        guard let move else { return }
        show(0, announce: false)
        coach.onCatalog = { [weak model] list in model?.updateCatalog(list) }
        await coach.start(serverURL: settings.poseServerURL, exercise: move.key, blur: settings.blurCamera) { [weak model] in
            // nil means the engine is ready; only a missing model is an error here.
            guard let model else { return "Gymie isn't ready." }
            return await model.preparePoseEngine()
        }
        announce()
    }

    private func show(_ i: Int, announce: Bool = true) {
        index = i
        base[i] = reps[i]
        lastScore = nil
        cue = nil
        coach.setExercise(moves[i].key)
        positionTimer?.cancel()
        positioning = moves[i].needsPositioning
        if positioning {
            positionTimer = Task { [weak self] in
                try? await Task.sleep(for: BreakSession.positionTimeout)
                guard !Task.isCancelled else { return }
                self?.positioning = false
            }
        }
        if announce { self.announce() }
    }

    func select(_ i: Int) {
        guard i != index, moves.indices.contains(i), phase == .routine else { return }
        show(i)
    }

    private func announce() {
        guard settings.voice, let move else { return }
        voice.say("\(move.label). \(move.target - reps[index]) reps.")
    }

    private func onFrame(_ frame: PoseFrame) {
        guard phase == .routine, let move else { return }
        if positioning && !frame.notVisible {
            positioning = false
            positionTimer?.cancel()
        }
        let was = reps[index]
        reps[index] = min(base[index] + frame.summary.reps, move.target)
        if let rep = frame.rep_event {
            scores[index].append(rep.score)
            lastScore = rep.score
            let issue = rep.issue_text?.first
            if let issue {
                cue = issue; cueGood = false
            } else if rep.partial {
                cue = "Go a little further"; cueGood = false
            } else {
                cue = rep.score >= 85 ? "Great form" : nil; cueGood = true
            }
            if settings.sounds && !rep.partial { Sounds.play(.rep) }
            if settings.voice { voice.say(rep.partial ? "Go a little further" : (issue ?? "\(reps[index])")) }
        }
        if was < move.target && reps[index] >= move.target {
            if let next = nextOpenMove(moves, reps: reps, from: index) {
                if settings.sounds { Sounds.play(.moveDone) }
                show(next)
            } else {
                done()
            }
        }
    }

    func swap() {
        guard let model, let replacement = swapMove(model.catalog, moves: moves, at: index) else { return }
        moves[index] = replacement
        reps[index] = 0
        scores[index] = []
        show(index)
    }

    func currentResult() -> BreakResult {
        let all = scores.flatMap { $0 }
        return BreakResult(
            scored: !all.isEmpty,
            countedReps: totalReps,
            targetReps: targetReps,
            scores: all,
            moves: moves.enumerated().map { .init(key: $0.element.key, area: $0.element.area, completed: reps[$0.offset] >= $0.element.target) })
    }

    // MARK: Actions

    func done() {
        guard phase != .summary, let model else { return }
        let result = currentResult()
        self.result = result
        coach.stop()
        positionTimer?.cancel()
        let award = model.completeBreak(result, lastKey: moves.last?.key)
        self.award = award
        phase = .summary
        if settings.sounds { Sounds.play(award.levelUp != nil ? .levelUp : .finish) }
        if settings.voice {
            voice.say(award.levelUp.map { "Level up! You're now a \($0.name)." }
                      ?? (result.scored ? "Nice work. \(award.breakdown.total) XP." : "Break logged."))
        }
    }

    func snooze() { leave(.snooze) }
    func skip() { leave(.skip) }

    func pauseHour() {
        model?.pause()
        model?.closeBreakWindow()
    }

    private func leave(_ action: Schedule.Action) {
        model?.breakAction(action)
        model?.closeBreakWindow()
    }

    func close() { model?.closeBreakWindow() }

    func stop() {
        coach.stop()
        positionTimer?.cancel()
        voice.stop()
    }
}

// MARK: - Voice and sounds

@MainActor
final class Voice {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.52
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

enum Sounds {
    enum Cue: String {
        case rep = "Tink", moveDone = "Pop", finish = "Glass", levelUp = "Hero"
    }

    @MainActor static func play(_ cue: Cue) {
        NSSound(named: NSSound.Name(cue.rawValue))?.play()
    }
}
