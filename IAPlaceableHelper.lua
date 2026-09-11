-- IAPlaceableHelper.lua — Wraps the game's PlaceableLoadingData:load() API for spawning temporary silos.
-- Shared placeable utilities: spawning, removal, farm-place resolution (used by both the delivery
-- mission system and the static farmer placeable system).

IAPlaceableHelper = IAPlaceableHelper or {}

-- Temporary silo storage mapping for tracking spawned placeables
IAPlaceableHelper._spawnedPlaceables = IAPlaceableHelper._spawnedPlaceables or {}

--------------------------------------------------------------------------------
-- Farm place resolution (shared by delivery missions and static farmer placeables)
--------------------------------------------------------------------------------

--- Find a 'large_area' farm place for the given neighbour.
--- Delegates to IANeighbour:getLargeAreaPlace() which searches assignedHomebasePlaceIds.
--- @param neighbour table IANeighbour instance
--- @return table|nil place
function IAPlaceableHelper.findLargeAreaFarmPlace(neighbour)
    if neighbour == nil or type(neighbour.getLargeAreaPlace) ~= "function" then
        return nil
    end
    return neighbour:getLargeAreaPlace()
end

--- Compute the world position of the right-back corner of a large_area place.
--- Local offset (side, 0, -back) rotated by the place's yaw; terrain height sampled.
--- @param place table place with x, y, z, rotation fields
--- @return number|nil wx, number|nil wy, number|nil wz
function IAPlaceableHelper.computeRightBackCorner(place)
    if place == nil then return nil, nil, nil end
    if IANeighbours == nil then return nil, nil, nil end

    local boxLength = IANeighbours.getPlaceDebugBoxLength and IANeighbours.getPlaceDebugBoxLength(place.withVehicle, place.withAttachment, place.sizeType)
    local side      = IANeighbours.getPlaceDebugBoxSide     and IANeighbours.getPlaceDebugBoxSide(place.withVehicle, place.withAttachment, place.sizeType)

    if boxLength == nil or boxLength <= 0 or side == nil then
        return place.x or 0, (place.y or 0) + 1.0, place.z or 0
    end

    local front = IANeighbours.PLACE_DEBUG_FRONT_M or 3
    local back  = math.max(0, boxLength - front)
    local rot   = place.rotation or 0

    if getWorldPositionFromYawLocalOffset == nil then
        return place.x or 0, (place.y or 0) + 1.0, place.z or 0
    end

    -- +X = right (1m margin from border), -Z = back
    local rightOffset = math.max(0, side - 1)
    local wx, _, wz = getWorldPositionFromYawLocalOffset(place.x or 0, place.y or 0, place.z or 0, rot, rightOffset, 0, -back)
    if wx == nil or wz == nil then
        return place.x or 0, (place.y or 0) + 1.0, place.z or 0
    end

    local wy = (place.y or 0) + 1.0
    if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        local ty = getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz)
        if ty ~= nil then
            wy = ty + 1.0
        end
    end

    return wx, wy, wz
end

--------------------------------------------------------------------------------
-- Store item resolution
--------------------------------------------------------------------------------

--- Try g_storeManager lookup with a single path, returning the storeItem if found.
-- @param xmlFilename string Path to try
-- @return table|nil storeItem
local function _tryStoreLookup(xmlFilename)
    if g_storeManager ~= nil and type(g_storeManager.getItemByXMLFilename) == "function" then
        local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)
        if storeItem ~= nil then
            return storeItem
        end
    end
    return nil
end

