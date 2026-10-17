// Composes the 1024 px app icon master: the logo clipped to a squircle tile on the macOS icon grid
// (824 px tile centered on a 1024 px transparent canvas), so the Dock shows it at the same size as other icons.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift AppIconMaster.swift <logo.png> <master.png>\n".utf8))
    exit(2)
}

let canvasSize = 1024
let tileSize = 824
let tileOrigin = (canvasSize - tileSize) / 2
let superellipseExponent = 5.0

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("cannot read \(path)")
    }
    return image
}

// Apple's icon grid uses a continuous-corner squircle; a superellipse with exponent 5 is a close approximation.
func squirclePath(origin: Double, size: Double) -> CGPath {
    let radius = size / 2
    let center = origin + radius
    let path = CGMutablePath()
    let steps = 720
    for step in 0..<steps {
        let angle = 2 * Double.pi * Double(step) / Double(steps)
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = center + radius * copysign(pow(abs(cosine), 2 / superellipseExponent), cosine)
        let y = center + radius * copysign(pow(abs(sine), 2 / superellipseExponent), sine)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

let logo = loadImage(arguments[1])
guard let context = CGContext(data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("cannot create canvas")
}
context.interpolationQuality = .high

let tilePath = squirclePath(origin: Double(tileOrigin), size: Double(tileSize))
let tileRect = CGRect(x: tileOrigin, y: tileOrigin, width: tileSize, height: tileSize)

context.saveGState()
context.addPath(tilePath)
context.clip()
context.draw(logo, in: tileRect)
context.restoreGState()

// A faint hairline keeps the black tile's edge visible against dark Dock backgrounds.
context.addPath(tilePath)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
context.setLineWidth(2)
context.strokePath()

guard let master = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("cannot create \(arguments[2])")
}
CGImageDestinationAddImage(destination, master, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("cannot write \(arguments[2])")
}
