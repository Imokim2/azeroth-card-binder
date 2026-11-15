# Community and support

The community server belongs to the project owner. Companion Discord sign-in is a separate OAuth application and does not create a community server or require a bot.

## Public links

Use `https://worldofwarcards.co.uk/discord` in the addon, README, issue chooser and CurseForge description. The Worker redirects it to `DISCORD_INVITE_URL`. Set that public variable for staging and production once a real invitation exists. It accepts only clean HTTPS `discord.gg/<code>` and `discord.com/invite/<code>` links. Invalid or absent configuration leads to the community section of Help, which explains when setup is pending. The redirect does not access the database and is not cached.

Use a never-expiring, unlimited-use invite to a public welcome channel, with temporary membership disabled. Do not put bot credentials, OAuth secrets or member-specific invitations in this configuration. If an invite is revoked, replace the variable and deploy; the addon address stays the same. Verify the final redirect and destination after deployment.

## Channel layout

- Start here: welcome, rules, downloads, updates, known-issues. Information channels should be read-only for ordinary members.
- Collectors: general, show-your-binder, trading, seasons-and-events.
- Support: help, bug-reports, suggestions.
- Voice: Collector’s Table and Dungeon Group.

Keep administrator and moderation privileges restricted to the owner and explicitly approved team members. No third-party bot is required for this setup. Keep member notifications to mentions rather than every message.

## What to pin

Link downloads to the official website; do not duplicate installers or key files in chat. Link known issues to the maintained GitHub document and include the loading-loop recovery workarounds with their uncertainty. Ask bug reporters what happened, where, their versions and any error message. Settings > Help provides a report link containing basic game details. Never ask for full SavedVariables, companion account files or private keys in public channels.

Keep the CurseForge page as an unsubmitted draft until the user requests publication and platform compatibility/companion guidance has been checked. A Discord server does not resolve those separate submission questions.
