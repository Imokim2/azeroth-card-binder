# Fullscreen minimise/restore investigation

Status: unresolved; do not describe 1.0.5/companion 1.0.1 as a confirmed fix or clear the public-release gate on automated checks alone.

Players reported the whole client repeatedly minimising and restoring roughly twice a second, during loading and a flight path, with the binder closed. It needed a forced exit. A sync-warning focus path in companion 1.0.0 was real and was removed in 1.0.1, but the affected player did not see the companion appear or a sync error. That path has not been established as the cause. The updated pair has not yet been tested together by that player.

Addon 1.0.5 removes 3D pickup models, releases hidden/transition models and suspends them on taxis. These are mitigations. Card motion changes in 1.0.6 are artwork changes, not another claimed display-loop fix.

Addon 1.0.7 restores pickup models when the player's 3D setting is enabled, correcting the unconditional icon-only popups introduced in 1.0.5. Notifications wait through loading/world transitions and taxi travel, preserve their queue and visible lifetime, and use the existing model-release-on-hide lifecycle. Disabling 3D still gives 2D notifications. This removes the blanket pickup-model suppression, so include normal card finds in further stability testing; the original loop is still unresolved.

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

A short successful run is not proof for an intermittent failure. Collect repeated loading/flight sessions from affected players and preserve any recurrence trace before declaring the issue resolved. Do not release on CurseForge while the cause or stability remains in doubt.
