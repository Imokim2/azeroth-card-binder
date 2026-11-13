# Companion startup checks

Companion 0.4.4 dynamically required the shared JavaScript reference ledger from recovery.ts. The build uses allowJs=false, so TypeScript did not include that dependency. Repository tests found the source file and passed; an installed ASAR could not find it and the whole app failed at import time.

Companion 0.4.5 statically imports the existing portable TypeScript chain validator. TypeScript follows and emits that dependency and its crypto module. Recovery checks stay the same, with an asynchronous plan function. No save or protocol migration is involved.

The build script removes only app/dist before compiling, so old outputs cannot hide missing files. A regression check copies only compiled output into a temporary directory outside the repository and imports the startup graph there.

`npm run dist` now finishes with `npm run check:package`. This extracts the actual app.asar into an isolated temporary folder, validates imports, renderer/preload files and catalog, then starts the real packaged Windows executable with `--warcards-smoke-test`. A successful main process, preload bridge and rendered interface must produce a version/catalog-matching proof file before exiting. The release job cannot upload/publish the installer if this fails.

Smoke mode requires a separate WARCARDS_DATA directory and a loopback-only server. It stays hidden, creates no tray icon, does not change Windows startup settings and cannot use a player's saved game folder or account. Its profile and extracted files are removed afterwards. The original published 0.4.4 installer is rejected by this check before any executable is launched.
