# Scheduled bonus events

The first implementation boosts card acquisition rolls for companion-paired Ranked binders. It does not grant cards, change existing copies, increase pack sizes or affect crafting/trading. Existing card history ships in the same addon 1.1.0 candidate, with companion 1.0.8 and server 1.1.0.

## Scheduling

Sign into `/admin` on the website with the existing admin credentials and choose **Bonus events**. Set a name, local start date/time, duration (60 minutes by default), card-drop multiplier and either all collections or chosen sets. Review the confirmation before scheduling. The browser converts the chosen local time to an absolute UTC timestamp, so players in different time zones receive the same interval. Published rules are immutable: no editing/deleting an event that clients may already have loaded. Events can last 5 minutes to 24 hours, start within 30 days and use a multiplier between 1.01x and 5x. The form offers 1.5x, 2x, 3x and 5x.

This release is scheduled-only. WoW reads Sync.lua at login or `/reload`; a companion write cannot hot-load a new event into a running client. Schedule in advance and ask players to sync and load the schedule before its start. If a manual /reload triggered a companion sync, wait for the app to finish and /reload again to load its answer. Loaded future events start/end without further syncs, including while the binder is closed. There is no fixed daily schedule or recurring timer.

The companion fetches the public schedule on startup and ordinary saved-progress syncs, with no additional periodic polling. The public answer is edge-cacheable for five minutes and contains no player data. Upcoming data covers 30 days and at most 64 events. A server without the new endpoint supplies no bonus; normal collecting remains available. Sync.lua pairs the schedule to the successfully synced binder nonce. This proves pairing, not whether a desktop process is currently alive.

## Player experience

A chat notice and optional event sound announce each activation once. The binder header between its title and First Edition shows the event, multiplier and remaining time. Hover for affected collections and other active events. The highest eligible multiplier applies to each card; events do not multiply one another. Existing campfire rules still apply, and their eligible rolls can also receive an event bonus. A new **Event alerts** sound setting mutes the cue without hiding the notice/countdown. Event expiry flushes pending attempts and removes the badge.

Dungeon public-chat messages are a separate client restriction: the addon's automatic announcements still obey `C_ChatInfo.InChatMessagingLockdown()`. A blocked dungeon/raid find offers a local **Share this find** link that opens a prepared party/raid/instance/guild message. The player presses Enter to send using the game's normal chat box. It never retries through another channel or sends a restricted message automatically. The generated client API describes the lockdown flag as chat API security restrictions: [ChatInfo documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua).

## Ranked compatibility and rollout

Migration `0021_bonus_events.sql` adds a small shared schedule table. Run it before deploying the new Worker; keep all historic definitions permanently for late offline uploads and rebuilds. Scheduling is authenticated, audited and rate-limited by the existing admin controls. Reading the schedule writes no per-player database rows.

Ledger spec 13 adds two reserved attempt markers: partner `bonus` or `camp-bonus`, with trade `<event-id>:<first-attempt-unix>:<last-attempt-unix>`. Every existing hashed field, chain and catalogue key stays unchanged. The companion submits spec 13 only for batches containing those actual drop/miss markers; ordinary batches stay spec 12, so a player named Bonus remains a valid trade partner. The server verifies the official ID, source set, interval, multiplier and tape outcome, and rebuilds use the same archived definitions. Miss runs preserve their original first/last times when saved or flushed after expiry. Invented, wrong-set, out-of-window and future claims are refused.

This inherits the ledger's existing limits: it cannot prove that a kill happened or independently observe every client timestamp. A schedule is authoritative server content; it is not a new proof of real gameplay. Detailed verification belongs in maintainer docs, not the public rules page.

Deploy the backwards-compatible server/migration first, then test matching companion/addon builds. Do not activate a production event just to verify installation. No live event, new domain, account plan or paid service is required by this change.

## Group test

1. Keep the existing binder. Install the matching companion/addon and sync, then load the reply with `/reload`.
2. Schedule an event a few minutes ahead on the test server. Confirm the local-time preview and selected sets.
3. Before its start, load the schedule and close the binder. The notice/sound should happen at the start; opening the binder should show its countdown.
4. Try an eligible and an excluded source, and an overlapping lower/higher event. Check the effective marker and later server acceptance. Try the normal campfire buff as well.
5. Leave a miss run open at expiry, save/reload and sync later. Its original attempt interval and normal inventory must remain intact.
6. Mute Event alerts, reload during the event and test Casual/unpaired binders. They should not get repeated cues or Ranked event drops.
7. In a dungeon with chat lockdown, collect a card and click its local Share link. It must prepare a message without sending until Enter. Group/guild changes invalidate the old channel draft.
8. Gift a newly found copy onward and inspect its original finder/location/date to check the bundled history feature.
