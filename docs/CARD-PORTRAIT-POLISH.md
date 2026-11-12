# Group-test UI and portrait pass

Addon 0.6.1 and companion 0.4.1 address the first group-test list. Satchel slots take the native bag button's size and effective scale when available, with a 36 pixel fallback. Empty slots use the game's backpack texture rather than the padded character-equipment slot artwork. Shift-drag moves the satchel launcher and General settings resets it. The header portrait has a circular texture mask. The satchel root sits above the binder's deepest model layers so its background and controls draw together.

Incoming trades/gifts show the sender and View trade/Decline controls for up to 15 seconds. Repeated protocol invites do not create new notifications. The existing Trade sound switch controls the cue. Accepting remains in the trade window; notices never accept a trade. Range is checked on trade actions and reports an out-of-range warning. Existing saved range/kill switches no longer disable normal distance checks or no-loot kill rolls.

The Packs button and debug/testing, duplicate title, range and kill settings were removed. Support slash commands remain available. Titles stay in Achievements. The companion hides its roll count; the internal Ranked supply is unchanged. NSIS assisted setup offers an install folder; normal in-app updates keep the existing destination.

## Portraits

The selected set preloads up to four unique creature/node resources together. Each completed model retains its resource instead of clearing the only scratch frame. Variants share a resource. The previous set is released when selecting another; closing the collection stops active work while preserving the current set. Slow requests retry once. The loader renders behind opaque parchment, rather than relying on almost-transparent frames.

Cards apply their authored action before their camera and reapply after late loading/visibility changes. Leaving an interactive detail resets its temporary turn. Boss variants retain their distinct animation and crop, with front-facing angles and zero sideways offsets. Critter face variants keep their deliberately close crop.

Every live category selects a packaged painting. Existing dedicated Elwynn, Westfall and Deadmines paintings have priority; other places use a suitable shared biome. These are themed illustrations rather than exact game-location captures. `CardBackdrops.lua` holds those choices; client journal/loading/map artwork and the final gradient remain fallbacks if a painting cannot load.

## New image assets and prompts

Built-in image generation produced six separate paintings, inspected before conversion. Final client assets are `AzerothCardBinder/Art/Scenery/{Snow,Desert,Swamp,Ruins,Volcano,Coast}.tga`, each an uncompressed 512 × 512, 24-bit texture. `tools/import-portrait-art.py <source-png> <name>` only converts/resizes a selected finished painting. The original generated PNGs remain outside the repository in the image-generation output directory.

Each final prompt used this prefix:

> Create ONE finished background painting for a World of Warcards collectible card portrait. Match painterly classic World of Warcraft environment art: visible delicate brushwork, believable atmospheric perspective, soft cinematic light, detailed outer edges and a clear relatively quiet mid-tone centre to place a character's upper torso in front. Square 1:1 full bleed image, landscape environment, no characters or creatures.

Then the matching scene:

- **Snow:** Snowy mountain pass with frost-covered pine trees framing both sides, distant blue peaks and a dwarven stone arch. Cold blue, soft snow white, muted amber lantern.
- **Desert:** Dry red sandstone canyon and arid savannah, thorny acacia silhouettes at edges, distant mesas and weathered stone ruins. Ochre, warm sand, red clay and dusty blue sky.
- **Swamp:** Misty marsh with gnarled dark trees, hanging moss at edges and luminous shallow green water, distant ruined watchtower. Moss green, muted teal, soft mist.
- **Ruins:** Atmospheric ancient gothic ruined monastery courtyard, weathered stone arches at edges, distant crimson-roofed tower and subtle candles, misty night. Slate stone, muted crimson, pale blue light.
- **Volcano:** Deep volcanic mountain cavern with black stone pillars at edges, distant fortress bridge, glowing orange lava below, atmospheric warm smoke. Black basalt, ember orange, bronze.
- **Coast:** Rocky seashore and deep-blue tidal grotto, weathered columns framing edges, distant island cliff and waves. Sea blue, muted turquoise, warm weathered stone.

Each ended with: "No lettering, text, UI, frame, logo, watermark, objects in the foreground centre, collage or multiple panels. This is the [name] background asset."

## In-game checks

Compare the visible satchel slots against the native combined backpack at the same UI scale. Drag/reload/reset its launcher, overlap it with the binder, open a sealed pack, and verify the round header portrait and click targets. Test a gift/trade notification and an out-of-range acceptance attempt.

Open a large category without paging, wait for it to preload, then page to later cards. Compare a card's thumbnail and default detail before and after revisiting it. Check boss editions and animated cards in game: offline tests verify deterministic camera values and resource retention but cannot prove every creature's animation bounds or visual alignment in Forever. Capture any remaining badly framed card by name and edition for a specific override.
