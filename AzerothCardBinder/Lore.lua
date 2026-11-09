local _, ACB = ...

-- Lore for the cards that do not have a hand-made line yet.
--   1. A line written for that exact creature (bosses and well-known rares and elites).
--   2. Otherwise a line built from what the name says it is: a faction, a role or a kind of creature.
--   3. Otherwise a line for its rank.
-- Every line is at most 80 characters so it fits the card's description box. Where the exact creature
-- is not described the line stays general instead of guessing.
local MAX = 80

-- ---- 1. Written for one creature, by NPC id ----
local written = {
    -- Ahn'Qiraj Temple
    [15516] = "A Qiraji guardian that whirls through the hive in a blur of blades.",
    [15727] = "The Old God's mind, dreaming and hungry beneath Ahn'Qiraj.",
    [15276] = "A Qiraji twin emperor whose arcane might needs no blade.",
    [15275] = "A Qiraji twin emperor who fights in melee and shares his brother's life.",
    [15589] = "The Old God's watching eye. Its gaze burns and its tentacles seize.",
    [15510] = "A colossal Qiraji worm that drags the unwary under the sand.",
    [15511] = "One of the Bug Trio, a Qiraji brute that spreads poison.",
    [15509] = "The Qiraji wasp queen, whose venom turns to a frenzy.",
    [15543] = "One of the Bug Trio, whose shriek terrifies and heals her allies.",
    [15963] = "A watching eye in the service of the Old God.",
    [15263] = "A Qiraji prophet who splits into copies of himself.",
    [15544] = "One of the Bug Trio, a charging Qiraji bruiser.",
    [15299] = "A giant globule of slime that shatters when it is frozen.",
    -- Blackwing Lair
    [12017] = "A dragonkin overseer who rules Blackwing's hatcheries.",
    [14020] = "A many-headed chromatic dragon, Nefarian's strangest experiment.",
    [14601] = "A black drake whose bite burns with shadow flame.",
    [11983] = "A black drake of Nefarian's brood, quick with fire and wing buffets.",
    [11981] = "A black drake of Nefarian's brood that grows wilder as it fights.",
    [10162] = "Nefarian in a human guise, who sneers at those who dare the lair.",
    [12435] = "A black dragon kept under the Orb of Command's control.",
    -- Molten Core
    [12056] = "A fire lord who turns his allies and enemies into living bombs.",
    [12057] = "A fire lord of Ragnaros, escorted by explosive firesworn.",
    [12259] = "A flamewaker lord who curses foes with searing pain.",
    [11988] = "A molten giant, guarded by two raging Core Ragers.",
    [12118] = "A flamewaker lord whose curse brings doom to those it marks.",
    [11982] = "A huge hound of molten rock and the lord of the Core Hounds.",
    [12264] = "A fire lord who blinks around the room and counters spells.",
    [12098] = "Ragnaros's herald, who leads the flamewaker priests.",
    -- Naxxramas
    [15956] = "A crypt lord who fills the Arachnid Quarter with locusts.",
    [15930] = "A stitched construct bound to Stalagg by crackling lightning.",
    [15932] = "A rotting horror that gorges on flesh in the Construct Quarter.",
    [16060] = "A cruel necromancer who raises trainees and riders from the dead.",
    [15953] = "A cult leader of the Arachnid Quarter, guarded by fanatic followers.",
    [15931] = "A flesh giant that sprays clouds of plague.",
    [15936] = "A plague warlock who makes foes dance across a burning floor.",
    [16062] = "One of the Four Horsemen, a fallen crusader risen as a death knight.",
    [16061] = "A death knight instructor whose pupils are taught to hit back.",
    [15990] = "A lich, once a Kirin Tor mage, who serves the Lich King.",
    [16065] = "One of the Four Horsemen, a death knight of the Military Quarter.",
    [16011] = "A giant fungus whose spores stifle healing.",
    [15952] = "The spider queen of Naxxramas, who webs her prey to the walls.",
    [15954] = "A necromancer who curses raiders and raises skeletons.",
    [16028] = "A huge abomination stitched together from many corpses.",
    [16063] = "One of the Four Horsemen, a death knight with unholy fire.",
    [15929] = "A stitched construct bound to Feugen by crackling lightning.",
    [15928] = "A stitched abomination charged with lightning by two tanks.",
    [16064] = "One of the Four Horsemen, a death knight who calls down meteors.",
    -- Onyxia's Lair, Ruins of Ahn'Qiraj, Zul'Gurub
    [10184] = "A black dragon, daughter of Deathwing, who rules her lair in the marsh.",
    [15369] = "A giant Qiraji wasp that hunts from above.",
    [15370] = "A huge Qiraji worm that gorges until it bursts.",
    [15348] = "A giant Qiraji worm lurking under the ruins.",
    [15340] = "A Qiraji construct that drains the mana of those near it.",
    [15339] = "A towering Qiraji warrior shielded by the crystals around him.",
    [11382] = "A Gurubashi warlord who rides his raptor, Ohgan, into battle.",
    [14834] = "The Soulflayer, a blood god the Gurubashi called down on themselves.",
    [14509] = "A Zulian high priest who fights on in the shape of a tiger.",
    [14507] = "A Zulian high priest who serves Hakkar with poison.",
    [14517] = "A Zulian high priestess who calls down bats and fire.",
    [14510] = "A Zulian high priestess who turns into a spider.",
    [11380] = "A Hakkari witch doctor who weaves hexes and summons spirits.",
    -- Blackrock Spire and the world
    [9816] = "A Blackrock fire mage who tends the dragonkin's forge.",
    [10363] = "Nefarian's general and the commander of the Blackrock Spire.",
    [10430] = "A monstrous beast that prowls Blackrock Spire.",
    [12397] = "A doom lord of the Burning Legion, who walks the world in a rage.",
    [7846] = "A hulking black dragon that rules the Blasted Lands' skies.",
    [6109] = "An ancient blue dragon who guards Azshara's magic.",
    [15481] = "The wandering spirit of an ancient blue dragon.",
    [15742] = "A colossal Silithid that fights for the swarm of Silithus.",
    [15741] = "A colossal Silithid that fights for the swarm of Silithus.",
    [15740] = "A colossal Silithid that fights for the swarm of Silithus.",
    [15341] = "A Qiraji general who leads the hive's war host.",

    -- Notable rares and elites
    [573] = "A harvester that learned to reap more than wheat.",
    [506] = "A gnoll sergeant who leads his pack through Westfall.",
    [520] = "A hulking brute who hunts the roads of Westfall.",
    [462] = "A rare menace known to everyone who travels Westfall.",
    [9025] = "An enraged earth elemental who guards Blackrock Depths.",
    [9042] = "A dwarf of the Dark Iron who patrols Blackrock Depths.",
    [9041] = "A warden of the Depths, long past caring for anyone.",
    [8923] = "A giant golem built to guard the Depths against all comers.",
    [9219] = "A Spirestone ogre butcher of Blackrock Spire.",
    [9218] = "A Spirestone ogre battle lord, proud of his clan.",
    [9217] = "A Spirestone ogre magus who rules his clan's spellcasters.",
    [9596] = "A Blackrock orc warlord with an axe to grind.",
    [9718] = "A Spirestone ogre bruiser who answers to no one.",
    [10509] = "An orc of Blackrock Spire, a keeper of its old runes.",
    [9736] = "A Blackrock orc who keeps the Spire's stores and its secrets.",
    [10376] = "A crystalline spider of the Spire that glitters and poisons.",
    [12237] = "A satyr of Maraudon's corrupted halls who feeds on the wounded.",
    [4842] = "A quilboar earthcaller of Razorfen Kraul who calls on the earth.",
    [3872] = "A Shadowfang captain whose sworn dead never rest.",
    [1720] = "A hardened convict who rules Stormwind Stockade's yard.",
    [10558] = "A bard of Stratholme still singing for those long dead.",
    [10393] = "A skeleton of Stratholme, once a living guard.",
    [10809] = "A hulking creature of Stratholme's cursed streets.",
    [5912] = "A mutated faerie dragon of the Wailing Caverns, all glitter and spite.",
    [10081] = "A restless dust spirit of Zul'Farrak's sands.",
    [10080] = "A Sandfury troll raider who lives off the desert.",
    [10082] = "A Zul'Farrak creature that haunts the Sandfury ruins.",
    [1137] = "A rare wolf-like howler that prowls the snowy hills of Dun Morogh.",
    [1132] = "A rare wolf of Dun Morogh's drifts, always on the hunt.",
    [1260] = "A rare great father of the yetis, ruler of the Dun Morogh heights.",
    [99] = "A cunning rare thief of Elwynn's woods.",
    [79] = "A kobold taskmaster who drives his diggers hard.",
    [61] = "A light-fingered Defias thief who stalks Elwynn Forest.",
    [100] = "A rare, fast boar that few hunters ever catch in Elwynn.",
    [10356] = "A rare undead who haunts Tirisfal's gloom.",
    [10357] = "A rare undead tormentor of Tirisfal.",
    [10358] = "The restless shade of someone who lost everything.",
    [12431] = "A rare wolf who hunts the Silverpine woods.",
    [12432] = "A rare, tusked beast of Silverpine, with a fearsome bite.",
    [12433] = "A rare spider of Silverpine that spins its web by night.",
    [14267] = "A rare ogre of Loch Modan who crushes all that cross him.",
    [14268] = "A rare undead lord of Loch Modan with a dark past.",
    [14266] = "A rare spinner of Loch Modan whose venom spreads panic.",
    [1398] = "A rare Dark Iron boss of Loch Modan who bullies everyone near him.",
    [2476] = "A huge crocolisk that rules the waters of Loch Modan.",
    [521] = "A rare worg of Duskwood's moonlit paths.",
    [574] = "A rare spider that waits in Duskwood's dark.",
    [503] = "A rare lord who stalks Duskwood's night.",
    [507] = "A rare wolf-shaped terror of Duskwood.",
    [534] = "A rare wraith who haunts Duskwood's roads.",
    [14275] = "A rare Stormpike dwarf who rules Hillsbrad's wilds.",
    [2605] = "A rare Witherbark troll chieftain of Arathi's swamps.",
    [723] = "A rare ogre of Stranglethorn who butchers all who pass.",
    [11383] = "A rare Zulian priestess of Stranglethorn.",
    [2541] = "A rare lord of Stranglethorn's jungle ruins.",
    [8296] = "A rare twisted creature of Deadwind Pass.",
    [5824] = "A rare quilboar captain of the Barrens.",
    [5785] = "A rare harpy sister who haunts the Barrens.",
    [5830] = "A rare harpy sister, taloned and cruel.",
    [14231] = "A rare, wandering behemoth of the Barrens, wherever it goes.",
    [3652] = "A rare lasher who whips through the Barrens' thorns.",
    [14339] = "A rare Felwood beast, howling in the corrupted woods.",
    [14344] = "A rare Felwood beast of the corrupted woods.",
    [14342] = "A rare Felwood bear that lumbers through the corruption.",
    [14345] = "A rare Felwood ogre of the corrupted woods.",
    [14343] = "A rare, ancient beast of the Felwood groves.",
    [14340] = "A rare Felwood drake of the corrupted heights.",
    [10196] = "A rare Winterspring general, still at war.",
    [10199] = "A rare Winterspring bear whose snow-white paws leave deep tracks.",
    [14479] = "A rare Twilight's Hammer lord of Silithus's dunes.",
}

