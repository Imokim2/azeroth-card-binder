# Collectible editions share base set slots

## Context

Alternate still poses and animated boss cards are separate collectibles. Their ownership, trades and Ranked drops must be checked without making every ordinary set require all artwork variations or rewriting existing histories.

## Decision

Use immutable `edition:<id>` inventory keys linked to a base creature. Signature remains on its existing key. A successful supported boss drop selects Signature, still or animated at 80%, 15% and 5%; these are conditional edition rates, with the source drop chance and bad-luck protection unchanged. Holographic finish keeps the existing permanent-unlock behavior separately for each edition.

Ordinary set slots, card milestones and scores group editions by creature. Trades and recycling use exact edition copies; special editions cannot be crafted. Ledger specification 4 introduces an `editions1` activation marker using the existing event fields. Ranked derives edition choice from a domain-separated hash of the issued tape entry and validates the exact inventory key. Older events retain their previous meaning.

## Consequences

Existing inventories and chain hashes remain valid. The shared catalog, companion app and server must update together before Ranked testing. Score rules version 2 deduplicates edition families. The first sixteen variants cover eight bosses in Deadmines, Shadowfang Keep, Scarlet Monastery and Blackfathom Deeps. Native model framing and animation still need an in-game playtest.

The implementation, initial content and integration tests are documented in [COLLECTIBLE-EDITIONS.md](../COLLECTIBLE-EDITIONS.md).
