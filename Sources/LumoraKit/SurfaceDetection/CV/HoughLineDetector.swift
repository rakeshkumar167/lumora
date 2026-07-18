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
}
