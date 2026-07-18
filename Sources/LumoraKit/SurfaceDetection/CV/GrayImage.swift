import Foundation

/// A single-channel image: row-major float pixels in `0...1`, top-left origin.
public struct GrayImage: Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height, "pixel count must equal width*height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Value at (x, y); callers must pass in-bounds coordinates.
    @inlinable public func at(_ x: Int, _ y: Int) -> Float { pixels[y * width + x] }
}
