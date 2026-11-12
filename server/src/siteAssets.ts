import icons from "./siteIcons.json" with { type: "json" };

const decode = (text: string) => Uint8Array.from(atob(text), character => character.charCodeAt(0));
const assets: Record<string, { type: string; body: string | Uint8Array }> = {
  "/favicon.svg": { type: "image/svg+xml", body: icons.svg },
  "/favicon.ico": { type: "image/x-icon", body: decode(icons.ico) },
  "/apple-touch-icon.png": { type: "image/png", body: decode(icons.apple) },
};

export function siteAsset(path: string): Response | undefined {
  if (!Object.hasOwn(assets, path)) return;
  const asset = assets[path];
  if (!asset) return;
  return new Response(asset.body, { headers: {
    "content-type": asset.type, "cache-control": "public, max-age=86400", "x-content-type-options": "nosniff",
  } });
}
