--
-- Fields of Stories — phone field mission borrow coordinator (sessions, markers, refill, return).
--

IAMissionBorrow = {}

IAMissionBorrow.sessions = {}
IAMissionBorrow._nextSessionId = 1
IAMissionBorrow.RETURN_RADIUS_M = 15
IAMissionBorrow.REFILL_RADIUS_M = 15
IAMissionBorrow.EMPTY_FILL_THRESHOLD = 50

local EQUIPMENT_CALLBACKS = {
	accept_with_equipment = true,
	accept_half_with_equipment = true,
}

function IAMissionBorrow.isActive()
	return IABorrowAccess ~= nil and IABorrowAccess.isBorrowSystemActive ~= nil and IABorrowAccess.isBorrowSystemActive()
end

function IAMissionBorrow.makeSessionId(neighbourId)
	local n = IAMissionBorrow._nextSessionId
	IAMissionBorrow._nextSessionId = n + 1
	return tostring(neighbourId or 0) .. "_" .. tostring(n)
end

function IAMissionBorrow.getSession(sessionId)
	if sessionId == nil then
		return nil
	end
	return IAMissionBorrow.sessions[tostring(sessionId)]
end

--- True while at least one borrow session is live (player currently has borrowed equipment out).
-- Used to relax cross-farm access checks (e.g. opening foreign-owned shed doors) for the borrow duration.
function IAMissionBorrow.hasActiveSession()
	return next(IAMissionBorrow.sessions) ~= nil
end

function IAMissionBorrow.isEquipmentBorrowCallback(action)
	return action ~= nil and EQUIPMENT_CALLBACKS[tostring(action)] == true
end

--- Conversation entry filter: hide equipment accept lines when fleet implements unavailable.
function IAMissionBorrow.buildContractEntryAvailabilityFilter(neighbour, contractOpenList)
	return function(entry)
		if entry == nil then
			return true
		end
		local action = entry.callbackOnSelectImmediate
		if not IAMissionBorrow.isEquipmentBorrowCallback(action) then
			return true
		end
		local h = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
		if h == nil or neighbour == nil or contractOpenList == nil then
			return false
		end
		local maxCount = nil
		if action == "accept_half_with_equipment" then
			maxCount = math.max(1, math.floor(#contractOpenList / 2))
		end
		return h:canOfferEquipmentBorrowForOpenList(neighbour, contractOpenList, maxCount)
	end
end

local function distSqXZ(x1, z1, x2, z2)
	local dx = (x1 or 0) - (x2 or 0)
	local dz = (z1 or 0) - (z2 or 0)
	return dx * dx + dz * dz
end

function IAMissionBorrow.getVehicleWorldXZ(ia)
	if ia == nil then
		return nil, nil
	end
	local gv = ia.vehicle
	if gv ~= nil and gv.rootNode ~= nil then
		local x, _, z = getWorldTranslation(gv.rootNode)
		return x, z
	end
	if ia.positionX ~= nil and ia.positionZ ~= nil then
		return ia.positionX, ia.positionZ
	end
	return nil, nil
end

function IAMissionBorrow.isVehicleUnattached(ia)
	local gv = ia ~= nil and ia.vehicle or nil
	if gv == nil or type(gv.getAttacherVehicle) ~= "function" then
		return true
	end
	local ok, att = pcall(gv.getAttacherVehicle, gv)
	return ok and att == nil
end

function IAMissionBorrow.isNearReturnPose(ia, radiusM)
	local tx, tz = IABorrowAccess.getReturnWorldPose(ia)
	local vx, vz = IAMissionBorrow.getVehicleWorldXZ(ia)
	if tx == nil or vx == nil then
		return false
	end
	local r = radiusM or IAMissionBorrow.RETURN_RADIUS_M
	return distSqXZ(vx, vz, tx, tz) <= r * r
end

function IAMissionBorrow.fillBorrowedUnitIfNeeded(ia, seedFruitTypeIndex)
	if ia == nil then
		return
	end
	if type(ia.fillSprayerOrSpreaderIfNeeded) == "function" then
		ia:fillSprayerOrSpreaderIfNeeded()
	end
	if type(ia.fillSeederIfNeeded) == "function" then
		ia:fillSeederIfNeeded(seedFruitTypeIndex)
	end
end

function IAMissionBorrow.resolveSeedIndexForOpenRow(openRow)
	if openRow == nil then
		return nil
	end
	if openRow.nextCropFruitTypeIndex ~= nil then
		return openRow.nextCropFruitTypeIndex
	end
	local cfg = openRow.config
	if cfg ~= nil and cfg.seedFruitTypeIndex ~= nil and cfg.seedFruitTypeIndex ~= "" then
		if IAFieldwork ~= nil and type(IAFieldwork.resolveFruitTypeNameOrIndex) == "function" then
			return IAFieldwork.resolveFruitTypeNameOrIndex(cfg.seedFruitTypeIndex)
		end
	end
	return nil
end

function IAMissionBorrow.unborrowSessionUnits(session)
	if session == nil or session.borrowedUnits == nil then
		IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", "[BORROW-CANCEL] early-return: session=nil or borrowedUnits=nil", nil, nil, nil)
		return
	end
	IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", string.format(
		"[BORROW-CANCEL] entry sessionId=%s units=%d",
		tostring(session.id), #session.borrowedUnits
	), session.neighbour, nil, nil)
	for idx, ia in ipairs(session.borrowedUnits) do
		if ia == nil then
			IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", string.format("[BORROW-CANCEL] unit#%d nil -> skip", idx), session.neighbour, nil, nil)
		else
			local hasVehicle = ia.vehicle ~= nil
			local hasAccess = IABorrowAccess ~= nil and IABorrowAccess.setBorrowedForGameVehicle ~= nil
			IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", string.format(
				"[BORROW-CANCEL] unit#%d uid=%s isBorrowedByPlayer=%s vehicle=%s borrowReturnPlaceId=%s",
				idx, tostring(ia.uniqueId), tostring(ia.isBorrowedByPlayer),
				hasVehicle and "present" or "NIL",
				tostring(ia.borrowReturnParkingPlaceId)
			), session.neighbour, ia, nil)
			if hasVehicle and hasAccess then
				local ok, msg = IABorrowAccess.setBorrowedForGameVehicle(ia.vehicle, false)
				IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", string.format(
					"[BORROW-CANCEL] unit#%d setBorrowedForGameVehicle(false) ok=%s msg=%s -> isBorrowedByPlayer=%s presence.owner=%s",
					idx, tostring(ok), tostring(msg), tostring(ia.isBorrowedByPlayer),
					tostring(ia.presenceState ~= nil and ia.presenceState.owner)
				), session.neighbour, ia, nil)
			else
				IAprintDebug("IAMissionBorrow.unborrowSessionUnits()", string.format(
					"[BORROW-CANCEL] unit#%d SKIPPED setBorrowedForGameVehicle (vehicle=%s access=%s) -> hotspots NOT removed via live path",
					idx, hasVehicle and "present" or "NIL", hasAccess and "ok" or "missing"
				), session.neighbour, ia, nil)
			end
		end
	end
