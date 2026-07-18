import Foundation

/// Foreground component labels: 0 = background, 1…count = components.
public struct LabelField: Equatable {
    public let width: Int
    public let height: Int
    public var labels: [Int]
    public let count: Int
}

/// 8-connected connected-component labeling via iterative flood fill.
public enum ConnectedComponents {
    public static func label(_ binary: [Bool], width w: Int, height h: Int) -> LabelField {
        var labels = [Int](repeating: 0, count: w * h)
        var next = 0
        let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
        let dy = [-1, -1, -1, 0, 0, 1, 1, 1]
        var stack: [Int] = []
        for start in 0..<(w * h) where binary[start] && labels[start] == 0 {
            next += 1
            labels[start] = next
            stack.append(start)
            while let idx = stack.popLast() {
                let x = idx % w, y = idx / w
                for k in 0..<8 {
                    let nx = x + dx[k], ny = y + dy[k]
                    if nx >= 0, nx < w, ny >= 0, ny < h {
                        let j = ny * w + nx
                        if binary[j], labels[j] == 0 { labels[j] = next; stack.append(j) }
                    }
                }
            }
        }
        return LabelField(width: w, height: h, labels: labels, count: next)
    }
}
