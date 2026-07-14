import CoreGraphics

/// Integer Hilbert space-filling curve. `points(order:)` returns the visitation
/// sequence over a 2^order × 2^order grid (integer cell coords). Pure + tested.
public enum HilbertCurve {
    public static func points(order: Int) -> [CGPoint] {
        let n = 1 << max(0, order)
        var result: [CGPoint] = []
        result.reserveCapacity(n * n)
        for d in 0..<(n * n) {
            var rx = 0, ry = 0, t = d, x = 0, y = 0
            var s = 1
            while s < n {
                rx = 1 & (t / 2)
                ry = 1 & (t ^ rx)
                if ry == 0 {
                    if rx == 1 { x = s - 1 - x; y = s - 1 - y }
                    swap(&x, &y)
                }
                x += s * rx; y += s * ry
                t /= 4
                s <<= 1
            }
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }
}
