# 0001. The ledger is the source of truth; everything else is derived

Status: Accepted
Date: 2026-11-10

## Context

Ranking players on a global collection race means the server must decide whose numbers count, and the add-on's saved data is an editable file. Scores and ranks will change as rules are tuned, and bugs in scoring are certain.

## Decision

The server stores each player's append-only, hash-chained ledger (see [LEDGER-SPEC.md](../LEDGER-SPEC.md)). Counts, scores, ranks, snapshots and flags are all projections of the stored ledgers and can be rebuilt from them at any time. Data is never edited to fix a result; the rule is changed and the projections are recomputed.

## Alternatives considered

- Store only the latest snapshot per player: simple, but history can be rewritten and a scoring change cannot be replayed.
- Store every attempt as a row: complete, but far more writes and storage than the plan can afford.

## Consequences

A rebuild job is a required part of the server. Rules need a version number. Card keys must never be reused or renamed. Storage grows with ledgers, so old batches move to cold storage by season.
