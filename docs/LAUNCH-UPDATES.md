# Launch update prompts

Companion 0.4.2 checks `/v1/releases` once on launch, before Discord sign-in or choosing the game folder. The controller verifies the release signature against the existing trusted key. A configured app opens its window when an installable update is found, rather than remaining hidden in the tray. A notice near the top shows both available versions and separate install/update buttons.

The player chooses when to install. Updating the companion asks for confirmation before downloading the verified installer and closing/restarting. Updating or installing the addon uses the existing verified archive, preserves `Data/Sync.lua`, backs up the installed addon and reports when a game restart or `/reload` is needed. An addon update needs a selected game folder; a companion update does not need a game folder or Discord sign-in.

**Check for updates** is available in the window and tray. **Sync collection** also checks immediately. Opening/focusing the companion, including reopening it from the tray or its shortcut, checks too; repeated focus changes reuse the last attempt for one minute. There is no idle update timer. Normal game-save syncs retain the six-hour update-check interval. The controller passes its launch response and original check time to the engine, avoiding a duplicate request or extending the cache age on an engine restart. The HTTP request timeout keeps an unreachable service from hanging indefinitely.

A running older companion retains its own check schedule until updated. It can discover this release with Sync collection or a full tray Quit/relaunch. Closing the window alone leaves that process running. Public release announcements can remain cached at the edge for up to five minutes after publication.

Tests cover signed-out launch discovery, a configured launch with only one release request, addon availability before sign-in, untrusted signatures, offline launch, declining companion installation and showing both update actions while the binder is already synced. Existing installation tests verify hashes, tamper rejection, addon backup/restore and consent. In-game data is never reset by an update prompt.