end

function IAMissionBorrow.countRunningMissionsInSession(session, excludeMission)
	if session == nil or session.missions == nil then
		return 0
	end
	local n = 0
	for _, m in ipairs(session.missions) do
		if m ~= nil and m ~= excludeMission and m.status ~= nil and MissionStatus ~= nil then
			if m.status == MissionStatus.RUNNING or m.status == MissionStatus.PREPARING or m.status == MissionStatus.CREATED then
				n = n + 1
			end
		end
	end
	return n
end

function IAMissionBorrow.resolveNeighbourDisplayName(session, mission)
	local who = nil
	if session ~= nil then
		who = session.neighbourName
		if who == nil or tostring(who) == "" then
			who = session.neighbour ~= nil and session.neighbour.name or nil
		end
	end
	if (who == nil or tostring(who) == "") and mission ~= nil then
		who = mission.iaFoSNeighbourFirstName
	end
	if who == nil or tostring(who) == "" then
		if g_i18n ~= nil and g_i18n.getText ~= nil then
			who = g_i18n:getText("ia_field_outcome_neighbour_generic")
		else
			who = "your neighbour"
		end
	end
	return tostring(who)
end

function IAMissionBorrow.resolveBorrowReturnDebugPlace(ia)
	if ia == nil or IAEquipmentPresence == nil or IAEquipmentPresence.State == nil or IAEquipmentPresence.State.getReservedParkingPlaceId == nil then
		return nil
	end
	local placeId = IAEquipmentPresence.State.getReservedParkingPlaceId(ia)
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

function IAMissionBorrow.resolveBorrowReturnDebugPose(ia)
	local place = IAMissionBorrow.resolveBorrowReturnDebugPlace(ia)
	if place ~= nil and place.x ~= nil and place.z ~= nil then
		return place, place.x, place.y, place.z, place.rotation or 0
	end
	if IABorrowAccess ~= nil and IABorrowAccess.getReturnWorldPose ~= nil then
		local x, z, pose = IABorrowAccess.getReturnWorldPose(ia)
		if x ~= nil and z ~= nil then
			local y = pose ~= nil and pose.y or nil
			local rot = pose ~= nil and pose.rotation or 0
			return nil, x, y, z, rot
		end
	end
	return nil, nil, nil, nil, nil
end

function IAMissionBorrow.getDebugMarkerY(x, y, z, lift)
	local yy = y
	if yy == nil and g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil and x ~= nil and z ~= nil then
		yy = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
	end
	return (yy or 0) + (lift or 0.2)
end

--- Resolve a friendly display name for a borrowed unit (engine getFullName preferred, falls back to mod-side fields).
function IAMissionBorrow.resolveBorrowedVehicleDisplayName(ia)
	local name = nil
	if ia ~= nil then
		if ia.vehicle ~= nil and type(ia.vehicle.getFullName) == "function" then
			pcall(function() name = ia.vehicle:getFullName() end)
		end
		if name == nil or tostring(name) == "" then
			name = ia.vehicleName
		end
		if name == nil or tostring(name) == "" then
			name = ia.xmlFilename
		end
	end
	if name == nil or tostring(name) == "" then
		return "borrowed vehicle"
	end
	return tostring(name)
