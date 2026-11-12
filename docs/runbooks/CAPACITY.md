# Capacity: does it fit the free Workers plan?

**Short answer: no. Run production on the Workers Paid plan ($5 a month) before real players arrive.**

Cloudflare's free Workers plan gives each request **10 ms of CPU time** (waiting for the database or the network is not counted); the paid plan allows far more (30 seconds by default). The heaviest requests here do real computation, so we measured them.

## How it was measured

`server/bench/cpu.bench.ts` (run `npm run bench` in `server/`, or `node bench/cpu.bench.ts`) runs the real API code against an in-memory SQLite database and times the heaviest requests. It is an estimate: Node's crypto is not Cloudflare's, and SQLite here runs on the same thread (on Cloudflare a database wait costs no CPU), which makes the figures slightly high. They are good for the order of magnitude and for which request is the expensive one. Windows' timer is coarse (16 ms steps for CPU time), so the **wall-clock column is the one to read**.

## Results (12 Nov 2026, a desktop PC)

| Request | Wall time | Why |
|---|---|---|
| 1,000 tape entries (HMAC-SHA256), by themselves | about 18 ms | one WebCrypto HMAC call per entry |
| `POST /v1/tape`, first (issues 1,000 entries) | about 54 ms | derive 1,000, commit, store, return them |
| `POST /v1/tape`, again (returns the unused ones) | about 22 ms | the unused entries are derived again on every request |
| `POST /v1/ledger`, a short Casual history | under 1 ms | |
| `POST /v1/ledger`, Ranked, 173 attempts | about 11 ms | every attempt is replayed against its own tape entry |
| `POST /v1/ledger`, Ranked, one full tape batch (about 1,000 attempts) | roughly 60 ms (extrapolated) | |

Even if Cloudflare's runtime were two or three times faster than this PC, the tape requests and a larger Ranked upload would still be over 10 ms. On the free plan they would be cut off with an error, which for Ranked means **no new roll tape and refused uploads**.

## New saved-progress mode (prepared source)

The companion now uses saved-file events instead of periodic network polling. The leaderboard updates after a game save or catch-up upload of newly saved progress, and otherwise stays cached locally. Wanted lists stay in the addon; there is no web board or companion wanted upload/download. See [LOW-COST-SYNC.md](LOW-COST-SYNC.md) for behaviour, verification and rollout.

This removes idle polling rather than merely slowing it down. An idle-day test makes zero additional requests after a successful pass. These client savings require users to install the new companion; the public installer still has its earlier behaviour. Actual card validation/history storage remains a cost. The historical calculations below are heavy-use examples, not the expected bill for this new mode.

## Previous polling model (for comparison)

Two changes keep the load down however many people play (12 Nov 2026): public answers are **shared at the edge** for a minute or five (`server/src/cache.ts`: the ladder, firsts, wanted board, public player pages, site pages and release announcement are worked out once, not once per request), and the companion app **asks for standings every 30 minutes** (it was 5) and **asks for roll tape only when the add-on is running low** (it was every pass).

