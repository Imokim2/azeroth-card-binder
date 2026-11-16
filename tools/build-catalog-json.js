// Writes packages/shared/catalog.json: the card catalog as data, for the server, the app and the website.
//
//   node tools/build-catalog-json.js
//
// The add-on's Lua files stay the source of truth. This loads them with LuaJIT (no game needed) and writes out
// what the other parts need to check a ledger: every card (name, rarity, rank, set), every set, the drop rates,
// the shiny odds and the Binder Dust values. Output is sorted and deterministic, so running it twice changes
// nothing, and `catalogVersion` is a hash of the content: it changes exactly when the catalog does.
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.join(__dirname, "..");
const luajit = process.env.LUAJIT || "luajit";
const output = process.env.CATALOG_OUT || path.join(root, "packages", "shared", "catalog.json");

// Runs inside LuaJIT. Prints one JSON document: plain tables only, written by hand so no library is needed.
const dump = String.raw`
local addon = "AzerothCardBinder"
local ACB = {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "CatalogFellowship.lua", "DropRates.lua", "Editions.lua", "UnobtainableCards.lua", "LaunchCollection.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end

local function quote(text)
    return '"' .. tostring(text):gsub('[%c"\\]', function(c)
        local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return named[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function encode(value)
    local kind = type(value)
    if kind == "string" then return quote(value) end
    if kind == "number" then return string.format("%.0f", value) end
    if kind == "boolean" then return tostring(value) end
    if kind ~= "table" then error("cannot encode " .. kind) end
    local parts = {}
    if #value > 0 then
        for _, inner in ipairs(value) do parts[#parts + 1] = encode(inner) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for _, key in ipairs(sortedKeys(value)) do parts[#parts + 1] = quote(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local cards, sets = {}, {}
for _, page in ipairs(ACB.pages) do
    local keys = {}
    for _, card in ipairs(page.cards) do
        keys[#keys + 1] = card.key
        local entry = { name = card.name, rarity = card.rarity, rank = card.rank, set = page.code }
        if card.boss then entry.boss = true end
        if card.seasonal then entry.seasonal = true end -- held back for seasons (LaunchCollection.lua)
        if card.unobtainable then entry.unobtainable = true end -- its creature cannot be killed (UnobtainableCards.lua)
        if card.faction then entry.faction = card.faction end -- only that faction can win it ("alliance" or "horde"; ledger spec 10)
        if card.activity then entry.activity = card.activity end -- earned only by completing this activity (Fellowship, ledger spec 12)
        if card.since then entry.since = card.since end -- added in this ledger spec: not acquired before mode/faction1
        if card.profession then entry.profession = card.profession end
        entry.dropProfile, entry.critter = card.dropProfile, card.critter
        cards[card.key] = entry
    end
    table.sort(keys)
    local required = {}
    for _, card in ipairs(page.required or page.cards) do required[#required + 1] = card.key end
    table.sort(required)
    sets[#sets + 1] = { code = page.code, title = page.title, group = page.group, reward = page.reward, cards = keys,
        required = #required ~= #keys and required or nil }
end
table.sort(sets, function(a, b) return a.code < b.code end)
local editions = {}
for baseKey, family in pairs(ACB.editions) do
    local list = {}
    for index = 2, #family do
        local card = family[index]
        cards[card.key] = { name = card.name, rarity = card.rarity, rank = card.rank, set = ACB.pages[card.page].code,
            baseKey = baseKey, editionTitle = card.editionTitle, boss = card.boss,
            dropProfile = card.dropProfile, critter = card.critter, balanceOnly = card.balanceOnly }
        list[#list + 1] = { key = card.key, weight = card.editionWeight }
    end
    editions[baseKey] = list
end

io.write(encode({
    cards = cards,
    editions = editions,
    dust = ACB.dust,
    stackFactor = ACB.stackFactor,
    rates = ACB.rates,
    sets = sets,
    shinyOdds = ACB.shinyOdds,
}))
`;

function build() {
    const result = spawnSync(luajit, ["-"], { cwd: root, input: dump, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    if (result.error || result.status !== 0) {
        throw new Error(`LuaJIT failed (${luajit}): ${result.error ? result.error.message : result.stderr}`);
    }
    const catalog = JSON.parse(result.stdout);
    // Freeze the published spec-9 launch rules for events before mode/faction1.
    // New active lists must not reinterpret a saved drop, pack or completed page.
    const previous = JSON.parse(fs.readFileSync(path.join(root, "packages", "shared", "spec9-collection.json"), "utf8"));
    for (const [key, seasonal] of Object.entries(previous.seasonal)) {
        if (!catalog.cards[key]) throw new Error(`missing historical card ${key}`);
        catalog.cards[key].seasonalBeforeFaction = seasonal;
    }
    for (const [code, required] of Object.entries(previous.required)) {
        const set = catalog.sets.find(entry => entry.code === code);
        if (!set || required.some(key => !catalog.cards[key])) throw new Error(`missing historical set ${code}`);
        set.requiredBeforeFaction = required;
    }
    for (const set of catalog.sets) {
        if (!set.code) throw new Error(`a set has no code: ${set.title}`);
    }
    // The version is a hash of the content, so it changes exactly when the catalog does.
    const version = crypto.createHash("sha256").update(JSON.stringify(catalog)).digest("hex").slice(0, 12);
    return { catalogVersion: version, ...catalog };
}

if (require.main === module) {
    const catalog = build();
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, JSON.stringify(catalog) + "\n");
    console.log(`wrote ${path.relative(root, output)}: ${Object.keys(catalog.cards).length} cards, ${catalog.sets.length} sets, version ${catalog.catalogVersion}`);
}

module.exports = { build };
