# Azeroth Card Binder · First playtest

Version 0.1.0 targets World of Warcraft: Forever, interface 16001. The installed build used for the interface check was 1.60.1.70862. The add-on is standalone and stores one binder per WoW account installation using SavedVariables.

## Install

1. Extract the ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. The final path should end in `AddOns/AzerothCardBinder/AzerothCardBinder.toc`.
2. Restart WoW, enable **Azeroth Card Binder** on the character screen, then type `/acb` in game.
3. Open **Deadmines**, **Westfall**, or **Gathering** to see every slot, including missing cards. Each owned slot shows the total and spare copies. The Deadmines page tracks the eight boss cards and the full twelve-card set separately.

## Collection

Opening loot with a readable source from the catalog gives a personal roll per source. There are 18 cards. Normal enemies roll at 0.5%, elites at 1%, and rares and rare elites at 5%. The binder lists the catalog's expected rank. If the game gives the add-on a readable rank for the same source, the roll uses that rank. Copper Vein and Peacebloom use a prototype rate of 0.5% per node, with a readable player gathering cast and matching node loot required.

Cards are keyed by NPC or object ID. A session remembers each rolled spawn token, including misses, across loot windows and zone transitions. Reloading the interface or relogging starts a fresh session. Sources with no readable identity, empty loot windows, and sources outside the catalog are skipped. Group loot that never exposes the corpse to you may produce no roll. Use a clean logout or reload to check that Forever restores the binder.

## Deadmines and gathering checklist

1. Run `/acb diag` to start the trace. In Westfall, open loot on a Defias Pillager, close the window without taking everything, then reopen it. Expect one `loot` line and an `Already rolled` line. Try a second Pillager and repeat with auto-loot enabled.
2. Loot several Deadmines enemies, including a boss, during ordinary group play. The trace shows an attempted roll even when the card misses. If loot comes up empty or a source is unreadable, note the enemy, loot method and whether auto-loot was on.
3. For the optional personal roll, toggle `/acb boss` on before fighting Edwin VanCleef. Target him while he is alive and keep him targeted through the kill. Loot his corpse afterward if you can. If Forever sends matching readable start and success events and exposes the same boss as a readable corpse at completion, expect one `encounter` or `loot` roll and a deduplication line if the other route also runs. The trial starts disabled and currently matches the English encounter name. In a group it also requires you to be alive in the instance at completion.
4. Mine a Copper Vein or pick Peacebloom. Check for a `gather` roll. Try interrupting a gather before it completes and compare with looting a corpse. A corpse dropping ore or herbs follows its creature rule.
5. Use `/acb log` to copy the last 80 trace lines. The trace omits raw spawn identifiers. Copy it before reloading.

The encounter trial is deliberately narrow. If the required events, boss token or corpse are absent at completion, the regular loot route still applies. Loot attribution, gathering spell payloads, boss eligibility, and SavedVariables restoration need a live pass on the launch client.

## Trade preview

Both players need this version and at least one duplicate each. Meet outdoors and out of combat, open `/acb trade`, then enter each other's character name. Use `Name-Realm` if needed.

1. One player clicks **Listen**. The other chooses a duplicate with **<** or **>** and clicks **Send offer**.
2. The listener chooses a different duplicate and clicks **Send reply**.
3. Review the two displayed cards and click **Confirm preview** on both clients. If a message was missed, use **Resend last step**. If both players started as the sender or the preview expired, clear it on both clients and begin again.

This release exchanges offers and confirmations over addon whispers. A completed preview leaves the binder balances intact. The two-player transport needs a live pass. Collection data is local and editable, so the preview only checks the sending client's own spare copy.

## References

- Forever's exported [loot events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua), [unit and cast events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), [encounter events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterInfoDocumentation.lua), and [addon messaging APIs](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua).
- The Forever beta [loot-source report](https://eu.forums.blizzard.com/en/wow/t/feature-request-area-aoe-looting-for-multiple-corpses/633131) and [GUID format notes](https://warcraft.wiki.gg/wiki/GUID) informed the loot-source and session deduplication assumptions.
- Catalog cross-checks used the [Forever Deadmines journal](https://www.wowhead.com/forever/dungeon-journal/the-deadmines), [Miner Johnson observation](https://wowforever.ninja/npcs/3586-miner-johnson/), [Foe Reaper 4000 records](https://www.wowhead.com/forever/npcs/min-level:19/max-level:20), [Copper Vein](https://www.wowhead.com/forever/object=1731/copper-vein), and [Peacebloom](https://www.wowhead.com/forever/object=1618/peacebloom).
