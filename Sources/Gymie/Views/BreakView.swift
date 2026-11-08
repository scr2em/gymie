import GymieCore
import SwiftUI

struct BreakView: View {
    let session: BreakSession

    var body: some View {
        Group {
            switch session.phase {
            case .warning: WarningView(session: session)
            case .routine: RoutineView(session: session)
            case .summary: SummaryView(session: session)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

// MARK: - Warning after 3 skips

private struct WarningView: View {
    let session: BreakSession
    @Environment(AppModel.self) private var model

    var body: some View {
        let hours = Schedule.warningHours(skips: session.skips, intervalMin: model.state.settings.intervalMin)
        VStack(spacing: 18) {
            Image(systemName: "chair.lounge.fill").font(.system(size: 54)).foregroundStyle(.orange)
            Text("~\(hours.formatted()) hours without moving").font(.largeTitle.weight(.bold))
            Text("You've skipped \(session.skips) breaks in a row. Two minutes now beats a stiff neck tonight.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 12) {
                Button("Start a break now") { session.startFromWarning() }
                    .buttonStyle(.borderedProminent).tint(.mint).keyboardShortcut(.defaultAction)
                Button(session.canSnooze ? "Snooze 20 min" : "Snoozed twice, time to move") { session.snooze() }
                    .disabled(!session.canSnooze)
                Button("Pause 1 hr") { session.pauseHour() }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Routine

private struct RoutineView: View {
    let session: BreakSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 20) {
                cameraColumn
                guideColumn.frame(width: 300)
            }
            .padding(20)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let move = session.move {
                Image(systemName: AREA_SYMBOLS[move.area] ?? "figure.walk").font(.title2).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(move.area).font(.caption).foregroundStyle(.secondary)
                    Text(move.label).font(.title2.weight(.semibold))
                }
            } else {
                Text("Time to move").font(.title2.weight(.semibold))
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(session.moves.indices, id: \.self) { i in
                    Button { session.select(i) } label: {
                        Capsule()
                            .fill(session.reps[i] >= session.moves[i].target ? Color.mint : (i == session.index ? Color.mint.opacity(0.5) : Color.gray.opacity(0.3)))
                            .frame(width: 36, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(session.moves[i].label)
                }
            }
            Text("\(min(session.index + 1, max(session.moves.count, 1)))/\(max(session.moves.count, 1))")
                .font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            Label("\(session.liveXp) XP", systemImage: "bolt.fill")
                .font(.headline.monospacedDigit()).foregroundStyle(.yellow)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var cameraColumn: some View {
        ZStack {
            CameraPreview(coach: session.coach, dim: session.positioning)
            VStack {
                HStack {
                    statusPill
                    Spacer()
                    if let score = session.lastScore {
                        Text("Form \(score)").font(.headline.monospacedDigit())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Spacer()
                if session.positioning, let move = session.move {
                    Label(move.camera == "side" ? "Turn sideways and step back until your whole body is in frame"
                                                : "Step back until your whole body is in frame",
                          systemImage: "person.fill.viewfinder")
                        .font(.headline).padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                HStack(alignment: .bottom) {
                    if let cue = session.cue {
                        Text(cue).font(.headline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background((session.cueGood ? Color.mint : Color.orange).opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Spacer()
                    if let move = session.move {
                        Text("\(session.reps[session.index]) / \(move.target)")
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(12)
            if session.isOffline { offlineOverlay }
        }
    }

    @ViewBuilder private var statusPill: some View {
        let (text, color): (String, Color) = switch session.coach.status {
        case .idle, .starting: (session.coach.detail ?? "Connecting…", .orange)
        case .live: ("Live", .green)
        case .offline: ("Offline", .red)
        case .cameraDenied: ("No camera", .red)
        }
        Label(text, systemImage: "circle.fill")
            .labelStyle(.titleAndIcon).font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var offlineOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: session.coach.status == .cameraDenied ? "video.slash.fill" : "wifi.exclamationmark")
                .font(.system(size: 34))
            Text(session.coach.status == .cameraDenied ? "Camera access is off" : "No rep counting right now")
                .font(.headline)
            Group {
                if case .offline(let reason) = session.coach.status { Text(reason) }
                if session.coach.status == .cameraDenied {
                    Text("Allow Gymie in System Settings → Privacy & Security → Camera.")
                }
            }
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Follow the steps on the right, then press Done. It counts for your schedule but earns no XP.")
                .font(.callout).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var guideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let move = session.move {
                Text("How to").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(move.howTo).font(.title3).fixedSize(horizontal: false, vertical: true)
                Label(move.camera == "side" ? "Side-on to the camera" : "Facing the camera",
                      systemImage: move.camera == "side" ? "person.crop.rectangle" : "person.crop.square")
                    .font(.callout).foregroundStyle(.secondary)
                if move.stance == "standing" {
                    Label("Standing", systemImage: "figure.stand").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    if let demo = move.demoURL, let url = URL(string: demo) {
                        Link(destination: url) { Label("Watch demo", systemImage: "play.rectangle.fill") }
                    }
                    Spacer()
                    if session.canSwap {
                        Button("Different exercise") { session.swap() }.buttonStyle(.link)
                    }
                }
            } else {
                Text("Stand up, roll your shoulders, look out of a window for a minute. Then press Done.")
                    .font(.title3)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(session.moves.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: session.reps[i] >= session.moves[i].target ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(session.reps[i] >= session.moves[i].target ? .mint : .secondary)
                        Text(session.moves[i].label).fontWeight(i == session.index ? .semibold : .regular)
                        Spacer()
                        Text("\(session.reps[i])/\(session.moves[i].target)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(session.manual ? "Break started by you" : "Scheduled break")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !session.manual {
                Button("Skip") { session.skip() }
                Button(session.canSnooze ? "Snooze 20 min" : "Snoozed twice, time to move") { session.snooze() }
                    .disabled(!session.canSnooze)
            }
            Button("Done") { session.done() }
                .buttonStyle(.borderedProminent).tint(.mint).keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Summary

private struct SummaryView: View {
    let session: BreakSession
    @Environment(AppModel.self) private var model
    @State private var shownTotal = 0
    @State private var barXp = 0

    var body: some View {
        let award = session.award
        let total = award?.breakdown.total ?? 0
        ZStack {
            VStack(spacing: 20) {
                if let up = award?.levelUp {
                    Text("Level up!").font(.title.weight(.heavy)).foregroundStyle(.mint)
                    Text("You're now a \(up.name)").font(.title2)
                } else {
                    Text(session.result?.scored == true ? "Nice work" : "Break logged").font(.largeTitle.weight(.bold))
                }
                Text("+\(shownTotal) XP")
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .contentTransition(.numericText())
                if let b = award?.breakdown {
                    VStack(alignment: .leading, spacing: 6) {
                        line("Break", b.breakXp)
                        if b.firstBreak > 0 { line("First break today", b.firstBreak) }
                        if b.streak > 0 { line("Streak bonus", b.streak) }
                        ForEach(b.challenges, id: \.id) { c in line("Challenge: \(c.name)", c.bonus, symbol: "checkmark.seal.fill") }
                    }
                    .frame(width: 340)
                }
                if session.result?.scored == false {
                    Text("No camera scoring this time, so no XP. The break still counts for your schedule.")
                        .foregroundStyle(.secondary)
                }
                LevelHeader(xp: barXp).frame(width: 420)
                if let badges = award?.newBadges, !badges.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(badges, id: \.self) { id in
                            Label("New badge: \(badgeLabel(id))", systemImage: badgeSymbol(id))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.mint.opacity(0.2), in: Capsule())
                        }
                    }
                }
                Button("Back to work") { session.close() }
                    .buttonStyle(.borderedProminent).tint(.mint).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if award?.levelUp != nil { ConfettiView() }
        }
        .task {
            let end = model.state.profile.xp
            barXp = end - total
            withAnimation(.easeOut(duration: 1.2)) { barXp = end }
            let steps = max(1, min(total, 30))
            for k in 1...steps {
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation { shownTotal = total * k / steps }
            }
        }
    }

    private func line(_ label: String, _ xp: Int, symbol: String = "plus.circle.fill") -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            Text("+\(xp)").monospacedDigit().fontWeight(.semibold)
        }
    }
}
