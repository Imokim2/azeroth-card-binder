# Companion app

The Windows desktop app that watches the add-on's saved-data file, uploads new ledger events to the server and writes the file the add-on reads back. Built in Phase B of [docs/ROADMAP.md](../docs/ROADMAP.md). The contracts it follows are [docs/LEDGER-SPEC.md](../docs/LEDGER-SPEC.md), [docs/API.md](../docs/API.md) and [packages/shared/](../packages/shared/).

**What exists:** the app's core, tested end to end, with no window yet. **What does not:** the Electron shell (window, tray, installer, auto-update), the Discord sign-in, the in-game link code, and keeping the private key in the operating system's keychain. Those need Electron installed and a real screen to check; see roadmap B5 and B7 to B10.

```
src/luaTable.ts    reads the game's SavedVariables text without running it (strict, size and depth limits)
src/binderFile.ts  the add-on's saved data as the app needs it: unacknowledged events and the snapshot
src/client.ts      register a key; upload in batches with retries, backoff and Retry-After; resync; fetch the tape and the standings
src/signIn.ts      Discord sign-in: opens the browser, catches the one-time code on a loopback address, registers the key
src/identity.ts    the Ed25519 key pair, made once, kept through a SecretStore (the keychain, in the finished app)
src/syncFile.ts    writes Data/Sync.lua: numbers and hashes only, validated before writing
src/files.ts       finds the game folder, writes files atomically, waits for the game to finish writing
src/engine.ts      the sync loop: upload, tape, standings, Sync.lua; runs on every change of the game's file
test/              the parser, and the whole loop with the real Lua add-on and the real server
```

## How it works

The add-on keeps every ledger event in its saved-data file until the server has acknowledged it, so **the file is the upload queue**. After a failure, the next sync sends whatever is still unacknowledged; there is nothing else to lose or to get out of step. Uploads are safe to repeat, so a reply lost on the way cannot double anything. When the server acknowledges events, the app writes the acknowledgement into `Data/Sync.lua`; at the player's next login the add-on drops those events.

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
