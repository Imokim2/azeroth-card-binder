# Card status in unit tooltips

Addon 1.0.10 addresses the report that dungeon mob tooltips had no collection status, both in and out of combat. The earlier implementation only read `data.guid` and silently stopped when it was missing, restricted, or unavailable as a current loot source. This is a plausible explanation for the report, not a confirmed trace from an affected dungeon session.

The read-only tooltip lookup now tries:

1. A readable GUID from the tooltip data.
2. A readable GUID from the actual displayed unit returned by `GetUnit`, or its UnitName tooltip line's unit token.
3. A readable NPC name matched exactly, without case sensitivity, against the current zone/dungeon's catalog. More than one matching identity declines to guess. A readable unknown GUID never falls back to a different named card.

Only available cards and already-owned card families are displayed. Showing an owned held-back card does not make it collectible again: `ACB.source` and all acquisition/Ranked rules are unchanged. Object tooltips do not use unit-name fallbacks. Player tooltips do not use NPC-name matching, and passive title/faction restrictions are unchanged.

The client may protect unit identity independently of combat. Blizzard's generated [Unit API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) mark `UnitGUID`, `UnitName`, and related functions with identity restrictions. Its [tooltip helper](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua) returns unit/name/GUID data without turning those values into public identities. These are source references for defensive handling; the exact values returned by Forever 1.60.1 still require in-game verification.

Every candidate is checked with the existing secret-value guard before inspecting it. If no readable identity is available and the tooltip GUID is protected, the tooltip says “Card status: hidden by the game here. Check the binder index.” Do not claim that this makes every restricted dungeon mob identifiable. It replaces a silent omission with an honest explanation; the index can search the mob name manually and filter owned or unowned cards.

Verification covers missing/secret tooltip GUIDs, independently readable unit data, readable name lines, protected names, wrong and ambiguous identities, player exclusion, legacy tooltip hooks, wanted status and owned seasonal cards. Index tests cover card/set/category searches, exact variant ownership, pagination resets, live count changes and saved filter persistence. Further verification is needed on a real affected dungeon tooltip.
