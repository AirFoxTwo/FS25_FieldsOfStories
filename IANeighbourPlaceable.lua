-- IANeighbourPlaceable.lua — Wrapper for placeables owned by a neighbour (farmer).
-- Tracks uniqueId, externalId, xmlFilename, position, rotation, and the live placeable object.
-- Follows the same save/load pattern as IANeighbourVehicle for outbound XML persistence.

IANeighbourPlaceable = {}
local IANeighbourPlaceable_mt = Class(IANeighbourPlaceable)

--- Create a new placeable wrapper instance.
--- @param uniqueId string|nil Game engine placeable uniqueId (nil for not-yet-spawned)
--- @param externalId string Stable identifier for outbound XML mapping
--- @param farmId number Farm ID (99 = NPC farm)
--- @param neighbour table Parent IANeighbour instance
--- @return table IANeighbourPlaceable
function IANeighbourPlaceable.new(uniqueId, externalId, farmId, neighbour)
    local self = setmetatable({}, IANeighbourPlaceable_mt)

    self.uniqueId = uniqueId
    self.externalId = externalId
    self.farmId = farmId or 99
    self.neighbour = neighbour

    self.xmlFilename = nil          -- Store item XML path (e.g. "placeables/farma400modified/farma400modified.xml")
    self.positionX = nil
    self.positionY = nil
    self.positionZ = nil
    self.rotation = nil

    self.placeable = nil           -- The actual game placeable object (set after spawn/load)

    return self
end

--- Spawn the placeable using IAPlaceableHelper.
--- @param callback function(placeable, errorMsg) Called on completion
function IANeighbourPlaceable:spawn(callback)
    if callback == nil then callback = function() end end

    if self.xmlFilename == nil then
        callback(nil, "No xmlFilename set")
        return
    end

    -- Auto-resolve position from large_area farm place if no explicit position set
    if self.positionX == nil and self.neighbour ~= nil and IAPlaceableHelper ~= nil then
        local largePlace = IAPlaceableHelper.findLargeAreaFarmPlace(self.neighbour)
        if largePlace ~= nil then
            local cornerX, cornerY, cornerZ = IAPlaceableHelper.computeRightBackCorner(largePlace)
            if cornerX ~= nil and cornerZ ~= nil then
                self.positionX = cornerX
                self.positionY = cornerY
                self.positionZ = cornerZ
                self.rotation = largePlace.rotation
                local neighbourName = self.neighbour.name or "?"
                IAprintDebug("IANeighbourPlaceable", string.format("Resolved position for '%s' → place id=%s type=%s sizeType=%s characterNumber=%s at (%.1f, %.1f, %.1f)",
                    neighbourName, tostring(largePlace.id), tostring(largePlace.type), tostring(largePlace.sizeType), tostring(largePlace.characterNumber), cornerX, cornerY, cornerZ))
            end
        else
            local neighbourName = self.neighbour.name or "?"
            IAprintDebug("IANeighbourPlaceable", string.format("No farm place found for '%s' (id=%s, homebaseIds=%s)",
                neighbourName, tostring(self.neighbour.id), tostring(self.neighbour.assignedHomebasePlaceIds ~= nil and table.concat(self.neighbour.assignedHomebasePlaceIds, ",") or "none")))
        end
    end

    -- Require a valid position — never spawn at world origin (0,0,0)
    if self.positionX == nil then
        local neighbourName = self.neighbour ~= nil and self.neighbour.name or "?"
        IAprintDebug("IANeighbourPlaceable", string.format("Cannot spawn '%s' for %s: no position resolved (no large_area, no homebase, no explicit position in FARMER_PLACEABLES)", tostring(self.xmlFilename), neighbourName))
        callback(nil, "No position resolved — no large_area, no homebase, no explicit position")
        return
    end

    local x = self.positionX
    local y = nil  -- let PlaceableLoadingData:setPosition auto-sample terrain height
    local z = self.positionZ or 0
    local ry = self.rotation or 0
    local farmId = self.farmId or 99  -- NPC farm; access granted via IABorrowAccess during missions

    IAPlaceableHelper.spawnPlaceable(self.xmlFilename, x, y, z, ry, farmId,
        function(placeable, errorMsg, _args)
            if placeable ~= nil then
                self.placeable = placeable
                self.uniqueId = placeable.uniqueId
                -- Register the mapping so outbound XML can restore it
                if IANeighbours ~= nil and IANeighbours.setPlaceableIdMapping ~= nil and self.externalId ~= nil and self.uniqueId ~= nil then
                    IANeighbours:setPlaceableIdMapping(self.externalId, self.uniqueId)
                end
                if self.neighbour ~= nil then
                    self.neighbour:addPlaceable(self)
                end
                callback(placeable, nil)
            else
                callback(nil, errorMsg)
            end
        end
    )
end

--- Attach to an existing game placeable by uniqueId (restore from save).
--- @param uniqueId string Game engine placeable uniqueId
--- @return boolean true if found and attached
function IANeighbourPlaceable:loadPlaceableById(uniqueId)
    if uniqueId == nil then return false end

    if g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil then
        local ps = g_currentMission.placeableSystem
        if ps.placableByUniqueId ~= nil then
            local p = ps.placableByUniqueId[tostring(uniqueId)]
            if p ~= nil then
                self.placeable = p
                self.uniqueId = uniqueId
                if self.neighbour ~= nil then
                    self.neighbour:addPlaceable(self)
                end
                return true
            end
        end
    end

    return false
end

--- Delete the placeable from the game world.
function IANeighbourPlaceable:delete()
    if self.placeable ~= nil then
        IAPlaceableHelper.removePlaceable(self.placeable)
        self.placeable = nil
    end
    self.uniqueId = nil
end

return IANeighbourPlaceable
