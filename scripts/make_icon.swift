// Draws the Curv app icon and writes Resources/Curv.icns.
// Run: swift scripts/make_icon.swift
import AppKit

func render(_ size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  let s = size
  let rect = NSRect(x: 0, y: 0, width: s, height: s)
  let radius = s * 0.225
  let bg = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02), xRadius: radius, yRadius: radius)
  NSGradient(colors: [NSColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1), NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)])!
    .draw(in: bg, angle: -90)

  // grid
  NSColor.white.withAlphaComponent(0.07).setStroke()
  for i in 1..<4 {
    let g = NSBezierPath(); g.lineWidth = s * 0.008
    g.move(to: NSPoint(x: s * 0.12, y: s * 0.12 + s * 0.76 * CGFloat(i) / 4)); g.line(to: NSPoint(x: s * 0.88, y: s * 0.12 + s * 0.76 * CGFloat(i) / 4)); g.stroke()
    g.removeAllPoints()
    g.move(to: NSPoint(x: s * 0.12 + s * 0.76 * CGFloat(i) / 4, y: s * 0.12)); g.line(to: NSPoint(x: s * 0.12 + s * 0.76 * CGFloat(i) / 4, y: s * 0.88)); g.stroke()
  }

  let pts = [NSPoint(x: s * 0.16, y: s * 0.24), NSPoint(x: s * 0.40, y: s * 0.40), NSPoint(x: s * 0.62, y: s * 0.64), NSPoint(x: s * 0.84, y: s * 0.80)]
  let accent = NSColor(red: 0.37, green: 0.66, blue: 1.0, alpha: 1)

  // fill under the curve
  let fill = NSBezierPath(); fill.move(to: NSPoint(x: pts[0].x, y: s * 0.12))
  pts.forEach { fill.line(to: $0) }; fill.line(to: NSPoint(x: pts.last!.x, y: s * 0.12)); fill.close()
  accent.withAlphaComponent(0.16).setFill(); fill.fill()

  // glow + line
  let line = NSBezierPath(); line.move(to: pts[0]); pts.dropFirst().forEach { line.line(to: $0) }
  line.lineCapStyle = .round; line.lineJoinStyle = .round
  accent.withAlphaComponent(0.35).setStroke(); line.lineWidth = s * 0.11; line.stroke()
  accent.setStroke(); line.lineWidth = s * 0.055; line.stroke()

  for p in pts.dropFirst().dropLast() {
    let r = s * 0.055
    let dot = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    accent.setFill(); dot.fill()
    NSColor.white.setStroke(); dot.lineWidth = s * 0.018; dot.stroke()
  }
  image.unlockFocus()
  return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.first!).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("Resources/Curv.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = base * scale
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try png(render(CGFloat(px)), px).write(to: iconset.appendingPathComponent(name))
  }
}
let task = Process(); task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/Curv.icns").path]
task.launch(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote Resources/Curv.icns" : "iconutil failed")
