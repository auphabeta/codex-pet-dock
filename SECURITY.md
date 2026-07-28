# Security

## Supported channel

Only the latest published Preview or Stable release receives security fixes.
Source snapshots and third-party repackages are not supported release channels.

## Trust boundary

Codex Pet Dock does not inject code into Codex, patch `app.asar`, edit the Codex
installation, or copy authentication credentials. It communicates with the
official local `codex app-server` process and uses read-only Windows window/UI
automation APIs.

Custom themes are not executable. The local theme loader accepts only a bounded,
allowlisted JSON manifest and one PNG in the same canonical directory. Scripts,
CSS, JavaScript, commands, URLs, symbolic links/reparse points, absolute paths,
path traversal, oversized files, and unsafe dimensions are rejected. Archive
import and remote theme download are not implemented.

Theme Studio writes only the same allowlisted manifest and local PNG contract.
Saving signals the running Dock through a local named event; it does not load
plugins, invoke theme commands, or contact a remote service.

## Reporting

Do not open a public issue containing credentials, local paths, session data, or
screenshots with private content. Until a dedicated private reporting channel is
published, disclose only a minimal reproduction and redact all personal data.

## Release requirements

A public Stable release must provide a reproducible build workflow, SHA-256
checksums, dependency inventory, malware scan results, and Authenticode signing.
Users must never be instructed to disable antivirus or Windows security checks.
