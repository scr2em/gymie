import GymieCore
import SwiftUI

/// Mirrored camera image (blurred when privacy is on) with the pose skeleton on top.
struct CameraPreview: View {
    let coach: PoseCoach
    var dim = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.85))
            if let image = coach.preview {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
            Canvas { ctx, size in
                guard let lm = coach.landmarks else { return }
                func point(_ i: Int) -> CGPoint? {
                    guard lm.indices.contains(i), lm[i].count >= 3, lm[i][2] > 0.5 else { return nil }
                    return CGPoint(x: (1 - lm[i][0]) * size.width, y: lm[i][1] * size.height)
                }
                var path = Path()
                for pair in coach.connections where pair.count == 2 {
                    if let a = point(pair[0]), let b = point(pair[1]) {
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                }
                ctx.stroke(path, with: .color(.mint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                for i in lm.indices {
                    if let p = point(i) {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.white))
                    }
                }
            }
            if dim { Color.black.opacity(0.35) }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("\(level)").font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Level \(level)")
    }
}

struct LevelHeader: View {
    let xp: Int

    var body: some View {
        let info = levelFor(xp)
        HStack(spacing: 12) {
            LevelBadge(level: info.level)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.name).font(.headline)
                    Spacer()
                    Text("\(xp) XP").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: info.progress).tint(.mint)
                if let next = info.next {
                    Text("\(next - xp) XP to level \(info.level + 1)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Top level reached").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    var symbol: String?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(value).font(.title3.weight(.semibold).monospacedDigit())
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Mon-Sun rows by week columns, like GitHub's contribution graph.
struct HeatmapView: View {
    let cells: [[HeatCell]]
    private let colors: [Color] = [.gray.opacity(0.18), .mint.opacity(0.35), .mint.opacity(0.55), .mint.opacity(0.75), .mint]

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(cells.indices, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(cells[w]) { cell in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cell.future ? Color.clear : colors[cell.level])
                            .opacity(cell.offday && cell.breaks == 0 ? 0.5 : 1)
                            .frame(width: 11, height: 11)
                            .help("\(cell.date.formatted(date: .abbreviated, time: .omitted)): \(cell.breaks) breaks, \(cell.xp) XP")
                    }
                }
            }
        }
    }
}

struct ConfettiView: View {
    @State private var start = Date()
    private let pieces: [(x: Double, delay: Double, speed: Double, color: Color, spin: Double)] = (0..<80).map { _ in
        (Double.random(in: 0...1), Double.random(in: 0...0.6), Double.random(in: 0.6...1.2),
         [Color.mint, .pink, .yellow, .orange, .blue, .purple].randomElement()!, Double.random(in: -6...6))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let local = max(0, t - p.delay)
                    let y = -20 + local * p.speed * size.height * 0.6
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(local * 3 + p.spin) * 18
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * p.spin))
                    piece.fill(Path(CGRect(x: -4, y: -2, width: 8, height: 4)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
