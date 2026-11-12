// Keep the recipient in deployment configuration, outside public HTML and source.
// Opening this link does not take a payment; the supporter chooses and confirms on PayPal.
export function paypalSupport(account: string | undefined): Response {
  const recipient = account?.trim() ?? "";
  const valid = recipient.length <= 254 && (/^[^\s@<>"'&]+@[^\s@<>"'&]+\.[A-Za-z]{2,}$/.test(recipient) || /^[A-Z0-9]{13}$/.test(recipient));
  if (!valid) {
    return new Response("The support link is not available right now. You can continue using World of Warcards for free.", {
      status: 503, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  const destination = new URL("https://www.paypal.com/donate/");
  destination.searchParams.set("business", recipient);
  destination.searchParams.set("item_name", "World of Warcards server costs");
  destination.searchParams.set("currency_code", "GBP");
  return new Response(null, { status: 302, headers: {
    location: destination.href, "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex, nofollow",
  } });
}
