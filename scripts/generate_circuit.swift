// Run: swift scripts/generate_circuit.swift
// Extracts trace paths from a real PCB image (scripts/circuit-template.jpg) via
// Vision contour detection and bakes them into Resources/circuit.json as
// normalized polylines ordered into a continuous pen walk. The Circuit Trace
// effect plays these back (progressive reveal) — cheap, no runtime Vision.
import AppKit
import Vision

let srcPath = "scripts/circuit-template.jpg"
guard let nsImage = NSImage(contentsOfFile: srcPath),
      let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot load \(srcPath)\n".data(using: .utf8)!); exit(1)
}

let req = VNDetectContoursRequest()
req.contrastAdjustment = 1.8
req.detectsDarkOnLight = false        // bright traces on a dark board
req.maximumImageDimension = 1024
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do { try handler.perform([req]) } catch { FileHandle.standardError.write("vision failed\n".data(using: .utf8)!); exit(1) }
guard let obs = req.results?.first as? VNContoursObservation else { exit(1) }

struct PL { var pts: [CGPoint]; var len: Double; var c: CGPoint }
var pls: [PL] = []
for i in 0..<obs.contourCount {
    guard let contour = try? obs.contour(at: i) else { continue }
    let simp = (try? contour.polygonApproximation(epsilon: 0.0022)) ?? contour
    let raw = simp.normalizedPoints
    if raw.count < 2 { continue }
    var pts = raw.map { CGPoint(x: Double($0.x), y: 1 - Double($0.y)) }   // → top-left origin
    if let f = pts.first { pts.append(f) }                                // close loop
    var acc = 0.0
    var sx = 0.0, sy = 0.0
    for k in 1..<pts.count { acc += Double(hypot(pts[k].x - pts[k-1].x, pts[k].y - pts[k-1].y)) }
    for p in pts { sx += Double(p.x); sy += Double(p.y) }
    if acc < 0.02 { continue }                                            // drop tiny/noise
    pls.append(PL(pts: pts, len: acc, c: CGPoint(x: sx / Double(pts.count), y: sy / Double(pts.count))))
}

// Keep the longest ~600 contours.
pls.sort { $0.len > $1.len }
pls = Array(pls.prefix(600))

// Order into a pen walk: start top-left, greedily hop to the nearest centroid.
var ordered: [PL] = []
var remaining = pls
if !remaining.isEmpty {
    var idx = remaining.indices.min { remaining[$0].c.x + remaining[$0].c.y < remaining[$1].c.x + remaining[$1].c.y }!
    while !remaining.isEmpty {
        let cur = remaining.remove(at: idx)
        ordered.append(cur)
        if remaining.isEmpty { break }
        idx = remaining.indices.min {
            hypot(remaining[$0].c.x - cur.c.x, remaining[$0].c.y - cur.c.y)
                < hypot(remaining[$1].c.x - cur.c.x, remaining[$1].c.y - cur.c.y)
        }!
    }
}

func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
let paths = ordered.map { pl in pl.pts.map { [r3(Double($0.x)), r3(Double($0.y))] } }
let totalPts = paths.reduce(0) { $0 + $1.count }
let json: [String: Any] = ["paths": paths]
let out = try! JSONSerialization.data(withJSONObject: json, options: [])
let path = "Sources/Lumora/Resources/circuit.json"
try! out.write(to: URL(fileURLWithPath: path))
print("wrote \(path): \(paths.count) paths, \(totalPts) points, \(out.count / 1024) KB")
