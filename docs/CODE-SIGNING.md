# Code signing the Windows installer

The companion installer is not code-signed, so Windows shows an "unknown publisher" warning (SmartScreen) and warns more the fewer people have run the file. A normal certificate costs money every year and needs a registered business. **SignPath Foundation** gives free signing to open-source projects; the certificate is in their name, which shows as the publisher.

This page is what we found about the programme (read on 12 Nov 2026 from signpath.org/terms and SignPath's documentation; **check the live pages before applying, because the terms can change**), where our project stands, and what to do.

## Does the project qualify?

| Requirement (from SignPath's terms) | Where we are |
|---|---|
| An OSI-approved open-source licence for all components, no commercial dual-licensing | **Yes.** GPL-3.0-or-later (`LICENSE`). |
| No proprietary or non-open-source code | **Yes.** Everything built into the installer is in this repository or an npm dependency (Electron, electron-builder's runtime). |
| Actively maintained | **Yes.** |
| Already released in the form to be signed | **Yes.** v0.5.0 on GitHub. |
| Functionality described on the download page | **Yes.** `/download` describes the add-on and the companion. |
| Only your own binaries, built from your own source, builds verifiable from source | **Yes.** The release workflow builds the installer from the tagged commit on GitHub-hosted machines. |
| No hacking tools or features that bypass security | **Yes.** The app reads one saved-data file and writes one file for the add-on; it does not touch the game's memory or network traffic (`docs/POLICY.md`). |
| Respects privacy: disclose any data sent to other systems, a way to avoid it | **Mostly.** The app talks only to our own server, after sign-in and sync, and the privacy page says what is kept. The app does nothing until the player signs in, and signing out stops it. **Check:** SignPath may want the privacy statement shown at install time; our installer is a one-click installer with no pages, so see "Open questions". |
| Warn before changing system configuration; provide uninstall | **Yes.** Per-user install, no system changes beyond a Start-with-Windows option the player ticks, uninstall from Windows' Apps list. |
| A published **code signing policy** on the home and download pages, with the attribution line | **Page is live** at `/code-signing-policy` and linked from every page's footer (so from the home and download pages). The attribution line is on it, under "When signing is in use". |
| Team roles: authors, reviewers, approvers, with multi-factor authentication for GitHub and SignPath | **Listed** on the policy page (the two maintainers). **Each person must turn on multi-factor authentication** on GitHub and, once they have an account, on SignPath. |
| Product name and one product version in every build | The installer's product name is "World of Warcards". **Check** the file's version metadata matches the release (electron-builder uses `app/package.json`'s version). |
| Manual approval of each signing request | Planned; it is how SignPath's Foundation plan works. |

## Open questions to ask SignPath

1. Is a one-click NSIS installer with no pages acceptable, with the privacy statement on the website and in the app's own window, instead of a page in the installer?
2. The installer also contains an uninstaller and Electron's own files. Signing only the final installer is the usual setup; is that enough?
3. How long does an application take, and who must apply (the repository owner)?
4. We update the add-on from inside the companion (download, verify against a signed manifest, install). Does that fit the "warn before changing system configuration" rule? It only touches the add-on's own folder in the game, and asks first.

## Applying (the owner or a maintainer, a few minutes)

The application is the form at <https://signpath.org/apply>. We could not read the form's fields from here, so expect to be asked for roughly: the project's name and website, the repository, the licence, a short description, how releases are built, and who the team is. Draft answers:

- **Project:** World of Warcards, a collectible card add-on for World of Warcraft: Forever, with a Windows companion app and a ranking server.
- **Website:** <https://worldofwarcards.co.uk>. **Code signing policy:** <https://worldofwarcards.co.uk/code-signing-policy>. **Download page:** <https://worldofwarcards.co.uk/download>.
- **Repository:** <https://github.com/Imokim2/azeroth-card-binder> (public, GPL-3.0-or-later).
- **What is to be signed:** the Windows NSIS installer of the companion app (`World-of-Warcards-Setup-<version>.exe`), built by `.github/workflows/release.yml` on GitHub-hosted Windows runners when a `v*` tag is pushed.
- **Build:** `npm ci` and `npm run dist` in `app/` (electron-builder). The repository, the workflow and the lockfiles are the only inputs.
- **Team:** Imokim2 (owner, author, reviewer, approver) and harrydexter18-afk (author, reviewer, approver).
- **Privacy:** the app contacts only `worldofwarcards.co.uk`, after the player signs in; see <https://worldofwarcards.co.uk/privacy>.

Before sending: both maintainers turn on multi-factor authentication on GitHub, and the owner decides who approves signing requests.

## After SignPath accepts the project

1. In SignPath, create the project, an artifact configuration (the installer file, `<zip-file>` root because GitHub artifacts are zipped) and a signing policy. Note the organisation id and the two slugs.
2. Add the GitHub.com trusted build system to the SignPath project and link it.
3. Create an API token for a submitter user and store it as the repository **secret** `SIGNPATH_API_TOKEN`.
4. Set the repository **variables** `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG` and `SIGNPATH_SIGNING_POLICY_SLUG` (Settings, Secrets and variables, Actions). The steps already in the installer job of `.github/workflows/release.yml` wake up when `SIGNPATH_ORGANIZATION_ID` is set: they upload the unsigned installer, ask SignPath to sign it, wait for the approval, and put the signed file in the release in place of the unsigned one.
5. Change the status on the policy page (`codeSigningPage` in `server/src/sitePages.ts`) from "not code-signed yet" to "signed by SignPath Foundation", and the unsigned-installer wording on the download, help and FAQ pages, README and `SECURITY.md`.
6. For each release: push the tag, **approve the signing request in SignPath** (it waits for a person), then sign the manifest as usual (`docs/runbooks/RELEASES.md`). The manifest hashes the *signed* installer that is on the release page, so use the files you download from the release.

## Notes

- SignPath's open-source plan checks that every job leading up to the signing request ran on GitHub-hosted machines; ours do.
- A signature removes the "unknown publisher" name but SmartScreen reputation still builds with downloads, so the warning may soften rather than vanish at first.
- Nothing here changes the app's own update checks: it still trusts only the Ed25519-signed manifest, which is separate from the Windows signature.
