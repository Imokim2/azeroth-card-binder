# Per-copy card history: first test build

Ships in addon 1.1.0 and companion 1.0.8, bundled with scheduled bonuses and the dungeon announcement fix. The website and signed companion feed provide the matching releases. Existing binders are kept.

## What players can do

Newly found cards record their original finder, actual acquisition location, date and source. A pack card records its opener and the place it was opened. Crafted cards say Created by. Individual duplicates receive different copy IDs. The origin stays unchanged through a gift, a later trade and a reload. The last giver and total number of transfers are also shown; this version does not claim a complete list of every previous owner.

Open **Card history** beside the selected card in your binder. Previous / Next copy browses duplicates; **Use this copy** chooses the copy for your next offer or donation. Older copies have no fabricated origin. Both offered cards have a **History** button in the trade window. Accept waits for the revision-bound copy exchange, and changing an offer clears acceptance. The receiving inventory gets that exact record when the real transfer commits.

When viewing another player's personal binder, its Card history button requests that one copy from them. It respects their binder privacy setting and the game's existing outdoors/out-of-combat whisper restrictions. The owner must be online with this version. There is no proximity scan or automatic history broadcast. Ordinary card links keep opening the viewer's own binder as before; they do not identify the sender's individual copy.

Both players need the new addon for card trades/gifts. Older card-transfer protocols are refused to prevent silently stripping history. Pack-only modern trades remain compatible. Companion 1.0.8 supplies the capability marker and refuses automatic backup restores that would lose or transplant copy records. Install that companion first, sync, then load the new addon and `/reload` to import its reply.

## Data and compatibility

`cardCopies[key]` stores encoded, bounded records for individually tracked copies. Existing untracked stock remains an implicit quantity, so installing the update never manufactures card records or changes counts. `cardCopyChoice` is a preference; `cardHistorySerial` and the existing binder nonce/head seed stable copy IDs without touching the drop RNG. `cardHistoryDonations` retains the transferred record by donation operation, allowing a refused donation to return the same origin. Guild catalogue origin sharing is not implemented in this first build; its existing latest-donor display stays as it was.

Copy records contain a 32-character ID, exact card key, original character name including the Forever surname, acquisition timestamp/location/source, last sender, received time, method and transfer count. They contain no Discord ID, email or credentials. The codec rejects unknown cards, bad lengths, invalid numbers, control/link markup and malformed UTF-8. No received string is evaluated as Lua. These are informational addon records, not a server certificate proving a player's location or ownership history.

History preserves ordinary spec 12 records; scheduled bonus attempts additionally use spec 13 (see docs/BONUS-EVENTS.md). The historical chain fields stay unchanged, and the catalogue remains 39500d3ae8ca. History itself leaves counts, tape rolls, drop rates and existing holographic entitlement unchanged. It does not award cards or affect Ranked scoring, and adds no server migration, extra polling or database writes. The separate scheduled-event feature has its own shared schedule table. History lives in the addon's saved file and travels through explicit addon exchanges; keep saved-variable backups. The server's account-data export does not include this local history.

## Transfer safety

The copy packet is hashed and acknowledged for both offer revisions before Accept becomes available. Replies from a foreign player, session or revision are ignored. Packets stay within 250 bytes, use the existing trade prefix and are paced alongside ordinary trade messages; missing packets/acknowledgements are retried. A changed fingerprint for the same revision stops the offer. The chosen copy is checked again at commit, incoming duplicate IDs are refused, and accepted offers reserve their named copy or one untracked legacy copy against recycling/donation. Cancellation does not debit or create copies.

The view service requests one copy at a time, caps incomplete replies, paces and retries responses, respects privacy changes and ignores unsolicited, cancelled or expired replies. The history window contains text only and creates no additional model frames.

## Group test

1. Install companion 1.0.8, keep the game closed during installation, sync and load addon 1.1.0. Use an existing Ranked binder; do not start a new one.
2. Find a new card. Check its original finder, zone and date under Card history. Existing stock should say Not recorded.
3. Find another copy of that card. Verify its copy ID differs, select one with Use this copy and offer it to Harry.
4. Both inspect the offer's History, then gift it. Check counts and original details on the receiving side; reload both and inspect again.
5. Trade the same copy onward. Verify its original finder/location/date/ID still match, while its last sender and transfer count update.
6. Change an offer and cancel another after accepting. No copy or record should move in the cancelled case. The changed offer needs a new history exchange and acceptance.
7. View the recipient's personal binder from the other character. Request Card history, then test a private binder and an offline/old-version owner. Only requested, permitted history should appear.
8. Test a pack, a crafted card, recycling another duplicate and a declined/refunded guild donation. Verify counts and retained origin records.

Automated coverage includes the real collection, transport and UI against game API stand-ins, plus companion backup safety. Actual client whisper delivery, font fit and group testing remain necessary before public publication.

## Verification

The combined candidate passes all 305 Lua checks and all 462 Node checks through `node tools/release.js build`, including companion recovery, shared contracts and server integration. Both type checks, the installer ASAR checks and its isolated executable startup also pass. The addon archive is `AzerothCardBinder-1.1.0.zip`, with companion `World-of-Warcards-Setup-1.0.8.exe`.
