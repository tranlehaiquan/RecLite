#!/usr/bin/env swift
// Renders the RecLite app icon (1024×1024, transparent background) using CoreGraphics.
// Usage: swift scripts/generate_icon.swift <output.png>
// Layout follows Apple's macOS icon grid: 824pt squircle centered on a 1024pt canvas.

import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Continuous-corner rounded rect (approximates Apple's squircle better than circular corners)
func squirclePath(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k: CGFloat = 1.28 // extends the curve along each edge for a smoother, squircle-like corner
    let e = min(r * k, min(rect.width, rect.height) / 2)
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + e, y: maxY))
    path.addLine(to: CGPoint(x: maxX - e, y: maxY))
    path.addCurve(to: CGPoint(x: maxX, y: maxY - e), control1: CGPoint(x: maxX - e * 0.25, y: maxY), control2: CGPoint(x: maxX, y: maxY - e * 0.25))
    path.addLine(to: CGPoint(x: maxX, y: minY + e))
    path.addCurve(to: CGPoint(x: maxX - e, y: minY), control1: CGPoint(x: maxX, y: minY + e * 0.25), control2: CGPoint(x: maxX - e * 0.25, y: minY))
    path.addLine(to: CGPoint(x: minX + e, y: minY))
    path.addCurve(to: CGPoint(x: minX, y: minY + e), control1: CGPoint(x: minX + e * 0.25, y: minY), control2: CGPoint(x: minX, y: minY + e * 0.25))
    path.addLine(to: CGPoint(x: minX, y: maxY - e))
    path.addCurve(to: CGPoint(x: minX + e, y: maxY), control1: CGPoint(x: minX, y: maxY - e * 0.25), control2: CGPoint(x: minX + e * 0.25, y: maxY))
    path.closeSubpath()
    return path
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create context") }

// MARK: - Squircle base

let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let iconPath = squirclePath(iconRect, radius: 185)

// Soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.28))
ctx.addPath(iconPath)
ctx.setFillColor(color(0xF2F2F4))
ctx.fillPath()
ctx.restoreGState()

// Off-white → light gray surface
ctx.saveGState()
ctx.addPath(iconPath)
ctx.clip()
let surface = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF), color(0xF3F3F5), color(0xDEDEE2)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(surface, start: CGPoint(x: 0, y: iconRect.maxY), end: CGPoint(x: 0, y: iconRect.minY), options: [])

// Gentle inner shadow along the bottom edge for depth
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: color(0x000000, 0.12))
ctx.addRect(iconRect.insetBy(dx: -60, dy: -60))
ctx.addPath(squirclePath(iconRect.insetBy(dx: 2, dy: 2), radius: 183))
ctx.setFillColor(color(0x000000))
ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

// Bevel: bright glassy highlight on top, darker rim on the outside
ctx.saveGState()
ctx.addPath(iconPath)
ctx.clip()
ctx.addPath(squirclePath(iconRect.insetBy(dx: 6, dy: 6), radius: 179))
ctx.setLineWidth(8)
ctx.replacePathWithStrokedPath()
ctx.clip()
let bevel = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF, 1.0), color(0xFFFFFF, 0.25), color(0xC8C8CE, 0.6)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bevel, start: CGPoint(x: 0, y: iconRect.maxY), end: CGPoint(x: 0, y: iconRect.minY), options: [])
ctx.restoreGState()

ctx.addPath(iconPath)
ctx.setStrokeColor(color(0x8E8E93, 0.35))
ctx.setLineWidth(2)
ctx.strokePath()

// MARK: - Monitor glyph

let charcoal = color(0x3A3A3D)
let cx = size / 2
let strokeWidth: CGFloat = 34
let screenSize = CGSize(width: 460, height: 310)
let standGap: CGFloat = 64
let standHeight: CGFloat = 34
// Vertically center the whole glyph (screen + gap + stand) in the icon
let glyphHeight = screenSize.height + strokeWidth / 2 + standGap + standHeight
let glyphBottom = size / 2 - glyphHeight / 2
let screenRect = CGRect(x: cx - screenSize.width / 2, y: glyphBottom + standHeight + standGap + strokeWidth / 2, width: screenSize.width, height: screenSize.height)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: color(0x000000, 0.18))
ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: 42, cornerHeight: 42, transform: nil))
ctx.setStrokeColor(charcoal)
ctx.setLineWidth(strokeWidth)
ctx.strokePath()

// Stand: short rounded horizontal bar
let standRect = CGRect(x: cx - 95, y: glyphBottom, width: 190, height: standHeight)
ctx.addPath(CGPath(roundedRect: standRect, cornerWidth: standHeight / 2, cornerHeight: standHeight / 2, transform: nil))
ctx.setFillColor(charcoal)
ctx.fillPath()
ctx.restoreGState()

// MARK: - Glossy red record dot

let dotRadius: CGFloat = 70
let dotCenter = CGPoint(x: screenRect.midX, y: screenRect.midY)
let dotRect = CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: color(0xA0140E, 0.25))
ctx.addEllipse(in: dotRect)
ctx.setFillColor(color(0xE0342A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: dotRect)
ctx.clip()
let red = CGGradient(colorsSpace: colorSpace, colors: [color(0xF0473C), color(0xD9342A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(red, start: CGPoint(x: 0, y: dotRect.maxY), end: CGPoint(x: 0, y: dotRect.minY), options: [])
// Soft gloss across the top half
let gloss = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
let glossRect = CGRect(x: dotRect.minX + 18, y: dotCenter.y + 4, width: dotRect.width - 36, height: dotRadius - 10)
ctx.addEllipse(in: glossRect)
ctx.clip()
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: glossRect.maxY), end: CGPoint(x: 0, y: glossRect.minY), options: [])
ctx.restoreGState()

// MARK: - Export

guard let image = ctx.makeImage() else { fatalError("Render failed") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
