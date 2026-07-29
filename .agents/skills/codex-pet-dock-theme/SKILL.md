---
name: codex-pet-dock-theme
description: Create, refine, validate, and install a safe custom visual base for Codex Pet Dock from a user's idea, screenshot, or transparent PNG. Use when a user asks Codex to design a Pet Dock theme, turn a visual prompt into a dock base, fix pet contact or metric readability in a custom base, or install a data-only theme without editing Codex or Pet Dock source.
---

# Create a Codex Pet Dock theme

Turn the user's visual direction into one installed, data-only theme. Make the
experience feel like choosing a design, not filling in a technical form; handle
names, geometry, files, and validation yourself.

## Workflow

1. Locate this Pet Dock workspace from the current directory. Read
   `docs/custom-themes.md` and the local
   `%LOCALAPPDATA%\CodexPetDock\themes\theme.example.json` when it exists.
2. Keep the creative interaction effortless:
   - If the request is open-ended, offer exactly three distinct directions.
     Give each a short name, style, palette, material, and one-sentence visual
     description, then ask the user to pick one.
   - If the user already gave a concrete direction or reference image, use it
     directly instead of asking them to repeat it.
   - Never ask the user for dimensions, coordinates, manifest fields, or a
     theme ID. Derive the display name and stable lowercase ID yourself.
   - Ask one concise follow-up only when a missing visual choice would
     materially change the result.
3. If image generation or editing is available, create a real transparent PNG
   containing only the base. Prefer a 896x288 source for a 224x72 runtime base.
   Otherwise ask the user for a transparent PNG and pause.
4. Work in a temporary directory first. Create only `platform.png` and
   `theme.json`. Calibrate the visible contact surface, overlap, shadow, metric
   offset, scrim, and accent from the actual artwork.
5. Validate the image alpha channel, transparent corners, size, dimensions,
   safe file name, manifest whitelist, contact geometry, and text area.
6. Copy the candidate to a temporary `ConfigDirectoryOverride\themes\<id>`
   and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy RemoteSigned `
     -File .\src\Start-CodexPetQuota.ps1 `
     -ThemeSwitchDiagnostics -AllowMultipleInstances `
     -ConfigDirectoryOverride <temporary-config-directory>
   ```

   Require the target theme to report successful switching, persistence,
   layout, alpha coverage, contact fit, and native pet-window drag delegation.
7. Only after validation, install the two files under
   `%LOCALAPPDATA%\CodexPetDock\themes\<id>`. If that directory already exists,
   show the files that would be replaced and obtain confirmation first.
8. Signal the named event `Local\CodexPetDock.ReloadThemes` when it exists.
   Otherwise tell the user to choose `Reload custom themes` from the tray.
9. Report the installed paths, image dimensions and alpha result, validation
   result, and how to select the theme.

## Hard boundaries

- Never modify the Codex installation, `app.asar`, official pet assets, Codex
  settings, authentication data, or shortcuts.
- Never modify Pet Dock source to create a user theme.
- Never read or expose `auth.json`, access tokens, or conversation contents.
- A theme may contain one local PNG and one schema-version-1 JSON manifest only.
  Reject scripts, CSS, JavaScript, commands, URLs, dependencies, absolute asset
  paths, path traversal, reparse points, and undocumented manifest fields.
- Do not silently overwrite an existing theme.
- Do not fake transparency with a white, checkerboard, or color-key background.
- Do not put labels, metric values, logos, or watermarks in the artwork; Pet
  Dock draws live metrics.
- Do not install an unvalidated placeholder merely to finish the task.

## Visual quality

Make the pet and base read as one object: provide a continuous landing surface,
a subtle contact shadow, a small foot overlap, and coherent lighting. Keep the
front metric face dark or backed by a restrained scrim. Preserve two clear
columns for `WEEK LEFT` and `WEEK TOKENS`, including at Windows 125%-200% scale.
