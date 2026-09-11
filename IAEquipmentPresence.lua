--
-- FS25 Fields of Stories - equipment presence (3 layers)
-- Layer 1 State: desired presence only (no game calls)
-- Layer 2 Reconcile: diff desired vs actual, sole high-level authority
-- Layer 3 Mechanics: delegated to IANeighbourVehicle:mech_* (no policy)
--

IAEquipmentPresence = {}

-- ---------------------------------------------------------------------------
-- Layer 1 — Presence state model
-- ---------------------------------------------------------------------------

IAEquipmentPresence.State = {}

function IAEquipmentPresence.State.newDefault()
	return {
		owner = "none",
		mode = "hidden",
		pose = nil,
		attachment = nil,
		parkingPlaceId = nil
	}
end

function IAEquipmentPresence.State.ensure(ia)
	if ia.presenceState == nil then
		ia.presenceState = IAEquipmentPresence.State.newDefault()
	end
	return ia.presenceState
end

--- Single integration point for vehicle map hotspot lifecycle (borrowed = visible, otherwise removed).
-- Acts only on transitions and on the first apply after the game vehicle has been attached.
-- Safe to call when ia.vehicle is nil (no-op until vehicle is loaded; flag is left unset so a later call applies).
function IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
	if ia == nil or ia.vehicle == nil then
		IAprintDebug("IAEquipmentPresence.State.applyVehicleHotspotForPresence()", string.format(
			"[BORROW-CANCEL] early-return ia=%s vehicle=%s",
			ia ~= nil and "present" or "nil",
			ia ~= nil and (ia.vehicle ~= nil and "present" or "NIL") or "n/a"
		), ia ~= nil and ia.neighbour or nil, ia, nil)
		return
	end

	-- TODO: temorary disabled until the borrow-equipment missions are fixed (hotspot is not removed correctly after mission)
	local desired = false--ia.presenceState ~= nil and ia.presenceState.owner == "borrowed"
	IAprintDebug("IAEquipmentPresence.State.applyVehicleHotspotForPresence()", string.format(
		"[BORROW-CANCEL] entry desired=%s vehicleHotspotApplied=%s presence.owner=%s mapHotspot=%s",
		tostring(desired), tostring(ia.vehicleHotspotApplied),
		tostring(ia.presenceState ~= nil and ia.presenceState.owner),
		tostring(ia.vehicle.mapHotspot)
	), ia.neighbour, ia, nil)
	if ia.vehicleHotspotApplied == desired then
		IAprintDebug("IAEquipmentPresence.State.applyVehicleHotspotForPresence()", string.format(
			"[BORROW-CANCEL] no-op (vehicleHotspotApplied==desired==%s) -> engine map hotspot UNCHANGED",
			tostring(desired)
		), ia.neighbour, ia, nil)
		return
	end
	if IABorrowAccess == nil then
		IAprintDebug("IAEquipmentPresence.State.applyVehicleHotspotForPresence()", "[BORROW-CANCEL] IABorrowAccess=nil -> cannot toggle hotspot", ia.neighbour, ia, nil)
		return
	end
	if desired then
		if IABorrowAccess.ensureVehicleMapHotspot ~= nil then
			IABorrowAccess.ensureVehicleMapHotspot(ia.vehicle)
		end
	else
		if IABorrowAccess.removeVehicleMapHotspot ~= nil then
			IABorrowAccess.removeVehicleMapHotspot(ia.vehicle)
		end
	end
	ia.vehicleHotspotApplied = desired
	IAprintDebug("IAEquipmentPresence.State.applyVehicleHotspotForPresence()", string.format(
		"[BORROW-CANCEL] applied desired=%s mapHotspot(now)=%s",
		tostring(desired), tostring(ia.vehicle.mapHotspot)
	), ia.neighbour, ia, nil)
end

--- Re-apply once after mechanics that may have recreated an engine vehicle hotspot.
function IAEquipmentPresence.State.reapplyVehicleHotspotForPresence(ia)
	if ia == nil then
		return
	end
	ia.vehicleHotspotApplied = nil
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

function IAEquipmentPresence.State.reportStateChange(ia,s,source)
	if s == nil then
		return
	end
	if source == nil then
		source = "unknown"
	end
	local str = "State changed: from "..tostring(source)..": "..tostring(s.owner).." "..tostring(s.mode)
	if s.attachment ~= nil then
		str = str .. " Attachment: " .. tostring(s.attachment.role) .. " " .. tostring(s.attachment.parentUniqueId)
	end
	if s.parkingPlaceId ~= nil then
		str = str .. " Parking Place: " .. tostring(s.parkingPlaceId)
	end
	IAprintDebug("IAEquipmentPresence.State.reportStateChange()", str, ia.neighbour, ia, nil)
end
function IAEquipmentPresence.State.setDesiredHidden(ia)
	local s = IAEquipmentPresence.State.ensure(ia)
	s.owner = "none"
	s.mode = "hidden"
	s.pose = nil
	s.attachment = nil
	s.parkingPlaceId = nil
	IAEquipmentPresence.State.reportStateChange(ia, s, "setDesiredHidden")
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

