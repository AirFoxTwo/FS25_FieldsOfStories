--
-- Fields of Stories — single-player borrow access (drive / attach without changing ownerFarmId).
--

IABorrowAccess = {}

IABorrowAccess.MOD_NAME = g_currentModName
IABorrowAccess.SPEC_NAME = string.format("%s.borrowAccess", IABorrowAccess.MOD_NAME)
IABorrowAccess.SPEC_TABLE_NAME = string.format("spec_%s", IABorrowAccess.SPEC_NAME)

--- NPC / neighbour fleet farm id (see XMLHelper default for neighbours).
IABorrowAccess.NPC_FARM_ID = 99

--- Pickup / return yard map markers (`mapicon_borrow.dds`), ref-counted per parking place.
IABorrowAccess._yardHotspots = IABorrowAccess._yardHotspots or {}
IABorrowAccess._yardPlaceRefCount = IABorrowAccess._yardPlaceRefCount or {}
IABorrowAccess._iaYardPlaceKey = IABorrowAccess._iaYardPlaceKey or {}

--- Performance: O(1) set of borrowed vehicle uniqueIds. hasPlayerBorrowAccess does
--- a single table lookup instead of iterating all neighbours × vehicles via
--- getIAForVehicle. Built from scratch after XML load and on unborrow;
--- incrementally updated on borrow.
IABorrowAccess._borrowedUniqueIds = {}

function IABorrowAccess.markBorrowed(ia)
	if ia ~= nil and ia.uniqueId ~= nil then
		IABorrowAccess._borrowedUniqueIds[tostring(ia.uniqueId)] = true
	end
end

--- Full rebuild from fleet state. Called after XML load and at end of unborrow.
--- O(neighbours × vehicles) but runs rarely (load + unborrow transitions only).
function IABorrowAccess.rebuildBorrowedIdSet()
	IABorrowAccess._borrowedUniqueIds = {}
	if IANeighbours == nil or IANeighbours.neighbours == nil then return end
	for _, n in pairs(IANeighbours.neighbours) do
		if n ~= nil and n.vehicles ~= nil then
			for _, ia in pairs(n.vehicles) do
				if ia ~= nil and ia.isBorrowedByPlayer == true and ia.uniqueId ~= nil then
					IABorrowAccess._borrowedUniqueIds[tostring(ia.uniqueId)] = true
				end
			end
		end
	end
end

local function getRootVehicle(vehicle)
	if vehicle == nil then
		return nil
	end
	return vehicle.rootVehicle or vehicle
end

function IABorrowAccess.isBorrowSystemActive()
	if g_currentMission == nil then
		return false
	end
	if IANeighbours ~= nil and IANeighbours.BlockMod == true then
		return false
	end
	local info = g_currentMission.missionDynamicInfo
	if info ~= nil and info.isMultiplayer == true then
		return false
	end
	return true
end

function IABorrowAccess.getPlayerFarmId()
	if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
		return g_localPlayer.farmId
	end
	if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
		return g_currentMission:getFarmId()
	end
	return 1
end

function IABorrowAccess.getOwnerFarmId(vehicle)
	if vehicle == nil then
		return nil
	end
	if vehicle.getOwnerFarmId ~= nil then
		return vehicle:getOwnerFarmId()
	end
	return vehicle.ownerFarmId
end

--- Resolve fleet IA by this game object's uniqueId (not attacher root — attached implements have their own uid).
function IABorrowAccess.getIAForVehicle(vehicle)
	if vehicle == nil or IANeighbours == nil or IANeighbours.getIANeighbourVehicleByUniqueId == nil then
		return nil, nil
	end
	if vehicle.uniqueId ~= nil then
		local ia, neighbour = IANeighbours:getIANeighbourVehicleByUniqueId(vehicle.uniqueId)
		if ia ~= nil then
			return ia, neighbour
		end
	end
	local root = getRootVehicle(vehicle)
	if root ~= nil and root ~= vehicle and root.uniqueId ~= nil then
		return IANeighbours:getIANeighbourVehicleByUniqueId(root.uniqueId)
	end
	return nil, nil
end

function IABorrowAccess.isFleetNpcVehicle(vehicle)
	local owner = IABorrowAccess.getOwnerFarmId(vehicle)
	return owner ~= nil and owner == IABorrowAccess.NPC_FARM_ID
end

--- True when this game vehicle (or its fleet wrapper) is marked borrowed-by-player.
-- Uses O(1) uniqueId set lookup — no iteration over neighbours/vehicles.
-- Empty set (nothing borrowed): next() returns nil instantly.
function IABorrowAccess.hasPlayerBorrowAccess(vehicle)
	if not IABorrowAccess.isBorrowSystemActive() or vehicle == nil then return false end
	if next(IABorrowAccess._borrowedUniqueIds) == nil then return false end
	if vehicle.uniqueId == nil then return false end
	return IABorrowAccess._borrowedUniqueIds[tostring(vehicle.uniqueId)] == true
end

function IABorrowAccess.shouldAllowCrossFarmAttach(attachable, farmId, attacherVehicle)
	if not IABorrowAccess.isBorrowSystemActive() then
		return false
	end
	local playerFarm = IABorrowAccess.getPlayerFarmId()
	if playerFarm == nil or farmId ~= playerFarm then
		return false
	end
	if IABorrowAccess.hasPlayerBorrowAccess(attachable) then
		return true
	end
	if attacherVehicle ~= nil and IABorrowAccess.hasPlayerBorrowAccess(attacherVehicle) then
		return true
	end
	return false
end

--- AttacherJoints.updateActionEvents uses accessHandler:canFarmAccess for attach HUD (showAttachNotAllowedText), not isAttachAllowed.
function IABorrowAccess.shouldAllowFarmAccessForBorrowed(farmId, object)
	if not IABorrowAccess.isBorrowSystemActive() or object == nil then
		return false
	end
	local playerFarm = IABorrowAccess.getPlayerFarmId()
	if playerFarm == nil or farmId ~= playerFarm then
		return false
	end
	if Vehicle ~= nil and object.isa ~= nil and object:isa(Vehicle) then
		return IABorrowAccess.hasPlayerBorrowAccess(object)
	end
	return false
end

function IABorrowAccess.isBorrowProtected(vehicle)
	if vehicle == nil then
		return false
	end
	if IABorrowAccess.hasPlayerBorrowAccess(vehicle) then
		return true
	end
	if IABorrowAccess.isFleetNpcVehicle(vehicle) then
		local ia = IABorrowAccess.getIAForVehicle(vehicle)
		if ia ~= nil then
			return true
		end
	end
	return false
end

