# World of Warcards

A collectible card add-on for World of Warcraft: Forever. Defeat neutral and hostile creatures and gather herbs and ore to find cards, fill a binder set by set, trade spares with other players, and (planned) race everyone else to complete the whole collection.

The add-on folder is `AzerothCardBinder/`. The name is historical and stays, because the saved-data name, the card-link prefix and the install path all depend on it. The name players see is World of Warcards.

## Install (players)

Copy the `AzerothCardBinder` folder into `World of Warcraft/_forever_/Interface/AddOns/`, enable it on the character screen, then click the book on the minimap or type `/acb`. The first-playtest notes are in [AzerothCardBinder/PLAYTEST.md](AzerothCardBinder/PLAYTEST.md).

## Develop

You need [LuaJIT](https://luajit.org) (the tests use Lua 5.1 semantics, as WoW does) and [Node.js](https://nodejs.org) for the data tools.

```
luajit tests/run.lua          run every offline test with a mocked WoW API
node tools/release.js check   syntax-check every Lua and JavaScript file
node tools/release.js build   run the checks and tests, then build the install ZIP
```

The tests never start WoW. Anything that depends on the real client (tooltips, sounds, fonts, models, two-player trading) has to be checked in game; the checklist is in [docs/ROADMAP.md](docs/ROADMAP.md#6-testing).

## Layout

| Folder | What is in it |
|---|---|
| `AzerothCardBinder/` | The add-on, installed as it is |
| `tests/` | Offline Lua tests |
| `tools/` | Scripts that build the card catalog and the release |
| `docs/` | Roadmap, specifications, decision records and runbooks |
| `packages/shared/` | Contracts shared by the add-on, server and app: schemas and test vectors |
| `server/` | The planned ranking server (not built yet) |
| `app/` | The planned companion desktop app (not built yet) |

## Where to read next

- [docs/ROADMAP.md](docs/ROADMAP.md): the plan from here to a global, competitive collection race, with phases, tasks and risks.
- [docs/LEDGER-SPEC.md](docs/LEDGER-SPEC.md): the exact format of the tamper-evident ledger.
- [docs/adr/](docs/adr/): why the big decisions were made.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to make a change.
- [CREDITS.md](CREDITS.md): where the data comes from.
