# Addon sounds

Settings → Sounds has a master switch and separate controls for card pickups, packs, trades/gifts and windows. Turning a group off retains its saved preference through a master mute. Pop-up visibility is independent: a collector can have quiet pop-ups, or sounds without pop-ups. These controls apply to addon feedback; game audio and native UI sound settings remain the game's own controls.

The 13 original bundled mono Vorbis clips total about 117 KB. They are synthesized from struck tones, filtered noise and short envelopes, with no recordings or borrowed samples. `tools/make-sounds.py` contains the source; it uses NumPy, SciPy and soundfile 0.13.1. It also writes an ignored WAV listening reel and timing JSON under `outputs/sound-preview`. The waveform and encoded peaks are checked during generation; every cue is under two seconds, with a short fade to avoid abrupt sample edges. Playback uses the SFX channel and respects the game's sound-effects volume. Native sound-kit fallbacks are retained if custom playback is unavailable.

| Group | Feedback |
|---|---|
| Card pickups | Short warm common cue; rising rare/epic/legendary rewards; a separate shiny shimmer; a restrained paper tap for duplicates/crafting; a set-completion flourish |
| Packs | A find cue, paper anticipation during the shake, opening burst at the burst transition, paper at each flip and a reveal reward |
| Trades/gifts | One confirmation per completed local transaction, including modern retry-safe gifts |
| Windows | A quiet paper/leather cue on opening a previously hidden binder or satchel |

`Flip all` plays a musical reward only for the best remaining result, after that batch finishes revealing. It still plays the short individual paper flips. Manual flips retain their per-card reveal; weaker rewards do not interrupt a stronger cue already playing. Per-cue throttling limits rapid repeats. Playback has no influence on rolls, inventory or the ledger.

Use the four preview buttons in Settings → Sounds. `/acb sound test pickup`, `packs`, `trades` or `windows` does the same; `/acb sound stop` cancels delayed previews and stops returned addon sound handles. `/acb sound` toggles the master switch. Muting a group or leaving the Sounds settings cancels previews. Previews respect category/master mutes and never grant cards or open packs.

The standalone listening reel is about 18 seconds. Its order is: paper, common, rare, epic, legendary, shiny, pack anticipation, pack burst, pack found, trade, set completion, window, duplicate. It is a first sound-design pass; audition at the normal in-game SFX volume, including combat and repeated five-card openings.

In-game checks: mute pickups while leaving pack audio enabled; disable packs during an opening; mute all with previews pending; disable pop-ups while keeping audio; test duplicate vs new/shiny finds; finish a trade with a lost confirmation retry; and use both manual flips and Flip all. Confirm no overpowering stack of reward sounds and no audio after a muted preview was cancelled.