--- Resolve a store item by xmlFilename. Tries g_storeManager first, then falls back
-- to resolving the path against the current mod directory (IANeighbours.dir / g_currentModDirectory).
-- g_storeManager may store items under either absolute or relative paths, so we try both.
-- @param xmlFilename string Path to the store item XML (relative or absolute)
-- @param rotationY number|nil Default rotation for the synthetic store item fallback
-- @return table|nil storeItem, string|nil resolvedRelativePath
function IAPlaceableHelper.resolveStoreItem(xmlFilename, rotationY)
    -- 1) Try the path exactly as provided
    local storeItem = _tryStoreLookup(xmlFilename)
    if storeItem ~= nil then
        return storeItem, xmlFilename
    end

    -- 2) Fallback: resolve against the current mod directory
    local modDir = (IANeighbours ~= nil and IANeighbours.dir) or g_currentModDirectory
    if modDir == nil then
        return nil, nil
    end

    -- Normalize path separators
    local normalizedPath = xmlFilename:gsub("\\", "/")
    local normalizedModDir = modDir:gsub("\\", "/")

    -- Ensure modDir ends with "/" for prefix matching
    if not normalizedModDir:match("/$") then
        normalizedModDir = normalizedModDir .. "/"
    end

    -- Determine relative and absolute forms
    local relativePath
    local absolutePath
    if normalizedPath:sub(1, normalizedModDir:len()) == normalizedModDir then
        -- Input is absolute and inside the mod directory
        relativePath = normalizedPath:sub(normalizedModDir:len() + 1)
        absolutePath = normalizedPath
    else
        -- Input is relative (or absolute but not inside mod dir)
        relativePath = normalizedPath
        absolutePath = normalizedModDir .. normalizedPath
    end

    -- Try the alternate form with g_storeManager
    if relativePath ~= normalizedPath then
        storeItem = _tryStoreLookup(relativePath)
        if storeItem ~= nil then
            return storeItem, relativePath
        end
    end
    if absolutePath ~= normalizedPath then
        storeItem = _tryStoreLookup(absolutePath)
        if storeItem ~= nil then
            return storeItem, relativePath
        end
    end

    -- 3) Build a synthetic storeItem for the relative path.
    -- PlaceableLoadingData:setStoreItem only reads .xmlFilename and .rotation from the storeItem,
    -- so this is sufficient to load unregistered placeable XMLs from the mod directory.
    local syntheticStoreItem = {
        xmlFilename = relativePath,
        rotation = rotationY or 0,
    }

    return syntheticStoreItem, relativePath
end

--- Spawn a placeable at the given position.
--- @param xmlFilename string Path to the store item XML (e.g. "data/placeables/mapUS/storage/storage.xml"), a relative path within the mod directory (e.g. "placeables/farma400modified/farma400modified.xml"), or an absolute path
--- @param x number World X position
--- @param y number World Y position  
--- @param z number World Z position
--- @param rotationY number Rotation around Y axis in radians
--- @param farmId number Farm ID to assign ownership
--- @param callback function(placeable, errorMsg, args) Async callback on completion
--- @param args table|nil Extra args passed to callback
function IAPlaceableHelper.spawnPlaceable(xmlFilename, x, y, z, rotationY, farmId, callback, args)
    if callback == nil then
        callback = function() end
    end

    -- Validate inputs
    if xmlFilename == nil or type(xmlFilename) ~= "string" then
        callback(nil, "No xmlFilename provided", args)
        return
    end

    -- Resolve the store item (with mod-directory fallback)
    local storeItem, resolvedPath = IAPlaceableHelper.resolveStoreItem(xmlFilename, rotationY)
    if storeItem == nil then
        callback(nil, "Store item not found: " .. xmlFilename, args)
        return
    end

    -- Create a proper PlaceableLoadingData instance (follows PlaceableSystem:loadPlaceableFromXML pattern)
    if PlaceableLoadingData == nil or type(PlaceableLoadingData.new) ~= "function" then
        callback(nil, "PlaceableLoadingData.new not available", args)
        return
    end

    local data = PlaceableLoadingData.new()
    data:setStoreItem(storeItem)
    data:setPosition(x, y, z)
    data:setRotation(0, rotationY or 0, 0)
    data:setOwnerFarmId(farmId or 1)
    data:setIsSaved(false)

    -- Load the placeable. When inside an async task (e.g. called from a mission),
    -- queue as a subtask. When called from a console command or synchronous context,
    -- call load() directly — addSubtask will drop the callback otherwise.
    local function doLoad()
        data:load(function(_callbackTarget, placeable, loadingState, _args)
            if placeable ~= nil then
                -- finalizePlacement activates collisions, triggers, actions etc.
                if type(placeable.finalizePlacement) == "function" then
                    placeable:finalizePlacement()
                end
                table.insert(IAPlaceableHelper._spawnedPlaceables, placeable)
                callback(placeable, nil, args)
            else
                callback(nil, string.format("Placeable load failed for '%s' (loadingState=%s)", resolvedPath, tostring(loadingState)), args)
            end
        end, nil, args)
    end

    if g_asyncTaskManager ~= nil and type(g_asyncTaskManager.getIsInsideTask) == "function" and g_asyncTaskManager:getIsInsideTask() then
        g_asyncTaskManager:addSubtask(doLoad)
    else
        doLoad()
    end
