#!/usr/bin/env swift
import AppKit
import Foundation

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let radius = size * 0.22
    let bg = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.08, alpha: 1).setFill()
    bg.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    bg.addClip()

    let photo = inset.insetBy(dx: size * 0.12, dy: size * 0.14)
    let photoPath = NSBezierPath(roundedRect: photo, xRadius: size * 0.04, yRadius: size * 0.04)
    let sky = NSGradient(colors: [
        NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.36, green: 0.48, blue: 0.62, alpha: 1),
    ])!
    sky.draw(in: photoPath, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    photoPath.addClip()

    let sunRect = NSRect(
        x: photo.midX + photo.width * 0.12,
        y: photo.midY + photo.height * 0.08,
        width: size * 0.16,
        height: size * 0.16
    )
    NSColor(calibratedRed: 0.98, green: 0.86, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: sunRect).fill()

    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: photo.minX, y: photo.minY + photo.height * 0.38))
    hill.curve(
        to: NSPoint(x: photo.maxX, y: photo.minY + photo.height * 0.28),
        controlPoint1: NSPoint(x: photo.minX + photo.width * 0.35, y: photo.minY + photo.height * 0.62),
        controlPoint2: NSPoint(x: photo.minX + photo.width * 0.7, y: photo.minY + photo.height * 0.08)
    )
    hill.line(to: NSPoint(x: photo.maxX, y: photo.minY))
    hill.line(to: NSPoint(x: photo.minX, y: photo.minY))
    hill.close()
    NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.18, alpha: 1).setFill()
    hill.fill()

    NSGraphicsContext.current?.restoreGraphicsState()

    if size >= 32 {
        cropMarks(around: photo, size: size)
    }

    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedRed: 0.93, green: 0.62, blue: 0.28, alpha: 0.9).setStroke()
    bg.lineWidth = max(1, size * 0.018)
    bg.stroke()

    image.unlockFocus()
    return image
}

func cropMarks(around photo: NSRect, size: CGFloat) {
    let len = size * 0.07
    let width = max(1.4, size * 0.012)
    NSColor(calibratedWhite: 0.96, alpha: 0.92).setStroke()
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (photo.minX, photo.maxY, 1, -1),
        (photo.maxX, photo.maxY, -1, -1),
        (photo.minX, photo.minY, 1, 1),
        (photo.maxX, photo.minY, -1, 1),
    ]
    for (x, y, sx, sy) in corners {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .square
        path.move(to: NSPoint(x: x, y: y + sy * len))
        path.line(to: NSPoint(x: x, y: y))
        path.line(to: NSPoint(x: x + sx * len, y: y))
        path.stroke()
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for item in sizes {
    let img = drawIcon(size: item.px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        fputs("Failed to render \(item.name)\n", stderr)
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(item.name).png"))
    print("Wrote \(item.name).png")
}

let master = drawIcon(size: 1024)
if let tiff = master.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: assets.appendingPathComponent("AppIcon-1024.png"))
}

let icns = assets.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("Created \(icns.path)")
