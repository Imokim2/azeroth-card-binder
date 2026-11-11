local _, ACB = ...

-- Written by the World of Warcards companion app; the game only reads it. Without the app it stays as shipped.
-- `acks` lists, for each binder the app has uploaded, the last event the server stored ({ seq, hash }).
-- Several binders can be listed because every WoW account on this computer shares this folder.
-- It also carries the roll tape for Ranked mode and, for the Ladder tab, the standings: `leaderboard` (the top 100,
-- each { rank, name, score, cards, sets } with score in tenths of a point), `you` (the same without a name), `verified`
-- (a set of ranked characters, "name-realmname") and `firsts` (who finished each set first). `wanted` is the board of what
-- public players are looking for, and `reportsDone` the set of report tokens the server has taken (see Reports.lua).
ACB.sync = { syncVersion = 0, acks = {} }