end

--- Remove a previously spawned placeable from the world.
--- @param placeable table The placeable object to remove
function IAPlaceableHelper.removePlaceable(placeable)
    if placeable == nil then return end
    
    -- Remove from tracking table
    for i = #IAPlaceableHelper._spawnedPlaceables, 1, -1 do
        if IAPlaceableHelper._spawnedPlaceables[i] == placeable then
            table.remove(IAPlaceableHelper._spawnedPlaceables, i)
            break
        end
    end
    
    -- Try to delete the placeable
    if type(placeable.delete) == "function" then
        placeable:delete()
    elseif type(placeable.remove) == "function" then
        placeable:remove()
    elseif type(placeable.destroy) == "function" then
        placeable:destroy()
    end
    
    -- Also try removing from placeable system if it has a removePlaceable method
    if g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil 
        and type(g_currentMission.placeableSystem.removePlaceable) == "function" then
        g_currentMission.placeableSystem:removePlaceable(placeable)
    end
end

--- Get the total fill level of all fill units on a placeable.
--- @param placeable table The placeable object
--- @return number Total fill level in liters
function IAPlaceableHelper.getPlaceableFillLevel(placeable)
    if placeable == nil then return 0 end
    
    -- FS25 silos: use unloadingStation to sum fill across all supported fill types
    if placeable.spec_silo ~= nil and placeable.spec_silo.unloadingStation ~= nil then
        local us = placeable.spec_silo.unloadingStation
        local total = 0
        if type(us.getSupportedFillTypes) == "function" then
            local supported = us:getSupportedFillTypes()
            if supported ~= nil then
                for fillTypeIndex, _ in pairs(supported) do
                    if type(us.getFillLevel) == "function" then
                        local ok, fl = pcall(us.getFillLevel, us, fillTypeIndex, 1)
                        if ok and type(fl) == "number" then
                            total = total + fl
                        end
                    end
                end
            end
        end
        return total
    end
    
    local total = 0
    
    -- Try getFillLevel if available (some placeables have this directly)
    if type(placeable.getFillLevel) == "function" then
        total = total + placeable:getFillLevel()
    end
    
    -- Try fillUnits table
    if placeable.fillUnits ~= nil then
        for _, unit in ipairs(placeable.fillUnits) do
            if unit ~= nil then
                if type(unit.getFillLevel) == "function" then
                    total = total + unit:getFillLevel()
                elseif unit.fillLevel ~= nil then
                    total = total + unit.fillLevel
                end
            end
        end
    end
    
    -- Try getFillUnits
    if type(placeable.getFillUnits) == "function" then
        local units = placeable:getFillUnits()
        if units ~= nil then
            for _, unit in ipairs(units) do
                if unit ~= nil then
                    if type(unit.getFillLevel) == "function" then
                        total = total + unit:getFillLevel()
                    elseif unit.fillLevel ~= nil then
                        total = total + unit.fillLevel
                    end
                end
            end
        end
    end
    
    -- Try spec_xxx.fillLevel (common FS25 pattern)
    if placeable.spec_fillUnit ~= nil then
        for _, spec in pairs(placeable.spec_fillUnit) do
            if type(spec) == "table" and spec.fillLevel ~= nil then
                total = total + spec.fillLevel
            end
        end
    end
    
    return total
end

--- Get fill level for a specific fill type from a silo placeable.
--- @param placeable table The placeable object
--- @param fillTypeIndex number FillType index
--- @param farmId number Farm ID (default 1 = player)
--- @return number Fill level in liters for that fill type
function IAPlaceableHelper.getPlaceableFillLevelForFillType(placeable, fillTypeIndex, farmId)
    if placeable == nil or fillTypeIndex == nil then return 0 end
    farmId = farmId or 1
    if placeable.spec_silo ~= nil and placeable.spec_silo.unloadingStation ~= nil then
        local us = placeable.spec_silo.unloadingStation
        if type(us.getFillLevel) == "function" then
            local ok, fl = pcall(us.getFillLevel, us, fillTypeIndex, farmId)
            if ok and type(fl) == "number" then
                return fl
            end
        end
    end
    return 0
end

return IAPlaceableHelper
