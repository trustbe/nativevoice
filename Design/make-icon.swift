// Draws the app icon and writes AppIcon.icns.
//
// The shape is original on purpose: Apple's SF Symbols licence forbids using
// a symbol, or anything confusingly similar to one, in an app icon. The menu
// bar uses `mic.fill` and that is fine — inside the interface is allowed —
// but the bundle icon has to be drawn.
//
// It is a level meter rather than a microphone. A microphone outline turns to
// mush at 16pt, which is the size this icon is seen at most often: in the
// Input Monitoring and Accessibility lists, where somebody is deciding
// whether to trust it.
//
// Geometry follows the macOS grid: a 1024 canvas with the body in the middle
// 824, corner radius 0.225 of the body.

import AppKit
import Foundation

let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2
let radius = body * 0.225

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    let scale = size / canvas
    context.scaleBy(x: scale, y: scale)

    let rect = CGRect(x: inset, y: inset, width: body, height: body)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil)

    // A drop shadow sized to the body, the way macOS icons sit on a surface.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -body * 0.012),
                      blur: body * 0.05,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    let colours = [
        NSColor(srgbRed: 0.37, green: 0.31, blue: 0.86, alpha: 1).cgColor,
        NSColor(srgbRed: 0.55, green: 0.29, blue: 0.82, alpha: 1).cgColor,
        NSColor(srgbRed: 0.71, green: 0.27, blue: 0.70, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colours, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: [])
    }

    // A soft highlight along the top edge, so the face is not flat.
    if let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.26).cgColor,
                 NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]) {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: [])
    }
    context.restoreGState()

    // Five bars. Symmetric, because this is a mark and not a readout — an
    // asymmetric waveform reads as a screenshot of one particular moment.
    let heights: [CGFloat] = [0.34, 0.64, 1.0, 0.64, 0.34]
    let barWidth = body * 0.082
    let gap = body * 0.052
    let tallest = body * 0.46
    let total = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
    var x = rect.midX - total / 2

    context.setFillColor(NSColor.white.cgColor)
    for factor in heights {
        let height = tallest * factor
        let bar = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(roundedRect: bar,
                               cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                               transform: nil))
        context.fillPath()
        x += barWidth + gap
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let iconset = outputDirectory + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset,
                                         withIntermediateDirectories: true)

let wanted: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

for (pixels, name) in wanted {
    let image = drawIcon(size: CGFloat(pixels))
    guard let data = png(image, pixels) else {
        FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("wrote \(iconset)")
