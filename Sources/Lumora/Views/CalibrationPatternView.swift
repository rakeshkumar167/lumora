import LumoraKit
import SwiftUI

/// The projected calibration pattern: a glowing magenta boundary + four filled
/// magenta corner markers on black. Fills the projector output so the markers
/// sit at the projection's corners.
struct CalibrationPatternView: View {
    private var magenta: Color {
        Color(red: CalibrationPattern.markerColor.r,
              green: CalibrationPattern.markerColor.g,
              blue: CalibrationPattern.markerColor.b)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let minDim = min(w, h)
            let bInset = minDim * CalibrationPattern.boundaryInsetFraction
            let mInset = minDim * CalibrationPattern.markerInsetFraction
            let r = minDim * CalibrationPattern.markerRadiusFraction
            let corners = [CGPoint(x: mInset, y: mInset),
                           CGPoint(x: w - mInset, y: mInset),
                           CGPoint(x: w - mInset, y: h - mInset),
                           CGPoint(x: mInset, y: h - mInset)]
            ZStack {
                Color.black
                RoundedRectangle(cornerRadius: 4)
                    .stroke(magenta, lineWidth: max(3, minDim * 0.006))
                    .padding(bInset)
                    .shadow(color: magenta, radius: 14)
                    .shadow(color: magenta, radius: 6)
                ForEach(corners.indices, id: \.self) { i in
                    Circle()
                        .fill(magenta)
                        .frame(width: 2 * r, height: 2 * r)
                        .position(corners[i])
                        .shadow(color: magenta, radius: 12)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }
}
