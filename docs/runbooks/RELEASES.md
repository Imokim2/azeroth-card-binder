# Releasing: companion app, add-on and server

How an update reaches players, and how to publish one. Companion 0.4.0 checks at startup, on manual Sync and at most once
per six hours during saved-progress syncs (`GET /v1/releases`), with no periodic network polling while idle. Older companions
retain their previous schedule until updated. It tells the player when the app or the add-on is out of date, and can install either one with a
click, but only from a release that was **signed with our release key**: the app trusts nothing else.

## What stands behind it

- **The release key.** An Ed25519 key pair. The *public* half is built into the app (`app/src/releaseKey.ts`); the *private*
  half signs each release and lives only with whoever publishes. Lose the private key and no installed app can be updated
  by a new release (they would need reinstalling by hand); leak it and anyone can push code to every player. Keep it outside
  the repository, backed up, in a password manager.
- **The signed manifest** (`server/src/releases.json`): the version, address, size and SHA-256 of the installer and of the
  add-on zip, signed. The server serves it as it is; the app checks the signature, then checks every download against it.
- **Worker variables** (`server/wrangler.toml`): `MIN_CLIENT` (oldest companion app the server accepts), `MIN_ADDON` (oldest
  add-on that still gets Ranked roll tape) and, until a manifest is signed, `LATEST_APP` / `LATEST_ADDON`. Raising a
  minimum never needs a new signature.
- **Where the files live.** GitHub Releases on the public repository. The manifest holds plain `https` addresses, so any host
  would do, and the app downloads from the address in the signed manifest and nowhere else. The website's download page shows
  the same files, with checksums, from the manifest, and links to the releases page when `RELEASES_URL` is set.

## One-time setup

```
node tools/release-manifest.js keygen C:\path\outside\the\repo\warcards-release-key.json
```

This writes the key file and prints the public key. Put the public key in `app/src/releaseKey.ts` (the `RELEASE_PUBLIC_KEY`
line), commit it, and build the installer **with it**: an app built before that holds no key and cannot update itself.
The first installer players run has to carry the key, so do this before anything is handed out.

## Publishing a release

1. Bump the versions together (`node tools/release.js bump <version>` for the add-on; `app/package.json` for the app) and
   update `CHANGELOG.md`. Run `node tools/release.js check` and the tests.
2. Tag and push: `git tag v0.5.0` then `git push origin v0.5.0`. The release workflow (`.github/workflows/release.yml`) builds the
   add-on zip and the installer (`World-of-Warcards-Setup-<version>.exe`), checks and tests everything, and publishes a GitHub
   release with both and a `SHA256SUMS.txt`. (To build by hand instead: `node tools/release.js build` and `cd app; npm run dist`.)
3. Note the two download addresses on the release page (right-click each file, copy link). Download both files once and use
   those exact files for the signature in step 4: it hashes them.
4. Sign:
   ```
   node tools/release-manifest.js sign --key <keyfile> --app "app/release/World of Warcards Setup 0.3.0.exe" --app-url <https address>
       --addon dist/AzerothCardBinder-0.5.0.zip --addon-url <https address> --app-notes "What changed" --addon-notes "What changed"
   node tools/release-manifest.js verify
   ```
   `sign` warns if the key that signed is not the one built into the app. The add-on zip's file name must contain the add-on
   version.
5. Set `LATEST_*` if you rely on them (and `RELEASES_URL` in `server/wrangler.toml` once the repository is public: `https://github.com/<owner>/<repo>/releases/latest`), deploy staging, look at the result, then deploy production:
   ```
   cd server; npx wrangler deploy --env staging
   ```
   `GET /v1/releases` should now show the new versions and a `signed` block.
6. Players see the update after a release check; **Sync now** or restarting the companion checks immediately. **Update add-on** downloads the zip, checks it,
   keeps the old copy in the app's data folder (`addon-backups`), installs it and says to `/reload`. **Update companion**
   asks first, then downloads the installer and runs it; the app closes and opens again.

## Raising the minimum (pausing Ranked for old add-ons)

`MIN_ADDON` is the oldest add-on version that still gets new roll tape. Below it the server answers `addon_too_old` and gives
nothing; the add-on stops Ranked rolling once it learns the minimum (through `Data/Sync.lua`) or when its tape runs out.
Casual is never affected and nothing already earned is lost: tape handed out earlier stays valid.

Give players time first: announce the new version (step 4 and 5), wait a week or so, **then** raise `MIN_ADDON` in
`server/wrangler.toml` and deploy. Raising it on release day strands everyone who has not opened the companion app yet.

## Checks before announcing

- `node tools/smoke.js --env staging` passes (and `node tools/smoke.js` for production once deployed; add `--deep` to download the release files and check their SHA-256).
- `node tools/release-manifest.js verify` says the signature is good.
- The staging app (built with the real key) offers the update, installs the add-on, and `/acb version` in the game shows the
  new version after `/reload`.
- Try one tampered download on a test machine: the companion must refuse it and leave the add-on as it was.

## If something goes wrong

- **A bad add-on release:** publish a fixed one with a higher version (versions only go up). Players who installed the bad
  one can copy back their saved copy from `addon-backups` in the app's data folder.
- **A leaked release key:** stop signing, make a new key, ship a new installer by every other means (the website's download
  page), and tell players to reinstall; apps that hold the old key cannot be updated safely.
- **Take an announcement back:** replace `server/src/releases.json` with `{ "manifest": null, "signature": null }` and deploy;
  the Worker variables stand again.
