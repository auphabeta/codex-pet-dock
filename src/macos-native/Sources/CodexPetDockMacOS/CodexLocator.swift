import AppKit
import ApplicationServices
import CoreGraphics

struct PetAnchor {
    enum Source: String {
        case accessibilityElement
        case hostWindowFallback
    }

    let frame: CGRect
    let movableWindow: AXUIElement?
    let source: Source
}

struct QuartzWindowCandidate {
    let frame: CGRect
    let windowNumber: CGWindowID
    let layer: Int
    let title: String

    var area: CGFloat { frame.width * frame.height }
}

enum AccessibilityPermission {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

final class CodexProcessLocator {
    func locate() -> NSRunningApplication? {
        let applications = NSWorkspace.shared.runningApplications
        return applications
            .filter { application in
                guard !application.isTerminated else { return false }
                let name = application.localizedName?.lowercased() ?? ""
                let bundleID = application.bundleIdentifier?.lowercased() ?? ""
                let executablePath = application.executableURL?.path.lowercased() ?? ""

                let identifiesCodex =
                    name == "codex" ||
                    bundleID.contains("codex") ||
                    executablePath.contains("/codex.app/")
                let identifiesOpenAI =
                    bundleID.contains("openai") ||
                    executablePath.contains("openai") ||
                    name == "codex"
                return identifiesCodex && identifiesOpenAI
            }
            .sorted { lhs, rhs in
                let lhsActive = lhs.isActive ? 0 : 1
                let rhsActive = rhs.isActive ? 0 : 1
                if lhsActive != rhsActive { return lhsActive < rhsActive }
                return lhs.processIdentifier < rhs.processIdentifier
            }
            .first
    }
}

final class CodexPetLocator {
    private let processLocator = CodexProcessLocator()

    func locate() -> (application: NSRunningApplication, anchor: PetAnchor)? {
        guard let application = processLocator.locate() else {
            return nil
        }

        let pid = application.processIdentifier
        let fallback = bestQuartzWindow(for: pid)

        if AccessibilityPermission.isTrusted(prompt: false),
           let accessibilityAnchor = bestAccessibilityAnchor(for: pid, fallback: fallback) {
            return (application, accessibilityAnchor)
        }

        guard let fallback else {
            return nil
        }
        return (
            application,
            PetAnchor(
                frame: fallback.frame,
                movableWindow: nil,
                source: .hostWindowFallback
            )
        )
    }

