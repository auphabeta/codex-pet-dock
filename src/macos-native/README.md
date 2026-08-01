# Codex Pet Dock — macOS native prototype

This directory contains the Swift/AppKit desktop-attachment prototype for the
`feature/macos-native` branch. It does not modify Codex, inject into its
renderer, or read authentication files.

## Implemented

- menu-bar application with no Dock icon;
- transparent, non-activating AppKit dock panel;
- Codex process discovery through `NSWorkspace`;
- top-level Codex window discovery through Quartz;
- precise pet-element discovery through macOS Accessibility (`AXUIElement`);
- fallback attachment to the smallest matching Codex window when AX metadata is
  unavailable;
- periodic dock tracking and safe hiding when Codex disappears;
- optional movement of the Codex host window when the AX position attribute is
  writable;
- an offline preview mode for testing the AppKit overlay without Codex.

Quota and token values intentionally remain `--` in this prototype. The Windows
app-server client and token aggregation algorithm should be migrated into a
shared data layer after the attachment contract is validated on real macOS
Codex builds.

## Requirements

- macOS 13 or newer;
- Xcode 15 or newer, or a matching Swift toolchain;
- Codex for macOS installed and running;
- Accessibility permission for precise pet-element tracking and host-window
  movement.

## Run from source

```bash
cd src/macos-native
swift build
swift run CodexPetDockMacOS
```

The process runs as a menu-bar accessory. Open the paw menu and choose
`Request Accessibility permission`, then enable the built executable in:

```text
System Settings → Privacy & Security → Accessibility
```

Use `Preview dock without Codex` to verify the transparent AppKit panel before
permission is granted.

## Current prototype limitations

- Accessibility identifiers exposed by Codex may vary between releases. The
  locator scores `AXIdentifier`, `AXDOMIdentifier`, title, description, help,
  role description, size, and proximity to the detected Codex window.
- The top-left-to-AppKit coordinate conversion is validated for the primary
  display. Vertical multi-display arrangements require a display-aware
  conversion before release packaging.
- The fallback window matcher is conservative but may attach to another small
  Codex utility window when Accessibility data is unavailable.
- Dragging only moves the official host window when macOS reports its
  `AXPosition` attribute as writable.
- The prototype is an executable Swift package, not yet a signed/notarized
  `.app` or `.dmg`.

## Next steps

1. Validate AX identifiers and window geometry against the current Codex macOS
   release and record stable fixtures.
2. Add display-aware coordinate conversion and AX window-change observers.
3. Port `account/read`, `account/rateLimits/read`, and local token aggregation.
4. Load the existing theme manifest and PNG assets from a shared resource
   target.
5. Add an Xcode application target, login-item support, signing, notarization,
   and release packaging.
