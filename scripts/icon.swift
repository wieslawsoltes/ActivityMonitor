import AppKit

let directory = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: directory).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let factor = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: factor)
    transform.concat()
    let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
    NSGradient(
      starting: NSColor(calibratedRed: 0.19, green: 0.25, blue: 0.33, alpha: 1),
      ending: NSColor(calibratedRed: 0.07, green: 0.1, blue: 0.16, alpha: 1))!.draw(
        in: shape, angle: 90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    for y in stride(from: 250, through: 800, by: 150) {
      let p = NSBezierPath()
      p.move(to: NSPoint(x: 130, y: y))
      p.line(to: NSPoint(x: 894, y: y))
      p.lineWidth = 3
      p.stroke()
    }
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 145, y: 510))
    for (x, y) in [(300, 510), (370, 665), (485, 285), (605, 780), (700, 510), (875, 510)] {
      wave.line(to: NSPoint(x: x, y: y))
    }
    wave.lineJoinStyle = .round
    wave.lineCapStyle = .round
    wave.lineWidth = 34
    NSColor(calibratedRed: 0.43, green: 0.91, blue: 0.79, alpha: 1).setStroke()
    wave.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale==2 ? "@2x":"").png"))
  }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", directory + "/AppIcon.icns"]
try process.run()
process.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
