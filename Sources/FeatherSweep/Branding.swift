import AppKit
import SwiftUI

/// All geometry is vector based. Packaging can render this same function at iconset sizes.
enum Branding {
    static let blue = Color(red: 0.0, green: 0.47, blue: 1.0)

    static func drawLogo(in context: CGContext, rect: CGRect, template: Bool = false) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width, y: rect.height)
        if !template {
            let tile = CGPath(roundedRect: CGRect(x: 0.055, y: 0.055, width: 0.89, height: 0.89),
                              cornerWidth: 0.205, cornerHeight: 0.205, transform: nil)
            context.saveGState()
            context.addPath(tile)
            context.clip()
            let colors = [CGColor(red: 0.02, green: 0.64, blue: 1, alpha: 1),
                          CGColor(red: 0.02, green: 0.34, blue: 0.98, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.1, y: 0.95),
                                       end: CGPoint(x: 0.9, y: 0.05), options: [])
            context.restoreGState()
        }
        context.setStrokeColor(template ? NSColor.black.cgColor : NSColor.white.cgColor)
        context.setFillColor(template ? NSColor.black.cgColor : NSColor.white.cgColor)
        context.setLineWidth(template ? 0.064 : 0.052)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: 0.46, y: 0.49), radius: 0.258,
                       startAngle: .pi * 0.28, endAngle: .pi * 1.98, clockwise: false)
        context.strokePath()

        let drive = CGMutablePath()
        drive.move(to: CGPoint(x: 0.31, y: 0.39))
        drive.addLine(to: CGPoint(x: 0.345, y: 0.59))
        drive.addQuadCurve(to: CGPoint(x: 0.37, y: 0.61), control: CGPoint(x: 0.35, y: 0.61))
        drive.addLine(to: CGPoint(x: 0.55, y: 0.61))
        drive.addQuadCurve(to: CGPoint(x: 0.575, y: 0.59), control: CGPoint(x: 0.57, y: 0.61))
        drive.addLine(to: CGPoint(x: 0.61, y: 0.39))
        drive.addLine(to: CGPoint(x: 0.61, y: 0.32))
        drive.addQuadCurve(to: CGPoint(x: 0.58, y: 0.29), control: CGPoint(x: 0.61, y: 0.29))
        drive.addLine(to: CGPoint(x: 0.34, y: 0.29))
        drive.addQuadCurve(to: CGPoint(x: 0.31, y: 0.32), control: CGPoint(x: 0.31, y: 0.29))
        drive.closeSubpath()
        context.addPath(drive)
        context.strokePath()
        context.move(to: CGPoint(x: 0.32, y: 0.39))
        context.addLine(to: CGPoint(x: 0.60, y: 0.39))
        context.strokePath()
        context.fillEllipse(in: CGRect(x: 0.535, y: 0.325, width: 0.025, height: 0.025))

        let sparkle = CGMutablePath()
        let points: [CGPoint] = [CGPoint(x: 0.73, y: 0.82), CGPoint(x: 0.765, y: 0.725),
                                 CGPoint(x: 0.86, y: 0.69), CGPoint(x: 0.765, y: 0.655),
                                 CGPoint(x: 0.73, y: 0.56), CGPoint(x: 0.695, y: 0.655),
                                 CGPoint(x: 0.60, y: 0.69), CGPoint(x: 0.695, y: 0.725)]
        sparkle.addLines(between: points)
        sparkle.closeSubpath()
        context.addPath(sparkle)
        context.fillPath()
        context.restoreGState()
    }

    @MainActor
    static func image(size: CGFloat = 128, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawLogo(in: context, rect: rect, template: template)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = template ? "轻扫菜单栏" : "轻扫"
        return image
    }
}