--- Resolve game vehicle by uniqueId substring, "entered", or "nearest".
function IABorrowAccess.resolveGameVehicle(token)
	if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
		return nil, "no mission / vehicle system"
	end
	local vehicles = g_currentMission.vehicleSystem.vehicles
	if vehicles == nil then
		return nil, "no vehicles"
	end

	local t = token
	if t == nil or t == "" then
		t = "entered"
	end
	t = string.lower(tostring(t))

	if t == "entered" or t == "current" then
		if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
			return nil, "not in a vehicle"
		end
		local v = g_localPlayer:getCurrentVehicle()
		if v == nil then
			return nil, "not in a vehicle"
		end
		return getRootVehicle(v), nil
	end

	if t == "nearest" then
		if g_localPlayer == nil then
			return nil, "no local player"
		end
		local px, _, pz = g_localPlayer:getPosition()
		local best, bestDist = nil, math.huge
		for _, v in pairs(vehicles) do
			if v ~= nil and not v.isDeleted and IABorrowAccess.isFleetNpcVehicle(v) then
				local vx, _, vz = getWorldTranslation(v.rootNode or v.components[1].node)
				local dx, dz = vx - px, vz - pz
				local d = dx * dx + dz * dz
				if d < bestDist then
					bestDist = d
					best = getRootVehicle(v)
				end
			end
		end
		if best == nil then
			return nil, "no NPC fleet vehicle nearby"
		end
		return best, nil
	end

	local matches = {}
	for _, v in pairs(vehicles) do
		if v ~= nil and not v.isDeleted and v.uniqueId ~= nil then
			local uid = tostring(v.uniqueId)
			if uid == t or string.find(uid, t, 1, true) ~= nil then
				table.insert(matches, getRootVehicle(v))
			end
		end
	end
	if #matches == 0 then
		return nil, "no vehicle with uniqueId matching '" .. tostring(token) .. "'"
	end
	if #matches > 1 then
		return nil, string.format("%d vehicles match uniqueId '%s' (be more specific)", #matches, tostring(token))
	end
	return matches[1], nil
end

--- Fleet implements currently mounted on this IA game vehicle (collect before detach).
function IABorrowAccess.forEachAttachedFleetIA(parentIa, callback)
	if parentIa == nil or callback == nil or parentIa.vehicle == nil then
		return
	end
	if type(parentIa.vehicle.getAttachedImplements) ~= "function" then
		return
	end
	local ok, attached = pcall(function()
		return parentIa.vehicle:getAttachedImplements()
	end)
	if not ok or attached == nil then
		return
	end
	for _, entry in pairs(attached) do
		local obj = entry
		if type(entry) == "table" and entry.object ~= nil then
			obj = entry.object
		end
		local childIa = IABorrowAccess.getIAForVehicle(obj)
		if childIa ~= nil then
			callback(childIa, obj)
		end
	end
end

--- World X/Z for borrow pickup, return, and refill (homebase slot or saved pickup pose).
function IABorrowAccess.getReturnWorldPose(ia)
	if ia == nil then
		return nil, nil, nil
	end
	local rx, rz = ia.borrowPickupPositionX, ia.borrowPickupPositionZ
	if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.getReservedParkingPlaceId ~= nil then
		local placeId = IAEquipmentPresence.State.getReservedParkingPlaceId(ia)
		if placeId ~= nil and IANeighbours ~= nil and IANeighbours.places ~= nil then
			for _, place in ipairs(IANeighbours.places) do
				if place ~= nil and place.id ~= nil and tostring(place.id) == tostring(placeId) then
					local pose = nil
					if IANeighbours.gameLoopHelper ~= nil and IANeighbours.gameLoopHelper.homebaseParking ~= nil then
						local hb = IANeighbours.gameLoopHelper.homebaseParking
						if hb.buildPoseForVehicleAtPlace ~= nil then
							pcall(function()
								pose = hb:buildPoseForVehicleAtPlace(place, ia)
							end)
						end
					end
					if pose ~= nil and pose.x ~= nil and pose.z ~= nil then
						return pose.x, pose.z, pose
					end
					if place.x ~= nil and place.z ~= nil then
						return place.x, place.z, { x = place.x, y = place.y, z = place.z, rotation = place.rotation }
					end
					break
				end
			end
		end
	end
	if rx ~= nil and rz ~= nil then
		return rx, rz, nil
	end
	return nil, nil, nil
end

function IABorrowAccess.getBorrowYardPlaceKey(ia)
	if ia == nil then
		return nil
	end
	local wx, wz = IABorrowAccess.getReturnWorldPose(ia)
	if wx == nil or wz == nil then
		wx, wz = ia.borrowPickupPositionX, ia.borrowPickupPositionZ
	end
	if wx == nil or wz == nil then
		return nil
	end
	if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.getReservedParkingPlaceId ~= nil then
		local pid = IAEquipmentPresence.State.getReservedParkingPlaceId(ia)
		if pid ~= nil then
			return "place_" .. tostring(pid)
		end
	end
	return string.format("pos_%.1f_%.1f", wx, wz)
end

function IABorrowAccess.registerBorrowMapHotspotTexture()
	if g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil then
		return
	end
	if IABorrowAccess._borrowMapHotspotRegistered then
		return
	end
	local dir = (IANeighbours ~= nil and IANeighbours.dir) or nil
	if dir == nil then
		return
	end
	local path = dir .. "textures/iaBorrowMapHotspot.xml"
	if fileExists(path) then
		g_overlayManager:addTextureConfigFile(path, "iaFosBorrow")
	end
	IABorrowAccess._borrowMapHotspotRegistered = true
end

--- PlaceableHotspot at homebase pickup / return pose (`images/mapicon_borrow.dds`).
function IABorrowAccess.createBorrowYardMapHotspot(worldX, worldZ, neighbourDisplayName)
	if PlaceableHotspot == nil or g_currentMission == nil or worldX == nil or worldZ == nil then
		return nil
	end
	IABorrowAccess.registerBorrowMapHotspotTexture()
	local mainW, mainH = 40, 40
	local smallW, smallH = 40, 40
	if getNormalizedScreenValues ~= nil then
		mainW, mainH = getNormalizedScreenValues(40, 40)
		smallW, smallH = getNormalizedScreenValues(40, 40)
	end
	local sliceMain = IA_BORROW_MAP_OVERLAY_SLICE or "iaFosBorrow.borrow"
	local hotspot = PlaceableHotspot.new()
	hotspot.isADMarker = true
	hotspot.iaFosBorrowYardMarker = true
	hotspot.width, hotspot.height = mainW, mainH
	if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
		hotspot.icon = g_overlayManager:createOverlay(sliceMain, 0, 0, mainW, mainH)
		hotspot.iconSmall = g_overlayManager:createOverlay(sliceMain, 0, 0, smallW, smallH)
	end
	if hotspot.icon == nil then
		if hotspot.delete ~= nil then
			pcall(function()
				hotspot:delete()
			end)
		end
		return nil
	end
	hotspot:setWorldPosition(worldX, worldZ)
	local label = "Borrow yard"
	if g_i18n ~= nil and g_i18n.getText ~= nil then
		label = g_i18n:getText("ia_mission_borrow_yard_marker")
	end
	if neighbourDisplayName ~= nil and tostring(neighbourDisplayName) ~= "" then
		label = label .. " (" .. tostring(neighbourDisplayName) .. ")"
	end
	hotspot:setName(label)
	if iaAddMapHotspotToMission(hotspot) then
		IAprintDebug("IABorrowAccess.createBorrowYardMapHotspot()", string.format(
			"[HOTSPOT] yard hotspot CREATED label=%s wx=%.1f wz=%.1f",
			label, worldX or 0, worldZ or 0
		), nil, nil, nil)
		return hotspot
	end
	IAprintDebug("IABorrowAccess.createBorrowYardMapHotspot()", string.format(
		"[HOTSPOT] yard hotspot create FAILED (iaAddMapHotspotToMission returned false) label=%s -> deleting orphaned hotspot",
		label
	), nil, nil, nil)
	if hotspot.delete ~= nil then
		pcall(function()
			hotspot:delete()
		end)
	end
	return nil
end

function IABorrowAccess.removeBorrowYardMapHotspot(hotspot)
	if hotspot == nil then
		IAprintDebug("IABorrowAccess.removeBorrowYardMapHotspot()", "[HOTSPOT] called with hotspot=nil -> noop", nil, nil, nil)
		return
	end
	IAprintDebug("IABorrowAccess.removeBorrowYardMapHotspot()", string.format(
		"[HOTSPOT] removing yard hotspot yardPlaceKey=%s",
		tostring(hotspot.iaFosBorrowYardPlaceKey)
	), nil, nil, nil)
	if type(iaRemoveMapHotspotFromMission) == "function" then
		iaRemoveMapHotspotFromMission(hotspot)
	elseif g_currentMission ~= nil and g_currentMission.removeMapHotspot ~= nil then
		pcall(function()
			g_currentMission:removeMapHotspot(hotspot)
		end)
	end
	if hotspot.delete ~= nil then
		pcall(function()
			hotspot:delete()
		end)
	end
	IAprintDebug("IABorrowAccess.removeBorrowYardMapHotspot()", string.format(
		"[HOTSPOT] yard hotspot REMOVED yardPlaceKey=%s",
		tostring(hotspot.iaFosBorrowYardPlaceKey)
	), nil, nil, nil)
end

--- Show borrow-yard icon for this fleet unit's return place (ref-counted per place key).
function IABorrowAccess.ensureBorrowYardMapHotspotForIA(ia, neighbourDisplayName)
	if not IABorrowAccess.isBorrowSystemActive() or ia == nil or ia.uniqueId == nil then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] skipped (active=%s ia=%s uid=%s)",
			tostring(IABorrowAccess.isBorrowSystemActive()),
			tostring(ia ~= nil),
			tostring(ia ~= nil and ia.uniqueId or nil)
		), nil, ia, nil)
		return
	end
	local uid = tostring(ia.uniqueId)
	local placeKey = IABorrowAccess.getBorrowYardPlaceKey(ia)
	if placeKey == nil then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s placeKey=nil -> cannot create yard hotspot",
			uid
		), ia.neighbour, ia, nil)
		return
	end
	if IABorrowAccess._iaYardPlaceKey[uid] == placeKey then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s already registered for placeKey=%s -> noop",
			uid, tostring(placeKey)
		), ia.neighbour, ia, nil)
		return
	end
	if IABorrowAccess._iaYardPlaceKey[uid] ~= nil then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s changing placeKey %s -> %s, releasing old",
			uid, tostring(IABorrowAccess._iaYardPlaceKey[uid]), tostring(placeKey)
		), ia.neighbour, ia, nil)
		IABorrowAccess.releaseBorrowYardMapHotspotForIA(ia)
	end
	local wx, wz = IABorrowAccess.getReturnWorldPose(ia)
	if wx == nil or wz == nil then
		wx, wz = ia.borrowPickupPositionX, ia.borrowPickupPositionZ
	end
	if wx == nil or wz == nil then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s placeKey=%s no world pose -> aborting create",
			uid, tostring(placeKey)
		), ia.neighbour, ia, nil)
		return
	end
	IABorrowAccess._iaYardPlaceKey[uid] = placeKey
	local refs = IABorrowAccess._yardPlaceRefCount[placeKey] or 0
	if refs == 0 then
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s placeKey=%s refs=0 -> creating yard hotspot at wx=%.1f wz=%.1f",
			uid, tostring(placeKey), wx, wz
		), ia.neighbour, ia, nil)
		local hotspot = IABorrowAccess.createBorrowYardMapHotspot(wx, wz, neighbourDisplayName)
		if hotspot ~= nil then
			hotspot.iaFosBorrowYardPlaceKey = placeKey
			IABorrowAccess._yardHotspots[placeKey] = hotspot
		end
	else
		IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
			"[HOTSPOT] uid=%s placeKey=%s refs=%d -> reusing existing yard hotspot, just incrementing",
			uid, tostring(placeKey), refs
		), ia.neighbour, ia, nil)
	end
	IABorrowAccess._yardPlaceRefCount[placeKey] = refs + 1
	IAprintDebug("IABorrowAccess.ensureBorrowYardMapHotspotForIA()", string.format(
		"[HOTSPOT] uid=%s placeKey=%s refsAfter=%d",
		uid, tostring(placeKey), refs + 1
	), ia.neighbour, ia, nil)
