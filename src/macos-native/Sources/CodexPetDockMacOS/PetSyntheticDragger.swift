import AppKit
import CoreGraphics

/// Replays the same mouse gesture that a user performs when dragging the Codex
/// pet. This is used only after the dock's own mouse gesture has ended, so the
/// synthetic events do not compete with a physical button-down sequence.
final class PetSyntheticDragger {
    func dragPet(from anchorFrame: CGRect, by appKitDelta: CGPoint) -> Bool {
        let distance = hypot(appKitDelta.x, appKitDelta.y)
        guard distance >= 3,
              AccessibilityPermission.isTrusted(prompt: false),
              let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let startAppKit = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        let endAppKit = CGPoint(
            x: startAppKit.x + appKitDelta.x,
            y: startAppKit.y + appKitDelta.y
        )
        let startQuartz = quartzPoint(fromAppKit: startAppKit)
        let endQuartz = quartzPoint(fromAppKit: endAppKit)
        let restoreQuartz = CGEvent(source: nil)?.location

        guard let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: startQuartz,
            mouseButton: .left
        ) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)

        let steps = max(8, min(24, Int(distance / 8)))
        for index in 1...steps {
            let progress = CGFloat(index) / CGFloat(steps)
            let point = CGPoint(
                x: startQuartz.x + (endQuartz.x - startQuartz.x) * progress,
                y: startQuartz.y + (endQuartz.y - startQuartz.y) * progress
            )
            guard let dragged = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                continue
            }
            dragged.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.008)
        }

        guard let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: endQuartz,
            mouseButton: .left
        ) else {
            if let restoreQuartz {
                CGWarpMouseCursorPosition(restoreQuartz)
            }
            return false
        }

        mouseUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)

        if let restoreQuartz {
            CGWarpMouseCursorPosition(restoreQuartz)
        }
        return true
    }

    private func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
