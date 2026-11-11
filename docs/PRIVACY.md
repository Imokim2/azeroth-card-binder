# Privacy (draft for the privacy page, roadmap E3)

Written for the website's privacy page and the app's About window. It describes what the code does today; keep it in step with the code. This is a plain-language draft, not legal advice.

## What is stored

- **Your Discord id**, nothing else from Discord: not your name, avatar, email or servers. The sign-in asks for the `identify` permission only, and the one-time token is thrown away straight away.
- **A public key** made on your computer. The matching private key never leaves it.
- **Your characters' names and realms**, taken from your ledger.
- **Your ledger**: every card found, crafted, recycled and traded, with times, the partner's character name and the trade id.
- **Your score** and when it last changed.
- **Counts the server needs to check play**: attempts per card, roll-tape positions used, and flags raised by the fair-play checks (with a reviewer's note if a person looked).

## What is shown to others

Only if you choose **public** when you register: your character name and realm, your rank and score, your sets finished, and a "verified" mark beside your name in the game. A **private** player is stored but never listed.

## What is not collected

Nothing about what is on your screen, in the game's memory or in your chat. The companion app reads one file the game writes (the add-on's saved data) and writes one file the add-on reads. It does not touch the game process or its network traffic.

## Your choices

- Choose public or private when you register, and change it by signing in again.
- Ask for your data to be deleted. (**Not built yet**: a deletion route is a launch requirement, roadmap E3.)
- A banned player is hidden, not deleted, so that a ban cannot be dodged by starting again.

## Where it lives

On Cloudflare (Workers and D1), configured in `server/wrangler.toml`. The Discord application's secret and the other secrets are Worker secrets, never in the repository.
