// make-test-photo.swift — writes a 3000×2000 JPEG of one flat colour with a faint label, for the
// Immich device-test album (immich-test-album.sh) and the runner-side arrival upload.
//
//   swift make-test-photo.swift <out.jpg> <hex rrggbb> <label>
//
// Flat near-white / near-black frames are the #72/#60 glass stress cases; the label keeps
// every file's checksum unique, so Immich never dedupes an upload away.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let rgb = UInt32(args[2], radix: 16) else {
    FileHandle.standardError.write(Data("usage: make-test-photo.swift <out.jpg> <rrggbb> <label>\n".utf8))
    exit(2)
}
let (w, h) = (3000, 2000)
let r = CGFloat((rgb >> 16) & 0xFF) / 255, g = CGFloat((rgb >> 8) & 0xFF) / 255, b = CGFloat(rgb & 0xFF) / 255
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

// Label in a slightly contrasting tone, bottom left — readable in a screenshot, not a hero.
let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
let ink: CGFloat = luminance > 0.5 ? 0.55 : 0.45
let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
let text = NSAttributedString(string: args[3], attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: ink, alpha: 1),
])
ctx.textPosition = CGPoint(x: 80, y: 80)
CTLineDraw(CTLineCreateWithAttributedString(text), ctx)

let url = URL(fileURLWithPath: args[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { exit(1) }
