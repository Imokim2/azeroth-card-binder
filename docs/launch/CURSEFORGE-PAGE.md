# World of Warcards

<!-- Current release description: addon 1.0.20 / companion 1.0.6 / server 1.0.5. Updated 16 November 2026. Existing gallery captures are genuine earlier-build screenshots; a Guild/batch capture is still needed. -->

![World of Warcards](../media/banner.png)

Collect cards from creatures, dungeon bosses and gathering nodes as you play. Fill your binder, swap spares with friends or keep a zone pack sealed for a trade.

**Built for World of Warcraft: Forever.** Retail and other Classic clients are not currently supported.

## Your binder

Browse collections by zone or dungeon, see the gaps you still need to fill and take a closer look at your favourite cards. Search for a creature, set or category, then filter the index by **All**, **Owned** or **Unowned**.

The zone collection bar tracks your progress as you travel. Prefer the binder to open at the same place? Enable **Settings → General → Open binder at current zone**. It finds the current zone or dungeon collection, even with the bar hidden. In places without a matching collection, the binder remembers your previous page. The option starts off disabled.

Card links still take you straight to the selected card. Shift-click a card to share it in game; other players using the addon can open it in their own binder and see their own collection status.

![The collection index with an undiscovered Wiry Swoop card selected](../media/gallery/binder.png)

## Open packs

Packs are named **Pack: Zone**, such as **Pack: Westfall**, and contain cards from that area. Common packs hold **one card**, Rare packs **three** and Epic packs **five**. The cards inside can be different rarities.

Sealed packs stay in the **Warcards Satchel**, a separate bag beside your normal bag controls. Right-click a pack to open it, then turn the cards over to reveal what you found. Or keep it sealed and offer it in a trade. Packs do not take up normal bag slots.

![The Warcards Satchel, shown empty before any packs have been found](../media/gallery/satchel.png)

<!-- Still needed: a real pack-opening capture with cards being revealed. -->

## Trade with friends

Right-click another player and choose **Trade cards or packs**. Offer a card from your binder or a sealed pack from your satchel. Both players review the final offer and accept before anything moves.

Sending a gift works the same way: the receiving player leaves their side empty, and both players accept. Mark missing cards in your **Wanted** list to make it easier to find a swap.

Both players need the companion set up and a **Ranked** binder. Trading and gifting are disabled in Casual. Cards and packs are addon-owned items, so trades use the Warcards window rather than the game's mail or auction house.

![The card trade window with a Dragonmaw Bonewarder offered](../media/gallery/trading.png)

## Fill a guild binder

Open **Guild** to browse a full shared binder, with the same index, card pages, missing slots and edition previews as your personal collection.

Choose **Add cards** to open your own binder at a spare copy. Click cards to select them, or use **Add one copy to tray** for extra copies. Spare copies are offered first; **All owned** lets you include last copies. **Review selected** lists the batch before anything leaves your binder. Remove cards or keep choosing, and check the last-copy warnings before confirming.

Use **Guild index** at the top to return from any section. **Cancel donation** clears the selection without moving cards. New confirmed donations show the latest donating character; older donations may not have a recorded name.

Donations are permanent: copies leave your collection and stay with the guild, even if you leave. Nobody can withdraw them, including officers. Donated copies appear as **Waiting for sync**; they do not add to confirmed ownership, completion or points until accepted.

Keep companion **1.0.6** open. After confirming the batch, click **Save & sync** once to save it with a reload. The companion syncs automatically. Once it finishes, click **Refresh after sync** to load the reply. You do not need to switch apps or sync after every card. If the server cannot accept a donation, the copy returns when the addon loads the reply.

Create or join through the companion. New guild binders are ready immediately, and their owner approves member applications. Forever characters have first names and surnames; everyone uses the same Forever world for guild lookup.

Wanted lists are still available from the Guild page or with `/acb wanted`.

## Collect together

The Fellowship set rewards the things you do with other players: trading, gifting, donating to your guild binder and sitting at a campfire. Collect all four for the Better Together achievement and Fellow Traveler title. An active campfire buff also boosts common and rare creature-card finds.

## Collect alternate editions

Some cards have separate collectible editions with different poses or animations. Inspect the 3D portrait and rotate it by hand; rarer cards and special editions can have extra movement or looping animations.

<!-- Still needed: an actual alternate-edition comparison screenshot. -->

## Cards from both sides of Azeroth

