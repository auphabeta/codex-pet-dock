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
    private var dragFailureStatus: String?
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
        dragFailureStatus = nil
        tick()
    }

    func setWindowFallbackEnabled(_ enabled: Bool) {
        windowFallbackEnabled = enabled
        manualOffset = .zero
        dragFailureStatus = nil
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
            dragFailureStatus = nil
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
            publishStatus(
                dragFailureStatus ?? "Attached to Codex pet — drag the dock to move both"
            )
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

        if let anchor = currentAnchor,
           let originalWindow = anchor.movableWindow {
            let result = locator.moveBestAvailableWindow(
                startingAt: originalWindow,
                anchorFrame: anchor.frame,
                by: delta
            )
            switch result {
            case .moved:
                dragFailureStatus = nil
                tick()
                return
            case .noWritableWindow, .failed:
                dragFailureStatus = result.statusText
                publishStatus(
                    result.statusText ?? "Attached, but the Codex pet window could not be moved"
                )
                return
            }
        }

        guard currentAnchor?.source == .hostWindowFallback else {
            dragFailureStatus = "Attached, but no movable Codex pet window was exposed"
            publishStatus(dragFailureStatus!)
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