end

--- Build box geometry (4 corners + label center) for a borrowed unit's return/pickup pose. Drawn per-frame as
-- line segments by drawSessionReturnDebugBoxes (mirrors field-border debug style) - no persistent scene nodes,
-- no center dot, no corner dots. Label uses the vehicle's display name.
function IAMissionBorrow.addBorrowReturnDebugMarker(session, ia, place, x, y, z, rotation)
	if session == nil or x == nil or z == nil or getWorldPositionFromYawLocalOffset == nil or IANeighbours == nil then
		return
	end

	local withVehicle = true
	if place ~= nil then
		withVehicle = place.withVehicle == true
	end
	local withAttachment = place ~= nil and place.withAttachment == true or false
	local sizeType = place ~= nil and place.sizeType or nil
	-- Shared box geometry (single source of truth, also used by map-init place debug boxes).
	if IAHelper_computePlaceDebugBoxCorners == nil then
		return
	end
	local corners = IAHelper_computePlaceDebugBoxCorners(x, y, z, rotation or 0, withVehicle, withAttachment, sizeType, 0.25)
	if corners == nil then
		return
	end

	session.iaReturnDebugBoxes = session.iaReturnDebugBoxes or {}
	session.iaReturnDebugBoxes[#session.iaReturnDebugBoxes + 1] = {
		label = IAMissionBorrow.resolveBorrowedVehicleDisplayName(ia),
		centerX = x,
		centerY = IAMissionBorrow.getDebugMarkerY(x, y, z, 0.25),
		centerZ = z,
		corners = corners,
	}
end

function IAMissionBorrow.clearSessionReturnDebugMarkers(session)
	if session == nil then
		return
	end
	-- Legacy: pre-line-refactor sessions stored persistent debug scene nodes; clean any leftovers.
	if session.iaReturnDebugPointNodes ~= nil then
		if IANeighbours ~= nil and IANeighbours.removeDebugPointNode ~= nil then
			for _, node in ipairs(session.iaReturnDebugPointNodes) do
				IANeighbours:removeDebugPointNode(node)
			end
		end
		session.iaReturnDebugPointNodes = nil
	end
	session.iaReturnDebugBoxes = nil
end

--- True iff at least one mission in the session is in the "return expected" state, i.e. probe evaluation
-- finished (= contract completed) and the borrow has not been satisfied yet. This is the same condition
-- syncMissionBorrowReturnPending uses to flip iaFoSBorrowReturnPending true and to trigger the
-- "ia_mission_borrow_return_to_farm" notification, so the player only sees the return boxes once the game
-- has actually told them to return the equipment.
function IAMissionBorrow.isSessionAwaitingReturn(session)
	if session == nil or session.missions == nil then
		return false
	end
	for _, mission in ipairs(session.missions) do
		if mission ~= nil and mission.iaFoSBorrowReturnPending == true then
			return true
		end
	end
	return false
end

--- Draw all return/pickup boxes for a session as line segments + a single label at center (no point dots).
-- Matches field-border debug rendering: per-frame drawDebugLine in neutral gray, label via Utils.renderTextAtWorldPosition.
-- Applies the same 50 m draw-range filter used by IANeighbours.debugPoints rendering.
-- Gated on isSessionAwaitingReturn so the box only appears once the contract is "completed" (return expected).
function IAMissionBorrow.drawSessionReturnDebugBoxes(session)
	if session == nil or session.iaReturnDebugBoxes == nil or drawDebugLine == nil then
		return
	end
	if not IAMissionBorrow.isSessionAwaitingReturn(session) then
		return
	end
	local refX, refY, refZ = nil, nil, nil
	if g_localPlayer ~= nil then
		local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
		if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) then
			refX, refY, refZ = getWorldTranslation(v.rootNode)
		end
		if refX == nil and g_localPlayer.getPosition ~= nil then
			refX, refY, refZ = g_localPlayer:getPosition()
		end
	end
	local rangeSq = 50 * 50
	for _, box in ipairs(session.iaReturnDebugBoxes) do
		local inRange = true
		if refX ~= nil and refY ~= nil and refZ ~= nil and box.centerX ~= nil and box.centerZ ~= nil then
			local dx, dy, dz = box.centerX - refX, (box.centerY or 0) - refY, box.centerZ - refZ
			inRange = (dx * dx + dy * dy + dz * dz) <= rangeSq
		end
		if inRange then
			local n = #box.corners
			for i = 1, n do
				local a = box.corners[i]
				local b = box.corners[(i % n) + 1]
				if a ~= nil and b ~= nil then
					drawDebugLine(a.x, a.y, a.z, 50, 50, 50, b.x, b.y, b.z, 50, 50, 50)
				end
			end
			if box.label ~= nil and box.label ~= "" and Utils ~= nil and Utils.renderTextAtWorldPosition ~= nil and getCorrectTextSize ~= nil then
				Utils.renderTextAtWorldPosition(box.centerX, (box.centerY or 0) + 0.25, box.centerZ, box.label, getCorrectTextSize(0.012), 0)
			end
		end
	end
end

