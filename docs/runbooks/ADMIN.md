# The admin panel

`/admin` on the live site (`https://worldofwarcards.co.uk/admin`) is where the people who run the service look at flags and reports, find a player and see what is held about them, ban or unban, delete a player's data, and read a record of what has been done.

## What it does

| Tab | What you can do |
|---|---|
| **Flags** | The players the checks held back. Clear (back on the ladder) or confirm (keep off) with a note; read the reports about them; open their player page; ban or unban. |
| **Players** | Search by display name, character name (with or without the realm part) or player id; with nothing typed it lists the newest players. A player's page shows when they joined, whether they are public or private, how many keys and restarted binders they have, their characters, score, binder mode and cards owned, uploads, trades (matched, open, unmatched), flags, and how many reports there are about them. **Ban...** asks for a reason, **Unban** asks to confirm, **Reset their binder...** and **Restore this binder...** (below) ask for a reason, **Delete their data...** asks you to type the player id. The page also lists the player's archived binders. |
| **Activity** | The newest 100 things done in the panel: who, what, to whom, when, and the reason or note. |

The panel never shows a Discord id, a key or the events of a binder (those are in the player's own *Download my data* copy). Private players can be found here: the panel is for the people who run the service, and everything that happens in it is recorded.

**Ban** stops a player uploading and hides them from the ladder; nothing is deleted and *Unban* undoes it. **Delete** is permanent on the live service (the same as the player's own *Delete my data*): recovery copies age out of Cloudflare's 7-day history and our 14-day backups, and **if a restore ever brings a deleted player back, delete them again before reopening the service** (see `docs/runbooks/PRIVACY-REQUESTS.md`). The activity record keeps only the player id and the reason, so it can stay after a deletion.

## Reset and restore a binder

**Reset their binder...** puts the player's whole binder aside in a private archive (the same thing as the player starting a new binder themselves) and takes them off the ladder. Nothing is deleted. Use it when a binder cannot be trusted but the player should be allowed to carry on (a ban is for the player, a reset is for the binder).

- Their add-on still holds the old history. So that it cannot simply upload it again, the reset records the time and the server refuses any upload that starts from before it, with the error `binder_reset`. The companion app shows this as "The server refused it (binder_reset)". The player has to start a new binder: **Start a new binder** in the companion app, then `/acb newbinder confirm` in the game. A new binder's first event is after the reset, so it is accepted.
- Their trades: the other players' halves of trades with this binder are no longer matched, so after seven days those cards stop counting towards those players' scores (the same as any trade whose other half never arrives). Tell people who traded with a cheater that this is expected.
- Their roll tape moves to a new epoch, so the new binder never replays the old one's rolls.

**Restore this binder...** (on each archived binder in the player's page) brings an archived binder back as the current one. Use it to undo a reset, or to give a player back the binder they put aside by mistake with *Start a new binder*. If the player has a binder now, it is put aside in its place and can be restored in turn, so nothing is lost either way. The player's add-on carries on exactly where it was, because the binder comes back with its chain and its roll-tape epoch. If the player's add-on has moved on to a new binder in the game, restoring the old one on the server will make their next upload fail; they would need to start a new binder again.

A player who has been reset can still be found by the name on the binder that was put aside, or by player id, or from the Activity tab.

## Signing in

Two locks, both needed once Cloudflare Access is set up:

1. **Cloudflare Access** (who you are): Cloudflare puts its own sign-in in front of `/admin` and `/v1/admin/*` (Google, GitHub, or a one-time code sent to an email address you list). The Worker checks Access's signed token itself, so a request that did not come through Access is refused, including one to the `workers.dev` address. The panel then shows "Signed in as you@example.com" and the activity record carries that email.
2. **The admin token** (the shared secret, `ADMIN_TOKEN`): typed into the page; kept only in that browser tab's memory and never in the address, a cookie or browser storage. Closing the tab forgets it.

Until Access is set up the token alone works and the activity record says `token` instead of a name. Set Access up before more than one person uses the panel.

## Setting up Cloudflare Access (once, about ten minutes, free for up to 50 people)

1. Cloudflare dashboard, **Zero Trust** (the first time, it asks you to choose a team name and the free plan: the team name becomes `<team>.cloudflareaccess.com`).
2. **Access, Applications, Add an application, Self-hosted.** Name it "World of Warcards admin". Session duration: 8 hours is sensible.
3. Under **Public hostname** (or *Application domain*) add these paths on `worldofwarcards.co.uk`:
   - `/admin`
   - `/v1/admin` (and its subpaths: use `/v1/admin/*` if the form asks for a wildcard)
   For staging, make a second application for `staging.worldofwarcards.co.uk` with the same two paths.
4. **Policy:** *Allow*, include **Emails**, and list the addresses of the people who run the service (Harry's and Ollie's). Choose the login methods you want (Google/GitHub, or the one-time PIN, which needs nothing set up).
5. Save, then open the application again and copy its **Application Audience (AUD) Tag**: a 64-character hex string.
6. Tell the Worker about it. In `server/wrangler.toml`, add to the `vars` of each environment (production and staging, each with its own AUD tag):

   ```
   ACCESS_TEAM_DOMAIN = "<team>.cloudflareaccess.com", ACCESS_AUD = "<the 64-character tag>"
   ```

   then `npx wrangler deploy --env production` (and `--env staging`). **Set both or neither.** If only one is set, or either is malformed, the panel refuses everyone, which is the safe way to get it wrong.
7. Check it: open `https://worldofwarcards.co.uk/admin` in a private window. Cloudflare's sign-in should appear first; after it the page loads, you enter the token, and the panel says "Signed in as <your email> (Cloudflare Access)". Open the `workers.dev` address of the Worker the same way: the panel must say it is not accepted.

The companion app, the add-on and the website never call `/admin` or `/v1/admin/*`, so protecting those paths cannot affect players.

## If you are locked out

- *Access says you are not allowed:* ask the other person to add your email to the policy (Zero Trust, Access, Applications, the application, Policies).
- *The panel says "not accepted" after Access let you in:* the token is wrong (`npx wrangler secret put ADMIN_TOKEN --env production` sets a new one), or `ACCESS_AUD` is not this application's tag.
- *Everyone is locked out:* remove `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` from `wrangler.toml` and deploy; the token alone works again. The `/v1/admin/*` routes and the page are still shut without the token, but nothing then proves who is acting, so put Access back soon.
- *Lost the token:* set a new one as above; nothing else uses it.

## What it does not do

It cannot rewind one player's binder to an earlier upload (as opposed to putting the whole binder aside). A rewind would leave the player's add-on ahead of the server, so its next upload would not follow the stored history, and it would leave the other side of every trade since then unmatched. Reset and restore cover the cases that matter. For a whole-database mistake use Cloudflare's point-in-time restore (`docs/runbooks/BACKUPS.md`); for a bad deploy, `wrangler rollback`.

## How to notice problems

`GET /v1/admin/audit` (or the Activity tab) shows every action. An entry you do not recognise means the token and, if set up, an Access login were both used: change the token, remove the email from the Access policy, and see `docs/runbooks/ALERTS.md`.