end

function IABorrowAccess.releaseBorrowYardMapHotspotForIA(ia)
	if ia == nil or ia.uniqueId == nil then
		IAprintDebug("IABorrowAccess.releaseBorrowYardMapHotspotForIA()", "[BORROW-CANCEL] ia=nil or uniqueId=nil -> abort", nil, ia, nil)
		return
	end
	local uid = tostring(ia.uniqueId)
	local placeKey = IABorrowAccess._iaYardPlaceKey[uid]
	if placeKey == nil then
		IAprintDebug("IABorrowAccess.releaseBorrowYardMapHotspotForIA()", string.format(
			"[BORROW-CANCEL] uid=%s no _iaYardPlaceKey entry -> nothing to release (yard hotspot was never registered for this uid via ensureBorrowYardMapHotspotForIA)",
			uid
		), ia.neighbour, ia, nil)
		return
	end
	IABorrowAccess._iaYardPlaceKey[uid] = nil
	local refs = (IABorrowAccess._yardPlaceRefCount[placeKey] or 1) - 1
	IAprintDebug("IABorrowAccess.releaseBorrowYardMapHotspotForIA()", string.format(
		"[BORROW-CANCEL] uid=%s placeKey=%s refsAfter=%d",
		uid, tostring(placeKey), refs
	), ia.neighbour, ia, nil)
	if refs <= 0 then
		IABorrowAccess._yardPlaceRefCount[placeKey] = nil
		local hotspot = IABorrowAccess._yardHotspots[placeKey]
		IABorrowAccess._yardHotspots[placeKey] = nil
		IABorrowAccess.removeBorrowYardMapHotspot(hotspot)
		IAprintDebug("IABorrowAccess.releaseBorrowYardMapHotspotForIA()", string.format(
			"[BORROW-CANCEL] placeKey=%s ref dropped to 0 -> yard hotspot removed", tostring(placeKey)
		), ia.neighbour, ia, nil)
	else
		IABorrowAccess._yardPlaceRefCount[placeKey] = refs
		IAprintDebug("IABorrowAccess.releaseBorrowYardMapHotspotForIA()", string.format(
			"[BORROW-CANCEL] placeKey=%s refs=%d > 0 -> yard hotspot KEPT (other unit still references it)",
			tostring(placeKey), refs
		), ia.neighbour, ia, nil)
	end
