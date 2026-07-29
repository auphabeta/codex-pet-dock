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
     description.
     **🔴 CHECKPOINT — visual direction:** stop and wait for the user to pick
     one. Do not generate or install a theme before the choice.
   - If the user already gave a concrete direction or reference image, use it
     directly instead of asking them to repeat it.
   - Never ask the user for dimensions, coordinates, manifest fields, or a
     theme ID. Derive the display name and stable lowercase ID yourself.
     Prefix it with the repository owner when available, otherwise `local`.
   - Ask one concise follow-up only when a missing visual choice would
     materially change the result.
3. Generate a real transparent PNG containing only the base, preferably
   896x288 for a 224x72 theme. Follow the active image tool's alpha workflow;
   chroma is only an intermediate. If image tools are unavailable, ask for one
   transparent PNG and stop.
4. Work in a temporary directory. Keep intermediates outside the final
   candidate, normalize its aspect ratio, and put exactly `platform.png` and
   `theme.json` inside. Calibrate contact, overlap, shadow, metric offset,
   scrim, and accent from the artwork.
5. Validate the image alpha channel, transparent corners, size, dimensions,
   safe file name, manifest whitelist, contact geometry, and both text areas.
   Parse `theme.json` with the installed runtime before copying it anywhere.
6. Copy the candidate to a temporary `ConfigDirectoryOverride\themes\<id>`
   and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy RemoteSigned `
     -File .\src\Start-CodexPetQuota.ps1 `
     -ThemeSwitchDiagnostics -AllowMultipleInstances `
     -ConfigDirectoryOverride <temporary-config-directory>
   ```

   Parse the JSON report and select the target theme result. Pass only when
   `ok`, `switched`, `persisted`, `layoutFits`, `controlSizeFits`, `fontFits`,
   `contactFits`, and `dragDelegatesToPet` are true and `alphaCoverage >= 0.95`.
   Do not lower a threshold to make a candidate pass.
7. Only after validation, install the two files under
   `%LOCALAPPDATA%\CodexPetDock\themes\<id>`.
   **🔴 CHECKPOINT — overwrite:** if that directory already exists, show the
   current and candidate `platform.png` and `theme.json` with sizes and hashes,
   then stop for confirmation. If declined, install under a newly derived ID
   or leave the existing theme untouched.
8. Signal the named event `Local\CodexPetDock.ReloadThemes` when it exists.
   If it does not exist, use `Reload custom themes` from the tray and confirm
   the target appears in the catalog.
9. If a pet is visible, select the theme without editing Codex, inspect its
   contact, two metrics, and expanded card, then restart only Pet Dock once and
   confirm restoration. If unsafe or unavailable, mark this check pending and
   give the exact tray path.
10. Report paths, dimensions, alpha corners, diagnostic fields, repair rounds,
    reload, visual and restart results, plus the selection path.

## Validation recovery

Make at most three candidate rounds. Each round changes only the failing
property, then reruns the complete temporary diagnostic.

| Trigger | One repair | If it still fails |
|---|---|---|
| Missing alpha or opaque corners | Redo generation or background removal | Stop; do not install |
| `alphaCoverage < 0.95` | Move content or strengthen the opaque metric face | Stop after round three; keep the threshold |
| `contactFits` is false | Recalibrate contact, overlap, and shadow from visible pixels | Stop and report the gap |
| Layout or font fails | Recalibrate geometry; use compact text only for a short panel | Stop and report the field |
| Switch, persistence, or drag fails | Recheck the manifest and rerun in a clean temporary config | Stop as incompatible |
| Reload or visual check fails | Report the step and tray recovery path | Do not claim end-to-end success |

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
