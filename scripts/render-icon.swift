import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Compile this file together with Sources/FeatherSweep/Branding.swift.
/// Every PNG uses the same vector drawing function as the app and menu bar.
@main
struct IconRenderer {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "IconRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Usage: render-icon /absolute/Resources"])
        }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, pixels) in sizes {
            try render(pixels: pixels, to: iconset.appendingPathComponent(name))
        }
        try render(pixels: 1024, to: resources.appendingPathComponent("AppLogo.png"))
    }

    private static func render(pixels: Int, to url: URL) throws {
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                  UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "IconRenderer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG: \(url.path)"])
        }
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        Branding.drawLogo(in: context, rect: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let image = context.makeImage() else {
            throw NSError(domain: "IconRenderer", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot render logo"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "IconRenderer", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG: \(url.path)"])
        }
    }
}