Some bonus cards can only be earned by one faction. Trade or receive them as a gift to add the other side's cards to your binder. These extras are not required to finish a set and are not selected for seasons.

The collection includes expanded dungeon and raid card lists. Cards tied to known unkillable creatures or one-off encounters are excluded from collection goals and seasonal lists. Copies you already own stay in your binder when the available card list changes.

## Achievements and titles

Work towards achievements for collecting cards, finishing sets and trading. Earn and equip binder titles that other players using the addon can see in your tooltip.

![Collection achievements showing card and set progress](../media/gallery/achievements.png)

## Seasonal collections

When a season is running, everyone gets the same list of cards to collect before the deadline. Seasons run alongside your normal Ranked binder: fresh copies earned from drops, packs or trades can count towards both collections.

Copies you owned before the season started do not fill its slots. Everyone who finishes in time receives the listed rewards, with extras for the first finishers. Keep the companion running and save and sync before the deadline so your progress is recorded.

Some cards are held back from the launch collection and return through seasons. Once a season releases them, they stay available. Cards you already own are kept when the catalog changes.

<!-- Add an actual Seasons screenshot from the uploaded build before submission. -->

## Getting started

1. Put the **AzerothCardBinder** folder inside **Interface/AddOns** in the Forever installation you actually launch. The `.toc` file should be directly inside that folder.
2. Enable **World of Warcards** in the character screen's AddOns list. Open the binder from the minimap button or type `/acb`. Open the satchel with `/acb bag`.
3. Choose your collection mode before finding your first card.

**Casual** works with the addon alone. **Ranked** uses the separate Windows companion for trading, gifting, seasons and the online ladder. Sign in through Discord, choose your game folder and keep the companion running while you play. It syncs after `/reload` or logout; it does not automate gameplay.

For Ranked setup, `/reload`, wait for the companion to finish syncing, then `/reload` again to load the returned setup. Check that the binder says **RANKED / Ready** before collecting. A successful sync does not convert cards already found in Casual into Ranked cards.

![The Windows companion app with a synced Ranked binder](../media/gallery/companion.png)

Install matching addon and companion updates, updating the companion first when a release requires it. **Updates keep your cards, packs and saved progress.** Keep your game's `WTF` folder and existing saved data. Starting a new binder is a separate, deliberate choice.

<!-- Keep the companion description factual and the homepage link in the footer.
     Do not add direct external EXE links or bundle an installer with the addon. -->

## Make it comfortable

In **Settings**, choose whether to show card pop-ups, tooltip hints, the zone bar and 3D portraits. Switch pickup, pack, trade and window sounds on or off separately. Shift-drag the satchel button to move it.

The **Chat** page has optional guild announcements for card and pack finds. Choose a minimum rarity for guild card messages so every common find does not fill guild chat.

## Known issue: loading screens

Some Forever players using DirectX 12 have reported stuck loading screens with repeated desktop flickering. **Warcards' 3D models may make this issue more likely or worse.** The bounded model preloader added in 1.0.10 reduces graphics-resource use, but is **not a confirmed fix**.

**If it happens:** press Enter, type `/reload` and press Enter again if chat still responds. This has recovered an affected session, but is not guaranteed. If it fails, close the game with Alt+F4 and relaunch it. Forced closure can lose finds since the last normal save. You can also turn off **3D card models** in Settings to reduce model work.

See the [known issues and troubleshooting steps](https://github.com/Imokim2/azeroth-card-binder/blob/main/KNOWN-ISSUES.md) before installing. We are still investigating; the matching client reports do not establish an official diagnosis or a confirmed Blizzard fix.

## Help and feedback

Open **Settings → Help → Report a bug** in the binder and copy the link into your browser. It includes basic game details; add what happened and what you were doing. You do not need to diagnose the cause first. Please include your companion version if you know it.

Join the **World of Warcards Discord** for setup help, bug reports, known issues and update notices. Show off your binder, find people to trade with or talk about the next season.

[Community Discord](https://worldofwarcards.co.uk/discord) · [Report a problem](https://github.com/Imokim2/azeroth-card-binder/issues/new/choose) · [Source code](https://github.com/Imokim2/azeroth-card-binder) · [Website and help](https://worldofwarcards.co.uk/help)

World of Warcards is free and open source under GPL-3.0-or-later. It is a fan project, not affiliated with or endorsed by Blizzard Entertainment.
