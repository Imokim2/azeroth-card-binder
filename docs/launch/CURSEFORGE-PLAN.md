# CurseForge release preparation

**Updated 15 November 2026; not submitted.** The description matches the published **addon 1.0.13 / companion 1.0.1** baseline. Harry's incoming collection changes are recorded below and are not yet part of that download. Choose the final upload version after the combined release is ready; do not relabel the existing archive.

The [description](CURSEFORGE-PAGE.md), [initial release notes](CURSEFORGE-CHANGELOG.md), branding and five real screenshots are prepared. The Discord link is **https://worldofwarcards.co.uk/discord**, which redirects to the community's permanent invite. The [support enquiry](CURSEFORGE-SUPPORT-DRAFT.md) is prepared only; no ticket has been sent. Forever compatibility tags, companion wording and the final gameplay gallery still need confirmation.

## Page fields

| Field | Proposed value |
|---|---|
| Name | World of Warcards |
| Summary | Trade cards and sealed zone packs, collect alternate editions and finish seasonal collections in World of Warcraft: Forever. |
| Description | [CURSEFORGE-PAGE.md](CURSEFORGE-PAGE.md), checked against the final upload build |
| Release notes | [CURSEFORGE-CHANGELOG.md](CURSEFORGE-CHANGELOG.md), updated if Harry's collection changes ship first |
| Avatar | [project-icon.png](../media/project-icon.png), 400 × 400 PNG |
| Header | [banner.png](../media/banner.png), branding rather than a gameplay capture |
| Gallery | Five genuine supplied captures; refresh and complete using [SCREENSHOTS.md](SCREENSHOTS.md) |
| Licence | GPL-3.0-or-later, matching the repository |
| Source | https://github.com/Imokim2/azeroth-card-binder |
| Issue tracker | https://github.com/Imokim2/azeroth-card-binder/issues/new/choose |
| Homepage | https://worldofwarcards.co.uk |
| Community | https://worldofwarcards.co.uk/discord |
| Categories | Choose the closest collection/roleplay and miscellaneous categories after confirming the supported client |
| Comments | Enable; also provide the issue tracker and Discord help channels |
| Supported client | Forever only; interface `16001`, `AllowLoadGameType: camelot`; confirm the platform target before choosing tags |

The description puts the loading-screen notice near the top and community/homepage links at the bottom. It includes no direct external installer link, fixed catalog count, active-season claim or planned guild-binder feature.

## Harry's incoming card changes

[PR #63 — Fix/unobtainable cards](https://github.com/Imokim2/azeroth-card-binder/pull/63), head `4126de1`, is open and passed CI on 15 November. It expands dungeon and raid lists, introduces faction bonus cards, and excludes known unkillable or one-off creatures from obtainable collection goals. Existing copies remain owned. Some source data still needs in-game confirmation, so avoid claims that every encounter is covered or verified.

This also changes the Ranked data format. It needs a coordinated **addon, companion and server** release and an upgrade check against existing binders. The current companion 1.0.1 is not the matching uploader for those changes. Passing PR checks does not establish a published or tested upgrade. Do not merge it into this documentation-only branch or advertise its features against the existing 1.0.13 archive.

After that release is published and verified, add this player-facing section after “Collect alternate editions” and include its changes in the initial release notes:

### Cards from both sides of Azeroth

Some bonus cards can only be earned by one faction. Trade or receive them as a gift to add the other side's cards to your binder. These extras are not required to finish a set and are not selected for seasons.

The collection includes expanded dungeon and raid card lists. Cards tied to known unkillable creatures or one-off encounters are excluded from collection goals and seasonal lists. Copies you already own stay in your binder when the available card list changes.

## Before submission

1. **Confirm Forever support.** Ask CurseForge whether it accepts this client and which game/version tags to use. Do not select Retail or another Classic flavour to get the project listed. The [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips) explains how to request support for an absent game; it does not establish support for Forever.
2. **Confirm companion wording.** The [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies) prohibit external file-download links. Ask how to describe the separate Windows companion and link the homepage. Casual collecting works with the addon alone; Ranked trading, gifting, seasons and ladder features require the companion. Do not bundle its installer in the addon ZIP or put a direct external EXE link in the description.
3. **Finish the gameplay gallery.** The supplied binder, trade, achievements, empty-satchel and companion images are real, from 13 November. Refresh them for the final build: the companion capture visibly reports addon 1.0.0. Add actual pack-opening, alternate-edition and running-season captures where available. Keep the layout illustrations out of the public gallery. Upload genuine screenshots to CurseForge and replace relative image paths in the description with its gallery URLs.
4. **Match the exact release.** Update the description and release notes to the final uploaded addon, matching companion and server. If PR #63 ships, add the section above only after the coordinated update is verified. No fixed card counts are advertised while the active pool is changing. Record the final version, source commit and archive checksum here.
5. **Check links and page presentation.** Verify the Discord redirect, help page, known-issue link and issue tracker. Keep promotional/community links at the bottom, as required by the moderation policy. The submission guide supports external issue trackers and recommends genuine gameplay images.

## Known issue to retain

The DX12 loading-screen/minimise loop is disclosed near the top of the description and in [KNOWN-ISSUES.md](../../KNOWN-ISSUES.md). Warcards' 3D models may exacerbate it. The bounded preloader in 1.0.10 is a mitigation, not a confirmed fix or an official Blizzard diagnosis. Include the `/reload` workaround when chat responds and Alt+F4/relaunch fallback, including the possibility of losing unsaved finds.

This is a disclosed known issue, not an automatic publication hold awaiting a graphics fix. It does not remove the separate compatibility, companion and release checks above.

## Final upload review

- Run the release checks and an in-game group test using the downloaded archive, including an existing-binder upgrade, trading/gifting and model loading.
- Verify `AzerothCardBinder/AzerothCardBinder.toc` is at the expected ZIP depth. Include no installer, account data, credentials or live sync file.
- Confirm Ranked compatibility across the exact addon, companion and server versions. Updates must preserve cards, packs and saved progress without a new-binder reset.
- Check avatar, summary, description, gallery, licence, client tags and support links in the actual CurseForge editor.
- Keep the loading-screen notice visible. If no season is active, do not present a test season as live community activity.
- Wait for the user's instruction to create/submit the CurseForge project or upload a release. Preparing these materials does not publish anything.

References rechecked 15 November 2026: [creating a project](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project), [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies). These establish page requirements; acceptance of this specific client and companion remains unconfirmed.