end

function IABorrowAccess.releaseBorrowYardMarkersForTree(ia)
	if ia == nil then
		return
	end
	IABorrowAccess.releaseBorrowYardMapHotspotForIA(ia)
	IABorrowAccess.forEachAttachedFleetIA(ia, function(childIa)
		IABorrowAccess.releaseBorrowYardMapHotspotForIA(childIa)
	end)
end

function IABorrowAccess.syncBorrowYardMarkers(ia, borrowed, neighbourDisplayName)
	if ia == nil then
		return
	end
	if borrowed == true then
		IABorrowAccess.ensureBorrowYardMapHotspotForIA(ia, neighbourDisplayName)
	else
		IABorrowAccess.releaseBorrowYardMapHotspotForIA(ia)
	end
end

--- Remove vehicle map hotspot from HUD (borrow end / fleet hidden). `deleteMapHotspot` alone can leave a stale reference.
function IABorrowAccess.removeVehicleMapHotspot(gameVehicle)
	IAprintDebug("IABorrowAccess.removeVehicleMapHotspot()", "[HOTSPOT] Removing vehicle map hotspot", nil, gameVehicle, nil)
	if gameVehicle == nil then
		IAprintDebug("IABorrowAccess.removeVehicleMapHotspot()", "[HOTSPOT] Game vehicle is nil -> abort", nil, nil, nil)
		return
	end
	IAprintDebug("IABorrowAccess.removeVehicleMapHotspot()", string.format(
		"[HOTSPOT] entry mapHotspotPresent=%s deleteMapHotspot=%s",
		tostring(gameVehicle.mapHotspot ~= nil),
		tostring(gameVehicle.deleteMapHotspot ~= nil)
	), nil, gameVehicle, nil)
	if gameVehicle.deleteMapHotspot ~= nil then
		IAprintDebug("IABorrowAccess.removeVehicleMapHotspot()", "[HOTSPOT] calling gameVehicle:deleteMapHotspot()", nil, gameVehicle, nil)
		IAsafePcall("IABorrowAccess.removeVehicleMapHotspot() gameVehicle:deleteMapHotspot()", function()
			gameVehicle.mapHotspot:setVisible(false)
			gameVehicle:deleteMapHotspot()
		end)
	end
	
	IAprintDebug("IABorrowAccess.removeVehicleMapHotspot()", string.format(
		"[HOTSPOT] exit mapHotspotPresent=%s",
		tostring(gameVehicle.mapHotspot ~= nil)
	), nil, gameVehicle, nil)
end

function IABorrowAccess.ensureVehicleMapHotspot(gameVehicle)

	if gameVehicle == nil or gameVehicle.createMapHotspot == nil then
		IAprintDebug("IABorrowAccess.ensureVehicleMapHotspot()", string.format(
			"[HOTSPOT] skip (gameVehicle=%s createMapHotspot=%s)",
			tostring(gameVehicle ~= nil),
			tostring(gameVehicle ~= nil and gameVehicle.createMapHotspot ~= nil)
		), nil, gameVehicle, nil)
		return
	end
	IAprintDebug("IABorrowAccess.ensureVehicleMapHotspot()", string.format(
		"[HOTSPOT] before createMapHotspot mapHotspotPresent=%s",
		tostring(gameVehicle.mapHotspot ~= nil)
	), nil, gameVehicle, nil)
	pcall(function()
		gameVehicle:createMapHotspot()
	end)
	IAprintDebug("IABorrowAccess.ensureVehicleMapHotspot()", string.format(
		"[HOTSPOT] after createMapHotspot mapHotspotPresent=%s",
		tostring(gameVehicle.mapHotspot ~= nil)
	), nil, gameVehicle, nil)
end

--- True when the local player is driving/controlling this unit's cab (not merely on the same root as an attached implement).
function IABorrowAccess.isPlayerInBorrowedCab(gameVehicle)
	if g_localPlayer == nil or gameVehicle == nil then
		return false
	end
	if gameVehicle.getIsEntered ~= nil then
		local ok, entered = pcall(function()
			return gameVehicle:getIsEntered()
		end)
		if ok and entered then
			return true
		end
	end
	if g_localPlayer.getCurrentVehicle == nil then
		return false
	end
	local playerVehicle = g_localPlayer:getCurrentVehicle()
	return playerVehicle ~= nil and playerVehicle == gameVehicle
end

function IABorrowAccess.isPlayerInAnyVehicle()
	if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
		return false
	end
	return g_localPlayer:getCurrentVehicle() ~= nil
end

