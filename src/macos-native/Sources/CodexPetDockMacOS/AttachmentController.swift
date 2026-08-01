import AppKit
import ApplicationServices

final class AttachmentController {
    var onStatusChanged: ((String) -> Void)?

    private let overlay: DockOverlayController
    private let locator = CodexPetLocator()
    private let syntheticDragger = PetSyntheticDragger()
    private var timer: Timer?
    private var previewEnabled = false
    private var windowFallbackEnabled = false
    private var currentAnchor: PetAnchor?
    private var manualOffset = CGPoint.zero
    private var dragFailureStatus: String?
    private var lastStatus = ""

    private var isDraggingPreciseAnchor = false
    private var isVerifyingPetMove = false
    private var dragStartAnchor: PetAnchor?
    private var accumulatedDrag = CGPoint.zero
    private var verificationWorkItem: DispatchWorkItem?

    init(overlay: DockOverlayController) {
        self.overlay = overlay
        overlay.onDragBegan = { [weak self] in
            self?.handleDragBegan()
        }
        overlay.onDrag = { [weak self] delta in
            self?.handleDrag(delta)
        }
        overlay.onDragEnded = { [weak self] totalDelta in
            self?.handleDragEnded(totalDelta)
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
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        isDraggingPreciseAnchor = false
        isVerifyingPetMove = false
        dragStartAnchor = nil
        overlay.hide()
        currentAnchor = nil
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        tick()
    }

    func setPreviewEnabled(_ enabled: Bool) {
        previewEnabled = enabled
        resetDragState()
        manualOffset = .zero
        dragFailureStatus = nil
        tick()
    }

    func setWindowFallbackEnabled(_ enabled: Bool) {
        windowFallbackEnabled = enabled
        resetDragState()
        manualOffset = .zero
        dragFailureStatus = nil
        tick()
    }

    private func tick() {
        guard !isDraggingPreciseAnchor, !isVerifyingPetMove else {
            return
        }

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
                dragFailureStatus ?? "Attached to Codex pet — drag the dock and release"
            )
        } else {
            publishStatus("Debug window fallback — drag the dock to reposition")
        }
    }

    private func handleDragBegan() {
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        accumulatedDrag = .zero

        guard !previewEnabled,
              currentAnchor?.source == .accessibilityElement else {
            return
        }

        dragFailureStatus = nil
        isDraggingPreciseAnchor = true
        dragStartAnchor = currentAnchor
        publishStatus("Dragging dock — release to move Codex pet")
    }

    private func handleDrag(_ delta: CGPoint) {
        if previewEnabled {
            manualOffset.x += delta.x
            manualOffset.y += delta.y
            overlay.moveBy(delta)
            return
        }

        if isDraggingPreciseAnchor {
            accumulatedDrag.x += delta.x
            accumulatedDrag.y += delta.y
            overlay.moveBy(delta)
            return
        }

        guard currentAnchor?.source == .hostWindowFallback else {
            return
        }
        manualOffset.x += delta.x
        manualOffset.y += delta.y
        overlay.moveBy(delta)
    }

    private func handleDragEnded(_ totalDelta: CGPoint) {
        if previewEnabled || currentAnchor?.source == .hostWindowFallback {
            tick()
            return
        }

        guard isDraggingPreciseAnchor,
              let startAnchor = dragStartAnchor else {
            return
        }

        isDraggingPreciseAnchor = false
        dragStartAnchor = nil

        let requestedDelta = hypot(totalDelta.x, totalDelta.y) >= 3
            ? totalDelta
            : accumulatedDrag
        accumulatedDrag = .zero

        guard hypot(requestedDelta.x, requestedDelta.y) >= 3 else {
            tick()
            return
        }

        isVerifyingPetMove = true
        publishStatus("Moving Codex pet…")

        guard syntheticDragger.dragPet(
            from: startAnchor.frame,
            by: requestedDelta
        ) else {
            isVerifyingPetMove = false
            dragFailureStatus = "Could not send a trusted drag gesture to Codex"
            tick()
            return
        }

        publishStatus("Verifying Codex pet movement…")
        let workItem = DispatchWorkItem { [weak self] in
            self?.verifyPetMove(
                from: startAnchor,
                requestedDelta: requestedDelta
            )
        }
        verificationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.22,
            execute: workItem
        )
    }

    private func verifyPetMove(
        from startAnchor: PetAnchor,
        requestedDelta: CGPoint
    ) {
        verificationWorkItem = nil
        defer {
            isVerifyingPetMove = false
            tick()
        }

        guard let result = locator.locate(allowWindowFallback: false),
              result.anchor.source == .accessibilityElement else {
            dragFailureStatus = "Codex pet disappeared while verifying the drag"
            return
        }

        let actualDelta = CGPoint(
            x: result.anchor.frame.midX - startAnchor.frame.midX,
            y: result.anchor.frame.midY - startAnchor.frame.midY
        )
        let requestedDistance = hypot(requestedDelta.x, requestedDelta.y)
        let actualDistance = hypot(actualDelta.x, actualDelta.y)
        let minimumDistance = max(3, min(12, requestedDistance * 0.25))
        let directionalProgress =
            actualDelta.x * requestedDelta.x +
            actualDelta.y * requestedDelta.y

        if actualDistance >= minimumDistance, directionalProgress > 0 {
            currentAnchor = result.anchor
            dragFailureStatus = nil
            publishStatus("Attached to Codex pet — drag verified")
        } else {
            dragFailureStatus =
                "Dock drag was sent, but Codex did not move the pet"
        }
    }

    private func resetDragState() {
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        isDraggingPreciseAnchor = false
        isVerifyingPetMove = false
        dragStartAnchor = nil
        accumulatedDrag = .zero
    }

    private func publishStatus(_ status: String) {
        guard status != lastStatus else { return }
        lastStatus = status
        onStatusChanged?(status)
    }
}
