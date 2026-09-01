#!/usr/bin/env swift
//
// make-qr.swift — generate a QR code PNG with CoreImage. No third-party dependency.
//
// Why this exists: nothing in the app produces a QR code, it only scans one
// (OwnFrame/Onboarding/QRScannerView.swift is decode-only). AP-5
// (docs/presentation-overhaul-plan.md, FR-9010-26) needs a QR that links an App Store
// composite to the demo shared album. FR-9010-26 names Swift + CoreImage's
// CIQRCodeGenerator as the sanctioned tool for this — it ships with the OS, so it does
// not violate the repo-wide "no third-party dependency" constraint the way a brew/pip/SPM
// QR library would.
//
// Three load-bearing choices, all driven by the fact that the code is meant to be
// composited onto a dark scene photograph (the app's design language is always-dark,
// `9000` FR-9000-05) and then re-photographed off a screen by a phone camera — a pipeline
// that loses sharpness and contrast twice, on a low-contrast ground, before a scanner ever
// sees it:
//
//   - Error-correction level "H" (~30% of the code words recoverable) is the default and
//     the highest level CIQRCodeGenerator offers. Lower levels (L/M/Q) pack more data per
//     module but leave less margin for the glare, blur, and moire that a screen-photograph
//     of a print introduces. --correction-level exists only to allow deliberately
//     downgrading it for a size-vs-robustness experiment; H is what ships.
//   - A 4-module quiet zone, padded onto the native bitmap before upscaling.
//     CIQRCodeGenerator emits the symbol only, with no margin — a single module of border
//     at most. The QR spec requires 4 modules of quiet zone, and skimping on it is exactly
//     the failure this asset cannot afford: composited onto a dark photograph, a 1-module
//     margin gives a scanner almost nothing to lock the three finder patterns onto, and
//     that gap only shows up once someone points a phone at a physical screen — the
//     scenario SC-9010-07 exists to catch, discovered too late to fix cheaply.
//     --quiet-zone exists so the margin can be widened or (for isolated testing only)
//     dropped without hand-editing the bitmap logic.
//   - Nearest-neighbour upscaling. CIQRCodeGenerator emits exactly one pixel per module
//     (a 39-character URL renders to well under 40x40 pixels). Naively scaling that up
//     with CIImage's default sampler interpolates between modules and blurs the crisp
//     module edges a scanner locks onto. This script instead draws the native-resolution,
//     already-quiet-zone-padded bitmap into a larger CGContext with
//     interpolationQuality = .none and antialiasing off, which replicates each module's
//     pixels rather than blending them — the modules (and the padding) stay hard-edged,
//     and the margin stays an exact whole number of modules, at any --min-size. Padding
//     before the upscale rather than after is what keeps it exact.
//
// Usage:
//   swift .claude/scripts/make-qr.swift [--url URL] [--out PATH] [--min-size PIXELS]
//                                       [--correction-level L|M|Q|H] [--quiet-zone MODULES]
//
// Defaults reproduce the AP-5 deliverable:
//   --url https://bilder.kippings.de/s/Iceland2021
//   --out Design/AppStore/qr/iceland.png   (resolved against the repo root when relative)
//   --min-size 1200                        (native asset resolution; the composite
//                                            renderer downsamples from here, which is
//                                            safe — upsampling a finished QR later would
//                                            not be)
//   --correction-level H
//   --quiet-zone 4                         (the QR spec's minimum; see above)
//
// Exit codes:
//   0  PNG written
//   1  bad arguments (unknown flag, missing value, bad --correction-level)
//   2  QR generation failed (CIQRCodeGenerator produced no output, e.g. message too long
//      for the QR symbol capacity at the requested correction level)
//   3  could not encode or write the PNG to disk
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Repo root

// Mirrors the Python scripts' `ROOT = Path(__file__).resolve().parents[2]`
// (.claude/scripts/<file> -> .claude/scripts -> .claude -> repo root), so a relative
// --out behaves the same regardless of the caller's working directory.
func repoRoot() -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: cwd)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    return scriptURL
        .deletingLastPathComponent()  // .claude/scripts
        .deletingLastPathComponent()  // .claude
        .deletingLastPathComponent()  // repo root
}

// MARK: - Argument parsing (argparse-equivalent: no ArgumentParser — that is itself a
// third-party SPM package, and a single-file `swift script.swift` script cannot declare
// package dependencies anyway).

let usage = """
Generate a QR code PNG with CoreImage's CIQRCodeGenerator. No third-party dependency.

Usage:
  swift .claude/scripts/make-qr.swift [--url URL] [--out PATH] [--min-size PIXELS]
                                      [--correction-level L|M|Q|H] [--quiet-zone MODULES]

  --url URL                 text to encode (default: https://bilder.kippings.de/s/Iceland2021)
  --out PATH                output PNG path, relative to the repo root unless it starts
                             with "/" (default: Design/AppStore/qr/iceland.png)
  --min-size PIXELS          minimum output edge length before integer nearest-neighbour
                             upscaling (default: 1200)
  --correction-level L|M|Q|H  QR error-correction level (default: H, the highest CoreImage
                             offers)
  --quiet-zone MODULES       white border padded on all four sides, in modules, before the
                             upscale (default: 4, the QR spec minimum; see header comment)
  -h, --help                 print this message

Exit codes: 0 written · 1 bad arguments · 2 QR generation failed · 3 could not write PNG
"""

struct Options {
    var url = "https://bilder.kippings.de/s/Iceland2021"
    var out = "Design/AppStore/qr/iceland.png"
    var minSize = 1200
    var correctionLevel = "H"
    var quietZone = 4
}

