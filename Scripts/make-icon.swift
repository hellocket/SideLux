// SideLux app icon generator: swift Scripts/make-icon.swift <output.png>  (or ./build.sh icon)
// Half sun: one half glows warm, the other is translucent glass (Liquid Glass style)
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/icon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ext: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext

// macOS icon grid: an 824pt body inside the 1024pt canvas
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
let c = CGPoint(x: 512, y: 512)

// 1) Body shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.28))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x252244)); ctx.fillPath()
ctx.restoreGState()

// 2) Background: muted indigo gradient
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x8092DA), rgb(0x524C93), rgb(0x252244)], [0, 0.5, 1]),
                       start: CGPoint(x: 260, y: 924), end: CGPoint(x: 760, y: 100), options: ext)
// Warm glow spreading from the bright half
ctx.drawRadialGradient(gradient([rgb(0xFFB35C, 0.45), rgb(0xFF8A3D, 0.0)]),
                       startCenter: CGPoint(x: 380, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 380, y: 512), endRadius: 340, options: [])
ctx.restoreGState()

// Scale the whole sun (rays + disc) slightly around the center; shape unchanged
let sunScale: CGFloat = 0.88
ctx.saveGState()
ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: sunScale, y: sunScale); ctx.translateBy(x: -c.x, y: -c.y)

// 3) Rays (left = glowing, right = glass)
let rayInner: CGFloat = 238, rayOuter: CGFloat = 300, rayWidth: CGFloat = 46
func ray(_ deg: CGFloat) -> CGPath {
    let a = deg * .pi / 180
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x + cos(a) * rayInner, y: c.y + sin(a) * rayInner))
    p.addLine(to: CGPoint(x: c.x + cos(a) * rayOuter, y: c.y + sin(a) * rayOuter))
    return p.copy(strokingWithWidth: rayWidth, lineCap: .round, lineJoin: .round, miterLimit: 1)
}
func glass(_ path: CGPath, bounds: CGRect) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.42), rgb(0xFFFFFF, 0.12)]),
                           start: CGPoint(x: bounds.minX, y: bounds.maxY), end: CGPoint(x: bounds.maxX, y: bounds.minY), options: ext)
    ctx.restoreGState()
}
func warm(_ path: CGPath, top: CGFloat, bottom: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFE9A8), rgb(0xFFB547), rgb(0xFF8642)], [0, 0.5, 1]),
                           start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: ext)
    ctx.restoreGState()
}
let warmRays: [CGFloat] = [90, 135, 180, 225, 270], glassRays: [CGFloat] = [45, 0, 315]
// Glow behind the bright rays
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: rgb(0xFFA94D, 0.75))
for d in warmRays { ctx.addPath(ray(d)) }
ctx.setFillColor(rgb(0xFFB547)); ctx.fillPath()
ctx.restoreGState()
for d in warmRays { warm(ray(d), top: c.y + rayOuter, bottom: c.y - rayOuter) }
for d in glassRays { glass(ray(d), bounds: ray(d).boundingBox) }

// 4) Sun disc
let r: CGFloat = 178
let disc = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
let leftHalf = CGMutablePath()
leftHalf.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: .pi * 1.5, clockwise: false)
leftHalf.closeSubpath()
let rightHalf = CGMutablePath()
rightHalf.addArc(center: c, radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
rightHalf.closeSubpath()

// Right half: translucent glass (no outline) with a hint of depth
ctx.saveGState()
ctx.addPath(rightHalf); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xE8EEFF, 0.40), rgb(0xC9D4FF, 0.14)]),
                       start: CGPoint(x: c.x, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: ext)
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.0), rgb(0xFFFFFF, 0.16)]),
                       startCenter: c, startRadius: r * 0.55, endCenter: c, endRadius: r, options: [])
ctx.restoreGState()

// Left half: glowing
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0xFF9A3C, 0.85))
ctx.addPath(leftHalf); ctx.setFillColor(rgb(0xFFB547)); ctx.fillPath()
ctx.restoreGState()
warm(leftHalf, top: disc.maxY, bottom: disc.minY)

// 5) Glass highlight across the disc (light from the top left)
ctx.saveGState()
ctx.addEllipse(in: disc); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.0)]),
                       startCenter: CGPoint(x: c.x - 0.39 * r, y: c.y + 0.53 * r), startRadius: 0,
                       endCenter: CGPoint(x: c.x - 0.39 * r, y: c.y + 0.53 * r), endRadius: 0.84 * r, options: [])
ctx.restoreGState()

ctx.restoreGState()   // end of sun scaling

// 6) Glass rim on the body (bright at the top, fading downward)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setLineWidth(4)
ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0.18)], [0, 0.6, 1]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: ext)
ctx.restoreGState()
// Soft glass highlight at the top
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.0)]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.maxY - 300), options: [])
ctx.restoreGState()

ctx.flush()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
