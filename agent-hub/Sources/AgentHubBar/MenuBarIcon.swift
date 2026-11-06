import AppKit

enum MenuBarIcon {
    // Same glyph as the Agent Tabs plugin icon: a tab, a terminal frame and a prompt.
    static func make(hasAttention: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1, width: 7, height: 3.5), xRadius: 1, yRadius: 1).fill()

            let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 17, height: 11), xRadius: 2, yRadius: 2)
            frame.lineWidth = 1.5
            frame.stroke()

            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: 5, y: 6.5))
            prompt.line(to: NSPoint(x: 8, y: 9))
            prompt.line(to: NSPoint(x: 5, y: 11.5))
            prompt.lineWidth = 1.5
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round
            prompt.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 10, y: 11.5))
            cursor.line(to: NSPoint(x: 14, y: 11.5))
            cursor.lineWidth = 1.5
            cursor.lineCapStyle = .round
            cursor.stroke()

            if hasAttention {
                NSBezierPath(ovalIn: NSRect(x: 14, y: 0, width: 5.5, height: 5.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
