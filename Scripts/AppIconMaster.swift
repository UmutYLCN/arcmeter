// Composes the 1024 px app icon master: full-bleed black with the logo scaled into the macOS icon safe area.
// The canvas has no corner radius and no transparent padding; macOS applies the icon mask itself.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift AppIconMaster.swift <logo.png> <master.png>\n".utf8))
    exit(2)
}

let canvasSize = 1024
// The gauge ring fills about 82% of the logo, so 820 px places it at roughly two thirds of the canvas.
let logoSize = 820
let logoOrigin = (canvasSize - logoSize) / 2

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("cannot read \(path)")
    }
    return image
}

let logo = loadImage(arguments[1])
guard let context = CGContext(data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("cannot create canvas")
}
context.interpolationQuality = .high

// The logo's own background is near-black, so filling the canvas with black lets the edge of the scaled logo disappear.
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.draw(logo, in: CGRect(x: logoOrigin, y: logoOrigin, width: logoSize, height: logoSize))

guard let master = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("cannot create \(arguments[2])")
}
CGImageDestinationAddImage(destination, master, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("cannot write \(arguments[2])")
}