function IAMissionBorrow.drawAllSessionReturnDebugBoxes()
	for _, session in pairs(IAMissionBorrow.sessions or {}) do
		IAMissionBorrow.drawSessionReturnDebugBoxes(session)
	end
end

--- Always-on player aid: marker box at every borrowed unit's return/pickup place. The 50 m draw-range filter in IANeighbours.update handles "only when player is nearby" visibility.
function IAMissionBorrow.refreshSessionReturnDebugMarkers(session)
	if session == nil then
		return
	end
	IAMissionBorrow.clearSessionReturnDebugMarkers(session)
	if IANeighbours == nil then
		return
	end
	local seen = {}
	for _, ia in ipairs(session.borrowedUnits or {}) do
		local place, x, y, z, rotation = IAMissionBorrow.resolveBorrowReturnDebugPose(ia)
		if x ~= nil and z ~= nil then
			local key = place ~= nil and place.id ~= nil and ("place_" .. tostring(place.id)) or string.format("pos_%.1f_%.1f", x, z)
			if seen[key] ~= true then
				seen[key] = true
				IAMissionBorrow.addBorrowReturnDebugMarker(session, ia, place, x, y, z, rotation)
			end
		end
	end
end

function IAMissionBorrow.syncReturnDebugMarkersForAllSessions()
	for _, session in pairs(IAMissionBorrow.sessions or {}) do
		IAMissionBorrow.refreshSessionReturnDebugMarkers(session)
	end
end

function IAMissionBorrow.showFormattedIngameNotification(i18nKey, session, mission, notificationType)
	if g_currentMission == nil or g_currentMission.addIngameNotification == nil or g_i18n == nil or FSBaseMission == nil then
		return
	end
	local who = IAMissionBorrow.resolveNeighbourDisplayName(session, mission)
	local text = string.format(g_i18n:getText(i18nKey), who)
	local ntype = notificationType or FSBaseMission.INGAME_NOTIFICATION_OK
	g_currentMission:addIngameNotification(ntype, text)
end

function IAMissionBorrow.syncMissionBorrowReturnPending(mission)
	if mission == nil or mission.iaFoSUsesBorrowedEquipment ~= true then
		return
	end
	local wasPending = mission.iaFoSBorrowReturnPending == true
	if mission.iaProbeEvalAllFinished == true and mission.iaFoSBorrowReturnSatisfied ~= true then
		mission.iaFoSBorrowReturnPending = true
		if not wasPending and mission.iaFoSBorrowReturnNotified ~= true then
			mission.iaFoSBorrowReturnNotified = true
			local session = IAMissionBorrow.getSession(mission.iaFoSMissionBorrowSessionId)
			IAMissionBorrow.showFormattedIngameNotification("ia_mission_borrow_return_to_farm", session, mission, FSBaseMission.INGAME_NOTIFICATION_OK)
		end
	else
		mission.iaFoSBorrowReturnPending = false
	end
end

function IAMissionBorrow.finishProbeCompleteMissionsInSession(session)
	if session == nil or session.missions == nil then
		return
	end
	for _, mission in ipairs(session.missions) do
		if mission ~= nil
			and mission.iaFoSUsesBorrowedEquipment == true
			and mission.iaProbeEvalAllFinished == true
			and mission.status == MissionStatus.RUNNING
		then
			mission.iaFoSBorrowReturnPending = false
			mission.iaFoSBorrowReturnSatisfied = true
			if type(mission.finish) == "function" and MissionFinishState ~= nil then
				mission:finish(MissionFinishState.SUCCESS)
			end
		end
	end
end

function IAMissionBorrow.endSession(sessionId, unborrow)
	local session = IAMissionBorrow.getSession(sessionId)
	if session == nil then
		IAprintDebug("IAMissionBorrow.endSession()", string.format(
			"[BORROW-CANCEL] sessionId=%s NOT FOUND -> nothing to end",
			tostring(sessionId)
		), nil, nil, nil)
		return
	end
	IAprintDebug("IAMissionBorrow.endSession()", string.format(
		"[BORROW-CANCEL] entry sessionId=%s unborrow=%s units=%d missions=%d",
		tostring(sessionId), tostring(unborrow),
		session.borrowedUnits ~= nil and #session.borrowedUnits or 0,
		session.missions ~= nil and #session.missions or 0
	), session.neighbour, nil, nil)
	IAMissionBorrow.clearSessionReturnDebugMarkers(session)
	if unborrow == true then
		IAMissionBorrow.unborrowSessionUnits(session)
	else
		IAprintDebug("IAMissionBorrow.endSession()", "[BORROW-CANCEL] unborrow=false -> session removed but units left borrowed", session.neighbour, nil, nil)
	end
	IAMissionBorrow.sessions[tostring(sessionId)] = nil
	IAprintDebug("IAMissionBorrow.endSession()", string.format(
		"[BORROW-CANCEL] sessionId=%s removed from IAMissionBorrow.sessions",
		tostring(sessionId)
	), session.neighbour, nil, nil)
end

