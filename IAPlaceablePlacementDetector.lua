-- IAPlaceablePlacementDetector.lua — Detects when a "tool" placeable is placed via the
-- construction screen and converts it into a real IAMapPlace entry in the Fields of Stories
-- place system. The placeable is deleted after conversion; it only serves as a positioning tool.
--
-- Extension: add a new entry to TOOL_PLACEABLES (keyed by storeItem.rawXMLFilename / relative path) with:
--   configSource   = configuration key to read from placeable.configurations (e.g. "solarPanels")
--   mappings       = { [configIndex] = { placeType, sizeType, withVehicle, withAttachment } }
--   defaultMapping = fallback if config cannot be read

IAPlaceablePlacementDetector = IAPlaceablePlacementDetector or {}

--------------------------------------------------------------------------------
-- Mapping table: tool placeable → place creation parameters
--------------------------------------------------------------------------------

--- Maps a normalized relative config filename to handler info.
-- The key MUST match the rawXMLFilename from the placeable's storeItem
-- (i.e. the path as registered in modDesc.xml <storeItems>).
-- placeType       = fixed place type for this tool
-- sizes           = table sizeIndex → { sizeType, withVehicle, withAttachment }
-- defaultSize     = fallback size index when IANeighbours.placeableToolSizeIndex is unset
--
-- Size indices (controlled by IANeighbours.placeableToolSizeIndex keybind):
--   1 = character
--   2 = vehicle
--   3 = vehicle_attachment
--   4 = oversize_vehicle
--   5 = large_area
IAPlaceablePlacementDetector.TOOL_PLACEABLES = {
    ["placeables/place_character/place_character_public_place.xml"] = {
        displayName = "Place: Public Place",
        placeType = "public_place",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_shop.xml"] = {
        displayName = "Place: Shop",
        placeType = "shop",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_gas_station.xml"] = {
        displayName = "Place: Gas Station",
        placeType = "gas_station",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_roadside.xml"] = {
        displayName = "Place: Roadside",
        placeType = "roadside",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_dirt_road.xml"] = {
        displayName = "Place: Dirt Road",
        placeType = "dirt_road",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_player_farm.xml"] = {
        displayName = "Place: Player Farm",
        placeType = "player_farm",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_public_relax_place.xml"] = {
        displayName = "Place: Public Relax",
        placeType = "public_relax_place",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_private_relax_place.xml"] = {
        displayName = "Place: Private Relax",
        placeType = "private_relax_place",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_sell_point.xml"] = {
        displayName = "Place: Sell Point",
        placeType = "sell_point",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_church.xml"] = {
        displayName = "Place: Church",
        placeType = "church",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_public_infrastructure.xml"] = {
        displayName = "Place: Public Infrastructure",
        placeType = "public_infrastructure",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_industry.xml"] = {
        displayName = "Place: Industry",
        placeType = "industry",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_workshop.xml"] = {
        displayName = "Place: Workshop",
        placeType = "workshop",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_shed.xml"] = {
        displayName = "Place: Shed",
        placeType = "shed",
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/place_character/place_character_remove.xml"] = {
        displayName = "Tool: Remove Place",
        placeType = "remove",
        sizes = {
            [1] = { sizeType = "remove", withVehicle = false, withAttachment = false },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_18_homebase.xml"] = {
        displayName = "Character Homebase: Marcus Brown",
        placeType = "character_homebase",
        characterNumber = 18,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
            [4] = { sizeType = "oversize_vehicle",  withVehicle = true,  withAttachment = true  },
            [5] = { sizeType = "large_area",        withVehicle = true,  withAttachment = true  },
            [6] = { sizeType = "silo",              withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_19_homebase.xml"] = {
        displayName = "Character Homebase: Jacob Miller",
        placeType = "character_homebase",
        characterNumber = 19,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
            [4] = { sizeType = "oversize_vehicle",  withVehicle = true,  withAttachment = true  },
            [5] = { sizeType = "large_area",        withVehicle = true,  withAttachment = true  },
            [6] = { sizeType = "silo",              withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_20_homebase.xml"] = {
        displayName = "Character Homebase: Emma Kensington",
        placeType = "character_homebase",
        characterNumber = 20,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
            [4] = { sizeType = "oversize_vehicle",  withVehicle = true,  withAttachment = true  },
            [5] = { sizeType = "large_area",        withVehicle = true,  withAttachment = true  },
            [6] = { sizeType = "silo",              withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_21_homebase.xml"] = {
        displayName = "Character Homebase: Brian Winter",
        placeType = "character_homebase",
        characterNumber = 21,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
            [4] = { sizeType = "oversize_vehicle",  withVehicle = true,  withAttachment = true  },
            [5] = { sizeType = "large_area",        withVehicle = true,  withAttachment = true  },
            [6] = { sizeType = "silo",              withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_1_homebase.xml"] = {
        displayName = "Character Homebase: Mary Carter",
        placeType = "character_homebase",
        characterNumber = 1,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_2_homebase.xml"] = {
        displayName = "Character Homebase: John Carter",
        placeType = "character_homebase",
        characterNumber = 2,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_10_homebase.xml"] = {
        displayName = "Character Homebase: Sharon Whitaker",
        placeType = "character_homebase",
        characterNumber = 10,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_11_homebase.xml"] = {
        displayName = "Character Homebase: Kyle Bennett",
        placeType = "character_homebase",
        characterNumber = 11,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_13_homebase.xml"] = {
        displayName = "Character Homebase: Lukas Brenner",
        placeType = "character_homebase",
        characterNumber = 13,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_14_homebase.xml"] = {
        displayName = "Character Homebase: Martin Walker",
        placeType = "character_homebase",
        characterNumber = 14,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_15_homebase.xml"] = {
        displayName = "Character Homebase: Susan Keller",
        placeType = "character_homebase",
        characterNumber = 15,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_16_homebase.xml"] = {
        displayName = "Character Homebase: Andy Hoffman",
        placeType = "character_homebase",
        characterNumber = 16,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
    ["placeables/character_homebase/char_17_homebase.xml"] = {
        displayName = "Character Homebase: Paul Meyer",
        placeType = "character_homebase",
        characterNumber = 17,
        sizes = {
            [1] = { sizeType = "character",         withVehicle = false, withAttachment = false },
            [2] = { sizeType = "vehicle",           withVehicle = true,  withAttachment = false },
            [3] = { sizeType = "vehicle_attachment", withVehicle = true,  withAttachment = true  },
            [4] = { sizeType = "oversize_vehicle",  withVehicle = true,  withAttachment = true  },
            [5] = { sizeType = "large_area",        withVehicle = true,  withAttachment = true  },
            [6] = { sizeType = "silo",              withVehicle = true,  withAttachment = true  },
        },
        defaultSize = 1,
    },
}

--------------------------------------------------------------------------------
-- Internal state
--------------------------------------------------------------------------------

--- Set of already-processed placeable uniqueIds (prevents re-processing).
IAPlaceablePlacementDetector._seenUniqueIds = {}

--- Resolve the relative XML filename for a placeable.
-- Uses storeItem.rawXMLFilename (the path as registered in modDesc) which is always
-- relative. Falls back to configFileName stripped to relative form.
-- @param placeable table The placeable object
-- @return string|nil Normalized relative path (lowercase, forward slashes)
local function _getRelativePath(placeable)
    if placeable == nil then return nil end

    -- Best: storeItem.rawXMLFilename is the modDesc-registered relative path
    local storeItem = placeable.storeItem
    if storeItem ~= nil and storeItem.rawXMLFilename ~= nil and storeItem.rawXMLFilename ~= "" then
        return tostring(storeItem.rawXMLFilename):gsub("\\", "/"):lower()
    end

    -- Fallback: strip absolute prefix from configFileName to get relative path
    local cf = placeable.configFileName
    if cf == nil or cf == "" then return nil end
    local s = tostring(cf):gsub("\\", "/"):lower()

    -- Try to find "placeables/" in the path and strip everything before it
    local idx = s:find("placeables/")
    if idx ~= nil then
        return s:sub(idx)
    end

    return s
end

--- Seed the seen-set with all existing placeables so we don't re-process
-- placeables already present when this function is called (e.g. after savegame load).
function IAPlaceablePlacementDetector:seedFromExistingPlaceables()
    self._seenUniqueIds = {}
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil or ps.placeables == nil then
        return
    end
    for _, p in ipairs(ps.placeables) do
        if p ~= nil and p.uniqueId ~= nil then
            self._seenUniqueIds[p.uniqueId] = true
        end
    end
    if IANeighbours and IANeighbours.debug then
        local n = 0
        for _ in pairs(self._seenUniqueIds) do n = n + 1 end
        print("--- IAPlaceablePlacementDetector: seeded seen-set with " .. tostring(n) .. " existing placeables")
    end
end

--------------------------------------------------------------------------------
-- Live Preview: draws a debug box at the construction cursor while our tool is selected
--------------------------------------------------------------------------------

--- Display name → TOOL_PLACEABLES key reverse map (built once from TOOL_PLACEABLES metadata).
IAPlaceablePlacementDetector._displayNameToToolKey = nil

--- Build the displayName → tool-key reverse lookup from TOOL_PLACEABLES metadata.
local function _buildL10nReverseMap()
    if IAPlaceablePlacementDetector._displayNameToToolKey ~= nil then
        return
    end
    IAPlaceablePlacementDetector._displayNameToToolKey = {}
    for toolKey, def in pairs(IAPlaceablePlacementDetector.TOOL_PLACEABLES) do
        if def.displayName ~= nil then
            IAPlaceablePlacementDetector._displayNameToToolKey[def.displayName] = toolKey
        end
    end
end

--- Try to find the selected tool placeable's mappingDef and relative path during construction.
-- Returns mappingDef, relPath OR nil.
local function _findSelectedToolInConstruction()
    if g_constructionScreen == nil or not g_constructionScreen.isOpen then
        return nil, nil
    end
    -- brush.placeable is non-nil only when a placeable is actively selected for
    -- placement. After ESC deselects, it becomes nil while storeItem data stays stale.
    if g_constructionScreen.brush == nil or g_constructionScreen.brush.placeable == nil then
        return nil, nil
    end

    -- Approach 1: try brush.storeItem.rawXMLFilename (most reliable if available)
    local brush = g_constructionScreen.brush
    if brush ~= nil then
        if brush.storeItem ~= nil and brush.storeItem.rawXMLFilename ~= nil then
            local relPath = tostring(brush.storeItem.rawXMLFilename):gsub("\\", "/"):lower()
            local mappingDef = IAPlaceablePlacementDetector.TOOL_PLACEABLES[relPath]
            if mappingDef ~= nil then
                return mappingDef, relPath
            end
        end
        -- Diagnostic: log brush properties once per construction opening
        if IANeighbours and IANeighbours.debug then
            if not IAPlaceablePlacementDetector._loggedBrushType then
                IAPlaceablePlacementDetector._loggedBrushType = true
                local hasStore = brush.storeItem ~= nil
                local rawPath = hasStore and brush.storeItem.rawXMLFilename or "nil"
                print("--- DETECTOR: brush.typeName=" .. tostring(brush.typeName) .. " hasStoreItem=" .. tostring(hasStore) .. " rawXMLFilename=" .. tostring(rawPath))
            end
        end
    else
        if IANeighbours and IANeighbours.debug then
            if not IAPlaceablePlacementDetector._loggedNoBrush then
                IAPlaceablePlacementDetector._loggedNoBrush = true
                print("--- DETECTOR: g_constructionScreen.brush is nil")
            end
        end
    end

    -- Approach 2: match itemDetailsName.sourceText against known display names
    _buildL10nReverseMap()
    local details = g_constructionScreen.itemDetailsName
    if details ~= nil and details.sourceText ~= nil then
        local src = tostring(details.sourceText)
        if IANeighbours and IANeighbours.debug then
            if not IAPlaceablePlacementDetector._loggedDetailsSrc or IAPlaceablePlacementDetector._loggedDetailsSrc ~= src then
                IAPlaceablePlacementDetector._loggedDetailsSrc = src
                print("--- DETECTOR: itemDetailsName.sourceText = " .. src)
            end
        end
        local toolKey = IAPlaceablePlacementDetector._displayNameToToolKey[src]
        if toolKey ~= nil then
            local mappingDef = IAPlaceablePlacementDetector.TOOL_PLACEABLES[toolKey]
            if mappingDef ~= nil then
                return mappingDef, toolKey
            end
        end
    end

    return nil, nil
end

--- Read the current place size index from IANeighbours.placeableToolSizeIndex.
-- Defaults to 1 if unset or out of range for the given mappingDef.
local function _getCurrentSizeIndex(mappingDef)
    local idx = 1
    if IANeighbours ~= nil and IANeighbours.placeableToolSizeIndex ~= nil then
        idx = IANeighbours.placeableToolSizeIndex
    end
    -- Clamp to available sizes
    if mappingDef ~= nil and mappingDef.sizes ~= nil then
        if mappingDef.sizes[idx] == nil then
            idx = mappingDef.defaultSize or 1
        end
    end
    return idx
end

--- Resolve the mapped size params for the current size index.
local function _getMappedSize(mappingDef)
    local idx = _getCurrentSizeIndex(mappingDef)
    return mappingDef.sizes[idx] or mappingDef.sizes[mappingDef.defaultSize or 1]
end

--- Draw a temporary debug box at the construction cursor position for the selected tool.
-- Called every frame when the construction screen is open.
-- Skips drawing when the cursor is near an existing IAMapPlace (within 2m),
-- because debug rendering at positions overlapping existing placeable geometry
-- causes rendering corruption (white boxes flying across the screen).
function IAPlaceablePlacementDetector:_drawConstructionPreview(mappingDef, relPath)
    local cursor = g_constructionScreen.cursor
    if cursor == nil then return end

    local x = cursor.currentHitX
    local z = cursor.currentHitZ
    local ry = cursor.targetRotation

    if x == nil or z == nil then return end

    -- Remove tool: draw a mid-sized red X (skip proximity guard — the remove tool
    -- must work near existing places, so draw before the place-proximity check)
    if mappingDef.placeType == "remove" then
        local cy = (cursor.currentHitY or 0) + 0.5
        if drawDebugPoint ~= nil then
            drawDebugPoint(x, cy, z, 1, 0, 0, 1, true)
        end
        if drawDebugLine ~= nil then
            local xSize = 1.0
            local r, g, b = 1, 0, 0
            drawDebugLine(x - xSize, cy, z - xSize, r, g, b, x + xSize, cy, z + xSize, r, g, b)
            drawDebugLine(x + xSize, cy, z - xSize, r, g, b, x - xSize, cy, z + xSize, r, g, b)
        end
        if DebugUtil ~= nil and DebugUtil.drawDebugCircle ~= nil then
            DebugUtil.drawDebugCircle(x, cy, z, 1.5, 24, {1, 0, 0}, false, false, false)
        end
        return
    end

    -- Skip preview if cursor is near an existing place (prevents rendering corruption)
    if IANeighbours and IANeighbours.places then
        for _, place in ipairs(IANeighbours.places) do
            if place and place.x and place.z then
                local dx = place.x - x
                local dz = place.z - z
                if (dx * dx + dz * dz) < 4 then  -- within 2 meters
                    return
                end
            end
        end
    end

    -- Read current size from IANeighbours.placeableToolSizeIndex
    local mapped = _getMappedSize(mappingDef)
    if mapped == nil then return end

    -- Compute debug box dimensions
    local boxLength, side
    if IANeighbours and IANeighbours.getPlaceDebugBoxLength then
        boxLength = IANeighbours.getPlaceDebugBoxLength(mapped.withVehicle == true, mapped.withAttachment == true, mapped.sizeType)
        side = IANeighbours.getPlaceDebugBoxSide and IANeighbours.getPlaceDebugBoxSide(mapped.withVehicle == true, mapped.withAttachment == true, mapped.sizeType)
    end
    side = side or (IANeighbours and IANeighbours.PLACE_DEBUG_SIDE_M) or 1.5
    local front = (IANeighbours and IANeighbours.PLACE_DEBUG_FRONT_M) or 3

    local cy = (cursor.currentHitY or 0) + 0.5  -- offset above terrain to avoid z-fighting

    -- Center dot (always draw when not near a place)
    if drawDebugPoint ~= nil then
        drawDebugPoint(x, cy, z, 0, 1, 0, 1, true)
    end

    if boxLength == nil or boxLength <= 0 then
        if IANeighbours and IANeighbours.debug then
            renderText(x, cy + 0.5, z, "[PREVIEW] " .. tostring(mappingDef.placeType) .. " (" .. tostring(mapped.sizeType) .. ")", 0.012)
        end
        return
    end

    if getWorldPositionFromYawLocalOffset == nil then return end

    local back = math.max(0, boxLength - front)

    -- 4 corners of the placement box in world space
    local flx, _, flz = getWorldPositionFromYawLocalOffset(x, cy, z, ry, -side, 0, front)
    local frx, _, frz = getWorldPositionFromYawLocalOffset(x, cy, z, ry,  side, 0, front)
    local brx, _, brz = getWorldPositionFromYawLocalOffset(x, cy, z, ry,  side, 0, -back)
    local blx, _, blz = getWorldPositionFromYawLocalOffset(x, cy, z, ry, -side, 0, -back)

    if flx == nil or frx == nil or brx == nil or blx == nil then return end

    -- Green box outline
    if drawDebugLine ~= nil then
        local r, g, b = 0, 1, 0
        drawDebugLine(flx, cy, flz, r, g, b, frx, cy, frz, r, g, b)
        drawDebugLine(frx, cy, frz, r, g, b, brx, cy, brz, r, g, b)
        drawDebugLine(brx, cy, brz, r, g, b, blx, cy, blz, r, g, b)
        drawDebugLine(blx, cy, blz, r, g, b, flx, cy, flz, r, g, b)

        -- Forward arrow
        local arrowLen = front + 3.0
        local tipX, _, tipZ = getWorldPositionFromYawLocalOffset(x, cy, z, ry, 0, 0, arrowLen)
        if tipX ~= nil then
            drawDebugLine(x, cy, z, r, g, b, tipX, cy, tipZ, r, g, b)
            local wlx, _, wlz = getWorldPositionFromYawLocalOffset(x, cy, z, ry, -0.6, 0, arrowLen - 1.2)
            local wrx, _, wrz = getWorldPositionFromYawLocalOffset(x, cy, z, ry,  0.6, 0, arrowLen - 1.2)
            if wlx ~= nil and wrx ~= nil then
                drawDebugLine(tipX, cy, tipZ, r, g, b, wlx, cy, wlz, r, g, b)
                drawDebugLine(tipX, cy, tipZ, r, g, b, wrx, cy, wrz, r, g, b)
            end
        end
    end

    if IANeighbours and IANeighbours.debug then
        renderText(x, cy + 1.2, z, "[PREVIEW] " .. tostring(mappingDef.placeType) .. " (" .. tostring(mapped.sizeType) .. ")", 0.012)
    end
end

--- Live preview: draw a debug box at the construction cursor if our tool is selected.
-- Call this every frame (alongside checkForNewToolPlaceables).
-- Safe to call when construction screen is closed (returns immediately).
function IAPlaceablePlacementDetector:checkForPreview()
    if g_constructionScreen == nil or not g_constructionScreen.isOpen then
        IAPlaceablePlacementDetector._loggedBrushType = nil
        IAPlaceablePlacementDetector._loggedNoBrush = nil
        IAPlaceablePlacementDetector._loggedDetailsSrc = nil
        IAPlaceablePlacementDetector._loggedPreviewFound = nil
        -- Unregister construction-context keybind
        if IAPlaceablePlacementDetector._constructionKeybind ~= nil and g_inputBinding ~= nil then
            g_inputBinding:removeActionEvent(IAPlaceablePlacementDetector._constructionKeybind)
            local me = g_constructionScreen and g_constructionScreen.menuEvents
            if me ~= nil then
                for i = #me, 1, -1 do
                    if me[i] == IAPlaceablePlacementDetector._constructionKeybind then
                        table.remove(me, i)
                    end
                end
            end
            IAPlaceablePlacementDetector._constructionKeybind = nil
        end
        -- Unregister bulk-remove keybind
        if IAPlaceablePlacementDetector._bulkRemoveKeybind ~= nil and g_inputBinding ~= nil then
            g_inputBinding:removeActionEvent(IAPlaceablePlacementDetector._bulkRemoveKeybind)
            local me = g_constructionScreen and g_constructionScreen.menuEvents
            if me ~= nil then
                for i = #me, 1, -1 do
                    if me[i] == IAPlaceablePlacementDetector._bulkRemoveKeybind then
                        table.remove(me, i)
                    end
                end
            end
            IAPlaceablePlacementDetector._bulkRemoveKeybind = nil
        end
        -- Restore place-marker visibility if we auto-enabled it
        if IAPlaceablePlacementDetector._autoMarkersWasOn ~= nil and IANeighbours ~= nil then
            IANeighbours.mapInitPlaceMarkersVisible = IAPlaceablePlacementDetector._autoMarkersWasOn
            IAPlaceablePlacementDetector._autoMarkersWasOn = nil
            if IANeighbours.mapInitPlaceMarkersVisible then
                IANeighbours:rebuildMapInitDebugPoints()
            else
                IANeighbours:clearAllDebugPoints()
            end
        end
        return
    end

    -- Re-register if the construction screen rebuilt menuEvents and wiped our keybind
    if g_constructionScreen.menuEvents ~= nil and IAPlaceablePlacementDetector._constructionKeybind ~= nil then
        local found = false
        for _, id in ipairs(g_constructionScreen.menuEvents) do
            if id == IAPlaceablePlacementDetector._constructionKeybind then found = true; break end
        end
        if not found then
            -- Keybind was wiped by construction screen rebuild; re-register
            g_inputBinding:removeActionEvent(IAPlaceablePlacementDetector._constructionKeybind)
            IAPlaceablePlacementDetector._constructionKeybind = nil
        end
    end
    -- Same for bulk-remove keybind
    if g_constructionScreen.menuEvents ~= nil and IAPlaceablePlacementDetector._bulkRemoveKeybind ~= nil then
        local found = false
        for _, id in ipairs(g_constructionScreen.menuEvents) do
            if id == IAPlaceablePlacementDetector._bulkRemoveKeybind then found = true; break end
        end
        if not found then
            g_inputBinding:removeActionEvent(IAPlaceablePlacementDetector._bulkRemoveKeybind)
            IAPlaceablePlacementDetector._bulkRemoveKeybind = nil
        end
    end

    -- Register keybind (first time or after rebuild wipe)
    if IAPlaceablePlacementDetector._constructionKeybind == nil
        and g_inputBinding ~= nil
        and InputAction ~= nil
        and InputAction.IAPlaceSizeSelect ~= nil then
        local _, eventId = g_inputBinding:registerActionEvent(
            InputAction.IAPlaceSizeSelect,
            g_constructionScreen,
            function() IAPlaceablePlacementDetector:cycleToolSize() end,
            false, true, false, true)
        if eventId ~= nil then
            IAPlaceablePlacementDetector._constructionKeybind = eventId
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
            g_inputBinding:setActionEventTextVisibility(eventId, true)
            g_inputBinding:setActionEventActive(eventId, true)
            g_inputBinding:setActionEventText(eventId, g_i18n and g_i18n:getText("input_IAPlaceSizeSelect") or "Place Size")
            g_constructionScreen.menuEvents = g_constructionScreen.menuEvents or {}
            table.insert(g_constructionScreen.menuEvents, eventId)
            if IANeighbours and IANeighbours.debug then
                print("--- DETECTOR: (re)registered construction-context keybind")
            end
        end
    end

    -- Register bulk-remove keybind (first time or after rebuild wipe)
    if IAPlaceablePlacementDetector._bulkRemoveKeybind == nil
        and g_inputBinding ~= nil
        and InputAction ~= nil
        and InputAction.IAPlaceBulkRemove ~= nil then
        local _, eventId = g_inputBinding:registerActionEvent(
            InputAction.IAPlaceBulkRemove,
            g_constructionScreen,
            function() IAPlaceablePlacementDetector:bulkRemovePlaces() end,
            false, true, false, true)
        if eventId ~= nil then
            IAPlaceablePlacementDetector._bulkRemoveKeybind = eventId
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
            g_inputBinding:setActionEventTextVisibility(eventId, true)
            g_inputBinding:setActionEventActive(eventId, true)
            g_inputBinding:setActionEventText(eventId, g_i18n and g_i18n:getText("input_IAPlaceBulkRemove") or "Bulk Remove")
            g_constructionScreen.menuEvents = g_constructionScreen.menuEvents or {}
            table.insert(g_constructionScreen.menuEvents, eventId)
            if IANeighbours and IANeighbours.debug then
                print("--- DETECTOR: (re)registered bulk-remove keybind")
            end
        end
    end

    -- Draw preview if our tool is selected
    local mappingDef, relPath = _findSelectedToolInConstruction()
    if mappingDef ~= nil then
        -- Auto-enable place markers so the player can see existing places while placing
        if IANeighbours ~= nil and IAPlaceablePlacementDetector._autoMarkersWasOn == nil then
            IAPlaceablePlacementDetector._autoMarkersWasOn = IANeighbours.mapInitPlaceMarkersVisible or false
            if not IAPlaceablePlacementDetector._autoMarkersWasOn then
                IANeighbours.mapInitPlaceMarkersVisible = true
                IANeighbours:rebuildMapInitDebugPoints()
            end
        end
        if IANeighbours and IANeighbours.debug then
            if not IAPlaceablePlacementDetector._loggedPreviewFound then
                IAPlaceablePlacementDetector._loggedPreviewFound = true
                print("--- DETECTOR: PREVIEW FOUND tool, drawing...")
            end
        end
        self:_drawConstructionPreview(mappingDef, relPath)
    end
end

--- Returns true if the construction screen is open AND a Fields of Stories tool placeable is selected.
-- Use this to gate the place-size keybind visibility.
function IAPlaceablePlacementDetector:isAnyToolSelected()
    if g_constructionScreen == nil or not g_constructionScreen.isOpen then
        return false
    end
    local mappingDef, _ = _findSelectedToolInConstruction()
    if IANeighbours and IANeighbours.debug then
        if mappingDef ~= IAPlaceablePlacementDetector._lastIsSelected then
            IAPlaceablePlacementDetector._lastIsSelected = mappingDef
            print("--- DETECTOR: isAnyToolSelected = " .. tostring(mappingDef ~= nil))
        end
    end
    return mappingDef ~= nil
end

--- Public accessor: returns mappingDef, relPath (same as _findSelectedToolInConstruction) for HUD use.
-- Unlike isAnyToolSelected, this also returns the resolved place parameters so the HUD can display
-- the current tool type and size without duplicating the lookup logic.
function IAPlaceablePlacementDetector:getSelectedToolInfo()
    if g_constructionScreen == nil or not g_constructionScreen.isOpen then
        return nil, nil
    end
    return _findSelectedToolInConstruction()
end

--- Cycle the placeable tool size index through only the sizes defined for the currently selected tool.
-- Unlike IANeighbours:cyclePlaceableToolSize() which uses a hardcoded max, this respects
-- the actual sizes table in TOOL_PLACEABLES so tools with 2-3 sizes don't cycle through empty indices.
function IAPlaceablePlacementDetector:cycleToolSize()
    local mappingDef, _ = _findSelectedToolInConstruction()
    if mappingDef == nil or mappingDef.sizes == nil then
        return
    end

    -- Collect defined size indices sorted
    local definedIndices = {}
    for i, _ in pairs(mappingDef.sizes) do
        table.insert(definedIndices, i)
    end
    table.sort(definedIndices)
    if #definedIndices == 0 then
        return
    end

    -- Find current index position in the defined list
    local currentIdx = IANeighbours and IANeighbours.placeableToolSizeIndex or 1
    local pos = 1
    for pi, si in ipairs(definedIndices) do
        if si == currentIdx then
            pos = pi
            break
        elseif si > currentIdx then
            -- Current index not in defined set (e.g. switched tools); start cycle from here
            pos = pi
            break
        end
    end

    -- Advance to next, wrapping around
    pos = pos + 1
    if pos > #definedIndices then
        pos = 1
    end
    local nextIdx = definedIndices[pos]

    if IANeighbours ~= nil then
        IANeighbours.placeableToolSizeIndex = nextIdx
    end

    if IANeighbours and IANeighbours.debug then
        local sizeNames = { "character", "vehicle", "vehicle+attachment", "oversize", "large area", "silo" }
        print("--- DETECTOR: cycleToolSize -> " .. tostring(nextIdx) .. " (" .. (sizeNames[nextIdx] or "?") .. ") of " .. #definedIndices .. " defined sizes")
    end
end

--- Bulk-remove all places matching the currently selected tool's place type.
-- For public places: removes all places of that type (filtered by current size selection).
-- For character_homebase: removes only places assigned to the specific character.
-- Shows a confirmation dialog before executing.
function IAPlaceablePlacementDetector:bulkRemovePlaces()
    local mappingDef, _ = _findSelectedToolInConstruction()
    if mappingDef == nil then
        return
    end

    -- Don't bulk-remove when the "remove" tool itself is selected
    if mappingDef.placeType == "remove" then
        return
    end

    local ptype = mappingDef.placeType

    -- Determine character scope for homebases
    local characterId = nil
    local characterName = nil
    local assignedPlaceIds = nil
    if ptype == "character_homebase" and mappingDef.characterNumber ~= nil then
        characterId = mappingDef.characterNumber
        if IANeighbours ~= nil and IANeighbours.neighbours ~= nil then
            for _, n in pairs(IANeighbours.neighbours) do
                if n ~= nil and not n.isDeleted and n.id == characterId then
                    if n.name ~= nil then
                        characterName = n.name
                    end
                    if n.assignedHomebasePlaceIds ~= nil then
                        assignedPlaceIds = {}
                        for _, pid in ipairs(n.assignedHomebasePlaceIds) do
                            assignedPlaceIds[tostring(pid)] = true
                        end
                    end
                    break
                end
            end
        end
        if characterName == nil then
            characterName = mappingDef.displayName or ("Character #" .. tostring(characterId))
        end
    end

    -- Count matching places
    local count = 0
    if IANeighbours ~= nil and IANeighbours.places ~= nil then
        for _, place in ipairs(IANeighbours.places) do
            if place ~= nil then
                local st = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
                if st == ptype then
                    local charMatch = true
                    if characterId ~= nil then
                        if assignedPlaceIds ~= nil and place.id ~= nil then
                            charMatch = assignedPlaceIds[tostring(place.id)] == true
                        else
                            charMatch = false
                        end
                    end
                    if charMatch then
                        count = count + 1
                    end
                end
            end
        end
    end

    if count == 0 then
        if g_i18n ~= nil then
            local msg = g_i18n:getText("gui_fos_bulk_remove_none") or "No places of this type to remove."
            pcall(function()
                if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
                    and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
                    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
                end
            end)
        end
        if IANeighbours and IANeighbours.debug then
            print("--- DETECTOR: bulkRemovePlaces: no matching places for type=" .. tostring(ptype))
        end
        return
    end

    -- Build confirm message
    local confirmMsg
    if characterId ~= nil and characterName ~= nil then
        confirmMsg = (g_i18n and g_i18n:getText("gui_fos_bulk_remove_confirm_char")) or "Remove %d place(s) for '%s'?"
        confirmMsg = string.format(confirmMsg, count, characterName)
    else
        local typeLabel = mappingDef.displayName or ptype
        confirmMsg = (g_i18n and g_i18n:getText("gui_fos_bulk_remove_confirm")) or "Remove %d place(s) of type '%s'?"
        confirmMsg = string.format(confirmMsg, count, typeLabel)
    end

    -- Show confirmation dialog, then perform removal on confirm
    if g_gui ~= nil and g_gui.showDialog ~= nil then
        IAPlaceablePlacementDetector._pendingBulkRemove = {
            ptype = ptype,
            characterId = characterId,
            count = count,
        }
        -- Ensure the dialog GUI is loaded before showing it
        if g_gui.guis == nil or g_gui.guis["IABulkRemoveConfirmGUI"] == nil then
            local baseDir = IANeighbours and IANeighbours.dir or g_currentModDirectory
            if baseDir ~= nil then
                local path = baseDir .. "gui/IABulkRemoveConfirmGUI.xml"
                local controller = IABulkRemoveConfirmGUI.new(g_gui)
                g_gui:loadGui(path, "IABulkRemoveConfirmGUI", controller, false)
                if IANeighbours and IANeighbours.debug then
                    print("--- DETECTOR: loaded IABulkRemoveConfirmGUI gui=" .. tostring(g_gui.guis["IABulkRemoveConfirmGUI"]))
                end
            end
        end
        if IANeighbours and IANeighbours.debug then
            print("--- DETECTOR: showing IABulkRemoveConfirmGUI, pending=" .. tostring(IAPlaceablePlacementDetector._pendingBulkRemove ~= nil))
        end
        local dialog = g_gui:showDialog("IABulkRemoveConfirmGUI")
        -- Store dialog reference so the controller can close itself
        IAPlaceablePlacementDetector._bulkRemoveDialog = dialog
        -- Also push dialog ref to the controller and trigger onOpen manually
        local gui = g_gui.guis["IABulkRemoveConfirmGUI"]
        if gui ~= nil and gui.target ~= nil then
            if gui.target.setDialog ~= nil then
                gui.target:setDialog(dialog)
                if IANeighbours and IANeighbours.debug then
                    print("--- DETECTOR: setDialog called on controller, dialog=" .. tostring(dialog))
                end
            end
            if gui.target.onOpen ~= nil then
                gui.target:onOpen()
            end
        end
    end
end

--- Execute the pending bulk removal (called from the confirm dialog).
function IAPlaceablePlacementDetector:executeBulkRemove()
    if IANeighbours and IANeighbours.debug then
        print("--- DETECTOR: executeBulkRemove called")
    end
    local pending = IAPlaceablePlacementDetector._pendingBulkRemove
    if pending == nil then
        return
    end
    IAPlaceablePlacementDetector._pendingBulkRemove = nil

    if IANeighbours == nil then
        return
    end

    local removed = IANeighbours:removePlacesByType(pending.ptype, nil, pending.characterId)

    -- Show notification
    if g_i18n ~= nil then
        local msg = g_i18n:getText("gui_fos_bulk_remove_done") or "Removed %d place(s)."
        msg = string.format(msg, removed)
        pcall(function()
            if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
                and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
            end
        end)
    end

    if IANeighbours and IANeighbours.debug then
        print(string.format("--- DETECTOR: executeBulkRemove removed %d places (type=%s, char=%s)",
            removed, tostring(pending.ptype), tostring(pending.characterId)))
    end
end

--- Check for newly placed tool placeables. Call this once per frame.
-- In FS25, the construction brush ghost is NOT a real placeable in placeableSystem.placeables —
-- it only becomes a real placeable when the user clicks to confirm placement. Therefore we can
-- safely iterate all placeables every frame without needing brush-path detection.
function IAPlaceablePlacementDetector:checkForNewToolPlaceables()
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil or ps.placeables == nil then
        return
    end

    for _, placeable in ipairs(ps.placeables) do
        if placeable == nil or placeable.uniqueId == nil then
            -- not fully initialized yet
        elseif self._seenUniqueIds[placeable.uniqueId] then
            -- already processed
        elseif placeable.rootNode == nil or not entityExists(placeable.rootNode) then
            -- i3d not loaded yet; check again next frame
        else
            local relPath = _getRelativePath(placeable)
            if relPath ~= nil then
                local mappingDef = self.TOOL_PLACEABLES[relPath]
                if mappingDef ~= nil then
                    self:_handleNewToolPlaceable(placeable, mappingDef, relPath)
                end
            end
            self._seenUniqueIds[placeable.uniqueId] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Conversion: placeable → IAMapPlace
--------------------------------------------------------------------------------

--- Internal: convert a newly detected tool placeable into a real place.
-- @param placeable table The placed tool placeable
-- @param mappingDef table Entry from TOOL_PLACEABLES
-- @param normPath string Normalized configFileName (for logging)
function IAPlaceablePlacementDetector:_handleNewToolPlaceable(placeable, mappingDef, normPath)
    -- 1) Read current size from IANeighbours.placeableToolSizeIndex
    local mapped = _getMappedSize(mappingDef)
    if mapped == nil then
        if IANeighbours and IANeighbours.debug then
            print("--- IAPlaceablePlacementDetector: no size mapping for path=" .. tostring(normPath))
        end
        return
    end

    -- 3) Extract world position and rotation.
    --    Avoid getWorldRotation: Euler angles clamp at ±π/2.
    --    Use localDirectionToWorld + MathUtil.getYRotationFromDirection instead (same as
    --    IAMapInitDialogGUI:getCurrentPosition and the legacy place system).
    local x, y, z = getWorldTranslation(placeable.rootNode)
    local ry = 0
    if localDirectionToWorld ~= nil and placeable.rootNode ~= nil then
        local dirX, _, dirZ = localDirectionToWorld(placeable.rootNode, 0, 0, 1)
        if MathUtil ~= nil and MathUtil.getYRotationFromDirection ~= nil then
            ry = MathUtil.getYRotationFromDirection(dirX, dirZ)
        end
    end

    if x == nil or z == nil then
        if IANeighbours and IANeighbours.debug then
            print("--- IAPlaceablePlacementDetector: invalid position for " .. tostring(normPath))
        end
        return
    end

    if IANeighbours and IANeighbours.debug then
        local sizeIdx = _getCurrentSizeIndex(mappingDef)
        print(string.format("--- IAPlaceablePlacementDetector: converting %s sizeIdx=%d → type=%s size=%s at (%.2f, %.2f, %.2f) rot=%.2f",
            tostring(normPath), sizeIdx, tostring(mappingDef.placeType), tostring(mapped.sizeType), x, y or 0, z, ry or 0))
    end

    -- 4) Delete the tool placeable from the world.
    --    Direct delete() handles physics removal + placeableSystem deregistration.
    --    Avoid IAPlaceableHelper.removePlaceable() — it calls delete() then
    --    double-calls placeableSystem:removePlaceable() which fails on a destroyed placeable.
    if placeable.delete ~= nil and type(placeable.delete) == "function" then
        local ok, err = pcall(placeable.delete, placeable)
        if not ok and IANeighbours and IANeighbours.debug then
            print("--- IAPlaceablePlacementDetector: WARNING failed to delete placeable: " .. tostring(err))
        end
    end

    -- 5) Handle "remove" type: delete nearest place within 5m (IAMapPlaces + farmer silos)
    if mappingDef.placeType == "remove" then
        local removedPlace = IANeighbours:removeNearestPlaceAt(x, z, 5)
        local removedSilo = false

        -- If the removed IAMapPlace was a silo type, delete the game placeable
        -- and clear the link from all other silo IAMapPlaces that shared it.
        if removedPlace ~= nil and removedPlace.sizeType == "silo" and removedPlace._siloPlaceableUniqueId ~= nil then
            local siloUid = removedPlace._siloPlaceableUniqueId
            -- Clear the link from all other silo places sharing this silo
            if IANeighbours and IANeighbours.places then
                for _, p in ipairs(IANeighbours.places) do
                    if p ~= nil and p ~= removedPlace and p.sizeType == "silo"
                        and p._siloPlaceableUniqueId == siloUid then
                        p._siloPlaceableUniqueId = nil
                    end
                end
            end
            -- Clear _charSiloMap entry so a future place can re-spawn
            if IANeighbours and IANeighbours.xmlHelper and IANeighbours.xmlHelper._charSiloMap then
                for charId, uid in pairs(IANeighbours.xmlHelper._charSiloMap) do
                    if uid == siloUid then
                        IANeighbours.xmlHelper._charSiloMap[charId] = nil
                        break
                    end
                end
            end
            -- Delete the game placeable
            local ps = g_currentMission and g_currentMission.placeableSystem
            if ps and ps.placableByUniqueId then
                local silo = ps.placableByUniqueId[tostring(siloUid)]
                if silo ~= nil and not silo.isDeleted and not silo.isDeleting then
                    -- Clean up neighbour's IANeighbourPlaceable reference
                    if IANeighbours and IANeighbours.neighbours then
                        for _, neighbour in pairs(IANeighbours.neighbours) do
                            if neighbour and neighbour.placeables then
                                for uid, iaPl in pairs(neighbour.placeables) do
                                    if iaPl and iaPl._mapPlace == removedPlace then
                                        iaPl.placeable = nil
                                        iaPl._mapPlace = nil
                                        break
                                    end
                                end
                            end
                        end
                    end
                    if silo.delete then
                        pcall(silo.delete, silo)
                    end
                    removedSilo = true
                    if IANeighbours and IANeighbours.debug then
                        print("--- IAPlaceablePlacementDetector: removed farmer silo " .. tostring(silo.uniqueId))
                    end
                end
            end
        end

        -- Build notification message
        local msg
        if removedPlace ~= nil and removedSilo then
            local okMsg = (g_i18n and g_i18n.getText and g_i18n:getText("gui_mapinit_notify_remove_nearest_ok"))
            msg = (okMsg and okMsg ~= "gui_mapinit_notify_remove_nearest_ok") and okMsg or "Nearest place and silo removed."
        elseif removedPlace ~= nil then
            local okMsg = (g_i18n and g_i18n.getText and g_i18n:getText("gui_mapinit_notify_remove_nearest_ok"))
            msg = (okMsg and okMsg ~= "gui_mapinit_notify_remove_nearest_ok") and okMsg or "Nearest place removed."
        else
            local noMsg = (g_i18n and g_i18n.getText and g_i18n:getText("gui_mapinit_notify_remove_nearest_none"))
            msg = (noMsg and noMsg ~= "gui_mapinit_notify_remove_nearest_none") and noMsg or "No place found to remove."
        end

        if g_currentMission and g_currentMission.addIngameNotification
            and FSBaseMission and FSBaseMission.INGAME_NOTIFICATION_OK then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
        end
        return
    end

    -- 5) Build the map-init entry and create the IAMapPlace
    if IANeighbours == nil then return end

    local placeType = mappingDef.placeType or "public_place"
    local entry = {
        x = x,
        y = y or 0,
        z = z,
        rotation = ry or 0,
        type = placeType,
        withVehicle = mapped.withVehicle == true,
        withAttachment = mapped.withAttachment == true,
        sizeType = mapped.sizeType,
        characterNumber = mappingDef.characterNumber,
    }

    -- Ensure places table exists
    if IANeighbours.places == nil then
        IANeighbours.places = {}
    end

    IANeighbours:addPlaceFromMapInitEntry(entry)

    -- Capture the newly created place (last in the array)
    local newPlace = IANeighbours.places[#IANeighbours.places]

    -- Assign character_homebase place to the corresponding neighbour (mirrors IAMapInitDialogGUI:savePlaceType lines 1474-1482)
    if placeType == "character_homebase" and mappingDef.characterNumber ~= nil then
        if IANeighbours and IANeighbours.neighbours then
            for _, n in pairs(IANeighbours.neighbours) do
                if n and not n.isDeleted and n.id == mappingDef.characterNumber and n.assignHomebasePlace then
                    n:assignHomebasePlace(newPlace)
                    break
                end
            end
        end
    end

    -- 6) Save to map config XML
    local mapId = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId
    if mapId ~= nil and IANeighbours.xmlHelper ~= nil and IANeighbours.xmlHelper.saveMapConfigToFile ~= nil then
        if IANeighbours.debug then
            print("--- saveMapConfigToFile caller: IAPlaceablePlacementDetector mapId=" .. tostring(mapId))
        end
        IANeighbours.xmlHelper:saveMapConfigToFile(mapId)
    end

    -- 7) Draw debug visualization
    local label = placeType .. " (" .. tostring(mapped.sizeType or "?") .. ")"
    IANeighbours:addPlaceDebugPointsAt(x, y or 0, z, ry or 0, label, mapped.withVehicle == true, mapped.withAttachment == true, nil, nil, newPlace, mapped.sizeType)

    -- 8) Show in-game notification
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
        and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
        local sizeLabel = tostring(mapped.sizeType or "?")
        local msg
        if g_i18n ~= nil and g_i18n.getText ~= nil then
            local tmpl = g_i18n:getText("gui_fos_place_created")
            if tmpl ~= nil and tmpl ~= "" and tmpl ~= "gui_fos_place_created" then
                -- Translate place type through i18n if a key exists
                local typeLabel = g_i18n:getText("gui_mapinit_place_type_" .. placeType)
                if typeLabel == nil or typeLabel == "" or typeLabel == ("gui_mapinit_place_type_" .. placeType) then
                    typeLabel = placeType
                end
                msg = string.format(tmpl, typeLabel, sizeLabel)
            end
        end
        if msg == nil or msg == "" then
            msg = "Place created: " .. placeType .. " (" .. sizeLabel .. ")"
        end
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
    end
end
