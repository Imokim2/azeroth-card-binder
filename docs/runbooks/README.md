# Runbooks

Step-by-step instructions for things that go wrong. They are written when the thing they cover exists. The ones planned (see Section 9 of the [roadmap](../ROADMAP.md)):

- database overloaded
- bad deploy: roll back
- flag storm
- season rollover failed
- leaked or lost player key
- data deletion request (built into the app and the API: see API.md, `POST /v1/delete`)
- [logs and alerts](ALERTS.md)
- [backups and restoring the database](BACKUPS.md)
- [releasing: app, add-on and server](RELEASES.md)
- [capacity: does it fit the free Workers plan?](CAPACITY.md)
- [privacy requests](PRIVACY-REQUESTS.md)
- [code signing the Windows installer](../CODE-SIGNING.md)
- catalog refresh after a game patch

Each runbook has the same shape: how you notice, how to confirm, what to do, how to check it worked, and who to tell.