func parseArgs(_ args: [String]) -> Options {
    var opts = Options()
    var i = 0
    func nextValue(for flag: String) -> String {
        i += 1
        guard i < args.count else {
            FileHandle.standardError.write("error: \(flag) requires a value\n".data(using: .utf8)!)
            exit(1)
        }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "-h", "--help":
            print(usage)
            exit(0)
        case "--url":
            opts.url = nextValue(for: "--url")
        case "--out":
            opts.out = nextValue(for: "--out")
        case "--min-size":
            let raw = nextValue(for: "--min-size")
            guard let n = Int(raw), n > 0 else {
                FileHandle.standardError.write("error: --min-size must be a positive integer, got \"\(raw)\"\n".data(using: .utf8)!)
                exit(1)
            }
            opts.minSize = n
        case "--correction-level":
            let raw = nextValue(for: "--correction-level").uppercased()
            guard ["L", "M", "Q", "H"].contains(raw) else {
                FileHandle.standardError.write("error: --correction-level must be one of L, M, Q, H, got \"\(raw)\"\n".data(using: .utf8)!)
                exit(1)
            }
            opts.correctionLevel = raw
        case "--quiet-zone":
            let raw = nextValue(for: "--quiet-zone")
            guard let n = Int(raw), n >= 0 else {
                FileHandle.standardError.write("error: --quiet-zone must be a non-negative integer, got \"\(raw)\"\n".data(using: .utf8)!)
                exit(1)
            }
            opts.quietZone = n
        default:
            FileHandle.standardError.write("error: unknown argument \"\(args[i])\"\n\n\(usage)\n".data(using: .utf8)!)
            exit(1)
        }
        i += 1
    }
    return opts
}

// MARK: - QR generation

/// Renders `message` at native module resolution (one pixel per module, 8-bit grayscale,
/// no alpha) via CIQRCodeGenerator. Returns nil if CoreImage produced no output — this is
/// how CIQRCodeGenerator reports "message too long for a QR symbol at this correction
/// level" rather than throwing.
func generateNativeQR(message: String, correctionLevel: String) -> CGImage? {
    guard let data = message.data(using: .utf8) else { return nil }
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }

    let context = CIContext()
    return context.createCGImage(
        output,
        from: output.extent,
        format: .L8,
        colorSpace: CGColorSpaceCreateDeviceGray()
    )
}

/// Pads `image` with `modules` pixels of white on all four sides, at native (one-pixel-per-
/// module) resolution — so the padding is done before the integer upscale and stays an
/// exact whole number of modules at any --min-size. See the header comment for why the
/// quiet zone matters for this asset specifically.
func padWithQuietZone(_ image: CGImage, modules: Int) -> CGImage? {
    guard modules > 0 else { return image }
    let width = image.width + modules * 2
    let height = image.height + modules * 2
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    context.setAllowsAntialiasing(false)
    context.setShouldAntialias(false)
    context.draw(image, in: CGRect(x: modules, y: modules, width: image.width, height: image.height))
    return context.makeImage()
}

/// Integer nearest-neighbour upscale: draws the native bitmap into a larger context with
/// interpolation and antialiasing disabled, so each module is replicated as a hard-edged
/// block of pixels rather than smoothed. See the header comment for why this matters here.
func nearestNeighborUpscale(_ image: CGImage, scale: Int) -> CGImage? {
    let width = image.width * scale
    let height = image.height * scale
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.interpolationQuality = .none
    context.setAllowsAntialiasing(false)
    context.setShouldAntialias(false)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: - Main

let opts = parseArgs(Array(CommandLine.arguments.dropFirst()))

let root = repoRoot()
let outURL = opts.out.hasPrefix("/")
    ? URL(fileURLWithPath: opts.out)
    : root.appendingPathComponent(opts.out)

guard let native = generateNativeQR(message: opts.url, correctionLevel: opts.correctionLevel) else {
    FileHandle.standardError.write("error: CIQRCodeGenerator produced no output for the given message and correction level (message likely too long for a QR symbol at level \(opts.correctionLevel))\n".data(using: .utf8)!)
    exit(2)
}

let moduleEdge = native.width  // CIQRCodeGenerator output is always square, symbol only

guard let padded = padWithQuietZone(native, modules: opts.quietZone) else {
    FileHandle.standardError.write("error: failed to pad the native QR bitmap with a quiet zone\n".data(using: .utf8)!)
    exit(2)
}
let paddedEdge = padded.width  // symbol + quiet zone on both sides, still square
let scale = max(1, Int((Double(opts.minSize) / Double(paddedEdge)).rounded(.up)))

guard let upscaled = nearestNeighborUpscale(padded, scale: scale) else {
    FileHandle.standardError.write("error: failed to upscale the padded QR bitmap\n".data(using: .utf8)!)
    exit(2)
}

do {
    try FileManager.default.createDirectory(
        at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
} catch {
    FileHandle.standardError.write("error: could not create output directory: \(error)\n".data(using: .utf8)!)
    exit(3)
}

guard writePNG(upscaled, to: outURL) else {
    FileHandle.standardError.write("error: could not write PNG to \(outURL.path)\n".data(using: .utf8)!)
    exit(3)
}

print("wrote \(outURL.path)")
print("  encodes:            \(opts.url)")
print("  correction level:   \(opts.correctionLevel)")
print("  symbol modules:     \(moduleEdge)x\(moduleEdge)")
print("  quiet zone:         \(opts.quietZone) modules/side")
print("  total modules:      \(paddedEdge)x\(paddedEdge)")
print("  scale:              \(scale)x (nearest-neighbour)")
print("  pixel size:         \(upscaled.width)x\(upscaled.height)")
