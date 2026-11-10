// Draws the DMG window background: drag-to-install arrow plus first-launch steps.
// swift Scripts/make-dmg-background.swift <output-dir>   → background.png (1x) and background@2x.png
import AppKit

let W: CGFloat = 600, H: CGFloat = 440
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Finder icon centers (from the window's top-left), shared with build.sh's AppleScript
let appCenter = CGPoint(x: 160, y: 150), appsCenter = CGPoint(x: 440, y: 150)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Flip so y grows downward, matching Finder's icon coordinates
    let t = NSAffineTransform(); t.translateX(by: 0, yBy: H); t.scaleX(by: 1, yBy: -1); t.concat()

    color(0xF4F4F8).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color c: NSColor = color(0x2B2B33), center: Bool = false, width: CGFloat = 0) {
        let p = NSMutableParagraphStyle(); p.alignment = center ? .center : .left; p.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c, .paragraphStyle: p]
        let str = NSAttributedString(string: s, attributes: attrs)
        let w = width > 0 ? width : W
        let h = str.boundingRect(with: NSSize(width: w, height: 400), options: [.usesLineFragmentOrigin]).height
        // Drawing in a flipped context: flip back locally so glyphs aren't upside down
        NSGraphicsContext.saveGraphicsState()
        let f = NSAffineTransform(); f.translateX(by: 0, yBy: y + h); f.scaleX(by: 1, yBy: -1); f.concat()
        str.draw(with: NSRect(x: center ? x - w / 2 : x, y: 0, width: w, height: h), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }

    text("Drag SideLux into Applications", W / 2, 34, size: 17, weight: .semibold, center: true)

    // Arrow between the two icons
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: appCenter.x + 72, y: appCenter.y)); arrow.line(to: NSPoint(x: appsCenter.x - 78, y: appsCenter.y))
    arrow.move(to: NSPoint(x: appsCenter.x - 90, y: appsCenter.y - 11)); arrow.line(to: NSPoint(x: appsCenter.x - 78, y: appsCenter.y))
    arrow.line(to: NSPoint(x: appsCenter.x - 90, y: appsCenter.y + 11))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    color(0x8C8CA8).setStroke(); arrow.stroke()

    // First-launch card
    let card = NSRect(x: 30, y: 250, width: W - 60, height: 160)
    color(0xFFFFFF).setFill(); NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
    color(0xDADAE6).setStroke(); let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12); border.lineWidth = 1; border.stroke()

    text("First launch", card.minX + 22, card.minY + 18, size: 14, weight: .semibold)
    text("SideLux isn't notarized by Apple, so macOS may say it can't verify the app.", card.minX + 22, card.minY + 40,
         size: 12, color: color(0x6B6B78), width: card.width - 44)
    let steps = [
        "Open SideLux. When the warning appears, click Done.",
        "Open System Settings → Privacy & Security and scroll down.",
        "Click Open Anyway next to SideLux, then confirm.",
    ]
    for (i, s) in steps.enumerated() {
        let y = card.minY + 72 + CGFloat(i) * 24
        text("\(i + 1)", card.minX + 22, y, size: 13, weight: .semibold, color: color(0x6A5ACD), width: 14)
        text(s, card.minX + 42, y, size: 13, width: card.width - 64)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(CGFloat(1), "background.png"), (2, "background@2x.png")] {
    let data = render(scale: scale).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("wrote \(outDir)/background.png and background@2x.png")
