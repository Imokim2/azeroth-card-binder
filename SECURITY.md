# Security

## Reporting a problem

If you find a way to cheat the ladder, read or change another player's data, run code through the companion app or its updates, or get at the server's secrets, **please do not post it publicly**. Use GitHub's private vulnerability reporting for this repository (the **Security** tab, then **Report a vulnerability**) and describe what you found and how to reproduce it. We will answer within a few days.

This is a volunteer fan project with no bug bounty, but we will credit you if you want to be named.

## What matters most here

- **Ranked integrity.** The server replays every uploaded ledger event and checks every Ranked drop against the roll tape it issued. A way to make the server accept an event it should refuse is a security problem. The rules are in [docs/LEDGER-SPEC.md](docs/LEDGER-SPEC.md).
- **The update path.** The companion app installs updates only from a manifest signed with the release key built into it, and checks every download's size and SHA-256. A way around either check is a security problem.
- **Players' data.** The server stores a Discord id, a public key, character names and the ledger. What is kept and for how long is on the [privacy page](https://worldofwarcards.co.uk/privacy).

## What is not a vulnerability

Anything that needs control of a player's own computer or game files (they can already change their own saved data; the server does not trust it), reports that Ranked can be gamed by reading the roll tape ahead (a known, bounded limit, described in the ledger specification), and denial of service by volume.

## No secrets in this repository

Secrets (`TAPE_SECRET`, `ADMIN_TOKEN`, `DISCORD_CLIENT_SECRET`, the release signing key) live only in Cloudflare's secret store and with the maintainers. If you ever find one in the code or its history, report it as above.