-- quiet=true suppresses the no-op diagnostic logs (remainingActive / KEEP / NOT FOUND).
-- The per-frame updateSession sweep passes quiet=true to avoid spamming the log every frame;
-- event-driven callers (onMissionEnded) leave it nil for full BORROW-CANCEL diagnostics.
-- The "actually end session" branch always logs regardless of quiet.
function IAMissionBorrow.tryEndSessionIfNoActiveMissions(sessionId, excludeMission, quiet)
	local session = IAMissionBorrow.getSession(sessionId)
	if session == nil then
		if not quiet then
			IAprintDebug("IAMissionBorrow.tryEndSessionIfNoActiveMissions()", string.format(
				"[BORROW-CANCEL] sessionId=%s NOT FOUND -> nothing to end",
				tostring(sessionId)
			), nil, nil, nil)
		end
		return
	end
	local n = IAMissionBorrow.countRunningMissionsInSession(session, excludeMission)
	if not quiet then
		IAprintDebug("IAMissionBorrow.tryEndSessionIfNoActiveMissions()", string.format(
			"[BORROW-CANCEL] sessionId=%s remainingActive=%d excludeMissionUid=%s",
			tostring(sessionId), n,
			tostring(excludeMission ~= nil and rawget(excludeMission, "uniqueId") or nil)
		), session.neighbour, nil, nil)
	end
	if n > 0 then
		if not quiet then
			IAprintDebug("IAMissionBorrow.tryEndSessionIfNoActiveMissions()", string.format(
				"[BORROW-CANCEL] sessionId=%s KEEP (%d other mission(s) still active) -> hotspots stay until those finish",
				tostring(sessionId), n
			), session.neighbour, nil, nil)
		end
		return
	end
	IAprintDebug("IAMissionBorrow.tryEndSessionIfNoActiveMissions()", string.format(
		"[BORROW-CANCEL] sessionId=%s no other active missions -> calling endSession(unborrow=true)",
		tostring(sessionId)
	), session.neighbour, nil, nil)
	IAMissionBorrow.endSession(sessionId, true)
end

--- @param IANeighbour neighbour
-- @param table missions array of IAFieldOutcomeMission
-- @param table borrowedUnits array of IANeighbourVehicle
-- @param table|nil openList open fieldwork rows (seed indices)
-- @param string|nil fixedSessionId optional session id (save restore)
-- @return string|nil sessionId
function IAMissionBorrow.startSession(neighbour, missions, borrowedUnits, openList, fixedSessionId)
	if not IAMissionBorrow.isActive() or neighbour == nil or borrowedUnits == nil or #borrowedUnits == 0 then
		return nil
	end
	local isRestore = fixedSessionId ~= nil and tostring(fixedSessionId) ~= ""
	local sessionId = isRestore and tostring(fixedSessionId) or IAMissionBorrow.makeSessionId(neighbour.id)
	local seedByUid = {}
	if openList ~= nil then
		for _, row in ipairs(openList) do
			local seedIdx = IAMissionBorrow.resolveSeedIndexForOpenRow(row)
			if seedIdx ~= nil then
				local h = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
				if h ~= nil and row.config ~= nil then
					local resolved = h:resolveMissionAttachmentsForConfig(neighbour, row.config)
					if resolved ~= nil then
						for _, ia in ipairs({ resolved.attachmentBack, resolved.attachmentFront }) do
							-- Weight attachments are not borrowed for fieldwork contracts (see
							-- IAGameLoopHelper:collectMissionBorrowUnitsForOpenList), so skip them
							-- here too to keep seedByUid aligned with the actual borrowedUnits set.
							if ia ~= nil and ia.uniqueId ~= nil and not h:iaVehicleHasWeightCategory(ia) then
								seedByUid[tostring(ia.uniqueId)] = seedIdx
							end
						end
					end
				end
			end
		end
	end
	local neighbourName = neighbour.name
	if neighbourName == nil or tostring(neighbourName) == "" then
		neighbourName = missions ~= nil and missions[1] ~= nil and missions[1].iaFoSNeighbourFirstName or nil
	end
	local session = {
		id = sessionId,
		neighbour = neighbour,
		neighbourId = neighbour.id,
		neighbourName = neighbourName,
		missions = missions or {},
		borrowedUnits = {},
		emptyNotified = false,
		seedByUid = seedByUid,
	}
	-- Build set of all borrow uids so swaps don't pick another borrow unit as victim.
	local borrowUidSet = {}
	for _, ia in ipairs(borrowedUnits) do
		if ia ~= nil and ia.uniqueId ~= nil then
			borrowUidSet[tostring(ia.uniqueId)] = true
		end
	end
	local hb = IANeighbours ~= nil and IANeighbours.gameLoopHelper ~= nil and IANeighbours.gameLoopHelper.homebaseParking or nil
	for _, ia in ipairs(borrowedUnits) do
		if ia ~= nil then
			-- Borrow needs a homebase place to anchor return / yard hotspot. If the implement is
			-- not visible at homebase, swap it in by hiding a spawned sibling at a compatible slot.
			if hb ~= nil and type(hb.swapHomebasePlaceWithSpawnedSiblingForBorrow) == "function" then
				pcall(function()
					hb:swapHomebasePlaceWithSpawnedSiblingForBorrow(neighbour, ia, borrowUidSet)
				end)
			end
			table.insert(session.borrowedUnits, ia)
			if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil and IAEquipmentPresence.State.snapshotBorrowPlaces ~= nil then
				IAEquipmentPresence.State.snapshotBorrowPlaces(ia)
			end
			if ia.vehicle ~= nil and IABorrowAccess ~= nil and IABorrowAccess.setBorrowedForGameVehicle ~= nil then
				IABorrowAccess.setBorrowedForGameVehicle(ia.vehicle, true)
			end
			-- Equipment is left empty on borrow — the player fills it from the NPC silo.
		end
	end
	if missions ~= nil then
		for _, mission in ipairs(missions) do
			if mission ~= nil then
				mission.iaFoSUsesBorrowedEquipment = true
				mission.iaFoSMissionBorrowSessionId = sessionId
				mission.iaFoSNeighbourId = neighbour.id
				IAMissionBorrow.syncMissionBorrowReturnPending(mission)
			end
		end
	end
	IAMissionBorrow.sessions[sessionId] = session
	IAMissionBorrow.refreshSessionReturnDebugMarkers(session)
	-- Initial consumable silo fill on borrow: top up the NPC silo with the required
	-- consumable (lime, fertilizer, slurry, herbicide, seeds, manure) so the player
	-- can immediately load their borrowed implement.
	if missions ~= nil and IAFieldOutcomeMission ~= nil and IAFieldOutcomeMission.getConsumableFillTypeForJob ~= nil then
		for _, mission in ipairs(missions) do
			if mission ~= nil and type(mission.iaGetNeighbourSilo) == "function" and type(mission.iaRefillSiloConsumable) == "function" then
				local jt = IAFieldwork.normalizeFieldworkJobType(tostring(mission.iaFoSFieldworkJob or ""))
			local consumableFt = nil
			if IAFieldOutcomeMission.CONSUMABLE_JOB_FILL_TYPES[jt] ~= nil or jt == "seed" then
				consumableFt = IAFieldOutcomeMission.getConsumableFillTypeForJob(jt, mission)
			end
				if consumableFt ~= nil then
					local silo = mission:iaGetNeighbourSilo()
					if silo ~= nil then
						mission:iaRefillSiloConsumable(silo, consumableFt)
					end
				end
			end
		end
	end
	IAprintDebug("IAMissionBorrow.startSession()", string.format(
		"id=%s units=%d missions=%d",
		tostring(sessionId), #session.borrowedUnits, #session.missions
	), neighbour, nil, nil)
	return sessionId
