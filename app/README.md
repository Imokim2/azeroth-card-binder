# Companion app

The Windows desktop app that watches the add-on's saved-data file, uploads new ledger events to the server and writes the file the add-on reads back. Built in Phase B of [docs/ROADMAP.md](../docs/ROADMAP.md). The contracts it follows are [docs/LEDGER-SPEC.md](../docs/LEDGER-SPEC.md), [docs/API.md](../docs/API.md) and [packages/shared/](../packages/shared/).

**What exists:** the app's core, tested end to end, an Electron window and tray around it, and a per-user Windows installer build (see below). The dashboard walks a player through signing in with Discord, choosing the game folder and watching the sync; the private key is kept encrypted by the operating system (Electron's `safeStorage`). **Still needed:** code signing, automatic updates, and a full live sign-in and in-game sync playtest. The dashboard has been checked with sample account data at desktop and narrow window sizes, including its setup, connected, error and new-binder screens.

```
src/luaTable.ts    reads the game's SavedVariables text without running it (strict, size and depth limits)
src/binderFile.ts  the add-on's saved data as the app needs it: unacknowledged events and the snapshot
src/client.ts      register a key; upload in batches with retries, backoff and Retry-After; resync; fetch the tape and the standings
src/signIn.ts      Discord sign-in: opens the browser, catches the one-time code on a loopback address, registers the key
src/identity.ts    the Ed25519 key pair, made once, kept through a SecretStore (the keychain, in the finished app)
src/syncFile.ts    writes Data/Sync.lua: numbers and hashes only, validated before writing
electron/main.ts   the Electron shell: window, tray, folder dialog, opening the browser, key protection
electron/preload.cjs the fixed list of things the window may ask for
electron/renderer/ the screen (HTML, CSS and plain JavaScript; text is only ever put on the page as text)
src/controller.ts  what the app does, with no window: settings, sign-in, folder, engine, status (tested)
src/settings.ts    the app's own settings file
src/secrets.ts     keeping the key encrypted on disk
src/files.ts       finds the game folder, writes files atomically, waits for the game to finish writing
src/engine.ts      the sync loop (it also notices a saved binder that does not continue the server's, so the player can be offered a new binder): upload, tape, standings, Sync.lua; runs on every change of the game's file
test/              the parser, and the whole loop with the real Lua add-on and the real server
```

## How it works

The add-on keeps every ledger event in its saved-data file until the server has acknowledged it, so **the file is the upload queue**. After a failure, the next sync sends whatever is still unacknowledged; there is nothing else to lose or to get out of step. Uploads are safe to repeat, so a reply lost on the way cannot double anything. When the server acknowledges events, the app writes the acknowledgement into `Data/Sync.lua`; at the player's next login the add-on drops those events.

## Run it

Needs Node 24 or later. From this folder:

```
npm ci
npm start
```

`npm start` compiles the TypeScript to `dist/` and opens the window. Closing the window sends the app to the tray; **Quit** is in the tray menu. Settings and the encrypted key live in `%APPDATA%World of Warcards`. Set `WARCARDS_DATA` to use another data folder, and `WARCARDS_SERVER` to use another server (the default is the staging server in `src/config.ts`).

## Build the installer

From this folder, with `npm ci` done once:

```
npm run pack      # an unpacked app in release/win-unpacked, to try without installing
npm run dist      # release/World of Warcards Setup <version>.exe
```

The installer is a per-user install (no administrator rights) of about 116 MB, most of it Electron itself. It is **not code-signed**, so Windows SmartScreen shows an "unknown publisher" warning the first time; signing needs a certificate, which costs money and is a decision for later. There is no auto-update yet: the repository is private, and updates need a public release feed or a token. The installed app finds the catalog as a resource beside the program (`resources/catalog.json`).

## Run the tests

Needs Node 24 or later and LuaJIT (the end-to-end tests run the real add-on code). No install is needed to run them:

```
node --test test/*.test.ts
```

Type-check (needs `npm ci` once):

```
npm ci
npm run typecheck
```

## Known gaps

- The parser is tested against files written by a serializer in `tests/tools/write-saved.lua` that follows the game's layout, and against the real Lua interpreter, but **not against a file the game itself wrote**. Add one to the tests the first time a real file can be shared.
- The folder layout of World of Warcraft: Forever (where `WTF` and `Interface` live) is not confirmed. `findGameFolders` looks for `WTF/Account` up to two levels below a folder the player picks.
