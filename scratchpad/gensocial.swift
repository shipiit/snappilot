import AppKit

func hex(_ s: String, _ a: CGFloat = 1) -> NSColor {
    var h = s; if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
    return NSColor(red: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255, blue: CGFloat(v&0xff)/255, alpha: a)
}
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }

func draw(size: NSSize, path: String) {
    let W = size.width, H = size.height, s = W / 1600.0
    let img = NSImage(size: size); img.lockFocus()

    hex("#0E1017").setFill(); NSRect(origin: .zero, size: size).fill()
    hex("#5661F6", 0.18).setFill()
    rrect(NSRect(x: W*0.58, y: -H*0.35, width: W*0.75, height: H*1.0), 500*s).fill()

    // ----- Right: mini task-board mock -----
    let boardW = W*0.34, boardH = H*0.62
    let boardX = W - boardW - 90*s, boardY = (H - boardH)/2
    let board = NSRect(x: boardX, y: boardY, width: boardW, height: boardH)
    hex("#171A22").setFill(); rrect(board, 22*s).fill()
    hex("#FFFFFF", 0.08).setStroke(); let bb = rrect(board, 22*s); bb.lineWidth = 1.5*s; bb.stroke()
    // window dots
    for (i, c) in ["#E5484D", "#E2A03F", "#3FB950"].enumerated() {
        hex(c).setFill(); NSBezierPath(ovalIn: NSRect(x: boardX + 22*s + CGFloat(i)*26*s, y: board.maxY - 34*s, width: 14*s, height: 14*s)).fill()
    }
    // 4 columns
    let colColors = ["#8A8F98", "#5661F6", "#D177E0", "#3FB950"]
    let pad = 22*s, top = board.maxY - 60*s
    let colW = (boardW - pad*2 - 3*14*s) / 4
    for i in 0..<4 {
        let colX = boardX + pad + CGFloat(i)*(colW + 14*s)
        hex(colColors[i]).setFill()
        NSBezierPath(ovalIn: NSRect(x: colX, y: top, width: 11*s, height: 11*s)).fill()
        let cards = [3, 2, 2, 3][i]
        for j in 0..<cards {
            let cy = top - 34*s - CGFloat(j)*54*s
            hex("#FFFFFF", 0.06).setFill(); rrect(NSRect(x: colX, y: cy - 40*s, width: colW, height: 44*s), 8*s).fill()
            hex(colColors[i], 0.7).setFill(); rrect(NSRect(x: colX + 8*s, y: cy - 14*s, width: colW*0.5, height: 8*s), 4*s).fill()
        }
    }

    // ----- Left: brand block (vertically centered) -----
    let cx = 110 * s
    var y = H*0.72

    let iconSize = 116 * s
    let iconRect = NSRect(x: cx, y: y, width: iconSize, height: iconSize)
    hex("#5661F6").setFill(); rrect(iconRect, 28*s).fill()
    NSColor.white.setStroke()
    let inset = iconRect.insetBy(dx: 26*s, dy: 26*s); let L = inset.width * 0.34
    let bp = NSBezierPath(); bp.lineWidth = 7*s; bp.lineCapStyle = .round
    func corner(_ p: NSPoint, _ dx: CGFloat, _ dy: CGFloat) { bp.move(to: NSPoint(x: p.x + dx*L, y: p.y)); bp.line(to: p); bp.line(to: NSPoint(x: p.x, y: p.y + dy*L)) }
    corner(NSPoint(x: inset.minX, y: inset.maxY), 1, -1); corner(NSPoint(x: inset.maxX, y: inset.maxY), -1, -1)
    corner(NSPoint(x: inset.minX, y: inset.minY), 1, 1); corner(NSPoint(x: inset.maxX, y: inset.minY), -1, 1)
    bp.stroke()
    let ar = NSBezierPath(); ar.lineWidth = 8*s; ar.lineCapStyle = .round; ar.lineJoinStyle = .round
    let c = NSPoint(x: inset.midX, y: inset.midY)
    ar.move(to: NSPoint(x: c.x - 15*s, y: c.y + 15*s)); ar.line(to: NSPoint(x: c.x + 15*s, y: c.y - 15*s))
    ar.line(to: NSPoint(x: c.x + 1*s, y: c.y - 15*s)); ar.move(to: NSPoint(x: c.x + 15*s, y: c.y - 15*s)); ar.line(to: NSPoint(x: c.x + 15*s, y: c.y - 1*s)); ar.stroke()

    y -= 40*s
    NSAttributedString(string: "Snappilot", attributes: [.font: NSFont.systemFont(ofSize: 96*s, weight: .bold), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: cx, y: y - 96*s))
    y -= 150*s
    NSAttributedString(string: "Capture · Record · Meeting AI · Tasks · Notes", attributes: [.font: NSFont.systemFont(ofSize: 33*s, weight: .medium), .foregroundColor: hex("#AAB2C5")]).draw(at: NSPoint(x: cx, y: y))

    // pills (two rows)
    y -= 90*s
    let pills = ["📸 Capture", "🎥 Record", "🧠 Meeting AI", "✅ Tasks", "📓 Notes"]
    var px = cx
    for p in pills {
        let at = NSAttributedString(string: p, attributes: [.font: NSFont.systemFont(ofSize: 28*s, weight: .semibold), .foregroundColor: NSColor.white])
        let tw = at.size().width, padx = 24*s
        let rect = NSRect(x: px, y: y - 12*s, width: tw + padx*2, height: 58*s)
        hex("#FFFFFF", 0.08).setFill(); rrect(rect, 29*s).fill()
        hex("#5661F6", 0.5).setStroke(); let bpp = rrect(rect, 29*s); bpp.lineWidth = 1.5*s; bpp.stroke()
        at.draw(at: NSPoint(x: px + padx, y: y + 3*s))
        px += tw + padx*2 + 16*s
        if px > boardX - 120*s { px = cx; y -= 76*s }
    }

    y -= 96*s
    NSAttributedString(string: "Free · Open source · 100% on-device", attributes: [.font: NSFont.systemFont(ofSize: 30*s, weight: .bold), .foregroundColor: hex("#5661F6")]).draw(at: NSPoint(x: cx, y: y))
    NSAttributedString(string: "github.com/shipiit/snappilot", attributes: [.font: NSFont.systemFont(ofSize: 28*s, weight: .semibold), .foregroundColor: hex("#7C86A0")]).draw(at: NSPoint(x: cx, y: y - 46*s))

    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path)); print("wrote", path)
    }
}

let dir = "/Users/rahulraj/Documents/snappilot/social"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
draw(size: NSSize(width: 1600, height: 900), path: dir + "/peerlist-1600x900.png")
draw(size: NSSize(width: 1600, height: 900), path: dir + "/twitter-1600x900.png")
draw(size: NSSize(width: 1200, height: 627), path: dir + "/linkedin-1200x627.png")
