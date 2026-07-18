import Foundation

/// Shared geometry/color for the projected calibration pattern — used by both
/// the projected SwiftUI view (app) and the marker detector so they agree.
public enum CalibrationPattern {
    /// Magenta — a saturated hue rarely present in rooms.
    public static let markerColor = RGBAColor(r: 0.92, g: 0.20, b: 0.62)
    /// Corner-marker center inset from each edge, as a fraction of the frame.
    public static let markerInsetFraction: Double = 0.08
    /// Marker disc radius, as a fraction of the smaller frame dimension.
    public static let markerRadiusFraction: Double = 0.045
    /// Glow-boundary inset from the edges, as a fraction of the frame.
    public static let boundaryInsetFraction: Double = 0.04
}