-- ---- 2. Built from the name ----
-- Word test: whole words only, so "boar" does not match "boarding".
local function has(text, word)
    return text:find("%f[%a']" .. word:gsub("%-", "%%-") .. "%f[%A]") ~= nil
end

-- Groups and what they are called in a sentence. First match wins, so specific names come first.
local factions = {
    { "scarlet", "the Scarlet Crusade" }, { "defias", "the Defias Brotherhood" }, { "twilight", "the Twilight's Hammer" },
    { "blackrock", "the Blackrock clan" }, { "shadowforge", "the Dark Iron dwarves" }, { "dark iron", "the Dark Iron dwarves" },
    { "anvilrage", "the Dark Iron dwarves" }, { "deviate", "the Deviate of the Wailing Caverns" },
    { "razorfen", "the Razorfen quilboar" }, { "razormane", "the Razormane quilboar" }, { "bristleback", "the Bristleback quilboar" },
    { "deathguard", "the Forsaken" }, { "forsaken", "the Forsaken" }, { "stormpike", "the Stormpike dwarves" },
    { "frostwolf", "the Frostwolf clan" }, { "witherbark", "the Witherbark trolls" }, { "vilebranch", "the Vilebranch trolls" },
    { "bloodscalp", "the Bloodscalp trolls" }, { "skullsplitter", "the Skullsplitter trolls" }, { "gurubashi", "the Gurubashi trolls" },
    { "hakkari", "the Hakkari trolls" }, { "atal'ai", "the Atal'ai trolls" }, { "sandfury", "the Sandfury trolls" },
    { "smolderthorn", "the Smolderthorn trolls" }, { "frostmane", "the Frostmane trolls" }, { "kolkar", "the Kolkar centaur" },
    { "magram", "the Magram centaur" }, { "gelkis", "the Gelkis centaur" }, { "maraudine", "the Maraudine centaur" },
    { "galak", "the Galak centaur" }, { "kurzen", "the Kurzen jungle fighters" }, { "stonesplinter", "the Stonesplinter troggs" },
    { "grimtotem", "the Grimtotem tauren" }, { "gordok", "the Gordok ogres" }, { "gordunni", "the Gordunni ogres" },
    { "dragonmaw", "the Dragonmaw orcs" }, { "mosshide", "the Mosshide gnolls" }, { "riverpaw", "the Riverpaw gnolls" },
    { "gnarlpine", "the Gnarlpine furbolgs" }, { "timbermaw", "the Timbermaw furbolgs" }, { "bloodsail", "the Bloodsail Buccaneers" }, { "death talon", "the Death Talon dragonkin" },
    { "winterfall", "the Winterfall furbolgs" }, { "deadwood", "the Deadwood furbolgs" }, { "stonevault", "the Stonevault earthen" },
    { "dustbelcher", "the Dustbelcher ogres" },
    { "southsea", "the Southsea pirates" }, { "dalaran", "the Dalaran mages" }, { "syndicate", "the Syndicate" },
    { "venture co", "the Venture Co. goblins" }, { "stonard", "the Horde of Stonard" }, { "nethergarde", "the Nethergarde Alliance force" },
    { "theramore", "the Theramore garrison" }, { "cenarion", "the Cenarion Circle" }, { "ravenclaw", "the Ravenclaw undead" },
    { "slitherblade", "the Slitherblade naga" }, { "greymist", "the Greymist murlocs" }, { "jaedenar", "the Jaedenar cult" },
    { "burning blade", "the Burning Blade cult" }, { "spirestone", "the Spirestone ogres" }, { "scarshield", "the Scarshield Legion" },
    { "blackhand", "the Blackhand clan" }, { "blackwing", "Blackwing Lair's forces" }, { "crimson", "the Crimson Legion" },
    { "shadowsworn", "the Shadowsworn" }, { "thistlefur", "the Thistlefur furbolgs" }, { "gorishi", "the Gorishi hive" },
    { "qiraji", "the Qiraji" }, { "anubisath", "the Qiraji's Anubisath" }, { "naxxramas", "the Scourge of Naxxramas" },
    { "scholomance", "the Scholomance necromancers" }, { "stormwind", "Stormwind" }, { "ironforge", "Ironforge" },
    { "hillsbrad", "the Hillsbrad militia" }, { "redridge", "the Redridge militia" }, { "hive'zara", "the Hive'Zara swarm" },
    { "hive'regal", "the Hive'Regal swarm" }, { "hive'ashi", "the Hive'Ashi swarm" }, { "venomtip", "the Venomtip" },
    { "bloodfen", "the Bloodfen raptors" }, { "scalebane", "the Scalebane" }, { "obsidian", "the Obsidian guard" },
}

