# Card acquisition messages

Every acquired card has a private, rarity-coloured clickable link in chat. Clicking it uses the existing card-link handler to open that card in the player's own binder, including their current ownership counts. Pop-up and audio settings do not disable this message.

Public announcements are on by default. The wording is `World of Warcards: I just added 'Defias Pillager' to my binder.` A newly found shiny adds `(Shiny)` after the name. Public messages contain ordinary readable text, so players without the addon see the same wording.

Routing uses instance-group chat when in an instance group, raid chat when in a raid, party chat when in a party, and `/say` when solo. General settings has **Announce cards in chat**; `/acb announce` toggles the same saved preference. Switching it off clears pending public announcements and leaves private links enabled.

Normal finds, duplicates, crafting, incoming trades and gifts use the collection's `cardAdded` path after the inventory change commits. Giving away a card, a failed operation, previews, saved-data restoration and repeated loot events do not trigger it. Receiving an unopened pack is not a card acquisition. Pack contents report when flipped, or when the window closes for any remaining results, exactly once per result. This avoids revealing face-down cards in chat.

Public announcements are spaced two seconds apart. The queue holds at most 30 messages, expires entries after 60 seconds, and is never saved across a reload. Messages queued for a different chat type are discarded if the player changes between solo, party, raid or instance group. Chat lockdown waits within the expiry period; missing APIs and refused sends fail safely without retrying the refused message or switching channels. Private messages remain available. The actual Forever client's permission to automatically send public chat must still be checked in game.

API reference: the client's generated [ChatInfo API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua) describes `C_ChatInfo.SendChatMessage` and `InChatMessagingLockdown`. The legacy `SendChatMessage` entry point is supported when the namespaced entry point is absent.

## In-game check

1. With pop-ups and sounds off, find a card while solo. Confirm one private clickable message and one `/say` announcement. Click the private link and check the card and owned count.
2. Find a card in a party and raid; confirm the announcement uses the matching group channel. Check instance-group chat separately if available.
3. Open a pack. Confirm no card names appear before flipping; flip one, then close early. Each card should produce one private link and one paced public announcement.
4. Turn public announcements off and find another card. Only the private message should appear. Reload and confirm the switch stays off.
5. Receive a gift and complete a trade; only received cards should announce. Giving a card or trading a sealed pack should not announce a card.

Automated coverage: `tests/parts/29-card-announcements.lua` exercises acquisition paths, clickable links, channel selection, pacing, muting, reload preference retention, queue expiry, chat changes, denied sends and the legacy API fallback. The earlier loot and trade tests also run with this integration loaded.
