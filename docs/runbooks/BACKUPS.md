# Backups and restoring the database

**How you notice:** someone deleted or changed data they should not have (a bad migration, a bad deploy, a mistaken admin
action), the database reports errors, or the Cloudflare account itself is lost or locked.

There are two layers. The first handles most mistakes; the second is for when the account is the problem.

## 1. Cloudflare's point-in-time restore (Time Travel)

Every D1 database keeps a history it can be rewound to, to the minute: 7 days on the free plan, 30 on the paid one. It is on
by default and costs nothing.

See where the database is now (a bookmark) and what restoring would do:

```
cd server
npx wrangler d1 time-travel info warcards --env production
```

Rewind to a moment (UTC) or to a bookmark noted earlier:

```
npx wrangler d1 time-travel restore warcards --env production --timestamp=2026-11-12T09:30:00Z
npx wrangler d1 time-travel restore warcards --env production --bookmark=<bookmark>
```

A restore **replaces the live database** with the old one: everything written after that moment is lost, including players'
uploads since. It can itself be undone: the command prints the bookmark from just before the restore, so run that bookmark
back if it turns out to be the wrong moment. Before a risky change (a migration, a manual fix) run `time-travel info` and keep
the bookmark in the notes of the change.

After a restore, the add-on and the app recover by themselves: the server tells each app where it stands (`ackSeq`), and the
app uploads whatever the server no longer has from the player's saved file, which is kept until the server has it.

## 2. Copies kept outside Cloudflare

```
node tools/backup-db.js --env production --out D:\warcards-backups --keep 14
```

This exports every table to `warcards-production-<time>.sql`, checks that the file really holds the service's tables (an
export that does not is thrown away, not kept), and removes copies beyond the newest 14. The folder must be **outside the
repository** (the tool refuses otherwise) and **private**: the dump holds Discord account ids and every ledger event.

Run it every day. On Windows, once:

```
schtasks /Create /SC DAILY /ST 04:30 /TN "WorldOfWarcards database backup" /TR "cmd /c cd /d C:\Users\Harry\azeroth-card-binder && node tools\backup-db.js --env production --out D:\warcards-backups >> D:\warcards-backups\backup.log 2>&1"
```

(Use your own folders. The computer must be on and signed in to Cloudflare through `wrangler login`; if the task fails the log
file says why.) Once a month, copy the newest file to a second place (another drive, a private cloud folder).

## Restoring from a file

Do this when Time Travel cannot help (past its window, or the account is gone). Restore into a **new** database first, look
at it, then point the Worker at it.

1. Make an empty database and load the file:
   ```
   cd server
   npx wrangler d1 create warcards-restore
   npx wrangler d1 execute warcards-restore --remote --file D:\warcards-backups\warcards-production-<time>.sql
   ```
2. Look at it: `npx wrangler d1 execute warcards-restore --remote --command "SELECT COUNT(*) FROM players"` (and `batches`,
   `ledger_state`) and compare with what you expect.
3. Put its id in `server/wrangler.toml` as the production `database_id`, deploy (`npx wrangler deploy --env production`),
   and check `/v1/health` and the ladder.
4. Players recover as after a point-in-time restore: the apps re-upload what the restored database lacks.

If the whole Cloudflare account is lost, recreate the Worker and database from the repository (`server/wrangler.toml`,
`wrangler d1 create`, apply the migrations), set the three secrets again (`TAPE_SECRET` **must be the same value as before**,
or every Ranked tape entry changes and no earlier drop can be checked: it belongs in the password manager), then load the
file as above.

## Privacy

Deleting an account removes it from the live database at once. It remains in the 7-day recovery history and in the copies in
the backup folder until they age out (at most 14 days of daily copies). If a player asks, say so; if a restore brings back an
account that was deleted since, **delete it again** (`POST /v1/delete` through the app, or by hand) before the service reopens.

## Check it worked

- `/v1/health` answers `db: true`.
- The ladder (`/ladder`) and a known player's page load.
- The next sync from a player uploads cleanly (`/status` and `wrangler tail --env production` show no errors).
- Tell the players if their recent progress was rewound: it will be re-uploaded from their own saved files, but anything the
  game never saved is gone.
