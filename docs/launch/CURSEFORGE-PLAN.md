# CurseForge release preparation

**Submitted 15 November 2026; processing and moderator approval pending.** The description matches the published **addon 1.0.15 / companion 1.0.3** baseline, with server 1.0.2. Harry's card changes and the older-collection compatibility fix are included in this matching release. Project 1808775 has addon file 9638154, uploaded from the exact verified 1.0.15 archive for Forever 1.60.1. It is set to publish automatically once approved; it is not yet confirmed publicly available.

The [description](CURSEFORGE-PAGE.md), [initial release notes](CURSEFORGE-CHANGELOG.md), branding and five real screenshots are prepared. The Discord link is **https://worldofwarcards.co.uk/discord**, which redirects to the community's permanent invite. Forever and version 1.60.1 are listed on CurseForge; the old absent-client question is resolved. The listing uses the supplied genuine gameplay images. Add a current Guild capture when available; do not describe the older captures as taken from the new build. An optional [companion enquiry](CURSEFORGE-SUPPORT-DRAFT.md) is prepared if moderation needs clarification; no ticket has been sent.

## Page fields

| Field | Proposed value |
|---|---|
| Name | World of Warcards |
| Summary | Trade cards and sealed zone packs, collect alternate editions and finish seasonal collections in World of Warcraft: Forever. |
| Description | [CURSEFORGE-PAGE.md](CURSEFORGE-PAGE.md), checked against the final upload build |
| Release notes | [CURSEFORGE-CHANGELOG.md](CURSEFORGE-CHANGELOG.md), matched to addon 1.0.15 and companion 1.0.3 |
| Avatar | [project-icon.png](../media/project-icon.png), 400 × 400 PNG |
| Header | [banner.png](../media/banner.png), branding rather than a gameplay capture |
| Gallery | Five genuine supplied captures; refresh and complete using [SCREENSHOTS.md](SCREENSHOTS.md) |
| Licence | GPL-3.0-or-later, matching the repository |
| Source | https://github.com/Imokim2/azeroth-card-binder |
| Issue tracker | https://github.com/Imokim2/azeroth-card-binder/issues/new/choose |
| Homepage | https://worldofwarcards.co.uk |
| Community | https://worldofwarcards.co.uk/discord |
| Categories | Minigames; Guild and Achievements as additional categories |
| Comments | Enable; also provide the issue tracker and Discord help channels |
| Supported client | World of Warcraft → Forever, version 1.60.1 for the current build; interface `16001`, `AllowLoadGameType: camelot` |

The description puts the loading-screen notice near the bottom, just before Help and feedback, with community/homepage links in the footer. It includes no direct external installer link, fixed catalog count, active-season claim or unimplemented feature.

## Included card changes

