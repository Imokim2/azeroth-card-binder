# Logs and alerts

What the server writes, what to look for, and what to do. The server logs one JSON line per request through `console.log`; with `observability` on in `server/wrangler.toml` Cloudflare keeps them so they can be searched in the dashboard (Workers > the Worker > Logs) and followed live with `npx wrangler tail --env staging --format json`.

## What a log line holds

`{ at, level, msg: "request", requestId, route, method, status, ms, code? }` for every request, plus these warnings:

| `msg` | Meaning |
|---|---|
| `discord token exchange refused` (`status`, `error`) | Discord refused the sign-in code. `invalid_client` means the Discord secret on the server is wrong; `invalid_grant` is a used or expired code (normal now and then). |
| `discord user lookup refused` / `discord could not be reached` | Discord is failing; sign-ins will fail until it recovers. |
| `database overloaded` | D1 said its queue is full. Clients are told to retry in 5 seconds. |
| `unhandled error` (`error`) | A bug. Level `error`; `code` is `internal`. |
| `maintenance` | The hourly job ran (matched trades, written-off halves). |

Logs never hold a Discord id, a key, a signature, a card or an upload.

## What to watch, and what it means

| Look for | Likely cause | What to do |
|---|---|---|
| `level: error` or `status >= 500` | A bug or Cloudflare trouble | Open the line, find the `requestId`, read the `error`. If it began with a deploy, roll back: `npx wrangler rollback --env staging`. |
| Many `code: rate_limited` from one burst | One client hammering, or a bug in the app retrying too fast | Check the app's version; the limits are in `wrangler.toml`. |
| Many `bad_signature` or `unknown_key` | An old app version, a deleted account still syncing, or probing | Usually harmless. A sudden flood from many places is not: see the rate limits. |
| `tape_invalid` | A modified add-on, or a stale roll tape after a reset | One player: read their flags. Many at once: a server change broke the tape derivation. |
| `database overloaded` | Too many writes at once | See the cost limits in the roadmap; the paid plan raises them. |
| The hourly `maintenance` line missing for 3 hours | The scheduled job is not running | Check the Worker's cron trigger in the dashboard. |
| `/v1/health` not `ok:true` | The database or the Worker is down | See below. |

## Watching it from outside

`GET /v1/health` answers `{ ok, db, version, catalogVersion }` and is never rate limited. Point a free uptime monitor at it (for example the one in the Cloudflare dashboard, or any external one) and alert on anything but `200` with `"ok":true`. Set Cloudflare notifications (dashboard > Notifications) for the Worker and for D1 usage so a limit is seen before it is hit.

## When health is not ok

1. Open the address in a browser. `"db":false` means the Worker is up but the database is not answering: check the D1 page of the dashboard and the status page.
2. If it began with a deploy, roll back: `npx wrangler rollback --env staging`.
3. If it is the database and Cloudflare reports no incident, look for `database overloaded` lines and for an upload storm in the logs.
