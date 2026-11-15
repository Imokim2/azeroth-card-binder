# Project images

The banner, social image and icon use the website’s dark background, brass trim and existing card branding. They are drawn by `tools/make-project-art.py`; no font files are redistributed.

Five actual screenshots supplied by Ollie on 13 November 2026 replace the matching illustrations. They are kept unchanged, including their original dimensions. The website serves identical copies from `server/public/images/` through Cloudflare static assets, separate from the API. Only the five public screenshots and their cache-header file belong in that directory.

| File | Size | Status / use |
|---|---|---|
| `banner.png` | 1440 × 460 | Branding: README and project-page header |
| `social-preview.png` | 1280 × 640 | Branding: GitHub social preview |
| `project-icon.png` | 400 × 400 | Branding: proposed CurseForge avatar |
| `site-icon.png` | 256 × 256 | Website favicon preview |
| `gallery/binder.png` | 1116 × 765 | Actual collection index, Wiry Swoop selected |
| `gallery/trading.png` | 999 × 797 | Actual trade window with one card offered |
| `gallery/achievements.png` | 527 × 588 | Actual collection achievements and progress |
| `gallery/satchel.png` | 561 × 521 | Actual satchel, empty; do not caption it as holding packs |
| `gallery/companion.png` | 1106 × 850 | Actual synced Windows companion, addon 1.0.0 |
| `gallery/packs.png` | 1280 × 720 | Layout illustration only; real opening capture still needed |
| `gallery/variants.png` | 1280 × 720 | Layout illustration only; real edition comparison still needed |

Only actual screenshots are displayed in the public README and website. The two remaining illustrated files are kept as references, and are not used as gameplay evidence in the CurseForge draft.

The README banner becomes visible when committed to the default branch. GitHub’s separate social-preview setting requires an image upload; committing the file does not set it automatically. GitHub recommends [1280 × 640 for the best display](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

## Replace the placeholders

1. Take clean captures from the release build using the [shot list](../launch/SCREENSHOTS.md).
2. Replace the matching file in `gallery/`. Keep the filename so the README continues to work. Aim for 16:9; 1920 × 1080 or larger is useful, but keep the UI readable at the displayed size.
3. Keep an untouched original outside this folder. Crop personal chat and account details; do not paint in UI or models that did not render.
4. Update that image’s README alt text and remove its “Screenshot placeholder” wording. Remove the blanket illustration note once every panel is real; while mixed, identify the remaining illustrations.
5. Keep the banner and icon as branding unless you want to redesign them. Brand artwork is not evidence of game functionality.

The generator preserves existing gallery images so real captures will not be overwritten. It always regenerates the three brand assets. It needs Python and Pillow, with Georgia/Segoe UI on Windows or DejaVu on Linux. Font files are not copied into the repository.

Before CurseForge submission, add real pack-opening, edition and season captures, and match all captions to the exact uploaded build. The current trade capture shows an offer before acceptance, not a completed trade.

Run `python tools/make-site-icons.py` to regenerate the website icon preview and `server/src/siteIcons.json`. The latter embeds an SVG favicon, a real ICO with 16, 32 and 48 pixel images, and a 180 pixel Apple touch icon. They use the existing card-and-diamond mark and need no external artwork or font files.