--- Force leave using FS25 Enterable paths (doLeaveVehicle / Player.leaveVehicle), not requestToLeave (often no-op in SP).
function IABorrowAccess.forcePlayerLeaveEnterable(enterable)
	if g_localPlayer == nil or enterable == nil then
		return false
	end

	if enterable.setIsLeavingAllowed ~= nil then
		pcall(function()
			enterable:setIsLeavingAllowed(true)
		end)
	end

	if enterable.doLeaveVehicle ~= nil then
		pcall(function()
			enterable:doLeaveVehicle()
		end)
		if not IABorrowAccess.isPlayerInAnyVehicle() then
			return true
		end
	end

	if g_localPlayer.leaveVehicle ~= nil then
		pcall(function()
			g_localPlayer:leaveVehicle(enterable, true)
		end)
		if not IABorrowAccess.isPlayerInAnyVehicle() then
			return true
		end
		pcall(function()
			g_localPlayer:leaveVehicle()
		end)
		if not IABorrowAccess.isPlayerInAnyVehicle() then
			return true
		end
	end

	if enterable.requestToLeave ~= nil then
		pcall(function()
			enterable:requestToLeave(g_localPlayer)
		end)
		if not IABorrowAccess.isPlayerInAnyVehicle() then
			return true
		end
	elseif g_currentMission ~= nil and g_currentMission.requestToLeaveVehicle ~= nil and g_localPlayer.connection ~= nil then
		pcall(function()
			g_currentMission:requestToLeaveVehicle(g_localPlayer.connection, enterable)
		end)
		if not IABorrowAccess.isPlayerInAnyVehicle() then
			return true
		end
	end

	return not IABorrowAccess.isPlayerInAnyVehicle()
end

--- Eject player from the borrowed cab before detach/teleport.
function IABorrowAccess.ejectPlayerFromVehicleTree(gameVehicle)
	if not IABorrowAccess.isPlayerInBorrowedCab(gameVehicle) then
		return
	end
	local enterable = g_localPlayer:getCurrentVehicle()
	if enterable == nil then
		enterable = gameVehicle
	end
	IABorrowAccess.forcePlayerLeaveEnterable(enterable)
	if enterable ~= gameVehicle and gameVehicle.getIsEntered ~= nil then
		local ok, entered = pcall(function()
			return gameVehicle:getIsEntered()
		end)
		if ok and entered then
			IABorrowAccess.forcePlayerLeaveEnterable(gameVehicle)
		end
	end
end

--- Detach a borrowed implement from its host (player tractor, NPC tractor, etc.) when borrow ends.
function IABorrowAccess.detachFromCurrentAttacher(implementVehicle)
	if implementVehicle == nil or implementVehicle.getAttacherVehicle == nil then
		return
	end
	local okAtt, attacher = pcall(function()
		return implementVehicle:getAttacherVehicle()
	end)
	if not okAtt or attacher == nil or attacher.detachImplement == nil then
		return
	end
	if attacher.getImplementIndexByObject ~= nil then
		local okIdx, implementIndex = pcall(function()
			return attacher:getImplementIndexByObject(implementVehicle)
		end)
		if okIdx and implementIndex ~= nil then
			pcall(function()
				attacher:detachImplement(implementIndex, true)
			end)
			return
		end
	end
	if attacher.getAttachedImplements ~= nil then
		local okList, attached = pcall(function()
			return attacher:getAttachedImplements()
		end)
		if okList and attached ~= nil then
			for index, entry in pairs(attached) do
				local obj = entry
				if type(entry) == "table" and entry.object ~= nil then
					obj = entry.object
				end
				if obj == implementVehicle then
					pcall(function()
						attacher:detachImplement(index, true)
					end)
					return
				end
			end
		end
	end
end

--- Unhook from host tractor, then drop mounted tools (implements on returned root).
function IABorrowAccess.detachBorrowedVehicleFromWorld(ia)
	if ia == nil or ia.vehicle == nil then
		return
	end
	IABorrowAccess.detachFromCurrentAttacher(ia.vehicle)
	if type(ia.mech_detachAllImplements) == "function" then
		pcall(function()
			ia:mech_detachAllImplements()
		end)
	end
end

--- Physical detach, clear borrow on unit and borrowed children on its hitch, reconcile only those units.
function IABorrowAccess.applyBorrowReturn(ia, neighbour)
	if ia == nil then
		IAprintDebug("IABorrowAccess.applyBorrowReturn()", "[BORROW-CANCEL] ia=nil -> abort", neighbour, nil, nil)
		return
	end
	IAprintDebug("IABorrowAccess.applyBorrowReturn()", string.format(
		"[BORROW-CANCEL] entry uid=%s vehicle=%s isBorrowedByPlayer=%s presence.owner=%s borrowReturnPlaceId=%s",
		tostring(ia.uniqueId), ia.vehicle ~= nil and "present" or "NIL",
		tostring(ia.isBorrowedByPlayer),
		tostring(ia.presenceState ~= nil and ia.presenceState.owner),
		tostring(ia.borrowReturnParkingPlaceId)
	), neighbour, ia, nil)

	local borrowedChildren = {}
	IABorrowAccess.forEachAttachedFleetIA(ia, function(childIa)
		if childIa.isBorrowedByPlayer == true then
			table.insert(borrowedChildren, childIa)
		end
	end)
	IAprintDebug("IABorrowAccess.applyBorrowReturn()", string.format(
		"[BORROW-CANCEL] borrowedChildren count=%d", #borrowedChildren
	), neighbour, ia, nil)

	IABorrowAccess.ejectPlayerFromVehicleTree(ia.vehicle)
	IABorrowAccess.detachBorrowedVehicleFromWorld(ia)
	IAprintDebug("IABorrowAccess.applyBorrowReturn()", "[BORROW-CANCEL] post-eject + post-detach from world", neighbour, ia, nil)

	for _, childIa in ipairs(borrowedChildren) do
		if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.endBorrowed ~= nil then
			IAEquipmentPresence.State.endBorrowed(childIa)
		else
			childIa.isBorrowedByPlayer = false
		end
	end

	if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.endBorrowed ~= nil then
		IAEquipmentPresence.State.endBorrowed(ia)
	else
		ia.isBorrowedByPlayer = false
		local ps = ia.presenceState
		if ps ~= nil and ps.owner == "borrowed" then
			ps.owner = "none"
		end
	end
	IAprintDebug("IABorrowAccess.applyBorrowReturn()", string.format(
		"[BORROW-CANCEL] post-endBorrowed isBorrowedByPlayer=%s presence.owner=%s vehicleHotspotApplied=%s",
		tostring(ia.isBorrowedByPlayer),
		tostring(ia.presenceState ~= nil and ia.presenceState.owner),
		tostring(ia.vehicleHotspotApplied)
	), neighbour, ia, nil)

	if IAEquipmentPresence ~= nil and IAEquipmentPresence.Reconcile ~= nil and IAEquipmentPresence.Reconcile.reconcileVehicle ~= nil then
		local function reconcileReturnedUnit(unitIa)
			if unitIa == nil then
				return
			end
			if IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.syncBorrowedFlag ~= nil then
				IAEquipmentPresence.State.syncBorrowedFlag(unitIa)
			end
			IAEquipmentPresence.Reconcile.reconcileVehicle(unitIa)
		end
		for _, childIa in ipairs(borrowedChildren) do
			reconcileReturnedUnit(childIa)
		end
		reconcileReturnedUnit(ia)
	end

	if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.reapplyVehicleHotspotForPresence ~= nil then
		for _, childIa in ipairs(borrowedChildren) do
			IAEquipmentPresence.State.reapplyVehicleHotspotForPresence(childIa)
		end
		IAEquipmentPresence.State.reapplyVehicleHotspotForPresence(ia)
		IAprintDebug("IABorrowAccess.applyBorrowReturn()", string.format(
			"[BORROW-CANCEL] post-reapplyVehicleHotspotForPresence vehicleHotspotApplied=%s mapHotspot=%s",
			tostring(ia.vehicleHotspotApplied),
			tostring(ia.vehicle ~= nil and ia.vehicle.mapHotspot or "no-vehicle")
		), neighbour, ia, nil)
	end

	IABorrowAccess.releaseBorrowYardMapHotspotForIA(ia)
	IAprintDebug("IABorrowAccess.applyBorrowReturn()", string.format(
		"[BORROW-CANCEL] post-releaseBorrowYardMapHotspotForIA yardKey(after)=%s",
		tostring(IABorrowAccess._iaYardPlaceKey ~= nil and IABorrowAccess._iaYardPlaceKey[tostring(ia.uniqueId or "")] or "nil")
	), neighbour, ia, nil)
	IABorrowAccess.rebuildBorrowedIdSet()
