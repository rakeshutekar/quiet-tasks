import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap")
    }

    representation.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let radius = size * 0.22
    let body = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.055, dy: size * 0.055), xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.13, alpha: 1).setFill()
    body.fill()

    let top = NSBezierPath(roundedRect: NSRect(x: size * 0.055, y: size * 0.69, width: size * 0.89, height: size * 0.255), xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.46, alpha: 1).setFill()
    top.fill()

    NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.88, alpha: 1).setStroke()
    let lineWidth = max(1.5, size * 0.035)
    for index in 0..<3 {
        let y = size * (0.56 - CGFloat(index) * 0.15)
        let box = NSBezierPath(roundedRect: NSRect(x: size * 0.19, y: y - size * 0.028, width: size * 0.065, height: size * 0.065), xRadius: size * 0.015, yRadius: size * 0.015)
        box.lineWidth = lineWidth
        box.stroke()

        let line = NSBezierPath()
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: size * 0.31, y: y))
        line.line(to: NSPoint(x: size * 0.78, y: y))
        line.stroke()
    }

    let mark = NSBezierPath()
    mark.lineWidth = max(1.4, size * 0.03)
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: size * 0.32, y: size * 0.80))
    mark.line(to: NSPoint(x: size * 0.41, y: size * 0.75))
    mark.line(to: NSPoint(x: size * 0.58, y: size * 0.88))
    mark.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode png")
    }
    return png
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for (filename, size) in sizes {
    let png = drawIcon(size: size)
    try png.write(to: output.appendingPathComponent(filename))
}
