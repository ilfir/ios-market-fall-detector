// Renders the 1024x1024 app icon: a falling market line on a dark red gradient.
// Usage: swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// Background gradient (top-left lighter red to bottom-right deep red).
let gradient = CGGradient(colorsSpace: space, colors: [color(214, 48, 49), color(110, 14, 26)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

// Faint grid lines.
ctx.setStrokeColor(color(255, 255, 255, 0.10))
ctx.setLineWidth(6)
for y in stride(from: 260, through: 780, by: 130) {
    ctx.move(to: CGPoint(x: 150, y: y))
    ctx.addLine(to: CGPoint(x: 874, y: y))
}
ctx.strokePath()

// Market line: a choppy rise, then a sharp fall (CoreGraphics origin is bottom-left).
let points: [CGPoint] = [
    CGPoint(x: 150, y: 600), CGPoint(x: 260, y: 680), CGPoint(x: 350, y: 640), CGPoint(x: 450, y: 760),
    CGPoint(x: 540, y: 700), CGPoint(x: 640, y: 520), CGPoint(x: 720, y: 560), CGPoint(x: 840, y: 290),
]

// Soft fill under the line.
ctx.saveGState()
ctx.beginPath()
ctx.move(to: CGPoint(x: points[0].x, y: 180))
points.forEach { ctx.addLine(to: $0) }
ctx.addLine(to: CGPoint(x: points.last!.x, y: 180))
ctx.closePath()
ctx.setFillColor(color(255, 255, 255, 0.12))
ctx.fillPath()
ctx.restoreGState()

// The line itself.
ctx.setStrokeColor(color(255, 255, 255))
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.addLines(between: points)
ctx.strokePath()

// Arrow head at the end of the fall.
let end = points.last!
let prev = points[points.count - 2]
let angle = atan2(end.y - prev.y, end.x - prev.x)
let headLength: CGFloat = 120
let spread: CGFloat = .pi / 5.5
ctx.setFillColor(color(255, 255, 255))
ctx.beginPath()
ctx.move(to: CGPoint(x: end.x + cos(angle) * 40, y: end.y + sin(angle) * 40))
ctx.addLine(to: CGPoint(x: end.x - cos(angle - spread) * headLength, y: end.y - sin(angle - spread) * headLength))
ctx.addLine(to: CGPoint(x: end.x - cos(angle + spread) * headLength, y: end.y - sin(angle + spread) * headLength))
ctx.closePath()
ctx.fillPath()

// Alert dot.
ctx.setFillColor(color(255, 214, 10))
ctx.fillEllipse(in: CGRect(x: 760, y: 760, width: 110, height: 110))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