end

function IAMissionBorrow.onMissionEnded(mission, _success)
	if mission == nil then
		IAprintDebug("IAMissionBorrow.onMissionEnded()", "[BORROW-CANCEL] mission=nil -> noop", nil, nil, nil)
		return
	end
	local sessionId = mission.iaFoSMissionBorrowSessionId
	IAprintDebug("IAMissionBorrow.onMissionEnded()", string.format(
		"[BORROW-CANCEL] entry success=%s missionUid=%s status=%s sessionId=%s usesBorrowed=%s pending=%s",
		tostring(_success), tostring(rawget(mission, "uniqueId")), tostring(mission.status),
		tostring(sessionId), tostring(mission.iaFoSUsesBorrowedEquipment),
		tostring(mission.iaFoSBorrowReturnPending)
	), nil, nil, nil)
	if sessionId == nil then
		IAprintDebug("IAMissionBorrow.onMissionEnded()", "[BORROW-CANCEL] sessionId=nil -> nothing to clean (mission was not borrow-tied)", nil, nil, nil)
		return
	end
	mission.iaFoSBorrowReturnPending = false
	IAMissionBorrow.tryEndSessionIfNoActiveMissions(sessionId, mission)
end

function IAMissionBorrow.isFillUnitNearlyEmpty(vehicle, fillUnitIndex)
	if vehicle == nil or fillUnitIndex == nil then
		return false
	end
	if vehicle.getFillUnitFillLevel == nil or vehicle.getFillUnitCapacity == nil then
		return false
	end
	local okL, level = pcall(vehicle.getFillUnitFillLevel, vehicle, fillUnitIndex)
	local okC, cap = pcall(vehicle.getFillUnitCapacity, vehicle, fillUnitIndex)
	if not okL or not okC or cap == nil or cap <= 0 then
		return false
	end
	return (level or 0) < math.min(IAMissionBorrow.EMPTY_FILL_THRESHOLD, cap * 0.02)
end

function IAMissionBorrow.isBorrowedImplementNearlyEmpty(ia)
	local gv = ia ~= nil and ia.vehicle or nil
	if gv == nil then
		return false
	end
	local cat = ia.category ~= nil and string.lower(tostring(ia.category)) or ""
	if cat == "sprayer" or cat == "manure spreader" then
		if gv.getSprayerFillUnitIndex ~= nil then
			local ok, idx = pcall(gv.getSprayerFillUnitIndex, gv)
			if ok and idx ~= nil and IAMissionBorrow.isFillUnitNearlyEmpty(gv, idx) then
				return true
			end
		end
	end
	if cat == "seeder" and gv.spec_fillUnit ~= nil and gv.spec_fillUnit.fillUnits ~= nil then
		for fillUnitIndex, _ in pairs(gv.spec_fillUnit.fillUnits) do
			if IAMissionBorrow.isFillUnitNearlyEmpty(gv, fillUnitIndex) then
				return true
			end
		end
	end
	return false
