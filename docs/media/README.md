# Project images

These graphics use the website’s dark background, brass trim, serif headings and existing card/diamond branding. They are drawn by `tools/make-project-art.py`, with no game artwork or redistributed font files. They are branding and layout illustrations, not in-game screenshots.

| File | Size | Where it goes |
|---|---|---|
| `banner.png` | 1440 × 460 | GitHub README and project-page header |
| `social-preview.png` | 1280 × 640 | GitHub repository Settings → General → Social preview |
| `project-icon.png` | 400 × 400 | Proposed CurseForge avatar |
| `site-icon.png` | 256 × 256 | Preview of the website’s matching card favicon |
| `gallery/binder.png` | 1280 × 720 | Main binder screenshot |
| `gallery/packs.png` | 1280 × 720 | Pack opening |
| `gallery/trading.png` | 1280 × 720 | Trade and gift window |
| `gallery/variants.png` | 1280 × 720 | Alternate collectible cards |
| `gallery/achievements.png` | 1280 × 720 | Achievements and titles |
| `gallery/companion.png` | 1280 × 720 | Companion app |

The README banner becomes visible when committed to the default branch. GitHub’s separate social-preview setting requires an image upload; committing the file does not set it automatically. GitHub recommends [1280 × 640 for the best display](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

## Replace the placeholders

1. Take clean captures from the release build using the [shot list](../launch/SCREENSHOTS.md).
2. Replace the matching file in `gallery/`. Keep the filename so the README continues to work. Aim for 16:9; 1920 × 1080 or larger is useful, but keep the UI readable at the displayed size.
3. Keep an untouched original outside this folder. Crop personal chat and account details; do not paint in UI or models that did not render.
4. Update that image’s README alt text and remove its “Screenshot placeholder” wording. Remove the blanket illustration note once every panel is real; while mixed, identify the remaining illustrations.
5. Keep the banner and icon as branding unless you want to redesign them. Brand artwork is not evidence of game functionality.

The generator preserves existing gallery images so real captures will not be overwritten. It always regenerates the three brand assets. It needs Python and Pillow, with Georgia/Segoe UI on Windows or DejaVu on Linux. Font files are not copied into the repository.

Before CurseForge submission, replace the illustrated gallery with actual screenshots and match all captions to the exact uploaded build.

Run `python tools/make-site-icons.py` to regenerate the website icon preview and `server/src/siteIcons.json`. The latter embeds an SVG favicon, a real ICO with 16, 32 and 48 pixel images, and a 180 pixel Apple touch icon. They use the existing card-and-diamond mark and need no external artwork or font files.
