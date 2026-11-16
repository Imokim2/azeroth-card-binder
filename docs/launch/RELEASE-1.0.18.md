# Forever full names and guilds: companion 1.0.5 / addon 1.0.18

Forever returns the character's surname as UnitFullName's second value. Existing signed peer identities use those two fields and remain unchanged. Guild lookup now uses one shared Forever world instead of partitioning guilds by surname. The companion shows first name and surname together, keeping selector values/signatures intact.

Migration 0019 normalizes guild metadata and enforces one live guild name across Forever. It does not touch ledgers, card inventories or donation receipts. Conflicting legacy guild names must be resolved before applying it. The user explicitly approved retiring their empty duplicate and moving their existing membership into the original owner's pending applications. That guarded correction preserved the original guild and its donated card; no player save was edited.

PR #70 passed full CI 43779240824. Source 1ed23ef / tag v1.0.18 passed release workflow 43779490450, including the actual packaged Windows startup and installer checks. The tagged lockfile's globalthis version label was subsequently corrected on main to match its unchanged resolved 1.0.4 artifact and integrity; executable inputs were unchanged. Published ZIP/EXE checksums and the trusted release signature verified. The actual addon update preserved two fixture accounts, both backups and existing Ranked Sync data byte-for-byte.

Both databases received migration 0019 after recovery references were recorded. Staging passed public checks and exact signed-feed/download checks before production publication. Companion 1.0.5 / addon 1.0.18 are served through the website and trusted updater; server is 1.0.4, with unchanged catalog and minimum supported versions.

The guild owner refreshes the companion's Guild section to approve member applications. Approved members sync and /reload to load membership into the addon. Existing collections and guild donations are preserved.
