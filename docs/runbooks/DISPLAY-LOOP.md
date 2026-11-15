# Fullscreen minimise/restore investigation

Status: actual DX12 allocation/recovery failure captured; the trigger is not established. Addon 1.0.10 bounds the preloader's scene allocation. At the user's request on 15 November 2026, carry this as a disclosed [known issue](../../KNOWN-ISSUES.md) on GitHub and the prepared CurseForge page. Do not describe the mitigation as a confirmed resolution or assume Blizzard has acknowledged a specific cause or delivered a fix. CurseForge submission remains a separate action requiring the user's instruction.

Players reported the whole client repeatedly minimising and restoring roughly twice a second, during loading and a flight path, with the binder closed. It needed a forced exit. A sync-warning focus path in companion 1.0.0 was real and was removed in 1.0.1, but the affected player did not see the companion appear or a sync error. That path has not been established as the cause. A later recurrence was captured with companion 1.0.1 running.

Addon 1.0.5 removes 3D pickup models, releases hidden/transition models and suspends them on taxis. These are mitigations. Card motion changes in 1.0.6 are artwork changes, not another claimed display-loop fix.

Addon 1.0.7 restores pickup models when the player's 3D setting is enabled, correcting the unconditional icon-only popups introduced in 1.0.5. Notifications wait through loading/world transitions and taxi travel, preserve their queue and visible lifetime, and use the existing model-release-on-hide lifecycle. Disabling 3D still gives 2D notifications. This removes the blanket pickup-model suppression, so include normal card finds in further stability testing; the original loop is still unresolved.

## Captured failure on 15 November 2026

### Reported temporary recovery

The user later reported that the client still accepted chat input during the fail loop. Typing `/reload` allowed it to finish loading normally. Add this as the first recovery attempt when input remains responsive; it is a player-observed workaround, not a guaranteed fix. A successfully completed reload normally writes SavedVariables, but do not promise that graphics-failure recovery always preserves progress. If typing or reloading fails, Alt+F4 followed by relaunch has also allowed affected players to enter normally, with the usual risk to unsaved finds. Preserve `Logs/gx.log` before a full relaunch where possible.

The recurring locations overlap with other player reports, which supports investigating the client transitions as a common trigger. That overlap does not establish independence from Warcards: the other players' addon lists and reproduction conditions are unknown. Likewise, recovery through `/reload` resets addon UI and Lua state as well as UI-related client resources, so it does not by itself isolate the addon or the native renderer as the cause. Ask for the versions, location and what recovered the session; players need not diagnose the graphics log themselves.

### Captured graphics failure

At 00:06:48 UTC, while entering Razorfen Kraul, the client's graphics log first recorded `OutOfMemory: AllocDescriptors Failed` and `OutOfMemory: RTV view create failed`, followed by a lost device on the loading screen. The first device-recovery restart followed at 00:06:48.897; the preserved live copy reached recovery occurrence 138 at 00:09:09.420. The player confirmed using a binder earlier in that game session. The game did not recover and the player forced it closed. They have also experienced it at the Deeprun Tram and Blackfathom Deeps. Evidence copies are local and ignored under `.local-tools/display-incident-20261115-000731/`; never commit or upload the raw files automatically.

At the first failure, reported GPU memory use was about 4.4 GB against a 9.3 GB budget. This establishes allocation failure and repeated renderer recovery; it does not by itself establish ordinary VRAM exhaustion or which component caused it. The active companion executable was verified as 1.0.1. Installed addon files were 1.0.9; the exact Lua version loaded at that moment was not independently confirmed. Versions 1.0.7 through 1.0.9 share the relevant model-loading code.

The recorder started after the loop was already underway and its output was preserved too. It includes normal user interaction with other applications, so foreground changes alone cannot identify a cause at onset. The graphics log establishes the recurring renderer failure rather than merely an inferred focus issue.

