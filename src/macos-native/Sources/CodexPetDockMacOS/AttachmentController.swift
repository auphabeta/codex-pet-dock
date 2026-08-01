import AppKit
import ApplicationServices

final class AttachmentController {
    var onStatusChanged: ((String) -> Void)?

    private let overlay: DockOverlayController
    private let locator = CodexPetLocator()
    private var timer: Timer?
    private var previewEnabled = false
    private var windowFallbackEnabled = false
    private var currentAnchor: PetAnchor?
    private var manualOffset = CGPoint.zero
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
        manualOffset = .zero
        tick()
    }

    func setWindowFallbackEnabled(_ enabled: Bool) {
        windowFallbackEnabled = enabled
        manualOffset = .zero
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
                ),
                offset: manualOffset
            )
            publishStatus("Preview mode — drag the dock to move it")
            return
        }

        guard let result = locator.locate(
            allowWindowFallback: windowFallbackEnabled
        ) else {
            currentAnchor = nil
            overlay.hide()

            if !AccessibilityPermission.isTrusted(prompt: false) {
                publishStatus("Grant Accessibility permission to find the pet")
            } else if locator.isCodexRunning() {
                publishStatus("Codex is running, but no pet element was detected")
            } else {
                publishStatus("Waiting for Codex")
            }
            return
        }

        currentAnchor = result.anchor
        let precise = result.anchor.source == .accessibilityElement
        overlay.show(
            attachedTo: result.anchor.frame,
            metrics: DockMetrics(
                weeklyRemainingText: "--",
                weeklyTokensText: "--",
                statusText: precise ? "ATTACHED" : "WINDOW DEBUG"
            ),
            offset: precise ? .zero : manualOffset
        )

        if precise {
            publishStatus("Attached to Codex pet")
        } else {
            publishStatus("Debug window fallback — drag the dock to reposition")
        }
    }

    private func handleDrag(_ delta: CGPoint) {
        if previewEnabled {
            manualOffset.x += delta.x
            manualOffset.y += delta.y
            tick()
            return
        }

        if let movableWindow = currentAnchor?.movableWindow,
           locator.move(window: movableWindow, by: delta) {
            tick()
            return
        }

        guard currentAnchor?.source == .hostWindowFallback else {
            return
        }
        manualOffset.x += delta.x
        manualOffset.y += delta.y
        tick()
    }

    private func publishStatus(_ status: String) {
        guard status != lastStatus else { return }
        lastStatus = status
        onStatusChanged?(status)
    }
}
