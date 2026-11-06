import AppKit

enum MenuBarIcon {
    // A solid rounded frame with a cut-out >_ prompt.
    static func make(hasAttention: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.75, y: 1.25, width: 18.5, height: 13.5), xRadius: 4.5, yRadius: 4.5).fill()

            context.saveGState()
            context.setBlendMode(.clear)
            makePromptPaths().forEach { $0.stroke() }
            if hasAttention {
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: -1.5, width: 8.5, height: 8.5)).fill()
            }
            context.restoreGState()

            if hasAttention {
                NSBezierPath(ovalIn: NSRect(x: 14, y: 0, width: 5.5, height: 5.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func makePromptPaths() -> [NSBezierPath] {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 5.5, y: 5.5))
        chevron.line(to: NSPoint(x: 8.5, y: 8))
        chevron.line(to: NSPoint(x: 5.5, y: 10.5))

        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 10.5, y: 10.5))
        cursor.line(to: NSPoint(x: 14.5, y: 10.5))

        for path in [chevron, cursor] {
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
        }
        return [chevron, cursor]
    }
}
