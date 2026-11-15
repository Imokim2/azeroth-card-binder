# Guild setup fix: addon 1.0.16 / companion 1.0.4

The companion's guild dropdown could be loaded before the first sync finished, then never updated. It also relied on the most recent ledger event, which disappears when acknowledged events are pruned. Character choices now come from persistent Ranked faction records, with a recent-event fallback for older saves. Local sync status refreshes the choices without extra network polling, preserves the selection and explains an empty list.

Creating a guild binder now creates its active owner membership in the same database transaction. Website approval is not required. The owner still approves member applications. Additive migration 0018 activates existing pending requests where the owner has no other active or pending membership, preserving IDs and collection history. It leaves conflicting historical requests for manual review rather than replacing a membership.

Update companion 1.0.4 first, then addon 1.0.16 and reload. The addon change updates its Guild setup text. Server 1.0.3 carries the automatic creation flow and matching website guidance. Collection and donation rules, catalog, ledger protocol and minimum supported versions are unchanged. No player saved file is reset or edited by this release.

Regression coverage includes the shipped renderer receiving a delayed sync, character discovery after pruning/restart, automatic owner creation, transaction rollback, migration preservation and existing donation/member validation.
