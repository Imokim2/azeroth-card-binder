# 0008: One trade flow for exchanges and gifts

Accepted 12 November 2026.

Players choose a partner, choose a card and start a trade. The partner's window opens without a separate Listen action. Each side sees what they give and receive, and both must accept. Gift mode explicitly leaves the recipient's offer empty. Empty offers never create catalog keys or ledger events.

The new in-game session messages are distinct from legacy offer/reply messages. Both players need the updated addon for this flow. Offers have monotonic revisions; changing an offer clears both acceptance marks, and old acceptance messages cannot confirm a later revision. Accepted offers are locked until the other offer changes or cancellation completes.

The initiator coordinates the final decision after both accepts. The recipient applies the agreed transfer on the commit message and acknowledges it; the initiator applies on that acknowledgement. Messages are retried and applying is idempotent. Cancellation is decided by that same coordinator, so an in-flight acceptance cannot silently revive a cancelled trade. As before, game reloads and modified clients remain limits of an addon-only protocol; server matching checks uploaded transfers independently.

A gift is an existing tradeOut/tradeIn pair across the two players, with no return transfer. No schema, chain hash or ledger version change is required. Exact editions retain their keys; holographic unlock flags remain non-transferable. Completed gifts count as completed trades for existing milestones, once per participant, and are labelled as gifts in history.
