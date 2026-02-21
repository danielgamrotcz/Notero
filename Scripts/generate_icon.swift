#!/usr/bin/env swift

import AppKit
import CoreGraphics

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "Sources/Resources/Assets.xcassets/AppIcon.appiconset"

let backgroundColor = NSColor(red: 0x0D/255.0, green: 0x0A/255.0, blue: 0x14/255.0, alpha: 1.0)
let foregroundColor = NSColor.white

for size in sizes {
    let cgSize = CGSize(width: size, height: size)
    let image = NSImage(size: cgSize)

    image.lockFocus()

    // Background
    backgroundColor.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: cgSize)).fill()

    // Draw three wavy lines (text/writing symbol)
    let s = CGFloat(size)
    let padding = s * 0.22
    let drawArea = s - 2 * padding

    foregroundColor.setStroke()

    let lineWidth = max(1, s * 0.06)
    let lineLengths: [CGFloat] = [0.8, 0.6, 0.4]  // relative to drawArea
    let yPositions: [CGFloat] = [0.3, 0.5, 0.7]    // relative to drawArea
    let waveAmplitude = s * 0.02

    for i in 0..<3 {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        let lineLen = drawArea * lineLengths[i]
        let startX = padding + (drawArea - lineLen) / 2
        let y = padding + drawArea * yPositions[i]

        path.move(to: NSPoint(x: startX, y: y))

        // Subtle wave
        let segments = 20
        for j in 1...segments {
            let progress = CGFloat(j) / CGFloat(segments)
            let x = startX + lineLen * progress
            let waveY = y + sin(progress * .pi * 2) * waveAmplitude
            path.line(to: NSPoint(x: x, y: waveY))
        }

        path.stroke()
    }

    image.unlockFocus()

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        print("Failed to create image for size \(size)")
        continue
    }

    let filename = "\(outputDir)/icon_\(size).png"
    do {
        try pngData.write(to: URL(fileURLWithPath: filename))
        print("Generated \(filename)")
    } catch {
        print("Error writing \(filename): \(error)")
    }
}

print("Icon generation complete!")
