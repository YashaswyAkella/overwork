import AppKit

// Usage: swift Tools/MakeIcon.swift out.png
let out = CommandLine.arguments[1]
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let squircle = NSBezierPath(roundedRect: rect.insetBy(dx: 70, dy: 70), xRadius: 210, yRadius: 210)
    NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.09, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    srand48(7)
    for _ in 0..<220 {
        let x = drand48() * size, y = drand48() * size, r = 2 + drand48() * 4
        NSColor.white.withAlphaComponent(CGFloat(0.25 + drand48() * 0.7)).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
    }
    let c = NSPoint(x: size / 2, y: size / 2)
    let glow = NSGradient(colorsAndLocations:
        (NSColor.black, 0.0),
        (NSColor.black, 0.60),
        (NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.8, alpha: 1), 0.63),
        (NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.12, alpha: 1), 0.72),
        (NSColor(calibratedRed: 0.5, green: 0.3, blue: 0.9, alpha: 0.5), 0.88),
        (NSColor.clear, 1.0))!
    glow.draw(fromCenter: c, radius: 0, toCenter: c, radius: 440, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()
    return true
}
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
