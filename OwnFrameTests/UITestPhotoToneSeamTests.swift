//
//  UITestPhotoToneSeamTests.swift
//  OwnFrameTests
//
//  300 T001 (#72) capture seam: `--uitest-photo-tone=white|black` makes the hermetic stub
//  renderer paint a full-bleed near-white or near-black photo, so the chrome-legibility
//  captures (FR-300-34) run over the worst-case tones. The border and midpoint dot of the
//  default renders would give the chrome a dark/light edge to lean on, so neither may appear.
//

import Testing
import UIKit
@testable import OwnFrame

struct UITestPhotoToneSeamTests {

    @Test func parsesToneFromLaunchArguments() {
        #expect(UITestPhotoTone(arguments: ["--uitest", "--uitest-photo-tone=white"]) == .white)
        #expect(UITestPhotoTone(arguments: ["--uitest-slideshow", "--uitest-photo-tone=black"]) == .black)
    }

    @Test func absentOrUnknownToneKeepsTheDefaultRenders() {
        #expect(UITestPhotoTone(arguments: ["--uitest", "--uitest-slideshow"]) == nil)
        #expect(UITestPhotoTone(arguments: ["--uitest-photo-tone=grey"]) == nil)
    }

    // @covers FR-300-34
    @Test(arguments: [(UITestPhotoTone.white, UInt8(0xF8)), (UITestPhotoTone.black, UInt8(0x08))])
    func rendersFullBleedWithNoBorderOrDot(tone: UITestPhotoTone, expected: UInt8) throws {
        let pixels = try RGBAPixels(pngData: tone.renderPortrait())
        // Corner, where the default render's white border sits (x 20…36), and the midpoint dot.
        let samples = [(2, 2), (28, pixels.height / 2), (pixels.width / 2, pixels.height / 2)]
        for (x, y) in samples {
            let (r, g, b) = pixels.rgb(x: x, y: y)
            #expect(abs(Int(r) - Int(expected)) <= 1, "red at (\(x), \(y))")
            #expect(abs(Int(g) - Int(expected)) <= 1, "green at (\(x), \(y))")
            #expect(abs(Int(b) - Int(expected)) <= 1, "blue at (\(x), \(y))")
        }
    }
}

/// Decodes a PNG into an sRGB RGBA8 buffer at the image's pixel size.
private struct RGBAPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(pngData: Data) throws {
        let image = try #require(UIImage(data: pngData)?.cgImage)
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        try #require(drawn)
        width = w
        height = h
        bytes = buffer
    }

    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
}