-- Role words and the noun they become.
local roles = {
    guard = "guard", guardsman = "guard", sentry = "sentry", sentinel = "sentinel", defender = "defender", warrior = "warrior",
    hunter = "hunter", shaman = "shaman", mage = "mage", priest = "priest", priestess = "priestess", warlock = "warlock",
    rogue = "rogue", scout = "scout", brute = "brute", raider = "raider", champion = "champion", captain = "captain",
    lieutenant = "lieutenant", enforcer = "enforcer", miner = "miner", worker = "worker", overseer = "overseer",
    taskmaster = "taskmaster", foreman = "foreman", digger = "digger", smuggler = "smuggler", trapper = "trapper",
    pillager = "pillager", looter = "looter", messenger = "messenger", cultist = "cultist", acolyte = "acolyte",
    necromancer = "necromancer", summoner = "summoner", sorceress = "sorceress", warden = "warden", slayer = "slayer",
    berserker = "berserker", ambusher = "ambusher", invader = "invader", soldier = "soldier", mystic = "mystic",
    geomancer = "geomancer", pathfinder = "pathfinder", keeper = "keeper", seer = "seer", oracle = "oracle", doctor = "doctor",
    grunt = "grunt", thug = "thug", assassin = "assassin", reaver = "reaver", ravager = "ravager", mauler = "mauler",
    flayer = "flayer", watchman = "watchman", herbalist = "herbalist", skirmisher = "skirmisher", elder = "elder",
    lord = "lord", lady = "lady", master = "master", knight = "knight", crusader = "crusader",
    archer = "archer", enchantress = "enchantress", servant = "servant", slave = "slave", prisoner = "prisoner",
}