end

function IABorrowAccess.setBorrowedForGameVehicle(vehicle, borrowed)
	if vehicle == nil then
		IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", "[BORROW-CANCEL] vehicle=nil -> abort", nil, nil, nil)
		return false, "vehicle is nil"
	end
	local ia, neighbour = IABorrowAccess.getIAForVehicle(vehicle)
	local fleetVehicle = vehicle
	if not IABorrowAccess.isFleetNpcVehicle(fleetVehicle) then
		fleetVehicle = getRootVehicle(vehicle)
	end
	if ia == nil then
		if not IABorrowAccess.isFleetNpcVehicle(fleetVehicle) then
			IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", string.format(
				"[BORROW-CANCEL] not an NPC fleet vehicle ownerFarmId=%s",
				tostring(IABorrowAccess.getOwnerFarmId(fleetVehicle))
			), nil, vehicle, nil)
			return false, "not an NPC fleet vehicle (ownerFarmId " .. tostring(IABorrowAccess.getOwnerFarmId(fleetVehicle)) .. ")"
		end
		local uid = vehicle.uniqueId or (fleetVehicle ~= nil and fleetVehicle.uniqueId)
		IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", string.format(
			"[BORROW-CANCEL] no IANeighbourVehicle for uniqueId=%s -> abort", tostring(uid)
		), nil, vehicle, nil)
		return false, "no IANeighbourVehicle for uniqueId " .. tostring(uid) .. " (not in mod fleet list)"
	end

	borrowed = borrowed == true
	local neighbourName = neighbour ~= nil and neighbour.name or nil
	IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", string.format(
		"[BORROW-CANCEL] entry borrowed=%s currentIsBorrowed=%s presence.owner=%s vehicleHotspotApplied=%s borrowReturnPlaceId=%s",
		tostring(borrowed), tostring(ia.isBorrowedByPlayer),
		tostring(ia.presenceState ~= nil and ia.presenceState.owner),
		tostring(ia.vehicleHotspotApplied),
		tostring(ia.borrowReturnParkingPlaceId)
	), neighbour, ia, nil)
	if ia.isBorrowedByPlayer == borrowed then
		IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", string.format(
			"[BORROW-CANCEL] flag already %s -> only syncBorrowYardMarkers (engine vehicle hotspot WILL NOT be touched)",
			tostring(borrowed)
		), neighbour, ia, nil)
		IABorrowAccess.syncBorrowYardMarkers(ia, borrowed, neighbourName)
		return true, borrowed and "already borrowed" or "already not borrowed"
	end

	if borrowed then
		ia.isBorrowedByPlayer = true
		IABorrowAccess.markBorrowed(ia)
		if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.setDesiredBorrowed ~= nil then
			IAEquipmentPresence.State.setDesiredBorrowed(ia)
		end
		IABorrowAccess.syncBorrowYardMarkers(ia, true, neighbourName)
	else
		IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", "[BORROW-CANCEL] flag transition true->false -> applyBorrowReturn", neighbour, ia, nil)
		IABorrowAccess.applyBorrowReturn(ia, neighbour)
		-- applyBorrowReturn calls rebuildBorrowedIdSet internally
	end

	--IABorrowAccess.persistBorrowStateToOutbound()
	--IAprintDebug("IABorrowAccess.setBorrowedForGameVehicle()", string.format(
	--	"[BORROW-CANCEL] post-persist isBorrowedByPlayer=%s presence.owner=%s vehicleHotspotApplied=%s mapHotspot=%s",
	--	tostring(ia.isBorrowedByPlayer),
	--	tostring(ia.presenceState ~= nil and ia.presenceState.owner),
	--	tostring(ia.vehicleHotspotApplied),
	--	tostring(ia.vehicle ~= nil and ia.vehicle.mapHotspot or "no-vehicle")
	--), neighbour, ia, nil)

	local name = ia.vehicleName or ia.name or ia.xmlFilename or "vehicle"
	local neighbourName = neighbour ~= nil and neighbour.name or "?"
	local uid = ia.uniqueId or vehicle.uniqueId or (fleetVehicle ~= nil and fleetVehicle.uniqueId)
	return true, string.format("%s [%s] borrow=%s (uniqueId %s)", tostring(name), tostring(neighbourName), tostring(borrowed), tostring(uid))
end

--function IABorrowAccess.persistBorrowStateToOutbound()
--	if IANeighbours == nil or IANeighbours.xmlHelper == nil or IANeighbours.xmlHelper.saveOutboundXMLToXMLFile == nil then
--		return
--	end
--	pcall(function()
--		IANeighbours.xmlHelper:saveOutboundXMLToXMLFile()
--	end)
--end

function IABorrowAccess.listBorrowedVehicles()
	local lines = {}
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return { "no neighbours loaded" }
	end
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia in pairs(neighbour.vehicles) do
				if ia ~= nil and ia.isBorrowedByPlayer == true then
					table.insert(lines, string.format("  %s | %s | uid=%s", tostring(neighbour.name), tostring(ia.vehicleName or ia.xmlFilename or "?"), tostring(ia.uniqueId)))
				end
			end
		end
	end
	if #lines == 0 then
		table.insert(lines, "  (none)")
	end
	return lines