[Harry's PR #63](https://github.com/Imokim2/azeroth-card-binder/pull/63) is merged. The matching [1.0.15 release](https://github.com/Imokim2/azeroth-card-binder/releases/tag/v1.0.15) contains addon 1.0.15 and companion 1.0.3; server 1.0.2 supports its new card format. Install the companion first. [PR #65](https://github.com/Imokim2/azeroth-card-binder/pull/65) preserves the earlier active list for older finds, pack results and completed pages, so an update does not require a binder reset.

The description includes the Guild tab and permanent donations, as well as faction bonus cards, expanded dungeon/raid lists and exclusions for known unkillable or one-off targets. Guild setup, membership approval and donations are included with the matching companion, server and database migrations. Owned copies remain owned. Some creature data still needs in-game confirmation, so do not claim every encounter is covered or verified. The [release record](RELEASE-1.0.15.md) distinguishes automated checks from the remaining group test.

## Before submission

1. **Select the supported client.** Use **World of Warcraft → Forever → 1.60.1** for the current `16001` build. CurseForge's [published Forever file listing](https://www.curseforge.com/wow/addons/quality-of-life-forever/files/all?gameVersionTypeId=88568&page=1&pageSize=20&showAlphaFiles=hide) explicitly lists that flavour and version. Confirm the choices against the final tested client in the upload editor; do not select Retail or another Classic flavour.
2. **Keep the companion wording descriptive.** The [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies) prohibit external file-download links. The draft explains the separate Windows companion and puts the homepage at the bottom, with no direct installer link. Casual collecting works with the addon alone; Ranked trading, gifting, seasons and ladder features require the companion. Do not bundle its installer in the addon ZIP. The policy does not itself require a separate companion-support approval; the optional enquiry is available if a moderator asks or the final page needs a different link arrangement.
3. **Finish the gameplay gallery.** The supplied binder, trade, achievements, empty-satchel and companion images are real, from 13 November. Refresh them for the final build: the companion capture visibly reports addon 1.0.0. Add actual pack-opening, alternate-edition and running-season captures where available. Keep the layout illustrations out of the public gallery. Upload genuine screenshots to CurseForge and replace relative image paths in the description with its gallery URLs.
4. **Match the exact release.** Update the description and release notes to the final uploaded addon, matching companion and server. Harry's card changes are included in 1.0.15; use companion 1.0.3 with that addon. No fixed card counts are advertised while the active pool is changing. The upload is addon 1.0.15 from tag `v1.0.15`, source `a5e2697`, SHA-256 `0fd9337592d43cc94db7dc51f1a3144d773c9af56128bf3899ca09b045ed01e7`.
5. **Check links and page presentation.** Verify the Discord redirect, help page, known-issue link and issue tracker. Keep promotional/community links at the bottom, as required by the moderation policy. The submission guide supports external issue trackers and recommends genuine gameplay images.

## Known issue to retain

The DX12 loading-screen/minimise loop is disclosed near the bottom of the description, just before Help and feedback, and in [KNOWN-ISSUES.md](../../KNOWN-ISSUES.md). Warcards' 3D models may exacerbate it. The bounded preloader in 1.0.10 is a mitigation, not a confirmed fix or an official Blizzard diagnosis. Include the `/reload` workaround when chat responds and Alt+F4/relaunch fallback, including the possibility of losing unsaved finds.

This is a disclosed known issue, not an automatic publication hold awaiting a graphics fix. It does not remove the release and page checks above.

## Final upload review

- Run the release checks and an in-game group test using the downloaded archive, including an existing-binder upgrade, trading/gifting and model loading.
- Verify `AzerothCardBinder/AzerothCardBinder.toc` is at the expected ZIP depth. Include no installer, account data, credentials or live sync file.
- Confirm Ranked compatibility across the exact addon, companion and server versions. Updates must preserve cards, packs and saved progress without a new-binder reset.
- Check avatar, summary, description, gallery, licence, client tags and support links in the actual CurseForge editor.
- Keep the loading-screen notice visible. If no season is active, do not present a test season as live community activity.
- Wait for the user's instruction to create/submit the CurseForge project or upload a release. Preparing these materials does not publish anything.

References rechecked 15 November 2026: [Forever files and client tags](https://www.curseforge.com/wow/addons/quality-of-life-forever/files/all?gameVersionTypeId=88568&page=1&pageSize=20&showAlphaFiles=hide), [creating a project](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project), [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies). The platform lists Forever; this project's own moderation decision has not occurred because it has not been submitted.

## CurseForge submission record

- Project: [World of Warcards](https://authors.curseforge.com/#/projects/1808775/files), public slug `world-of-warcards`.
- File: [World of Warcards 1.0.15](https://authors.curseforge.com/#/projects/1808775/files/9638154), uploaded as `AzerothCardBinder-1.0.15.zip`, Release, Forever 1.60.1. Automatic publication is selected for after approval.
- The project creation form is complete, with the original icon, Minigames category, Guild and Achievements categories, comments enabled, GPLv3 and third-party distribution allowed. The description states GPL-3.0-or-later, matching the repository.
- The description includes the Guild tab, permanent donations, separate companion setup, Discord and support links. Known issues remain near the bottom. The public GitHub repository is configured as Source; the official website, permanent Discord invite and setup guide are linked in project settings.
- Approval has not been claimed. A new project is hidden until moderation approves it. The website and GitHub remain the working downloads in the meantime.
