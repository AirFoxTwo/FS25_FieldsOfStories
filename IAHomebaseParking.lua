--
-- FS25 - InteractiveNeighbours - Homebase parking (off-situation spawn to shed/homebase slots)
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 04.04.2026
-- @Version: 1.0.0.0

IAHomebaseParking = {}
IAHomebaseParking._mt = Class(IAHomebaseParking)

function IAHomebaseParking.new(ianeighboursInstance)
	local self = setmetatable({}, IAHomebaseParking._mt)
	self.ianeighbours = ianeighboursInstance
	return self
end

-- Maximum distance (m) to search for a nearby public_place when placing "last used" vehicle on foot (roadside spline places are not used).
local NEARBY_PUBLIC_PLACE_MAX_RADIUS_M = 300

-- Place sizeTypes that are exclusive to area-based situations (opt-in via <placeSizes>) and must
-- never be used to park idle / off-situation vehicles at homebase. Mirrors IAGameLoopHelper's
-- IA_EXCLUSIVE_PLACE_SIZE_TYPES so a "large_area" homebase/shed slot is not turned into a parking bay.
-- Silo places are storage buildings, not parking bays, and must never host parked vehicles/attachments.
local PARKING_EXCLUDED_PLACE_SIZE_TYPES = {
	["large_area"] = true,
	["silo"] = true,
}

--- True when the place's sizeType is reserved for situations and must not host parked vehicles.
local function isExcludedParkingSizeType(place)
	if place == nil or place.sizeType == nil then
		return false
	end
	return PARKING_EXCLUDED_PLACE_SIZE_TYPES[string.lower(tostring(place.sizeType))] == true
end

-- Collision options for isPlaceBlocked: exclude only this vehicle's root component (so it does not block its own target slot).
local function placeCollisionOptionsForVehicle(ia, extra)
	local opts = {}
	if extra ~= nil then
		for k, v in pairs(extra) do
			opts[k] = v
		end
	end
	if ia ~= nil and ia.vehicle ~= nil and ia.vehicle.components ~= nil and ia.vehicle.components[1] ~= nil and ia.vehicle.components[1].node ~= nil then
		opts.excludeNodeIds = { ia.vehicle.components[1].node }
	end
	return opts
end

-- Find the closest place of type public_place to (refX, refZ), within max radius, not blocked.
-- @param IAHomebaseParking|table parking - instance with .ianeighbours
local function findClosestPublicPlaceForOnFootParking(parking, refX, refZ, maxRadiusM, iaExcludeFromCollision)
	if refX == nil or refZ == nil or parking.ianeighbours == nil or parking.ianeighbours.places == nil then
		return nil
	end
	local places = parking.ianeighbours.places
	local inn = parking.ianeighbours
	local maxR = maxRadiusM or NEARBY_PUBLIC_PLACE_MAX_RADIUS_M
	local maxRSq = maxR * maxR
	local publicPlaceBlockedOpts = placeCollisionOptionsForVehicle(iaExcludeFromCollision, { forPublicPlaceParkingSelection = true })

	local candidates = {}
	for _, place in ipairs(places) do
		if place ~= nil and place.x ~= nil and place.z ~= nil then
			local ptype = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			local allowsVehicle = (place.withVehicle ~= false)
			if ptype == "public_place" and allowsVehicle then
				local dx = place.x - refX
				local dz = place.z - refZ
				local dSq = dx * dx + dz * dz
				if dSq <= maxRSq then
					table.insert(candidates, { place = place, dSq = dSq })
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.dSq < b.dSq
	end)

	for _, entry in ipairs(candidates) do
		local place = entry.place
		if not inn:isPlaceBlocked(place, publicPlaceBlockedOpts) then
			return place
		end
	end
	return nil
end

local PARKING_STICKY_MAX_DIST_M = 4
local PARKING_STICKY_MAX_DIST_SQ = PARKING_STICKY_MAX_DIST_M * PARKING_STICKY_MAX_DIST_M

local function iaParkingPlaceIdsEqual(a, b)
	if a == nil or b == nil then return false end
	return tostring(a) == tostring(b)
end

