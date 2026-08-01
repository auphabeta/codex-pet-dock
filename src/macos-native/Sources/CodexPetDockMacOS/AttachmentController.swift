import AppKit
import ApplicationServices

final class AttachmentController {
    var onStatusChanged: ((String) -> Void)?

    private let overlay: DockOverlayController
    private let locator = CodexPetLocator()
    private var timer: Timer?
    private var previewEnabled = false
    private var currentAnchor: PetAnchor?
    private var lastStatus = ""

    init(overlay: DockOverlayController) {
        self.overlay = overlay
        overlay.onDrag = { [weak self] delta in
            self?.handleDrag(delta)
        }
    }

    func start() {
        stop()
        tick()
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.35,
            repeats: true
        ) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overlay.hide()
        currentAnchor = nil
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        tick()
    }

    func setPreviewEnabled(_ enabled: Bool) {
        previewEnabled = enabled
        tick()
    }

    private func tick() {
        if previewEnabled {
            currentAnchor = nil
            overlay.showPreview(
                metrics: DockMetrics(
                    weeklyRemainingText: "--",
                    weeklyTokensText: "--",
                    statusText: "PREVIEW"
                )
            )
            publishStatus("Preview mode")
            return
        }

        guard let result = locator.locate() else {
            currentAnchor = nil
            overlay.hide()
            publishStatus("Waiting for Codex pet")
            return
        }

        currentAnchor = result.anchor
        let precise = result.anchor.source == .accessibilityElement
        overlay.show(
            attachedTo: result.anchor.frame,
            metrics: DockMetrics(
                weeklyRemainingText: "--",
                weeklyTokensText: "--",
                statusText: precise ? "ATTACHED" : "WINDOW"
            )
        )

        if precise {
            publishStatus("Attached to Codex pet")
        } else if AccessibilityPermission.isTrusted(prompt: false) {
            publishStatus("Using Codex window fallback")
        } else {
            publishStatus("Grant Accessibility for precise attachment")
        }
    }

    private func handleDrag(_ delta: CGPoint) {
        guard !previewEnabled,
              let movableWindow = currentAnchor?.movableWindow,
              locator.move(window: movableWindow, by: delta) else {
            return
        }
        tick()
    }

    private func publishStatus(_ status: String) {
        guard status != lastStatus else { return }
        lastStatus = status
        onStatusChanged?(status)
    }
}