end

--- Per-unit diagnostic snapshot used by the "stuck near completion" log. Captures everything that gates `allReturned` so a stuck mission immediately reveals which unit and which condition is blocking.
function IAMissionBorrow.describeUnitReturnState(ia)
	if ia == nil then
		return "ia=nil"
	end
	local uid = ia.uniqueId or "?"
	local name = ia.vehicleName or ia.xmlFilename or "?"
	local cat = ia.category or "?"
	local unattached = IAMissionBorrow.isVehicleUnattached(ia)
	local nearReturn = IAMissionBorrow.isNearReturnPose(ia, IAMissionBorrow.RETURN_RADIUS_M)
	local tx, tz = nil, nil
	if IABorrowAccess ~= nil and IABorrowAccess.getReturnWorldPose ~= nil then
		tx, tz = IABorrowAccess.getReturnWorldPose(ia)
	end
	local vx, vz = IAMissionBorrow.getVehicleWorldXZ(ia)
	local dist = nil
	if tx ~= nil and vx ~= nil then
		local dx, dz = vx - tx, vz - tz
		dist = math.sqrt(dx * dx + dz * dz)
	end
	local attacher = "nil"
	if ia.vehicle ~= nil and type(ia.vehicle.getAttacherVehicle) == "function" then
		local okA, att = pcall(ia.vehicle.getAttacherVehicle, ia.vehicle)
		if okA and att ~= nil then
			attacher = tostring(att.configFileName or att.typeName or "vehicle")
		end
	end
	local hint = ""
	if not unattached then
		hint = " (BLOCKED: still hitched, detach implement)"
	elseif not nearReturn then
		if tx == nil then
			hint = " (BLOCKED: return pose unresolved -> IABorrowAccess.getReturnWorldPose returned nil)"
		else
			hint = string.format(" (BLOCKED: outside %dm of return slot)", IAMissionBorrow.RETURN_RADIUS_M)
		end
	end
	return string.format(
		"uid=%s name=%s cat=%s unattached=%s(attacher=%s) nearReturn=%s dist=%s/%dm target=%s,%s pos=%s,%s%s",
		tostring(uid), tostring(name), tostring(cat),
		tostring(unattached), attacher,
		tostring(nearReturn),
		dist ~= nil and string.format("%.1f", dist) or "nil",
		IAMissionBorrow.RETURN_RADIUS_M,
		tx ~= nil and string.format("%.1f", tx) or "nil",
		tz ~= nil and string.format("%.1f", tz) or "nil",
		vx ~= nil and string.format("%.1f", vx) or "nil",
		vz ~= nil and string.format("%.1f", vz) or "nil",
		hint
	)
end

--- Log once per state-change when the session has at least one probe-complete mission but allReturned is false (the player did all the field work but the borrow return condition still blocks completion).
function IAMissionBorrow.logSessionStuckIfNeeded(session, anyProbeDone, allReturned)
	if session == nil then
		return
	end
	if not anyProbeDone or allReturned then
		if session._iaStuckLogDigest ~= nil then
			IAprintDebug("IAMissionBorrow.logSessionStuckIfNeeded()", string.format(
				"session id=%s no longer stuck (allReturned=%s anyProbeDone=%s)",
				tostring(session.id), tostring(allReturned), tostring(anyProbeDone)
			), session.neighbour, nil, nil)
			session._iaStuckLogDigest = nil
		end
		return
	end
	local parts = {}
	for _, ia in ipairs(session.borrowedUnits or {}) do
		if ia ~= nil then
			table.insert(parts, IAMissionBorrow.describeUnitReturnState(ia))
		end
	end
	local digest = table.concat(parts, " | ")
	if session._iaStuckLogDigest == digest then
		return
	end
	session._iaStuckLogDigest = digest
	IAprintDebug("IAMissionBorrow.logSessionStuckIfNeeded()", string.format(
		"session id=%s STUCK: probes complete but allReturned=false (%d unit%s):",
		tostring(session.id), #parts, #parts == 1 and "" or "s"
	), session.neighbour, nil, nil)
	for i, line in ipairs(parts) do
		IAprintDebug("IAMissionBorrow.logSessionStuckIfNeeded()", string.format("  #%d %s", i, line), session.neighbour, nil, nil)
	end
end