--- True if another mod vehicle already claims this homebase/shed slot, excluding the vehicle being assigned.
local function isHomebasePlaceOccupiedByOtherVehicle(inn, placeId, assigningUniqueId)
	if placeId == nil or inn == nil or inn.neighbours == nil then
		return false
	end
	for _, neighbour in pairs(inn.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia in pairs(neighbour.vehicles) do
				if ia ~= nil and (assigningUniqueId == nil or ia.uniqueId ~= assigningUniqueId) then
					if IAEquipmentPresence ~= nil and IAEquipmentPresence.State.vehiclePresenceBlocksPlaceId ~= nil then
						if IAEquipmentPresence.State.vehiclePresenceBlocksPlaceId(ia, placeId, assigningUniqueId) then
							return true
						end
					elseif ia.parkingPlaceId ~= nil and ia.parkingPlaceSemantic == "homebase" and iaParkingPlaceIdsEqual(ia.parkingPlaceId, placeId) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function iaVehicleStableSortKey(ia)
	if ia == nil then return "" end
	if ia.uniqueId ~= nil then return tostring(ia.uniqueId) end
	if ia.externalId ~= nil then return tostring(ia.externalId) end
	return ""
end

local function sortIANeighbourVehicleList(list)
	table.sort(list, function(a, b)
		return iaVehicleStableSortKey(a) < iaVehicleStableSortKey(b)
	end)
end

local function findPlaceByIdInNeighbours(inn, placeId)
	if inn == nil or inn.places == nil or placeId == nil then
		return nil
	end
	for _, p in ipairs(inn.places) do
		if p ~= nil and iaParkingPlaceIdsEqual(p.id, placeId) then
			return p
		end
	end
	return nil
end

local function isHomebaseParkingStructurallyValid(neighbour, place, ia_vehicle, isAttachmentSlot)
	if ia_vehicle == nil or place == nil or neighbour == nil then
		return false
	end
	if not iaParkingPlaceIdsEqual(ia_vehicle.parkingPlaceId, place.id) then
		return false
	end
	if ia_vehicle.parkingPlaceSemantic ~= "homebase" then
		return false
	end
	local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
	if st ~= "character_homebase" and st ~= "shed" then
		return false
	end
	if isExcludedParkingSizeType(place) then
		return false
	end
	if isAttachmentSlot then
		if place.withAttachment ~= true then
			return false
		end
	else
		if place.withAttachment == true or place.withVehicle ~= true then
			return false
		end
	end
	local assigned = false
	for _, id in ipairs(neighbour.assignedHomebasePlaceIds or {}) do
		if iaParkingPlaceIdsEqual(id, place.id) then
			assigned = true
			break
		end
	end
	if not assigned then
		return false
	end
	if ia_vehicle.vehicle == nil then
		return false
	end
	return true
end

local function isStickyHomebaseValid(inn, neighbour, place, ia_vehicle, isAttachmentSlot)
	if inn == nil or not isHomebaseParkingStructurallyValid(neighbour, place, ia_vehicle, isAttachmentSlot) then
		return false
	end
	local rx = ia_vehicle.realPositionX or ia_vehicle.positionX
	local rz = ia_vehicle.realPositionZ or ia_vehicle.positionZ
	if rx == nil or rz == nil or place.x == nil or place.z == nil then
		return true
	end
	local dx, dz = rx - place.x, rz - place.z
	return (dx * dx + dz * dz) <= PARKING_STICKY_MAX_DIST_SQ
end

local function isStickyPublicValid(inn, place, ia_vehicle)
	if ia_vehicle == nil or place == nil or inn == nil then
		return false
	end
	if place.id == nil or not iaParkingPlaceIdsEqual(ia_vehicle.parkingPlaceId, place.id) then
		return false
	end
	if ia_vehicle.parkingPlaceSemantic ~= "public_place" then
		return false
	end
	local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
	if st ~= "public_place" or place.withVehicle == false then
		return false
	end
	if inn:isPlaceBlocked(place, placeCollisionOptionsForVehicle(ia_vehicle, { forPublicPlaceParkingSelection = true })) then
		return false
	end
	if ia_vehicle.vehicle == nil then
		return false
	end
	local rx = ia_vehicle.realPositionX or ia_vehicle.positionX
	local rz = ia_vehicle.realPositionZ or ia_vehicle.positionZ
	if rx == nil or rz == nil or place.x == nil or place.z == nil then
		return true
	end
	local dx, dz = rx - place.x, rz - place.z
	return (dx * dx + dz * dz) <= PARKING_STICKY_MAX_DIST_SQ
end

local function computeHomebaseBackOffsetWorldXZ(place, inn, ia_vehicle, vehicleRotationY)
	if place == nil or inn == nil or place.x == nil or place.z == nil then
		return place and place.x, place and place.z
	end
	local boxLen = IANeighbours.getPlaceDebugBoxLength(place.withVehicle == true, place.withAttachment == true, place.sizeType)
	if boxLen == nil or boxLen <= 0 then
		return place.x, place.z
	end
	local front = inn.PLACE_DEBUG_FRONT_M or 3
	local back = math.max(0, boxLen - front)
	local ry = place.rotation or 0
	local vrot = vehicleRotationY or ry
	local dYaw = vrot - ry
	while dYaw > math.pi do dYaw = dYaw - 2 * math.pi end
	while dYaw < -math.pi do dYaw = dYaw + 2 * math.pi end
	local gv = ia_vehicle and ia_vehicle.vehicle
	local L, W = 4, 2.5
	if gv and gv.size then
		if type(gv.size.length) == "number" and gv.size.length > 0 then
			L = gv.size.length
		end
		if type(gv.size.width) == "number" and gv.size.width > 0 then
			W = gv.size.width
		end
	end
	local c = math.abs(math.cos(dYaw))
	local s = math.abs(math.sin(dYaw))
	local halfDepth = 0.5 * (L * c + W * s)
	if halfDepth < 0.25 then
		halfDepth = 0.25
	end
	local zRearFlush = halfDepth - back
	local zFrontLimit = front - halfDepth
	local localZ = zRearFlush
	if zRearFlush > zFrontLimit then
		localZ = (front - back) * 0.5
	end
	local cy = place.y
	if cy == nil and g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		cy = getTerrainHeightAtWorldPos(g_terrainNode, place.x, 0, place.z)
	end
	cy = cy or 0
	local wx, _, wz = getWorldPositionFromYawLocalOffset(place.x, cy, place.z, ry, 0, 0, localZ)
	if wx == nil or wz == nil then
		return place.x, place.z
	end
	return wx, wz
end

local function iaCategoryLower(ia)
	if ia == nil or ia.category == nil then return "" end
	return string.lower(tostring(ia.category))
end

local function isHeaderAttachment(ia)
	local cat = iaCategoryLower(ia)
	if string.find(cat, "trailer") ~= nil then return false end
	-- Check for "cutter"/"header" BEFORE the broad "beet"/"potato" exclusions,
	-- so categories like "beetHarvesterCutters" are correctly recognized as headers.
	if string.find(cat, "cutter") ~= nil then return true end
	if string.find(cat, "header") ~= nil then return true end
	if string.find(cat, "beet") ~= nil then return false end
	if string.find(cat, "potato") ~= nil then return false end
	return false
end

local function findHeaderTrailerVehicle(neighbour, headerExternalId, freeForAttachmentPlaces)
	if neighbour == nil or headerExternalId == nil then return nil end
	-- Primary lookup: neighbour.vehicles (keyed by uniqueId, may be incomplete for fresh spawns)
	if neighbour.vehicles ~= nil then
		for _, vehicle in pairs(neighbour.vehicles) do
			if tostring(vehicle.externalId) == tostring(headerExternalId) then
				return vehicle
			end
		end
	end
	-- Fallback: search freeForAttachmentPlaces (the sorted list used by the pairing loop).
	-- On a fresh scenario load, vehicles may not yet have a uniqueId assigned when
	-- addVehicle() is called, so neighbour.vehicles[nil] silently fails in Lua 5.1
	-- and the trailer is absent from that table even though the IANeighbourVehicle
	-- wrapper exists in the attachment list.
	if freeForAttachmentPlaces ~= nil then
		for _, vehicle in ipairs(freeForAttachmentPlaces) do
			if tostring(vehicle.externalId) == tostring(headerExternalId) then
				return vehicle
			end
		end
	end
	return nil
end

local function isWeightAttachment(ia)
	local cat = iaCategoryLower(ia)
	return string.find(cat, "weight") ~= nil
end

--- Vehicles that must never be spawned for homebase parking (physics issues,
--- too large for homebase slots). They are only visible during situations.
local NEVER_PARK_AT_HOMEBASE_XML_PATTERNS = {
	"fd250",
	"hdht52",
}
local function isNeverParkedAtHomebaseVehicle(ia)
	if ia == nil or ia.xmlFilename == nil then
		return false
	end
	local fn = string.lower(tostring(ia.xmlFilename))
	for _, pattern in ipairs(NEVER_PARK_AT_HOMEBASE_XML_PATTERNS) do
		if string.find(fn, pattern, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function normalizeRotation(r)
	if r == nil then return 0 end
	while r > math.pi do r = r - 2 * math.pi end
	while r < -math.pi do r = r + 2 * math.pi end
	return r
end

-- Per-category yaw correction applied on top of the parking place's rotation.
-- Header/cutter implements have their cutter bar oriented across the chassis,
-- so we rotate them -90° to keep the bar inside the bay instead of overhanging
-- into neighbouring slots. Weights are modeled facing the tractor's hitch, so
-- when parked unattached they end up backwards versus the place orientation;
-- a 180° flip makes them face out of the bay like other attachments.
-- Beet harvester cutter TRAILERS (e.g. ROPA RR-XL) share the same category as
-- their cutter ("beetHarvesterCutters") but need the opposite rotation (+90° CCW)
-- because their model is oriented differently from the cutter head.
local function getHomebaseRotationForVehicle(place, ia_vehicle)
	local rot = place.rotation or 0
	IAprintDebug("IAHomebaseParking:getHomebaseRotationForVehicle", string.format("vehicle=%s category=%s baseRot=%.3f isHeader=%s", tostring(ia_vehicle.externalId or ia_vehicle.uniqueId or "?"), tostring(ia_vehicle.category or "?"), rot, tostring(isHeaderAttachment(ia_vehicle))), nil, ia_vehicle, nil)
	if isHeaderAttachment(ia_vehicle) then
		local cat = iaCategoryLower(ia_vehicle)
		local fn = ia_vehicle.xmlFilename ~= nil and string.lower(tostring(ia_vehicle.xmlFilename)) or ""
		-- Beet harvester cutter trailers share the "beetHarvesterCutters" category
		-- with the cutter head but need opposite rotation. Detect them by filename.
		if string.find(cat, "beet") ~= nil and string.find(fn, "trailer") ~= nil then
			rot = normalizeRotation(rot + math.pi * 0)  -- +0° CCW
		else
			rot = normalizeRotation(rot + math.pi * -0.5)  -- -90° (normal header/cutter)
		end
	elseif isWeightAttachment(ia_vehicle) then
		rot = normalizeRotation(rot + math.pi)
	end
	return rot
end

local function getHeaderOnTrailerHeightOffset(trailerIA)
	-- Place the header on top of its paired trailer.
	-- When the trailer's physics size height is reliable (> 0.1 m), use it as the
	-- base offset so the header sits just above the trailer top (with 1.5 m clearance
	-- to prevent visual clipping / physics overlap). Otherwise fall back to a fixed
	-- offset (~2.0 m above ground).
	local MIN_TRAILER_HEIGHT = 2
	local FALLBACK_OFFSET = 1.5
	if trailerIA and trailerIA.vehicle and trailerIA.vehicle.size then
		local h = trailerIA.vehicle.size.height
		if type(h) == "number" and h > MIN_TRAILER_HEIGHT then
			return h + 0.5
		end
	end
	return FALLBACK_OFFSET
end

--- Build a homebase parking pose for a fleet vehicle at a place (used when borrow ends / XML reload).
function IAHomebaseParking:buildPoseForVehicleAtPlace(place, ia_vehicle)
	if place == nil or ia_vehicle == nil or place.x == nil or place.z == nil then
		return nil
	end
	local rot = getHomebaseRotationForVehicle(place, ia_vehicle)
	local wx, wz = computeHomebaseBackOffsetWorldXZ(place, self.ianeighbours, ia_vehicle, rot)
	local groundY = (g_terrainNode ~= nil) and (getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz) + 0.2) or (place.y or 0)
	return { x = wx, y = groundY, z = wz, rotation = rot }
end

function IAHomebaseParking:findPlaceById(placeId)
	return findPlaceByIdInNeighbours(self.ianeighbours, placeId)
end

-- Get assigned homebase-related places for a neighbour (character_homebase and paired shed slots), split by kind (vehicle vs attachment).
function IAHomebaseParking:getAssignedHomebasePlacesForNeighbour(neighbour)
	local vehiclePlaces = {}
	local oversizePlaces = {}
	local attachmentPlaces = {}
	if neighbour == nil or neighbour.assignedHomebasePlaceIds == nil or #neighbour.assignedHomebasePlaceIds == 0 then
		return vehiclePlaces, oversizePlaces, attachmentPlaces
	end
	local places = self.ianeighbours.places
	if places == nil or #places == 0 then
		return vehiclePlaces, oversizePlaces, attachmentPlaces
	end
	local assignedSet = {}
	for _, id in ipairs(neighbour.assignedHomebasePlaceIds) do
		assignedSet[id] = true
	end
	for _, place in ipairs(places) do
		if place ~= nil and place.id ~= nil and assignedSet[place.id] then
			local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			if (st == "character_homebase" or st == "shed") and place.x ~= nil and place.z ~= nil and not isExcludedParkingSizeType(place) then
				if place.withAttachment == true then
					if place.sizeType ~= nil and string.lower(tostring(place.sizeType)) == "oversize_vehicle" then
						table.insert(oversizePlaces, place)
					else
						table.insert(attachmentPlaces, place)
					end
				elseif place.withVehicle == true then
					table.insert(vehiclePlaces, place)
				end
			end
		end
	end
	local function sortPlacesById(placesList)
		table.sort(placesList, function(a, b)
			local ida = a and a.id
			local idb = b and b.id
			if ida == idb then return false end
			if ida == nil then return false end
			if idb == nil then return true end
			local na, nb = tonumber(ida), tonumber(idb)
			if na ~= nil and nb ~= nil then return na < nb end
			return tostring(ida) < tostring(idb)
		end)
	end
	sortPlacesById(vehiclePlaces)
	sortPlacesById(oversizePlaces)
	sortPlacesById(attachmentPlaces)
	return vehiclePlaces, oversizePlaces, attachmentPlaces
end

local LOG = "IAHomebaseParking:assignDesiredHomebaseForNeighbour()"
local LOG_PAIR = "IAHomebaseParking:pairHeaderTrailer()"

--- Unique ids for vehicles that belong to the active situation (convoy); excluded from homebase slot assignment.
-- Uses scenario refs plus activeSituationId on fleet wrappers (set in IASituation:initialize before parking runs).
-- @return table string uniqueId -> true
function IAHomebaseParking.buildInSituationUniqueIdSet(neighbour, scenario)
	local inSituationIds = {}
	local situationId = scenario ~= nil and scenario.id or nil
	local function add(ia)
		if ia ~= nil and ia.uniqueId ~= nil then
			inSituationIds[tostring(ia.uniqueId)] = true
		end
	end
	if scenario ~= nil then
		add(scenario.vehicle)
		add(scenario.attachmentBack)
		add(scenario.attachmentFront)
	end
	if neighbour ~= nil and neighbour.vehicles ~= nil and situationId ~= nil then
		local sid = tostring(situationId)
		for _, ia in pairs(neighbour.vehicles) do
			if ia ~= nil and ia.activeSituationId ~= nil and tostring(ia.activeSituationId) == sid then
				add(ia)
			end
		end
	end
	return inSituationIds
end

--- Remove homebase desired state written for situation convoy (safety net after assign or stale save data).
function IAHomebaseParking:clearStaleHomebaseDesiredForSituationFleet(neighbour, scenario)
	if neighbour == nil or neighbour.vehicles == nil or IAEquipmentPresence == nil then
		return
	end
	local inSituationIds = IAHomebaseParking.buildInSituationUniqueIdSet(neighbour, scenario)
	for _, ia in pairs(neighbour.vehicles) do
		if ia ~= nil and ia.uniqueId ~= nil and inSituationIds[tostring(ia.uniqueId)] then
			IAEquipmentPresence.State.stripHomebaseDesiredForSituationMember(ia)
		end
	end
end

--- Policy only: assign homebase desired presence for off-situation vehicles (no mechanics).
function IAHomebaseParking:assignDesiredHomebaseForNeighbour(neighbour, scenario)
	if neighbour == nil or neighbour.vehicles == nil then
		return
	end
	scenario = scenario or {}
	local inSituationIds = IAHomebaseParking.buildInSituationUniqueIdSet(neighbour, scenario)
	local function isOversizeVehicleType(ia)
		if ia == nil or ia.type == nil then
			return false
		end
		local t = string.lower(tostring(ia.type))
		return t == "combine"
			or t == "greenbeanharvesters"
			or t == "peaharvesters"
			or t == "spinachharvesters"
			or t == "beetloading"
			or t == "beetharvesters"
			or t == "forageharvesters"
	end
	local freeForVehiclePlaces = {}
	local freeForOversizePlaces = {}
	local freeForAttachmentPlaces = {}
	local freeNeverParked = {}
	for _, ia_vehicle in pairs(neighbour.vehicles) do
		local uid = ia_vehicle ~= nil and ia_vehicle.uniqueId ~= nil and tostring(ia_vehicle.uniqueId) or nil
		if ia_vehicle ~= nil and (uid == nil or not inSituationIds[uid]) then
			-- Vehicles that are too large / cause physics issues are never parked
			-- at homebase; they only appear when part of an active situation.
			if isNeverParkedAtHomebaseVehicle(ia_vehicle) then
				table.insert(freeNeverParked, ia_vehicle)
			else
				local gv = ia_vehicle.vehicle
				if gv ~= nil and type(gv.getIsAIActive) == "function" and gv:getIsAIActive() then
					if type(ia_vehicle.stopAIJob) == "function" then
						pcall(function() ia_vehicle:stopAIJob() end)
					end
				end
				local vtype = (ia_vehicle.type ~= nil) and string.lower(tostring(ia_vehicle.type)) or ""
				if isOversizeVehicleType(ia_vehicle) then
					table.insert(freeForOversizePlaces, ia_vehicle)
				elseif vtype == "car" or vtype == "tractor" or vtype == "tractor large" then
					table.insert(freeForVehiclePlaces, ia_vehicle)
				else
					table.insert(freeForAttachmentPlaces, ia_vehicle)
				end
			end
		end
	end
	sortIANeighbourVehicleList(freeForVehiclePlaces)
	sortIANeighbourVehicleList(freeForOversizePlaces)
	sortIANeighbourVehicleList(freeForAttachmentPlaces)
	local placedAtPublicPlaceId = nil
	-- On-foot public_place parking (commented — see history in repo)
	--if scenario.place ~= nil and (scenario.place.withVehicle == false or scenario.place.withVehicle == nil) then
	--	...
	--			publicPlace = findClosestPublicPlaceForOnFootParking(self, refX, refZ, NEARBY_PUBLIC_PLACE_MAX_RADIUS_M, lastUsed)
	--	...
	--end
	local vehiclePlaces, oversizePlaces, attachmentPlaces = self:getAssignedHomebasePlacesForNeighbour(neighbour)
	local function skipPublicPlaceVehicle(ia)
		return ia ~= nil and ia.uniqueId ~= nil and ia.uniqueId == placedAtPublicPlaceId
	end
	local inn = self.ianeighbours
	local parkingDone = {}
	local placeStickyVehicle = {}
	local placeStickyAttachment = {}
	local reservedHomebasePlaceId = {}
	local function reserveHomebasePlace(placeId, uniqueId)
		if placeId == nil or uniqueId == nil then
			return false
		end
		local key = tostring(placeId)
		local prev = reservedHomebasePlaceId[key]
		if prev ~= nil and prev ~= uniqueId then
			return false
		end
		reservedHomebasePlaceId[key] = uniqueId
		return true
	end
	-- Reserve the situation's character place so homebase parking
	-- (header+trailer pairing, attachment pass, etc.) cannot steal it.
	-- Without this, when iaForceSituation triggers the first-ever homebase
	-- parking pass, both the situation placement and the vehicle parking
	-- can independently select the same place in a single tick.
	if scenario.place ~= nil and scenario.place.id ~= nil then
		reservedHomebasePlaceId[tostring(scenario.place.id)] = "__situation__"
	end
	-- Re-claim a previously saved homebase slot before any new assignment so a
	-- vehicle keeps the spot it was parked at last save / borrow return.
	local function tryTrustSavedHomebaseSlot(ia, wantAttachmentSlot, allowOversizePlace)
		if ia == nil or ia.uniqueId == nil or skipPublicPlaceVehicle(ia) or parkingDone[ia.uniqueId] then
			return
		end
		if ia.parkingPlaceSemantic ~= "homebase" or ia.parkingPlaceId == nil then
			if ia.borrowReturnParkingPlaceId == nil then
				return
			end
			ia.parkingPlaceId = ia.borrowReturnParkingPlaceId
			ia.parkingPlaceSemantic = ia.borrowReturnParkingPlaceSemantic or "homebase"
		end
		local p = findPlaceByIdInNeighbours(inn, ia.parkingPlaceId)
		if p == nil or not isHomebaseParkingStructurallyValid(neighbour, p, ia, wantAttachmentSlot) then
			return
		end
		if allowOversizePlace ~= true and p.sizeType ~= nil and string.lower(tostring(p.sizeType)) == "oversize_vehicle" then
			return
		end
		if not reserveHomebasePlace(p.id, ia.uniqueId) then
			return
		end
		if wantAttachmentSlot then
			placeStickyAttachment[p.id] = true
		else
			placeStickyVehicle[p.id] = true
		end
		parkingDone[ia.uniqueId] = true
		-- Borrowed units keep their existing desired presence (managed by the borrow flow).
		if ia.isBorrowedByPlayer ~= true and IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.setDesiredHomebase ~= nil then
			local pose = nil
			if type(self.buildPoseForVehicleAtPlace) == "function" then
				pcall(function()
					pose = self:buildPoseForVehicleAtPlace(p, ia)
				end)
			end
			if pose == nil then
				local y = p.y
				if y == nil and g_terrainNode ~= nil and p.x ~= nil and p.z ~= nil then
					y = getTerrainHeightAtWorldPos(g_terrainNode, p.x, 0, p.z) + 0.2
				end
				pose = { x = p.x, y = y or 0, z = p.z, rotation = p.rotation or 0 }
			end
			IAEquipmentPresence.State.setDesiredHomebase(ia, pose, p.id)
		end
	end
	for _, ia in ipairs(freeForVehiclePlaces) do
		tryTrustSavedHomebaseSlot(ia, false, false)
	end
	for _, ia in ipairs(freeForOversizePlaces) do
		tryTrustSavedHomebaseSlot(ia, true, true)
	end
	for _, ia in ipairs(freeForAttachmentPlaces) do
		tryTrustSavedHomebaseSlot(ia, true, false)
	end
	-- Sticky pass: keep a vehicle on its last slot if it is still parked within sticky distance.
	local function runStickyPass(places, candidates, isAttachmentSlot, stickyMap)
		for _, place in ipairs(places) do
			if place ~= nil and place.id ~= nil then
				for _, ia in ipairs(candidates) do
					if not skipPublicPlaceVehicle(ia)
						and (ia.uniqueId == nil or not parkingDone[ia.uniqueId])
						and isHomebaseParkingStructurallyValid(neighbour, place, ia, isAttachmentSlot)
						and isStickyHomebaseValid(inn, neighbour, place, ia, isAttachmentSlot)
						and reserveHomebasePlace(place.id, ia.uniqueId)
					then
						parkingDone[ia.uniqueId] = true
						stickyMap[place.id] = true
						break
					end
				end
			end
		end
	end
	runStickyPass(vehiclePlaces, freeForVehiclePlaces, false, placeStickyVehicle)
	runStickyPass(attachmentPlaces, freeForAttachmentPlaces, true, placeStickyAttachment)
	runStickyPass(oversizePlaces, freeForOversizePlaces, true, placeStickyAttachment)

	-- Pairing pre-pass: place header attachments on top of their designated header trailers.
	-- Headers marked with headerTrailerExternalId are paired on top of the resolved trailer
	-- at the same XZ position, using the trailer's height for the Y offset.
	local pairedTrailerUids = {}
	for _, headerIA in ipairs(freeForAttachmentPlaces) do
		IAprintDebug(LOG, string.format("PAIR_DEBUG: iterating freeForAttachmentPlaces vehicle category=%s externalId=%s uniqueId=%s isHeader=%s headerTrailerExternalId=%s", 
			tostring(headerIA.category or "?"), tostring(headerIA.externalId or "?"), tostring(headerIA.uniqueId or "?"), 
			tostring(isHeaderAttachment(headerIA)), tostring(headerIA.headerTrailerExternalId or "nil")))
		local headerUid = headerIA ~= nil and headerIA.uniqueId ~= nil and tostring(headerIA.uniqueId) or nil
			-- REDUNDANT FALLBACK: directly read headerTrailerExternalId from neighbour.vehicles
			-- headerIA comes from neighbour.iaVehicles which may not have headerTrailerExternalId set,
			-- but neighbour.vehicles (keyed by externalId or hash) should have it.
			if headerIA.headerTrailerExternalId == nil and headerIA.externalId ~= nil then
				local extIdStr = tostring(headerIA.externalId)
				IAprintDebug(LOG, string.format("PAIR_DEBUG_REDUNDANT: checking neighbour.vehicles for externalId=%s", extIdStr))
				if neighbour.vehicles ~= nil then
					for _, v in pairs(neighbour.vehicles) do
						if tostring(v.externalId) == extIdStr then
							if v.headerTrailerExternalId ~= nil then
								headerIA.headerTrailerExternalId = v.headerTrailerExternalId
								IAprintDebug(LOG, string.format("PAIR_DEBUG_REDUNDANT: COPIED headerTrailerExternalId=%s from neighbour.vehicles to iaVehicle externalId=%s", 
									tostring(v.headerTrailerExternalId), extIdStr))
							else
								IAprintDebug(LOG, string.format("PAIR_DEBUG_REDUNDANT: vehicle found in neighbour.vehicles but headerTrailerExternalId is nil, category=%s", 
									tostring(v.category or "?")))
							end
							break
						end
					end
				else
					IAprintDebug(LOG, "PAIR_DEBUG_REDUNDANT: neighbour.vehicles is nil")
				end
			end

		if headerUid ~= nil
			and isHeaderAttachment(headerIA)
			and headerIA.headerTrailerExternalId ~= nil then
			IAprintDebug(LOG, string.format("PAIR_DEBUG: ENTERED pairing gate for vehicle externalId=%s, headerTrailerExternalId=%s, headerUid=%s", tostring(headerIA.externalId or "?"), tostring(headerIA.headerTrailerExternalId or "?"), tostring(headerUid or "?")))
			local trailerIA = findHeaderTrailerVehicle(neighbour, headerIA.headerTrailerExternalId, freeForAttachmentPlaces)
			if trailerIA ~= nil then
				IAprintDebug(LOG, string.format("PAIR_DEBUG: TRAILER FOUND trailerUid=%s", tostring(trailerIA.uniqueId or "?")))
				local trailerUid = trailerIA.uniqueId ~= nil and tostring(trailerIA.uniqueId) or nil
				
				-- Handle cases where header and/or trailer were parked separately
				-- by tryTrustSavedHomebaseSlot (Phase 1) and need re-pairing:
				
				if trailerUid ~= nil then
					IAprintDebug(LOG, string.format("PAIR_DEBUG: headerUid=%s parkingDone=%s, trailerUid=%s parkingDone=%s, headerPlaceId=%s, trailerPlaceId=%s", 
						tostring(headerUid), tostring(parkingDone[headerUid]), tostring(trailerUid), tostring(parkingDone[trailerUid]),
						tostring(headerIA.parkingPlaceId or "?"), tostring(trailerIA.parkingPlaceId or "?")))
				end
				
				-- Case A: Header parked, trailer NOT parked (trailer couldn't claim shared spot)
				if parkingDone[headerUid] and trailerUid ~= nil and not parkingDone[trailerUid]
					and not inSituationIds[trailerUid]
					and not (trailerIA.isBorrowedByPlayer == true) then
					if headerIA.parkingPlaceId ~= nil then
						reservedHomebasePlaceId[tostring(headerIA.parkingPlaceId)] = nil
						placeStickyAttachment[headerIA.parkingPlaceId] = nil
					end
					headerIA.parkingPlaceId = nil
					headerIA.parkingPlaceSemantic = nil
					parkingDone[headerUid] = false
					IAprintDebug(LOG, "PAIR_DEBUG: CASE A FIRED - unparking header")
				end
				
				-- Case B: Trailer parked, header NOT parked (trailer claimed shared spot first)
				if not parkingDone[headerUid] and trailerUid ~= nil and parkingDone[trailerUid]
					and not inSituationIds[trailerUid]
					and not (trailerIA.isBorrowedByPlayer == true) then
					if trailerIA.parkingPlaceId ~= nil then
						reservedHomebasePlaceId[tostring(trailerIA.parkingPlaceId)] = nil
						placeStickyAttachment[tostring(trailerIA.parkingPlaceId)] = nil
					end
					trailerIA.parkingPlaceId = nil
					trailerIA.parkingPlaceSemantic = nil
					parkingDone[trailerUid] = false
					IAprintDebug(LOG, "PAIR_DEBUG: CASE B FIRED - unparking trailer")
				end
				
				-- Case C: Both parked but on DIFFERENT spots (separate saved slots)
				if parkingDone[headerUid] and trailerUid ~= nil and parkingDone[trailerUid]
					and headerIA.parkingPlaceId ~= trailerIA.parkingPlaceId
					and not inSituationIds[trailerUid]
					and not (trailerIA.isBorrowedByPlayer == true) then
					-- Unpark header
					if headerIA.parkingPlaceId ~= nil then
						reservedHomebasePlaceId[tostring(headerIA.parkingPlaceId)] = nil
						placeStickyAttachment[headerIA.parkingPlaceId] = nil
					end
					headerIA.parkingPlaceId = nil
					headerIA.parkingPlaceSemantic = nil
					parkingDone[headerUid] = false
					-- Unpark trailer
					if trailerIA.parkingPlaceId ~= nil then
						reservedHomebasePlaceId[tostring(trailerIA.parkingPlaceId)] = nil
						placeStickyAttachment[tostring(trailerIA.parkingPlaceId)] = nil
					end
					trailerIA.parkingPlaceId = nil
					trailerIA.parkingPlaceSemantic = nil
					parkingDone[trailerUid] = false
					IAprintDebug(LOG, "PAIR_DEBUG: CASE C FIRED - unparking BOTH")
				end
				IAprintDebug(LOG, string.format("PAIR_DEBUG: After cases - parkingDone[headerUid]=%s, parkingDone[trailerUid]=%s, headerUid exists=%s", 
					tostring(parkingDone[headerUid]), tostring(trailerUid ~= nil and tostring(parkingDone[trailerUid]) or "N/A"),
					tostring(headerUid ~= nil)))
				-- Original pairing logic (headerUid may have been unparked above)
				if not parkingDone[headerUid] then
					-- Trailer must be free, not in a situation, and not borrowed
					if trailerUid ~= nil
						and not inSituationIds[trailerUid]
						and trailerIA.isBorrowedByPlayer ~= true
						and not parkingDone[trailerUid] then
						-- Try the trailer's saved homebase slot first, then any free attachment place
						local place = nil
						IAprintDebug(LOG, "PAIR_DEBUG: ATTEMPTING to find shared place for header+trailer")
						if trailerIA.parkingPlaceSemantic == "homebase" and trailerIA.parkingPlaceId ~= nil then
							local candidate = findPlaceByIdInNeighbours(inn, trailerIA.parkingPlaceId)
							if candidate ~= nil
								and isHomebaseParkingStructurallyValid(neighbour, candidate, trailerIA, true)
								and not placeStickyAttachment[candidate.id]
								and not reservedHomebasePlaceId[tostring(candidate.id)]
								and reserveHomebasePlace(candidate.id, trailerUid) then
								place = candidate
							end
						end
						-- Fallback: find any free attachment place
						if place == nil then
							for _, p in ipairs(attachmentPlaces) do
								if p.id ~= nil
									and not placeStickyAttachment[p.id]
									and not reservedHomebasePlaceId[tostring(p.id)]
									and reserveHomebasePlace(p.id, trailerUid) then
									place = p
									break
								end
							end
						end
						if place == nil then
							IAprintDebug(LOG, "PAIR_DEBUG: NO PLACE FOUND for header+trailer pairing")
						else
							IAprintDebug(LOG, string.format("PAIR_DEBUG: PLACE FOUND id=%s for header+trailer", tostring(place.id or "?")))
						end
						if place ~= nil then
							-- Build trailer pose with normal rotation (no header rotation correction)
							local trailerPose = self:buildPoseForVehicleAtPlace(place, trailerIA)
							if trailerPose == nil then
								local trailerRot = place.rotation or 0
								local twx, twz = computeHomebaseBackOffsetWorldXZ(place, inn, trailerIA, trailerRot)
								local tgroundY = (g_terrainNode ~= nil) and (getTerrainHeightAtWorldPos(g_terrainNode, twx, 0, twz) + 0.2) or (place.y or 0)
								trailerPose = { x = twx, y = tgroundY, z = twz, rotation = trailerRot }
							end
							-- Header pose: same XZ as trailer, Y on top of trailer height, header-specific rotation.
							-- Shift the header laterally and longitudinally relative to the trailer's
							-- forward direction so it sits correctly on the trailer bed.
							local HEADER_LATERAL_OFFSET = 0      -- meters right (positive = right)
							local HEADER_LONGITUDINAL_OFFSET = 0  -- meters forward (positive = forward)
							if headerIA.xmlFilename ~= nil and string.find(string.lower(headerIA.xmlFilename), "mf8570header") ~= nil then
								HEADER_LATERAL_OFFSET = -0.2
								HEADER_LONGITUDINAL_OFFSET = -1.5
							end
							if headerIA.xmlFilename ~= nil and string.find(string.lower(headerIA.xmlFilename), "cr980_1830") ~= nil then
								HEADER_LATERAL_OFFSET = 0.5
								HEADER_LONGITUDINAL_OFFSET = -3
							end
							if headerIA.xmlFilename ~= nil and string.find(string.lower(headerIA.xmlFilename), "fd250") ~= nil then
								HEADER_LATERAL_OFFSET = -1
								HEADER_LONGITUDINAL_OFFSET = -1
							end
							local trailerRot = trailerPose.rotation or 0
							local forwardX = math.sin(trailerRot)
							local forwardZ = math.cos(trailerRot)
							local rightX = math.cos(trailerRot)
							local rightZ = -math.sin(trailerRot)
							local headerRot = getHomebaseRotationForVehicle(place, headerIA)
							local headerY = trailerPose.y + getHeaderOnTrailerHeightOffset(trailerIA)
							local headerX = trailerPose.x + rightX * HEADER_LATERAL_OFFSET + forwardX * HEADER_LONGITUDINAL_OFFSET
							local headerZ = trailerPose.z + rightZ * HEADER_LATERAL_OFFSET + forwardZ * HEADER_LONGITUDINAL_OFFSET
							local headerPose = { x = headerX, y = headerY, z = headerZ, rotation = headerRot }

							-- Set desired homebase for both
							if IAEquipmentPresence ~= nil then
								IAEquipmentPresence.State.setDesiredHomebase(trailerIA, trailerPose, place.id)
								IAEquipmentPresence.State.setDesiredHomebase(headerIA, headerPose, place.id)
							end

							-- Update position tracking
							trailerIA.positionX = trailerPose.x
							trailerIA.positionY = trailerPose.y
							trailerIA.positionZ = trailerPose.z
							trailerIA.rotation = trailerPose.rotation
							headerIA.positionX = headerPose.x
							headerIA.positionY = headerPose.y
							headerIA.positionZ = headerPose.z
							headerIA.rotation = headerPose.rotation

							-- Mark both as parked
							parkingDone[trailerUid] = true
							parkingDone[headerUid] = true
							pairedTrailerUids[trailerUid] = true
							placeStickyAttachment[place.id] = true
							IAprintDebug(LOG_PAIR, string.format("header_paired: header=%s trailer=%s onPlaceId=%s", tostring(headerIA.externalId or headerIA.uniqueId), tostring(trailerIA.externalId or trailerIA.uniqueId), tostring(place.id)), neighbour, headerIA, nil)
							IAprintDebug(LOG, string.format("PAIR_DEBUG: PAIRING COMPLETE headerPlaceId=%s trailerPlaceId=%s", 
								tostring(headerIA.parkingPlaceId or "?"), tostring(trailerIA.parkingPlaceId or "?")))
						end
					end
				end
			else
				IAprintDebug(LOG, string.format("PAIR_DEBUG: TRAILER NOT FOUND for header externalId=%s, headerTrailerExternalId=%s", tostring(headerIA.externalId or "?"), tostring(headerIA.headerTrailerExternalId or "?")))
			end
		end
end

	-- Shared: reserve slot; write desired homebase presence (Layer 1); reconcile applies mechanics.
	local function tryAssignOneHomebasePlace(place, ia_vehicle, wantAttachmentSlot, afterMoveOk)
		if ia_vehicle == nil or place.x == nil or place.z == nil then
			return false
		end
		local savedStructural = iaParkingPlaceIdsEqual(ia_vehicle.parkingPlaceId, place.id) and ia_vehicle.parkingPlaceSemantic == "homebase" and isHomebaseParkingStructurallyValid(neighbour, place, ia_vehicle, wantAttachmentSlot)
		local placeBlocked
		if savedStructural then
			placeBlocked = not reserveHomebasePlace(place.id, ia_vehicle.uniqueId)
		else
			-- Homebase/shed unused spawn: no overlapSphere — occupancy + saved parkingPlaceId + same-run reserve only.
			local hbOpts = placeCollisionOptionsForVehicle(ia_vehicle, {
				excludePresenceUniqueId = ia_vehicle.uniqueId
			})
			placeBlocked = inn:isPlaceBlockedByOccupancy(place, hbOpts)
				or isHomebasePlaceOccupiedByOtherVehicle(inn, place.id, ia_vehicle.uniqueId)
				or not reserveHomebasePlace(place.id, ia_vehicle.uniqueId)
		end
		if placeBlocked then
			return false
		end
		local pose = nil
		if type(self.buildPoseForVehicleAtPlace) == "function" then
			pcall(function()
				pose = self:buildPoseForVehicleAtPlace(place, ia_vehicle)
			end)
		end
		if pose == nil then
			local rot = getHomebaseRotationForVehicle(place, ia_vehicle)
			local wx, wz = computeHomebaseBackOffsetWorldXZ(place, inn, ia_vehicle, rot)
			local groundY = (g_terrainNode ~= nil) and (getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz) + 0.2) or (place.y or 0)
			pose = { x = wx, y = groundY, z = wz, rotation = rot }
		end
		ia_vehicle.positionX = pose.x
		ia_vehicle.positionY = pose.y
		ia_vehicle.positionZ = pose.z
		ia_vehicle.rotation = pose.rotation
		if ia_vehicle.uniqueId ~= nil then
			parkingDone[ia_vehicle.uniqueId] = true
		end
		if IAEquipmentPresence ~= nil then
			IAEquipmentPresence.State.setDesiredHomebase(ia_vehicle, pose, place.id)
		end
		if afterMoveOk ~= nil then
			pcall(function() afterMoveOk(ia_vehicle) end)
		end
		return true
	end

	local vi, oi, ai = 1, 1, 1
	for _, place in ipairs(vehiclePlaces) do
		if place.id == nil or not placeStickyVehicle[place.id] then
			while vi <= #freeForVehiclePlaces and (skipPublicPlaceVehicle(freeForVehiclePlaces[vi]) or (freeForVehiclePlaces[vi].uniqueId ~= nil and parkingDone[freeForVehiclePlaces[vi].uniqueId])) do
				vi = vi + 1
			end
			local ia_vehicle = freeForVehiclePlaces[vi]
			if ia_vehicle ~= nil then
				if tryAssignOneHomebasePlace(place, ia_vehicle, false, function(ia)
					if ia.emptyFillUnits ~= nil then
						pcall(function() ia.emptyFillUnits() end)
					end
					if ia.tryFold ~= nil then
						pcall(function() ia:tryFold("homebase") end)
					end
				end) then
					vi = vi + 1
					IAprintDebug(LOG, string.format("vehicle_assigned: type=%s placeId=%s kind=%s", tostring(ia_vehicle.typeName or "unknown"), tostring(place.id), tostring(place.sizeType or "standard")), neighbour, ia_vehicle, nil)
				end
			end
		end
	end

	for _, place in ipairs(oversizePlaces) do
		if place.id == nil or not placeStickyAttachment[place.id] then
			while oi <= #freeForOversizePlaces and (skipPublicPlaceVehicle(freeForOversizePlaces[oi]) or (freeForOversizePlaces[oi].uniqueId ~= nil and parkingDone[freeForOversizePlaces[oi].uniqueId])) do
				oi = oi + 1
			end
			local ia_vehicle = freeForOversizePlaces[oi]
			if ia_vehicle ~= nil then
				if tryAssignOneHomebasePlace(place, ia_vehicle, true, function(ia)
					if ia.emptyFillUnits ~= nil then
						pcall(function() ia.emptyFillUnits() end)
					end
					if ia.tryFold ~= nil then
						pcall(function() ia:tryFold("homebase") end)
					end
				end) then
					oi = oi + 1
					IAprintDebug(LOG, string.format("vehicle_assigned: type=%s placeId=%s kind=%s", tostring(ia_vehicle.typeName or "unknown"), tostring(place.id), tostring(place.sizeType or "standard")), neighbour, ia_vehicle, nil)
				end
			end
		end
	end

	for _, place in ipairs(attachmentPlaces) do
		if place.id == nil or not placeStickyAttachment[place.id] then
			while ai <= #freeForAttachmentPlaces and (skipPublicPlaceVehicle(freeForAttachmentPlaces[ai]) or (freeForAttachmentPlaces[ai].uniqueId ~= nil and (parkingDone[freeForAttachmentPlaces[ai].uniqueId] or pairedTrailerUids[freeForAttachmentPlaces[ai].uniqueId]))) do
				ai = ai + 1
			end
			local ia_vehicle = freeForAttachmentPlaces[ai]
			if ia_vehicle ~= nil then
				if tryAssignOneHomebasePlace(place, ia_vehicle, true, function(ia)
					if ia.emptyFillUnits ~= nil then
						pcall(function() ia.emptyFillUnits() end)
					end
					if type(ia.shouldBeUnfoldedWhenUnattached) == "function" and ia:shouldBeUnfoldedWhenUnattached() and ia.tryUnfold ~= nil then
						pcall(function() ia:tryUnfold("homebase_unusedParking") end)
					elseif ia.tryFold ~= nil then
						pcall(function() ia:tryFold("homebase") end)
					end
				end) then
					ai = ai + 1
					IAprintDebug(LOG, string.format("vehicle_assigned: type=%s placeId=%s kind=%s", tostring(ia_vehicle.typeName or "unknown"), tostring(place.id), tostring(place.sizeType or "standard")), neighbour, ia_vehicle, nil)
				end
			end
		end
	end

	local function isAlreadyParkedAndValid(ia)
		if ia == nil or inn == nil or neighbour == nil then
			return false
		end
		if ia.uniqueId ~= nil and parkingDone[ia.uniqueId] then
			return true
		end
		if ia.parkingPlaceSemantic == "homebase" and ia.parkingPlaceId ~= nil then
			local p = findPlaceByIdInNeighbours(inn, ia.parkingPlaceId)
			if p ~= nil then
				local vtype = (ia.type ~= nil) and string.lower(tostring(ia.type)) or ""
				local wantAttachmentSlot = not (vtype == "car" or vtype == "tractor" or vtype == "tractor large")
				if not isHomebaseParkingStructurallyValid(neighbour, p, ia, wantAttachmentSlot) then
					return false
				end
				local owner = reservedHomebasePlaceId[tostring(p.id)]
				if owner ~= nil and owner ~= ia.uniqueId then
					return false
				end
				return true
			end
		end
		if ia.parkingPlaceSemantic == "public_place" and ia.parkingPlaceId ~= nil then
			local p = findPlaceByIdInNeighbours(inn, ia.parkingPlaceId)
			if p ~= nil then
				return isStickyPublicValid(inn, p, ia)
			end
		end
		return false
	end

	local function hideIfUnparked(ia)
		if ia == nil then
			return
		end
		local uid = ia.uniqueId ~= nil and tostring(ia.uniqueId) or nil
		if uid ~= nil and inSituationIds[uid] then
			return
		end
		local gv = ia.vehicle
		if gv ~= nil and type(gv.getIsAIActive) == "function" and gv:getIsAIActive() then
			return
		end
		if isAlreadyParkedAndValid(ia) then
			return
		end
		local ps = ia.presenceState
		if ps ~= nil and ps.owner == "homebase" and ps.mode == "visible" and ps.pose ~= nil and ps.parkingPlaceId ~= nil then
			return
		end
		if IAEquipmentPresence ~= nil then
			IAEquipmentPresence.State.setDesiredHidden(ia)
			IAprintDebug(LOG, string.format("vehicle_hidden: type=%s reason=no_place", tostring(ia.typeName or "unknown")), neighbour, ia, nil)
		end
	end

	for _, ia in ipairs(freeForVehiclePlaces) do
		hideIfUnparked(ia)
	end
	for _, ia in ipairs(freeForOversizePlaces) do
		hideIfUnparked(ia)
	end
	for _, ia in ipairs(freeForAttachmentPlaces) do
		local uid = ia ~= nil and ia.uniqueId ~= nil and tostring(ia.uniqueId) or nil
		if uid == nil or not pairedTrailerUids[uid] then
			hideIfUnparked(ia)
		end
	end
	for _, ia in ipairs(freeNeverParked) do
		-- Force-hide: strip any stale homebase parking state from a previous
		-- session, then set desired hidden AND immediately hide the vehicle.
		-- Bypasses hideIfUnparked guards (isAlreadyParkedAndValid /
		-- presenceState) which could skip these vehicles if they were saved
		-- as homebase-visible before the exclusion.
		local uid = ia ~= nil and ia.uniqueId ~= nil and tostring(ia.uniqueId) or nil
		if uid ~= nil and not inSituationIds[uid] then
			ia.parkingPlaceId = nil
			ia.parkingPlaceSemantic = nil
			if IAEquipmentPresence ~= nil then
				IAEquipmentPresence.State.setDesiredHidden(ia)
			end
			-- Hide immediately: setting desiredHidden alone defers the actual
			-- removeFromPhysics to reconciliation, which runs too late — the
			-- DynamicMountAttacher:onUpdateTick fires first and crashes.
			if ia.vehicle ~= nil and ia.vehicleIsVisible then
				pcall(function() ia:mech_hide() end)
			end
			IAprintDebug(LOG, string.format("vehicle_hidden: type=%s reason=never_parked_at_homebase", tostring(ia.typeName or "unknown")), neighbour, ia, nil)
		end
	end

	-- Force-hide header trailers whose headers are in the active situation.
	-- Headers in the convoy leave their paired trailer behind; the trailer must
	-- not be independently parked on a different homebase slot. Without this,
	-- the normal attachment loop can assign the trailer a free slot since the
	-- header is no longer in freeForAttachmentPlaces to trigger pairing.
	if neighbour.vehicles ~= nil then
		for _, headerIA in pairs(neighbour.vehicles) do
			local headerUid = headerIA ~= nil and headerIA.uniqueId ~= nil and tostring(headerIA.uniqueId) or nil
			if headerUid ~= nil
				and inSituationIds[headerUid]
				and headerIA.headerTrailerExternalId ~= nil then
				local trailerIA = findHeaderTrailerVehicle(neighbour, headerIA.headerTrailerExternalId, freeForAttachmentPlaces)
				if trailerIA ~= nil then
					local trailerUid = trailerIA.uniqueId ~= nil and tostring(trailerIA.uniqueId) or nil
					if trailerUid ~= nil and not inSituationIds[trailerUid] then
						-- Strip parking fields so tryTrustSavedHomebaseSlot won't
						-- reclaim the old paired slot on the next parking pass.
						trailerIA.parkingPlaceId = nil
						trailerIA.parkingPlaceSemantic = nil
						if IAEquipmentPresence ~= nil then
							IAEquipmentPresence.State.setDesiredHidden(trailerIA)
						end
						IAprintDebug(LOG, string.format("vehicle_hidden: type=%s reason=header_in_situation", tostring(trailerIA.typeName or "unknown")), neighbour, trailerIA, nil)
					end
				end
			end
		end
	end

	local function countParked(list)
		local total, parked = 0, 0
		for _, ia in ipairs(list) do
			if ia ~= nil then
				total = total + 1
				if ia.uniqueId ~= nil and parkingDone[ia.uniqueId] then
					parked = parked + 1
				end
			end
		end
		return parked, total
	end
	local pv, tv = countParked(freeForVehiclePlaces)
	local po, to = countParked(freeForOversizePlaces)
	local pa, ta = countParked(freeForAttachmentPlaces)
	IAprintDebug(LOG, string.format("parked vehicles=%d/%d oversize=%d/%d attachments=%d/%d", pv, tv, po, to, pa, ta), neighbour, nil, nil)
end

-- ---------------------------------------------------------------------------
-- Borrow homebase swap: when the player borrows an implement that is not visible
-- at homebase, take the homebase parking place from a sibling that IS spawned there
-- so the borrow flow has a real return / pickup pose to anchor onto.
-- ---------------------------------------------------------------------------

--- Slot kind classifier matching assignDesiredHomebaseForNeighbour buckets.
-- @return boolean wantAttachmentSlot, boolean wantOversize
local function classifyIASlotKind(ia)
	if ia == nil or ia.type == nil then
		return true, false
	end
	local t = string.lower(tostring(ia.type))
	if t == "combine"
		or t == "greenbeanharvesters"
		or t == "peaharvesters"
		or t == "spinachharvesters"
		or t == "beetloading"
		or t == "beetharvesters"
		or t == "forageharvesters"
	then
		return true, true
	end
	if t == "car" or t == "tractor" or t == "tractor large" then
		return false, false
	end
	return true, false
end

--- True if `place` is a homebase/shed slot that ia could be parked at structurally.
local function placeHostsIAVehicle(place, ia)
	if place == nil or ia == nil or place.x == nil or place.z == nil then
		return false
	end
	local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
	if st ~= "character_homebase" and st ~= "shed" then
		return false
	end
	if isExcludedParkingSizeType(place) then
		return false
	end
	local wantAttachment, wantOversize = classifyIASlotKind(ia)
	local placeOversize = (place.sizeType ~= nil and string.lower(tostring(place.sizeType)) == "oversize_vehicle")
	if wantAttachment then
		if place.withAttachment ~= true then
			return false
		end
		if wantOversize ~= placeOversize then
			return false
		end
	else
		if place.withVehicle ~= true or place.withAttachment == true then
			return false
		end
	end
	return true
end

--- True if ia is currently visible at a homebase slot (parked, not borrowed, not in situation, not attached).
function IAHomebaseParking:isIAVisibleAtHomebase(ia)
	if ia == nil or ia.vehicle == nil then
		return false
	end
	if ia.isBorrowedByPlayer == true or ia.activeSituationId ~= nil then
		return false
	end
	local s = ia.presenceState
	if s == nil or s.owner ~= "homebase" or s.mode ~= "visible" then
		return false
	end
	if ia.parkingPlaceId == nil or ia.parkingPlaceSemantic ~= "homebase" then
		return false
	end
	local gv = ia.vehicle
	if gv ~= nil and type(gv.getAttacherVehicle) == "function" then
		local ok, att = pcall(gv.getAttacherVehicle, gv)
		if ok and att ~= nil then
			return false
		end
	end
	return true
end

--- Find a sibling fleet vehicle currently visible at homebase whose place ia could occupy.
-- Excludes any uid in `excludeUidSet` (typically: all borrow units + already claimed siblings).
-- @param IANeighbour neighbour
-- @param IANeighbourVehicle ia
-- @param table|nil excludeUidSet  uniqueId -> true
-- @return IANeighbourVehicle|nil sibling, table|nil place
function IAHomebaseParking:findSpawnedSwapCandidate(neighbour, ia, excludeUidSet)
	if neighbour == nil or neighbour.vehicles == nil or ia == nil then
		return nil, nil
	end
	excludeUidSet = excludeUidSet or {}
	local iaUid = ia.uniqueId ~= nil and tostring(ia.uniqueId) or nil
	local sorted = {}
	for _, other in pairs(neighbour.vehicles) do
		if other ~= nil then
			local oUid = other.uniqueId ~= nil and tostring(other.uniqueId) or nil
			local skip = (oUid ~= nil and (oUid == iaUid or excludeUidSet[oUid] == true))
			if not skip then
				table.insert(sorted, other)
			end
		end
	end
	sortIANeighbourVehicleList(sorted)
	for _, other in ipairs(sorted) do
		if self:isIAVisibleAtHomebase(other) then
			local place = self:findPlaceById(other.parkingPlaceId)
			if place ~= nil and placeHostsIAVehicle(place, ia) then
				return other, place
			end
		end
	end
	return nil, nil
end

--- Plan: can every unit in `units` end up at homebase (already there, or via a swap)?
-- Walks units once, claiming a unique sibling per non-home unit (so two non-home
-- units cannot share the same swap candidate).
-- @return boolean
function IAHomebaseParking:canSatisfyAllBorrowUnitsViaHomebaseOrSwap(neighbour, units)
	if neighbour == nil or units == nil or #units == 0 then
		return false
	end
	local borrowUidSet = {}
	for _, ia in ipairs(units) do
		if ia == nil then
			return false
		end
		if ia.uniqueId ~= nil then
			borrowUidSet[tostring(ia.uniqueId)] = true
		end
	end
	local claimed = {}
	for _, ia in ipairs(units) do
		if self:isIAVisibleAtHomebase(ia) then
			-- already at home, no swap needed
		else
			local exclude = {}
			for k, v in pairs(borrowUidSet) do exclude[k] = v end
			for k, v in pairs(claimed) do exclude[k] = v end
			local sibling = self:findSpawnedSwapCandidate(neighbour, ia, exclude)
			if sibling == nil then
				return false
			end
			if sibling.uniqueId ~= nil then
				claimed[tostring(sibling.uniqueId)] = true
			end
		end
	end
	return true
end

--- Hide a spawned sibling and assign its homebase place to ia (so borrow flow has a real return pose).
-- No-op when ia is already visible at homebase. Returns false when no compatible sibling is available.
-- @param IANeighbour neighbour
-- @param IANeighbourVehicle ia
-- @param table|nil excludeUidSet  uniqueId -> true (e.g. other borrow units)
-- @return boolean true when ia ends up visible at homebase (already, or after swap)
function IAHomebaseParking:swapHomebasePlaceWithSpawnedSiblingForBorrow(neighbour, ia, excludeUidSet)
	if ia == nil or neighbour == nil then
		return false
	end
	-- Restore guard: a unit that is already borrowed has its real return slot stored in borrowReturnParkingPlaceId. isIAVisibleAtHomebase always returns false for borrowed units, so without this short-circuit the function would proceed to steal a random sibling's place and overwrite ia.parkingPlaceId / presenceState.parkingPlaceId. That desyncs getReservedParkingPlaceId from borrowReturnParkingPlaceId and breaks the map hotspot, the return debug box, and isNearReturnPose after every savegame reload.
	if ia.isBorrowedByPlayer == true and ia.borrowReturnParkingPlaceId ~= nil then
		IAprintDebug(
			"IAHomebaseParking:swapHomebasePlaceWithSpawnedSiblingForBorrow()",
			"skip: already borrowed with borrowReturnParkingPlaceId=" .. tostring(ia.borrowReturnParkingPlaceId) .. " (restore path)",
			neighbour, ia, nil
		)
		return true
	end
	if self:isIAVisibleAtHomebase(ia) then
		return true
	end
	if IAEquipmentPresence == nil or IAEquipmentPresence.State == nil then
		return false
	end
	local sibling, place = self:findSpawnedSwapCandidate(neighbour, ia, excludeUidSet)
	if sibling == nil or place == nil then
		return false
	end

	local pose = nil
	pcall(function()
		pose = self:buildPoseForVehicleAtPlace(place, ia)
	end)
	if pose == nil then
		local y = place.y
		if y == nil and g_terrainNode ~= nil and place.x ~= nil and place.z ~= nil then
			y = getTerrainHeightAtWorldPos(g_terrainNode, place.x, 0, place.z) + 0.2
		end
		pose = { x = place.x, y = y or 0, z = place.z, rotation = place.rotation or 0 }
	end

	local siblingPrevParkingPlaceId = sibling.parkingPlaceId
	sibling.parkingPlaceId = nil
	sibling.parkingPlaceSemantic = nil
	IAEquipmentPresence.State.setDesiredHidden(sibling)

	ia.parkingPlaceId = place.id
	ia.parkingPlaceSemantic = "homebase"
	IAEquipmentPresence.State.setDesiredHomebase(ia, pose, place.id)

	if IAEquipmentPresence.Reconcile ~= nil and IAEquipmentPresence.Reconcile.reconcileVehicle ~= nil then
		pcall(function() IAEquipmentPresence.Reconcile.reconcileVehicle(sibling) end)
		pcall(function() IAEquipmentPresence.Reconcile.reconcileVehicle(ia) end)
	end

	IAprintDebug(
		"IAHomebaseParking:swapHomebasePlaceWithSpawnedSiblingForBorrow()",
		"sibling uid=" .. tostring(sibling.uniqueId) .. " vacated place id=" .. tostring(siblingPrevParkingPlaceId or place.id) .. " for borrow target uid=" .. tostring(ia.uniqueId),
		neighbour, ia, nil
	)
	return true
end

--- Assign homebase desired state then reconcile fleet (Layer 2 applies mechanics).
function IAHomebaseParking:spawnNonSituationVehiclesToHomebase(neighbour, scenario)
	self:assignDesiredHomebaseForNeighbour(neighbour, scenario)
	self:clearStaleHomebaseDesiredForSituationFleet(neighbour, scenario)
	if IAEquipmentPresence ~= nil and IAEquipmentPresence.Reconcile ~= nil then
		IAEquipmentPresence.Reconcile.reconcileNeighbourFleet(neighbour, {
			scenario = scenario,
			computeHomebaseDesired = false
		})
	end
end
