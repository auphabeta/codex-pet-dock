import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var attachmentController: AttachmentController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = DockOverlayController()
        let attachment = AttachmentController(overlay: overlay)
        let statusBar = StatusBarController()

        statusBar.onRequestAccessibility = {
            attachment.requestAccessibilityPermission()
        }
        statusBar.onTogglePreview = { enabled in
            attachment.setPreviewEnabled(enabled)
        }
        statusBar.onToggleWindowFallback = { enabled in
            attachment.setWindowFallbackEnabled(enabled)
        }
        statusBar.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        attachment.onStatusChanged = { [weak statusBar] status in
            statusBar?.updateStatus(status)
        }

        statusBarController = statusBar
        attachmentController = attachment
        attachment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        attachmentController?.stop()
    }
}

final class StatusBarController: NSObject {
    var onRequestAccessibility: (() -> Void)?
    var onTogglePreview: ((Bool) -> Void)?
    var onToggleWindowFallback: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let statusLine: NSMenuItem
    private let previewItem: NSMenuItem
    private let windowFallbackItem: NSMenuItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        statusLine = NSMenuItem(
            title: "Starting…",
            action: nil,
            keyEquivalent: ""
        )
        previewItem = NSMenuItem(
            title: "Preview dock without Codex",
            action: #selector(togglePreview(_:)),
            keyEquivalent: ""
        )
        windowFallbackItem = NSMenuItem(
            title: "Allow Codex window fallback (debug)",
            action: #selector(toggleWindowFallback(_:)),
            keyEquivalent: ""
        )
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: "Codex Pet Dock"
            )
            button.toolTip = "Codex Pet Dock"
        }

        statusLine.isEnabled = false
        previewItem.target = self
        windowFallbackItem.target = self

        let productNote = NSMenuItem(
            title: "The pet is supplied by Codex; this app only draws the dock",
            action: nil,
            keyEquivalent: ""
        )
        productNote.isEnabled = false

        let requestPermission = NSMenuItem(
            title: "Request Accessibility permission",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        requestPermission.target = self

        let openSettings = NSMenuItem(
            title: "Open Accessibility settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openSettings.target = self

        let quitItem = NSMenuItem(
            title: "Quit Codex Pet Dock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(productNote)
        menu.addItem(.separator())
        menu.addItem(requestPermission)
        menu.addItem(openSettings)
        menu.addItem(previewItem)
        menu.addItem(windowFallbackItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func updateStatus(_ status: String) {
        if Thread.isMainThread {
            applyStatus(status)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyStatus(status)
            }
        }
    }

    private func applyStatus(_ status: String) {
        statusLine.title = status
        statusItem.button?.toolTip = "Codex Pet Dock — \(status)"
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func togglePreview(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        onTogglePreview?(sender.state == .on)
    }

    @objc private func toggleWindowFallback(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        onToggleWindowFallback?(sender.state == .on)
    }

    @objc private func quit() {
        onQuit?()
    }
}