function IAEquipmentPresence.State.setDesiredHomebase(ia, pose, parkingPlaceId)
	local s = IAEquipmentPresence.State.ensure(ia)
	s.owner = "homebase"
	s.mode = "visible"
	s.pose = pose
	s.attachment = nil
	s.parkingPlaceId = parkingPlaceId
	if pose ~= nil then
		ia.positionX = pose.x
		ia.positionY = pose.y
		ia.positionZ = pose.z
		ia.rotation = pose.rotation or 0
	end
	if parkingPlaceId ~= nil then
		ia.parkingPlaceId = parkingPlaceId
		ia.parkingPlaceSemantic = "homebase"
	end
	IAEquipmentPresence.State.reportStateChange(ia, s, "setDesiredHomebase")
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

function IAEquipmentPresence.State.setDesiredSituationMain(ia, pose)
	local s = IAEquipmentPresence.State.ensure(ia)
	s.owner = "situation"
	s.mode = "visible"
	s.pose = pose
	s.attachment = nil
	s.parkingPlaceId = nil
	if pose ~= nil then
		ia.positionX = pose.x
		ia.positionY = pose.y
		ia.positionZ = pose.z
		ia.rotation = pose.rotation or 0
	end
	IAEquipmentPresence.State.reportStateChange(ia, s, "setDesiredSituationMain")
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

function IAEquipmentPresence.State.setDesiredSituationAttachment(ia, role, parentUniqueId)
	local s = IAEquipmentPresence.State.ensure(ia)
	s.owner = "situation"
	s.mode = "visible"
	s.attachment = { role = role, parentUniqueId = parentUniqueId }
	s.parkingPlaceId = nil
	IAEquipmentPresence.State.reportStateChange(ia, s, "setDesiredSituationAttachment")
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

local function findPlaceById(placeId)
	if placeId == nil or IANeighbours == nil or IANeighbours.places == nil then
		return nil
	end
	for _, place in ipairs(IANeighbours.places) do
		if place ~= nil and place.id ~= nil and tostring(place.id) == tostring(placeId) then
			return place
		end
	end
	return nil
end

--- Remember homebase return slot and pickup world pose when borrow starts (outbound XML persists these).
function IAEquipmentPresence.State.snapshotBorrowPlaces(ia)
	if ia == nil then
		return
	end
	if ia.borrowReturnParkingPlaceId == nil then
		if ia.parkingPlaceId ~= nil and (ia.parkingPlaceSemantic == nil or ia.parkingPlaceSemantic == "homebase") then
			ia.borrowReturnParkingPlaceId = ia.parkingPlaceId
			ia.borrowReturnParkingPlaceSemantic = ia.parkingPlaceSemantic or "homebase"
		elseif ia.presenceState ~= nil and ia.presenceState.owner == "homebase" and ia.presenceState.parkingPlaceId ~= nil then
			ia.borrowReturnParkingPlaceId = ia.presenceState.parkingPlaceId
			ia.borrowReturnParkingPlaceSemantic = "homebase"
		end
	end
	if ia.borrowPickupPositionX == nil and ia.vehicle ~= nil and ia.vehicle.rootNode ~= nil then
		local wx, wy, wz = getWorldTranslation(ia.vehicle.rootNode)
		ia.borrowPickupPositionX = wx
		ia.borrowPickupPositionY = wy
		ia.borrowPickupPositionZ = wz
		if ia.vehicle.getWorldRotation ~= nil then
			local _, ry, _ = ia.vehicle:getWorldRotation()
			ia.borrowPickupRotation = ry
		end
	elseif ia.borrowPickupPositionX == nil and ia.positionX ~= nil and ia.positionZ ~= nil then
		ia.borrowPickupPositionX = ia.positionX
		ia.borrowPickupPositionY = ia.positionY
		ia.borrowPickupPositionZ = ia.positionZ
		ia.borrowPickupRotation = ia.rotation
	end
end

--- Restore the reserved homebase slot after borrow ends.
-- When the vehicle is already within the return radius of the parking slot (i.e. the
-- player just detached it in range, which is how borrow-equipment missions complete),
-- we keep the parking-place reservation but skip the physical teleport. Respawning on
-- the slot in that situation can drop the unit on top of the player. Far returns (e.g.
-- via console command) still teleport so the slot is actually re-populated.
function IAEquipmentPresence.State.restoreBorrowReturnHomebase(ia)
	if ia == nil or ia.borrowReturnParkingPlaceId == nil then
		return false
	end
	local place = findPlaceById(ia.borrowReturnParkingPlaceId)
	if place == nil then
		return false
	end
	local pose = nil
	if IANeighbours ~= nil and IANeighbours.gameLoopHelper ~= nil and IANeighbours.gameLoopHelper.homebaseParking ~= nil then
		local hb = IANeighbours.gameLoopHelper.homebaseParking
		if hb.buildPoseForVehicleAtPlace ~= nil then
			pcall(function()
				pose = hb:buildPoseForVehicleAtPlace(place, ia)
			end)
		end
	end
	if pose == nil then
		local y = place.y
		if y == nil and g_terrainNode ~= nil and place.x ~= nil and place.z ~= nil then
			y = getTerrainHeightAtWorldPos(g_terrainNode, place.x, 0, place.z) + 0.2
		end
		pose = { x = place.x, y = y or 0, z = place.z, rotation = place.rotation or 0 }
	end

	local poseForDesired = pose
	if ia.vehicle ~= nil and ia.vehicle.rootNode ~= nil and pose.x ~= nil and pose.z ~= nil then
		local wx, wy, wz = getWorldTranslation(ia.vehicle.rootNode)
		local dx = wx - pose.x
		local dz = wz - pose.z
		local thresholdM = (IAMissionBorrow ~= nil and IAMissionBorrow.RETURN_RADIUS_M) or 15
		if (dx * dx + dz * dz) <= (thresholdM * thresholdM) then
			poseForDesired = nil
			ia.positionX = wx
			ia.positionY = wy
			ia.positionZ = wz
			if ia.vehicle.getWorldRotation ~= nil then
				local okR, _, ry, _ = pcall(function() return ia.vehicle:getWorldRotation() end)
				if okR and ry ~= nil then
					ia.rotation = ry
				end
			end
		end
	end

	IAEquipmentPresence.State.setDesiredHomebase(ia, poseForDesired, place.id)
	ia.borrowReturnParkingPlaceSemantic = ia.borrowReturnParkingPlaceSemantic or "homebase"
	return true
