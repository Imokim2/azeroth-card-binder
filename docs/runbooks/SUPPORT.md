# Website support link

The shared website header and footer have an optional **Support via PayPal** button. Both open `/support` in another tab. The server redirects to the account-generated PayPal link configured by the owner. It sets no amount and does not take a payment: the supporter chooses and confirms on PayPal.

The addon has no donation message or button. Contributions do not unlock cards, features or Ranked advantages. The site does not call PayPal until someone follows the support link, load a payment script, record payment details or claim a tax-deductible charitable donation.

## Configuration

Set `SUPPORT_PAYPAL_URL` to an HTTPS PayPal.Me link or a payment link generated inside the recipient’s PayPal account, separately for each deployed environment. An email-based Donate checkout previously refused payments; an email alone is not enough to configure a working checkout.

```text
cd server
npx wrangler secret put SUPPORT_PAYPAL_URL --env production
```

Enter the full link when prompted. Keep deployment configuration out of `wrangler.toml` and the site HTML. The link is public when followed; it is not an account credential. PayPal handles its own checkout and may show the recipient’s identity. The old `SUPPORT_PAYPAL_ACCOUNT` setting is no longer used.

The recipient is never accepted from a visitor’s query string. `/support` is GET-only, is not cached and does not forward game/account information. Only recognised PayPal.Me, PayPal payment and hosted Donate link formats are accepted. Visitor-supplied amounts, recipients and return URLs are not forwarded. Missing or invalid configuration shows a branded setup notice without a redirect. Updating the link requires changing deployment configuration.

## Verification

- Every public page should show the same header and footer buttons, including on a narrow screen.
- `GET /support` must return 302 to the configured account-generated link; it must not set an amount. PayPal handles currency selection.
- Visiting `/support?business=another-account` must still use the configured recipient.
- POST and other methods are refused. The redirect has `cache-control: no-store` and `referrer-policy: no-referrer`.
- Check the recipient shown at PayPal before sharing the link widely. A live payment has not been submitted by automated verification.

PayPal reference: [PayPal.Me](https://www.paypal.com/uk/webapps/mpp/digital-wallet/send-receive-money/paypal-me). This uses a normal redirect, without embedding a payment SDK. The recipient must be a PayPal account that can receive payments; account-specific checkout acceptance remains PayPal’s decision.