-- Looked at in a fixed order so a creature always gets the same line.
local roleWords = {}
for word in pairs(roles) do roleWords[#roleWords + 1] = word end
table.sort(roleWords)

local function pickRole(text)
    for _, word in ipairs(roleWords) do
        if has(text, word) then return roles[word] end
    end
end

-- Kinds of creature: { words, { lines } }. Lines take the place name; keep each short enough to fit.
local creatures = {
    { { "boar", "goretusk", "razorback" }, { "A tusked boar that charges through %s.", "Boars root and charge across %s.", "Hunters know the boars of %s." } },
    { { "bear", "grizzly" }, { "A heavy bear that wanders %s.", "Bears like this one rule the wilds of %s.", "A bear of %s, best left alone." } },
    { { "wolf", "worg", "warg", "jackal", "coyote" }, { "A wolf hunting in packs around %s.", "A wild wolf of %s, quick to scent prey.", "Wolves like this one prowl %s." } },
    { { "raptor", "ravasaur", "devilsaur" }, { "A fast, sharp-clawed raptor of %s.", "Raptors stalk the brush of %s.", "A raptor of %s, quick and hungry." } },
    { { "scorpid", "scorpion" }, { "A stinging scorpid that skitters across %s.", "A scorpid of %s, armoured and venomous.", "Scorpids lurk in the sands of %s." } },
    { { "crocolisk", "croc" }, { "A snapping crocolisk that lurks in %s.", "A crocolisk of %s, waiting at the water's edge.", "Crocolisks lie hidden in %s." } },
    { { "spider", "widow", "venomweb", "tarantula" }, { "A venomous spider weaving its web in %s.", "A spider of %s that waits for prey.", "Spiders like this one infest %s." } },
    { { "crab", "crawler", "lobster", "tunneler" }, { "A claw-snapping crawler of %s.", "Crawlers like this one scuttle through %s.", "A crawler of %s, armoured and bad-tempered." } },
    { { "basilisk" }, { "A basilisk whose gaze turns heads in %s.", "A scaled basilisk of %s.", "Basilisks bask on the rocks of %s." } },
    { { "kodo" }, { "A great kodo that roams the plains of %s.", "A kodo of %s, slow and enormous.", "Kodos like this one wander %s." } },
    { { "ram", "goat", "sheep" }, { "A horned ram grazing the hills of %s.", "A ram of %s, stubborn and strong.", "Rams like this one roam %s." } },
    { { "ooze", "slime", "sludge", "jelly" }, { "A living pool of ooze that creeps through %s.", "A glob of ooze that drifts across %s.", "Oozes like this one slide through %s." } },
    { { "ghoul", "ghast" }, { "A ghoul that shambles through %s, hungry for flesh.", "A ghoul of %s, rotten and relentless.", "Ghouls like this one haunt %s." } },
    { { "skeleton", "skeletal", "bonewalker", "bone" }, { "A skeleton that clatters through %s.", "Restless bones that walk %s.", "A skeleton of %s, animated by dark magic." } },
    { { "zombie", "rotting", "rotted", "plagued", "risen" }, { "A shambling corpse that wanders %s.", "A rotting dead thing that lurches through %s.", "The risen dead drift through %s." } },
    { { "wraith", "ghost", "spectral", "spirit", "banshee", "shade", "specter", "haunt" }, { "A restless spirit that drifts through %s.", "A ghostly shape that haunts %s.", "A spirit of %s that cannot rest." } },
    { { "golem", "construct", "harvester", "juggernaut", "automaton", "gearbox" }, { "A stone-and-metal golem that guards %s.", "A golem of %s, built to follow orders.", "Golems like this one stand watch in %s." } },
    { { "elemental", "wisp", "geist", "spark", "ember", "magma", "lava", "fire" }, { "A being of raw elemental power in %s.", "An elemental bound to the land of %s.", "A raging elemental that haunts %s." } },
    { { "murloc", "murk", "fin", "oracle", "tidehunter" }, { "A gurgling murloc that lives near %s's water.", "A murloc of %s, bold in numbers.", "Murlocs like this one raid the shores of %s." } },
    { { "gnoll", "mongrel" }, { "A gnoll that prowls the camps of %s.", "A gnoll of %s, loud and quarrelsome.", "Gnolls like this one infest %s." } },
    { { "kobold" }, { "A candle-carrying kobold digging around %s.", "A kobold of %s, small, loud and mean.", "Kobolds like this one tunnel through %s." } },
    { { "troll", "headhunter", "witch doctor" }, { "A troll of %s, fierce and well-armed.", "Trolls like this one stalk %s.", "A troll hunter in the wilds of %s." } },
    { { "ogre", "mauler" }, { "A big, dim ogre that stomps around %s.", "An ogre of %s, wielding a club the size of a man.", "Ogres like this one rule %s." } },
    { { "harpy", "wingmaiden", "roguefeather", "bloodfeather", "bloodfury", "windfury", "ripper" }, { "A shrieking harpy that circles over %s.", "A harpy of %s, all claws and screams.", "Harpies like this one nest in %s." } },
    { { "centaur", "marauder", "outrunner" }, { "A centaur raider riding through %s.", "A centaur of %s, proud and ruthless.", "Centaurs like this one patrol %s." } },
    { { "quilboar", "boarman", "geomancer", "razormane" }, { "A quilboar of %s, thick-skinned and thorny.", "Quilboar like this one raid %s.", "A quilboar who lives by thorns in %s." } },
    { { "furbolg" }, { "A furbolg who lurks in the forests of %s.", "A furbolg of %s, shaggy and territorial.", "Furbolgs like this one roam %s." } },
    { { "satyr", "felsworn", "hatefury", "shadowstalker" }, { "A satyr of %s, twisted by demon-magic.", "Satyrs like this one lurk in %s.", "A satyr who serves dark powers in %s." } },
    { { "naga", "siren", "myrmidon", "sea witch", "tidehunter" }, { "A naga of %s, rising from the water.", "Naga like this one watch the coast of %s.", "A serpentine naga of %s." } },
    { { "mechanostrider", "strider", "plainstrider", "chicken", "hen", "cockatrice" }, { "A clockwork or feathered strider of %s.", "A strider of %s, quick on its feet.", "Striders like this one roam %s." } },
    { { "yeti", "wendigo", "ape", "gorilla", "silverback", "mangler" }, { "A shaggy beast that roams the heights of %s.", "A big ape-like brute of %s.", "A heavy-fisted beast of %s." } },
    { { "owlbeast", "owl", "hawk", "eagle", "windwalker", "buzzard", "vulture", "bird", "carrion" }, { "A hunting bird that circles over %s.", "A bird of prey that nests in %s.", "A bird of %s, sharp-eyed and quick." } },
    { { "wasp", "hornet", "drone", "silithid", "wyvern", "stinger", "gnat", "fly" }, { "A buzzing insect swarming over %s.", "A silithid of %s, chitin and hunger.", "Insects like this one nest in %s." } },
    { { "bat", "plaguebat", "screecher", "vampire", "bloodsucker" }, { "A bat flitting through the dark of %s.", "A bat of %s that hunts at dusk.", "Bats like this one roost in %s." } },
    { { "hippogryph", "thunderhead", "frayfeather", "gryphon", "griffon" }, { "A winged hippogryph that soars over %s.", "A hippogryph of %s, proud and swift.", "Hippogryphs like this one circle above %s." } },
    { { "sprite", "faerie", "fey", "wisp" }, { "A mischievous sprite that darts through %s.", "A sprite of %s, bright and spiteful.", "Sprites like this one dance around %s." } },
    { { "highborne", "eldreth", "spirit of eldre" }, { "A proud elven spirit bound to the ruins of %s.", "A restless highborne of %s, long past its time.", "An ancient elf's shade that haunts %s." } },
    { { "goblin", "gnome", "tinker", "engineer", "bomber", "sapper", "mekgineer" }, { "A scheming tinkerer who works away in %s.", "A tinkerer of %s with more gadgets than sense.", "A tinkerer at work in %s." } },
    { { "scarab", "locust", "beetle", "crypt fiend", "fiend" }, { "A skittering scarab that swarms through %s.", "Scarabs like this one crawl all over %s.", "A swarm creature of %s, quick and many." } },
    { { "rat", "mouse", "squirrel", "rabbit", "hare", "critter", "toad", "frog", "snail", "roach", "beetle", "cockroach" }, { "A harmless critter scurrying about %s.", "A small creature of %s, mostly underfoot.", "A critter of %s, seldom a threat." } },
    { { "snake", "serpent", "viper", "adder", "cobra", "lasher", "thornling" }, { "A venomous snake that slithers through %s.", "A snake of %s, patient and poisonous.", "Snakes like this one lurk in %s." } },
    { { "panther", "tiger", "lion", "cat", "cougar", "prowler", "nightsaber", "moonstalker", "huntress", "tigress", "pridelord", "pridewing", "lynx", "sabertooth", "saber", "puma", "pridewing", "stripe" }, { "A big cat that stalks prey through %s.", "A hunting cat of %s, silent and sudden.", "Cats like this one prowl %s." } },
    { { "hyena", "dog", "hound", "fox", "pup" }, { "A hound-like beast that scavenges in %s.", "A scavenger of %s, bold in packs.", "Scavengers like this one range across %s." } },
    { { "turtle", "tortoise", "shell", "snapjaw", "snapper", "snapclaw" }, { "A slow, armoured turtle of %s.", "A turtle of %s, hard to hurt.", "Turtles like this one plod through %s." } },
    { { "shark", "fish", "eel", "pike", "angler", "reef", "razorjaw", "saltwater", "sea" }, { "A sea creature that lurks off %s.", "A hunter of the waters near %s.", "A creature of the deep, found around %s." } },
    { { "imp", "voidwalker", "felhound", "felguard", "succubus", "doomguard", "infernal", "demon", "fel", "wrath", "legion", "terror" }, { "A demon of the Burning Legion, bound in %s.", "A demon summoned into %s.", "A fiendish thing at large in %s." } },
    { { "dragon", "whelp", "drake", "wyrm", "wyrmkin", "dragonkin", "dragonspawn", "scalebane" }, { "A dragonkin of %s, scaled and scornful.", "A whelp of a great dragon, found in %s.", "A drake of %s, young but dangerous." } },
    { { "treant", "ancient", "ent", "tree", "bough", "thorn", "moss" }, { "A walking tree that guards the forest of %s.", "A treelike guardian of %s's woods.", "An ancient wood spirit of %s." } },
    { { "horse", "steed", "stallion", "mare", "nightmare", "deer", "stag", "doe", "fawn", "elk", "moose", "gazelle", "zebra", "antelope", "cow", "bull", "pig", "sheep" }, { "A hoofed grazer wandering %s.", "A steed or stag of %s, shy and swift.", "A grazing beast of %s." } },
    { { "farmer", "peasant", "villager", "worker", "laborer", "commoner", "townsfolk", "merchant", "citizen", "scholar", "student", "apprentice", "initiate" }, { "A common soul going about its work in %s.", "A local of %s, no threat to anyone.", "Someone just trying to get by in %s." } },
    { { "knight", "paladin", "crusader", "templar", "champion", "cavalier", "marshal", "legionnaire" }, { "A heavily armed warrior of %s.", "A fighter in full armour who holds %s.", "A seasoned fighter, found in %s." } },
    { { "mage", "magus", "wizard", "sorcerer", "conjurer", "enchanter", "spellbinder", "evoker" }, { "A spellcaster of %s, quick with fire and frost.", "A mage who casts from the shadows of %s.", "A robed caster found in %s." } },
    { { "priest", "cleric", "healer", "monk", "prelate", "preacher" }, { "A robed priest who tends to its own in %s.", "A priest of %s, who heals its allies.", "A priest found in %s." } },
}

-- Titles and jobs, for named creatures that are not a kind of animal. Each line takes the place name.
local titles = {
    { { "baron", "baroness", "count", "countess", "duke", "prince", "princess", "king", "queen", "emperor" }, { "A noble who holds court in %s.", "A ruler of %s, proud and unforgiving.", "A high noble of %s." } },
    { { "lord", "lady", "highlord" }, { "A lord who holds sway in %s.", "A dangerous noble of %s.", "A ruler of %s, well guarded." } },
    { { "general", "commander", "warlord", "marshal", "sergeant", "lieutenant", "captain", "chieftain", "chief", "high chief" }, { "A leader who commands a war band in %s.", "A veteran commander found in %s.", "A leader whose orders carry weight in %s." } },
    { { "foreman", "overseer", "taskmaster", "supervisor", "slavemaster", "slave master" }, { "A taskmaster who drives the workers of %s.", "A foreman, hard on everyone around %s.", "An overseer with a whip, found in %s." } },
    { { "guard", "guardian", "protector", "sentinel", "sentry", "watcher", "defender", "warden", "keeper", "watchman", "ward", "overwatch" }, { "A watchful guardian holding its post in %s.", "A sentry that never leaves its post in %s.", "A defender who watches over %s." } },
    { { "hunter", "stalker", "tracker", "ranger", "scout", "pathfinder", "skirmisher" }, { "A hunter who tracks prey across %s.", "A scout who watches the paths of %s.", "A tracker in the wilds of %s." } },
    { { "warrior", "brute", "grunt", "raider", "reaver", "ravager", "slayer", "enforcer", "bruiser", "flayer", "invader", "ambusher", "champion", "berserker", "mauler", "myrmidon", "reveler", "destroyer", "fighter" }, { "A fighter of %s, always spoiling for a brawl.", "A hard-hitting fighter found in %s.", "A brawler who stalks %s." } },
    { { "rogue", "assassin", "thief", "smuggler", "pillager", "looter", "bandit", "cutthroat", "footpad", "messenger", "trapper" }, { "A sneak and a cutthroat in %s.", "A shady operator who lurks around %s.", "A cutpurse at work in %s." } },
    { { "shaman", "mystic", "seer", "oracle", "sorceress", "witch", "hexer", "warlock", "necromancer", "summoner", "cultist", "acolyte", "geomancer", "doctor", "prophet", "mender", "enchantress", "elder", "druid" }, { "A mystic of %s, who bends strange powers.", "A caster who works dark rites in %s.", "A seer or shaman found in %s." } },
    { { "miner", "digger", "worker", "laborer", "peon", "tunneler", "smith", "blacksmith", "engineer", "foreman" }, { "A laborer hard at work in %s.", "A worker of %s, with a pick or a hammer.", "A hand at work in %s." } },
    { { "horror", "lurker", "creeper", "terror", "beast", "abomination", "monstrosity", "fiend", "slime", "behemoth", "giant" }, { "A lurking horror that haunts %s.", "A hideous thing that creeps through %s.", "A monster of %s, best avoided." } },
}

-- ---- 3. By rank ----
local ranked = {
    normal = { "Commonly found around %s.", "A familiar sight to travelers in %s.", "Wanders %s in the usual way.", "Often seen along the paths of %s.", "Lives out its days around %s." },
    elite = { "A tough foe of %s, meant for a group.", "A hardened fighter found in %s.", "One of the stronger creatures of %s.", "A veteran of %s's many fights.", "Better faced with friends than alone in %s." },
    rare = { "A rare creature of %s, not often seen.", "A rare sighting in %s.", "Seen only now and then in %s.", "A rare find for those who roam %s.", "Few have met this rarity in %s." },
    rareelite = { "A rare and dangerous foe of %s.", "A rare elite that few challenge in %s.", "An elusive, formidable rarity of %s.", "Seldom seen, and rarely beaten, in %s.", "A rare, powerful presence in %s." },
    boss = { "A powerful boss of %s.", "The master of a lair in %s.", "A boss of %s, feared by many.", "A great foe waiting deep in %s.", "The ruler of this part of %s." },
}

-- ---- Putting a line together ----
local needsThe = { Deadmines = true, ["Stormwind Stockade"] = true, ["Scarlet Monastery"] = true }
local function placeName(card)
    local page = ACB.pages[card.page]
    local title = page and page.title or "the world"
    return needsThe[title] and ("the " .. title) or title
end

-- Use the first line that fits the card, starting from a different one for each creature.
local function fit(lines, start, ...)
    for step = 0, #lines - 1 do
        local line = lines[(start + step) % #lines + 1]:format(...)
        if #line <= MAX then return line end
    end
end

local function article(word)
    return word:match("^[AEIOUaeiou]") and "An" or "A"
end

function ACB.loreFor(card)
    if written[card.id] and not card.profession then return written[card.id] end
    local name = card.name:lower():gsub("[^%a' -]", " ")
    local place = placeName(card)
    local seed = card.id

    -- A named group, possibly with a role: "A Scarlet Crusade guard of ..."
    for _, faction in ipairs(factions) do
        if name:find(faction[1], 1, true) then
            local role = pickRole(name:gsub(faction[1], ""))
            local variants = {
                { article(card.name) .. " " .. card.name .. ", one of " .. faction[2] .. ", seen around " .. place .. "." },
                { card.name .. " of " .. faction[2] .. ", found in " .. place .. "." },
                { role and (article(role) .. " " .. role .. " of " .. faction[2] .. " who walks " .. place .. ".")
                    or ("A member of " .. faction[2] .. ", found in " .. place .. ".") },
                { "Sworn to " .. faction[2] .. ", and found in " .. place .. "." },
            }
            for step = 0, #variants - 1 do
                local line = variants[(seed + step) % #variants + 1][1]
                if #line <= MAX then return line end
            end
            local short = ("Of %s, in %s."):format(faction[2], place)
            if #short <= MAX then return short end
        end
    end

    -- A kind of creature.
    for _, kind in ipairs(creatures) do
        for _, word in ipairs(kind[1]) do
            if has(name, word) then
                local line = fit(kind[2], seed, place)
                if line then return line end
            end
        end
    end

    -- A title or job.
    for _, title in ipairs(titles) do
        for _, word in ipairs(title[1]) do
            if has(name, word) then
                local line = fit(title[2], seed, place)
                if line then return line end
            end
        end
    end

    -- Just a rank.
    local set = ranked[card.boss and "boss" or card.rank] or ranked.normal
    return fit(set, seed, place) or ACB.autoLore(card.boss and "b" or "n", 0, place)
end

-- ---- Gathering nodes ----
local nodeLore = {
    ["Silverleaf"] = "A common herb with silvery leaves, a staple of early herbalists.",
    ["Peacebloom"] = "A gentle bloom that grows wild across the green fields.",
    ["Earthroot"] = "A sturdy root herb that alchemists prize for healing brews.",
    ["Mageroyal"] = "A purple herb that clears the mind and restores a mage's mana.",
    ["Briarthorn"] = "A thorny herb used in potions of vitality.",
    ["Stranglekelp"] = "A tough kelp that grows in coastal waters and tangles divers.",
    ["Bruiseweed"] = "A bitter herb that soothes bruises and strengthens healing draughts.",
    ["Wild Steelbloom"] = "A hardy bloom whose petals gleam like metal.",
    ["Grave Moss"] = "A pale moss that thrives wherever the dead lie.",
    ["Kingsblood"] = "A red-veined herb, favoured by alchemists.",
    ["Liferoot"] = "A potent root said to coax life back into the wounded.",
    ["Fadeleaf"] = "A herb whose leaves fade to nothing in the right brew.",
    ["Goldthorn"] = "A golden thorny herb used in strengthening elixirs.",
    ["Khadgar's Whisker"] = "A herb named for the archmage, steeped for clarity of mind.",
    ["Wintersbite"] = "A frosty herb that thrives in the cold hills.",
    ["Firebloom"] = "A smouldering bloom found near fires and scorched earth.",
    ["Purple Lotus"] = "A deep purple lotus, prized by those who brew potent potions.",
    ["Arthas' Tears"] = "A pale herb that grows where the Scourge has tainted the land.",
    ["Sungrass"] = "A bright grass that stores the warmth of the sun.",
    ["Blindweed"] = "A murky weed that grows beside swamp water.",
    ["Ghost Mushroom"] = "A glowing fungus that grows in damp, dark places.",
    ["Gromsblood"] = "A blood-red herb named for an orc hero.",
    ["Golden Sansam"] = "A herb with golden leaves, prized for its soothing powers.",
    ["Dreamfoil"] = "A herb that brings vivid dreams to those who brew it.",
    ["Mountain Silversage"] = "A silvery sage that grows on high, windswept slopes.",
    ["Plaguebloom"] = "A sickly bloom that thrives in plague-ridden land.",
    ["Icecap"] = "A frost-white herb that grows in the coldest ground.",
    ["Black Lotus"] = "A rare black bloom said to hold great power.",
    ["Copper Vein"] = "Reddish ore that every young miner swings a pick at first.",
    ["Tin Vein"] = "A soft, silvery vein that smelts into bronze with copper.",
    ["Silver Vein"] = "A bright vein of silver, prized by jewelers and enchanters.",
    ["Iron Deposit"] = "A dark deposit of sturdy iron, the backbone of smithing.",
    ["Indurium Mineral Vein"] = "A rare, dense vein found in the Dark Iron's lands.",
    ["Gold Vein"] = "A glittering seam of gold, found by the persistent miner.",
    ["Mithril Deposit"] = "A bright deposit of mithril, light and strong.",
    ["Truesilver Deposit"] = "A gleaming, magical vein of truesilver.",
    ["Dark Iron Deposit"] = "A black, heat-hardened ore from beneath the Dark Iron's halls.",
    ["Small Thorium Vein"] = "A small vein of thorium, a dense and valuable metal.",
    ["Rich Thorium Vein"] = "A great vein of thorium, a rich prize for any miner.",
}

-- ---- Apply ----
for _, page in ipairs(ACB.pages) do
    for _, card in ipairs(page.cards) do
        if card.profession then
            if card.generated or not card.lore then card.lore = nodeLore[card.name] or card.lore end
        elseif card.generated then
            card.lore = ACB.loreFor(card)
        end
    end
end
