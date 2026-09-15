import SMCKit
import SwiftUI

/// Temperature (x) vs fan percent (y). Drag a point to move it, double-click
/// empty space to add one.
struct CurveEditor: View {
  @Binding var points: [CurvePoint]
  var currentTemp: Double?
  var onCommit: () -> Void = {}

  private let tMin = 30.0
  private let tMax = 110.0
  private let inset = EdgeInsets(top: 12, leading: 40, bottom: 26, trailing: 14)
  private let hitRadius: CGFloat = 16
  @State private var dragID: UUID?

  var body: some View {
    GeometryReader { geo in
      let rect = plotRect(geo.size)
      Canvas { ctx, _ in draw(ctx, rect) }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .gesture(
          DragGesture(minimumDistance: 2)
            .onChanged { value in
              if dragID == nil { dragID = nearest(to: value.startLocation, in: rect) }
              guard let id = dragID, let i = points.firstIndex(where: { $0.id == id }) else { return }
              let (t, p) = plotValue(at: value.location, in: rect)
              points[i].celsius = t.rounded()
              points[i].percent = p.rounded()
            }
            .onEnded { _ in
              dragID = nil
              onCommit()
            }
        )
        .onTapGesture(count: 2) { location in
          let (t, p) = plotValue(at: location, in: rect)
          points.append(CurvePoint(celsius: t.rounded(), percent: p.rounded()))
          onCommit()
        }
    }
  }

  // MARK: Geometry

  private func plotRect(_ size: CGSize) -> CGRect {
    CGRect(
      x: inset.leading, y: inset.top,
      width: size.width - inset.leading - inset.trailing,
      height: size.height - inset.top - inset.bottom
    )
  }

  private func x(_ t: Double, _ r: CGRect) -> CGFloat { r.minX + r.width * CGFloat((t - tMin) / (tMax - tMin)) }
  private func y(_ p: Double, _ r: CGRect) -> CGFloat { r.maxY - r.height * CGFloat(p / 100) }

  private func plotValue(at pt: CGPoint, in r: CGRect) -> (Double, Double) {
    let t = tMin + Double((pt.x - r.minX) / r.width) * (tMax - tMin)
    let p = Double((r.maxY - pt.y) / r.height) * 100
    return (min(max(t, tMin), tMax), min(max(p, 0), 100))
  }

  private func distance(_ p: CurvePoint, _ pt: CGPoint, _ r: CGRect) -> CGFloat {
    hypot(x(p.celsius, r) - pt.x, y(p.percent, r) - pt.y)
  }

  private func nearest(to pt: CGPoint, in r: CGRect) -> UUID? {
    guard let p = points.min(by: { distance($0, pt, r) < distance($1, pt, r) }),
          distance(p, pt, r) <= hitRadius else { return nil }
    return p.id
  }

  // MARK: Drawing

  private func draw(_ ctx: GraphicsContext, _ r: CGRect) {
    let grid = Color.gray.opacity(0.2)
    for t in stride(from: tMin, through: tMax, by: 10) {
      let gx = x(t, r)
      var line = Path()
      line.move(to: CGPoint(x: gx, y: r.minY))
      line.addLine(to: CGPoint(x: gx, y: r.maxY))
      ctx.stroke(line, with: .color(grid), lineWidth: 1)
      ctx.draw(Text("\(Int(t))°").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: gx, y: r.maxY + 12))
    }
    for pc in stride(from: 0.0, through: 100, by: 25) {
      let gy = y(pc, r)
      var line = Path()
      line.move(to: CGPoint(x: r.minX, y: gy))
      line.addLine(to: CGPoint(x: r.maxX, y: gy))
      ctx.stroke(line, with: .color(grid), lineWidth: 1)
      ctx.draw(Text("\(Int(pc))%").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: r.minX - 20, y: gy))
    }

    let sorted = points.sorted { $0.celsius < $1.celsius }
    if let first = sorted.first, let last = sorted.last {
      var path = Path()
      path.move(to: CGPoint(x: r.minX, y: y(first.percent, r)))
      for p in sorted { path.addLine(to: CGPoint(x: x(p.celsius, r), y: y(p.percent, r))) }
      path.addLine(to: CGPoint(x: r.maxX, y: y(last.percent, r)))
      var fill = path
      fill.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
      fill.addLine(to: CGPoint(x: r.minX, y: r.maxY))
      fill.closeSubpath()
      ctx.fill(fill, with: .color(.accentColor.opacity(0.12)))
      ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
    }

    if let t = currentTemp, t >= tMin, t <= tMax {
      let gx = x(t, r)
      var marker = Path()
      marker.move(to: CGPoint(x: gx, y: r.minY))
      marker.addLine(to: CGPoint(x: gx, y: r.maxY))
      ctx.stroke(marker, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
      ctx.draw(Text("\(Int(t))°C now").font(.caption2).foregroundStyle(.orange), at: CGPoint(x: gx, y: r.minY - 4))
    }

    for p in points {
      let c = CGPoint(x: x(p.celsius, r), y: y(p.percent, r))
      let dot = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
      ctx.fill(Path(ellipseIn: dot), with: .color(dragID == p.id ? .orange : .accentColor))
      ctx.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1.5)
    }
  }
}
