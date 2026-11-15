// Keep the public /discord address stable when a community invite changes.
// Configuration may only point to an ordinary Discord invite, never an arbitrary redirect.
export function communityRedirect(invite: string | undefined): Response {
  let destination = "/help#community";
  try {
    const url = new URL(invite ?? "");
    const validHost = url.hostname === "discord.gg" || url.hostname === "discord.com";
    const validPath = url.hostname === "discord.gg" ? /^\/[A-Za-z0-9-]{2,100}\/?$/.test(url.pathname) : /^\/invite\/[A-Za-z0-9-]{2,100}\/?$/.test(url.pathname);
    if (url.protocol === "https:" && validHost && validPath && !url.username && !url.password && !url.port && !url.search && !url.hash) destination = url.href;
  } catch { /* An unconfigured or invalid invite leads to the help page. */ }
  return new Response(null, { status: 302, headers: {
    location: destination, "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex, nofollow",
  } });
}