end

--- Logical homebase/shed slot this fleet unit reserves (presence, borrow return, or ia parking fields).
function IAEquipmentPresence.State.getReservedParkingPlaceId(ia)
	if ia == nil then
		return nil
	end
	local s = ia.presenceState
	if s ~= nil and s.parkingPlaceId ~= nil then
		return s.parkingPlaceId
	end
	if ia.borrowReturnParkingPlaceId ~= nil then
		return ia.borrowReturnParkingPlaceId
	end
	if ia.parkingPlaceSemantic == "homebase" and ia.parkingPlaceId ~= nil then
		return ia.parkingPlaceId
	end
	return nil
end

function IAEquipmentPresence.State.setDesiredBorrowed(ia)
	IAEquipmentPresence.State.snapshotBorrowPlaces(ia)
	local s = IAEquipmentPresence.State.ensure(ia)
	s.owner = "borrowed"
	s.mode = "visible"
	s.pose = nil
	s.attachment = nil
	if ia.borrowReturnParkingPlaceId ~= nil then
		s.parkingPlaceId = ia.borrowReturnParkingPlaceId
		ia.parkingPlaceId = ia.borrowReturnParkingPlaceId
		ia.parkingPlaceSemantic = ia.borrowReturnParkingPlaceSemantic or "homebase"
	else
		s.parkingPlaceId = nil
	end
	ia.isBorrowedByPlayer = true
	IAEquipmentPresence.State.reportStateChange(ia, s, "setDesiredBorrowed")
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

--- Borrow ended: restore homebase slot when reserved, else clear borrow desired state for fleet reconcile.
function IAEquipmentPresence.State.endBorrowed(ia)
	if ia == nil then
		IAprintDebug("IAEquipmentPresence.State.endBorrowed()", "[BORROW-CANCEL] ia=nil -> abort", nil, nil, nil)
		return
	end
	IAprintDebug("IAEquipmentPresence.State.endBorrowed()", string.format(
		"[BORROW-CANCEL] entry uid=%s isBorrowedByPlayer=%s presence.owner=%s borrowReturnPlaceId=%s",
		tostring(ia.uniqueId), tostring(ia.isBorrowedByPlayer),
		tostring(ia.presenceState ~= nil and ia.presenceState.owner),
		tostring(ia.borrowReturnParkingPlaceId)
	), ia.neighbour, ia, nil)
	ia.isBorrowedByPlayer = false
	ia._cachedReturnPose = nil
	if IAEquipmentPresence.State.restoreBorrowReturnHomebase(ia) then
		IAprintDebug("IAEquipmentPresence.State.endBorrowed()", string.format(
			"[BORROW-CANCEL] restoreBorrowReturnHomebase=true -> presence.owner=%s (setDesiredHomebase already triggered applyVehicleHotspotForPresence)",
			tostring(ia.presenceState ~= nil and ia.presenceState.owner)
		), ia.neighbour, ia, nil)
		return
	end
	local s = IAEquipmentPresence.State.ensure(ia)
	IAprintDebug("IAEquipmentPresence.State.endBorrowed()", string.format(
		"[BORROW-CANCEL] restoreBorrowReturnHomebase=false fallback path s.owner=%s",
		tostring(s.owner)
	), ia.neighbour, ia, nil)
	if s.owner == "borrowed" then
		s.owner = "none"
		s.mode = "visible"
		s.pose = nil
		s.attachment = nil
		s.parkingPlaceId = nil
		IAEquipmentPresence.State.reportStateChange(ia, s, "endBorrowed")
		IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
	else
		IAprintDebug("IAEquipmentPresence.State.endBorrowed()", string.format(
			"[BORROW-CANCEL] s.owner=%s != 'borrowed' -> SKIPPED applyVehicleHotspotForPresence (engine map hotspot may persist if it was created)",
			tostring(s.owner)
		), ia.neighbour, ia, nil)
	end
end

--- Drop homebase desired state for a vehicle in the active situation convoy (header, combine, etc.).
-- Prevents spawnNonSituationVehiclesToHomebase reconcile from teleporting to shed before loadStep attach/field pose.
function IAEquipmentPresence.State.stripHomebaseDesiredForSituationMember(ia)
	if ia == nil then
		return
	end
	local s = ia.presenceState
	if s == nil or s.owner ~= "homebase" then
		return
	end
	s.owner = "none"
	s.mode = "visible"
	s.pose = nil
	s.attachment = nil
	s.parkingPlaceId = nil
	IAEquipmentPresence.State.applyVehicleHotspotForPresence(ia)
