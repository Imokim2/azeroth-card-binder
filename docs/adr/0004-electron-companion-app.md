# 0004. The companion app is Electron, Windows first

Status: Accepted
Date: 2026-11-10

## Context

The add-on cannot reach the internet. A desktop app has to read its saved-data file, upload new events and write a data file back, in the way TradeSkillMaster's app does.

## Decision

Build the app with Electron and TypeScript, for Windows first, with auto-update through GitHub Releases. The private key lives in the operating system's keychain.

## Alternatives considered

- Tauri: smaller installer, but the team would need Rust.
- A .NET app: good Windows integration, but a second language and no shared code with the server.

## Consequences

The installer is large. The shared reference code in `packages/shared` can be reused directly. Code signing is a separate decision before public launch.
