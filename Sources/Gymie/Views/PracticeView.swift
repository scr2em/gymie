import GymieCore
import SwiftUI

/// Try any exercise with live rep counting. No XP, no schedule.
struct PracticeView: View {
    let coach: PoseCoach
    @Environment(AppModel.self) private var model
    @State private var selected: Exercise?
    @State private var reps = 0
    @State private var lastScore: Int?
    @State private var cue: String?

    var body: some View {
        HSplitView {
            List(selection: Binding(get: { selected?.key }, set: { key in select(model.catalog.first { $0.key == key }) })) {
                ForEach(AREAS, id: \.self) { area in
                    Section(area) {
                        ForEach(model.catalog.filter { $0.category == area }) { e in
                            Text(e.label).tag(e.key)
                        }
                    }
                }
            }
            .frame(minWidth: 220, maxWidth: 280)

            VStack(alignment: .leading, spacing: 14) {
                if let selected {
                    Text(selected.label).font(.title2.weight(.semibold))
                    ZStack(alignment: .bottomTrailing) {
                        CameraPreview(coach: coach)
                        HStack {
                            if let cue { Text(cue).padding(6).background(.ultraThinMaterial, in: Capsule()) }
                            Spacer()
                            Text("\(reps)").font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                .padding(.horizontal, 14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(12)
                    }
                    HStack {
                        statusText
                        Spacer()
                        if let lastScore { Text("Last rep form: \(lastScore)").monospacedDigit() }
                        Button("Reset count") { select(selected) }
                    }
                    Text(selected.how_to).foregroundStyle(.secondary)
                    if let demo = selected.demo_url, let url = URL(string: demo) {
                        Link(destination: url) { Label("Watch demo", systemImage: "play.rectangle.fill") }
                    }
                } else {
                    ContentUnavailableView("Pick an exercise", systemImage: "figure.mixed.cardio",
                                           description: Text("Practice any move with live rep counting. Practice doesn't earn XP."))
                }
                Spacer()
            }
            .padding(20)
            .frame(minWidth: 520)
        }
        .onAppear {
            coach.onCatalog = { model.updateCatalog($0) }
            coach.onFrame = { frame in
                reps = frame.summary.reps
                if let rep = frame.rep_event {
                    lastScore = rep.score
                    cue = rep.issue_text?.first ?? (rep.partial ? "Go a little further" : nil)
                }
            }
        }
    }

    @ViewBuilder private var statusText: some View {
        switch coach.status {
        case .idle, .starting: Label(coach.detail ?? "Connecting…", systemImage: "circle.dotted")
        case .live: Label("Live", systemImage: "circle.fill").foregroundStyle(.green)
        case .offline(let reason): Label(reason, systemImage: "wifi.exclamationmark").foregroundStyle(.orange).lineLimit(2)
        case .cameraDenied: Label("Camera access is off", systemImage: "video.slash").foregroundStyle(.orange)
        }
    }

    private func select(_ e: Exercise?) {
        guard let e else { return }
        selected = e
        reps = 0
        lastScore = nil
        cue = nil
        if coach.status == .live || coach.status == .starting {
            coach.setExercise(e.key)
        } else {
            Task {
                await coach.start(serverURL: model.state.settings.poseServerURL, exercise: e.key,
                                  blur: model.state.settings.blurCamera) { await model.preparePoseEngine() }
            }
        }
    }
}
