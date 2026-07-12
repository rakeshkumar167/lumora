import CoreGraphics
import Foundation

/// Trace paths extracted from a real PCB image (baked by scripts/generate_circuit.swift).
/// Loaded once; the Circuit Trace effect plays these back with a progressive reveal.
enum CircuitPattern {
    struct Pattern {
        /// Ordered polylines in normalized 0…1 (top-left origin).
        let paths: [[CGPoint]]
    }

    static let shared: Pattern? = load()

    private static func load() -> Pattern? {
        guard let url = Bundle.module.url(forResource: "circuit", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let raw = obj["paths"] as? [[[Double]]] else { return nil }
        let paths: [[CGPoint]] = raw.compactMap { pl in
            let pts = pl.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            return pts.count >= 2 ? pts : nil
        }
        return paths.isEmpty ? nil : Pattern(paths: paths)
    }
}