end

function IABorrowAccess.listFleetVehicles()
	local lines = {}
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return { "no neighbours loaded" }
	end
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia in pairs(neighbour.vehicles) do
				if ia ~= nil then
					local borrowed = ia.isBorrowedByPlayer == true and " [BORROWED]" or ""
					table.insert(lines, string.format(
						"  %s | %s | uid=%s%s",
						tostring(neighbour.name),
						tostring(ia.vehicleName or ia.xmlFilename or ia.type or "?"),
						tostring(ia.uniqueId or "?"),
						borrowed
					))
				end
			end
		end
	end
	if #lines == 0 then
		table.insert(lines, "  (none)")
	end
	return lines
end

-- ---------------------------------------------------------------------------
-- Vehicle specialization (registered from IANeighbours at mod load via addSpecialization)
-- ---------------------------------------------------------------------------

function IABorrowAccess.prerequisitesPresent(specializations)
	if SpecializationUtil.hasSpecialization(Locomotive, specializations) then
		return false
	end
	if SpecializationUtil.hasSpecialization(Attachable, specializations) then
		return true
	end
	return SpecializationUtil.hasSpecialization(Enterable, specializations)
		and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function IABorrowAccess.initSpecialization()
end

function IABorrowAccess.registerOverwrittenFunctions(vehicleType)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "isAttachAllowed", IABorrowAccess.isAttachAllowed)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", IABorrowAccess.getCanMotorRun)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsTabbable", IABorrowAccess.getIsTabbable)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMotorNotAllowedWarning", IABorrowAccess.getMotorNotAllowedWarning)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeSold", IABorrowAccess.getCanBeSold)
	if SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations) then
		SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsLeavingAllowed", IABorrowAccess.getIsLeavingAllowed)
	end
end

function IABorrowAccess:isAttachAllowed(superFunc, farmId, attacherVehicle)
	if IABorrowAccess.shouldAllowCrossFarmAttach(self, farmId, attacherVehicle) then
		if self.spec_attachable ~= nil and self.spec_attachable.detachingInProgress then
			return false, nil
		end
		return true, nil
	end
	return superFunc(self, farmId, attacherVehicle)
end

function IABorrowAccess:getCanMotorRun(superFunc, ...)
	if IABorrowAccess.hasPlayerBorrowAccess(self) then
		return true
	end
	return superFunc(self, ...)
end

function IABorrowAccess:getIsTabbable(superFunc)
	if IABorrowAccess.hasPlayerBorrowAccess(self) then
		return true
	end
	return superFunc(self)
end

function IABorrowAccess:getMotorNotAllowedWarning(superFunc)
	if IABorrowAccess.hasPlayerBorrowAccess(self) then
		return nil
	end
	return superFunc(self)
end

function IABorrowAccess:getCanBeSold(superFunc, ...)
	if IABorrowAccess.isBorrowProtected(self) then
		return false
	end
	return superFunc(self, ...)
end

function IABorrowAccess:getIsLeavingAllowed(superFunc)
	if IABorrowAccess.hasPlayerBorrowAccess(self) then
		return true
	end
	return superFunc(self)
end

-- ---------------------------------------------------------------------------
-- Console commands (registered from IANeighbours:loadMap)
-- ---------------------------------------------------------------------------

function IABorrowAccess:consoleCommandIaBorrowVehicle(arg1, arg2)
	if not IABorrowAccess.isBorrowSystemActive() then
		return "Borrow system is only active in single player."
	end

	local sub = arg1 ~= nil and string.lower(tostring(arg1)) or ""
	if sub == "list" then
		local lines = { "Borrowed fleet vehicles:" }
		for _, line in ipairs(IABorrowAccess.listBorrowedVehicles()) do
			table.insert(lines, line)
		end
		return table.concat(lines, "\n")
	end
	if sub == "fleet" then
		local lines = { "NPC fleet vehicles (use uniqueId with iaBorrowVehicle):" }
		for _, line in ipairs(IABorrowAccess.listFleetVehicles()) do
			table.insert(lines, line)
		end
		return table.concat(lines, "\n")
	end

	local borrowed = true
	local token = arg1
	if sub == "clear" or sub == "return" or sub == "off" or sub == "false" then
		borrowed = false
		token = arg2
	elseif sub == "set" or sub == "on" or sub == "true" then
		borrowed = true
		token = arg2
	end

	local vehicle, err = IABorrowAccess.resolveGameVehicle(token)
	if vehicle == nil then
		return "iaBorrowVehicle: " .. tostring(err)
	end

	local ok, msg = IABorrowAccess.setBorrowedForGameVehicle(vehicle, borrowed)
	if not ok then
		return "iaBorrowVehicle: " .. tostring(msg)
	end
	return "iaBorrowVehicle: " .. tostring(msg)
end

function IABorrowAccess.registerConsoleCommands()
	if addConsoleCommand == nil then
		return
	end
	addConsoleCommand(
		"iaBorrowVehicle",
		"Fields of Stories: borrow/return NPC fleet vehicle (SP). Usage: iaBorrowVehicle [uniqueId|entered|nearest] | iaBorrowVehicle clear [token] | iaBorrowVehicle list | iaBorrowVehicle fleet",
		"consoleCommandIaBorrowVehicle",
		IABorrowAccess,
		"[set|clear|list]; [uniqueId|entered|nearest]"
	)
end

--- Absolute script path (same as IANeighbours source path); avoid Utils.getFilename here — it can yield a bare filename and fail resource load.
function IABorrowAccess.getScriptFilename()
	local modDir = (IANeighbours ~= nil and IANeighbours.dir) or g_currentModDirectory
	if modDir == nil then
		return nil
	end
	return modDir .. "IABorrowAccess.lua"
end

function IABorrowAccess.installAccessHandlerHook()
	if IABorrowAccess._accessHandlerHookInstalled == true then
		return
	end
	if AccessHandler == nil or AccessHandler.canFarmAccess == nil then
		return
	end

	AccessHandler.canFarmAccess = Utils.overwrittenFunction(AccessHandler.canFarmAccess, function(handler, superFunc, farmId, object, ...)
		if IABorrowAccess.shouldAllowFarmAccessForBorrowed(farmId, object) then
			return true
		end
		return superFunc(handler, farmId, object, ...)
	end)

	IABorrowAccess._accessHandlerHookInstalled = true
	--Logging.info("[%s] Borrow access AccessHandler.canFarmAccess hook installed", IABorrowAccess.MOD_NAME)
