# Custom base themes

Codex Pet Dock supports local, data-only custom bases. A custom theme cannot run
code and cannot modify Codex.

## Quick start

For most users:

1. Open the tray menu.
2. Choose `Base theme` → `Create or edit custom base...`.
3. Browse to a transparent PNG.
4. Adjust the dashed contact surface and metric geometry in the live preview.
5. Choose `Save & reload`.
6. Select `Custom - <theme name>` from `Base theme`.

For manual authoring, choose `Open custom themes folder`, create one
subdirectory, and place `theme.json` plus one PNG inside it. Choose
`Reload custom themes` after editing; restarting the application is not required.

The application creates `theme.example.json` in the custom theme root. Copy its
contents into the new subdirectory as `theme.json`.

```text
%LOCALAPPDATA%\CodexPetDock\themes\
  theme.example.json
  my-cyber-base\
    theme.json
    platform.png
```

## Manifest

```json
{
  "schemaVersion": 1,
  "id": "creator.my-cyber-base",
  "name": "My Cyber Base",
  "asset": "platform.png",
  "width": 224,
  "height": 72,
  "contactSurfaceY": 20,
  "contactOverlap": 7,
  "contentOffsetY": 2,
  "contactShadow": true,
  "contactShadowY": 18,
  "compactMetrics": false,
  "metricsScrimOpacity": 120,
  "accent": "#6FE8EF"
}
```

| Field | Meaning |
|---|---|
| `id` | Stable lowercase ID. Use an author prefix to avoid conflicts. |
| `name` | Display name shown in the tray menu. |
| `asset` | PNG file name in the same directory. |
| `width` / `height` | Runtime window size, normally `224 × 72`. |
| `contactSurfaceY` | Y position of the visible surface where the pet stands. |
| `contactOverlap` | Visual overlap with the pet, normally `7`. |
| `contentOffsetY` | Vertical offset for the two metric rows. |
| `contactShadowY` | Y position of the pet contact shadow. |
| `compactMetrics` | Use the compact value font for short front panels. |
| `metricsScrimOpacity` | Dark readability backing from `0` to `220`. |
| `accent` | Progress and edge highlight in `#RRGGBB`. |

Recommended source image:

- transparent PNG;
- 896 × 288 for a normal 224 × 72 theme;
- keep the metric face opaque;
- keep decorative detail away from the two value columns;
- test at Windows 100%, 125%, 150%, and 200% scale.

## Security limits

The loader accepts only the documented manifest fields and one local PNG.
Unknown fields are rejected. In particular, scripts, CSS, JavaScript, commands,
URLs, absolute paths, parent-directory traversal, symbolic links, oversized
files, and unsafe dimensions are not accepted.

An invalid custom theme is skipped and recorded in
`%LOCALAPPDATA%\CodexPetDock\sidecar.log`; the application continues with the
last valid or default built-in theme.
