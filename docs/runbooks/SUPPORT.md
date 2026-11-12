# Website support link

The shared website footer has an optional **Support via PayPal** button. It opens `/support` in another tab. The server redirects to PayPal’s donation page with the configured recipient, a description of the server costs and GBP currency. It sets no amount and does not take a payment: the supporter chooses and confirms on PayPal.

The addon has no donation message or button. Contributions do not unlock cards, features or Ranked advantages. The site does not call PayPal until someone follows the support link, load a payment script, record payment details or claim a tax-deductible charitable donation.

## Configuration

Set `SUPPORT_PAYPAL_ACCOUNT` to the recipient’s confirmed PayPal email or merchant ID, separately for each deployed environment:

```text
cd server
npx wrangler secret put SUPPORT_PAYPAL_ACCOUNT --env production
```

Enter the recipient when prompted. Keep it out of `wrangler.toml`, the public source and the site HTML. PayPal receives it in the redirect URL and handles its own checkout; this is not a claim that PayPal hides the recipient’s identity. A hosted PayPal donation ID or a PayPal.Me link can be adopted later if the owner creates one.

The recipient is never accepted from a visitor’s query string. `/support` is GET-only, is not cached, does not forward game/account information, and fails closed if the account is missing or invalid. Updating the recipient requires changing deployment configuration, not editing a browser link. Do not accept arbitrary return URLs or change this into an open redirect.

## Verification

- Every public page should show the same footer button, including on a narrow screen.
- `GET /support` must return 302 to `https://www.paypal.com/donate/` with the configured recipient and GBP; it must not set an amount.
- Visiting `/support?business=another-account` must still use the configured recipient.
- POST and other methods are refused. The redirect has `cache-control: no-store` and `referrer-policy: no-referrer`.
- Check the recipient shown at PayPal before sharing the link widely. A live payment has not been submitted by automated verification.

PayPal reference: [Donate integration](https://developer.paypal.com/sdk/donate/). This uses a normal redirect, without embedding the SDK. The recipient must be a PayPal account that can receive payments; account-specific checkout acceptance remains PayPal’s decision.
