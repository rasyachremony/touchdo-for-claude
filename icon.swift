// Draws the TouchDo app icon (a Touch Bar strip with its three buttons) into an .iconset folder.
// Usage: swift icon.swift <dir.iconset>
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // Body on Apple's icon grid: 824/1024 square with a 100/1024 margin.
    let body = NSBezierPath(roundedRect: NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804), xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.24, blue: 0.40, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.13, alpha: 1))!.draw(in: body, angle: -90)
    let strip = NSRect(x: s * 0.16, y: s * 0.40, width: s * 0.68, height: s * 0.20)
    NSColor(white: 0, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: strip, xRadius: s * 0.05, yRadius: s * 0.05).fill()
    let symbols: [(String, NSColor)] = [("checklist", .systemBlue), ("cup.and.saucer.fill", .systemYellow),
                                        ("mic.fill", NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1))]
    for (i, (name, color)) in symbols.enumerated() {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.085, weight: .semibold).applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
        let cell = strip.width / 3
        image.draw(in: NSRect(x: strip.minX + cell * CGFloat(i) + (cell - image.size.width) / 2,
                              y: strip.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
