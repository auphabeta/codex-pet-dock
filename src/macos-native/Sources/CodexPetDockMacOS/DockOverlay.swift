import AppKit

struct DockMetrics {
    var weeklyRemainingText: String = "--"
    var weeklyTokensText: String = "--"
    var statusText: String = "WAITING"
}

final class DockOverlayController {
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    private let panel: NSPanel
    private let dockView: DockView
    private let size = CGSize(width: 224, height: 72)
    private let contactSurfaceFromBottom: CGFloat = 49
    private let contactOverlap: CGFloat = 6

    init() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dockView = DockView(frame: CGRect(origin: .zero, size: size))

        panel.contentView = dockView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        dockView.onDragBegan = { [weak self] in
            self?.onDragBegan?()
        }
        dockView.onDrag = { [weak self] delta in
            self?.onDrag?(delta)
        }
        dockView.onDragEnded = { [weak self] totalDelta in
            self?.onDragEnded?(totalDelta)
        }
    }

    func show(
        attachedTo petFrame: CGRect,
        metrics: DockMetrics,
        offset: CGPoint = .zero
    ) {
        let origin = CGPoint(
            x: petFrame.midX - size.width / 2 + offset.x,
            y: petFrame.minY - contactSurfaceFromBottom + contactOverlap + offset.y
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        dockView.metrics = metrics
        dockView.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func showPreview(
        metrics: DockMetrics,
        offset: CGPoint = .zero
    ) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return
        }
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2 + offset.x,
            y: visibleFrame.minY + 36 + offset.y
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        dockView.metrics = metrics
        dockView.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func moveBy(_ delta: CGPoint) {
        var frame = panel.frame
        frame.origin.x += delta.x
        frame.origin.y += delta.y
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DockView: NSView {
    var metrics = DockMetrics()
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    private var lastDragLocation: CGPoint?
    private var totalDrag = CGPoint.zero

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.current?.imageInterpolation = .high

        let bodyRect = bounds.insetBy(dx: 5, dy: 5)
        let body = NSBezierPath(
            roundedRect: bodyRect,
            xRadius: 13,
            yRadius: 13
        )
        let bodyGradient = NSGradient(
            starting: NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.13, alpha: 0.97),
            ending: NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.055, alpha: 0.98)
        )
        bodyGradient?.draw(in: body, angle: -90)

        NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.96, alpha: 0.7).setStroke()
        body.lineWidth = 1.2
        body.stroke()

        let platformRect = CGRect(x: 42, y: 42, width: 140, height: 24)
        let platform = NSBezierPath(ovalIn: platformRect)
        let platformGradient = NSGradient(
            starting: NSColor(calibratedRed: 0.25, green: 0.92, blue: 1.0, alpha: 0.62),
            ending: NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.34, alpha: 0.88)
        )
        platformGradient?.draw(in: platform, angle: -90)

        NSColor(calibratedRed: 0.56, green: 0.96, blue: 1.0, alpha: 0.9).setStroke()
        platform.lineWidth = 1
        platform.stroke()

        let glow = NSBezierPath(ovalIn: CGRect(x: 61, y: 45, width: 102, height: 15))
        NSColor(calibratedRed: 0.55, green: 0.97, blue: 1.0, alpha: 0.16).setFill()
        glow.fill()

        drawMetric(
            header: "WEEK LEFT",
            value: metrics.weeklyRemainingText,
            in: CGRect(x: 13, y: 13, width: 90, height: 27)
        )
        drawMetric(
            header: "WEEK TOKENS",
            value: metrics.weeklyTokensText,
            in: CGRect(x: 121, y: 13, width: 90, height: 27)
        )

        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 112, y: 13))
        divider.line(to: CGPoint(x: 112, y: 38))
        NSColor.white.withAlphaComponent(0.18).setStroke()
        divider.lineWidth = 1
        divider.stroke()

        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.50, green: 0.93, blue: 0.96, alpha: 0.72)
        ]
        let status = metrics.statusText.uppercased() as NSString
        status.draw(
            at: CGPoint(x: bounds.midX - status.size(withAttributes: statusAttributes).width / 2, y: 6),
            withAttributes: statusAttributes
        )
    }

    private func drawMetric(header: String, value: String, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.76, green: 0.98, blue: 1.0, alpha: 0.96),
            .paragraphStyle: paragraph
        ]

        (header as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.maxY - 9, width: rect.width, height: 9),
            withAttributes: headerAttributes
        )
        (value as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 18),
            withAttributes: valueAttributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        lastDragLocation = NSEvent.mouseLocation
        totalDrag = .zero
        NSCursor.closedHand.set()
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        guard let previous = lastDragLocation else {
            lastDragLocation = current
            return
        }
        let delta = CGPoint(
            x: current.x - previous.x,
            y: current.y - previous.y
        )
        lastDragLocation = current
        totalDrag.x += delta.x
        totalDrag.y += delta.y
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        let completedDrag = totalDrag
        lastDragLocation = nil
        totalDrag = .zero
        NSCursor.openHand.set()
        onDragEnded?(completedDrag)
    }
}
