// Run: swift scripts/verify_weather_widget.swift
// Standalone replica of WeatherWidgetView with sample data (day + night).
import AppKit
import SwiftUI

func icon(_ code: Int, _ day: Bool) -> String {
    switch code { case 0,1: return day ? "sun.max.fill" : "moon.stars.fill"
    case 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"; default: return "cloud.fill" }
}
func condition(_ code: Int) -> String {
    switch code { case 0: return "Clear"; case 1: return "Mainly Clear"; case 2: return "Partly Cloudy"; default: return "Cloudy" }
}

struct Widget: View {
    let temp: Int; let code: Int; let isDay: Bool; let place: String; let timeStr: String
    var body: some View {
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height), pad = base*0.12
            ZStack {
                RoundedRectangle(cornerRadius: base*0.14, style: .continuous)
                    .fill(LinearGradient(colors: isDay
                        ? [Color(red:0.29,green:0.56,blue:0.89), Color(red:0.53,green:0.74,blue:0.96)]
                        : [Color(red:0.08,green:0.10,blue:0.24), Color(red:0.22,green:0.20,blue:0.40)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: base*0.14, style: .continuous).stroke(.white.opacity(0.12), lineWidth: max(1, base*0.006)))
                VStack(alignment: .leading, spacing: base*0.03) {
                    HStack(spacing: base*0.03) {
                        Image(systemName: "location.fill").font(.system(size: base*0.06))
                        Text(place).font(.system(size: base*0.085, weight: .semibold, design: .rounded)).lineLimit(1)
                        Spacer()
                        Text(timeStr).font(.system(size: base*0.075, weight: .medium, design: .rounded)).opacity(0.85)
                    }
                    HStack(alignment: .top, spacing: base*0.02) {
                        Text("\(temp)").font(.system(size: base*0.30, weight: .thin, design: .rounded))
                        Text("°C").font(.system(size: base*0.12, design: .rounded)).padding(.top, base*0.04)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: base*0.04) {
                        Image(systemName: icon(code, isDay)).symbolRenderingMode(.multicolor).font(.system(size: base*0.11))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(condition(code)).font(.system(size: base*0.07, weight: .semibold, design: .rounded))
                            Text("Saturday, 12 Jul").font(.system(size: base*0.055, design: .rounded)).opacity(0.8)
                        }
                        Spacer()
                    }
                }.padding(pad).foregroundStyle(.white)
            }.frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct Board: View {
    var body: some View {
        HStack(spacing: 20) {
            Widget(temp: 27, code: 2, isDay: true, place: "Bangalore", timeStr: "8:16 PM").frame(width: 300, height: 300)
            Widget(temp: 12, code: 0, isDay: false, place: "London", timeStr: "3:47 AM").frame(width: 300, height: 300)
        }.padding(24).background(Color(white: 0.1))
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board()); r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/weather_widget.png")); print("wrote /tmp/weather_widget.png")
    }
}
