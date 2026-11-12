# 0010: Satchel and pack trading

Accepted 12 November 2026.

Represent packs as addon-owned stackable items, not native game inventory objects. A separate bag-style satchel shows one stack per zone and tier, with paging and right-click opening the existing reveal. Names are `Pack: <Zone>` with tier separate: Common holds 1 card, Rare 3, Epic 5. Legacy packs retain their five-card Epic identity. New tier odds are 70/25/5 after a successful pack find; they change quantity, not guaranteed card rarity. An unprotected addon button sits above the keyring when available, otherwise above the bag bar or at the bottom right. It never replaces the keyring or modifies protected bag controls.

The existing revisioned two-accept trade/gift protocol gains pack offers. One offer contains one card or one pack; `pack:<set-code>` is a trade-only key, never a card key. Pack counts remain in `saved.packs`. Opening a pack reserved by an active trade is blocked when no unreserved copy remains. Collection validation applies both sides before announcing success.

Ledger specification 6 adds a `mode/packs2` find-policy marker and reuses tradeIn/tradeOut with pack keys. Server replay validates the zone/tier, ownership/count delta and trade fields; pack keys are invalid for drops, crafts, recycling and packCard. The issued find entry also determines the tier, using digits above the pack-find remainder. Replay stores opened-card outputs by zone/tier after the first incoming pack trade. Pending, unmatched or unverified pack trades exclude these outputs from Ranked scoring, and provenance follows the outputs through later trades. This is conservative when found and traded packs share a type. Casual pack finds are themselves unverified provenance, even before opening. Existing event hashes and card inventory keys remain unchanged.

No native item creation, mail or auction-house integration is implied. Pack trading requires both players to update, plus matching companion/server protocol support. Repository publication and preparing source do not deploy a server or publish installers.
