test("artwork falls back from the journal to loading screens to the zone a dungeon sits in", function()
    local function artFor(slug)
        local entry = ACB.pages[ACB.pageForPlace[slug]].cards[1]
        local card = ACB.createCard(UIParent)
        card:set(entry, 1)
        return card.art
    end
    -- 1. The Dungeon Journal knows the place (listed with "The" in front).
    EJ_GetInstanceByIndex = function(position, raid)
        if position == 1 and raid == false then return 240, "The Wailing Caverns" end
    end
    EJ_GetInstanceInfo = function(id) return "name", "text", 9001 end
    equal(artFor("wailing-caverns").base.texture, 9001)
    EJ_GetInstanceByIndex, EJ_GetInstanceInfo = nil, nil

    -- 2. A loading screen named after the place.
    local asked = {}
    GetFileIDFromPath = function(path)
        asked[#asked + 1] = path
        if path == "Interface\\Glues\\LoadingScreens\\LoadScreenRazorfenKraul" then return 9002 end
    end
    equal(artFor("razorfen-kraul").base.texture, 9002)
    GetFileIDFromPath = nil

    -- 3. No picture of its own: the map of the zone it sits in (Maraudon is in Desolace).
    C_Map = {
        GetMapChildrenInfo = function() return { { name = "Desolace", mapID = 101 } } end,
        GetMapArtLayers = function(map) return map == 101 and { { layerWidth = 2, layerHeight = 1, tileWidth = 1, tileHeight = 1 } } or nil end,
        GetMapArtLayerTextures = function() return { 9003, 9004 } end,
    }
    local art = artFor("maraudon")
    C_Map = nil
    equal(art.tiles[1].texture, 9003)
    equal(art.tiles[2].texture, 9004)
    equal(ACB.zones.maraudon.parent, "Desolace")
    for slug in pairs(ACB.instanceZones) do assert(ACB.zones[slug], "every instance names a place that exists: " .. slug) end
end)

test("saved data cleaning drops what the add-on cannot use, keeps the rest, and is repeatable", function()
    local saved = ACB.cleanSavedData({
        counts = { ["npc:639"] = 2, ["npc:589"] = -1, ["npc:590"] = 1.5, ["npc:573"] = "many", ["npc:99999"] = 3 },
        misses = { ["npc:639"] = 12, ["npc:589"] = 0, ["npc:99999"] = 4 },
        shiny = { ["npc:639"] = true, ["npc:589"] = "yes", ["npc:99999"] = true },
        wanted = { ["npc:573"] = true, ["npc:99999"] = true },
        history = { { give = "npc:639", take = "npc:573" }, "junk", { give = "npc:99999", take = "npc:573" } },
        dust = -5, tradeCount = 0, sets = { DM = true, XX = 1 },
        titles = { ["Defias Bane"] = true, [5] = true, Bad = false }, levels = { x = 1 },
    })
    equal(saved.counts["npc:639"], 2)
    equal(saved.counts["npc:589"], nil) -- below one
    equal(saved.counts["npc:590"], nil) -- not a whole number
    equal(saved.counts["npc:573"], nil) -- not a number
    equal(saved.counts["npc:99999"], 3) -- a card that left the catalog keeps its copies
    equal(saved.misses["npc:639"], 12)
    equal(saved.misses["npc:589"], nil)
    equal(saved.misses["npc:99999"], nil) -- a bad-luck counter for an unknown card is meaningless
    equal(saved.shiny["npc:639"], true)
    equal(saved.shiny["npc:589"], nil)
    equal(saved.shiny["npc:99999"], nil)
    equal(saved.wanted["npc:573"], true)
    equal(saved.wanted["npc:99999"], nil)
    equal(#saved.history, 1)
    equal(saved.dust, 0)
    equal(saved.tradeCount, 1)
    equal(saved.sets.DM, true)
    equal(saved.sets.XX, nil)
    equal(saved.titles["Defias Bane"], true)
    equal(saved.titles[5], nil)
    equal(saved.titles.Bad, nil)
    equal(saved.levels, nil)
    -- Cleaning again changes nothing.
    ACB.cleanSavedData(saved)
    equal(saved.counts["npc:639"], 2)
    equal(#saved.history, 1)
    equal(saved.tradeCount, 1)
    -- An empty or wrongly typed file becomes a usable one.
    local fresh = ACB.cleanSavedData({ counts = "oops", dust = "lots" })
    equal(type(fresh.counts), "table")
    equal(type(fresh.history), "table")
    equal(fresh.dust, 0)
    equal(type(ACB.tableOrEmpty(5)), "table")
end)

test("no add-on code file grows past the size rule, and every listed file exists", function()
    -- Generated catalogs and the lore tables are data, not code, and are exempt.
    local data = { ["CatalogForever.lua"] = true, ["CatalogNodes.lua"] = true, ["Lore.lua"] = true }
    local limit, listed = 450, 0
    for name in io.lines(addon .. "/" .. addon .. ".toc") do
        name = name:gsub("%s+$", "")
        if name:match("%.lua$") then
            listed = listed + 1
            local lines = 0
            for _ in io.lines(addon .. "/" .. name) do lines = lines + 1 end
            assert(data[name] or lines <= limit, ("%s has %d lines; split it before adding more (limit %d)"):format(name, lines, limit))
        end
    end
    assert(listed >= 20, "the .toc should list the add-on's files")
end)
