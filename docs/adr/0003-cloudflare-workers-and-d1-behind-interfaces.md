# 0003. Host on Cloudflare Workers and D1, behind store interfaces

Status: Accepted
Date: 2026-11-10

## Context

The project needs a cheap, low-maintenance server that can grow. Cloudflare's documentation says a D1 database holds up to 10 GB on the paid plan, handles queries one at a time per database, and an account may have up to 50,000 databases.

## Decision

Build the server on Cloudflare Workers with D1, free plan while building and the paid plan at launch. The server code talks to `IngestStore`, `PlayerStore` and `LeaderboardStore` interfaces, never to D1 directly. Every table is keyed by player and every identifier is random, so players can later be spread across several databases.

## Alternatives considered

- A hosted Postgres (such as Supabase): easier analytics, about $25 a month, one more thing to size. Kept as the exit route.
- A small rented server: cheapest on paper, but backups, patches and security would be our job.

## Consequences

Throughput and size limits are watched with the scale triggers in the roadmap. Public pages are precomputed and cached. If limits are reached the interfaces let us queue writes, shard by player, or move to Postgres without rewriting the rules.