end

--- True if this fleet vehicle's desired presence reserves a logical place id (homebase slot, etc.).
-- @param IANeighbourVehicle ia
-- @param string|number placeId
-- @param string|nil excludeUniqueId vehicle being assigned (do not count as blocker)
function IAEquipmentPresence.State.vehiclePresenceBlocksPlaceId(ia, placeId, excludeUniqueId)
	if ia == nil or placeId == nil then
		return false
	end
	if excludeUniqueId ~= nil and ia.uniqueId ~= nil and tostring(ia.uniqueId) == tostring(excludeUniqueId) then
		return false
	end
	local reservedId = IAEquipmentPresence.State.getReservedParkingPlaceId(ia)
	if reservedId == nil or tostring(reservedId) ~= tostring(placeId) then
		return false
	end
	if ia.isBorrowedByPlayer == true then
		return true
	end
	local s = ia.presenceState
	if s ~= nil and s.mode == "visible" then
		return true
	end
	if ia.parkingPlaceSemantic == "homebase" then
		if s == nil or s.mode ~= "hidden" then
			return true
		end
	end
	return false
end

--- Any mod fleet vehicle has visible desired presence bound to placeId (used by IANeighbours:isPlaceBlocked).
-- @param string|number placeId
-- @param string|nil excludeUniqueId
-- @return boolean blocked
function IAEquipmentPresence.State.isPlaceBlockedByFleetPresenceState(placeId, excludeUniqueId)
	if placeId == nil or IANeighbours == nil or IANeighbours.neighbours == nil then
		return false
	end
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia in pairs(neighbour.vehicles) do
				if IAEquipmentPresence.State.vehiclePresenceBlocksPlaceId(ia, placeId, excludeUniqueId) then
					return true
				end
			end
		end
	end
	return false
end

function IAEquipmentPresence.State.syncBorrowedFlag(ia)
	if ia.isBorrowedByPlayer == true then
		IAEquipmentPresence.State.setDesiredBorrowed(ia)
	end
end

--- @param IASituation|nil sit
-- @return string|nil
function IAEquipmentPresence.State.resolveSituationId(sit)
	if sit == nil then
		return nil
	end
	local sid = sit.id
	if sid == nil and sit.config ~= nil then
		sid = sit.config.id
	end
	return sid ~= nil and tostring(sid) or nil
end

function IAEquipmentPresence.State.isSkippedByReconcile(ia)
	if ia == nil then
		return true
	end
	if ia.isBorrowedByPlayer == true then
		return true
	end
	local s = ia.presenceState
	if s ~= nil and s.owner == "borrowed" then
		return true
	end
	-- Restored / in-progress fieldwork convoy: policy set in IASituation init; no fleet reconcile until preserve ends.
	local sit = ia.neighbour ~= nil and ia.neighbour.activeSituation or nil
	if ia.activeSituationId ~= nil and sit ~= nil then
		local sid = IAEquipmentPresence.State.resolveSituationId(sit)
		if sid ~= nil and tostring(ia.activeSituationId) == sid then
			if type(sit.shouldPreserveSavedFieldworkPresence) == "function" and sit:shouldPreserveSavedFieldworkPresence() then
				return true
			end
		end
	end
	return false
end

function IAEquipmentPresence.State.buildPoseFromIA(ia)
	if ia == nil or ia.positionX == nil or ia.positionZ == nil then
		return nil
	end
	if ia.positionX == 0 and ia.positionZ == 0 then
		return nil
	end
	local y = ia.positionY
	if y == nil and g_terrainNode ~= nil then
		y = getTerrainHeightAtWorldPos(g_terrainNode, ia.positionX, 0, ia.positionZ) + 0.2
	end
	return {
		x = ia.positionX,
		y = y or 0,
		z = ia.positionZ,
		rotation = ia.rotation or 0
	}
end

-- ---------------------------------------------------------------------------
-- Layer 2 — Reconciliation
-- ---------------------------------------------------------------------------

IAEquipmentPresence.Reconcile = {}

local function roundXZ(v)
	if v == nil then
		return nil
	end
	return MathUtil.round(v, 0)
end

local function vehicleHasAttachedImplements(gv)
	if gv == nil or type(gv.getAttachedImplements) ~= "function" then
		return false
	end
	local ok, attached = pcall(function()
		return gv:getAttachedImplements()
	end)
	if not ok or attached == nil then
		return false
	end
	for _ in pairs(attached) do
		return true
	end
	return false
end

function IAEquipmentPresence.Reconcile.readActual(ia)
	local actual = {
		visible = ia.vehicleIsVisible == true,
		poseXZMatch = true,
		attachedToParentUniqueId = nil,
		attachmentRole = nil,
		aiActive = false,
		hasAttachedImplements = false
	}
	local gv = ia.vehicle
	if gv == nil then
		actual.missing = true
		return actual
	end
	actual.missing = false
	actual.hasAttachedImplements = vehicleHasAttachedImplements(gv)
	if type(gv.getIsAIActive) == "function" then
		actual.aiActive = gv:getIsAIActive()
	end
	if gv.rootNode ~= nil then
		local wx, wy, wz = getWorldTranslation(gv.rootNode)
		ia.realPositionX = wx
		ia.realPositionY = wy
		ia.realPositionZ = wz
	end
	local desired = ia.presenceState
	if desired ~= nil and desired.mode == "visible" and desired.pose ~= nil then
		local tx = roundXZ(desired.pose.x)
		local tz = roundXZ(desired.pose.z)
		local rx = roundXZ(ia.realPositionX)
		local rz = roundXZ(ia.realPositionZ)
		actual.poseXZMatch = (tx == rx and tz == rz)
	end
	if type(gv.getAttacherVehicle) == "function" then
		local ok, att = pcall(function()
			return gv:getAttacherVehicle()
		end)
		if ok and att ~= nil and att.uniqueId ~= nil and ia.neighbour ~= nil and ia.neighbour.vehicles ~= nil then
			for _, other in pairs(ia.neighbour.vehicles) do
				if other ~= nil and other.vehicle == att then
					actual.attachedToParentUniqueId = other.uniqueId ~= nil and tostring(other.uniqueId) or nil
					break
				end
			end
		end
	end
	return actual
