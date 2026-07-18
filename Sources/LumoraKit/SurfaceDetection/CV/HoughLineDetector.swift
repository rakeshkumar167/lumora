import CoreGraphics
import Foundation

/// Deterministic Hough line-segment detector: accumulator → peak NMS →
/// segment extraction along each peak. Pure Swift.
public enum HoughLineDetector {
    public struct Config {
        public var thetaStepDeg: Double   // accumulator angular resolution
        public var rhoStep: Double        // accumulator distance resolution (px)
        public var minVotes: Int          // peak must have ≥ this many votes
        public var peakNMSHalfWindow: Int // suppress peaks within this cell radius
        public var maxLines: Int          // cap on peaks processed
        public var lineTolerance: Double  // px distance for an edge point to belong to a line
        public var maxGap: Double         // px gap along a line bridged into one segment
        public var minLength: Double      // discard shorter segments
        public init(thetaStepDeg: Double = 1, rhoStep: Double = 1, minVotes: Int = 20,
                    peakNMSHalfWindow: Int = 8, maxLines: Int = 200,
                    lineTolerance: Double = 1.5, maxGap: Double = 4, minLength: Double = 15) {
            self.thetaStepDeg = thetaStepDeg
            self.rhoStep = rhoStep
            self.minVotes = minVotes
            self.peakNMSHalfWindow = peakNMSHalfWindow
            self.maxLines = maxLines
            self.lineTolerance = lineTolerance
            self.maxGap = maxGap
            self.minLength = minLength
        }
    }

    struct HoughAccumulator {
        let thetaCount: Int
        let rhoCount: Int
        let rhoMin: Double
        var votes: [Int]
        let cosT: [Double]
        let sinT: [Double]
        func vote(_ theta: Int, _ rho: Int) -> Int { votes[theta * rhoCount + rho] }
    }

    static func accumulate(_ edges: EdgeMap, config: Config) -> HoughAccumulator {
        let w = edges.width, h = edges.height
        let thetaCount = Int((180.0 / config.thetaStepDeg).rounded())
        var cosT = [Double](repeating: 0, count: thetaCount)
        var sinT = [Double](repeating: 0, count: thetaCount)
        for t in 0..<thetaCount {
            let rad = Double(t) * config.thetaStepDeg * .pi / 180
            cosT[t] = cos(rad); sinT[t] = sin(rad)
        }
        let diag = (Double(w * w + h * h)).squareRoot()
        let rhoMin = -diag
        let rhoCount = Int((2 * diag / config.rhoStep).rounded()) + 1
        var votes = [Int](repeating: 0, count: thetaCount * rhoCount)

        for y in 0..<h {
            for x in 0..<w where edges.edges[y * w + x] {
                let fx = Double(x), fy = Double(y)
                for t in 0..<thetaCount {
                    let rho = fx * cosT[t] + fy * sinT[t]
                    var ri = Int(((rho - rhoMin) / config.rhoStep).rounded())
                    if ri < 0 { ri = 0 } else if ri >= rhoCount { ri = rhoCount - 1 }
                    votes[t * rhoCount + ri] += 1
                }
            }
        }
        return HoughAccumulator(thetaCount: thetaCount, rhoCount: rhoCount, rhoMin: rhoMin,
                                votes: votes, cosT: cosT, sinT: sinT)
    }

    public static func detect(_ edges: EdgeMap, config: Config = .init()) -> [DetectedLine] {
        let acc = accumulate(edges, config: config)
        let found = peaks(acc, config: config)

        // Cache edge point coordinates once.
        let w = edges.width, h = edges.height
        var pts: [(Double, Double)] = []
        for y in 0..<h { for x in 0..<w where edges.edges[y * w + x] { pts.append((Double(x), Double(y))) } }

        var out: [DetectedLine] = []
        for peak in found {
            let ct = acc.cosT[peak.theta], st = acc.sinT[peak.theta]
            let rho = acc.rhoMin + Double(peak.rhoIdx) * config.rhoStep
            // Points on this line, projected onto the line direction (-sinθ, cosθ).
            var proj: [(t: Double, x: Double, y: Double)] = []
            for (px, py) in pts {
                let dist = abs(px * ct + py * st - rho)
                if dist <= config.lineTolerance {
                    proj.append((t: -px * st + py * ct, x: px, y: py))
                }
            }
            if proj.count < 2 { continue }
            proj.sort { $0.t < $1.t }
            // Split into runs at gaps > maxGap; emit runs ≥ minLength.
            var runStart = 0
            for i in 1...proj.count {
                let broken = i == proj.count || (proj[i].t - proj[i - 1].t) > config.maxGap
                if broken {
                    let a = proj[runStart], b = proj[i - 1]
                    let line = DetectedLine(p1: CGPoint(x: a.x, y: a.y), p2: CGPoint(x: b.x, y: b.y))
                    if line.length >= config.minLength { out.append(line) }
                    runStart = i
                }
            }
        }
        return out
    }

    struct Peak { let theta: Int; let rhoIdx: Int; let votes: Int }

    /// Local-maxima peaks ≥ minVotes, greedily non-max-suppressed within
    /// `peakNMSHalfWindow` cells (in both θ and ρ), strongest first.
    static func peaks(_ acc: HoughAccumulator, config: Config) -> [Peak] {
        var candidates: [Peak] = []
        for t in 0..<acc.thetaCount {
            for r in 0..<acc.rhoCount {
                let v = acc.votes[t * acc.rhoCount + r]
                if v >= config.minVotes { candidates.append(Peak(theta: t, rhoIdx: r, votes: v)) }
            }
        }
        candidates.sort { $0.votes > $1.votes }
        var accepted: [Peak] = []
        for c in candidates {
            if accepted.count >= config.maxLines { break }
            var suppressed = false
            for a in accepted where abs(a.theta - c.theta) <= config.peakNMSHalfWindow
                && abs(a.rhoIdx - c.rhoIdx) <= config.peakNMSHalfWindow {
                suppressed = true; break
            }
            if !suppressed { accepted.append(c) }
        }
        return accepted
    }
}
