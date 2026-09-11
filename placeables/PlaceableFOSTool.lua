-- PlaceableFOSTool
-- Minimal specialization that bypasses farmland ownership checks for
-- Fields of Stories tool placeables (place_character_public_place, etc.).
-- Allows placement anywhere on the map regardless of land ownership.

PlaceableFOSTool = {}
PlaceableFOSTool.MOD_NAME = g_currentModName or "FS25_Fields_of_Stories"

function PlaceableFOSTool.prerequisitesPresent(specializations)
    return true
end

function PlaceableFOSTool.registerFunctions(placeableType)
end

function PlaceableFOSTool.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "getIsOnOwnedFarmland",
        PlaceableFOSTool.getIsOnOwnedFarmland)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "getIsOnFarmland",
        PlaceableFOSTool.getIsOnFarmland)
end

function PlaceableFOSTool.registerEventListeners(placeableType)
end

--- Always claim the placeable is on owned farmland — bypasses the "you don't own this land" check.
function PlaceableFOSTool:getIsOnOwnedFarmland(superFunc, x, y, z, rotY)
    return true
end

--- Never claim the placeable is on farmland — prevents automatic farmland purchase.
function PlaceableFOSTool:getIsOnFarmland(superFunc, farmlandId)
    return false
end
