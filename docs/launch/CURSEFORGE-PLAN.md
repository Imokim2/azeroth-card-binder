# CurseForge release preparation

**Prepared for 1.0.0; not submitted.** Website and GitHub publication are separate from CurseForge acceptance. Forever client tagging and optional-companion wording remain outstanding. Five real screenshots are prepared; pack-opening, edition and seasonal captures are still needed. [Support enquiry draft](CURSEFORGE-SUPPORT-DRAFT.md) is ready to send manually; no ticket has been sent.

| Field | Proposed value |
|---|---|
| Name | World of Warcards |
| Summary | Collect cards from mobs, bosses and gathering nodes, fill your binder and trade spares with friends. |
| Description | [CURSEFORGE-PAGE.md](CURSEFORGE-PAGE.md), checked against the upload build |
| Avatar | [project-icon.png](../media/project-icon.png), 400 × 400 PNG |
| Header | [banner.png](../media/banner.png) |
| Gallery | Five supplied captures in `docs/media/gallery/`; remaining shots in [SCREENSHOTS.md](SCREENSHOTS.md) |
| Licence | GPL-3.0-or-later, matching the repository |
| Source | https://github.com/Imokim2/azeroth-card-binder |
| Issue tracker | https://github.com/Imokim2/azeroth-card-binder/issues/new/choose |
| Homepage | https://worldofwarcards.co.uk |
| Categories | Select the closest collection/roleplay and miscellaneous categories after confirming the supported client |
| Comments | Enable; link the issue tracker for bug reports |
| Supported client | Forever only; confirm the correct platform target and version before choosing tags |

## Before submission

1. **Confirm Forever support.** This addon uses interface `16001` and `AllowLoadGameType: camelot`. Ask CurseForge whether it accepts this client and how it should be tagged. Do not label it Retail or another Classic flavour just to get it listed. The [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips) directs authors to request support when their target game is absent; it does not establish support for Forever.
2. **Check the companion wording with support.** Current [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies) prohibit direct external file-download links. Ask how to describe the optional Windows companion. Casual collecting works with the addon alone. Do not put the Electron installer in the addon ZIP or link a direct external EXE from the description.
3. **Finish the gameplay gallery.** Binder, trade, achievements, empty satchel and companion screenshots were supplied on 13 November 2026 and are used in the draft. Pack-opening, alternate-edition and seasonal captures are still needed. The remaining layout illustrations are not displayed in the draft. Keep the banner as branding, and match all images to the uploaded build.
4. **Describe the uploaded build.** The 1.0.0 page includes the satchel, tiered packs, seasonal collections, player-menu trading, editions and titles. Match every claim to the exact 1.0.0 archive and include its release changelog. The optional companion is a separate download, never an executable inside the addon ZIP.
5. **Check page links.** Put homepage/promotional links at the bottom, following the moderation policy. Use the actual GitHub issue tracker; don’t invent a Discord invite. The [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips) supports external issue trackers and recommends in-game images.

## Final upload review

- Run the release checks and an in-game smoke test using the actual archive.
- Check the ZIP has `AzerothCardBinder/AzerothCardBinder.toc` at the expected depth and contains no installer, account files or credentials.
- Confirm the addon, companion and server versions agree where Ranked play requires it.
- Review compatibility tags, licence, avatar, summary, description, gallery and support links.
- Wait for the user’s instruction to publish before creating/submitting the project or uploading a CurseForge file.

References rechecked 13 November 2026: [creating a project](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project), [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies). These establish page requirements; acceptance of this specific client and companion remains unconfirmed.