end

--- True when this vehicle is part of a designated header-trailer pair that the
-- engine's DynamicMountAttacher will mount. Any physics manipulation (detach,
-- teleport, hide) on either side causes a race with onUpdateTick on save reload.
local function isInDesignatedHeaderTrailerPair(ia)
	if ia == nil or ia.neighbour == nil or ia.neighbour.vehicles == nil then
		return false
	end
	-- Only protect header-trailer pairs parked at homebase. When a header
	-- is in a situation (mounted on a combine) or being returned to homebase
	-- after a situation ends, normal detach/attach/teleport must work.
	if ia.activeSituationId ~= nil and tostring(ia.activeSituationId) ~= "" then
		return false
	end
	local ps = ia.presenceState
	if ps == nil or ps.owner ~= "homebase" then
		return false
	end
	-- Case A: This vehicle is a header that has a designated trailer
	if ia.headerTrailerExternalId ~= nil then
		return true
	end
	-- Case B: This vehicle is a trailer designated by some header
	if ia.externalId ~= nil then
		local thisExtId = tostring(ia.externalId)
		for _, v in pairs(ia.neighbour.vehicles) do
			if v ~= nil and v.headerTrailerExternalId ~= nil
				and tostring(v.headerTrailerExternalId) == thisExtId then
				return true
			end
		end
	end
	return false
end

function IAEquipmentPresence.Reconcile.compareDesiredVsActual(ia)
	local ops = {}
	local desired = ia.presenceState or IAEquipmentPresence.State.newDefault()
	local actual = IAEquipmentPresence.Reconcile.readActual(ia)
	-- Never hide, detach, teleport, or re-attach while the engine AI worker is active (save reload / mid-fieldwork).
	if actual.aiActive then
		IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Skipping ops (AI active)", ia.neighbour, ia, nil)
		return ops
	end
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Desired mode: "..tostring(desired.mode), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Desired owner: "..tostring(desired.owner), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Desired parkingPlaceId: "..tostring(desired.parkingPlaceId), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Reserved parkingPlaceId: "..tostring(IAEquipmentPresence.State.getReservedParkingPlaceId(ia)), ia.neighbour, ia, nil)
	if ia.isBorrowedByPlayer == true then
		IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Borrowed (return placeId: "..tostring(ia.borrowReturnParkingPlaceId)..")", ia.neighbour, ia, nil)
	end
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Actual visible: "..tostring(actual.visible), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Actual attached to parent unique id: "..tostring(actual.attachedToParentUniqueId), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Actual ai active: "..tostring(actual.aiActive), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Actual has attached implements: "..tostring(actual.hasAttachedImplements), ia.neighbour, ia, nil)
	IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Attachment not nil: "..tostring(desired.attachment ~= nil), ia.neighbour, ia, nil)

	-- If this vehicle is part of a designated header-trailer pair, leave it
	-- completely alone — any detach, teleport, or hide would race with the
	-- engine's DynamicMountAttacher:onUpdateTick on save reload.
	local skipPhysicsOps = isInDesignatedHeaderTrailerPair(ia)

	if desired.mode == "hidden" then
		if skipPhysicsOps then
			-- Don't hide; leave the pair in physics
			return ops
		end
		if actual.visible then
			table.insert(ops, "hide")
		end
		if actual.attachedToParentUniqueId ~= nil then
			table.insert(ops, "detachFromAttacher")
		end
		return ops
	end

	if desired.mode ~= "visible" then
		return ops
	end

	if desired.owner == "homebase" and desired.mode == "visible" then
		local vtype = (ia.type ~= nil) and string.lower(tostring(ia.type)) or ""
		if vtype == "car" and actual.hasAttachedImplements then
			table.insert(ops, "detachAllImplements")
		end
	end

	if desired.attachment ~= nil then
		IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Desired attachment: "..tostring(desired.attachment.role).." "..tostring(desired.attachment.parentUniqueId), ia.neighbour, ia, nil)
		IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Actual attached to parent unique id: "..tostring(actual.attachedToParentUniqueId), ia.neighbour, ia, nil)
		local parentId = tostring(desired.attachment.parentUniqueId)
		local role = desired.attachment.role
		local actualParentId = actual.attachedToParentUniqueId ~= nil and tostring(actual.attachedToParentUniqueId) or nil
		local needsAttach = (actualParentId ~= parentId)
		if not actual.visible then
			table.insert(ops, "show")
		end
		if needsAttach then
			if actualParentId ~= nil then
				IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Detaching from attacher: "..tostring(actualParentId), ia.neighbour, ia, nil)
				table.insert(ops, "detachFromAttacher")
			end
			IAprintDebug("IAEquipmentPresence.Reconcile.compareDesiredVsActual()", "Attaching to parent: "..tostring(role).." "..tostring(parentId), ia.neighbour, ia, nil)
			table.insert(ops, "attach:" .. tostring(role) .. ":" .. tostring(parentId))
		end
		return ops
	end

	if actual.attachedToParentUniqueId ~= nil and not skipPhysicsOps then
		table.insert(ops, "detachFromAttacher")
	end

	if desired.pose ~= nil then
		if not actual.poseXZMatch or not actual.visible then
			table.insert(ops, "prepareForTeleport")
			table.insert(ops, "teleport")
			table.insert(ops, "show")
		elseif not actual.visible then
			table.insert(ops, "show")
		end
	else
		if not actual.visible and not skipPhysicsOps then
			table.insert(ops, "show")
		end
	end

	return ops
