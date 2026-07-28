# Privacy

Codex Pet Dock is a local Windows sidecar. It does not upload telemetry, create
an account, or operate a remote service.

The Preview reads only the minimum local data required for its visible metrics:

- the official Codex `account/read` and `account/rateLimits/read` responses;
- `token_count` events and timestamps from local Codex session JSONL files;
- the screen bounds of the official Codex pet window and avatar element.

It does not read or export conversation text, prompts, generated answers,
`auth.json`, access tokens, refresh tokens, account email, or browser data.

Local state is stored under `%LOCALAPPDATA%\CodexPetDock`. It contains the
selected theme, optional user-provided custom theme PNG/JSON files, and a bounded
diagnostic log. Removing that directory resets Codex Pet Dock. Uninstall keeps
it by default so upgrades do not lose settings or custom themes.

The weekly token number is a local activity estimate. It is not billing data and
does not include sessions that have already been removed from the computer.
