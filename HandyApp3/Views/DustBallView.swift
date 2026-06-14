import SwiftUI

/// An intro flourish: thousands of multi-colored dust motes start scattered far out as a
/// 3D cloud, swirl inward over `duration` seconds (the whole cloud tumbling as they
/// spiral), then settle and freeze into the letter **H**.
///
/// Each mote owns a final position on the "H" glyph. It flies from a scaled-out, depth-
/// puffed position down to that target while its swirl unwinds; the cloud tumbles during
/// the flight but resolves front-on and upright at the end so the H reads cleanly.
struct DustBallView: View {
    private let particles: [DustMote]
    private let duration: Double = 5

    @State private var start = Date()
    @State private var frozen = false
    @State private var runID = UUID()

    init(count: Int = 2200) {
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in
            DustMote(
                target: sampleH(&rng),
                startScale: Double.random(in: 2.2...4.2, using: &rng),
                swirl: Double.random(in: 2.0...7.0, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                cloudZ: Double.random(in: -1...1, using: &rng),
                size: Double.random(in: 0.7...1.9, using: &rng),
                hue: Double.random(in: 0...1, using: &rng)
            )
        }
    }

    var body: some View {
        Group {
            if frozen {
                Canvas { ctx, size in draw(ctx, size, t: 1) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        let elapsed = timeline.date.timeIntervalSince(start)
                        draw(ctx, size, t: min(max(elapsed / duration, 0), 1))
                    }
                }
            }
        }
        .onAppear { restart() }
    }

    /// Replays the animation from the start (e.g. each time the Activity tab opens).
    private func restart() {
        let id = UUID()
        runID = id
        start = Date()
        frozen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if runID == id { frozen = true }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, t: Double) {
        let ease = 1 - pow(1 - t, 3)                 // ease-out: fast inrush, gentle settle
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) * 0.5
        let cameraDistance = 6.0
        let focal = 4.0
        let yaw = 4 * .pi * t                         // two full turns → ends front-facing
        let tilt = 0.4 * (1 - ease)                   // tumble that flattens out at the end

        struct Projected { let point: CGPoint; let radius: Double; let depth: Double; let color: Color }
        var projected: [Projected] = []
        projected.reserveCapacity(particles.count)

        for mote in particles {
            let moteScale = mote.startScale + (1 - mote.startScale) * ease
            let swirl = mote.swirl * (1 - ease)       // unwinds to 0 → lands on target
            var v = mote.target * moteScale
            v.z += mote.cloudZ * 1.5 * (1 - ease)     // 3D puff during flight, gone at end
            v = rotateY(v, swirl)
            v = rotateY(v, yaw)
            v = rotateX(v, tilt)

            let perspective = focal / (cameraDistance - v.z)
            let point = CGPoint(x: center.x + v.x * perspective * scale,
                                y: center.y - v.y * perspective * scale)
            let depthFade = 0.55 + 0.45 * min(max((v.z + 1) / 2, 0), 1)
            let alpha = 0.25 + 0.75 * ease            // dust solidifies as it gathers
            let color = Color(hue: mote.hue, saturation: 0.7, brightness: 0.95 * depthFade)
                .opacity(alpha)
            projected.append(Projected(point: point,
                                       radius: mote.size * perspective * 1.6,
                                       depth: v.z,
                                       color: color))
        }

        // Painter's algorithm: far motes first so near ones overlay them.
        projected.sort { $0.depth < $1.depth }
        for p in projected {
            let rect = CGRect(x: p.point.x - p.radius, y: p.point.y - p.radius,
                              width: p.radius * 2, height: p.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(p.color))
        }
    }
}

private struct DustMote {
    let target: SIMD3<Double>   // final position forming the letter H
    let startScale: Double      // initial outward scale (final scale is 1)
    let swirl: Double           // extra angle (radians) that unwinds to 0 during the flight
    let cloudZ: Double          // extra depth during flight, collapsing to 0 at the end
    let size: Double            // base point-size multiplier
    let hue: Double
}

// MARK: - Math helpers

private func rotateY(_ v: SIMD3<Double>, _ a: Double) -> SIMD3<Double> {
    let c = cos(a), s = sin(a)
    return SIMD3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
}

private func rotateX(_ v: SIMD3<Double>, _ a: Double) -> SIMD3<Double> {
    let c = cos(a), s = sin(a)
    return SIMD3(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
}

/// A uniform-by-area sample of the letter "H" glyph, centered at the origin. Height spans
/// y ∈ [-1, 1]; two vertical bars plus a crossbar, with a touch of z thickness.
private func sampleH(_ rng: inout SystemRandomNumberGenerator) -> SIMD3<Double> {
    let barWidth = 0.28
    let leftMin = -0.7, leftMax = -0.7 + barWidth          // left bar x range
    let rightMin = 0.7 - barWidth, rightMax = 0.7          // right bar x range
    let crossHalf = 0.18                                   // crossbar half-height

    let areaBar = barWidth * 2.0
    let areaCross = (rightMin - leftMax) * (crossHalf * 2)
    let total = areaBar * 2 + areaCross

    var x = 0.0, y = 0.0
    let pick = Double.random(in: 0...total, using: &rng)
    if pick < areaBar {
        x = Double.random(in: leftMin...leftMax, using: &rng)
        y = Double.random(in: -1...1, using: &rng)
    } else if pick < areaBar * 2 {
        x = Double.random(in: rightMin...rightMax, using: &rng)
        y = Double.random(in: -1...1, using: &rng)
    } else {
        x = Double.random(in: leftMax...rightMin, using: &rng)
        y = Double.random(in: -crossHalf...crossHalf, using: &rng)
    }

    let glyphScale = 1.15
    let z = Double.random(in: -0.05...0.05, using: &rng)
    return SIMD3(x * glyphScale, y * glyphScale, z)
}
