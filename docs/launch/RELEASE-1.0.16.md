# Guild setup fix: addon 1.0.16 / companion 1.0.4

The companion's guild dropdown could be loaded before the first sync finished, then never updated. It also relied on the most recent ledger event, which disappears when acknowledged events are pruned. Character choices now come from persistent Ranked faction records, with a recent-event fallback for older saves. Local sync status refreshes the choices without extra network polling, preserves the selection and explains an empty list.

Creating a guild binder now creates its active owner membership in the same database transaction. Website approval is not required. The owner still approves member applications. Additive migration 0018 activates existing pending requests where the owner has no other active or pending membership, preserving IDs and collection history. It leaves conflicting historical requests for manual review rather than replacing a membership.

Update companion 1.0.4 first, then addon 1.0.16 and reload. The addon change updates its Guild setup text. Server 1.0.3 carries the automatic creation flow and matching website guidance. Collection and donation rules, catalog, ledger protocol and minimum supported versions are unchanged. No player saved file is reset or edited by this release.

Regression coverage includes the shipped renderer receiving a delayed sync, character discovery after pruning/restart, automatic owner creation, transaction rollback, migration preservation and existing donation/member validation.

## Publication record — 15 November 2026

- PR #68 merged as `e8cfc59`, tagged `v1.0.16`. CI `43770932133` passed 258 Lua checks and 421 Node checks (7 Windows-only checks skipped on Linux). Release workflow `43771235657` passed, including actual packaged Windows startup and native installer checks.
- Migration 0018 was applied on staging, then production, after recovery references were recorded. The production aggregate check found no eligible pending guild request still waiting. Collection histories were unchanged.
- Published ZIP and EXE checksums matched. The ZIP has 105 entries, all TOC modules and an empty factory Sync file. The trusted signed updater installed the actual ZIP on two fixture accounts while preserving both saves, both backups and existing Ranked Sync data byte-for-byte.
- Staging passed 29 walkthrough checks. Both environments passed 18 deep download checks, exact release-feed signature/version checks and matching download-page checks. Final worker versions: staging `aa4c8121-9347-4c81-a8fb-98bb668aaaa1`; production `40f1d7ce-5df6-4919-a1fa-3092be15cb1a`.
- Website, GitHub release, Discord updates/download notices and CurseForge description use the automatic-creation instructions. CurseForge file `9638931` contains addon 1.0.16 for Forever 1.60.1 and is processing; the project remains awaiting moderator approval. No claim of public CurseForge availability is made. In-game group donation testing remains for the players.

Addon SHA-256: `403552101118d02930dfee6dd6b71ded7de567b2342e2fdbf42233653e8d8cc9`.

Companion SHA-256: `205bb54a131ab40345a4249baeda3f8bf064aa9fa15f46c45d3aabbe8bdacf2f`.
