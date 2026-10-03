import AppKit
import Foundation

// A sphere of separated latitude rings. Render to an explicit bitmap so every
// iconset member has its stated pixel dimensions, regardless of display scale.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    let s = CGFloat(pixels)
    let tile = NSBezierPath(roundedRect: NSRect(x: s * 0.065, y: s * 0.065, width: s * 0.87, height: s * 0.87), xRadius: s * 0.195, yRadius: s * 0.195)
    NSGradient(starting: NSColor(calibratedWhite: 0.075, alpha: 1), ending: NSColor(calibratedWhite: 0.155, alpha: 1))!.draw(in: tile, angle: 90)

    let radius = s * 0.315
    let tilt: CGFloat = 0.10
    // Fewer rings at the smallest size preserve the spaces between them.
    let latitudes: [CGFloat] = pixels <= 32 ? [-0.84, -0.42, 0, 0.42, 0.84] : [-0.90, -0.60, -0.30, 0, 0.30, 0.60, 0.90]
    let width = max(s * 0.0105, 0.7)
    func point(_ latitude: CGFloat, _ angle: CGFloat) -> NSPoint {
        let r = radius * sqrt(1 - latitude * latitude)
        return NSPoint(x: s * 0.5 + r * cos(angle), y: s * 0.5 + radius * latitude * sqrt(1 - tilt * tilt) + r * tilt * sin(angle))
    }
    // Rear arcs sit behind the front arcs. The gentle silver lighting gives the
    // rings depth while their silhouette stays crisp at Dock and Finder sizes.
    for front in [false, true] {
        for latitude in latitudes.reversed() {
            let count = 120
            for segment in 0..<count {
                let start = CGFloat(segment) / CGFloat(count) * .pi + (front ? .pi : 0)
                let end = CGFloat(segment + 1) / CGFloat(count) * .pi + (front ? .pi : 0)
                let path = NSBezierPath()
                path.move(to: point(latitude, start))
                path.line(to: point(latitude, end))
                path.lineWidth = width
                path.lineCapStyle = .round
                let angle = (start + end) / 2
                let tone = 0.72 - 0.23 * sin(angle) + 0.02 * cos(angle)
                NSColor(calibratedWhite: tone, alpha: 1).setStroke()
                path.stroke()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(pixels: size * scale).write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
