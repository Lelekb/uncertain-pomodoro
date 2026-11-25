import AppKit

enum BarStyle { case stepped, smooth }

@MainActor
enum BarRenderer {
    static let segmentCount = 5

    /// Draws whole segments by default, or proportional partial fills in smooth style.
    // Smooth style: kept for later use (user liked it), not the default.
    static func image(fraction: Double, mode: BarMode, style: BarStyle = .stepped) -> NSImage {
        let progress = fraction.isNaN ? 0 : min(1, max(0, fraction))
        let scaledProgress = progress * Double(segmentCount)
        let filledSegments = mode == .idle ? 0
            : (style == .stepped ? floor(scaledProgress) : scaledProgress)

        let image = NSImage(size: NSSize(width: 64, height: 14), flipped: false) { _ in
            // Resolve the semantic colour in the drawing appearance, including dark menu bars.
            let unfilledColor = NSColor.labelColor.withAlphaComponent(0.25)

            let segmentStride = CGFloat(60 / segmentCount)
            for index in 0..<segmentCount {
                // Whole-point edges remain crisp at both standard and Retina scales.
                let rect = NSRect(x: 2 + CGFloat(index) * segmentStride, y: 2,
                                  width: segmentStride - 1, height: 10)
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                unfilledColor.setFill()
                path.fill()

                let coverage = CGFloat(min(1, max(0, filledSegments - Double(index))))
                guard coverage > 0 else { continue }

                let color: NSColor
                if mode == .breakTime {
                    color = NSColor(srgbRed: 10 / 255.0, green: 132 / 255.0,
                                    blue: 1, alpha: 1)
                } else {
                    color = workColor(position: Double(index) / Double(segmentCount - 1))
                }

                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                color.setFill()
                NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                         width: rect.width * coverage, height: rect.height)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func workColor(position: Double) -> NSColor {
        let green = (52.0, 199.0, 89.0)
        let amber = (255.0, 159.0, 10.0)
        let red = (255.0, 59.0, 48.0)
        let start = position <= 0.5 ? green : amber
        let end = position <= 0.5 ? amber : red
        let amount = position <= 0.5 ? position * 2 : (position - 0.5) * 2

        return NSColor(srgbRed: (start.0 + (end.0 - start.0) * amount) / 255,
                       green: (start.1 + (end.1 - start.1) * amount) / 255,
                       blue: (start.2 + (end.2 - start.2) * amount) / 255,
                       alpha: 1)
    }
}

enum BarMode { case idle, work, breakTime }
