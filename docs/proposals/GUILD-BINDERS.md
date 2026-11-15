# Guild binders

Status: proposed next feature; not implemented or advertised as available.

## Agreed behaviour

Donations are permanent. The player chooses an exact card edition, reviews a clear warning and confirms. A successful donation removes that copy from their personal binder and adds it to the guild binder. Nobody can withdraw it, including officers and the guild leader. Donating the last personal copy leaves that personal slot empty.

The guild collection has its own progress and public ladder. Personal scores reflect the cards the player still owns. Existing achievements and seasonal credit need an explicit policy before implementation; a donation must never create another acquisition or reward claim.

## Player flow

Open Guild binder, choose Donate, pick a card using the existing binder picker, then confirm the card, edition, quantity and receiving guild. Show a pending donation until the server confirms it. Disable another donation of those copies while pending.

The current bridge exchanges files when the game saves and loads server data on login or /reload. It cannot deliver an immediate live server response to the running addon. The first implementation should explain when a save and reload are needed rather than showing success before confirmation. A failed donation leaves the card available; an uncertain result remains pending until reconciled.

Reuse the card picker, renderer and confirmation styling from trading. Use a dedicated server transaction rather than treating the server as a player in the peer-to-peer whisper protocol.

## Ownership and reliability

The server owns the guild inventory and validates donations against the verified Ranked collection. Give each donation an operation ID. Apply the personal debit, guild credit and donation receipt atomically. A retry, old saved file or repeated request with that ID returns the original result and cannot donate twice. Validate the exact edition, quantity, eligibility and current membership before committing.

Use a stable internal guild ID with realm and display name. Do not recreate or empty a binder when a leader changes, a guild is renamed or a member leaves. Preserve an audit record of donor, card, quantity and time. A simple donation history helps resolve mistakes without granting withdrawals.

Membership needs a separate decision before coding. Personal binders are account-wide, while guild membership belongs to individual characters. A sensible starting point is one enrolled guild per Ranked account, selected from a registered character and approved by the guild owner. Guild names and rosters in editable addon files are claims, not proof of membership. Stronger verification needs a trustworthy source or a moderated enrolment process. An account must never donate the same copy through several alts or guilds.

## Keeping server use low

Write only for confirmed donations and membership changes. Cache guild summaries and the guild ladder; fetch them when the guild page opens or a player asks to refresh. Keep the existing saved-file sync behaviour and avoid idle polling by every member. Update the displayed totals after confirmed donations, allowing a short cache delay on the public ladder.

Cost should follow donation volume and occasional views, rather than the number of online members multiplied by frequent refreshes. It will still use database reads, writes and storage. Measure those operations with realistic guild sizes before estimating a bill. Cloudflare D1 supports transactional batches; its [database API](https://developers.cloudflare.com/d1/worker-api/d1-database/) and [pricing](https://developers.cloudflare.com/d1/platform/pricing/) describe those constraints.

## Release boundary

This needs coordinated server, ledger, addon and companion bridge changes, plus migration and retry tests. Keep it separate from the current support/community release. Test duplicate submissions, interrupted saves, failed requests, old-client uploads, last-copy donations, edition identity, member departure and leaderboard rebuilding before enabling it. No guild database, migration or live donation endpoint has been created by this proposal.
