# Guild binders: design draft

Status: implemented for addon 1.0.15, companion 1.0.3 and server 1.0.2. Harry's service, membership and donation work is merged in PR #66. The Guild tab, shared inventory bridge, guild ladder and admin review page complete the UI. The decisions below describe the shipped flow; deployment enables guilds after migrations 0015–0017.

## Decisions taken

| Question | Decision |
|---|---|
| Who counts as a member | One enrolled guild per Ranked account, approved by that guild's owner (the proposal's suggestion, chosen 15 November 2026). |
| Who creates a guild | A Ranked player creates the guild binder immediately and becomes its owner. The owner approves member applications; website approval is not required. |
| Donations | Permanent, as in the proposal. Nobody withdraws, including the owner. |

## Membership

The server cannot see a game roster. A guild name in the add-on is a claim, so approval by the owner is the check, and the owner can look at the applicant's character in the real guild roster.

1. **Create.** The applicant asks (companion app or Discord) for a guild with realm, name and side. An admin approves it in the admin screen, which writes the audit row the admin actions already write. The guild gets a permanent id (a ULID, like players) and the applicant becomes its owner. Realm and display name are fields on the row, so a rename is an edit, never a new guild.
2. **Apply.** A Ranked player picks the guild in the companion app and names which of their registered characters is in it. Only characters already in the `characters` table can be named. A player with an enrolment or a pending application elsewhere cannot apply.
3. **Approve or refuse.** The owner sees pending applications in the companion app and decides. Approval makes the application an enrolment.
4. **Leave or remove.** A member can leave and the owner can remove a member. Neither touches past donations, which stay in the guild.
5. **Owner changes.** Admin only for now: transferring ownership and merging or closing a guild are rare, so they go through the admin screen and its audit log.

Rules that keep it honest:

- **One guild per account**, enforced by a unique index on the account, so alts of one account cannot enrol in several guilds. Alts held on separate accounts remain separate players, as they are everywhere else.
- **Faction.** A guild has one side, taken from the enrolling character's declared side (`mode/side`). The owner's character sets it at creation. Faction cards can be donated, since guilds are single-faction in the game.
- **A claim is never proof of rank.** The add-on may report `GetGuildInfo("player")` as a hint on the apply screen, and the server never relies on it.

## Donations

Tradeoff to confirm. The proposal says a failed donation leaves the card available. The bridge cannot give a live reply (saved data is exchanged on `/reload`), so the add-on must write the donor's debit before the server has agreed. The design therefore **escrows** the copy: it leaves the donor's binder at the click, the server then either credits the guild or returns the copy through a server-issued grant. A copy is never lost or duplicated, and a donation shows as pending until the server has settled it.

The shape follows season rewards, which already do exactly this for packs: the server issues a grant, the add-on writes a ledger event naming its id, and the upload redeems it once in the same transaction (`seasonReward`, `season_grants`, `season_redemptions`).

### Ledger (spec 11)

- New marker `mode/guild1`, written once like `launch1` and `faction1`. Donation events are refused before it, and the rules for earlier histories do not change, so every existing vector, pack check and upload replays unchanged.
- Two new kinds. `KINDS` in `packages/shared/src/ledger.js` is a closed list, so this needs a spec bump, vectors and the Lua tables.
  - `donate`: `key` is the exact card or edition, `partner` is the guild id, `trade` is a 32-hex operation id, `count` is the donor's copies afterwards (must be before minus one, like `tradeOut`).
  - `donateReturn`: the escrowed copy coming back. `trade` is the same operation id and `count` is before plus one. Valid only when the server has recorded that operation as refused.
- Both are Ranked-only, one copy per event (a quantity is several events), and `partner` names the target guild so a change of enrolment between the confirm screen and the upload cannot redirect a donation.

### Server

All of this is new tables; no existing table changes. Forward-only migrations, per the existing runbook.

- `guilds` (id, realm, name, side, owner_player_id, status, created_at).
- `guild_members` (guild_id, player_id, character, state: pending / active / removed, decided_at), with a unique index so a player has one live row.
- `guild_donations` (operation id primary key, guild_id, donor_player_id, key, seq, result: credited / refunded, at). The operation id is the retry guard: a repeat of the same upload finds the row and returns the original result.
- `guild_inventory` (guild_id, key, copies). Derived from credited donations, so it can be rebuilt.

Credit or refund is decided inside the ledger upload transaction, together with the donor's batch, so the personal debit, guild credit and receipt commit or fail as one (D1 batches are transactional). A donation is credited when the donor is an active member of the named guild and the copy is eligible; otherwise the server writes a refund result and issues the `donateReturn` grant.

Eligibility for credit matches what trading already trusts. A copy the trade-taint tracing (`server/src/taint.ts`) treats as untrusted does not count towards the guild's ladder score, and a donor who holds only untrusted copies of that card gets a refund. Rebuilds replay `donate` events using the stored result rows, because the decision depended on enrolment at the time and cannot be recomputed later.