end

--- While a borrow session is live, grant the player cross-farm access to foreign-owned PLACEABLE
-- animated objects (shed/gate doors) only. Those gate both their trigger prompt
-- (AnimatedObject:triggerCallback) and per-frame activation (getCanBeTriggered) on
-- accessHandler:canFarmAccessOtherId(playerFarmId, ownerFarmId), which has no object argument — so we
-- cannot tell a door check from a vehicle check inside the override. To keep this scoped to doors only
-- (and NOT relax entering foreign vehicles), the override is gated on _inAnimatedObjectAccess, a guard
-- flag set only while AnimatedObject's access methods run (see installAnimatedObjectAccessHook).
function IABorrowAccess.shouldAllowOtherIdAccessForBorrowed(farmId, objectFarmId)
	if IABorrowAccess._inAnimatedObjectAccess ~= true then
		return false
	end
	if not IABorrowAccess.isBorrowSystemActive() then
		return false
	end
	if IAMissionBorrow == nil or IAMissionBorrow.hasActiveSession == nil or not IAMissionBorrow.hasActiveSession() then
		return false
	end
	local playerFarm = IABorrowAccess.getPlayerFarmId()
	if playerFarm == nil or farmId ~= playerFarm then
		return false
	end
	if objectFarmId == nil or objectFarmId == playerFarm then
		return false
	end
	return true
end

function IABorrowAccess.installAccessHandlerOtherIdHook()
	if IABorrowAccess._accessHandlerOtherIdHookInstalled == true then
		return
	end
	if AccessHandler == nil or AccessHandler.canFarmAccessOtherId == nil then
		return
	end

	AccessHandler.canFarmAccessOtherId = Utils.overwrittenFunction(AccessHandler.canFarmAccessOtherId, function(handler, superFunc, farmId, objectFarmId, ...)
		if IABorrowAccess.shouldAllowOtherIdAccessForBorrowed(farmId, objectFarmId) then
			return true
		end
		return superFunc(handler, farmId, objectFarmId, ...)
	end)

	IABorrowAccess._accessHandlerOtherIdHookInstalled = true
	--Logging.info("[%s] Borrow access AccessHandler.canFarmAccessOtherId hook installed", IABorrowAccess.MOD_NAME)
end

--- Set IABorrowAccess._inAnimatedObjectAccess only while a placeable door/gate's activation is being
-- evaluated. AnimatedObjectActivatable:getIsActivatable() is the single chokepoint that encloses the
-- whole door access chain in FS25: getIsActivatable -> animatedObject:getCanBeTriggered() -> the
-- placeable's PlaceableAnimatedObjects:getCanTriggerAnimatedObject() -> accessHandler access check
-- (which ultimately funnels through canFarmAccessOtherId). Wrapping it here is what scopes the
-- canFarmAccessOtherId relaxation to placeable doors only. Vehicles never run through this class, so
-- they are unaffected. Note: FS25's AnimatedObject:triggerCallback has NO access check (it always adds
-- the activatable on trigger enter); getIsActivatable is the gate that decides whether the prompt shows.
function IABorrowAccess.installAnimatedObjectAccessHook()
	if IABorrowAccess._animatedObjectAccessHookInstalled == true then
		return
	end
	if AnimatedObjectActivatable == nil or AnimatedObjectActivatable.getIsActivatable == nil then
		return
	end

	AnimatedObjectActivatable.getIsActivatable = Utils.overwrittenFunction(AnimatedObjectActivatable.getIsActivatable, function(self, superFunc, ...)
		local prev = IABorrowAccess._inAnimatedObjectAccess
		IABorrowAccess._inAnimatedObjectAccess = true
		local results = { superFunc(self, ...) }
		IABorrowAccess._inAnimatedObjectAccess = prev
		return unpack(results)
	end)

	IABorrowAccess._animatedObjectAccessHookInstalled = true
	--Logging.info("[%s] Borrow access AnimatedObjectActivatable access guard installed", IABorrowAccess.MOD_NAME)
end

function IABorrowAccess.installValidateTypesHook()
	if IABorrowAccess._validateTypesHookInstalled == true then
		return
	end

	local function validateTypes(typeManager)
		if typeManager.typeName ~= "vehicle" then
			return
		end
		local specObject = g_specializationManager:getSpecializationObjectByName(IABorrowAccess.SPEC_NAME)
		if specObject == nil then
			return
		end
		for typeName, typeEntry in pairs(typeManager:getTypes()) do
			if specObject.prerequisitesPresent(typeEntry.specializations) then
				typeManager:addSpecialization(typeName, IABorrowAccess.SPEC_NAME)
			end
		end
	end

	TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, validateTypes)
	IABorrowAccess._validateTypesHookInstalled = true
	IABorrowAccess.installAccessHandlerHook()
	IABorrowAccess.installAccessHandlerOtherIdHook()
	IABorrowAccess.installAnimatedObjectAccessHook()
	--Logging.info("[%s] Borrow access validateTypes hook installed", IABorrowAccess.MOD_NAME)
end

--- Called once from IANeighbours at mod load (not loadMap). Loads this file via the engine specialization pipeline.
function IABorrowAccess.registerSpecialization()
	if g_specializationManager == nil then
		return false
	end
	if g_specializationManager:getSpecializationObjectByName(IABorrowAccess.SPEC_NAME) ~= nil then
		IABorrowAccess.installValidateTypesHook()
		return true
	end

	local scriptPath = IABorrowAccess.getScriptFilename()
	if scriptPath == nil or not fileExists(scriptPath) then
		--Logging.error("[%s] Borrow access script not found: %s", IABorrowAccess.MOD_NAME, tostring(scriptPath))
		return false
	end

	g_specializationManager:addSpecialization(
		"borrowAccess",
		"IABorrowAccess",
		scriptPath,
		nil
	)

	local specObject = g_specializationManager:getSpecializationObjectByName(IABorrowAccess.SPEC_NAME)
	if specObject == nil then
		--Logging.error("[%s] Borrow access specialization failed to register (class IABorrowAccess)", IABorrowAccess.MOD_NAME)
		return false
	end

	IABorrowAccess.installValidateTypesHook()
	--Logging.info("[%s] Borrow access specialization registered", IABorrowAccess.MOD_NAME)
	return true
end

-- File loaded by addSpecialization: install hooks when class is ready.
IABorrowAccess.installValidateTypesHook()
IABorrowAccess.installAccessHandlerHook()
IABorrowAccess.installAccessHandlerOtherIdHook()
IABorrowAccess.installAnimatedObjectAccessHook()
