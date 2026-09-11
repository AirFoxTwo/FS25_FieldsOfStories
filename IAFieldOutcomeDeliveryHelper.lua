-- IAFieldOutcomeDeliveryHelper.lua — Handles spawning a delivery placeable at a character's homebase.
-- Target architecture: at load time, the homebase large_area is detected and a placeable is spawned
-- at the right-back corner of that area (XML defined externally).
-- Farm-place resolution delegates to IAPlaceableHelper (shared with static farmer placeable system).

IAFieldOutcomeDeliveryHelper = IAFieldOutcomeDeliveryHelper or {}

-- Configuration
IAFieldOutcomeDeliveryHelper.DELIVERY_SILO_XML = "data/placeables/mapUS/farmSilo/farmSilo.xml"  -- Silo store item path (TODO: replace with final XML)

--------------------------------------------------------------------------------
-- Farm place lookup — delegates to IAPlaceableHelper
--------------------------------------------------------------------------------

--- Spawn a placeable at the large area farm place of a character/neighbour.
-- The placeable is spawned at the right-back corner of the large_area.
-- This is a standalone function, testable in isolation, no mission object needed.
-- @param character neighbour object from IANeighbours.neighbours
-- @param xmlFilename optional store item XML path (defaults to DELIVERY_SILO_XML)
-- @param callback function(placeable, errorMsg) async result callback
function IAFieldOutcomeDeliveryHelper.spawnSiloAtCharacterLargeArea(character, xmlFilename, callback)
    if callback == nil then callback = function() end end
    
    -- Validate IAPlaceableHelper
    if IAPlaceableHelper == nil or type(IAPlaceableHelper.spawnPlaceable) ~= "function" then
        print("[IAFieldOutcomeDeliveryHelper] IAPlaceableHelper.spawnPlaceable not available")
        callback(nil, "IAPlaceableHelper.spawnPlaceable not available")
        return
    end
    
    -- Validate character
    if character == nil then
        print("[IAFieldOutcomeDeliveryHelper] No character provided")
        callback(nil, "No character provided")
        return
    end
    
    -- Resolve XML path (default to farm silo)
    local xml = xmlFilename or IAFieldOutcomeDeliveryHelper.DELIVERY_SILO_XML or "data/placeables/mapUS/farmSilo/farmSilo.xml"
    
    -- Find the character's large area farm place
    local place = IAPlaceableHelper.findLargeAreaFarmPlace(character)
    if place == nil then
        print("[IAFieldOutcomeDeliveryHelper] No large_area farm place found for character " .. tostring(character.name or character.id))
        callback(nil, "No large_area farm place found")
        return
    end
    
    -- Compute right-back corner position
    local fx, fy, fz = IAPlaceableHelper.computeRightBackCorner(place)
    local rotationY = place.rotation or 0
    
    -- Resolve farm ID
    local farmId = 1
    if g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" then
        farmId = g_currentMission:getFarmId()
    end
    
    print(string.format("[IAFieldOutcomeDeliveryHelper] Spawning '%s' at character '%s' large area right-back corner (%.1f, %.1f, %.1f) farmId=%d",
        xml, tostring(character.name or character.id), fx, fy, fz, farmId))
    
    -- Spawn the placeable
    IAPlaceableHelper.spawnPlaceable(xml, fx, fy, fz, rotationY, farmId,
        function(placeable, errorMsg, args)
            if placeable ~= nil then
                print(string.format("[IAFieldOutcomeDeliveryHelper] Placeable spawned successfully at character '%s' large area right-back corner (%.1f, %.1f, %.1f)",
                    tostring(character.name or character.id), fx, fy, fz))
                callback(placeable, nil)
            else
                print("[IAFieldOutcomeDeliveryHelper] Failed to spawn placeable: " .. tostring(errorMsg))
                callback(nil, errorMsg)
            end
        end
    )
end

return IAFieldOutcomeDeliveryHelper