New routes, all signed like `/v1/seasons`: apply, decide, leave, my guild (with pending donations), guild summary (members and inventory) and a cached guild leaderboard. Reads happen when the guild page opens or on refresh. There is no polling and a write only happens for an enrolment decision or a confirmed donation, as the proposal asks.

### Add-on and companion

- The companion app carries the enrolment screens and writes `guild` into `Data/Sync.lua` (guild id, name, role, status, pending donation results and refund grants). The add-on never calls the network.
- The add-on's Guild binder page reuses the trade card picker and confirmation styling. Donate appears only when the last sync shows an active enrolment. The confirmation names the card, edition, quantity and guild and says it cannot be undone.
- A donation shows as Pending until the next sync says credited or refunded. Credited clears it, refunded writes the `donateReturn` event and the card reappears with a chat line.
- Companion 1.0.x must not see the new kinds before its parser knows them, so the server enables donations only when `MIN_CLIENT` and `MIN_ADDON` are raised to the versions that carry spec 11, the same order used for spec 10.

## Scoring and rewards

- A donor's personal score falls when the copy leaves, as the proposal says. Finished pages stay finished (`state.sets` is permanent), so firsts and titles never change.
- Season credit stays with the donor: it is recorded at acquisition (`season_acquisitions`) and `donate` is not an acquisition kind. The guild earns no season credit and no reward grant from a donation. A donation cannot be turned into a second claim.
- Guild progress counts distinct cards held in the guild inventory against the cards a guild can hold. Two sets of numbers are worth deciding: the ladder ranks guilds by points (as personal scoring does), and the page also shows the card collection percentage. Faction cards are counted as extras, the way personal pages treat them.

## Privacy

Donor name, card and time are kept for audit and shown to members only. A guild page lists a guild publicly only if the owner turns that on. Account deletion removes the donor's identity from the history but keeps the donation, because the guild still holds the card. This needs a line in `docs/PRIVACY.md` and the privacy page before launch.

## Build order, and where it stands

Built and tested, all off unless the server has `GUILDS_ENABLED = "true"`:

1. **Guild creation (server).** Migration `0015_guilds`, signed `POST /v1/guilds/request` and `/v1/guilds/mine`, admin `GET /v1/admin/guilds` and `POST /v1/admin/guilds/:id`. The guild's side comes from the asking character's declared side in its Ranked binder, and a name is held on its realm while pending or active.
2. **Enrolment (server).** Migration `0016_guild_members`: apply, owner decides, leave, remove, roster. The owner is the first member, added when the guild is approved. One live row per account.
3. **Ledger spec 11 (shared, server, add-on, companion).** `mode/guild1`, `donate`, `donateReturn` (`packages/shared/src/rules.js`, `docs/LEDGER-SPEC.md`); migration `0017_guild_donations`; the server settles each donation in the upload's own transaction (credited, or refused and issued back); `POST /v1/guilds/summary` and the public `GET /v1/guilds/leaderboard`.
4. **Add-on.** `Guild.lua`: `/acb guild`, `/acb guild donate <card>` with a confirmation, the markers and events, pending donations kept in the saved file, refused copies written back as `donateReturn` when the game loads.
5. **Companion.** The guild answer is fetched after uploads and written into `Sync.lua` paired to the binder; a Guild panel in the window to ask for a guild, join one, decide applications, remove members and leave.

Not built yet:

- **A picker in the binder for donating.** Donating today is by card name with a chat confirmation. The binder's trade picker is tied to the trade window, so a donation picker means generalising it.
- **A guild tab in the admin panel.** Guild creation is decided with the admin routes (`docs/runbooks/ADMIN.md`).
- **A guild page on the website**, and naming a new owner when an owner's account is deleted (no route yet).
- **Staging walkthrough and an in-game pass.** Nothing here has been run against the real game, and the staging walkthrough does not check guilds.

To turn it on: apply migrations 0015 to 0017, raise `MIN_CLIENT` and `MIN_ADDON` to the versions that carry spec 11 (an older companion cannot upload a binder that has donated), then set `GUILDS_ENABLED`.

## Tests required before it is switched on

Ollie's list, with the extra cases this design adds:

- duplicate upload of one donation, an interrupted save, a failed request and an old saved file replayed;
- last-copy donation, and edition identity (a shiny is not its base card);
- donor removed or leaving between the confirm screen and the upload (refund path, `donateReturn` accepted once, rejected twice);
- an application to a second guild, two accounts racing to enrol, an owner removing a member mid-donation;
- tainted copies, a rebuild reproducing guild inventory exactly, and the leaderboard rebuilding;
- uploads from add-ons and companions older than spec 11 still replaying with no change.

## Open questions

- Are guild creations approved by an admin in the admin screen (this draft) or through the Discord server?
- Is the escrow behaviour acceptable, or must a failed donation never remove the copy at all? The latter needs a pending state kept outside the ledger, which has its own edge cases.
- What should a leaderboard of guilds rank by: points, distinct cards, or both?
- Can an owner see per-donor history, or only the totals?
