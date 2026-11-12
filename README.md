# World of Warcards

A collectible card add-on for **World of Warcraft: Forever**. Defeat neutral and hostile creatures and gather herbs and ore to find cards, fill a binder set by set, open card packs, trade spares with other players, and race everyone else up a global, server-checked ladder.

> A free fan project. It is not affiliated with or endorsed by Blizzard Entertainment.

**Website and downloads:** <https://worldofwarcards.co.uk>

## The three parts

| Part | What it does | Where |
|---|---|---|
| **The add-on** | Your in-game binder: cards, sets, achievements, packs, trading and the ladder tab. | `AzerothCardBinder/` |
| **The companion app** | A Windows app that reads the add-on's saved data after a reload, uploads it, brings back Ranked roll tape and standings, and can install updates. | `app/` |
| **The server** | A Cloudflare Worker and D1 database that check every Ranked drop, run the ladder and serve the website. | `server/` |

The add-on folder is called `AzerothCardBinder`. The name is historical and stays, because the saved-data name, the card-link prefix and the install path all depend on it. The name players see is World of Warcards.

## Install (players)

1. Download the **add-on ZIP** and the **companion installer** from the [website](https://worldofwarcards.co.uk/download) or the project's GitHub *Releases* page.
2. Close the game and extract the `AzerothCardBinder` folder from the ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. Enable it on the character screen, then click the book on the minimap or type `/acb`.
3. Run the companion installer (Windows 64-bit, installs for your user, no administrator rights). It is **not code-signed yet**, so Windows may warn about an unknown publisher. Sign in with Discord, choose your game folder, then `/reload` in the game so it syncs.

Casual play works without the companion. Ranked play needs it. Each release lists SHA-256 checksums so a download can be checked. The first-playtest notes are in [AzerothCardBinder/PLAYTEST.md](AzerothCardBinder/PLAYTEST.md).

## How Ranked stays fair

Ranked random numbers come from a "roll tape" the server issues and the server checks every attempt against it. The ledger of everything you collect is hash-chained and signed with a key that stays on your computer. The format is in [docs/LEDGER-SPEC.md](docs/LEDGER-SPEC.md), the rules players are held to in the website's [fair-play guide](https://worldofwarcards.co.uk/fair-play), and what the service stores in the [privacy page](https://worldofwarcards.co.uk/privacy).

## Develop

You need [LuaJIT](https://luajit.org) (the tests use Lua 5.1 semantics, as WoW does) and [Node.js](https://nodejs.org) 24 or later.

```
luajit tests/run.lua           the add-on tests, with a mocked WoW API
node tools/release.js check    syntax-check every Lua and JavaScript file and the add-on's file list
node tools/release.js test     the add-on tests and the shared-contract tests
node tools/release.js build    check, test, then build dist/AzerothCardBinder-<version>.zip
(cd server && npm ci && npm test)    the server tests
(cd app && npm ci && npm test)       the companion app tests (npm run dist builds the installer)
```

The tests never start WoW. Anything that depends on the real client (tooltips, sounds, fonts, models, two-player trading) has to be checked in game; the checklist is in [docs/ROADMAP.md](docs/ROADMAP.md#6-testing).

## Layout

| Folder | What is in it |
|---|---|
| `AzerothCardBinder/` | The add-on, installed as it is |
| `app/` | The Windows companion app (Electron and TypeScript) |
| `server/` | The Cloudflare Worker, its database migrations and the website pages |
| `packages/shared/` | Contracts shared by the add-on, server and app: the ledger rules, the card catalog and test vectors |
| `tests/` | Offline Lua and shared-contract tests |
| `tools/` | Scripts that build the card catalog, the release, signed manifests and database backups |
| `docs/` | Roadmap, specifications, decision records and runbooks |

## Where to read next

- [docs/ROADMAP.md](docs/ROADMAP.md): the plan, with phases, tasks and risks.
- [docs/LEDGER-SPEC.md](docs/LEDGER-SPEC.md) and [docs/API.md](docs/API.md): the ledger format and the server's API.
- [docs/adr/](docs/adr/): why the big decisions were made.
- [docs/runbooks/](docs/runbooks/): releasing, backups and alerts.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to make a change. [SECURITY.md](SECURITY.md): how to report a vulnerability.
- [CREDITS.md](CREDITS.md): where the data comes from.

## Licence

Copyright (C) 2026 the World of Warcards contributors. Free software under the **GNU General Public License, version 3 or (at your option) any later version**: see [LICENSE](LICENSE). The generated creature and node catalogs are built from data that is itself GPL-licensed (see [CREDITS.md](CREDITS.md)). Game names and the Forever name belong to their owners and are used only to say what this is for.