A [7 November Forever bug report](https://us.forums.blizzard.com/en/wow/t/wow-forever-deeprun-tram-loading-screen-hang-infinite-dx12-device-recovery-loop-rx-9070-xt/2404609) describes the same allocation/recovery sequence on a Radeon RX 9070 XT; this captured PC uses an RTX 3080. Replies also mention Blackfathom Deeps. That supports a client DX12 failure affecting more than one setup. The report does not establish which addons were installed, so it does not exonerate or implicate Warcards.

### Model-pool correction in 1.0.10

Source review found that portrait warming created a separate `PlayerModel` frame for every unique NPC in the largest visited set, per folio. Clearing model content did not destroy those frame objects. The frame pool was unbounded by a fixed scene budget. This is an identified resource-growth problem and a plausible contributor, not a proven native descriptor leak.

The preloader now reuses at most four scene frames per folio, regardless of category size or how often sets change. It still visits every unique model, deduplicates editions, retries failed requests once, and clears scenes during transitions or closure. Only the workers' most recent loaded scenes are retained, so a previously warmed model may need loading again when shown. Visible card widgets keep their existing 3D artwork and controls. Tests exercise 200 NPCs across repeated category changes and assert that the frame pool never grows beyond four.

Fully exit and relaunch WoW after installing 1.0.10 so the old UI session's frame objects are gone. Keep the recorder running during normal group testing. A short successful run does not establish a fix. If recurrence persists, preserve `gx.log` before restarting and compare with the companion fully quit, then with 3D models disabled, changing one variable at a time. No renderer settings, drivers or saved progress are modified by this correction.

## Recurrence reported on 14 November 2026

Harry and Nick both reported another dungeon-entry loop. Harry was confirmed to have addon 1.0.7. Nick may have updated from an earlier version immediately before entering; whether he actually reloaded the UI or restarted the game is unknown. Changing zones or entering a dungeon does not load newly installed addon files. Nick recovered by repeatedly pressing Escape. Neither exact companion version nor which Warcards windows were open has been confirmed.

This is evidence that the 1.0.7 mitigation was insufficient in at least one affected setup. Addons 1.0.8 and 1.0.9 did not change `CardModels.lua`, `Cards.lua` or `Toast.lua`; do not present updating to 1.0.9 alone as another display-loop fix. Escape helping is a clue about UI/focus interaction, not proof that a particular Warcards window or the companion caused it.

Ollie's completed local recorder run from 17:46 to 18:46 UTC captured 132 state changes, zero minimised-game snapshots and zero companion-foreground snapshots. It did not capture the reported failure and cannot rule out the same issue on another PC.

For a comparable test, confirm the active addon version after an explicit `/reload` or game restart, and confirm companion 1.0.1. Capture the next normal session on an affected PC. Change one variable at a time: first keep the addon enabled and fully quit the companion; if it recurs, retain that setup and disable **3D card models**. A successful short test is not conclusive. Preserve the recorder output and `Logs/gx.log` from an actual recurrence before relaunching WoW.

## Evidence reviewed

- Local Windows Application/System events for the preceding two days contained no matching WoW, Warcards, DWM or display-driver failure in the queried events.
- The available WoW graphics log had no matched graphics-failure entries and did not contain a sustained twice-per-second focus sequence. It does not identify which other application held focus. A fresh launch may replace logs from the failed session.
- How to Train Your Kobold 0.12.3 source and installed version were inspected. Its scene uses 2D textures, its communication prefix is `KoboldDeep01`, and no 3D model creation, display-CVar changes or renderer-restart calls were found. This source review cannot exclude a client-level interaction between addons.
- WoW saves collection data on a normal reload/logout. Finds since the last save may roll back on a forced exit; do not reset a collection or edit a Ranked ledger to investigate this.

## Capture a recurrence

`tools/CaptureDisplay.cs` is a manual, read-only Windows diagnostic. It samples the foreground process and WoW's window bounds/visibility/minimised state at roughly 100 ms intervals, writing changes immediately to a local JSONL file. It does not focus windows, change graphics, inject into the client, capture titles/screenshots/keys, upload data or touch game saves. Process names for other foreground applications can appear; review before sharing. Its native reads use [GetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getforegroundwindow), [GetWindowThreadProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowthreadprocessid) and [IsIconic](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-isiconic).

Build this optional maintainer tool with the Windows .NET Framework compiler, then start it hidden before the test:

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /r:System.Web.Extensions.dll '/out:.local-tools\CaptureDisplay.exe' 'tools\CaptureDisplay.cs'
if ($LASTEXITCODE -ne 0) { throw 'Display recorder did not compile' }
Start-Process .local-tools/CaptureDisplay.exe -WindowStyle Hidden -ArgumentList '1800'
```

The default output folder is `display-captures` beside the helper, in the ignored `.local-tools` directory. The helper stops automatically. It does not need administrator access or any PowerShell execution-policy change. It is not bundled in the addon or companion, and never starts automatically. A first draft using a PowerShell script could not run under this machine's script policy; that draft was removed and no policy was changed.

The helper now defaults to 60 minutes when double-clicked without arguments. For affected testers, compile it with `/target:winexe` and package the executable with a short README in a standalone ZIP. They can double-click it immediately before testing, without a terminal or script-policy change. It writes only window/focus observations locally and does not diagnose or repair the problem automatically. Do not start this manual recorder for someone without their action or instruction.

When the loop happens, record the approximate time, whether it started during loading/flight, and the exact addon/companion versions and enabled addons. After exiting the stuck client, preserve `Logs/gx.log` before starting WoW again. Keep the JSONL local until reviewed. A foreground process alternating with WoW would support a focus-interference hypothesis; WoW staying foreground while its own window changes needs a different investigation. Neither result alone identifies a specific addon.

## Controlled tests before public release

Keep the client, graphics settings, character and dungeon/flight route consistent. Change one component at a time and fully quit the companion from its tray when a row says off. Do not delete saved variables.

| Run | Warcards | Kobold | Companion | Purpose |
| --- | --- | --- | --- | --- |
| A | Off | Off | Off | Establish whether the client fails independently |
| B | On | Off | Off | Isolate the card addon |
| C | Off | On | Off | Isolate Kobold |
| D | On | On | Off | Check the addon combination |
| E | On | On | On | Compare the companion's involvement |

Use the latest mitigations for B/D/E. If the issue occurs with Warcards, repeat that same configuration with **3D card models** disabled in Settings. This disables model requests but still creates empty model widgets; it does not exclude every engine interaction with model frames.

A short successful run is not proof for an intermittent failure. Collect repeated loading/flight sessions from affected players and preserve any recurrence trace before declaring the issue resolved. Keep the public known-issue notice current. The user has requested disclosure rather than an automatic publication hold for this issue; follow the separate CurseForge submission plan before publishing there.
