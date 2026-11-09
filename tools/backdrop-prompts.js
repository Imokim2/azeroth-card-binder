// Writes AzerothCardBinder/Art/Portrait-Backdrops-Needed.txt: one image prompt for every place that has no
// packaged portrait backdrop yet, in the same style as the three that are already there (see
// Portrait-Backdrops.txt).
//
//   node tools/backdrop-prompts.js
//
// To use a finished picture: save it as a 512 x 384, 32-bit, uncompressed TGA in AzerothCardBinder/Art, then add
// its place and file name to the `backdrops` table in Catalog.lua. Until then a card shows the best artwork the
// game itself can give (the Dungeon Journal picture, the loading screen, or the map of the zone it sits in).
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..", "AzerothCardBinder");
const places = [];
for (const match of fs.readFileSync(path.join(root, "CatalogForever.lua"), "utf8")
    .matchAll(/^ACB\.addPlace\("([a-z0-9-]+)", "([^"]+)", "([A-Za-z]+)"/gm)) {
    places.push({ slug: match[1], name: match[2], kind: match[3] });
}

// Places that already have a painting.
const done = new Set(["deadmines", "westfall", "elwynn-forest"]);

// One scene per place: what is in the picture, and its palette.
const scenes = {
    "ahnqiraj-temple": "A sandstone temple of the Qiraji half buried in desert, huge carved insectoid pillars at the edges, a pale shaft of light on dusty floor in the middle distance. Palette: sand gold, bruised violet and dark umber.",
    "blackwing-lair": "A cavern of black volcanic rock with a forged iron gate far away, rivers of slow orange lava along the edges, drifting ash. Palette: charcoal, ember orange and deep red.",
    "molten-core": "A vast chamber of molten stone, lava falls at the edges, a lake of glowing fire in the distance, rising heat haze. Palette: black basalt, bright orange and smoky red.",
    "naxxramas": "A floating necropolis of bone-pale stone under a green-grey sky, spires and cold fog at the edges, an eerie glow in the central distance. Palette: sickly green, bone white and slate.",
    "onyxias-lair": "A deep dragon's cave with scattered gold and ancient bones at the edges, a dim red glow from a far tunnel. Palette: dark rust, black stone and ember red.",
    "ruins-of-ahnqiraj": "Broken sandstone ruins of a Qiraji city under a hard blue-white sky, toppled carved columns at the edges, windblown dunes in the distance. Palette: dune gold, pale turquoise and shadow brown.",
    "zulgurub": "An overgrown jungle troll city, stone steps and carved idols at the edges, hanging vines, a faint green light on a distant temple. Palette: deep jungle green, mossy gold and dark brown.",
    "blackfathom-deeps": "A flooded sea cave in a dark gorge, glowing blue coral and carved night elf ruins at the edges, still water in the centre. Palette: deep ocean blue, teal and soft silver.",
    "blackrock-depths": "A dwarven underground city of dark stone halls and bridges over lava, forges glowing at the edges, a distant hall in warm smoke. Palette: black stone, forge orange and brass.",
    "blackrock-spire": "The inside of a black stone fortress, tall arched halls and iron braziers at the edges, orc banners high up, a red glow far ahead. Palette: soot grey, dull red and iron.",
    "dire-maul": "Overgrown elven ruins in a forest, broken arches and statues wrapped in ivy at the edges, shafts of green light through leaves. Palette: moss green, warm stone and violet shade.",
    "gnomeregan": "A gnome city of pipes and gears, brass machinery at the edges, a toxic green glow in the distance and drifting steam. Palette: brass, rust and toxic green.",
    "maraudon": "A cavern of glowing purple crystals and giant roots, a hint of green spring water in the distance, spores floating in the air. Palette: violet, jade and deep earth brown.",
    "ragefire-chasm": "A volcanic cavern beneath a city, orange lava channels at the edges, carved orc stonework and a red glow in the centre distance. Palette: scorched red, ochre and black rock.",
    "razorfen-downs": "A burial mound of bone and thorn, twisted bramble walls at the edges, pale bone-like arches, cold grey light in the middle. Palette: bone, bruised purple and dry thorn brown.",
    "razorfen-kraul": "A dense thicket of giant thorny vines forming a boar-man village, hide tents at the edges, a dusty amber glow in the distance. Palette: thorn green, dry clay and amber.",
    "scarlet-monastery": "A crimson-roofed gothic monastery in a misty graveyard, tall dark pines at the edges, a pale moon behind the central tower. Palette: crimson, grey stone and cold blue night.",
    "scholomance": "A candle-lit gothic crypt-school, tall arched stone with hanging banners at the edges, a ghostly blue light at the far end. Palette: tallow yellow, cold blue and aged stone.",
    "shadowfang-keep": "A moonlit hilltop castle in a gnarled pine forest, torn banners and bare trees at the edges, mist rolling across the courtyard. Palette: midnight blue, pale silver and wet black.",
    "stormwind-stockade": "A grim stone prison with iron-barred cells and torchlight at the edges, wet flagstones leading to a lit doorway. Palette: damp grey, torch amber and dark teal.",
    "stratholme": "A burned gothic city under a heavy grey sky, charred timbers and broken arches at the edges, a dim red glow beyond the gates. Palette: ash grey, dull crimson and soot brown.",
    "sunken-temple": "A giant green-stone dragon temple half under swamp water, vines and carved scales at the edges, shafts of green light on still water. Palette: jade, murky teal and old gold.",
    "uldaman": "A titan vault of carved stone, golden runes and wide stairways at the edges, a bright amber light in the distance. Palette: sand gold, bronze and deep blue shadow.",
    "wailing-caverns": "A lush underground cavern of twisted roots and glowing pools, a green mist across the middle distance, smooth rock overhead. Palette: emerald, teal and earth brown.",
    "zulfarrak": "A sun-bleached troll hill city of sandstone stairs and carved idols under a pale sky, heat shimmer at the edges. Palette: bleached sand, bone and hot turquoise.",
    "arathi-basin": "A green highland valley with a farm and a blacksmith's forge on far hills, wooden banners at the edges, a golden afternoon haze. Palette: meadow green, warm gold and sky blue.",
    "alterac-valley": "A snowy mountain valley with a fortress on either far end, pine trees and banners at the edges, drifting snow. Palette: snow white, cold blue and iron grey.",
    "dun-morogh": "A snowy dwarven highland, pine trees and frosted rock at the edges, a distant mountain hall in warm light. Palette: snow white, ice blue and hearth amber.",
    "tirisfal-glades": "A gloomy glade of dead leaves and twisted trees, a ruined chapel on a far hill, low green mist. Palette: sickly green, bruised purple and grey.",
    "silverpine-forest": "A cold pine forest in blue mist, a pale castle on a far ridge, silver-green needles at the edges. Palette: pine green, silver and midnight blue.",
    "loch-modan": "A calm mountain lake in a wide valley, rocky banks and small stone dams at the edges, soft golden light on far hills. Palette: lake blue, tawny rock and green.",
    "redridge-mountains": "A red cliff valley with a long calm lake, rust-coloured rock at the edges, a stone bridge on the far shore. Palette: brick red, lake blue and dry green.",
    "wetlands": "A grey-green marsh of reeds and still water under low cloud, a rocky coast on the far side, gulls in the mist. Palette: marsh green, slate and soft silver.",
    "duskwood": "A dark forest of huge gnarled trees under a moonlit sky, mist between the trunks, a single lamp-lit cottage far away. Palette: midnight blue, deep green and a touch of lantern amber.",
    "hillsbrad-foothills": "Rolling farmland and orchards under a bright sky, a stone keep on a hill in the distance, tall trees at the edges. Palette: apple green, warm gold and soft blue.",
    "alterac-mountains": "Snow-covered mountain peaks and ruined stone towers, pale blue sky and drifting snow, dark pines at the edges. Palette: icy blue, white and cold grey.",
    "arathi-highlands": "Open green highlands with stone walls, a lone wooden tower far away, a breezy sky. Palette: grass green, warm tan and light blue.",
    "stranglethorn-vale": "A dense jungle with giant ferns and hanging vines, a dim troll ruin deep in the distance, shafts of green-gold light. Palette: jungle green, gold and dark teal.",
    "swamp-of-sorrows": "A drowned swamp of dead trees and green water, a half-sunken stone temple in the mist, slow green light. Palette: murky green, ochre and slate.",
    "badlands": "Cracked orange desert canyons with dry rock arches, a faint titan ruin on a far cliff, dusty haze. Palette: terracotta, ochre and dusty violet.",
    "the-hinterlands": "A lush, wild highland forest with tall mossy cliffs, a troll-built tower on a far ridge, golden sun through leaves. Palette: forest green, lichen gold and soft blue.",
    "searing-gorge": "A black gorge of volcanic rock, lava glow in its depths, iron towers on the rim, smoke across the sky. Palette: charcoal, ember orange and dull brown.",
    "blasted-lands": "A red wasteland under a purple sky, jagged rock and a distant dark portal glowing at the horizon. Palette: blood red, violet and black.",
    "burning-steppes": "A scorched ash plain under a red sky, black ridges and a glowing mountain far away, drifting embers. Palette: ash grey, burnt orange and deep crimson.",
    "western-plaguelands": "Diseased farmland under a sick yellow sky, dead trees and wooden fences at the edges, a ruined tower far away. Palette: blighted yellow-green, brown and grey.",
    "eastern-plaguelands": "A barren land of black trees and ash, ruined towers and a sickly glow on the horizon, grey-green fog. Palette: ash, plague green and bone.",
    "deadwind-pass": "A narrow dark mountain pass with bare rock and an old black tower at the end, a low red sunset behind thick cloud. Palette: dark purple, rust and shadow.",
    "teldrassil": "Huge ancient trees with glowing violet leaves, soft moonlit mist on the forest floor, silver light between the trunks. Palette: violet, teal and silver.",
    "mulgore": "Green rolling plains with tall mesas and a few tipis far away, a wide bright sky with cloud shadows. Palette: grass green, red rock and sky blue.",
    "durotar": "A dry red-brown desert with spiked plants and rocky ridges, a small orc outpost far away under a hot sky. Palette: terracotta, sand and dusty blue.",
    "the-barrens": "A wide yellow savannah with flat-topped trees and scattered rock, a lone water-hole in the distance, a big pale sky. Palette: savannah gold, dry green and warm blue.",
    "darkshore": "A moonlit coast of cliffs and twisted trees, soft waves on dark sand, silver light on the sea. Palette: sea blue, deep teal and moon silver.",
    "stonetalon-mountains": "Tall red-grey rock spires with pine forest at their feet, wooden lifts and ropes at the edges, golden mist in the valley. Palette: rust, pine green and gold.",
    "ashenvale": "A tall twilight forest of silver-barked trees with a calm stream, shafts of blue light through leaves, a moonwell glowing faintly far away. Palette: forest green, blue and soft silver.",
    "thousand-needles": "Tall thin rock needles above a misty canyon floor, a rope bridge far away, a warm bright sky. Palette: sandstone, deep blue shade and gold.",
    "desolace": "A barren land of dead trees and pale rock, a faint spirit glow in the distance, a heavy grey sky. Palette: bone, grey-blue and faded green.",
    "dustwallow-marsh": "A misty marsh with twisted trees and slow water, a faint lighthouse glow on a far cliff, low grey cloud. Palette: swamp green, grey and soft amber.",
    "feralas": "A lush jungle of huge green trees with vines and mossy ruins, waterfalls on a far cliff, bright green light. Palette: emerald, mossy gold and mist white.",
    "tanaris": "A rolling golden desert under a hot pale sky, a distant coast town and rocky dunes, heat shimmer. Palette: sand gold, bleached white and warm turquoise.",
    "azshara": "A purple-tinged coast of old elven ruins, stone arches half buried in sand, a calm sea with a sunset glow. Palette: dusk violet, rose and sea teal.",
    "ungoro-crater": "A giant lush crater with towering ferns and crystals, dinosaur-sized plants at the edges, a warm green glow from a volcano on the far side. Palette: fern green, lava orange and teal.",
    "felwood": "A corrupted forest of twisted dark trees with sickly green fel light, ash-grey ground, a purple haze. Palette: poison green, violet and soot.",
    "winterspring": "A snowy mountain valley with frozen pines and a glowing blue lake far away, pale pink sky. Palette: ice blue, white and soft rose.",
    "moonglade": "A calm moonlit glade with a still silver lake and old standing stones, soft green light and white blossoms. Palette: silver, moss green and midnight blue.",
    "silithus": "An orange desert under a dark sky, a huge hive of the Qiraji with insect towers in the distance, drifting sand. Palette: sand orange, violet and bone.",
};

