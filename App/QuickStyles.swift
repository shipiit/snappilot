import SwiftUI
import SnapCore

/// A one-click style recipe applied to the current tool.
struct QuickStyle {
    var color: String
    var lineStyle: LineStyle = .solid
    var filled: Bool = false
    var startHead: ArrowHead = .none
    var endHead: ArrowHead = .none
    var stepStyle: StepStyle = .number
    var thickness: Double? = nil

    static func presets(for tool: Tool) -> [QuickStyle] {
        let red = "#FF3B30", orange = "#FF9500", yellow = "#FFCC00", green = "#34C759"
        let blue = "#007AFF", purple = "#AF52DE", teal = "#22B8CF", pink = "#FF2D55", white = "#FFFFFF"

        switch tool {
        case .arrow, .line:
            return [
                QuickStyle(color: red, endHead: .arrow),
                QuickStyle(color: orange, endHead: .arrow),
                QuickStyle(color: blue, endHead: .arrow),
                QuickStyle(color: yellow, startHead: .arrow, endHead: .arrow),
                QuickStyle(color: green, startHead: .dot, endHead: .arrow),
                QuickStyle(color: purple, startHead: .bar, endHead: .bar),
                QuickStyle(color: red, lineStyle: .dashed),
                QuickStyle(color: blue, lineStyle: .dotted),
                QuickStyle(color: orange, lineStyle: .dashed, endHead: .arrow),
                QuickStyle(color: teal, lineStyle: .dotted, endHead: .arrow),
                QuickStyle(color: pink, lineStyle: .dashed, startHead: .arrow, endHead: .arrow),
                QuickStyle(color: green, startHead: .dot, endHead: .dot),
            ]
        case .rect, .ellipse:
            return [
                QuickStyle(color: red),
                QuickStyle(color: orange),
                QuickStyle(color: blue),
                QuickStyle(color: green, filled: true),
                QuickStyle(color: purple, filled: true),
                QuickStyle(color: red, lineStyle: .dashed),
                QuickStyle(color: blue, lineStyle: .dotted),
                QuickStyle(color: yellow, thickness: 8),
                QuickStyle(color: teal, filled: true),
                QuickStyle(color: white, lineStyle: .dashed),
            ]
        case .step:
            return [
                QuickStyle(color: red, stepStyle: .number),
                QuickStyle(color: orange, stepStyle: .number),
                QuickStyle(color: blue, stepStyle: .number),
                QuickStyle(color: yellow, stepStyle: .number),
                QuickStyle(color: green, stepStyle: .upper),
                QuickStyle(color: purple, stepStyle: .upper),
                QuickStyle(color: teal, stepStyle: .upper),
                QuickStyle(color: white, stepStyle: .upper),
                QuickStyle(color: red, stepStyle: .lower),
                QuickStyle(color: orange, stepStyle: .lower),
                QuickStyle(color: blue, stepStyle: .lower),
                QuickStyle(color: pink, stepStyle: .lower),
            ]
        default:
            return []
        }
    }
}

/// A small preview of a QuickStyle recipe for the given tool.
struct QuickStylePreview: View {
    let style: QuickStyle
    let tool: Tool

    var body: some View {
        Canvas { ctx, size in
            let color = Color(nsColor: nsColor(fromHex: style.color))
            let pad: CGFloat = 8
            switch tool {
            case .arrow, .line:
                let s = CGPoint(x: pad, y: size.height - pad)
                let e = CGPoint(x: size.width - pad, y: pad)
                var p = Path(); p.move(to: s); p.addLine(to: e)
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                              dash: style.lineStyle.dashPattern(width: 2.5).map { CGFloat($0) }))
                head(style.startHead, at: s, from: e, in: ctx, color: color)
                head(style.endHead, at: e, from: s, in: ctx, color: color)
            case .rect:
                let r = CGRect(x: pad, y: pad + 3, width: size.width - pad * 2, height: size.height - pad * 2 - 6)
                if style.filled { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color)) }
                else { ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(color),
                                  style: StrokeStyle(lineWidth: 2.5, dash: style.lineStyle.dashPattern(width: 2.5).map { CGFloat($0) })) }
            case .ellipse:
                let r = CGRect(x: pad, y: pad + 3, width: size.width - pad * 2, height: size.height - pad * 2 - 6)
                if style.filled { ctx.fill(Path(ellipseIn: r), with: .color(color)) }
                else { ctx.stroke(Path(ellipseIn: r), with: .color(color),
                                  style: StrokeStyle(lineWidth: 2.5, dash: style.lineStyle.dashPattern(width: 2.5).map { CGFloat($0) })) }
            case .step:
                let d = min(size.width, size.height) - pad * 2
                let r = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: r), with: .color(color))
                ctx.draw(Text(style.stepStyle.label(for: 1)).font(.system(size: d * 0.55, weight: .bold)).foregroundColor(.white),
                         at: CGPoint(x: r.midX, y: r.midY))
            default: break
            }
        }
    }

    private func head(_ type: ArrowHead, at p: CGPoint, from other: CGPoint, in ctx: GraphicsContext, color: Color) {
        guard type != .none else { return }
        let angle = cg_atan2(p.y - other.y, p.x - other.x)
        switch type {
        case .arrow:
            let len: CGFloat = 8, spread = CGFloat.pi / 7
            var path = Path(); path.move(to: p)
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(angle - spread), y: p.y - len * cg_sin(angle - spread)))
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(angle + spread), y: p.y - len * cg_sin(angle + spread)))
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
        case .dot:
            let r: CGFloat = 3
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        case .bar:
            let len: CGFloat = 5, perp = angle + .pi / 2
            var path = Path()
            path.move(to: CGPoint(x: p.x + len * cg_cos(perp), y: p.y + len * cg_sin(perp)))
            path.addLine(to: CGPoint(x: p.x - len * cg_cos(perp), y: p.y - len * cg_sin(perp)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .none: break
        }
    }
}