end

function IAEquipmentPresence.Reconcile.getParentIA(neighbour, parentUniqueId)
	if neighbour == nil or parentUniqueId == nil or neighbour.vehicles == nil then
		return nil
	end
	for _, ia in pairs(neighbour.vehicles) do
		if ia ~= nil and ia.uniqueId ~= nil and tostring(ia.uniqueId) == tostring(parentUniqueId) then
			return ia
		end
	end
	return nil
end

function IAEquipmentPresence.Reconcile.executeDiff(ia, ops)
	if ops == nil or #ops == 0 then
		return
	end
	local neighbour = ia.neighbour
	local opSet = {}
	for _, op in ipairs(ops) do
		opSet[op] = true
	end
	local function runOp(op)
		if not opSet[op] then
			return
		end
		if op ~= nil and ia ~= nil and ia.vehicle ~= nil and neighbour ~= nil then
			IAprintDebug("IAEquipmentPresence.Reconcile.executeDiff()", "Executing operation: "..tostring(op), neighbour, ia, nil)
		end
		if op == "detachAllImplements" then
			pcall(function() ia:mech_detachAllImplements() end)
		elseif op == "detachFromAttacher" then
			pcall(function() ia:mech_detachFromAttacher() end)
		elseif op == "hide" then
			pcall(function() ia:mech_hide() end)
		elseif op == "prepareForTeleport" then
			pcall(function() ia:mech_prepareForTeleport() end)
		elseif op == "teleport" then
			local pose = ia.presenceState ~= nil and ia.presenceState.pose or nil
			if pose ~= nil then
				pcall(function() ia:mech_teleportToPose(pose) end)
			end
		elseif op == "show" then
			pcall(function() ia:mech_show() end)
		end
	end
	runOp("detachAllImplements")
	runOp("detachFromAttacher")
	runOp("hide")
	runOp("prepareForTeleport")
	runOp("teleport")
	for op, _ in pairs(opSet) do
		if type(op) == "string" and op:sub(1, 7) == "attach:" then
			local role, parentId = op:match("^attach:(%w+):(.+)$")
			local parentIa = IAEquipmentPresence.Reconcile.getParentIA(neighbour, parentId)
			if parentIa ~= nil then
				if role == "front" then
					pcall(function() ia:mech_attachFront(parentIa) end)
				else
					pcall(function() ia:mech_attachBack(parentIa) end)
				end
			end
		end
	end
	runOp("show")
end

function IAEquipmentPresence.Reconcile.driftSweep(ia)
	if IAEquipmentPresence.State.isSkippedByReconcile(ia) then
		return
	end
	local gv = ia.vehicle
	if gv == nil then
		return
	end
	if type(gv.getIsAIActive) == "function" and gv:getIsAIActive() then
		return
	end
	local desired = ia.presenceState or IAEquipmentPresence.State.newDefault()
	if desired.mode == "hidden" and ia.vehicleIsVisible == true then
		pcall(function() ia:mech_hide() end)
	end
end

function IAEquipmentPresence.Reconcile.reconcileVehicle(ia)
	IAprintDebug("IAEquipmentPresence.Reconcile.reconcileVehicle()", "Reconciling vehicle: "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), ia.neighbour, ia, nil)
	if IAEquipmentPresence.State.isSkippedByReconcile(ia) then
		IAprintDebug("IAEquipmentPresence.Reconcile.reconcileVehicle()", "Skipping vehicle: "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), ia.neighbour, ia, nil)
		return
	end
	local actualPre = IAEquipmentPresence.Reconcile.readActual(ia)
	if actualPre.aiActive then
		IAprintDebug("IAEquipmentPresence.Reconcile.reconcileVehicle()", "Skipping vehicle (AI active): "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), ia.neighbour, ia, nil)
		return
	end
	if ia.vehicle == nil and ia.fullLoaded == true then
		IAprintDebug("IAEquipmentPresence.Reconcile.reconcileVehicle()", "Vehicle not loaded: "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), ia.neighbour, ia, nil)
		return
	end
	IAprintDebug("IAEquipmentPresence.Reconcile.reconcileVehicle()", "Comparing desired vs actual: "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), ia.neighbour, ia, nil)
	local ops = IAEquipmentPresence.Reconcile.compareDesiredVsActual(ia)
	IAEquipmentPresence.Reconcile.executeDiff(ia, ops)
	IAEquipmentPresence.Reconcile.driftSweep(ia)
