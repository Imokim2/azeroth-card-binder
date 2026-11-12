# Saved-progress syncing

The companion source now syncs at startup and when the game finishes writing SavedVariables, rather than making a pass every ten minutes. WoW saves the binder on logout, quitting and `/reload`. The file alone cannot reliably distinguish those events, so they are treated together. No game-memory access or gameplay automation is involved.

## Network behaviour

- **Idle:** after a successful pass there is no periodic network timer. Leaving the app open with unchanged files makes no further automatic requests.
- **Game save:** upload new progress and refresh the leaderboard once the file settles. Further saves during a running upload queue one more pass so progress is not stranded.
- **Companion startup:** catch up any progress saved before the app opened. Restore the last downloaded leaderboard from the generated Sync.lua display data. Startup alone does not refresh the board; actually uploading previously unsent saved progress does.
- **Manual Sync:** uploads pending work, picks up accounts and checks updates. It does not repeatedly refresh the leaderboard without a new game save or new uploaded progress.
- **Ranked readiness:** fetch required data only when low, as before. Failed uploads or required refills retry with backoff from a minute to half an hour, respecting any longer server Retry-After. Successful recovery returns to idle.
- **App updates:** check at startup and at most once per six hours during saved-file passes. Manual Sync can check immediately. There is no separate background update timer.

## Wanted cards stay in game

The companion no longer uploads or downloads wanted lists, and no longer writes a wanted feed into Sync.lua. The addon ignores old remote wanted feeds and uses lists shared directly by players. Checking a target, viewing a binder and sharing trade lists already support this.

The website has no wanted board or navigation link. Old `/wanted` links lead to the in-game instructions. Legacy companion `/v1/wanted` calls receive an empty feed or a retired acknowledgement, without reading or writing the wanted table; this preserves their other sync features while they await an update. Old edge-cache entries are bypassed. Historical rows are retained for account export/deletion rather than silently deleting user data during deployment.

## Savings and limits

The previous source could make four standings requests plus an update request every half hour: roughly 240 metadata requests a day per continuously running companion, before actual uploads. The new client makes **zero periodic requests while idle** and no wanted requests. Standing updates cost three reads per game-save sync; update checks are less frequent.

For example, four saves per day mean around 12 standings requests, with updates, pending uploads and required refills in addition. That is a large cut in background traffic, but it is not a promise that the whole bill falls by the same percentage. Actual card/history writes, validation, storage and active sessions still matter. Standalone addon users without the companion generate no requests to this server.

The older 300-requests-per-user/day examples in CAPACITY.md are historical heavy-use scenarios, not a forecast for this new mode. Replace assumptions with measured Worker CPU, request totals and D1 rows as players test the new build.

## Rollout and verification

Companion 0.4.0 includes this mode, published with addon 0.6.0 for the group test. Client traffic savings require installing that companion update; already-installed 0.3.0 companions retain their previous polling. The matching signed downloads must exist before deploying the server’s raised minimum versions. Website wanted-board retirement was deployed earlier on the compatible public server line.

Automated tests cover a simulated idle day with zero requests, a file-change sync, queued writes during an upload, required-refill recovery with backoff, update caching, retained leaderboard display, no companion wanted requests, direct addon wanted sharing and retirement of cached web wanted data.