    func move(window: AXUIElement, by appKitDelta: CGPoint) -> Bool {
        guard var position = pointAttribute(window, kAXPositionAttribute as String) else {
            return false
        }
        position.x += appKitDelta.x
        position.y -= appKitDelta.y
        guard let value = AXValueCreate(.cgPoint, &position) else {
            return false
        }
        return AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    private func bestQuartzWindow(for pid: pid_t) -> QuartzWindowCandidate? {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let candidates = rawWindows.compactMap { info -> QuartzWindowCandidate? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == pid,
                  let boundsDictionary = info[kCGWindowBounds as String] as? CFDictionary,
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary),
                  quartzFrame.width >= 100,
                  quartzFrame.height >= 100,
                  quartzFrame.width <= 1600,
                  quartzFrame.height <= 1600 else {
                return nil
            }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { return nil }

            let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            return QuartzWindowCandidate(
                frame: ScreenCoordinates.appKitRect(fromQuartz: quartzFrame),
                windowNumber: windowNumber,
                layer: layer,
                title: title
            )
        }

        return candidates.min { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private func score(_ candidate: QuartzWindowCandidate) -> Double {
        var value = Double(candidate.area)
        let normalizedTitle = candidate.title.lowercased()
        if normalizedTitle.contains("codex") { value -= 250_000 }
        if candidate.layer > 0 { value -= 100_000 }
        if candidate.frame.width < 900 && candidate.frame.height < 900 {
            value -= 75_000
        }
        return value
    }

    private func bestAccessibilityAnchor(
        for pid: pid_t,
        fallback: QuartzWindowCandidate?
    ) -> PetAnchor? {
        let applicationElement = AXUIElementCreateApplication(pid)
        let windows = elementArrayAttribute(
            applicationElement,
            kAXWindowsAttribute as String
        )

        var bestCandidate: AccessibilityCandidate?
        var visited = 0

        for window in windows {
            guard let rawWindowFrame = accessibilityFrame(window),
                  rawWindowFrame.width >= 100,
                  rawWindowFrame.height >= 100,
                  rawWindowFrame.width <= 1600,
                  rawWindowFrame.height <= 1600 else {
                continue
            }

            let candidate = search(
                root: window,
                ownerWindow: window,
                fallbackFrame: fallback?.frame,
                visited: &visited,
                depth: 0
            )
            if let candidate,
               bestCandidate == nil || candidate.score > bestCandidate!.score {
                bestCandidate = candidate
            }
            if visited >= 1200 { break }
        }

        guard let bestCandidate else {
            return nil
        }
        return PetAnchor(
            frame: ScreenCoordinates.appKitRect(
                fromAccessibility: bestCandidate.rawFrame
            ),
            movableWindow: bestCandidate.ownerWindow,
            source: .accessibilityElement
        )
    }

    private func search(
        root: AXUIElement,
        ownerWindow: AXUIElement,
        fallbackFrame: CGRect?,
        visited: inout Int,
        depth: Int
    ) -> AccessibilityCandidate? {
        guard depth <= 14, visited < 1200 else {
            return nil
        }
        visited += 1

        var best: AccessibilityCandidate?
        if let rawFrame = accessibilityFrame(root),
           rawFrame.width >= 32,
           rawFrame.height >= 32,
           rawFrame.width <= 700,
           rawFrame.height <= 700 {
            let score = accessibilityScore(
                element: root,
                rawFrame: rawFrame,
                fallbackFrame: fallbackFrame
            )
            if score >= 45 {
                best = AccessibilityCandidate(
                    rawFrame: rawFrame,
                    ownerWindow: ownerWindow,
                    score: score
                )
            }
        }

        for child in elementArrayAttribute(root, kAXChildrenAttribute as String) {
            if let childCandidate = search(
                root: child,
                ownerWindow: ownerWindow,
                fallbackFrame: fallbackFrame,
                visited: &visited,
                depth: depth + 1
            ), best == nil || childCandidate.score > best!.score {
                best = childCandidate
            }
            if visited >= 1200 { break }
        }
        return best
    }

    private func accessibilityScore(
        element: AXUIElement,
        rawFrame: CGRect,
        fallbackFrame: CGRect?
    ) -> Int {
        let text = [
            stringAttribute(element, "AXIdentifier"),
            stringAttribute(element, "AXDOMIdentifier"),
            stringAttribute(element, kAXTitleAttribute as String),
            stringAttribute(element, kAXDescriptionAttribute as String),
            stringAttribute(element, kAXHelpAttribute as String),
            stringAttribute(element, kAXRoleDescriptionAttribute as String)
        ]
        .joined(separator: " ")
        .lowercased()

        var score = 0
        if text.contains("codex-avatar-button") { score += 140 }
        if text.contains("pet") { score += 70 }
        if text.contains("mascot") { score += 65 }
        if text.contains("avatar") { score += 50 }
        if text.contains("codex") { score += 20 }

        let role = stringAttribute(element, kAXRoleAttribute as String)
        if role == (kAXButtonRole as String) { score += 12 }

        if rawFrame.width >= 70 && rawFrame.height >= 70 { score += 8 }
        if rawFrame.width <= 420 && rawFrame.height <= 420 { score += 8 }

        if let fallbackFrame {
            let appKitFrame = ScreenCoordinates.appKitRect(fromAccessibility: rawFrame)
            if appKitFrame.intersects(fallbackFrame) { score += 18 }
            let dx = appKitFrame.midX - fallbackFrame.midX
            let dy = appKitFrame.midY - fallbackFrame.midY
            if hypot(dx, dy) < 240 { score += 12 }
        }
        return score
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func elementArrayAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func accessibilityFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ element: AXUIElement, _ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success,
        let axValue = value as? AXValue,
        AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success,
        let axValue = value as? AXValue,
        AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}

private struct AccessibilityCandidate {
    let rawFrame: CGRect
    let ownerWindow: AXUIElement
    let score: Int
}

enum ScreenCoordinates {
    static func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        convertTopLeftRect(rect)
    }

    static func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
        convertTopLeftRect(rect)
    }

    private static func convertTopLeftRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
