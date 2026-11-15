# Known issues

## Loading-screen hangs and desktop flickering with DirectX 12

Some Forever players have reported loading screens that get stuck while the game repeatedly disappears and reappears on the desktop. Reports include the Deeprun Tram, Razorfen Kraul and Blackfathom Deeps. A UI reload has recovered an affected session; otherwise the client may need to be force-closed and restarted.

**Warcards may make this issue more likely or worse.** Its 3D portraits use graphics resources. Earlier versions also created a separate preload scene for every creature in a category. Addon **1.0.10** limits that preloader to four reusable scenes per binder view, reducing the resource growth we found. This is a mitigation, **not a confirmed fix** for the loading-screen issue.

We captured a failure in which the client could not allocate DX12 descriptors or create a render-target view, then repeatedly restarted its renderer. Its reported graphics-memory budget was not full. DirectX manages these descriptors separately from the resources they describe; see [Microsoft's documentation](https://learn.microsoft.com/en-us/windows/win32/direct3d12/creating-descriptor-heaps). An allocation failure does not by itself mean all VRAM is used. We have not confirmed the exact cause of the client failure or how much Warcards affects it.

There is a [matching player report on Blizzard's forum](https://us.forums.blizzard.com/en/wow/t/wow-forever-deeprun-tram-loading-screen-hang-infinite-dx12-device-recovery-loop-rx-9070-xt/2404609). It is not an official diagnosis or confirmation of a Blizzard fix. We will update this notice as the investigation and client patches provide more evidence.

If it affects you:

- **Try `/reload` first if chat still accepts typing.** Press Enter, type `/reload` and press Enter again. A player has reported that this let the game finish loading normally during the loop. This is a reported temporary workaround, not a guaranteed fix. A completed reload normally saves addon data, so it is preferable to a forced exit when possible; we cannot guarantee progress is saved during a graphics failure.
- Use the latest addon and fully exit and relaunch WoW after updating. You can try switching off **3D card models** in the binder's Settings to reduce model work; this is not a guaranteed workaround.
- If typing or reloading does not work, use **Alt+F4** to close the stuck client, then launch it again. Restarting has allowed affected players to enter normally. A forced exit can lose finds since the last normal saved-data write, such as a `/reload` or logout.
- Before relaunching, keep a copy of the game's `Logs/gx.log`. When [reporting the problem](https://github.com/Imokim2/azeroth-card-binder/issues/new/choose), include the location, addon and companion versions, and whether the binder had been used earlier in the session. Review logs before sharing them publicly.

You do not need to interpret the error log to report this. Tell us where it happened and whether `/reload`, Escape or restarting helped; leave anything you do not know blank.

For the technical investigation and controlled test steps, see the [display-loop runbook](docs/runbooks/DISPLAY-LOOP.md).

## Incorrect companion setup warning when choosing Ranked

Fixed in addon **1.0.12**. Earlier versions could tell a successfully synced Casual player to download the companion again when they tried to enable Ranked. The addon checked pairing before explaining that the binder already contained Casual finds. The same update recognises established synced binders when companion 1.0.1 no longer lists them as untouched starter collections.

A successful sync does not convert Casual cards into Ranked cards. Keep that binder in Casual, or deliberately start a fresh active binder if you want Ranked. Starting over replaces the active collection; it is never required just to install an update. Ask in the [community Discord](https://worldofwarcards.co.uk/discord) if you are unsure. The correction does not reset cards or history, and companion 1.0.1 remains current.
