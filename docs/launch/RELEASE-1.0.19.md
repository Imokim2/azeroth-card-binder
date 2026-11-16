# Full guild binder and batch donations: addon 1.0.19

Guild collection browsing and donation selection now reuse the actual personal folio renderer: index, four-card pages, missing slots, collectible editions, model previews, parchment, fonts, colours and card frames. Guild controls remain inside the parchment margins; normal binder and trading navigation retain their existing layout and behaviour.

Donate cards opens at a spare copy. Cards and extra copies are selected into an in-memory tray; no copy leaves until the full review is confirmed. Review supports removing entries and continuing selection, labels each last copy separately and warns about permanent removal. Membership, inventory, Ranked history and batch capacity are rechecked. The existing signed per-copy donation protocol and receipts are unchanged.

Unconfirmed copies are projected into guild pages with explicit Pending/Waiting labels. Confirmed ownership, progress, index ownership filters and points exclude them. Settled receipts and other guilds are excluded from the projection. Save & sync saves a whole batch with a reload; the companion's existing watcher syncs automatically. The button becomes Refresh after sync for loading the reply. Keep companion 1.0.5 open; its canonical download is byte-for-byte unchanged.

PR #71 merged as 5c97d74, tag v1.0.19. CI 43841705497 and release workflow 43842302222 passed, including 262 Lua checks and Windows checks. Tests cover 50-copy mixed-card batches, cancellation, removal, repeated acceptance, last-copy warnings, stale membership/inventory, receipt projection, index ownership and reload state. The actual published ZIP has 107 safe entries, all TOC modules, exact new guild/folio source and an empty factory Sync. Its checksum and trusted signature verified, and installation preserved two fixture accounts, both backups and Ranked Sync byte-for-byte.

Staging passed service and exact signed-feed/download checks before production publication. The website help describes the batch flow. No server migration, catalog change, minimum-version increase, companion update or player save edit is required. Visual/group donation testing in the actual game remains for the players; automated UI checks do not claim an in-game visual pass.

Addon SHA-256: aeac2e4379cfe6d6b0ebd19ebf2c35f8dcbf31d2690b77d8a94f90d65851e6a3.