end

----- Drift cleanup threshold (meters): actual root vs. desired pose XZ distance above
---- which the periodic sweep considers a homebase-desired vehicle drifted and triggers
---- a fleet reconcile.
--IAEquipmentPresence.Reconcile.DRIFT_CLEANUP_THRESHOLD_M = 15.0
--
----- Homebase desired pose vs. assigned place threshold (meters): above this,
---- the desired "homebase" pose likely came from a saved fieldwork world pose.
--IAEquipmentPresence.Reconcile.HOMEBASE_PLACE_POSE_THRESHOLD_M = 30.0
--
----- True when this vehicle is currently "in use" and must be left alone by the
---- periodic homebase drift cleanup (borrowed, member of the neighbour's active
---- situation, AI driving, or player driving).
---- @param IANeighbourVehicle ia
---- @param string|number|nil activeSituationId neighbour's current active situation id
--function IAEquipmentPresence.Reconcile.isInActiveUseForCleanup(ia, activeSituationId)
--	if ia == nil then
--		return true
--	end
--	if ia.isBorrowedByPlayer == true then
--		return true
--	end
--	if ia.activeSituationId ~= nil and activeSituationId ~= nil
--		and tostring(ia.activeSituationId) == tostring(activeSituationId) then
--		return true
--	end
--	local gv = ia.vehicle
--	if gv == nil then
--		-- No game vehicle yet (not fully loaded) — nothing to clean, leave alone.
--		return true
--	end
--	if type(gv.getIsAIActive) == "function" then
--		local ok, ai = pcall(function() return gv:getIsAIActive() end)
--		if ok and ai then
--			return true
--		end
--	end
--	if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
--		local ok, cv = pcall(function() return g_localPlayer:getCurrentVehicle() end)
--		if ok and cv ~= nil and cv == gv then
--			return true
--		end
--	end
--	return false
--end
--
----- Squared XZ distance between actual root translation and desired presence pose.
---- Returns nil when there is no game vehicle, no desired pose, or pose is incomplete.
--local function actualVsDesiredPoseXZDistSq(ia)
--	if ia == nil or ia.vehicle == nil or ia.vehicle.rootNode == nil then
--		return nil
--	end
--	local ps = ia.presenceState
--	if ps == nil or ps.pose == nil or ps.pose.x == nil or ps.pose.z == nil then
--		return nil
--	end
--	local okPos, wx, _, wz = pcall(function()
--		return getWorldTranslation(ia.vehicle.rootNode)
--	end)
--	if not okPos or wx == nil or wz == nil then
--		return nil
--	end
--	local dx = wx - ps.pose.x
--	local dz = wz - ps.pose.z
--	return dx * dx + dz * dz
--end
--
----- True when a desired homebase pose is internally inconsistent before checking
---- the actual vehicle location (e.g. save reload restored a field pose as homebase).
--local function homebaseDesiredPoseLooksInvalid(ia)
--	local ps = ia ~= nil and ia.presenceState or nil
--	if ps == nil or ps.owner ~= "homebase" or ps.mode ~= "visible" or ps.pose == nil then
--		return false, nil
--	end
--	if ps.parkingPlaceId == nil then
--		return true, "missing homebase parkingPlaceId"
--	end
--	local place = findPlaceById(ps.parkingPlaceId)
--	if place == nil or place.x == nil or place.z == nil then
--		return true, "unknown homebase parkingPlaceId"
--	end
--	if ps.pose.x == nil or ps.pose.z == nil then
--		return true, "incomplete homebase pose"
--	end
--	local dx = ps.pose.x - place.x
--	local dz = ps.pose.z - place.z
--	local d2 = dx * dx + dz * dz
--	local threshold = IAEquipmentPresence.Reconcile.HOMEBASE_PLACE_POSE_THRESHOLD_M
--	if d2 > threshold * threshold then
--		return true, string.format("homebase pose %.1fm from place", math.sqrt(d2))
--	end
--	return false, nil
--end
--
----- Clear an activeSituationId left over from a torn-down situation so the next
---- homebase assign treats this vehicle as off-duty.
--local function clearStaleActiveSituationIdOnIA(neighbour, ia)
--	if ia == nil or ia.activeSituationId == nil then
--		return false
--	end
--	local activeId = neighbour ~= nil and neighbour.activeSituationId or nil
--	if activeId ~= nil and tostring(ia.activeSituationId) == tostring(activeId) then
--		return false
--	end
--	ia.activeSituationId = nil
--	ia.situation = nil
--	return true
--end
--
----- Build a minimal "scenario" table for spawnNonSituationVehiclesToHomebase from
---- the neighbour's current active situation (so its convoy is excluded from the
---- homebase assign). Returns an empty table when there is no active situation.
--local function buildSituationScenarioForCleanup(neighbour)
--	local sit = neighbour ~= nil and neighbour.activeSituation or nil
--	if sit == nil then
--		return {}
--	end
--	return {
--		id = sit.id,
--		vehicle = sit.vehicle,
--		attachmentBack = sit.attachmentBack,
--		attachmentFront = sit.attachmentFront,
--		place = sit.place,
--		config = sit.config
--	}
--end
--
----- Periodic repair sweep: ensure off-duty fleet vehicles are physically at their
---- desired homebase pose. Repairs the case where a reconcile pass was pre-empted
---- (e.g. large-timeScale day-skip completes fieldwork while
---- IANeighbour:handleActiveSituation is suspended, so isExpired/delete + reconcile
---- never fire; the next spawn-to-homebase sets desired = homebase/visible but the
---- mechanics teleport silently fails or the chain is mid-teardown). Symptom: vehicle
---- presence debug shows "homebase/visible" while an attachment sits on a field with
---- collision.
----
---- Triggers a full neighbour fleet re-assign + reconcile when any off-duty unit:
----   1) is missing a valid homebase desired pose (orphan/stale save pose), or
----   2) has homebase desired pose with actual XZ drift > DRIFT_CLEANUP_THRESHOLD_M.
----
---- Excludes in-use vehicles (borrow, active-situation convoy, AI driving, player
---- driving) so we never disturb anything the player or AI is relying on.
--function IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet(neighbour)
--	if neighbour == nil or neighbour.vehicles == nil then
--		return false
--	end
--	local activeSituationId = neighbour.activeSituationId
--	local needsReconcile = false
--	local thresholdSq = IAEquipmentPresence.Reconcile.DRIFT_CLEANUP_THRESHOLD_M
--		* IAEquipmentPresence.Reconcile.DRIFT_CLEANUP_THRESHOLD_M
--	for _, ia in pairs(neighbour.vehicles) do
--		if ia ~= nil and not IAEquipmentPresence.Reconcile.isInActiveUseForCleanup(ia, activeSituationId) then
--			-- Drop stale activeSituationId so this vehicle counts as off-duty for the
--			-- subsequent homebase assign (otherwise assign keeps treating it as in-situation).
--			clearStaleActiveSituationIdOnIA(neighbour, ia)
--
--			local ps = ia.presenceState
--			local hasHomebaseDesired = (ps ~= nil and ps.owner == "homebase"
--				and ps.mode == "visible" and ps.pose ~= nil and ps.parkingPlaceId ~= nil)
--			if not hasHomebaseDesired then
--				needsReconcile = true
--			else
--				local invalidDesired, invalidReason = homebaseDesiredPoseLooksInvalid(ia)
--				if invalidDesired then
--					needsReconcile = true
--					if IANeighbours ~= nil and IANeighbours.debug then
--						print(string.format(
--							"--- IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet() - invalid homebase desired"
--							.. " neighbour=%s uid=%s name=%s reason=%s",
--							tostring(neighbour.name or neighbour.id),
--							tostring(ia.uniqueId),
--							tostring(ia.vehicleName or ia.name or ia.xmlFilename),
--							tostring(invalidReason)
--						))
--					end
--				else
--					local d2 = actualVsDesiredPoseXZDistSq(ia)
--					if d2 ~= nil and d2 > thresholdSq then
--						needsReconcile = true
--						if IANeighbours ~= nil and IANeighbours.debug then
--							print(string.format(
--								"--- IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet() - drift detected"
--								.. " neighbour=%s uid=%s name=%s drift=%.1fm desiredPos=(%s,%s)",
--								tostring(neighbour.name or neighbour.id),
--								tostring(ia.uniqueId),
--								tostring(ia.vehicleName or ia.name or ia.xmlFilename),
--								math.sqrt(d2),
--								tostring(ps.pose.x),
--								tostring(ps.pose.z)
--							))
--						end
--					end
--				end
--			end
--		end
--	end
--	if not needsReconcile then
--		return false
--	end
--	local hb = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
--	if hb == nil or type(hb.spawnNonSituationVehiclesToHomebase) ~= "function" then
--		return false
--	end
--	local scenario = buildSituationScenarioForCleanup(neighbour)
--	if IANeighbours ~= nil and IANeighbours.debug then
--		print(string.format(
--			"--- IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet() - repairing fleet for neighbour=%s (activeSituationId=%s)",
--			tostring(neighbour.name or neighbour.id),
--			tostring(activeSituationId)
--		))
--	end
--	pcall(function()
--		hb:spawnNonSituationVehiclesToHomebase(neighbour, scenario)
--	end)
--	return true
--end

