import { layout } from "./siteShell.ts";

// Use an account-generated PayPal link. An email alone does not establish that
// the account can receive payments through PayPal's Donate checkout.
export function paypalSupport(paymentLink: string | undefined): Response | null {
  try {
    const url = new URL(paymentLink ?? "");
    if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
    const host = url.hostname.toLowerCase();
    const direct = (host === "paypal.me" || host === "www.paypal.me") && /^\/[A-Za-z0-9._-]{1,64}\/?$/.test(url.pathname);
    const paypal = host === "www.paypal.com" || host === "paypal.com";
    const generated = paypal && (/^\/paypalme\/[A-Za-z0-9._-]{1,64}\/?$/.test(url.pathname) || /^\/ncp\/payment\/[A-Za-z0-9_-]{8,128}\/?$/.test(url.pathname));
    const button = url.searchParams.get("hosted_button_id");
    const hosted = paypal && /^\/donate\/?$/.test(url.pathname) && button !== null && /^[A-Z0-9]{13}$/.test(button);
    if (!direct && !generated && !hosted) return null;
    url.search = ""; url.hash = "";
    if (hosted) url.searchParams.set("hosted_button_id", button!);
    return new Response(null, { status: 302, headers: {
      location: url.href, "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex, nofollow",
    } });
  } catch { return null; }
}

export function supportSetupPage(): string {
  return layout("Support World of Warcards", `<div class="page-heading"><h1>Support World of Warcards</h1><p class="lede">Thank you for wanting to help with hosting and server costs.</p></div><div class="page-content prose"><div class="notice">We’re updating the PayPal support link. Please check back soon.</div><p>World of Warcards is free, and support is completely optional.</p><p><a href="/">Back to the website</a></p></div>`, "/support");
}
