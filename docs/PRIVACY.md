# Privacy (draft for the privacy page, roadmap E3)

Written for the website's privacy page and the app's About window. It describes what the code does today; keep it in step with the code. This is a plain-language draft, not legal advice.

## What is stored

- **Your Discord id**, nothing else from Discord: not your name, avatar, email or servers. The sign-in asks for the `identify` permission only, and the one-time token is thrown away straight away.
- **A public key** made on your computer. The matching private key never leaves it.
- **Your characters' names and realms**, taken from your ledger.
- **Your ledger**: every card found, crafted, recycled and traded, with times, the partner's character name and the trade id.
- **Your score** and when it last changed.
- **The cards you are looking for** (your wanted list), only if you are public. A private player's list is not kept.
- **Reports** you send about other players (the character's name, a reason and a short note you wrote) and reports other players sent about you. Only the people who run the service read them; they are not shown to anyone else, and they are erased with the rest when you delete your data.
- **Counts the server needs to check play**: attempts per card, roll-tape positions used, and flags raised by the fair-play checks (with a reviewer's note if a person looked).

## What is shown to others

Only if you choose **public** when you register: your character name and realm, your rank and score, your sets finished, the cards you are looking for, and a "verified" mark beside your name in the game. A **private** player is stored but never listed.

## What is not collected

Nothing about what is on your screen, in the game's memory or in your chat. The companion app reads one file the game writes (the add-on's saved data) and writes one file the add-on reads. It does not touch the game process or its network traffic.

## Your choices

- Choose public or private when you register, and change it by signing in again.
- Delete your data from the server at any time with **Delete my data…** in the companion app: your record, ledger, characters, Discord link and any archived binders are erased from the live service at once. Copies kept for recovery after a mistake age out on their own: Cloudflare's recovery history lasts 7 days and our own daily copies are kept for 14. Your cards in the game and the files on your computer are not touched. You can sign up again later, from nothing. (A banned account's record is kept, so a ban cannot be undone by deleting the account.)
- A banned player is hidden, not deleted, so that a ban cannot be dodged by starting again.

## Technical logs

The server keeps a log of each request (the route, the result and how long it took, with a request id) so that problems can be found. It does not log your Discord id, your cards or what you uploaded. Cloudflare, which runs the server, also keeps its own technical logs, which include the address a request came from, for a limited time.

## Where it lives

On Cloudflare (Workers and D1), configured in `server/wrangler.toml`. The Discord application's secret and the other secrets are Worker secrets, never in the repository.
