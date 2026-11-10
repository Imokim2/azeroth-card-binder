# 0002. Two modes: Casual and Ranked

Status: Accepted
Date: 2026-11-10

## Context

The add-on must keep working for people who never install the companion app, but a competitive ladder needs random numbers a player cannot choose and a server that can check them.

## Decision

Casual mode uses local random numbers and does not count for the ladder. Ranked mode uses a tape of random numbers issued by the server, spent in order, and counts for the ladder. Ranked is opt-in and needs the companion app.

## Alternatives considered

- One mode with local random numbers: no way to bound how a modified add-on skips unlucky rolls.
- Ranked only: shuts out everyone without the app and makes the add-on useless when the server is down.

## Consequences

The add-on must work fully offline in Casual mode. Ranked rolls pause when the tape runs out and say so. The fair-play page states plainly that a player who edits the add-on can still read ahead, and that the advantage is bounded by rate limits and statistical checks.
