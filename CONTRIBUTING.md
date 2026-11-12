# Contributing

World of Warcards is meant to be maintained for years, so changes are held to a few simple rules. They are short on purpose.

## Before you start

- Read [README.md](README.md) and the part of [docs/ROADMAP.md](docs/ROADMAP.md) your change belongs to.
- A change to how the ledger, hashing, signing or uploads work starts in [docs/LEDGER-SPEC.md](docs/LEDGER-SPEC.md) and the shared vectors, not in code. See [packages/shared](packages/shared/).
- A significant decision (a new dependency, a new service, a change to a rule players feel) gets a short decision record in [docs/adr/](docs/adr/) in the same pull request.

## Making a change

1. Branch from `main` with a short descriptive name, for example `ledger-chain` or `fix-trade-timeout`.
2. Make the change and its tests together. The add-on is tested offline; run all of it with:

   ```
   node tools/release.js check          syntax-check every Lua and JavaScript file
   luajit tests/run.lua                 the add-on tests (the files are in tests/parts; list a new one in tests/run.lua)
   node --test tests/vectors.test.js    the shared-contract tests
   ```

   `node tools/release.js build` runs all three and builds the install ZIP. The server and the companion app have their own tests: `cd server && npm test` and `cd app && npm test`. Continuous integration runs the same checks on every pull request, and a pull request cannot merge while they fail.
3. Anything the offline tests cannot reach (tooltips, sounds, fonts, models, two-player trading, the Settings tab) must be checked in game. Say what you checked in the pull request. The checklist is in [docs/ROADMAP.md](docs/ROADMAP.md#6-testing).
4. Open a pull request using the template. Keep it to one idea; a reviewer should be able to read it in one sitting.

## Code rules

- **Add-on:** Lua 5.1, as WoW uses. No new global variables; share code through the `ACB` table. Wrap calls to game APIs that may be missing or return protected values with the existing helpers (`ACB.read`, `safe`).
- **Size:** a Lua file over about 400 lines, or a TypeScript file over about 300, is split before new code goes in. Pure data files (the generated catalogs and the lore tables) are exempt.
- **Server and app (when they exist):** TypeScript in strict mode, formatted and linted in continuous integration.
- **Tests:** a new feature needs a test. Core modules (the ledger, hashing, scoring, saved-data migrations) are not merged without tests. Fix a bug by adding the test that would have caught it.
- **Saved data:** the saved-variables name `AzerothCardBinderDB`, the folder name `AzerothCardBinder` and the card keys never change. A change to the saved-data layout is a numbered migration with a fixture file for the old layout.
- **Comments:** say why, not what. The existing files are the style guide.
- **Dependencies:** few, pinned, and each one explained in the pull request that adds it.

## Data tools

The card catalog is generated, never edited by hand. The scripts in [tools/](tools/) and how to run them are described in [CREDITS.md](CREDITS.md). Regenerate, read the diff, and run the tests before committing a new catalog.

## Commit messages

A short imperative first line saying what the commit does ("Add the ledger hash chain"), then a few lines on why if it is not obvious.

## Releases

`node tools/release.js build` produces `dist/AzerothCardBinder-<version>.zip`. Bump the version with `node tools/release.js bump <version>`, which updates the `.toc` and `CHANGELOG.md`. Every release gets a line in the changelog.
