import AppKit

extension CodexPetLocator {
    func locate(
        allowWindowFallback: Bool
    ) -> (application: NSRunningApplication, anchor: PetAnchor)? {
        guard let result = locate() else {
            return nil
        }
        if !allowWindowFallback,
           result.anchor.source == .hostWindowFallback {
            return nil
        }
        return result
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
