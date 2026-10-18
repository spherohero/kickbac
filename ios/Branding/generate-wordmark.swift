// Run from the repository root with Xcode-beta's `xcrun swift`.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = ios.appendingPathComponent("Branding/KickBACWordmark.pdf")
let page = CGPDFDocument(source as CFURL)!.page(at: 1)!
let bounds = page.getBoxRect(.mediaBox)
let asset = ios.appendingPathComponent("KickBAC/Assets.xcassets/KickBACWordmark.imageset")
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for scale in 1...3 {
    let context = CGContext(data: nil, width: 300 * scale, height: 49 * scale,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: (49 - bounds.height) / 2)
    context.drawPDFPage(page)
    let filename = "KickBACWordmark@\(scale)x.png"
    let output = CGImageDestinationCreateWithURL(asset.appendingPathComponent(filename) as CFURL,
                                                UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(output))
    images.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: asset.appendingPathComponent("Contents.json"), options: .atomic)
print("Generated shared KickBAC wordmark PNGs from the Mogi vector source.")