function IAMissionBorrow.updateSession(session, dt)
	if session == nil then
		return
	end
	local allReturned = true
	local anyNearReturn = false
	for _, ia in ipairs(session.borrowedUnits) do
		if ia ~= nil then
			if IAMissionBorrow.isNearReturnPose(ia, IAMissionBorrow.REFILL_RADIUS_M) then
				anyNearReturn = true
				-- Equipment is NOT auto-refilled near parking spot — player fills from silo.
			end
			if not (IAMissionBorrow.isVehicleUnattached(ia) and IAMissionBorrow.isNearReturnPose(ia, IAMissionBorrow.RETURN_RADIUS_M)) then
				allReturned = false
			end
		end
	end
	if not session.emptyNotified and not anyNearReturn then
		for _, ia in ipairs(session.borrowedUnits) do
			if IAMissionBorrow.isBorrowedImplementNearlyEmpty(ia) then
				session.emptyNotified = true
				IAMissionBorrow.showFormattedIngameNotification("ia_mission_borrow_refill_at_farm", session, nil, FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
				break
			end
		end
	end
	local anyProbeDone = false
	if session.missions ~= nil then
		for _, mission in ipairs(session.missions) do
			if mission ~= nil and mission.iaProbeEvalAllFinished == true and mission.status == MissionStatus.RUNNING then
				anyProbeDone = true
				break
			end
		end
	end
	IAMissionBorrow.logSessionStuckIfNeeded(session, anyProbeDone, allReturned)
	if allReturned and anyProbeDone and #session.borrowedUnits > 0 then
		IAMissionBorrow.finishProbeCompleteMissionsInSession(session)
	end
	if session.missions ~= nil then
		for _, mission in ipairs(session.missions) do
			IAMissionBorrow.syncMissionBorrowReturnPending(mission)
		end
	end
	IAMissionBorrow.tryEndSessionIfNoActiveMissions(session.id, nil, true)
end

function IAMissionBorrow.update(dt)
	if not IAMissionBorrow.isActive() then
		return
	end
	for sessionId, session in pairs(IAMissionBorrow.sessions) do
		IAMissionBorrow.updateSession(session, dt)
	end
	IAMissionBorrow.drawAllSessionReturnDebugBoxes()
end

--- Restore borrow session after load when missions were saved with usesBorrowedEquipment.
-- Failure branches are logged unconditionally: a silently-skipped restore leaves any borrowed-equipment mission permanently stuck at 99% (iaFoSBorrowReturnPending stays true with no live session to clear it).
function IAMissionBorrow.tryRestoreSessionForNeighbour(neighbour, missions)
	local nName = neighbour ~= nil and tostring(neighbour.name or neighbour.id or "?") or "nil"
	local nMissions = missions ~= nil and #missions or 0
	if not IAMissionBorrow.isActive() then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: borrow system inactive (IABorrowAccess.isBorrowSystemActive()=false) neighbour=%s missions=%d -> field-outcome missions with usesBorrowedEquipment will stay at 99%%", nName, nMissions), neighbour, nil, nil)
		return
	end
	if neighbour == nil then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: neighbour=nil missions=%d", nMissions), nil, nil, nil)
		return
	end
	if missions == nil or nMissions == 0 then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: no missions for neighbour=%s", nName), neighbour, nil, nil)
		return
	end
	local units = {}
	local seen = {}
	local sawBorrowMission = false
	local helperMissing = false
	local vehiclesMissing = false
	local nVehiclesScanned = 0
	for _, mission in ipairs(missions) do
		if mission ~= nil and mission.iaFoSUsesBorrowedEquipment == true then
			sawBorrowMission = true
			local h = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
			if h == nil then
				helperMissing = true
			elseif neighbour.vehicles == nil then
				vehiclesMissing = true
			else
				for _, ia in pairs(neighbour.vehicles) do
					nVehiclesScanned = nVehiclesScanned + 1
					if ia ~= nil and ia.isBorrowedByPlayer == true and ia.uniqueId ~= nil and not seen[tostring(ia.uniqueId)] then
						seen[tostring(ia.uniqueId)] = true
						table.insert(units, ia)
					end
				end
			end
			break
		end
	end
	if not sawBorrowMission then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: neighbour=%s has %d restored mission(s) but none has iaFoSUsesBorrowedEquipment=true", nName, nMissions), neighbour, nil, nil)
		return
	end
	if helperMissing then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: IANeighbours.gameLoopHelper=nil at restore time for neighbour=%s -> mission(s) will stay at 99%%", nName), neighbour, nil, nil)
		return
	end
	if vehiclesMissing then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: neighbour=%s has no .vehicles table at restore time -> mission(s) will stay at 99%%", nName), neighbour, nil, nil)
		return
	end
	if #units == 0 then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: no vehicles with isBorrowedByPlayer=true found for neighbour=%s (scanned %d vehicles). Either the borrow flag was not restored from XML or the unit was unborrowed before save -> mission(s) will stay at 99%%", nName, nVehiclesScanned), neighbour, nil, nil)
		return
	end
	local sessionId = missions[1].iaFoSMissionBorrowSessionId
	if sessionId == nil or sessionId == "" then
		sessionId = IAMissionBorrow.makeSessionId(neighbour.id)
	end
	if IAMissionBorrow.getSession(sessionId) ~= nil then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("SKIPPED: session already exists id=%s neighbour=%s", tostring(sessionId), nName), neighbour, nil, nil)
		return
	end
	local newId = IAMissionBorrow.startSession(neighbour, missions, units, nil, sessionId)
	if newId == nil then
		IAprintDebug("IAMissionBorrow.tryRestoreSessionForNeighbour()", string.format("FAILED: startSession returned nil for neighbour=%s sessionId=%s units=%d missions=%d -> mission(s) will stay at 99%%", nName, tostring(sessionId), #units, nMissions), neighbour, nil, nil)
	end
end
