--
-- Fields of Stories — general-purpose animated map hotspot for mission target positions.
-- Subclasses MapHotspot and uses base-game overlay atlases (default: "mapHotspots.circle",
-- the same animated red circle as vanilla field mission markers).
--

IATargetMapHotspot = {}
local IATargetMapHotspot_mt = Class(IATargetMapHotspot, MapHotspot)

--- Default mission-red color (same as vanilla field mission circles).
IATargetMapHotspot.DEFAULT_COLOR = {0.5089, 0.016, 0.016, 1}

--- Default overlay atlas slice id (engine pre-registered "mapHotspots" atlas).
IATargetMapHotspot.DEFAULT_OVERLAY_ID = "mapHotspots.circle"

--- Create a new target map hotspot.
--- @param worldX   number   World X position
--- @param worldZ   number   World Z position
--- @param radius   number|nil  World-space radius in meters (default 50)
--- @param overlayId string|nil Overlay atlas slice id (default "mapHotspots.circle")
--- @param color    table|nil   {r, g, b, a} (default mission red)
--- @return table|nil new MapHotspot instance, or nil if engine overlay is unavailable
function IATargetMapHotspot.new(worldX, worldZ, radius, overlayId, color)
    if MapHotspot == nil or g_overlayManager == nil or g_currentMission == nil then
        return nil
    end
    if worldX == nil or worldZ == nil then
        return nil
    end

    local self = MapHotspot.new(IATargetMapHotspot_mt)
    local w, h = getNormalizedScreenValues(50, 50)
    self.width = w
    self.height = h

    local sliceId = overlayId or IATargetMapHotspot.DEFAULT_OVERLAY_ID
    self.circle = g_overlayManager:createOverlay(sliceId, 0, 0, w, h)
    if self.circle == nil then
        if self.delete ~= nil then
            pcall(function() self:delete() end)
        end
        return nil
    end

    local col = color or IATargetMapHotspot.DEFAULT_COLOR
    self.circle:setColor(unpack(col))
    self.worldRadius = radius or 50
    self.forceNoRotation = true
    self:setWorldPosition(worldX, worldZ)
    return self
end

function IATargetMapHotspot:delete()
    IATargetMapHotspot:superClass().delete(self)
    if self.circle ~= nil then
        self.circle:delete()
        self.circle = nil
    end
end

--- Auto-scale the circle radius based on current map zoom level.
--- Called by the engine each frame while visible on the map.
function IATargetMapHotspot:postUpdate(dt)
    if g_currentMission == nil or g_currentMission.hud == nil then
        return
    end
    local ingameMap = g_currentMission.hud:getIngameMap()
    if ingameMap == nil or ingameMap.layout == nil then
        return
    end
    local mapW, mapH = ingameMap.layout:getMapSize()
    local w = self.worldRadius / ingameMap.worldSizeX * mapW
    local h = self.worldRadius / ingameMap.worldSizeZ * mapH
    if self.circle ~= nil then
        self.circle:setDimension(w, h)
    end
end

function IATargetMapHotspot:getWidth()
    return self.circle == nil and 0 or self.circle.width
end

function IATargetMapHotspot:getHeight()
    return self.circle == nil and 0 or self.circle.height
end

function IATargetMapHotspot:getDimension()
    if self.circle == nil then
        return 0, 0
    else
        return self.circle.width, self.circle.height
    end
end

function IATargetMapHotspot:setScale(scale) end

function IATargetMapHotspot:getCategory()
    return MapHotspot.CATEGORY_MISSION
end

function IATargetMapHotspot:getIsPersistent()
    return false
end

function IATargetMapHotspot:getRenderLast()
    return false
end

function IATargetMapHotspot:render(x, y, rotation, small)
    local circle = self.circle
    if circle ~= nil then
        circle:setPosition(x, y)
        circle:setColor(nil, nil, nil, IngameMap.alpha)
        circle:render()
    end
end
