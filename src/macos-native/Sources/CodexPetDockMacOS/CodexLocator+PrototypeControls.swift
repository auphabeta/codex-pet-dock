import AppKit

extension CodexPetLocator {
    func locate(
        allowWindowFallback: Bool
    ) -> (application: NSRunningApplication, anchor: PetAnchor)? {
        guard let result = locate() else {
            return nil
        }

        if result.anchor.source == .hostWindowFallback {
            return allowWindowFallback ? result : nil
        }

        let frame = result.anchor.frame
        let aspectRatio = frame.width / max(frame.height, 1)
        let plausiblePetBounds =
            frame.width >= 64 &&
            frame.height >= 64 &&
            frame.width <= 420 &&
            frame.height <= 420 &&
            aspectRatio >= 0.45 &&
            aspectRatio <= 2.2

        return plausiblePetBounds ? result : nil
    }

    func isCodexRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
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
    }
}
