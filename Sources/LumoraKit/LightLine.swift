import CoreGraphics
import Foundation

/// Visual + timing parameters for a light line network.
public struct LightLineStyle: Equatable, Codable {
    public var color: RGBAColor       // primary line color
    public var glowColor: RGBAColor   // accent / tracer-head tint
    public var thickness: Double      // core line width in points
    public var glowRadius: Double     // blur radius for the glow layer
    public var fillDuration: Double   // seconds for the front to reach maxDistance
    public var holdDuration: Double   // seconds fully-lit before reset

    public init(
        color: RGBAColor = .cyan,
        glowColor: RGBAColor = .white,
        thickness: Double = 3,
        glowRadius: Double = 12,
        fillDuration: Double = 3,
        holdDuration: Double = 1.5
    ) {
        self.color = color
        self.glowColor = glowColor
        self.thickness = thickness
        self.glowRadius = glowRadius
        self.fillDuration = fillDuration
        self.holdDuration = holdDuration
    }

    public static let `default` = LightLineStyle()
}

/// A network of connected line segments that render as a glowing path with a
/// pulse that fills from a chosen source joint, splitting at forks.
///
/// The graph is undirected: `joints` are nodes (normalized 0...1 positions),
/// `segments` are edges referencing joint ids. A joint of degree >= 3 is a fork.
public struct LightLine: Identifiable, Equatable, Codable {
    public struct Joint: Identifiable, Equatable, Codable {
        public var id: UUID
        public var point: CGPoint    // normalized 0...1 room-space position
        public init(id: UUID = UUID(), point: CGPoint) {
            self.id = id
            self.point = point
        }
    }

    public struct Segment: Identifiable, Equatable, Codable {
        public var id: UUID
        public var a: UUID           // Joint.ID
        public var b: UUID           // Joint.ID
        public init(id: UUID = UUID(), a: UUID, b: UUID) {
            self.id = id
            self.a = a
            self.b = b
        }
    }

    public var id: UUID
    public var name: String
    public var joints: [Joint]
    public var segments: [Segment]
    public var sourceJointID: UUID?
    public var style: LightLineStyle
    public var isVisible: Bool
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        name: String,
        joints: [Joint] = [],
        segments: [Segment] = [],
        sourceJointID: UUID? = nil,
        style: LightLineStyle = .default,
        isVisible: Bool = true,
        opacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.joints = joints
        self.segments = segments
        self.sourceJointID = sourceJointID
        self.style = style
        self.isVisible = isVisible
        self.opacity = opacity
    }

    /// An empty line ready for the pen tool to draw into.
    public static func empty(name: String) -> LightLine {
        LightLine(name: name)
    }

    // MARK: - Geometry / graph

    public func joint(_ id: UUID) -> Joint? {
        joints.first { $0.id == id }
    }

    /// Euclidean length of a segment in normalized space (0 if an endpoint is missing).
    public func length(of segment: Segment) -> Double {
        guard let a = joint(segment.a)?.point, let b = joint(segment.b)?.point else { return 0 }
        return Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// Shortest-path distance (summed segment lengths) from the source joint to
    /// every reachable joint, keyed by joint id. Empty if there is no source.
    /// Unreachable joints are absent from the result.
    public func distancesFromSource() -> [UUID: Double] {
        guard let source = sourceJointID, joint(source) != nil else { return [:] }

        // Adjacency: joint id -> [(neighbor id, weight)].
        var adj: [UUID: [(UUID, Double)]] = [:]
        for s in segments {
            let w = length(of: s)
            adj[s.a, default: []].append((s.b, w))
            adj[s.b, default: []].append((s.a, w))
        }

        // Dijkstra (small graphs: linear scan for the min is fine).
        var dist: [UUID: Double] = [source: 0]
        var settled: Set<UUID> = []
        while true {
            // Pick the unsettled joint with the smallest tentative distance.
            var current: UUID?
            var best = Double.greatestFiniteMagnitude
            for (id, d) in dist where !settled.contains(id) && d < best {
                best = d
                current = id
            }
            guard let u = current else { break }
            settled.insert(u)
            for (v, w) in adj[u] ?? [] where !settled.contains(v) {
                let nd = best + w
                if nd < (dist[v] ?? .greatestFiniteMagnitude) {
                    dist[v] = nd
                }
            }
        }
        return dist
    }

    /// The largest reachable joint distance — the full-fill target. 0 if none.
    public func maxDistance() -> Double {
        distancesFromSource().values.max() ?? 0
    }

    /// Fraction (0...1) of `segment` that is lit given the current absolute
    /// front distance, lighting from the endpoint nearer the source outward.
    /// Returns 0 for segments unreachable from the source.
    public func litFraction(of segment: Segment, front: Double, distances: [UUID: Double]) -> Double {
        guard let dA = distances[segment.a], let dB = distances[segment.b] else { return 0 }
        let near = Swift.min(dA, dB)
        let segLen = length(of: segment)
        guard segLen > 0 else { return front >= near ? 1 : 0 }
        let f = (front - near) / segLen
        return Swift.min(Swift.max(f, 0), 1)
    }
}

/// The fill -> hold -> reset timing cycle. `frontFraction` returns the fill
/// front as a fraction (0...1) of the network's max distance for a given
/// elapsed time since the animation started.
public struct FillCycle: Equatable {
    public var fillDuration: Double
    public var holdDuration: Double

    public init(fillDuration: Double, holdDuration: Double) {
        self.fillDuration = fillDuration
        self.holdDuration = holdDuration
    }

    public func frontFraction(elapsed: Double) -> Double {
        let fill = Swift.max(fillDuration, 0.0001)
        let period = fill + Swift.max(holdDuration, 0)
        guard period > 0 else { return 1 }
        let p = elapsed.truncatingRemainder(dividingBy: period)
        let phase = p < 0 ? p + period : p
        return phase < fill ? phase / fill : 1
    }
}
