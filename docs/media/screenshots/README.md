# Screenshot library

Stable, original PNG captures for the Codex Pet Dock README, release notes,
articles, and social posts. These files are copied from the user's source
captures without resizing or recompression.

Captured: 2026-07-29

## Recommended use

- Hero image: `capybara-holo-cyan-details.png`
- Alternate hero: `capybara-moon-lotus-details.png`
- Theme gallery: use the eight `capybara-*` images
- Pet switching demo: compare the three `pet-switch-*-holo-cyan-*` pets
- Animation compatibility demo: use the standing, sitting, and running girl captures
- Custom-theme article: pair one detail screenshot with the Theme Studio flow
- Exact dimensions and SHA-256 values: see `manifest.json`

Before publishing publicly, decide whether to keep or blur the exact Token
totals and reset time. The screenshots do not show an account name, email,
prompt, or conversation content.

## Gallery

### Holo Cyan 3D

![Capybara pet on the Holo Cyan base with the quota detail panel](capybara-holo-cyan-details.png)

### Holo Amber 3D

![Capybara pet on the Holo Amber base with the quota detail panel](capybara-holo-amber-details.png)

### Princess Cradle

![Capybara pet on the Princess Cradle base](capybara-princess-cradle.png)

### Forest Rune

![Capybara pet on the Forest Rune base](capybara-forest-rune.png)

### Clockwork Brass

![Capybara pet on the Clockwork Brass base with the quota detail panel](capybara-clockwork-brass-details.png)

### Moon Lotus

![Capybara pet on the Moon Lotus base with the quota detail panel](capybara-moon-lotus-details.png)

### Sakura Shrine

![Capybara pet on the Sakura Shrine base with the quota detail panel](capybara-sakura-shrine-details.png)

### Iron Throne

![Capybara pet on the Iron Throne base with the quota detail panel](capybara-iron-throne-details.png)

## Pet switching with the base preserved

These captures demonstrate that the pet and the metric base have independent
lifecycles. Users can switch the Codex pet while the selected base theme,
quota values, and detail card remain in place. The same base can therefore
support built-in and custom pets without modifying the pet package.

For a concise README comparison, place the following three Holo Cyan captures
side by side:

1. `pet-switch-girl-holo-cyan-details.png`
2. `pet-switch-codex-holo-cyan-details.png`
3. `pet-switch-flame-holo-cyan-compact.png`

### Girl pet on Holo Cyan

![Girl pet on the unchanged Holo Cyan base with the quota detail panel](pet-switch-girl-holo-cyan-details.png)

### Codex pet on Holo Cyan

![Codex robot pet on the same Holo Cyan base with the quota detail panel](pet-switch-codex-holo-cyan-details.png)

### Flame pet on Holo Cyan

![Flame pet on the same Holo Cyan base](pet-switch-flame-holo-cyan-compact.png)

### Codex pet, compact presentation

![Codex robot pet on the Holo Cyan base without the expanded card](pet-switch-codex-holo-cyan-compact.png)

## Pet animation and different bases

The following captures show that standing, sitting, and running poses can
change without separating the base from the pet.

### Girl pet standing on Sakura Shrine

![Girl pet standing on the Sakura Shrine base](pet-switch-girl-sakura-standing-details.png)

### Girl pet sitting on Sakura Shrine

![Girl pet sitting on the Sakura Shrine base](pet-switch-girl-sakura-sitting-details.png)

### Girl pet running on Princess Cradle

![Girl pet running on the Princess Cradle base](pet-switch-girl-princess-running-details.png)

### Girl pet sitting on Princess Cradle

![Girl pet sitting on the Princess Cradle base](pet-switch-girl-princess-sitting-details.png)

## How users add a custom base

No source-code changes are required.

1. Right-click the Codex Pet Dock tray icon.
2. Choose `Base theme` -> `Create or edit custom base...`.
3. Select a transparent PNG.
4. Adjust runtime size, the dashed pet contact surface, overlap, metric offset,
   scrim strength, compact text, and accent color.
5. Choose `Save & reload`.
6. Select `Custom - <theme name>` from the `Base theme` menu.

Advanced authors may place `theme.json` and `platform.png` under:

```text
%LOCALAPPDATA%\CodexPetDock\themes\<theme-id>\
```

Then choose `Reload custom themes`. Custom themes are data-only: scripts,
commands, URLs, CSS, and JavaScript are rejected. See
[`../../custom-themes.md`](../../custom-themes.md) for the complete manifest.