const style = "Use case: stylized-concept. Asset: scenic background plate behind a live 3D character or object in a small landscape card portrait. Painterly fantasy game environment, cinematic atmospheric perspective, broad shapes that read at thumbnail size, soft mid-distance detail. Keep a broad relatively even midtone opening behind the centre so a character's head and shoulders will silhouette clearly. Frame the scene with detail near the outer edges. No people, creatures, characters, readable text, logos, borders, cards, UI, watermarks or lettering. Fill the entire picture. Landscape composition around 4:3.";

const out = [
    "Portrait backdrops still to paint, written in the same style as Portrait-Backdrops.txt.",
    "Generated by tools/backdrop-prompts.js. Save each picture as a 512 x 384, 32-bit, uncompressed TGA in this folder,",
    "then add the place and file name to the `backdrops` table in Catalog.lua.",
    "",
];
let count = 0;
for (const place of places) {
    if (done.has(place.slug)) continue;
    const scene = scenes[place.slug];
    if (!scene) throw new Error("no scene written for " + place.slug);
    out.push(`${place.name} (${place.slug}, ${place.kind})`, `${style} ${scene}`, "");
    count++;
}
for (const slug of Object.keys(scenes)) {
    if (!places.some((place) => place.slug === slug)) throw new Error("scene for an unknown place: " + slug);
}
fs.writeFileSync(path.join(root, "Art", "Portrait-Backdrops-Needed.txt"), out.join("\n"));
console.log(`${count} prompts written`);
