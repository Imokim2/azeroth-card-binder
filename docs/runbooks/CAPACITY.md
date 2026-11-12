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

## How many players?

Two changes keep the load down however many people play (12 Nov 2026): public answers are **shared at the edge** for a minute or five (`server/src/cache.ts`: the ladder, firsts, wanted board, public player pages, site pages and release announcement are worked out once, not once per request), and the companion app **asks for standings every 30 minutes** (it was 5) and **asks for roll tape only when the add-on is running low** (it was every pass).

Rough figures per player with the companion app open all day (estimates, from how the app behaves; check Cloudflare's current limits and prices):

| | Before | Now |
|---|---|---|
| Requests a day | about 1,400 | about 300 |
| Database rows read for standings | a few hundred per refresh, per player | the ladder is recomputed at most once a minute for everyone: about 0.7 million rows a day in total, whether there are 10 players or 10,000 |
| Rows written | 100 to 300 a day (uploads) | the same |

**Free plan, Casual only:** the 100,000 requests a day allowance now lasts for roughly 300 players with the app open all day, or about 800 at 8 hours a day; the daily row-write allowance (about 100,000) is the next limit, at some hundreds of players. **Free plan, Ranked: still none**, because tape requests need more than 10 ms of CPU (above).

**Paid plan, Ranked:** it works. The CPU limit is 30 seconds a request against our heaviest request of about 60 ms; the database allowances are far above what we use; and the cost is small. As a rough guide, 5,000 active players at 300 requests a day each is 45 million requests a month: the plan includes 10 million, the rest costs about $0.30 per million, so around $10 more, plus a few cents of CPU time and database use. Expect something like $15 a month at that size, far less while it is small.

## What to do

1. **Switch the account to Workers Paid** (Cloudflare dashboard, Workers & Pages, Plans). It also raises the D1 database limits, which the free plan's daily write allowance would otherwise reach with a few thousand uploads a day (check Cloudflare's current limits page).
2. After switching, run `node tools/smoke.js` and watch `wrangler tail --env production` during a Ranked sync: each request line shows its CPU time.
3. Keep an eye on it from `wrangler tail` once players arrive. Cached answers do not appear in the request log (they never reach the API); the `x-cache: hit` or `miss` header on a response says which it was.

## Making it cheaper later (not needed on the paid plan)

- **Four entries per HMAC.** A tape entry is 8 bytes, an HMAC-SHA256 gives 32: one call could produce four entries, cutting the tape's cost to a quarter. It changes how entries are derived (a new ledger specification version, new test vectors and a way to keep old tapes valid), so it is a deliberate change, not a tweak.
- **Do not re-derive what the app already holds.** The tape request re-derives every unused entry each time; the app could say where it is and get only the new ones.
- **Smaller batches.** The tape batch is 1,000 entries; a smaller one lowers the worst request but means more requests.

None of these is needed while the account is on the paid plan: at the paid price of CPU time the heaviest request costs a fraction of a cent.
