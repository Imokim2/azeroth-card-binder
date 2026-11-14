# 0008: One trade flow for exchanges and gifts

Accepted 12 November 2026.

Players choose a partner, choose a card and start a trade. The partner's window opens without a separate Listen action. Each side sees what they give and receive, and both must accept. Gift mode explicitly leaves the recipient's offer empty. Empty offers never create catalog keys or ledger events.

The new in-game session messages are distinct from legacy offer/reply messages. Both players need the updated addon for this flow. Offers have monotonic revisions; changing an offer clears both acceptance marks, and old acceptance messages cannot confirm a later revision. Accepted offers are locked until the other offer changes or cancellation completes.

The initiator coordinates the final decision after both accepts. The recipient applies the agreed transfer on the commit message and acknowledges it; the initiator applies on that acknowledgement. Messages are retried and applying is idempotent. Cancellation is decided by that same coordinator, so an in-flight acceptance cannot silently revive a cancelled trade. As before, game reloads and modified clients remain limits of an addon-only protocol; server matching checks uploaded transfers independently.

A gift is an existing tradeOut/tradeIn pair across the two players, with no return transfer. No schema, chain hash or ledger version change is required. Exact editions retain their keys; holographic unlock flags remain non-transferable. Completed gifts count as completed trades for existing milestones, once per participant, and are labelled as gifts in history.
# Runtime access from addon 1.0.8

Current card/pack trades and gifts require an eligible Ranked binder. Casual players cannot send or receive them. New Ranked selection requires the companion's matching setup file; the addon cannot inspect whether the desktop process is running. A previously Ranked binder is never silently changed to Casual when setup or supply is missing. The first committed Casual card find shows one persistent warning per binder, independently of ordinary card popups.

New clients may reply `N|<trade-id>` to an initial invitation when their binder cannot trade. The sender handles this only before either acceptance or a commit decision; completed-session acknowledgements retain their existing replay protection. Collection mode cannot change during an unfinished transfer. Legacy trade entry points also check collection mode.

These are current client access rules, not a change to historical ledger replay or the provenance of old Casual-origin trades. The historical pack-transfer fixture arranges Ranked transport access separately while keeping its old ledger unchanged. Server checks continue to exclude Casual-origin value as before. Neither a saved mode nor a companion setup file is a cryptographic proof of a live desktop process.
