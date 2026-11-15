# Ranked character login fix: addon 1.0.17

An older Ranked save may have a fully acknowledged and pruned ledger but no persistent faction records. Companion 1.0.4 then has no character to list until another eligible creature triggers a roll. Players in new dungeons with no catalogued mobs can remain stuck without that roll.

On entering the world, a valid Ranked binder now records the ordinary faction and character mode events, when missing. It grants no cards, uses no tape, preserves progress and does not repeat events on later zone changes. Casual binders and unverified histories are unchanged. The companion remains 1.0.4 with the exact previously published signed installer.

PR #69 / source f5fe1cb, tag v1.0.17. All 259 Lua checks passed; full CI 43775476153 and release workflow 43775725085 passed. The actual published addon ZIP was checked for checksum, version, login hook, safe layout and empty factory Sync. Staging passed exact signed-feed and download-page checks before production publication. No player saved file was edited or reset.

Players install addon 1.0.17 through the companion, /reload, Sync collection, then Refresh the Guild section. No kill or card drop is required. Reload again after creating or joining a guild to load membership into the addon.
