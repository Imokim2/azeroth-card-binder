# Satchel rollout and playtest

Prepared source: addon 0.6.0, companion/server 0.4.0, ledger specification 6. The generated card catalog stays `5e7dcd9e5e29`. This builds on the chase-card changes and Harry's updater/domain work. Source preparation does not deploy Workers or publish installers/manifests.

Update the server, companion and both trading players' addons together. No SQL migration or inventory reset is needed. Old `saved.packs[zone]` entries remain five-card Epic packs. New Common and Rare packs are separate `zone:common` and `zone:rare` stacks. Back up normal saved data before the in-game test.

New found packs are 70% Common (1 card), 25% Rare (3) and 5% Epic (5), conditional on finding a pack; overall pack-find odds remain unchanged. Each card comes from the named zone. Chase weights remain in force for all pack tiers. Exact odds remain developer-facing.

Check on the Forever client:

- The satchel button appears above the keyring or bag bar without changing native controls. Check scaled UI and any custom action bars; `/acb bag` remains available if a bar hides or covers the launcher.
- The satchel has paged stacks with white, blue and purple borders and separate size/count labels. Names use `Pack: Zone` everywhere. Right-click each tier, verify only 1/3/5 faces appear, flip them and close early. Faces should preload behind the reveal.
- Trade one pack for a card, another pack, and as a gift. Both sides must accept. Change the offer after one accepts, cancel from either side, retry a dropped whisper, and confirm no duplicate transfer. The offered copy cannot open until removed/cancelled; spare copies can.
- Sync both players. Pending incoming packs confer no Ranked points until matched. Ranked-origin packs count when verified; Casual-origin packs and their opened cards remain unverified through further trades. Mixed found/traded stacks are treated conservatively. Casual pack finds are now themselves recorded as unverified provenance, so rebuild derived counters and run maintenance during the coordinated server rollout if older stored pack histories exist.

The addon cannot create native game items or transfer gold. Players may arrange a separate normal WoW gold trade, but it is not atomically tied to a pack gift and packs cannot be put on the native auction house. No automatic selling or payment promise is implemented.
