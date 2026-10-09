//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//
//  Regenerates the app icon PNGs for Mail Inspector/Assets.xcassets/AppIcon.appiconset.
//  Draws the icon procedurally (envelope + magnifying glass) at every required pixel size
//  instead of downsampling a single bitmap, so small sizes stay crisp.
//
//  Usage:
//    swift assets/icon/generate_icon.swift <output-directory>
//    cp <output-directory>/*.png "Mail Inspector/Assets.xcassets/AppIcon.appiconset/"
//

import AppKit

func drawIcon(context ctx: CGContext, size: CGFloat) {
    let s = size / 1024.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    func len(_ v: CGFloat) -> CGFloat { v * s }

    // Background squircle
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = len(185)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    // Base background color #40b5b8, with a subtle lighter/darker gradient for depth.
    let colors = [
        NSColor(calibratedRed: 0.363, green: 0.753, blue: 0.764, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.213, green: 0.603, blue: 0.614, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    // Envelope body
    let envRect = CGRect(x: len(160), y: len(300), width: len(580), height: len(400))
    let envPath = CGPath(roundedRect: envRect, cornerWidth: len(30), cornerHeight: len(30), transform: nil)
    // #fcfcfc
    ctx.setFillColor(NSColor(calibratedWhite: 0.988, alpha: 1).cgColor)
    ctx.addPath(envPath)
    ctx.fillPath()

    // Envelope flap (clipped to the envelope body so it never pokes outside)
    ctx.saveGState()
    ctx.addPath(envPath)
    ctx.clip()
    let flap = CGMutablePath()
    flap.move(to: pt(160, 700))
    flap.addLine(to: pt(450, 510))
    flap.addLine(to: pt(740, 700))
    flap.closeSubpath()
    // #efefef
    ctx.setFillColor(NSColor(calibratedWhite: 0.937, alpha: 1).cgColor)
    ctx.addPath(flap)
    ctx.fillPath()

    // #d6d6d6
    ctx.setStrokeColor(NSColor(calibratedWhite: 0.839, alpha: 1).cgColor)
    ctx.setLineWidth(len(7))
    ctx.setLineJoin(.round)
    let flapLine = CGMutablePath()
    flapLine.move(to: pt(160, 700))
    flapLine.addLine(to: pt(450, 510))
    flapLine.addLine(to: pt(740, 700))
    ctx.addPath(flapLine)
    ctx.strokePath()
    ctx.restoreGState()

    // Magnifying glass, overlapping the envelope's lower-right corner
    let lensCenter = pt(705, 300)
    let lensRadius = len(155)
    // #ec971f
    let amber = NSColor(calibratedRed: 0.925, green: 0.592, blue: 0.122, alpha: 1).cgColor

    ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor)
    ctx.addArc(center: lensCenter, radius: lensRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // Handle, drawn before the ring so the ring's stroke covers the seam cleanly
    let handleAngle = CGFloat.pi * 1.25
    let handleStart = CGPoint(x: lensCenter.x + lensRadius * cos(handleAngle), y: lensCenter.y + lensRadius * sin(handleAngle))
    let handleEnd = CGPoint(x: handleStart.x + len(150) * cos(handleAngle), y: handleStart.y + len(150) * sin(handleAngle))
    ctx.setStrokeColor(amber)
    ctx.setLineWidth(len(58))
    ctx.setLineCap(.round)
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()

    ctx.setStrokeColor(amber)
    ctx.setLineWidth(len(48))
    ctx.addArc(center: lensCenter, radius: lensRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
}

func makeIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    drawIcon(context: nsCtx.cgContext, size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDir = CommandLine.arguments[1]
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let rep = makeIcon(size: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
    try! data.write(to: url)
    print("Wrote \(url.path)")
}