--- Sole high-level entry: apply desired presence for entire neighbour fleet.
-- @param IANeighbour neighbour
-- @param table|nil context { scenario, computeHomebaseDesired } — when computeHomebaseDesired, run homebase slot policy first
function IAEquipmentPresence.Reconcile.reconcileNeighbourFleet(neighbour, context)
	if neighbour == nil or neighbour.vehicles == nil then
		return
	end
	context = context or {}
	if context.computeHomebaseDesired ~= false then
		if IAHomebaseParking ~= nil and IANeighbours ~= nil and IANeighbours.gameLoopHelper ~= nil then
			local hb = IANeighbours.gameLoopHelper.homebaseParking
			if hb ~= nil and hb.assignDesiredHomebaseForNeighbour ~= nil then
				hb:assignDesiredHomebaseForNeighbour(neighbour, context.scenario)
			end
		end
	end
	for _, ia in pairs(neighbour.vehicles) do
		if ia ~= nil then
			-- Situation convoy vehicles are managed by the situation's own
			-- reconcileSituationPresence; fleet must not touch them.
			if ia.activeSituationId ~= nil and tostring(ia.activeSituationId) ~= "" then
				-- skipped: situation owns this vehicle
			else
				IAEquipmentPresence.State.syncBorrowedFlag(ia)
				IAEquipmentPresence.Reconcile.reconcileVehicle(ia)
			end
		end
	end
end
