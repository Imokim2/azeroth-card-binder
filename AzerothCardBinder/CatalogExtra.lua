local _, ACB = ...

-- Places that wowforever.ninja has no creature list for yet, added by hand from what its own creature pages confirm.
-- CatalogForever.lua is generated from that site and is skipped for places it has no data for; this file fills the
-- gap and is meant to shrink: once the site lists a place's creatures, run tools/build-catalog.js and delete the place
-- here (adding a creature that already has a card does nothing, so the two never clash).
-- Rows are { npc id, name, rank, level } with rank n normal, e elite, r rare, R rare elite, b boss. A level is left
-- out until a source gives it.

-- Zephras Isle, the Skyborne starting zone (levels 1-12, opened 4 November 2026). Its eight rare creatures are listed
-- here with the id, name and rank shown on their wowforever.ninja pages (/npcs/<id>-<name>/), read from beta client
-- caches. Snapbeak's level 9 is from the Warcraft Wiki. The ordinary creatures (Al'Aketh, Galestrider, Cloudrunner,
-- Vuldren and the rest) are known by name but not yet by id, so they are not in the binder yet.
ACB.addPlace("zephras-isle", "Zephras Isle", "Zone", "1–12", {
    { 250936, "Den'dralass", "r" },
    { 256492, "Fernfeather", "r" },
    { 259398, "Galemender Delanea", "r" },
    { 259388, "Mystmane", "r" },
    { 255887, "Slydris", "R" },
    { 259394, "Snapbeak the Quick", "R", 9 },
    { 259385, "Tel'daeor the Stormspeaker", "r" },
    { 256028, "The Lost One", "R" },
})