Rough figures per player with the companion app open all day (estimates, from how the app behaves; check Cloudflare's current limits and prices):

| | Before | Now |
|---|---|---|
| Requests a day | about 1,400 | about 300 |
| Database rows read for standings | a few hundred per refresh, per player | shared for each cache key at each edge location until expiry; actual reads depend on geography, cache misses and the number of players returned |
| Rows written | 100 to 300 a day (uploads) | the same |

**Free plan, Casual only:** the 100,000 requests a day allowance now lasts for roughly 300 players with the app open all day, or about 800 at 8 hours a day; the daily row-write allowance (about 100,000) is the next limit, at some hundreds of players. **Free plan, Ranked: still none**, because tape requests need more than 10 ms of CPU (above).

**Paid plan:** the measured requests fit comfortably within the default per-request CPU allowance. That is not a load test or a guarantee of the monthly bill. The old estimate of about $15/month for 5,000 users is plausible under modest CPU/database use, but "a few cents of CPU" is not a safe blanket assumption.

## Monthly cost scenarios

Prices checked against [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) and [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) on 12 November 2026. Figures below are USD before tax, payment fees, domain renewal, backups and extra storage. They describe usage, not registered accounts.

Workers Paid starts at $5/month, including 10 million requests and 30 million CPU milliseconds. Additional usage costs $0.30 per million requests and $0.02 per million CPU milliseconds. D1 includes 25 billion rows read, 50 million rows written and 5 GB of storage per month; extra writes cost $1/million and extra storage $0.75/GB-month. Index maintenance can increase billed rows written.

For an illustrative all-day usage scenario, assume each active user makes 300 requests/day for 30 days, dynamic requests average 7 ms of billed CPU, and each user causes 100–300 **billed** D1 row writes/day. The 7 ms is an example, not a measured production average, and the row-write range is a planning assumption. Actual metered usage must replace both.

| Daily active users | Requests/month | Workers including example CPU | D1 write overage | Combined example/month |
|---|---:|---:|---:|---:|
| 1,000 | 9 million | $5.66 | $0 | about $6 |
| 5,000 | 45 million | $21.20 | $0 | about $21 |
| 50,000 | 450 million | $199.40 | $100–400 | about $300–600 |
| 100,000 | 900 million | $397.40 | $250–850 | about $650–1,250 |

The calculation is `$5 + max(0, requests - 10m) / 1m × $0.30 + max(0, requests × average CPU ms - 30m) / 1m × $0.02`, plus D1 overages. Read charges are omitted from the example because the assumed cached public load is below the included allowance; this is not a promise about all per-player history reads. Storage is also additional. At eight hours of activity a day rather than 24, the example's request/CPU component for 5,000 users is about $8, assuming proportional traffic. Already-issued clients can retain their older polling behaviour until updated.

Cache hits can greatly reduce computation and database reads, but do not necessarily remove Worker request charges. The current Cache API wrapper still runs inside the Worker. Costs also depend on replay/history size, not just how often the app polls. Measure the average and high-percentile deployed CPU, actual request totals, D1 rows read/written and storage growth rather than extrapolating the desktop wall-clock benchmark as billing data.

Set billing/usage alerts before a wide launch. Alerts notify; they are not a guaranteed hard spending cap. Do not upgrade plans or change paid services as part of adding the support button. If growth reaches tens of thousands of active players, load-test upload bursts and database capacity, and review history retention and partitioning before assuming the present architecture will scale indefinitely. Each paid D1 database has a fixed 10 GB maximum and processes queries on a single thread; the current one-database design will need capacity planning as histories grow. See [D1 limits](https://developers.cloudflare.com/d1/platform/limits/).

## What to do

1. **Switch the account to Workers Paid** (Cloudflare dashboard, Workers & Pages, Plans). It also raises the D1 database limits, which the free plan's daily write allowance would otherwise reach with a few thousand uploads a day (check Cloudflare's current limits page).
2. After switching, run `node tools/smoke.js` and watch `wrangler tail --env production` during a Ranked sync: each request line shows its CPU time.
3. Keep an eye on it from `wrangler tail` once players arrive. Cached answers do not appear in the request log (they never reach the API); the `x-cache: hit` or `miss` header on a response says which it was.

## Making it cheaper later (not needed on the paid plan)

- **Four entries per HMAC.** A tape entry is 8 bytes, an HMAC-SHA256 gives 32: one call could produce four entries, cutting the tape's cost to a quarter. It changes how entries are derived (a new ledger specification version, new test vectors and a way to keep old tapes valid), so it is a deliberate change, not a tweak.
- **Do not re-derive what the app already holds.** The tape request re-derives every unused entry each time; the app could say where it is and get only the new ones.
- **Smaller batches.** The tape batch is 1,000 entries; a smaller one lowers the worst request but means more requests.

None of these is needed while the account is on the paid plan: at the paid price of CPU time the heaviest request costs a fraction of a cent.
