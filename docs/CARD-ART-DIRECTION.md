# Card frames, shared poses and collectible editions

## Try the frame designs

Open **Card design studio** in Settings, or type `/acb studio` (`/acb designs` also works). `/acb studio Foe Reaper` previews a particular card. The gallery compares the current First Edition frame with three new treatments using the real `ACB.createCard` renderer:

| Design | Treatment |
| --- | --- |
| First Edition | Existing stone frame and rarity-coloured gems |
| Archivist | Parchment text panel, antique brass, engraved corners |
| Runebound | Midnight blue, silver rails, arcane detail |
| Sovereign | Black enamel, layered gold rails, crown ornament |

All are 136 × 190 with the existing model window, text fitting, foil, missing-card finish and count badge. They use native frames, borders, textures and font strings; no browser, shader, custom mask or new bitmap asset is required. The regular binder retains First Edition while these alternatives are reviewed. The studio can compare base and holographic finishes, rotate the portraits, and preview the authored editions below. Studio counts are illustrative and never enter saved collection data or the ledger.

## Shared artwork assignments

`CardPresentations.lua` defines the shared presentation content. An epic or legendary without a manual camera preset gets a deterministic selection from the fixed `signatureV1` pool using its catalog key. This does not call `math.random`, use the clock, or change the collection's drop roll sequence. Everyone using the same addon content gets the same assigned camera, facing, animation and frozen frame. Different cards can have different artwork without randomising each time they are viewed.

Keep the v1 pool's order and size fixed. To refine a particular creature, add a manual preset in `CardModels.lua`. Do not change the pool to add a new pose: that would change existing assignments. Use explicit card overrides or a separately versioned assignment for future content. Existing hand-tuned Deadmines and Westfall presets keep their original composition.

The selected owned detail can play a designated living portrait; miniature cards freeze on the corresponding frame. Dragging still turns the model. Right-click an animated detail to pause or resume its animation. Playback uses `HasAnimation` and `SetAnimation` where available; missing or unsupported calls fall back to a still pose. Each authored animation has a replay interval, so one-shot actions can repeat without a per-frame animation reset. Hiding the parent stops its update handlers.

The browser comparison uses existing character illustrations in place of game models and is labelled accordingly. Model framing, supported animations and timing must still be checked in Forever itself. The API definitions consulted are Blizzard's exported [character model API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICharacterModelBaseDocumentation.lua) and [model API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleModelAPIDocumentation.lua), mirrored from the client UI source.

## Collectible editions

Sixteen collectible variants are now implemented for eight bosses across Deadmines, Shadowfang Keep, Scarlet Monastery and Blackfathom Deeps. Their ownership is separate; a three-button strip below the large card shows counts or Locked. Any edition counts for the creature in ordinary sets.

The rarity icon now sits on the divider above the description: circle for Common, square for Rare, diamond for Epic, hexagon for Legendary and star for special editions. The nameplate keeps its full width.

See [COLLECTIBLE-EDITIONS.md](COLLECTIBLE-EDITIONS.md) for the content table, initial drop rates, inventory/trade behavior, version-4 ledger contract, tests and rollout requirements. The design studio remains a preview gallery and does not grant cards.
