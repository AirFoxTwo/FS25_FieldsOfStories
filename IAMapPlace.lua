--
-- FS25 - InteractiveNeighbours - Map Place Class
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 22.01.2026
-- @Version: 1.0.0.0
--
-- Places can be absolute (world x,y,z) or placeable-relative (stored in placeablePlaces.xml;
-- resolved to world position per map using placeable position + offset).
--

IAMapPlace = {}
IAMapPlace._mt = Class(IAMapPlace)

-- Create a new Map Place instance.
-- @param number id - Place ID
-- @param string name - Name of the place
-- @param string type - Type of place (e.g., "shop")
-- @param number x - X position (world, or 0 until resolved for placeable-relative)
-- @param number y - Y position
-- @param number z - Z position
-- @param number rotation - Rotation in radians (world, or 0 until resolved)
-- @param boolean withVehicle - Whether place allows vehicles
-- @param boolean withAttachment - Whether place allows vehicles with attachment (implies larger box when debugging)
-- @param string sizeType - Optional place size type: "character", "vehicle", "vehicle_attachment", "oversize_vehicle", "large_area".
-- @param number characterNumber - Optional; neighbour id for type "character_homebase" (place.characterNumber in XML)
-- @param string placeableFilename - Optional; if set, place is relative to this placeable (config filename)
-- @param number offsetX, offsetY, offsetZ - Optional; world offset from placeable root to spawn
-- @param number relRotation - Optional; spawn yaw relative to placeable yaw (radians)
function IAMapPlace.new(id, name, type, x, y, z, rotation, withVehicle, withAttachment, sizeType, characterNumber, placeableFilename, offsetX, offsetY, offsetZ, relRotation)
	local self = setmetatable({}, IAMapPlace._mt)

	self.id = id or nil
	self.name = name or "Unknown"
	self.type = type or "unknown"
	-- Semantic type for persistence and logic when runtime type is overridden (e.g. player_farm on owned farmland)
	self.basePlaceType = self.type
	self.x = x or 0
	self.y = y or 0
	self.z = z or 0
	self.rotation = rotation or 0

	-- Place size encoding:
	-- - Legacy: withVehicle/withAttachment booleans (3 tiers)
	-- - New: sizeType string (5 tiers; oversize_vehicle is bigger than vehicle_attachment, large_area is wider+longer for area-based situations)
	-- sizeType is persisted but we keep booleans for backward compatibility and for situation selection rules.
	local st = (sizeType ~= nil) and string.lower(tostring(sizeType)) or nil
	if st == "large_area" then
		self.sizeType = "large_area"
		self.withVehicle = true
		self.withAttachment = true
	elseif st == "oversize_vehicle" then
		self.sizeType = "oversize_vehicle"
		self.withVehicle = true
		self.withAttachment = true
	elseif st == "vehicle_attachment" then
		self.sizeType = "vehicle_attachment"
		self.withVehicle = true
		self.withAttachment = true
	elseif st == "vehicle" then
		self.sizeType = "vehicle"
		self.withVehicle = true
		self.withAttachment = false
	elseif st == "character" then
		self.sizeType = "character"
		self.withVehicle = false
		self.withAttachment = false
	elseif st == "silo" then
		self.sizeType = "silo"
		self.withVehicle = true
		self.withAttachment = true
	else
		self.withVehicle = withVehicle or false
		self.withAttachment = (withAttachment == true)
		if self.withAttachment == true then
			self.sizeType = "vehicle_attachment"
		elseif self.withVehicle == true then
			self.sizeType = "vehicle"
		else
			self.sizeType = "character"
		end
	end
	self.characterNumber = characterNumber

	-- Placeable-relative: spawn is defined as placeable position + offset; map-agnostic
	self.placeableFilename = placeableFilename or nil
	self.offsetX = (offsetX ~= nil) and offsetX or nil
	self.offsetY = (offsetY ~= nil) and offsetY or nil
	self.offsetZ = (offsetZ ~= nil) and offsetZ or nil
	self.relRotation = (relRotation ~= nil) and relRotation or nil

	-- Map-node place: offset/relRotation relative to named node (stored in placeablePlaces.xml)
	self.nodeName = nil
	-- Unique node identity when nodeName is ambiguous (e.g. multiple "vehicleShop" with different i3d)
	self.referenceId = nil    -- from i3d ReferenceNode referenceId
	self.referenceFilename = nil  -- from i3d Files section (the i3d path behind the reference)
	-- Runtime node id when resolved from map node (used to exclude this node and children from blocking detection)
	self.resolvedMapNodeId = nil
	-- Map I3D reference id string (from getAllMapNodesWithTransform entry.id); persisted in map config to re-match runtime node after save/load
	self.mapRefNodeId = nil
	-- Stable map I3D node ids to exclude from place collision checks (persisted); resolved lazily to engine node ids
	self.collisionExcludeRefIds = nil
	-- Runtime engine node ids for collision exclude (filled by IANeighbours:ensurePlaceCollisionExcludeRuntimeNodes)
	self.collisionExcludeRuntimeNodeIds = nil

	-- When true (from placeablePlaces.xml <ignoreCollision>): skip physics collision blocking for this place
	self.ignoreCollision = false

	-- Optional: character job title this place serves (placeablePlaces / map config #job or .job); used with type character_job
	self.job = nil

	-- Optional: free-form notes (e.g. auto-generated selling-station metadata); persisted in map config .description
	self.description = nil

	return self
end

--- Original/authored place type (shop, shed, …); use when place.type may be runtime-only (e.g. player_farm).
function IAMapPlace:getSemanticType()
	return self.basePlaceType or self.type
end

--- Whether this place is defined relative to a placeable (stored in placeablePlaces.xml).
function IAMapPlace:isPlaceableRelative()
	return self.placeableFilename ~= nil and self.placeableFilename ~= ""
end

--- Whether this place is defined relative to a map node (offsetX/Y/Z and relRotation in node local space).
function IAMapPlace:isNodeRelative()
	if self.nodeName == nil or self.nodeName == "" then
		return false
	end
	return (self.offsetX ~= nil or self.offsetY ~= nil or self.offsetZ ~= nil or self.relRotation ~= nil)
end

--- Resolve placeable-relative place to world position using the given placeable.
-- Sets self.x, self.y, self.z, self.rotation. No-op if not placeable-relative or placeable is nil.
-- Offsets are interpreted in placeable-local space.
-- @param table placeable - Placeable with rootNode (getWorldPositionFromNodeLocalOffset)
-- @return boolean - true if resolution was applied
function IAMapPlace:resolveFromPlaceable(placeable)
	if not self:isPlaceableRelative() or placeable == nil or placeable.rootNode == nil then
		return false
	end
	-- Convert stored local offsets to world direction, then add to placeable world position.
	-- This keeps relative places correct on rotated placeable instances.
	local ox = self.offsetX or 0
	local oy = self.offsetY or 0
	local oz = self.offsetZ or 0
	local wx, wy, wz = getWorldPositionFromNodeLocalOffset(placeable.rootNode, ox, oy, oz)
	if wx == nil or wz == nil then
		return false
	end
	self.x, self.y, self.z = wx, wy or 0, wz
	local placeableYaw = getNodeYawFromForward(placeable.rootNode, 0)
	self.rotation = normalizeYawPi((placeableYaw or 0) + (self.relRotation or 0))
	return true
end

--- Resolve node-relative place using a runtime node (getWorldPositionFromNodeLocalOffset). Prefer this when nodeId is available.
-- Sets self.x, self.y, self.z, self.rotation. No-op if not node-relative.
-- @param number nodeId - Runtime scene node id (e.g. from getMapRootNode + collectRuntimeMapNodes + findRuntimeNodeForXmlEntry)
-- @return boolean - true if resolution was applied
function IAMapPlace:resolveFromMapNodeWithRuntimeNode(nodeId)
	if not self:isNodeRelative() or nodeId == nil or not entityExists(nodeId) then
		return false
	end
	local ox = self.offsetX or 0
	local oy = self.offsetY or 0
	local oz = self.offsetZ or 0
	local wx, wy, wz = getWorldPositionFromNodeLocalOffset(nodeId, ox, oy, oz)
	if wx == nil or wz == nil then
		return false
	end
	self.x, self.y, self.z = wx, wy or 0, wz
	-- Node yaw from forward direction (same as IAMapInitDialogGUI / avoids getWorldRotation Euler clamp)
	local forwardX, _, forwardZ = localDirectionToWorld(nodeId, 0, 0, 1)
	local nodeYaw = (MathUtil and MathUtil.getYRotationFromDirection and MathUtil.getYRotationFromDirection(forwardX or 0, forwardZ or 0)) or (forwardX and forwardZ and math.atan2(forwardX, forwardZ)) or 0
	self.rotation = (nodeYaw or 0) + (self.relRotation or 0)
	while self.rotation > math.pi do self.rotation = self.rotation - 2 * math.pi end
	while self.rotation < -math.pi do self.rotation = self.rotation + 2 * math.pi end

	self.resolvedMapNodeId = nodeId
	if IANeighbours and IANeighbours.debug then
		print(string.format("--- IAMapPlace:resolveFromMapNodeWithRuntimeNode() [DEBUG] name=%s nodeName=%s localOffset=(%.3f,%.3f,%.3f) worldPos=(%.3f,%.3f,%.3f)",
			tostring(self.name), tostring(self.nodeName), ox, oy, oz, self.x, self.y, self.z))
	end
	return true
end

--- Resolve node-relative place to world position using node position and yaw (fallback when no runtime node).
-- Offset is in node local space; uses getWorldPositionFromYawLocalOffset (same frame as map-init corner debug).
-- @param number nx, ny, nz - Node world position
-- @param number nodeYaw - Node world yaw in radians (rotation around Y)
-- @return boolean - true if resolution was applied
function IAMapPlace:resolveFromMapNode(nx, ny, nz, nodeYaw)
	if not self:isNodeRelative() or nx == nil or nz == nil then
		return false
	end
	self.resolvedMapNodeId = nil  -- no runtime node in this path
	ny = ny or 0
	nodeYaw = nodeYaw or 0
	local ox = self.offsetX or 0
	local oy = self.offsetY or 0
	local oz = self.offsetZ or 0
	local wx, wy, wz = getWorldPositionFromYawLocalOffset(nx, ny, nz, nodeYaw, ox, oy, oz)
	if wx == nil or wz == nil then
		return false
	end
	self.x, self.y, self.z = wx, wy or 0, wz
	self.rotation = nodeYaw + (self.relRotation or 0)
	while self.rotation > math.pi do self.rotation = self.rotation - 2 * math.pi end
	while self.rotation < -math.pi do self.rotation = self.rotation + 2 * math.pi end

	if IANeighbours and IANeighbours.debug then
		local yawDeg = math.deg(nodeYaw)
		print(string.format("--- IAMapPlace:resolveFromMapNode() [DEBUG] name=%s nodeName=%s nodePos=(%.3f,%.3f,%.3f) nodeYaw=%.2f deg localOffset=(%.3f,%.3f,%.3f) worldPos=(%.3f,%.3f,%.3f)",
			tostring(self.name), tostring(self.nodeName), nx, ny, nz, yawDeg, ox, oy, oz, self.x, self.y, self.z))
	end
	return true
end

--- Whether this place has a valid world position (for spawning / distance checks).
function IAMapPlace:hasWorldPosition()
	return self.x ~= nil and self.z ~= nil
end

--- Ground reference Y: place.y or terrain height at (x,z). Used as the “surface” for collision probes.
function IAMapPlace:getCollisionSurfaceWorldY()
	if not self:hasWorldPosition() then
		return 0
	end
	local yVal = self.y
	if yVal == nil and g_terrainNode ~= nil then
		yVal = getTerrainHeightAtWorldPos(g_terrainNode, self.x, 0, self.z)
	end
	return yVal or 0
end

--- Terrain (or place fallback) at arbitrary world XZ — for rear attach collision probes along the slot.
function IAMapPlace:getCollisionSurfaceWorldYAt(worldX, worldZ)
	if worldX ~= nil and worldZ ~= nil and g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		local ty = getTerrainHeightAtWorldPos(g_terrainNode, worldX, 0, worldZ)
		if ty ~= nil then
			return ty
		end
	end
	return self:getCollisionSurfaceWorldY()
end

--- World Y at the center of the map-init debug wireframe sphere (surface + PLACE_COLLISION_DEBUG_SPHERE_RADIUS_M).
function IAMapPlace:getCollisionDebugSphereCenterWorldY()
	if IANeighbours == nil then
		return self:getCollisionSurfaceWorldY()
	end
	local r = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_M or 2.5
	if self.withVehicle == false and self.withAttachment ~= true then
		r = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_CHARACTER_ONLY_M or 0.25
	end
	return self:getCollisionSurfaceWorldY() + r
end

--- Debug sphere center Y at an offset probe position (terrain-based surface + debug radius).
function IAMapPlace:getCollisionDebugSphereCenterWorldYAt(worldX, worldZ)
	if IANeighbours == nil then
		return self:getCollisionSurfaceWorldYAt(worldX, worldZ)
	end
	local r = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_M or 2.5
	if self.withVehicle == false and self.withAttachment ~= true then
		r = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_CHARACTER_ONLY_M or 0.25
	end
	return self:getCollisionSurfaceWorldYAt(worldX, worldZ) + r
end

--- Only central API for place physics collision (overlapSphere + filters). Situation selection, IANeighbours:isPlaceBlockedByCollision, and map-init debug all go through this.
-- With withAttachment: also probes two points along local −Z (rear of the long-slot debug box). overlapSphere center is surface Y + overlap radius per probe.
-- Merges options.excludeNodeIds with collisionExcludeRuntimeNodeIds.
-- sell_point places additionally ignore node names containing exactFillRootNode / exactFillRootNodeManure / exactFillRootNodeLiquidManure / unloadNodeTrailer (unload trigger) in overlap results.
-- @param table|nil optionsOrNil optional — excludeNodeIds, forPublicPlaceParkingSelection (wider radius for public_place+vehicle), collisionRadiusM (overrides default/parking when > 0)
-- @param number|nil excludeNodeIdLegacy optional — if first arg is not a table, first arg is treated as collisionRadiusM and this as excludeNodeIds (legacy call shape)
-- @return boolean blocked, table blockingInfos, table blockingNodeIds — callers that only need blocked use select(1, place:isBlockedByCollision(opts))
function IAMapPlace:isBlockedByCollision(optionsOrRadiusM, excludeNodeIdLegacy)
	if self.ignoreCollision == true then
		return false, {}, {}
	end
	if not self:hasWorldPosition() or IANeighbours == nil or getPositionBlockedByCollision == nil then
		return false, {}, {}
	end

	-- NEW: Skip physics collision for character_homebase on-foot places
    -- (spawn points intentionally placed inside buildings / interiors).
    -- Occupancy checks (isPlaceBlockedByOccupancy) still prevent two
    -- characters from sharing the same place.
    local sem = (self.getSemanticType ~= nil and self:getSemanticType()) or self.type
    if sem ~= nil and string.lower(tostring(sem)) == "character_homebase" and self.withVehicle ~= true then
        return false, {}, {}
    end

	local options
	if type(optionsOrRadiusM) == "table" then
		options = optionsOrRadiusM
	else
		options = {}
		if optionsOrRadiusM ~= nil and type(optionsOrRadiusM) == "number" and optionsOrRadiusM > 0 then
			options.collisionRadiusM = optionsOrRadiusM
		end
		if excludeNodeIdLegacy ~= nil then
			options.excludeNodeIds = excludeNodeIdLegacy
		end
	end

	local publicPlaceParkingSelect = options ~= nil and options.forPublicPlaceParkingSelection == true
	local sem = (self.getSemanticType ~= nil and self:getSemanticType()) or self.type
	local ptype = string.lower(tostring(sem or ""))
	local allowsVehicle = (self.withVehicle ~= false)
	local isPublicPlaceParkingCandidate = (ptype == "public_place") and allowsVehicle
	-- sell_point: unload trigger collision nodes should not block the place probe
	local collisionExtraExcludeNames = nil
	if ptype == "sell_point" then
		collisionExtraExcludeNames = { "exactfillrootnode", "exactfillrootnodemanure", "exactfillrootnodeliquidmanure", "unloadnodetrailer" }
	end

	local surfaceY = self:getCollisionSurfaceWorldY()
	IANeighbours:ensurePlaceCollisionExcludeRuntimeNodes(self)
	local excludeNodeIds = IANeighbours:mergeCollisionExcludeNodeIds((options and options.excludeNodeIds) or nil, self.collisionExcludeRuntimeNodeIds)

	local collisionRadius = nil
	local optR = options and options.collisionRadiusM
	if optR ~= nil and optR > 0 then
		collisionRadius = optR
	elseif publicPlaceParkingSelect and isPublicPlaceParkingCandidate then
		collisionRadius = IANeighbours.ROADSIDE_PARKING_OCCUPANCY_RADIUS_M
	elseif self.withVehicle == false and self.withAttachment ~= true then
		collisionRadius = IANeighbours.PLACE_COLLISION_CHECK_RADIUS_CHARACTER_ONLY
	end

	local overlapR = (collisionRadius ~= nil and collisionRadius > 0) and collisionRadius or IANeighbours.PLACE_COLLISION_CHECK_RADIUS
	local probeY = surfaceY + overlapR

	local blocked, blockingInfos, blockingNodeIds = getPositionBlockedByCollision(IANeighbours, self.x, probeY, self.z, collisionRadius, excludeNodeIds, collisionExtraExcludeNames)

	-- Vehicle+attachment slots: two extra probes toward local −Z (rear of debug box) so long rigs are not cleared when only the cab area is free.
	if self.withAttachment == true then
		local centerY = (self.y ~= nil) and self.y or surfaceY
		local probes = IANeighbours.getAttachBackProbeWorldPositions(self.x, centerY, self.z, self.rotation or 0, self.withVehicle, self.withAttachment)
		for _, p in ipairs(probes) do
			local wx, wz = p[1], p[2]
			if wx ~= nil and wz ~= nil then
				local surfR = self:getCollisionSurfaceWorldYAt(wx, wz)
				local py = surfR + overlapR
				local b2, inf2, id2 = getPositionBlockedByCollision(IANeighbours, wx, py, wz, collisionRadius, excludeNodeIds, collisionExtraExcludeNames)
				blocked, blockingInfos, blockingNodeIds = IANeighbours.mergeBlockingCollisionResults(blocked, blockingInfos, blockingNodeIds, b2, inf2, id2)
			end
		end
	end

	if blocked and IANeighbours and IANeighbours.debug and blockingInfos and #blockingInfos > 0 then
		print(string.format("--- IAMapPlace:isBlockedByCollision() place=\"%s\" type=%s id=%s pos=(%.2f, %.2f, %.2f) -> blocking: %s",
			tostring(self.name), tostring(self.type), tostring(self.id), self.x, self.y or 0, self.z, table.concat(blockingInfos, " ; ")))
	end
	return blocked, blockingInfos, blockingNodeIds
end
