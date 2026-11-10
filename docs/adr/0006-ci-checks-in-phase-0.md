# 0006. Phase 0 CI runs tests and syntax checks; linters come later

Status: Accepted
Date: 2026-11-10

## Context

The roadmap plans luacheck and StyLua in continuous integration. Neither can be run on the current development machine, and the existing code was never checked with them, so adding them now would either start red or need a large untested reformatting commit.

## Decision

Phase 0 continuous integration runs the Lua tests, the shared-contract tests and a syntax check of every Lua and JavaScript file. luacheck and StyLua are added in a later, separate change that sets a baseline first (list the current warnings, fail only on new ones) and does the one-time formatting pass on its own.

## Alternatives considered

- Add both now and fix whatever fails: risks a long red build on code that works.
- Never add them: loses the cheap checks for unused variables and accidental globals.

## Consequences

Accidental globals and unused variables are only caught by the tests until the linter is added. This is tracked as a follow-up in the roadmap (G2b).
