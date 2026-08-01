import AppKit
import ApplicationServices

/// Result of attempting to move the Codex pet host window through macOS
/// Accessibility. Keeping the error visible makes it possible to distinguish a
/// locator problem from a target-window restriction.
enum PetWindowMoveResult {
    case moved
    case noWritableWindow
    case failed(AXError)

    var statusText: String? {
        switch self {
        case .moved:
            return nil
        case .noWritableWindow:
            return "Attached, but the Codex pet window is not AX-movable"
        case .failed(let error):
            return "Attached, but moving the pet failed (AX error \(error.rawValue))"
        }
    }
}

extension CodexPetLocator {
    /// Resolves the actual pet host window instead of assuming that the window
    /// used while traversing the AX tree is the movable one. Electron utility
    /// windows can expose the pet below a proxy/container window while the
    /// writable AXPosition belongs to a related top-level window.
    func moveBestAvailableWindow(
        startingAt originalWindow: AXUIElement,
        anchorFrame: CGRect,
        by appKitDelta: CGPoint
    ) -> PetWindowMoveResult {
        let candidates = movableWindowCandidates(
            startingAt: originalWindow,
            anchorFrame: anchorFrame
        )

        var lastError: AXError?
        for candidate in candidates {
            guard var position = moverPointAttribute(
                candidate,
                kAXPositionAttribute as String
            ) else {
                continue
            }

            var settable = DarwinBoolean(false)
            let settableError = AXUIElementIsAttributeSettable(
                candidate,
                kAXPositionAttribute as CFString,
                &settable
            )
            guard settableError == .success, settable.boolValue else {
                if settableError != .success {
                    lastError = settableError
                }
                continue
            }

            position.x += appKitDelta.x
            position.y -= appKitDelta.y
            guard let value = AXValueCreate(.cgPoint, &position) else {
                continue
            }

            let error = AXUIElementSetAttributeValue(
                candidate,
                kAXPositionAttribute as CFString,
                value
            )
            if error == .success {
                return .moved
            }
            lastError = error
        }

        if let lastError {
            return .failed(lastError)
        }
        return .noWritableWindow
    }

    private func movableWindowCandidates(
        startingAt originalWindow: AXUIElement,
        anchorFrame: CGRect
    ) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        var hashes = Set<CFHashCode>()

        func appendUnique(_ element: AXUIElement?) {
            guard let element else { return }
            let hash = CFHash(element)
            guard hashes.insert(hash).inserted else { return }
            candidates.append(element)
        }

        appendUnique(originalWindow)
        appendUnique(moverElementAttribute(
            originalWindow,
            kAXWindowAttribute as String
        ))

        var parent = moverElementAttribute(
            originalWindow,
            kAXParentAttribute as String
        )
        for _ in 0..<12 {
            guard let current = parent else { break }
            appendUnique(current)
            appendUnique(moverElementAttribute(
                current,
                kAXWindowAttribute as String
            ))
            parent = moverElementAttribute(
                current,
                kAXParentAttribute as String
            )
        }

        var pid: pid_t = 0
        if AXUIElementGetPid(originalWindow, &pid) == .success, pid > 0 {
            let application = AXUIElementCreateApplication(pid)
            for window in moverElementArrayAttribute(
                application,
                kAXWindowsAttribute as String
            ) {
                appendUnique(window)
            }
        }

        return candidates.sorted { lhs, rhs in
            moverWindowScore(lhs, anchorFrame: anchorFrame) <
                moverWindowScore(rhs, anchorFrame: anchorFrame)
        }
    }

    private func moverWindowScore(
        _ element: AXUIElement,
        anchorFrame: CGRect
    ) -> CGFloat {
        var score: CGFloat = 1_000_000_000

        if let rawFrame = moverAccessibilityFrame(element) {
            let frame = ScreenCoordinates.appKitRect(
                fromAccessibility: rawFrame
            )
            let dx = frame.midX - anchorFrame.midX
            let dy = frame.midY - anchorFrame.midY
            score = hypot(dx, dy)

            if frame.contains(
                CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
            ) {
                score -= 100_000
            }

            // Prefer compact utility/pet windows over the large Codex main
            // window when both contain accessibility descendants.
            score += min(frame.width * frame.height, 2_000_000) / 10_000
        }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXPositionAttribute as CFString,
            &settable
        ) == .success,
           settable.boolValue {
            score -= 200_000
        }

        let role = moverStringAttribute(
            element,
            kAXRoleAttribute as String
        )
        if role == (kAXWindowRole as String) {
            score -= 20_000
        }
        return score
    }

    private func moverAccessibilityFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = moverPointAttribute(
            element,
            kAXPositionAttribute as String
        ),
        let size = moverSizeAttribute(
            element,
            kAXSizeAttribute as String
        ),
        size.width > 0,
        size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func moverElementAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func moverElementArrayAttribute(
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

    private func moverStringAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> String {
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

    private func moverPointAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func moverSizeAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
