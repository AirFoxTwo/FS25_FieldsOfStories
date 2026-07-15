-- IAHelper.lua — library of global functions (IAHelper_* and other globals). Not a Class / not an IAHelper {} method table.
-- Neighbour PlaceableHotspot overlays (IANeighbours.registerNpcMapHotspotTexture): main map icon + small variant.
IA_NPC_MAP_OVERLAY_SLICE = IA_NPC_MAP_OVERLAY_SLICE or "iaFosNpc.npc"
IA_NPC_MAP_OVERLAY_SLICE_SMALL = IA_NPC_MAP_OVERLAY_SLICE_SMALL or "iaFosNpcSm.npc"
-- Borrow yard marker (IABorrowAccess.registerBorrowMapHotspotTexture): images/mapicon_borrow.dds
IA_BORROW_MAP_OVERLAY_SLICE = IA_BORROW_MAP_OVERLAY_SLICE or "iaFosBorrow.borrow"

--- @return boolean true if hotspot was registered with the mission/HUD
function iaAddMapHotspotToMission(hotspot)
	if g_currentMission == nil or hotspot == nil then
		IAprintDebug("iaAddMapHotspotToMission()", string.format(
			"[HOTSPOT] ADD skipped (g_currentMission=%s hotspot=%s)",
			tostring(g_currentMission ~= nil), tostring(hotspot ~= nil)
		), nil, nil, nil)
		return false
	end
	local label = tostring(hotspot.name ~= nil and hotspot:getName() or hotspot)
	if g_currentMission.addMapHotspot ~= nil then
		g_currentMission:addMapHotspot(hotspot)
		IAprintDebug("iaAddMapHotspotToMission()", string.format(
			"[HOTSPOT] ADD ok via g_currentMission:addMapHotspot name=%s isADMarker=%s neighbourMarker=%s yardMarker=%s yardPlaceKey=%s",
			label, tostring(hotspot.isADMarker), tostring(hotspot.iaFosNeighbourMarker),
			tostring(hotspot.iaFosBorrowYardMarker), tostring(hotspot.iaFosBorrowYardPlaceKey)
		), nil, nil, nil)
		return true
	end
	if g_currentMission.hud ~= nil and g_currentMission.hud.addMapHotspot ~= nil then
		g_currentMission.hud:addMapHotspot(hotspot)
		IAprintDebug("iaAddMapHotspotToMission()", string.format(
			"[HOTSPOT] ADD ok via g_currentMission.hud:addMapHotspot name=%s",
			label
		), nil, nil, nil)
		return true
	end
	IAprintDebug("iaAddMapHotspotToMission()", string.format(
		"[HOTSPOT] ADD FAILED no addMapHotspot on mission/hud name=%s", label
	), nil, nil, nil)
	return false
end

function iaRemoveMapHotspotFromMission(hotspot)
	if g_currentMission == nil or hotspot == nil then
		IAprintDebug("iaRemoveMapHotspotFromMission()", string.format(
			"[HOTSPOT] REMOVE skipped (g_currentMission=%s hotspot=%s)",
			tostring(g_currentMission ~= nil), tostring(hotspot ~= nil)
		), nil, nil, nil)
		return
	end
	local label = tostring(hotspot.name ~= nil and hotspot:getName() or hotspot)
	if g_currentMission.removeMapHotspot ~= nil then
		g_currentMission:removeMapHotspot(hotspot)
		IAprintDebug("iaRemoveMapHotspotFromMission()", string.format(
			"[HOTSPOT] REMOVE ok via g_currentMission:removeMapHotspot name=%s yardPlaceKey=%s",
			label, tostring(hotspot.iaFosBorrowYardPlaceKey)
		), nil, nil, nil)
	elseif g_currentMission.hud ~= nil and g_currentMission.hud.removeMapHotspot ~= nil then
		g_currentMission.hud:removeMapHotspot(hotspot)
		IAprintDebug("iaRemoveMapHotspotFromMission()", string.format(
			"[HOTSPOT] REMOVE ok via g_currentMission.hud:removeMapHotspot name=%s",
			label
		), nil, nil, nil)
	else
		IAprintDebug("iaRemoveMapHotspotFromMission()", string.format(
			"[HOTSPOT] REMOVE FAILED no removeMapHotspot on mission/hud name=%s", label
		), nil, nil, nil)
	end
end

--- Recursively set visibility on an i3d node and all descendants (skips nil / 0).
function iaSetNodeSubtreeVisible(nodeId, visible)
	local vis = visible ~= false
	if nodeId == nil or nodeId == 0 then
		return
	end
	setVisibility(nodeId, vis)
	for i = 0, getNumOfChildren(nodeId) - 1 do
		iaSetNodeSubtreeVisible(getChildAt(nodeId, i), vis)
	end
end

-- Debug print helper: method name + optional neighbour (id, name), vehicle (id, name), situation (id, intent).
-- Only prints when IANeighbours.debug is true.
-- @param string methodName - e.g. "IANeighbourVehicle:initialize()"
-- @param string message - Optional message to append after context
-- @param table neighbour - Optional IANeighbour (uses .id, .name)
-- @param table vehicle - Optional IANeighbourVehicle (uses .uniqueId, .vehicle:getFullName()) or vehicle object
-- @param table situation - Optional IASituation (uses .id, .config.intent)
function IAprintDebug(methodName, message, neighbour, vehicle, situation)
	if IANeighbours == nil or not IANeighbours.debug then
		return
	end
	local parts = { "--- ", tostring(methodName or "?") }
	if neighbour and type(neighbour) == "table" then
		local nid = neighbour.id ~= nil and tostring(neighbour.id) or "?"
		local nname = neighbour.name ~= nil and tostring(neighbour.name) or "?"
		parts[#parts + 1] = " | neighbour: " .. nid .. " " .. nname
	end
	if vehicle and type(vehicle) == "table" then
		local vid, vname = "?", "?"
		if vehicle.uniqueId ~= nil then
			vid = tostring(vehicle.uniqueId)
		end
		if vehicle.vehicle and type(vehicle.vehicle.getFullName) == "function" then
			vname = tostring(vehicle.vehicle:getFullName())
		elseif type(vehicle.getFullName) == "function" then
			vid = vid == "?" and "?" or vid
			vname = tostring(vehicle:getFullName())
		end
		parts[#parts + 1] = " | vehicle: " .. vid .. " " .. vname
	end
	if situation and type(situation) == "table" then
		local sid = situation.id ~= nil and tostring(situation.id) or "?"
		local intent = "?"
		if situation.config and situation.config.intent ~= nil then
			intent = tostring(situation.config.intent)
		elseif situation.intent ~= nil then
			intent = tostring(situation.intent)
		end
		parts[#parts + 1] = " | situation: " .. sid .. " " .. intent
	end
	if message ~= nil and tostring(message) ~= "" then
		parts[#parts + 1] = " - " .. tostring(message)
	end
	print(table.concat(parts))

	-- [FOS_TEST] bridge: feed into structured test log when a test is running
	if IATestRunner ~= nil and type(IATestRunner.emitDebug) == "function" then
		IATestRunner.emitDebug(methodName, message, neighbour, vehicle, situation)
	end
end

--- Run fn in pcall; on Lua error print when debug is enabled (IANeighbours.debug by default).
-- @param string label Full message prefix after "--- " (e.g. "IABorrowAccess.removeVehicleMapHotspot()")
-- @param function fn Zero-argument function
-- @param boolean|nil debugOverride If not nil, controls printing; if nil uses IANeighbours.debug when available
-- @return boolean ok True if pcall succeeded
function IAsafePcall(label, fn, debugOverride)
	if type(fn) ~= "function" then
		return false
	end
	local ok, err = pcall(fn)
	local doPrint = false
	if debugOverride ~= nil then
		doPrint = debugOverride == true
	else
		doPrint = IANeighbours ~= nil and IANeighbours.debug == true
	end
	if not ok and doPrint then
		print("--- " .. tostring(label) .. ": " .. tostring(err))
	end
	if ok then
		IAprintDebug(label, "success", nil, nil, nil)
	end
	return ok
end

--- Trim leading/trailing whitespace; nil-safe. Used by conversation XML parsing and voice catalog keys.
function IAtrim(s)
	if s == nil then
		return ""
	end
	return tostring(s):match("^%s*(.-)%s*$") or ""
end

--- Display language "de" or "en" for UI-facing strings (voice pack overrides game language when loaded).
--- For audio paths and any UI showing voice-pack-dependent content. Uses `getGameUiLanguageCode` when no voice pack is loaded
--- so the same source of truth as `g_i18n:getText()` is used.
--- @return string "de" or "en"
function getDisplayLanguageCode()
	--if IANeighbours ~= nil and IANeighbours.voicePackLoaded == true and IANeighbours.voicePackLanguage ~= nil and IANeighbours.voicePackLanguage ~= "" then
	--	return IANeighbours.voicePackLanguage
	--end

	if g_i18n ~= nil and g_i18n:getText("gui_language") ~= nil then
		return tostring(g_i18n:getText("gui_language"))
	end

	return "en"
end

function identifyAttachmentJoint(attachmentBack, vehicle)
    local attachmentJoint = nil
    local attachmentAttachIndex = nil
	local attachmentNode = nil
	local vehicleAttacherNode = nil

	if attachmentBack == nil or type(attachmentBack) ~= "table" or attachmentBack.spec_attachable == nil or attachmentBack.spec_attachable.inputAttacherJoints == nil then
		return nil, nil, nil, nil
	end
	if vehicle == nil or type(vehicle) ~= "table" or vehicle.spec_attacherJoints == nil or vehicle.spec_attacherJoints.attacherJoints == nil then
		return nil, nil, nil, nil
	end

    for i,v in pairs(attachmentBack.spec_attachable.inputAttacherJoints) do
        --print("--- IANeighbourVehicle:loadAttachmentBackById() - AttachmentBack attacher joint: "..tostring(i))
        --printObj(v, 3, "attachmentBack-inputAttacherJoints-"..tostring(i))
        local jointtype = v.jointType

        for a,x in pairs(vehicle.spec_attacherJoints.attacherJoints) do
            if x.jointType == jointtype and x.attacherJointDirection == -1 then -- -1 = rear, 1 = front
				--printObj(x, 3, "attachmentBack-Vehicle-"..tostring(a))
                --print("--- IANeighbourVehicle:loadAttachmentBackById() - Found matching joint: "..tostring(i))
                --print("--- IANeighbourVehicle:loadAttachmentBackById() - Attaching attachment joint: "..tostring(i).." with tractor attachindex: "..tostring(a))
                attachmentJoint = i
				attachmentNode = v.node
                vehicleAttachIndex = a
				vehicleAttacherNode = x.jointTransform
                break
            end

        end
        break
    end
    if attachmentJoint == nil or vehicleAttachIndex == nil then
        return nil, nil, nil, nil
    end
    return attachmentJoint, vehicleAttachIndex, attachmentNode, vehicleAttacherNode
end

-- Find a matching front attacher joint on the vehicle for the attachment (e.g. Header / Cutter).
-- @param table attachmentBack - The attachment vehicle (has spec_attachable.inputAttacherJoints)
-- @param table vehicle - The main vehicle (has spec_attacherJoints.attacherJoints)
-- @return number|nil attachmentJoint, number|nil vehicleAttachIndex, entityId|nil attachmentNode, entityId|nil vehicleAttacherNode
function identifyAttachmentJointFront(attachmentBack, vehicle)
    local attachmentJoint = nil
    local attachmentAttachIndex = nil
	local attachmentNode = nil
	local vehicleAttacherNode = nil

	if attachmentBack == nil or type(attachmentBack) ~= "table" or attachmentBack.spec_attachable == nil or attachmentBack.spec_attachable.inputAttacherJoints == nil then
		return nil, nil, nil, nil
	end
	if vehicle == nil or type(vehicle) ~= "table" or vehicle.spec_attacherJoints == nil or vehicle.spec_attacherJoints.attacherJoints == nil then
		return nil, nil, nil, nil
	end

    for i,v in pairs(attachmentBack.spec_attachable.inputAttacherJoints) do
        local jointtype = v.jointType

        for a,x in pairs(vehicle.spec_attacherJoints.attacherJoints) do
            if x.jointType == jointtype and x.attacherJointDirection == 1 then -- 1 = front
                attachmentJoint = i
				attachmentNode = v.node
                vehicleAttachIndex = a
				vehicleAttacherNode = x.jointTransform
                break
            end
        end
        break
    end
    if attachmentJoint == nil or vehicleAttachIndex == nil then
        return nil, nil, nil, nil
    end
    return attachmentJoint, vehicleAttachIndex, attachmentNode, vehicleAttacherNode
end

-- True if the vehicle defines at least one front attacher joint (same convention as identifyAttachmentJointFront: attacherJointDirection == 1).
function vehicleHasFrontAttacherJoint(vehicle)
	if vehicle == nil or type(vehicle) ~= "table" or vehicle.spec_attacherJoints == nil or vehicle.spec_attacherJoints.attacherJoints == nil then
		return false
	end
	for _, x in pairs(vehicle.spec_attacherJoints.attacherJoints) do
		if x ~= nil and x.attacherJointDirection == 1 then
			return true
		end
	end
	return false
end

-- Calculate the target world position for an attachment root node
-- so that the attachment's hook aligns with the vehicle's attacher
-- @param entityId vehicleRootNode - Root node of the vehicle
-- @param entityId attachmentRootNode - Root node of the attachment
-- @param entityId vehicleAttacherNode - Attacher (hook) node of the vehicle
-- @param entityId attachmentHookNode - Hook node of the attachment
-- @return number targetX, number targetY, number targetZ - World coordinates for attachment root node
function calculateAttachmentRootPosition(vehicleRootNode, attachmentRootNode, vehicleAttacherNode, attachmentHookNode)
	-- Step 1: Get world coordinates of vehicle's attacher (where attachment hook should be)
	local vehicleAttacherX, vehicleAttacherY, vehicleAttacherZ = getWorldTranslation(vehicleAttacherNode)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Vehicle Attacher Position: "..tostring(vehicleAttacherX)..", "..tostring(vehicleAttacherY)..", "..tostring(vehicleAttacherZ))
	end
	
	-- Step 2: Calculate the offset from attachment hook to attachment root node
	-- Get the hook's position in the root's local coordinate system
	-- The hook's position in its own local space is (0, 0, 0), transform it to root's local space
	local offsetX, offsetY, offsetZ = localToLocal(attachmentHookNode, attachmentRootNode, 0, 0, 0)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Offset (root local space): "..tostring(offsetX)..", "..tostring(offsetY)..", "..tostring(offsetZ))
	end
	
	-- Convert the local offset to world space direction
	local offsetWorldX, offsetWorldY, offsetWorldZ = localDirectionToWorld(vehicleAttacherNode, offsetX, offsetY, offsetZ)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Offset (world space): "..tostring(offsetWorldX)..", "..tostring(offsetWorldY)..", "..tostring(offsetWorldZ))
	end

	--IANeighbours:addDebugPoint(offsetWorldX, offsetWorldY, offsetWorldZ,100,100,100,100)
	-- Step 3: Calculate target world coordinates for attachment root node
	-- Target root position = vehicle attacher position - offset from root to hook
	local targetX = vehicleAttacherX - offsetWorldX
	local targetY = vehicleAttacherY - offsetWorldY
	local targetZ = vehicleAttacherZ - offsetWorldZ
	--IANeighbours:addDebugPoint(targetX, targetY, targetZ,150,150,150,100)

	
	local AttachmentHookX, AttachmentHookY, AttachmentHookZ = getWorldTranslation(attachmentHookNode)
	
	--IANeighbours:addDebugPoint(vehicleAttacherNode)
	--IANeighbours:addDebugPoint(attachmentRootNode)
	--IANeighbours:addDebugPoint(attachmentHookNode)

	return targetX, targetY, targetZ
end

function getFruitTypeGrowthStateName(fruitTypeIndex, growthState)

	local fruitTypes = g_fruitTypeManager:getFruitTypes()
	for _, fruitType in ipairs(fruitTypes) do
		if fruitTypeIndex == fruitType.index then
			for i, name in ipairs(fruitType.growthStateToName) do
				--print("--- IAXMLHelper:saveFarmlands() - fruitType: "..tostring(fruitType.name).." - growthState: "..tostring(name).." - "..tostring(i).." - "..tostring(farmland.field.fieldState.growthState))
				if i == growthState then
					return name
				end
			end
		end
	end
end

function arrayToString(arr)
	if arr == nil or type(arr) ~= "table" then
		return tostring(arr)
	end
	local parts = {}
	for _, v in ipairs(arr) do
		parts[#parts + 1] = tostring(v)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end
-- Calculate the target world position for an attachment root node
-- so that the attachment's hook aligns with the vehicle's attacher
-- @param entityId vehicleRootNode - Root node of the vehicle
-- @param entityId attachmentRootNode - Root node of the attachment
-- @param entityId vehicleAttacherNode - Attacher (hook) node of the vehicle
-- @param entityId attachmentHookNode - Hook node of the attachment
-- @return number targetX, number targetY, number targetZ - World coordinates for attachment root node
function calculateAttachmentRootPosition2(vehicleRootNode, attachmentRootNode, vehicleAttacherNode, attachmentHookNode)
	
	-- step 0: get offset of vehicle attacher
	local vehicleAttacherOffsetX, vehicleAttacherOffsetY, vehicleAttacherOffsetZ = localToLocal(vehicleAttacherNode, vehicleRootNode, 0, 0, 0)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Vehicle Attacher Offset (root local space): "..tostring(vehicleAttacherOffsetX)..", "..tostring(vehicleAttacherOffsetY)..", "..tostring(vehicleAttacherOffsetZ))
	end

	-- Step 1: Get vehicle's attacher world position
	local vehicleX, vehicleY, vehicleZ = getWorldTranslation(vehicleRootNode)

	-- Step 2: Get forward direction in world space (local 0,0,1 = forward)
	local forwardX, forwardY, forwardZ = localDirectionToWorld(vehicleRootNode, 0, 0, 1)

	-- Step 3: Calculate right direction using cross product (up × forward = right)
	local rightX, rightY, rightZ = MathUtil.crossProduct(0, 1, 0, forwardX, forwardY, forwardZ)

	-- Step 4: Get up direction in world space (local 0,1,0 = up)
	local upX, upY, upZ = localDirectionToWorld(vehicleRootNode, 0, 1, 0)


	-- Step 5: Calculate the offset from attachment hook to attachment root node
	-- Get the hook's position in the root's local coordinate system
	-- The hook's position in its own local space is (0, 0, 0), transform it to root's local space
	local AttachmentHookOffsetX, AttachmentHookOffsetY, AttachmentHookOffsetZ = localToLocal(attachmentHookNode, attachmentRootNode, 0, 0, 0)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Offset (root local space): "..tostring(AttachmentHookOffsetX)..", "..tostring(AttachmentHookOffsetY)..", "..tostring(AttachmentHookOffsetZ))
	end

	offsetX = 0--vehicleAttacherOffsetX + offsetX
	offsetY = 0--vehicleAttacherOffsetY + offsetY
	offsetZ = vehicleAttacherOffsetZ + (AttachmentHookOffsetZ*-1)
	if IANeighbours.debug then
		print("--- IAHelper:calculateAttachmentRootPosition() - Offset Z VehicleAttacherOffsetZ: "..tostring(vehicleAttacherOffsetZ)..", AttachmentHookOffsetZ: "..tostring(AttachmentHookOffsetZ)..", OffsetZ: "..tostring(offsetZ))
	end

	--local targetX = vehicleX + forwardX * offsetZ + rightX * offsetX + upX * offsetY
	--local targetY = vehicleY + forwardY * offsetZ + rightY * offsetX + upY * offsetY
	--local targetZ = vehicleZ + forwardZ * offsetZ + rightZ * offsetX + upZ * offsetY
	
	local targetX, targetY, targetZ = getWorldPositionFromNodeLocalOffset(vehicleRootNode, offsetX, offsetY, offsetZ)
	if targetX == nil then
		return vehicleX, vehicleY, vehicleZ
	end

	
	--IANeighbours:addDebugPoint(vehicleAttacherNode)
	--IANeighbours:addDebugPoint(attachmentRootNode)
	--IANeighbours:addDebugPoint(attachmentHookNode)
	--IANeighbours:addDebugPoint(vehicleRootNode)

	return targetX, targetY, targetZ
end

--- World position = node world translation + localDirectionToWorld(node, localX, localY, localZ). Central resolver for placeable/map-node local offsets (IAMapPlace, etc.).
-- @param entityId node
-- @return number|nil worldX, number|nil worldY, number|nil worldZ
function getWorldPositionFromNodeLocalOffset(node, localX, localY, localZ)
	if node == nil or not entityExists(node) or localDirectionToWorld == nil or getWorldTranslation == nil then
		return nil, nil, nil
	end
	local nx, ny, nz = getWorldTranslation(node)
	if nx == nil or nz == nil then
		return nil, nil, nil
	end
	ny = ny or 0
	local lx, ly, lz = localX or 0, localY or 0, localZ or 0
	local dx, dy, dz = localDirectionToWorld(node, lx, ly, lz)
	return nx + (dx or 0), ny + (dy or 0), nz + (dz or 0)
end

local iaHelperYawProbeTransform = nil

local function yawOnlyWorldXZAnalytic(centerX, centerZ, rotationY, localX, localZ)
	local ry = rotationY or 0
	local cosRy, sinRy = math.cos(ry), math.sin(ry)
	local lx, lz = localX or 0, localZ or 0
	return centerX + (lx * cosRy - lz * sinRy), centerZ + (lx * sinRy + lz * cosRy)
end

--- World position of (localX, localY, localZ) in a parent frame at world (worldX, worldY, worldZ) with Giants yaw only setRotation(0, rotationY, 0) — same as map-init corner debug parents. Uses localDirectionToWorld on a reused probe transform; analytic fallback if mission/API missing.
-- @param number rotationY - Yaw radians
function getWorldPositionFromYawLocalOffset(worldX, worldY, worldZ, rotationY, localX, localY, localZ)
	if worldX == nil or worldZ == nil then
		return nil, nil, nil
	end
	worldY = worldY or 0
	local lx, ly, lz = localX or 0, localY or 0, localZ or 0
	if g_currentMission == nil or g_currentMission.terrainRootNode == nil
		or localDirectionToWorld == nil or setTranslation == nil or setRotation == nil or createTransformGroup == nil or link == nil then
		local wx, wz = yawOnlyWorldXZAnalytic(worldX, worldZ, rotationY, lx, lz)
		return wx, worldY + ly, wz
	end
	if iaHelperYawProbeTransform == nil or not entityExists(iaHelperYawProbeTransform) then
		local pn = createTransformGroup("IAHelperYawProbe")
		if pn ~= nil and pn ~= 0 then
			link(g_currentMission.terrainRootNode, pn)
			iaHelperYawProbeTransform = pn
		end
	end
	local pn = iaHelperYawProbeTransform
	if pn == nil or pn == 0 or not entityExists(pn) then
		local wx, wz = yawOnlyWorldXZAnalytic(worldX, worldZ, rotationY, lx, lz)
		return wx, worldY + ly, wz
	end
	setTranslation(pn, worldX, worldY, worldZ)
	setRotation(pn, 0, rotationY or 0, 0)
	local wdx, wdy, wdz = localDirectionToWorld(pn, lx, ly, lz)
	return worldX + (wdx or 0), worldY + (wdy or 0), worldZ + (wdz or 0)
end

--- World position of a point at (localX, localY, localZ) in node's local space. Delegates to getWorldPositionFromNodeLocalOffset (localDirectionToWorld).
-- @param entityId node - Transform node (e.g. vehicle root or debug point node)
-- @param number localX - Offset in node's local X
-- @param number localY - Offset in node's local Y
-- @param number localZ - Offset in node's local Z
-- @return number|nil worldX, number|nil worldY, number|nil worldZ - World coordinates, or nil if node invalid
function getWorldPositionFromLocalOffset(node, localX, localY, localZ)
	return getWorldPositionFromNodeLocalOffset(node, localX, localY, localZ)
end

--- Recursively find first child node with user attribute key equal to value (e.g. onCreate == "TrafficSystem.onCreate").
-- @param number node - Parent node
-- @param string key - User attribute name
-- @param string value - Expected value
-- @return number|nil - Child node id or nil
function findNodeByUserAttribute(node, key, value)
	if node == nil or not entityExists(node) or key == nil or value == nil then
		return nil
	end
	local n = getNumOfChildren(node)
	for i = 0, n - 1 do
		local child = getChildAt(node, i)
		if child ~= nil and entityExists(child) then
			local attr = getUserAttribute(child, key)
			if attr == value then
				return child
			end
			local found = findNodeByUserAttribute(child, key, value)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

--- Max depth when walking traffic-root children for spline SHAPE nodes.
MAX_TRAFFIC_SPLINE_SEARCH_DEPTH = 24

-- getSplineLength must receive a SHAPE entity; pcall alone still triggers engine warnings on TRANSFORM nodes.
function safeGetSplineLength(nodeId)
	if nodeId == nil or not entityExists(nodeId) or type(getSplineLength) ~= "function" then
		return nil
	end
	if type(getHasClassId) == "function" and ClassIds ~= nil and ClassIds.SHAPE ~= nil then
		if not getHasClassId(nodeId, ClassIds.SHAPE) then
			return nil
		end
	end
	local ok, len = pcall(getSplineLength, nodeId)
	if not ok or len == nil or type(len) ~= "number" then
		return nil
	end
	return len
end

function findSplineShapeInSubtree(nodeId, depthLeft)
	if nodeId == nil or not entityExists(nodeId) then
		return nil
	end
	local len = safeGetSplineLength(nodeId)
	if len ~= nil and len >= 0.01 then
		return nodeId
	end
	if depthLeft <= 0 then
		return nil
	end
	local n = getNumOfChildren(nodeId)
	for i = 0, n - 1 do
		local child = getChildAt(nodeId, i)
		if child ~= nil and entityExists(child) then
			local found = findSplineShapeInSubtree(child, depthLeft - 1)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

--- Unit direction (x,y,z) or nil if length near zero.
function normalizeVec3(x, y, z)
	x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
	local len = math.sqrt(x * x + y * y + z * z)
	if len < 1e-6 then
		return nil
	end
	return x / len, y / len, z / len
end

--- True if two place tables are the same logical slot (matching id or same position within tolerance).
function placesMatchForSituationBlocking(place1, place2)
	if place1 == nil or place2 == nil then
		return false
	end
	if place1.id ~= nil and place2.id ~= nil then
		return place1.id == place2.id
	end
	local tolerance = 0.1
	local xMatch = math.abs((place1.x or 0) - (place2.x or 0)) < tolerance
	local yMatch = math.abs((place1.y or 0) - (place2.y or 0)) < tolerance
	local zMatch = math.abs((place1.z or 0) - (place2.z or 0)) < tolerance
	return xMatch and yMatch and zMatch
end

--- Low-level collision probe helper used by IANeighbours/IAMapPlace.
-- Runs `overlapSphere` at (x,y,z) and applies IANeighbours filtering:
-- terrain exclusion, collision filter group exclusion, node-name exclusion, and excludeNodeId subtree exclusion.
-- @param table neighbours - IANeighbours instance (used for constants/debug and overlap callback target)
-- @param table|nil extraExcludeNamePatterns optional array of lowercase substrings: node getName() matches if equal or contained (same rules as PLACE_BLOCKING_EXCLUDE_NODE_NAMES)
-- @return boolean blocked, table blockingInfos, table blockingNodeIds
function getPositionBlockedByCollision(neighbours, x, y, z, radiusM, excludeNodeId, extraExcludeNamePatterns)
	if neighbours == nil or x == nil or z == nil or g_currentMission == nil or g_currentMission.terrainRootNode == nil then
		return false, {}, {}
	end

	local function isNodeUnderTerrain(nodeId, terrainRootNode)
		if nodeId == nil or terrainRootNode == nil or not entityExists(nodeId) then
			return false
		end
		if nodeId == terrainRootNode then
			return true
		end
		local n = nodeId
		while n ~= nil and entityExists(n) do
			local p = getParent(n)
			if p == terrainRootNode then
				return true
			end
			n = p
		end
		return false
	end

	local function isNodeDescendantOf(nodeId, ancestorId)
		if nodeId == nil or ancestorId == nil or not entityExists(nodeId) or not entityExists(ancestorId) then
			return false
		end
		if nodeId == ancestorId then
			return true
		end
		local n = nodeId
		while n ~= nil and entityExists(n) do
			local p = getParent(n)
			if p == ancestorId then
				return true
			end
			n = p
		end
		return false
	end

	local function isNodeCollisionFilterGroupExcluded(nodeId, excludeGroups)
		if nodeId == nil or excludeGroups == nil or type(excludeGroups) ~= "table" then
			return false
		end
		local ok, group = pcall(function()
			if getCollisionFilterGroup and type(getCollisionFilterGroup) == "function" then
				return getCollisionFilterGroup(nodeId)
			end
			return nil
		end)
		if not ok or group == nil then
			return false
		end
		local g = tonumber(group) or 0
		for _, ex in ipairs(excludeGroups) do
			if ex ~= nil and g == (tonumber(ex) or 0) then
				return true
			end
		end
		return false
	end

	--- Match local node name, full scene path, or any ancestor name (overlap often hits children under mapBoundaries, etc.).
	local function lowerMatchesExcludePatterns(lowerStr)
		if lowerStr == nil or lowerStr == "" then
			return false
		end
		local list = neighbours.PLACE_BLOCKING_EXCLUDE_NODE_NAMES
		if list ~= nil then
			for _, pattern in ipairs(list) do
				if pattern ~= nil then
					local p = string.lower(tostring(pattern))
					if p == lowerStr or (string.len(p) > 0 and string.find(lowerStr, p) ~= nil) then
						return true
					end
				end
			end
		end
		if extraExcludeNamePatterns ~= nil and type(extraExcludeNamePatterns) == "table" then
			for _, pattern in ipairs(extraExcludeNamePatterns) do
				if pattern ~= nil then
					local p = string.lower(tostring(pattern))
					if p == lowerStr or (string.len(p) > 0 and string.find(lowerStr, p) ~= nil) then
						return true
					end
				end
			end
		end
		return false
	end

	local function isNodeNameExcludedFromBlocking(nodeId)
		if nodeId == nil then
			return false
		end
		local ok, name = pcall(function()
			if getName and type(getName) == "function" then
				return getName(nodeId)
			end
			return nil
		end)
		if ok and name ~= nil and type(name) == "string" and lowerMatchesExcludePatterns(string.lower(name)) then
			return true
		end
		local okF, fullPath = pcall(function()
			if getNodeIdFullName and type(getNodeIdFullName) == "function" then
				return getNodeIdFullName(nodeId)
			end
			return nil
		end)
		if okF and fullPath ~= nil and type(fullPath) == "string" and fullPath ~= "" and lowerMatchesExcludePatterns(string.lower(fullPath)) then
			return true
		end
		local n, depth = nodeId, 0
		while n ~= nil and depth < 64 do
			local okP, parentId = pcall(function()
				if getParent and type(getParent) == "function" then
					return getParent(n)
				end
				return nil
			end)
			if not okP or parentId == nil or parentId == 0 then
				break
			end
			local okAn, aname = pcall(function()
				if getName and type(getName) == "function" then
					return getName(parentId)
				end
				return nil
			end)
			if okAn and aname ~= nil and type(aname) == "string" and lowerMatchesExcludePatterns(string.lower(aname)) then
				return true
			end
			n = parentId
			depth = depth + 1
		end
		return false
	end

	local function getNodeDebugInfo(nodeId)
		if nodeId == nil then
			return "nil"
		end
		local ok, name = pcall(function()
			if getName and type(getName) == "function" then
				return getName(nodeId)
			end
			return nil
		end)
		if ok and name ~= nil and name ~= "" then
			return tostring(name) .. " (id=" .. tostring(nodeId) .. ")"
		end
		local ok2, path = pcall(function()
			if getNodeIdFullName and type(getNodeIdFullName) == "function" then
				return getNodeIdFullName(nodeId)
			end
			return nil
		end)
		if ok2 and path ~= nil and path ~= "" then
			return tostring(path) .. " (id=" .. tostring(nodeId) .. ")"
		end
		return "id=" .. tostring(nodeId)
	end

	local yVal = (y ~= nil) and y or 0
	local radius = (radiusM ~= nil and radiusM > 0) and radiusM or neighbours.PLACE_COLLISION_CHECK_RADIUS
	local collector = {}
	neighbours._overlapCollectorIds = collector

	local numShapes = 0
	if overlapSphere then
		local mask = neighbours.PLACE_OVERLAP_SPHERE_COLLISION_MASK
		if mask ~= nil then
			numShapes = overlapSphere(x, yVal, z, radius, "overlapCollectorCallback", neighbours, mask, true, true, true, false)
		else
			numShapes = overlapSphere(x, yVal, z, radius, "overlapCollectorCallback", neighbours)
		end
	end

	neighbours._overlapCollectorIds = nil
	if numShapes == 0 then
		return false, {}, {}
	end

	local function isExcluded(nodeId, exclude)
		if exclude == nil then return false end
		if type(exclude) == "number" then
			return isNodeDescendantOf(nodeId, exclude)
		end
		if type(exclude) ~= "table" then
			return false
		end
		for _, exId in ipairs(exclude) do
			if exId ~= nil and isNodeDescendantOf(nodeId, exId) then
				return true
			end
		end
		return false
	end

	local terrainRoot = g_currentMission.terrainRootNode
	local blockingNodes = {}
	local excludeFilterGroups = neighbours.PLACE_BLOCKING_EXCLUDE_COLLISION_FILTER_GROUPS
	for _, nodeId in ipairs(collector) do
		if nodeId ~= nil and not isNodeUnderTerrain(nodeId, terrainRoot) then
			if excludeFilterGroups ~= nil and isNodeCollisionFilterGroupExcluded(nodeId, excludeFilterGroups) then
				-- skip
			elseif isNodeNameExcludedFromBlocking(nodeId) then
				-- Exclude by name patterns (see PLACE_BLOCKING_EXCLUDE_NODE_NAMES)
			elseif not isExcluded(nodeId, excludeNodeId) then
				-- Exclude the main node and all nested children (e.g. place's own map node / building)
				table.insert(blockingNodes, nodeId)
			end
		end
	end

	if #blockingNodes > 0 then
		local blockingInfos = {}
		for _, nid in ipairs(blockingNodes) do
			table.insert(blockingInfos, getNodeDebugInfo(nid))
		end
		if neighbours.debug then
			print(string.format("--- IANeighbours:isPositionBlockedByCollision() position=(%.2f, %.2f, %.2f) radius=%.2fm | %d overlap(s), %d non-terrain blocking | blocking: %s",
				x, yVal, z, radius, #collector, #blockingNodes, table.concat(blockingInfos, " ; ")))
		end
		return true, blockingInfos, blockingNodes
	end

	return false, {}, {}
end

function distanceToPlayer(x,y,z)
    if g_localPlayer ~= nil then
		local playerX, playerY, playerZ = g_localPlayer:getPosition()
		

		
		if x ~= nil and z ~= nil and playerX ~= nil and playerZ ~= nil then
			--print("--- IANeighbour:update() - neighbourX: "..tostring(neighbourX)..", neighbourZ: "..tostring(neighbourZ)..", playerX: "..tostring(playerX)..", playerZ: "..tostring(playerZ))
			-- Calculate 3D distance: sqrt((x1-x2)^2 + (y1-y2)^2 + (z1-z2)^2)
			local dx = playerX - x
			local dy = (playerY or 0) - (y or 0)
			local dz = playerZ - z
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end
	end
    return nil
end

--- Teleport the local player to world X/Z (dev/debug: iaForceFieldwork / iaForceSituation).
-- Uses Player:teleportTo when available; otherwise moves the current vehicle or the on-foot root node.
-- @param number|nil x
-- @param number|nil z
-- @return boolean true if a teleport was attempted
function IAHelper_teleportLocalPlayerToWorldXZ(x, z)
	if g_localPlayer == nil or g_currentMission == nil then
		return false
	end
	local tx = tonumber(x)
	local tz = tonumber(z)
	if tx == nil or tz == nil then
		return false
	end
	if MathUtil ~= nil and type(MathUtil.round) == "function" then
		tx = MathUtil.round(tx, 0)
		tz = MathUtil.round(tz, 0)
	end

	local terrainNode = g_currentMission.terrainRootNode or g_terrainNode
	local ty = 0
	if terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		ty = getTerrainHeightAtWorldPos(terrainNode, tx, 0, tz) or 0
	end
	ty = ty + 0.2

	local vehicle = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if vehicle ~= nil then
		local rootVehicle = vehicle.rootVehicle or vehicle
		if rootVehicle ~= nil and rootVehicle.rootNode ~= nil and entityExists(rootVehicle.rootNode) then
			local wasInPhysics = rootVehicle.isAddedToPhysics == nil or rootVehicle:isAddedToPhysics()
			if rootVehicle.removeFromPhysics ~= nil then
				pcall(function() rootVehicle:removeFromPhysics() end)
			end
			if rootVehicle.setRelativePosition ~= nil then
				pcall(function() rootVehicle:setRelativePosition(tx, 0.5, tz, 0, true) end)
			else
				pcall(function()
					setTranslation(rootVehicle.rootNode, tx, ty, tz)
					setRotation(rootVehicle.rootNode, 0, 0, 0)
				end)
			end
			if wasInPhysics and rootVehicle.addToPhysics ~= nil then
				pcall(function() rootVehicle:addToPhysics() end)
			end
			return true
		end
	end

	if type(g_localPlayer.teleportTo) == "function" then
		local ok = pcall(function() g_localPlayer:teleportTo(tx, ty, tz, true, true) end)
		if ok then
			return true
		end
	end

	if g_localPlayer.rootNode ~= nil and entityExists(g_localPlayer.rootNode) then
		setWorldTranslation(g_localPlayer.rootNode, tx, ty + 0.1, tz)
		return true
	end

	return false
end

-- Terrain bounds helper (rectangle):
-- Uses mapWidth/mapHeight around terrain center (terrainRootNode world position, fallback 0,0).
-- @return table|nil bounds - { minX, maxX, minZ, maxZ } or nil if unavailable
function getTerrainBoundsRect()
	if g_currentMission == nil then
		return nil
	end
	local mapW = g_currentMission.mapWidth
	local mapH = g_currentMission.mapHeight
	if mapW == nil or mapH == nil or mapW <= 0 or mapH <= 0 then
		return nil
	end
	local cx, _, cz = 0, 0, 0
	if g_currentMission.terrainRootNode ~= nil and entityExists(g_currentMission.terrainRootNode) then
		cx, _, cz = getWorldTranslation(g_currentMission.terrainRootNode)
	end
	local halfW = mapW * 0.5
	local halfH = mapH * 0.5
	return {
		minX = cx - halfW,
		maxX = cx + halfW,
		minZ = cz - halfH,
		maxZ = cz + halfH
	}
end

-- Check if world position (x,z) is inside terrain bounds rectangle.
-- If bounds are unavailable, fail open (return true).
-- @param number x - world X
-- @param number z - world Z
-- @param table|nil bounds - Optional precomputed bounds from getTerrainBoundsRect()
-- @return boolean
function isWithinTerrainBoundsRect(x, z, bounds)
	if x == nil or z == nil then
		return false
	end
	local b = bounds or getTerrainBoundsRect()
	if b == nil then
		return true
	end
	return x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ
end

-- Normalize yaw to [-pi, pi].
-- @param number yaw
-- @return number
function normalizeYawPi(yaw)
	local a = yaw or 0
	while a > math.pi do
		a = a - 2 * math.pi
	end
	while a < -math.pi do
		a = a + 2 * math.pi
	end
	return a
end

-- Robust yaw extraction from node forward direction.
-- Uses localDirectionToWorld + MathUtil.getYRotationFromDirection to avoid Euler clamp artifacts.
-- @param entityId node
-- @param number fallbackYaw optional fallback when extraction fails
-- @return number yaw in radians
function getNodeYawFromForward(node, fallbackYaw)
	if node == nil or not entityExists(node) then
		return normalizeYawPi(fallbackYaw or 0)
	end
	local dirX, _, dirZ = localDirectionToWorld(node, 0, 0, 1)
	if dirX == nil or dirZ == nil then
		return normalizeYawPi(fallbackYaw or 0)
	end
	local yaw = (MathUtil and MathUtil.getYRotationFromDirection and MathUtil.getYRotationFromDirection(dirX, dirZ))
		or math.atan2(dirX, dirZ)
	return normalizeYawPi(yaw or fallbackYaw or 0)
end

function printObj(obj, hierarchyLevel,prefix) 
	if (hierarchyLevel == nil) then
	  hierarchyLevel = 0
	elseif (hierarchyLevel == 4) then
	  return 0
	end
  
	local whitespace = ""
	for i=0,hierarchyLevel,1 do
	  whitespace = whitespace .. "-"
	end
	io.write(whitespace)
	print("Debug: "..prefix)
	print(obj)
	if (type(obj) == "table") then
	  for k,v in pairs(obj) do
		io.write(whitespace .. "-")
		if (type(v) == "table") then
		  printObj(v, hierarchyLevel+1,prefix.." - "..k)
		else
		  print(prefix.." - "..k..": "..tostring(v))
		end           
	  end
	else
	  print(obj)
	end
end

--- In-game calendar month 1–12 from `environment.currentPeriod` (+2, with 13→1 / 14→2 wrap). Same rules as `getCurrentGameHours`.
--- @return number|nil
function getEnvironmentMonth1to12()
	if g_currentMission == nil or g_currentMission.environment == nil then
		return nil
	end
	local currentPeriod = g_currentMission.environment.currentPeriod or 0
	local month = currentPeriod + 2
	if month == 13 then
		month = 1
	elseif month == 14 then
		month = 2
	end
	return month
end

--- Current savegame calendar parts for schedule invalidation (aligns with `getCurrentGameHours` month mapping).
--- @return number|nil year, number|nil month1to12, number|nil dayInPeriod
function getEnvironmentYearMonthDayInPeriod()
	if g_currentMission == nil or g_currentMission.environment == nil then
		return nil, nil, nil
	end
	local env = g_currentMission.environment
	return env.currentYear, getEnvironmentMonth1to12(), env.currentDayInPeriod
end

--- In-game growth period index from `environment.currentPeriod` (same index used by fruit growth tables).
--- @return number|nil
function getEnvironmentCurrentPeriodOrNil()
	if g_currentMission == nil or g_currentMission.environment == nil then
		return nil
	end
	return g_currentMission.environment.currentPeriod
end

--- Mission growth / crop calendar mode (same source as contract harvest helpers).
--- @return any|nil
function getMissionGrowthModeOrNil()
	if g_currentMission == nil or g_currentMission.missionInfo == nil then
		return nil
	end
	return g_currentMission.missionInfo.growthMode
end

--- True if situation `months` is empty (year-round) or current calendar month is listed.
--- @return boolean
function iaSituationConfigMonthsMatchCurrent(config)
	if config == nil then
		return false
	end
	if config.months == nil or #config.months == 0 then
		return true
	end
	local currentMonth = getEnvironmentMonth1to12()
	if currentMonth == nil then
		return false
	end
	for _, monthNum in ipairs(config.months) do
		if currentMonth == (tonumber(monthNum) or monthNum) then
			return true
		end
	end
	return false
end

--- Read `growthDataSeasonal.periods[period].plantingAllowed` (and optional engine API) for a fruit type.
--- @return boolean|nil true/false when data exists; nil if undecided (caller may fall back to situation XML `months`).
function iaIsFruitTypePlantingAllowedInPeriod(fruitTypeIndex, period, growthMode)
	if fruitTypeIndex == nil or g_fruitTypeManager == nil or type(g_fruitTypeManager.getFruitTypeByIndex) ~= "function" then
		return nil
	end
	local fruit = nil
	local okFt, ftOrErr = pcall(function()
		return g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
	end)
	if okFt then
		fruit = ftOrErr
	end
	if fruit == nil then
		return nil
	end
	if period == nil then
		period = getEnvironmentCurrentPeriodOrNil()
	end
	if growthMode == nil then
		growthMode = getMissionGrowthModeOrNil()
	end
	if period == nil then
		return nil
	end
	if fruit.getIsPlantingAllowedInPeriod ~= nil and growthMode ~= nil then
		local ok, allowed = pcall(function()
			return fruit:getIsPlantingAllowedInPeriod(growthMode, period)
		end)
		if ok and type(allowed) == "boolean" then
			return allowed
		end
		local ok2, allowed2 = pcall(function()
			return fruit:getIsPlantingAllowedInPeriod(period, growthMode)
		end)
		if ok2 and type(allowed2) == "boolean" then
			return allowed2
		end
	end
	local gd = fruit.growthDataSeasonal
	if type(gd) ~= "table" then
		return nil
	end
	local periods = gd.periods
	if periods == nil and growthMode ~= nil then
		local sub = gd[growthMode]
		if type(sub) == "table" then
			periods = sub.periods
		end
	end
	if type(periods) ~= "table" then
		return nil
	end
	local row = periods[period]
	if type(row) ~= "table" or row.plantingAllowed == nil then
		return nil
	end
	local pa = row.plantingAllowed
	if pa == true or pa == 1 then
		return true
	end
	if pa == false or pa == 0 then
		return false
	end
	return nil
end

--- SEED fieldwork: use fruit-type planting window when available; otherwise situation `months` (empty = year-round).
--- @return boolean
function iaFieldworkSeedCalendarAllowedForFruit(config, fruitTypeIndexForSeed)
	local r = nil
	if fruitTypeIndexForSeed ~= nil then
		r = iaIsFruitTypePlantingAllowedInPeriod(fruitTypeIndexForSeed)
	end
	if r == false then
		return false
	end
	if r == true then
		return true
	end
	return iaSituationConfigMonthsMatchCurrent(config)
end

--- Field instance for a farmland id (`FarmlandManager:getFarmlandById` + `getField`). Prefer over scanning all farmlands.
--- @return table|nil field
function IAHelper_getFieldForFarmlandId(farmlandId)
	if farmlandId == nil or g_farmlandManager == nil then
		return nil
	end
	if type(g_farmlandManager.getFarmlandById) == "function" then
		local farmland = g_farmlandManager:getFarmlandById(farmlandId)
		if farmland ~= nil and type(farmland.getField) == "function" then
			local ok, f = pcall(farmland.getField, farmland)
			if ok then
				return f
			end
		end
	end
	return nil
end

--- Union of place ids listed in `neighbour[fieldName]` for every neighbour (`assignedHomebasePlaceIds`, `assignedWorkplacePlaceIds`, …).
--- @param table ianeighbours IANeighbours
--- @param string fieldName key on neighbour table holding an array of place ids
--- @return table set placeId -> true
function IAHelper_collectNeighbourAssignedPlaceIds(ianeighbours, fieldName)
	local assigned = {}
	if ianeighbours == nil or ianeighbours.neighbours == nil or fieldName == nil or fieldName == "" then
		return assigned
	end
	for _, neighbour in pairs(ianeighbours.neighbours) do
		if neighbour ~= nil then
			local list = neighbour[fieldName]
			if type(list) == "table" then
				for _, placeId in ipairs(list) do
					assigned[placeId] = true
				end
			end
		end
	end
	return assigned
end

--- Copy string-keyed map: entries listed in `orderedKeys` first (if present in src), then remaining string keys from `pairs(src)`.
--- @param table|nil src
--- @param table orderedKeys array of string keys
--- @return table
function IAHelper_copyTableStringKeysOrderedFirst(src, orderedKeys)
	if src == nil or type(src) ~= "table" then
		return {}
	end
	local out = {}
	if type(orderedKeys) == "table" then
		for _, k in ipairs(orderedKeys) do
			local v = src[k]
			if v ~= nil then
				out[k] = v
			end
		end
	end
	for k, v in pairs(src) do
		if out[k] == nil and v ~= nil and type(k) == "string" then
			out[k] = v
		end
	end
	return out
end

--- Sorted list of keys (stable logs, dumps).
--- @param table|nil t
--- @return table array of keys
function IAHelper_sortedMapKeys(t)
	local keys = {}
	if t == nil or type(t) ~= "table" then
		return keys
	end
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

function getCurrentGameHours()

	local plannedDaysPerPeriod = g_currentMission.environment.plannedDaysPerPeriod


	local currentYear = g_currentMission.environment.currentYear
	local currentMonth = getEnvironmentMonth1to12()
	local currentDayInPeriod = g_currentMission.environment.currentDayInPeriod
	local currentHour = g_currentMission.environment.currentHour
	local currentMinute = g_currentMission.environment.currentMinute
	--print("--- IAHelper:getCurrentGameHours() - Current Game Time: "..tostring(currentYear)..", "..tostring(currentMonth)..", "..tostring(currentDayInPeriod)..", "..tostring(currentHour)..", "..tostring(currentMinute))
	--print("--- IAHelper:getCurrentGameHours() - Hours: "..tostring(hours))
	--print("--- IAHelper:getCurrentGameHours() - Hours in Day: "..tostring(currentHour))
	--print("--- IAHelper:getCurrentGameHours() - Hours in Month: "..tostring(currentHour + (24 * (currentDayInPeriod-1))))
	--print("--- IAHelper:getCurrentGameHours() - Hours in Year: "..tostring(currentHour + (24 * (currentDayInPeriod-1)) + ((currentMonth-1) * 24 * plannedDaysPerPeriod)))
	--print("--- IAHelper:getCurrentGameHours() - Hours All: "..tostring(currentHour + (24 * (currentDayInPeriod-1)) + ((currentMonth-1) * 24 * plannedDaysPerPeriod) + ((currentYear-1) * 24 * 12 * plannedDaysPerPeriod)))
	local hours = currentHour + (24 * (currentDayInPeriod-1)) + ((currentMonth-1) * 24 * plannedDaysPerPeriod) + ((currentYear-1) * 24 * 12 * plannedDaysPerPeriod)
	return hours
end

-- Determine the current daytime based on the current hour
-- @return string - One of: "morning", "day", "evening", "night"
function getCurrentDaytime()
	if g_currentMission == nil or g_currentMission.environment == nil then
		return "day"  -- Default to day if environment not available
	end
	
	local currentHour = g_currentMission.environment.currentHour
	
	-- Define time ranges:
	-- Morning: 6-11 (6:00 to 11:59)
	-- Day: 12-17 (12:00 to 17:59) - but "day" also includes morning and evening
	-- Evening: 18-21 (18:00 to 21:59)
	-- Night: 22-5 (22:00 to 5:59)
	
	if currentHour >= 6 and currentHour < 12 then
		return "morning"
	elseif currentHour >= 12 and currentHour < 18 then
		return "day"
	elseif currentHour >= 18 and currentHour < 22 then
		return "evening"
	else
		-- 22-5 (night)
		return "night"
	end
end


---Apply a voice effect preset to a sample (by sample id). Uses setSampleFrequencyFilter for "phone" etc.
-- @param sampleId number Sample id (from createSample or getAudioSourceSample)
-- @param preset string e.g. "phone" for band-limited phone effect
function applyVoiceEffectPreset(sampleId, preset)
	if sampleId == nil or sampleId == 0 or preset == nil or preset == "" then
		return
	end
	local p = string.lower(preset)
	-- setSampleFrequencyFilter(sampleId, 1.0, lowpassGain, 0.0, lowpassCutoffFrequency, 0.0, lowpassResonance)
	if p == "phone" then
		setSampleFrequencyFilter(sampleId, 1.0, 0.6, 0.0, 3000, 0.0, 1.5)
	end
end

---Plays a voice sample (2D or 3D). Optional sourceNode for 3D (scene node id, or "player" for player position), optional effectPreset. Cleanup via isVoiceSamplePlaying + deleteVoiceSample.
-- @param string baseDir Mod base directory (e.g. g_currentModDirectory)
-- @param string relativePath Path relative to mod dir, e.g. "conversations/27/001_greeting.wav"
-- @param number|string|nil sourceNode Scene node for 3D (e.g. NPC root), or "player" for 3D at player position, or nil for 2D.
-- @param string|nil effectPreset Optional effect name, e.g. "phone" for band-limited phone effect.
-- @return number|table|nil Handle for cleanup: number (2D sample id) or table { sample=id, soundNode=node [, linkNode=node ] } (3D), or nil on failure
--- Prefer .ogg over .wav when both exist (smaller size, same quality). Keeps XML referencing .wav.
local function resolveVoicePath(baseDir, relativePath)
	if baseDir == nil or relativePath == nil or relativePath == "" then
		return nil
	end
	-- Prefer compressed OGG if present (e.g. after running helper/compress_conversation_audio.ps1)
	if relativePath:lower():match("%.wav$") then
		local oggPath = relativePath:gsub("%.wav$", ".ogg")
		local oggFile = Utils.getFilename(oggPath, baseDir)
		if fileExists(oggFile) then
			return oggFile
		end
	end
	return Utils.getFilename(relativePath, baseDir)
end

function createAndPlayVoiceSample(baseDir, relativePath, sourceNode, effectPreset)
	if baseDir == nil or relativePath == nil or relativePath == "" then
		return nil
	end
	local fileName = resolveVoicePath(baseDir, relativePath)
	if fileName == nil or fileName == "" then
		return nil
	end
	if not fileExists(fileName) then
		return nil
	end
	-- Resolve "player" to a temporary node at player position (caller must delete linkNode in handle)
	local linkNode = nil
	local ownLinkNode = false
	if sourceNode == "player" then
		if g_localPlayer ~= nil and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
			local x, y, z = g_localPlayer:getPosition()
			linkNode = createTransformGroup("IANeighbours_voice_player")
			if linkNode ~= nil and linkNode ~= 0 then
				link(g_currentMission.terrainRootNode, linkNode)
				setWorldTranslation(linkNode, x or 0, y or 0, z or 0)
				sourceNode = linkNode
				ownLinkNode = true
			else
				sourceNode = nil
			end
		else
			sourceNode = nil
		end
	else
		linkNode = sourceNode
	end
	if sourceNode ~= nil and entityExists(sourceNode) then
		local innerRadius = 3
		local outerRadius = 25
		local volume = 1
		local loops = 1
		local name = "IANeighbours_voice_3d"
		local soundNode = createAudioSource(name, fileName, outerRadius, innerRadius, volume, loops)
		if soundNode == nil or soundNode == 0 then
			if ownLinkNode and linkNode ~= nil and entityExists(linkNode) then
				unlink(linkNode)
				delete(linkNode)
			end
			return nil
		end
		link(sourceNode, soundNode)
		local sampleId = getAudioSourceSample(soundNode)
		if sampleId == nil or sampleId == 0 then
			delete(soundNode)
			if ownLinkNode and linkNode ~= nil and entityExists(linkNode) then
				unlink(linkNode)
				delete(linkNode)
			end
			return nil
		end
		setAudioSourceAutoPlay(soundNode, false)
		applyVoiceEffectPreset(sampleId, effectPreset)
		playSample(sampleId, loops, volume, 0, 0, 0)
		-- Missing/corrupt files can still yield a sound node; engine may log "can't load sample" and not play.
		if not isSamplePlaying(sampleId) then
			delete(soundNode)
			if ownLinkNode and linkNode ~= nil and entityExists(linkNode) then
				unlink(linkNode)
				delete(linkNode)
			end
			return nil
		end
		local handle = { sample = sampleId, soundNode = soundNode }
		if ownLinkNode and linkNode ~= nil then
			handle.linkNode = linkNode
		end
		return handle
	end
	local sample = createSample("IANeighbours_voice")
	if sample == nil or sample == 0 then
		return nil
	end
	if not loadSample(sample, fileName, false) then
		delete(sample)
		return nil
	end
	applyVoiceEffectPreset(sample, effectPreset)
	playSample(sample, 1, 1, 0, 0, 0)
	return sample
end

---Whether the voice sample handle is still playing.
-- @param handle number|table From createAndPlayVoiceSample
-- @return boolean
function isVoiceSamplePlaying(handle)
	if handle == nil then return false end
	local id = type(handle) == "table" and handle.sample or handle
	return id ~= nil and isSamplePlaying(id)
end

---Release the voice sample (2D or 3D). Safe to call with nil. Also deletes temporary player link node when present.
-- @param handle number|table From createAndPlayVoiceSample
function deleteVoiceSample(handle)
	if handle == nil then return end
	if type(handle) == "table" then
		if handle.soundNode ~= nil and entityExists(handle.soundNode) then
			delete(handle.soundNode)
		end
		handle.soundNode = nil
		if handle.linkNode ~= nil and entityExists(handle.linkNode) then
			unlink(handle.linkNode)
			delete(handle.linkNode)
		end
		handle.linkNode = nil
	else
		delete(handle)
	end
end

-- -----------------------------------------------------------------------------
-- Contract generation helpers (field/farmland driven, base-game only)
-- -----------------------------------------------------------------------------

---Resolve a field's farmland id across GIANTS/map/mod variations.
local function iaGetFieldFarmlandId(field)
	if field == nil then
		return nil
	end
	if field.farmland ~= nil then
		if type(field.farmland.getId) == "function" then
			local ok, id = pcall(field.farmland.getId, field.farmland)
			if ok then
				return tonumber(id)
			end
		end
		if field.farmland.id ~= nil then
			return tonumber(field.farmland.id)
		end
	end
	if field.farmlandId ~= nil then
		return tonumber(field.farmlandId)
	end
	return nil
end

---Check whether a value is contained in a set-table (nil set = allow all).
local function iaFieldMatchesFilterSet(value, filterSet)
	if filterSet == nil then
		return true
	end
	if type(filterSet) ~= "table" then
		return false
	end
	return filterSet[value] == true
end

---Normalize {1,2,3} or { [1]=true } into a set-table for fast membership tests.
local function iaBuildIdSet(listOrSet)
	if listOrSet == nil then
		return nil
	end
	if type(listOrSet) ~= "table" then
		return nil
	end
	-- if already a set-like table, keep it
	local isSetLike = false
	for k, v in pairs(listOrSet) do
		if type(k) ~= "number" and v == true then
			isSetLike = true
			break
		end
	end
	if isSetLike then
		return listOrSet
	end
	local set = {}
	for _, v in ipairs(listOrSet) do
		local n = tonumber(v)
		if n ~= nil then
			set[n] = true
		end
	end
	return set
end

---Apply the reference-style field eligibility rules plus optional opts filters.
local function iaIsFieldContractEligible(field, opts)
	if field == nil then
		return false
	end

	-- active mission already assigned to this field
	if field.currentMission ~= nil then
		return false
	end

	-- map/script can disable missions per field
	if Utils.getNoNil(field.isMissionAllowed, true) ~= true then
		return false
	end

	-- ownership filter (default: exclude player-owned fields)
	local allowOwned = opts ~= nil and opts.allowOwnedFields == true
	if not allowOwned and type(field.getHasOwner) == "function" then
		local ok, hasOwner = pcall(field.getHasOwner, field)
		if ok and hasOwner == true then
			return false
		end
	end

	-- optional filters
	local farmlandId = iaGetFieldFarmlandId(field)
	if opts ~= nil and opts.farmlandIds ~= nil then
		local set = iaBuildIdSet(opts.farmlandIds)
		if set ~= nil and not iaFieldMatchesFilterSet(farmlandId, set) then
			return false
		end
	end
	if opts ~= nil and opts.fieldIds ~= nil then
		local set = iaBuildIdSet(opts.fieldIds)
		local fid = tonumber(field.fieldId or field.id)
		if set ~= nil and not iaFieldMatchesFilterSet(fid, set) then
			return false
		end
	end

	return true
end

-- -----------------------------------------------------------------------------
-- FS25_ContractTypeGenerator parity: isAvailableForField, FieldUpdateTask prep,
-- tryGenerateMission call order (no-arg first), getFieldForMission + debugField.
-- -----------------------------------------------------------------------------

local function iaIsFruitHarvestableInCurrentPeriod(fruit, growthMode, period)
	if fruit == nil then
		return false
	end
	local minHarvest = fruit.minHarvestingGrowthState or 0
	local maxHarvest = fruit.maxHarvestingGrowthState or 0
	if minHarvest <= 0 or maxHarvest <= 0 then
		return false
	end
	if growthMode ~= nil and period ~= nil then
		if fruit.getIsHarvestableInPeriod ~= nil then
			local success, isHarvestable = pcall(fruit.getIsHarvestableInPeriod, fruit, growthMode, period)
			if success and type(isHarvestable) == "boolean" then
				return isHarvestable
			end
			local swappedSuccess, isHarvestableSwapped = pcall(fruit.getIsHarvestableInPeriod, fruit, period, growthMode)
			if swappedSuccess and type(isHarvestableSwapped) == "boolean" then
				return isHarvestableSwapped
			end
		end
		local periodTableCandidates = {
			fruit.harvestPeriods,
			fruit.harvestingPeriods,
			fruit.harvestPeriod,
		}
		for _, periodTable in ipairs(periodTableCandidates) do
			if type(periodTable) == "table" then
				local periodValue = periodTable[period]
				if periodValue ~= nil then
					return periodValue == true or periodValue == 1
				end
			end
		end
	end
	if fruit.getRandomInitialState ~= nil and growthMode ~= nil then
		local randomSuccess, randomState = pcall(fruit.getRandomInitialState, fruit, growthMode)
		if randomSuccess and type(randomState) == "number" then
			return randomState >= minHarvest and randomState <= maxHarvest
		end
	end
	return true
end

local function iaGetHarvestableMissionFruitsForCurrentPeriod()
	local harvestableFruits = {}
	local addedByIndex = {}
	local growthMode = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.growthMode or nil
	local currentPeriod = g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.currentPeriod or nil
	local function tryAddFruitByIndex(fruitTypeIndex)
		if fruitTypeIndex == nil or addedByIndex[fruitTypeIndex] then
			return
		end
		local fruit = g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypeByIndex ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex) or nil
		if fruit == nil then
			return
		end
		if fruit.index == FruitType.GRASS or fruit.index == FruitType.UNKNOWN then
			return
		end
		local isCatchCrop = false
		if fruit.getIsCatchCrop ~= nil then
			local success, result = pcall(fruit.getIsCatchCrop, fruit)
			if success then
				isCatchCrop = result == true
			end
		end
		if isCatchCrop then
			return
		end
		if iaIsFruitHarvestableInCurrentPeriod(fruit, growthMode, currentPeriod) then
			table.insert(harvestableFruits, fruit)
			addedByIndex[fruitTypeIndex] = true
		end
	end
	if g_fieldManager ~= nil and type(g_fieldManager.availableFruitTypeIndices) == "table" then
		for _, fruitTypeIndex in ipairs(g_fieldManager.availableFruitTypeIndices) do
			tryAddFruitByIndex(fruitTypeIndex)
		end
	elseif g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypes ~= nil then
		for _, fruit in ipairs(g_fruitTypeManager:getFruitTypes() or {}) do
			if fruit ~= nil and fruit.useForFieldMissions and fruit.allowsSeeding then
				tryAddFruitByIndex(fruit.index)
			end
		end
	end
	return harvestableFruits
end

local function iaCallIsAvailableForField(classObject, field)
	if classObject == nil or classObject.isAvailableForField == nil then
		return true, true
	end
	local success, isAvailableOrError = pcall(classObject.isAvailableForField, field, nil)
	if success then
		return true, isAvailableOrError == true
	end
	local successWithSelf, isAvailableWithSelf = pcall(classObject.isAvailableForField, classObject, field, nil)
	if successWithSelf then
		return true, isAvailableWithSelf == true
	end
	return false, false
end

local function iaApplyFieldState(field, state)
	if field == nil or state == nil or FieldUpdateTask == nil then
		return false
	end
	local task = FieldUpdateTask.new()
	if task == nil then
		return false
	end
	task:setField(field)
	if field.getDensityMapPolygon ~= nil then
		task:setArea(field:getDensityMapPolygon())
	end
	if state.fruitTypeIndex ~= nil then
		task:setFruit(state.fruitTypeIndex, state.growthState or 1)
	end
	if state.groundType ~= nil then
		task:setGroundType(state.groundType)
	end
	local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
	local groundAngle = state.groundAngle or 0
	task:setGroundAngle(-groundAngle)
	task:setWeedState((missionInfo ~= nil and missionInfo.weedsEnabled) and (state.weedState or 0) or 0)
	task:setStoneLevel((missionInfo ~= nil and missionInfo.stonesEnabled) and (state.stoneLevel or 0) or 0)
	task:setSprayType(state.sprayType or ((FieldSprayType ~= nil and FieldSprayType.NONE) or 0))
	task:setSprayLevel(state.sprayLevel or 0)
	task:setLimeLevel(state.limeLevel or 0)
	task:setPlowLevel(state.plowLevel or 0)
	task:setRollerLevel(state.rollerLevel or 0)
	task:setStubbleShredLevel(state.stubbleShredLevel or 0)
	if state.clearHeightTypes == true then
		task:clearHeight()
	end
	task:resetDisplacement()
	task:clearTireTracks()
	task:enqueue(true)
	if field.getFieldState ~= nil then
		local fieldState = field:getFieldState()
		if fieldState ~= nil then
			fieldState.isValid = true
			if state.fruitTypeIndex ~= nil then
				fieldState.fruitTypeIndex = state.fruitTypeIndex
			end
			if state.growthState ~= nil then
				fieldState.growthState = state.growthState
			end
			if state.groundType ~= nil then
				fieldState.groundType = state.groundType
			end
			if state.weedState ~= nil then
				fieldState.weedState = state.weedState
			end
			if state.stoneLevel ~= nil then
				fieldState.stoneLevel = state.stoneLevel
			end
			if state.sprayType ~= nil then
				fieldState.sprayType = state.sprayType
			end
			if state.sprayLevel ~= nil then
				fieldState.sprayLevel = state.sprayLevel
			end
			if state.limeLevel ~= nil then
				fieldState.limeLevel = state.limeLevel
			end
			if state.plowLevel ~= nil then
				fieldState.plowLevel = state.plowLevel
			end
			if state.rollerLevel ~= nil then
				fieldState.rollerLevel = state.rollerLevel
			end
			if state.stubbleShredLevel ~= nil then
				fieldState.stubbleShredLevel = state.stubbleShredLevel
			end
		end
	end
	return true
end

local function iaGetMissionPreparationStrategies(missionTypeName)
	local strategies = {}
	local lowerName = string.lower(tostring(missionTypeName or ""))
	local isHarvestMission = string.find(lowerName, "harvest", 1, true) ~= nil
	local fruitTypes = {}
	if g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypes ~= nil then
		fruitTypes = g_fruitTypeManager:getFruitTypes() or {}
	end
	local function findFruit(predicate)
		for _, fruit in ipairs(fruitTypes) do
			if fruit ~= nil and predicate(fruit) then
				return fruit
			end
		end
		return nil
	end
	local function getGroundTypeForFruit(fruit, growthState, fallback)
		if fruit ~= nil and fruit.getGrowthStateGroundType ~= nil then
			local groundType = fruit:getGrowthStateGroundType(growthState)
			if groundType ~= nil then
				return groundType
			end
		end
		return fallback
	end
	local cropFruit = findFruit(function(fruit)
		return fruit.allowsSeeding and not fruit:getIsCatchCrop() and fruit.index ~= FruitType.GRASS
	end)
	local rollingFruit = findFruit(function(fruit)
		return fruit.needsRolling and not fruit:getIsCatchCrop()
	end)
	local grassFruit = nil
	if g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypeByIndex ~= nil then
		grassFruit = g_fruitTypeManager:getFruitTypeByIndex(FruitType.GRASS)
	end
	if grassFruit == nil then
		grassFruit = findFruit(function(fruit)
			return string.upper(fruit.name or "") == "GRASS"
		end)
	end
	local sprayTypeNone = (FieldSprayType ~= nil and FieldSprayType.NONE) or 0
	local groundCultivated = (FieldGroundType ~= nil and FieldGroundType.CULTIVATED) or 0
	local groundPlowed = (FieldGroundType ~= nil and FieldGroundType.PLOWED) or groundCultivated
	local plowMax = g_fieldManager ~= nil and g_fieldManager.plowLevelMaxValue or 0
	local limeMax = g_fieldManager ~= nil and g_fieldManager.limeLevelMaxValue or 0
	local sprayMax = g_fieldManager ~= nil and g_fieldManager.sprayLevelMaxValue or 0
	local stoneMax = 0
	if g_currentMission ~= nil and g_currentMission.stoneSystem ~= nil and g_currentMission.stoneSystem.getMinMaxValues ~= nil then
		local _, maxValue = g_currentMission.stoneSystem:getMinMaxValues()
		stoneMax = maxValue or 0
	end
	local function addStrategy(name, state)
		state.groundAngle = state.groundAngle or 0
		state.clearHeightTypes = Utils.getNoNil(state.clearHeightTypes, false)
		table.insert(strategies, {
			name = name,
			state = state
		})
	end
	if string.find(lowerName, "roller", 1, true) ~= nil and rollingFruit ~= nil then
		addStrategy("roller_base", {
			fruitTypeIndex = rollingFruit.index,
			growthState = 1,
			groundType = getGroundTypeForFruit(rollingFruit, 1, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = sprayMax,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 0,
		})
	end
	if string.find(lowerName, "plow", 1, true) ~= nil and cropFruit ~= nil then
		local growthState = cropFruit.cutState or cropFruit.maxHarvestingGrowthState or 1
		addStrategy("plow_base", {
			fruitTypeIndex = cropFruit.index,
			growthState = growthState,
			groundType = getGroundTypeForFruit(cropFruit, growthState, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = sprayMax,
			limeLevel = limeMax,
			plowLevel = 0,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	if string.find(lowerName, "lime", 1, true) ~= nil and cropFruit ~= nil then
		addStrategy("lime_base", {
			fruitTypeIndex = cropFruit.index,
			growthState = 1,
			groundType = getGroundTypeForFruit(cropFruit, 1, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = sprayMax,
			limeLevel = 0,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	if (string.find(lowerName, "mowbale", 1, true) ~= nil or string.find(lowerName, "bale", 1, true) ~= nil or string.find(lowerName, "mow", 1, true) ~= nil) and grassFruit ~= nil then
		local grassGrowth = grassFruit.maxHarvestingGrowthState or grassFruit.cutState or 1
		addStrategy("mow_or_bale_grass", {
			fruitTypeIndex = grassFruit.index,
			growthState = grassGrowth,
			groundType = getGroundTypeForFruit(grassFruit, grassGrowth, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = sprayMax,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	if isHarvestMission then
		local harvestFruits = iaGetHarvestableMissionFruitsForCurrentPeriod()
		for i = #harvestFruits, 2, -1 do
			local j = math.random(1, i)
			harvestFruits[i], harvestFruits[j] = harvestFruits[j], harvestFruits[i]
		end
		for _, harvestFruit in ipairs(harvestFruits) do
			local harvestGrowth = harvestFruit.maxHarvestingGrowthState or harvestFruit.cutState or 1
			addStrategy("harvest_" .. tostring(harvestFruit.name or harvestFruit.index), {
				fruitTypeIndex = harvestFruit.index,
				growthState = harvestGrowth,
				groundType = getGroundTypeForFruit(harvestFruit, harvestGrowth, groundCultivated),
				sprayType = sprayTypeNone,
				sprayLevel = sprayMax,
				limeLevel = limeMax,
				plowLevel = plowMax,
				weedState = 0,
				stoneLevel = 0,
				rollerLevel = 1,
			})
		end
	end
	if string.find(lowerName, "sow", 1, true) ~= nil then
		addStrategy("sow_base", {
			fruitTypeIndex = FruitType.UNKNOWN,
			growthState = 1,
			groundType = groundCultivated,
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	if string.find(lowerName, "spray", 1, true) ~= nil and cropFruit ~= nil then
		addStrategy("spray_base", {
			fruitTypeIndex = cropFruit.index,
			growthState = 1,
			groundType = getGroundTypeForFruit(cropFruit, 1, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	-- Reference mod has no dedicated fertilize block; add one (name is often fertilizeMission / fertilize).
	if string.find(lowerName, "fertil", 1, true) ~= nil and cropFruit ~= nil then
		addStrategy("fertilize_base", {
			fruitTypeIndex = cropFruit.index,
			growthState = 1,
			groundType = getGroundTypeForFruit(cropFruit, 1, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = 0,
			rollerLevel = 1,
		})
	end
	if string.find(lowerName, "stone", 1, true) ~= nil then
		addStrategy("stone_base", {
			fruitTypeIndex = FruitType.UNKNOWN,
			growthState = 1,
			groundType = groundPlowed,
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = limeMax,
			plowLevel = plowMax,
			weedState = 0,
			stoneLevel = stoneMax,
			rollerLevel = 1,
		})
	end
	if not isHarvestMission and cropFruit ~= nil then
		addStrategy("generic_crop_young", {
			fruitTypeIndex = cropFruit.index,
			growthState = 1,
			groundType = getGroundTypeForFruit(cropFruit, 1, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = 0,
			plowLevel = 0,
			weedState = 3,
			stoneLevel = 0,
			rollerLevel = 0,
		})
		local cutGrowth = cropFruit.cutState or cropFruit.maxHarvestingGrowthState or 1
		addStrategy("generic_crop_cut", {
			fruitTypeIndex = cropFruit.index,
			growthState = cutGrowth,
			groundType = getGroundTypeForFruit(cropFruit, cutGrowth, groundCultivated),
			sprayType = sprayTypeNone,
			sprayLevel = sprayMax,
			limeLevel = limeMax,
			plowLevel = 0,
			weedState = 0,
			stoneLevel = stoneMax,
			rollerLevel = 1,
		})
	end
	if not isHarvestMission then
		addStrategy("generic_empty_field", {
			fruitTypeIndex = FruitType.UNKNOWN,
			growthState = 1,
			groundType = groundCultivated,
			sprayType = sprayTypeNone,
			sprayLevel = 0,
			limeLevel = 0,
			plowLevel = 0,
			weedState = 0,
			stoneLevel = stoneMax,
			rollerLevel = 0,
		})
	end
	return strategies
end

---Reference FS25_ContractTypeGenerator: tryGenerateMission with no args, then (classObject); then contract-style (true) fallbacks.
local function iaCallTryGenerateMission(classObject)
	if classObject == nil or type(classObject.tryGenerateMission) ~= "function" then
		return false, nil
	end
	local fn = classObject.tryGenerateMission
	local attempts = {
		function()
			return pcall(fn)
		end,
		function()
			return pcall(fn, classObject)
		end,
		function()
			return pcall(fn, true)
		end,
		function()
			return pcall(fn, true, false)
		end,
		function()
			return pcall(fn, classObject, true)
		end,
		function()
			return pcall(fn, classObject, true, false)
		end,
	}
	local lastErr = nil
	for i = 1, #attempts do
		local ok, missionOrErr = attempts[i]()
		if ok then
			return true, missionOrErr
		end
		lastErr = missionOrErr
	end
	return false, lastErr
end

---Force generation against a field: override getFieldForMission (and debugField like legacy IAGameLoopHelper).
local function iaTryGenerateMissionOnField(classObject, field)
	if classObject == nil or type(classObject.tryGenerateMission) ~= "function" then
		return nil
	end
	if g_fieldManager == nil or field == nil then
		local ok, missionOrErr = iaCallTryGenerateMission(classObject)
		return ok and missionOrErr or nil
	end
	local originalGetFieldForMission = g_fieldManager.getFieldForMission
	local prevDebugField = g_fieldManager.debugField
	if type(g_fieldManager.getFieldForMission) == "function" then
		g_fieldManager.getFieldForMission = function(_)
			return field
		end
	end
	g_fieldManager.debugField = field
	local ok, missionOrErr = iaCallTryGenerateMission(classObject)
	g_fieldManager.debugField = prevDebugField
	if type(originalGetFieldForMission) == "function" then
		g_fieldManager.getFieldForMission = originalGetFieldForMission
	end
	return ok and missionOrErr or nil
end

local function iaForcePrepareAndTryGenerateOnCandidates(missionTypeName, classObject, candidates)
	if candidates == nil or FieldUpdateTask == nil then
		return nil
	end
	local strategies = iaGetMissionPreparationStrategies(missionTypeName)
	if #strategies == 0 then
		return nil
	end
	for _, field in ipairs(candidates) do
		for _, strategy in ipairs(strategies) do
			iaApplyFieldState(field, strategy.state)
			local canUse = true
			if classObject.isAvailableForField ~= nil then
				local okAv, av = iaCallIsAvailableForField(classObject, field)
				canUse = okAv and av
			end
			if canUse then
				local mission = iaTryGenerateMissionOnField(classObject, field)
				if mission ~= nil then
					return mission
				end
			end
		end
	end
	return nil
end

---Register a generated mission and immediately run validation so invalid contracts are removed right away.
local function iaRegisterMissionAndValidate(mission, missionType)
	if mission == nil or missionType == nil or g_missionManager == nil then
		return false
	end
	mission.iaFieldsOfStoriesMission = true
	g_missionManager:registerMission(mission, missionType)
	if type(g_missionManager.updateMissions) == "function" then
		g_missionManager:updateMissions(0)
	end
	-- verify it survived validation
	for _, m in ipairs(g_missionManager.missions or {}) do
		if m == mission then
			return true
		end
	end
	return false
end

---Generate contracts for specific farmlands/fields by mission type name.
-- Uses base-game managers directly (no dependency on external_docs reference mods).
-- When the first pass returns nil, mirrors FS25_ContractTypeGenerator force path: FieldUpdateTask field prep + retry (unless opts.forcePrepareOnFailure == false).
-- @param string missionTypeName e.g. "HarvestMission"
-- @param number requestedCount how many missions to attempt
-- @param table|nil opts { farmlandIds={...}|set, fieldIds={...}|set, allowOwnedFields=bool, overrideMaxNumInstances=bool, forcePrepareOnFailure=bool }
-- @return number requestedCountSanitized, number generatedCount, table missionsGenerated
function IAHelper_generateFieldContractsByType(missionTypeName, requestedCount, opts)
	local missionsGenerated = {}
	local genCount = 0

	if g_missionManager == nil or missionTypeName == nil or missionTypeName == "" then
		return 0, 0, missionsGenerated
	end

	local numericCount = tonumber(requestedCount) or 1
	local req = math.max(1, math.floor(numericCount))

	local missionType = g_missionManager:getMissionType(missionTypeName)
	if missionType == nil or missionType.classObject == nil or type(missionType.classObject.tryGenerateMission) ~= "function" then
		return req, 0, missionsGenerated
	end

	-- optional: loosen per-type cap so the mission manager doesn't block generation
	local oldMaxNumInstances = nil
	local missionTypeData = nil
	if opts ~= nil and opts.overrideMaxNumInstances == true and type(g_missionManager.getMissionTypeDataByName) == "function" then
		missionTypeData = g_missionManager:getMissionTypeDataByName(missionTypeName)
		if missionTypeData ~= nil then
			oldMaxNumInstances = missionTypeData.maxNumInstances
			missionTypeData.maxNumInstances = math.max(missionTypeData.maxNumInstances or 0, (missionTypeData.numInstances or 0) + req)
		end
	end

	-- collect candidate fields (farmland/field filtering happens here)
	local candidates = {}
	if g_fieldManager ~= nil and type(g_fieldManager.fields) == "table" then
		for _, field in pairs(g_fieldManager.fields) do
			if iaIsFieldContractEligible(field, opts) then
				candidates[#candidates + 1] = field
			end
		end
	end

	-- shuffle so we don't always hit the same fields first
	for i = #candidates, 2, -1 do
		local j = math.random(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local classObject = missionType.classObject
	local forcePrepOnFailure = true
	if opts ~= nil and opts.forcePrepareOnFailure == false then
		forcePrepOnFailure = false
	end
	for _ = 1, req do
		local created = nil

		-- Reference: isAvailableForField before tryGenerateMission
		for _, field in ipairs(candidates) do
			local canUse = true
			if classObject.isAvailableForField ~= nil then
				local okAv, av = iaCallIsAvailableForField(classObject, field)
				if okAv then
					canUse = av
				end
			end
			if canUse then
				created = iaTryGenerateMissionOnField(classObject, field)
				if created ~= nil then
					break
				end
			end
		end

		-- Reference: force field state via FieldUpdateTask then retry (mutates terrain; disable with opts.forcePrepareOnFailure = false)
		if created == nil and forcePrepOnFailure then
			created = iaForcePrepareAndTryGenerateOnCandidates(missionTypeName, classObject, candidates)
		end

		if created == nil then
			break
		end

		if iaRegisterMissionAndValidate(created, missionType) then
			genCount = genCount + 1
			missionsGenerated[#missionsGenerated + 1] = created
		else
			-- validation removed it; stop early to avoid hammering
			break
		end
	end

	if missionTypeData ~= nil and oldMaxNumInstances ~= nil then
		missionTypeData.maxNumInstances = oldMaxNumInstances
	end

	return req, genCount, missionsGenerated
end

--- True if `tostring(value)` equals `tostring(item)` for any row in `array` (case-insensitive). Nil value, nil array, or empty array => false.
function IAHelper_valueEqualsAnyInArrayIgnoreCase(value, array)
	if value == nil or array == nil or #array == 0 then
		return false
	end
	local valueLower = string.lower(tostring(value))
	for _, item in ipairs(array) do
		if string.lower(tostring(item)) == valueLower then
			return true
		end
	end
	return false
end

--- Fisher–Yates shuffle in place. No-op when `t` is nil or has fewer than two elements.
function IAHelper_shuffleArrayInPlace(t)
	if t == nil or #t < 2 then
		return
	end
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function iaHelperFieldPolygonVertsWorld(field)
	local verts = {}
	if field == nil or field.polygonPoints == nil then
		return verts
	end
	for _, node in ipairs(field.polygonPoints) do
		if node ~= nil and entityExists(node) then
			local x, _, z = getWorldTranslation(node)
			if x ~= nil and z ~= nil then
				verts[#verts + 1] = { x = x, z = z }
			end
		end
	end
	return verts
end

local function iaHelperPointInPolygonXZ(px, pz, verts)
	local n = #verts
	if n < 3 then
		return false
	end
	local inside = false
	local j = n
	for i = 1, n do
		local vi, vj = verts[i], verts[j]
		local zi, zj = vi.z, vj.z
		if (zi > pz) ~= (zj > pz) then
			local xi, xj = vi.x, vj.x
			local denom = zj - zi
			if math.abs(denom) > 1e-9 then
				local xint = (xj - xi) * (pz - zi) / denom + xi
				if px < xint then
					inside = not inside
				end
			end
		end
		j = i
	end
	return inside
end

local function iaHelperDistPointToSeg2Sq(px, pz, ax, az, bx, bz)
	local abx, abz = bx - ax, bz - az
	local apx, apz = px - ax, pz - az
	local ab2 = abx * abx + abz * abz
	if ab2 < 1e-10 then
		return apx * apx + apz * apz
	end
	local t = math.max(0, math.min(1, (apx * abx + apz * abz) / ab2))
	local cx, cz = ax + abx * t, az + abz * t
	local dx, dz = px - cx, pz - cz
	return dx * dx + dz * dz
end

local function iaHelperMinDistSqToPolygonBorder(px, pz, verts)
	local n = #verts
	if n < 2 then
		return 0
	end
	local minD = math.huge
	for i = 1, n do
		local j = (i % n) + 1
		local vi, vj = verts[i], verts[j]
		local d = iaHelperDistPointToSeg2Sq(px, pz, vi.x, vi.z, vj.x, vj.z)
		if d < minD then
			minD = d
		end
	end
	return minD
end

local function iaHelperRngFromSeed(seed)
	local state = seed % 2147483647
	if state < 1 then
		state = 1
	end
	return function()
		state = (48271 * state) % 2147483647
		return (state - 1) / 2147483646
	end
end

local function iaHelperPolygonCentroidXZ(verts)
	local n = #verts
	if n < 1 then
		return 0, 0
	end
	local sx, sz = 0, 0
	for i = 1, n do
		sx = sx + verts[i].x
		sz = sz + verts[i].z
	end
	return sx / n, sz / n
end

--- Exterior probe distances (m) along −inward normal; edge is outer border only if every probe is outside the polygon ring.
IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M = { 2, 5, 15, 30 }
--- Inward probe (m): must be inside the field ring (rejects narrow strips between island and outer border).
IAHelper_FIELD_BORDER_INTERIOR_PROBE_M = 15
--- Largest exterior probe distance (for legacy callers / log messages).
IAHelper_FIELD_BORDER_EXTERIOR_PROBE_M = 30

--- Edge midpoint, unit tangent (A→B), and inward normal (toward polygon centroid).
local function iaHelperEdgeMidpointAndInwardNormal(ax, az, bx, bz, cx, cz)
	local ex, ez = bx - ax, bz - az
	local elen = math.sqrt(ex * ex + ez * ez)
	if elen < 1e-6 then
		return nil
	end
	local tx, tz = ex / elen, ez / elen
	local mx, mz = 0.5 * (ax + bx), 0.5 * (az + bz)
	local nix, niz = -tz, tx
	local toCx, toCz = cx - mx, cz - mz
	if nix * toCx + niz * toCz < 0 then
		nix, niz = -nix, -niz
	end
	return mx, mz, tx, tz, nix, niz
end

--- True when every exterior probe is outside the ring and the inward interior probe is inside (real outer border with field depth).
local function iaHelperIsOuterFieldBorderEdge(verts, ax, az, bx, bz, cx, cz)
	local mx, mz, _, _, nix, niz = iaHelperEdgeMidpointAndInwardNormal(ax, az, bx, bz, cx, cz)
	if mx == nil then
		return false
	end
	local dists = IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M
	if dists == nil or #dists < 1 then
		dists = { 15 }
	end
	for _, dist in ipairs(dists) do
		local d = tonumber(dist)
		if d ~= nil and d > 0 then
			local ex, ez = mx - nix * d, mz - niz * d
			if iaHelperPointInPolygonXZ(ex, ez, verts) then
				return false
			end
		end
	end
	local intM = tonumber(IAHelper_FIELD_BORDER_INTERIOR_PROBE_M)
	if intM == nil or intM <= 0 then
		intM = 15
	end
	local ix, iz = mx + nix * intM, mz + niz * intM
	if not iaHelperPointInPolygonXZ(ix, iz, verts) then
		return false
	end
	return true
end

--- Debug markers for each exterior probe distance (tier rises with distance).
local function iaHelperDbgExteriorProbes(dbg, mx, mz, nix, niz, labelPrefix)
	if dbg == nil or mx == nil or mz == nil or nix == nil or niz == nil then
		return
	end
	local dists = IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M or { 15 }
	local tierByIndex = { 1, 2, 3, 4 }
	for i, dist in ipairs(dists) do
		local d = tonumber(dist)
		if d ~= nil and d > 0 then
			dbg(mx - nix * d, mz - niz * d, labelPrefix .. " ext " .. tostring(d) .. "m", tierByIndex[i] or 2)
		end
	end
end

local function iaHelperTooCloseToAny(px, pz, list, minDist2)
	for _, q in ipairs(list) do
		if q.x ~= nil and q.z ~= nil then
			local dx, dz = px - q.x, pz - q.z
			if dx * dx + dz * dz < minDist2 then
				return true
			end
		end
	end
	return false
end

local function iaHelperEvenlyPickSubsetByIndex(nFull, maxPick)
	if maxPick <= 0 then
		return {}
	end
	if nFull <= maxPick then
		local t = {}
		for i = 1, nFull do
			t[i] = i
		end
		return t
	end
	if maxPick == 1 then
		return { math.max(1, math.floor(nFull / 2)) }
	end
	local t = {}
	for k = 1, maxPick do
		t[k] = math.floor((k - 1) * (nFull - 1) / (maxPick - 1)) + 1
	end
	return t
end

local function iaHelperFieldInteriorSeed(field)
	local nPoly = 0
	if field ~= nil and type(field.polygonPoints) == "table" then
		nPoly = #field.polygonPoints
	end
	local h = (nPoly * 7919) % 2147483647
	if field ~= nil and field.rootNode ~= nil then
		h = (h + (field.rootNode % 2147483647)) % 2147483647
	end
	if field ~= nil and type(field.getAreaHa) == "function" then
		local ok, ha = pcall(field.getAreaHa, field)
		if ok and ha ~= nil then
			h = (h + math.floor((ha or 0) * 1000 + 0.5)) % 2147483647
		end
	end
	if field ~= nil and field.name ~= nil then
		local name = tostring(field.name)
		for c = 1, math.min(#name, 64) do
			h = (h * 31 + string.byte(name, c)) % 2147483647
		end
	end
	if h < 1 then
		h = 1
	end
	return h
end

--- World XZ samples strictly inside the field polygon (not on the boundary ring).
-- Uses axis-aligned bbox rejection, ray-cast point-in-polygon, and a minimum distance from polygon edges so probes sit in the interior.
-- @param table field FS Field with polygonPoints (scene node ids)
-- @param number count how many distinct points to try to return (may be fewer if the field is thin or attempts exhaust)
-- @param table|nil exclude optional array of { x = number, z = number } — new points stay at least ~0.5 m away from these
-- @return table array of { x = number, z = number } world coordinates
function IAHelper_getRandomPointsInField(field, count, exclude)
	local out = {}
	local nWant = math.max(0, math.floor(tonumber(count) or 0))
	if nWant < 1 or field == nil then
		return out
	end
	local excludeList = exclude
	if excludeList == nil or type(excludeList) ~= "table" then
		excludeList = {}
	end

	local verts = iaHelperFieldPolygonVertsWorld(field)
	local n = #verts
	if n < 3 then
		if type(field.getCenterOfFieldWorldPosition) == "function" then
			local cx, cz = field:getCenterOfFieldWorldPosition()
			if cx ~= nil and cz ~= nil then
				out[1] = { x = cx, z = cz }
			end
		end
		return out
	end

	local minX, maxX = verts[1].x, verts[1].x
	local minZ, maxZ = verts[1].z, verts[1].z
	for i = 2, n do
		local p = verts[i]
		minX = math.min(minX, p.x)
		maxX = math.max(maxX, p.x)
		minZ = math.min(minZ, p.z)
		maxZ = math.max(maxZ, p.z)
	end

	local spanX = maxX - minX
	local spanZ = maxZ - minZ
	if spanX < 1e-4 or spanZ < 1e-4 then
		if type(field.getCenterOfFieldWorldPosition) == "function" then
			local cx, cz = field:getCenterOfFieldWorldPosition()
			if cx ~= nil and cz ~= nil then
				out[1] = { x = cx, z = cz }
			end
		end
		return out
	end

	local rng = iaHelperRngFromSeed(iaHelperFieldInteriorSeed(field))
	local minSep2 = 0.25
	local margins = { 0.85, 0.45, 0.15, 0.0 }
	local maxAttemptsTotal = math.max(400, nWant * 300)

	for _, margin in ipairs(margins) do
		local marginSq = margin * margin
		local attempts = 0
		while #out < nWant and attempts < maxAttemptsTotal do
			attempts = attempts + 1
			local rx = minX + rng() * spanX
			local rz = minZ + rng() * spanZ
			if iaHelperPointInPolygonXZ(rx, rz, verts) then
				if marginSq <= 0 or iaHelperMinDistSqToPolygonBorder(rx, rz, verts) > marginSq then
					local dup = false
					for _, p in ipairs(out) do
						local dx, dz = p.x - rx, p.z - rz
						if dx * dx + dz * dz < minSep2 then
							dup = true
							break
						end
					end
					if not dup and not iaHelperTooCloseToAny(rx, rz, excludeList, minSep2) then
						out[#out + 1] = { x = rx, z = rz }
					end
				end
			end
		end
		if #out >= nWant then
			break
		end
	end

	return out
end

--- Internal: longest-edge border spawn pose plus debug markers for field border / alignment visualization.
-- debugOut: optional array of { x, z, label, tier } points (tier 1=small … 4=tall pillar) or { segment=true, x1,z1,x2,z2,label }.
-- @return number|nil px, number|nil pz, number|nil yaw, table|nil debugOut
local function iaHelperComputeFieldBorderSpawnPoseInternal(field, combinedWidth, clearanceM, debugOut)
	local verts = iaHelperFieldPolygonVertsWorld(field)
	local n = #verts
	if n < 3 then
		return nil
	end
	local function dbg(x, z, label, tier)
		if debugOut ~= nil and x ~= nil and z ~= nil then
			debugOut[#debugOut + 1] = { x = x, z = z, label = label, tier = tier or 1 }
		end
	end
	local function dbgSeg(x1, z1, x2, z2, label)
		if debugOut ~= nil and x1 ~= nil and z1 ~= nil and x2 ~= nil and z2 ~= nil then
			debugOut[#debugOut + 1] = { segment = true, x1 = x1, z1 = z1, x2 = x2, z2 = z2, label = label }
		end
	end

	local clearM = tonumber(clearanceM)
	if clearM == nil or clearM < 0 then
		clearM = 0.75
	end
	local minOffset = 1.5
	local halfW = 0.5 * math.max(0, tonumber(combinedWidth) or 0)
	local d = math.max(halfW + clearM, minOffset)

	for i = 1, n do
		dbg(verts[i].x, verts[i].z, "[POLY] V" .. tostring(i), 1)
	end

	local cx, cz = iaHelperPolygonCentroidXZ(verts)
	dbg(cx, cz, "[CTR] centroid", 2)

	local bestOuterLenSq = -1
	local bestOuterI = nil
	local longestLenSq = -1
	local longestI = 1
	for i = 1, n do
		local ax, az = verts[i].x, verts[i].z
		local j = (i % n) + 1
		local bx, bz = verts[j].x, verts[j].z
		local ex, ez = bx - ax, bz - az
		local lenSq = ex * ex + ez * ez
		if lenSq > longestLenSq then
			longestLenSq = lenSq
			longestI = i
		end
		if lenSq > 1e-8 and iaHelperIsOuterFieldBorderEdge(verts, ax, az, bx, bz, cx, cz) then
			if lenSq > bestOuterLenSq then
				bestOuterLenSq = lenSq
				bestOuterI = i
			end
		end
	end

	local bestI = bestOuterI
	local usedOuterFilter = bestI ~= nil
	if bestI == nil then
		bestI = longestI
		if IANeighbours ~= nil and IANeighbours.debug then
			local distList = "2/5/15/30m"
			if IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M ~= nil then
				local parts = {}
				for _, d in ipairs(IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M) do
					table.insert(parts, tostring(d))
				end
				if #parts > 0 then
					distList = table.concat(parts, "/") .. "m"
				end
			end
			print(string.format(
				"--- IAHelper border spawn: no outer edge passed ext (%s) + int %.0fm inside; fallback to longest edge index %d",
				distList,
				tonumber(IAHelper_FIELD_BORDER_INTERIOR_PROBE_M) or 15,
				bestI
			))
		end
	elseif longestI ~= bestI and longestLenSq > bestOuterLenSq and debugOut ~= nil then
		local lj = (longestI % n) + 1
		local lax, laz = verts[longestI].x, verts[longestI].z
		local lbx, lbz = verts[lj].x, verts[lj].z
		local lmx, lmz, _, _, lnix, lniz = iaHelperEdgeMidpointAndInwardNormal(lax, laz, lbx, lbz, cx, cz)
		if lmx ~= nil then
			dbg(lax, laz, "[REJ] edgeA (longest)", 2)
			dbg(lbx, lbz, "[REJ] edgeB (longest)", 2)
			dbg(lmx, lmz, "[REJ] edgeMid", 2)
			iaHelperDbgExteriorProbes(dbg, lmx, lmz, lnix, lniz, "[REJ]")
			local rejIntM = tonumber(IAHelper_FIELD_BORDER_INTERIOR_PROBE_M) or 15
			dbg(lmx + lnix * rejIntM, lmz + lniz * rejIntM, "[REJ] int " .. tostring(rejIntM) .. "m", 2)
			dbgSeg(lax, laz, lbx, lbz, "[REJ] edge line")
		end
	end

	local bestLenSq = usedOuterFilter and bestOuterLenSq or longestLenSq
	if bestLenSq < 1e-8 then
		return nil
	end
	local jBest = (bestI % n) + 1
	local ax, az = verts[bestI].x, verts[bestI].z
	local bx, bz = verts[jBest].x, verts[jBest].z
	dbg(ax, az, "[EDGE] A (chosen)", 3)
	dbg(bx, bz, "[EDGE] B (chosen)", 3)
	dbgSeg(ax, az, bx, bz, "[EDGE] chosen line")

	local mx, mz, tx, tz, nix, niz = iaHelperEdgeMidpointAndInwardNormal(ax, az, bx, bz, cx, cz)
	if mx == nil then
		return nil
	end
	dbg(mx, mz, "[EDGE] mid", 2)
	iaHelperDbgExteriorProbes(dbg, mx, mz, nix, niz, "[OUT]")
	local intCheckM = tonumber(IAHelper_FIELD_BORDER_INTERIOR_PROBE_M) or 15
	dbg(mx + nix * intCheckM, mz + niz * intCheckM, "[IN] check " .. tostring(intCheckM) .. "m", 3)
	dbg(mx + nix * d, mz + niz * d, "[IN] inset " .. string.format("%.2fm", d), 2)
	local maxProbeM = IAHelper_FIELD_BORDER_EXTERIOR_PROBE_M
	if IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M ~= nil and #IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M > 0 then
		maxProbeM = IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M[#IAHelper_FIELD_BORDER_EXTERIOR_PROBE_DISTANCES_M]
	end
	dbgSeg(mx - nix * maxProbeM, mz - niz * maxProbeM, mx + nix * d, mz + niz * d, "[IN/OUT] normal")

	local dist = d
	local guard = 0
	while guard < 24 do
		local px, pz = mx + nix * dist, mz + niz * dist
		if iaHelperPointInPolygonXZ(px, pz, verts) then
			local yaw = nil
			if MathUtil ~= nil and type(MathUtil.getYRotationFromDirection) == "function" then
				yaw = MathUtil.getYRotationFromDirection(tx, tz)
			else
				yaw = math.atan2(tx, tz)
			end
			dbg(px, pz, "[SPAWN] vehicle pose", 4)
			dbg(px + tx * 4, pz + tz * 4, "[YAW+] heading", 2)
			dbg(px - tx * 4, pz - tz * 4, "[YAW-] back", 1)
			dbgSeg(px, pz, px + tx * 4, pz + tz * 4, "[YAW] forward")
			return px, pz, yaw, debugOut
		end
		dist = dist * 0.85
		if dist < 0.25 then
			break
		end
		guard = guard + 1
	end
	return nil
end

--- World spawn pose on the longest valid outer polygon edge (exterior probe filter rejects island/bridge edges), inset inward by half combined width + clearance.
-- @param table field FS Field with polygonPoints (scene nodes)
-- @param number combinedWidth max work-area width (m) across tractor + attachments — half is used for inset
-- @param number|nil clearanceM extra margin beyond half-width (default 0.75); absolute minimum offset 1.5 m
-- @return number|nil x, number|nil z, number|nil yaw radians (along the edge tangent)
function IAHelper_computeFieldBorderSpawnPose(field, combinedWidth, clearanceM)
	local px, pz, yaw = iaHelperComputeFieldBorderSpawnPoseInternal(field, combinedWidth, clearanceM, nil)
	return px, pz, yaw
end

--- Debug markers for field-border spawn geometry (polygon verts, longest edge, inset, spawn, yaw alignment).
-- @return table array of { x, z, label, tier } or { segment=true, x1, z1, x2, z2, label }
function IAHelper_collectFieldBorderSpawnDebugPoints(field, combinedWidth, clearanceM)
	local out = {}
	iaHelperComputeFieldBorderSpawnPoseInternal(field, combinedWidth, clearanceM, out)
	return out
end

--- For each polygon vertex, one point offset toward the field interior (centroid direction) by a random distance in [insetMinM, insetMaxM] meters, clamped to stay inside the polygon.
-- @param table field FS Field with polygonPoints
-- @param number insetMinM e.g. 5
-- @param number insetMaxM e.g. 10
-- @param number|nil maxCount optional cap; if set and vertex count exceeds it, evenly subsamples which vertices get probes
-- @return table array of { x = number, z = number }
function IAHelper_getBorderInsetProbePoints(field, insetMinM, insetMaxM, maxCount)
	local out = {}
	if field == nil then
		return out
	end
	local verts = iaHelperFieldPolygonVertsWorld(field)
	local n = #verts
	if n < 3 then
		return out
	end

	local minM = math.max(0, tonumber(insetMinM) or 5)
	local maxM = math.max(minM, tonumber(insetMaxM) or 10)

	local cx, cz = iaHelperPolygonCentroidXZ(verts)
	local rng = iaHelperRngFromSeed((iaHelperFieldInteriorSeed(field) + 17011) % 2147483647)

	local useIdx = {}
	for i = 1, n do
		useIdx[i] = i
	end
	local cap = tonumber(maxCount)
	if cap ~= nil and cap > 0 and n > cap then
		useIdx = iaHelperEvenlyPickSubsetByIndex(n, math.floor(cap))
	end

	for _, vi in ipairs(useIdx) do
		local v = verts[vi]
		local vx, vz = v.x, v.z
		local tx, tz = cx - vx, cz - vz
		local len = math.sqrt(tx * tx + tz * tz)
		if len > 1e-3 then
			local ux, uz = tx / len, tz / len
			local targetDist = minM + rng() * (maxM - minM)
			local d = targetDist
			local px, pz = vx + ux * d, vz + uz * d
			local guard = 0
			while (not iaHelperPointInPolygonXZ(px, pz, verts)) and d > 0.25 and guard < 24 do
				d = d * 0.82
				px, pz = vx + ux * d, vz + uz * d
				guard = guard + 1
			end
			if iaHelperPointInPolygonXZ(px, pz, verts) and not iaHelperTooCloseToAny(px, pz, out, 0.25) then
				out[#out + 1] = { x = px, z = pz }
			end
		end
	end

	return out
end

--- Fix selectedItemIndex when items[index] is missing (avoids PlayerStyle async nil.filename).
function iaCoercePlayerStyleSlotItem(slot, slotName, wantedIndex, debugPrefix)
	if slot == nil or slot.items == nil then
		return
	end
	local idx = slot.selectedItemIndex
	if slot.items[idx] ~= nil then
		return
	end
	local function tryPick(c)
		if c == nil or slot.items[c] == nil then
			return false
		end
		slot.selectedItemIndex = c
		if slot.selectedColorIndex == nil or slot.selectedColorIndex < 1 then
			slot.selectedColorIndex = 1
		end
		return true
	end
	if tryPick(0) or tryPick(1) then
		if IANeighbours and IANeighbours.debug and debugPrefix then
			print(debugPrefix .. " — slot " .. tostring(slotName) .. ": index " .. tostring(wantedIndex or idx) .. " missing in catalogue, using " .. tostring(slot.selectedItemIndex))
		end
		return
	end
	for i, it in pairs(slot.items) do
		if it ~= nil then
			slot.selectedItemIndex = i
			slot.selectedColorIndex = 1
			if IANeighbours and IANeighbours.debug and debugPrefix then
				print(debugPrefix .. " — slot " .. tostring(slotName) .. ": index " .. tostring(wantedIndex or idx) .. " missing, fallback " .. tostring(i))
			end
			return
		end
	end
end

--- hatHairstyleIndex must reference a hairStyle item with forHat (see PlayerStyle:loadConfigurationXML). XML hathair="0" or invalid index causes nil.filename in async load.
function iaLastForHatHairIndex(items)
	if items == nil then
		return nil
	end
	for i = #items, 1, -1 do
		local it = items[i]
		if it and it.forHat then
			return i
		end
	end
	return nil
end

function iaResolveHatHairstyleIndex(style, cfg, p, debugPrefix)
	local items = cfg.hairStyle and cfg.hairStyle.items
	local fallback = iaLastForHatHairIndex(items)
	if fallback == nil and items ~= nil and items[1] ~= nil then
		fallback = 1
	end
	if fallback == nil then
		fallback = 12
	end
	local function isUsableHatIdx(idx)
		if idx == nil or idx < 1 or items == nil or items[idx] == nil then
			return false
		end
		return items[idx].forHat == true
	end
	local cur = style.hatHairstyleIndex
	local h = p.hathair
	if h == nil then
		if isUsableHatIdx(cur) then
			return
		end
		style.hatHairstyleIndex = fallback
		return
	end
	if isUsableHatIdx(h) then
		style.hatHairstyleIndex = h
		return
	end
	if isUsableHatIdx(cur) then
		if IANeighbours and IANeighbours.debug and debugPrefix then
			print(debugPrefix .. " — hatHairstyleIndex: " .. tostring(h) .. " invalid, keep template " .. tostring(cur))
		end
		return
	end
	style.hatHairstyleIndex = fallback
	if IANeighbours and IANeighbours.debug and debugPrefix then
		print(debugPrefix .. " — hatHairstyleIndex: " .. tostring(h) .. " -> " .. tostring(fallback))
	end
end

--- Apply outbound/XML character style field table to a PlayerStyle (indices + color slots).
--- @param style PlayerStyle|nil
--- @param p table|nil hathair, glasses, glassesColorIndex, ...
--- @param debugPrefix string|nil optional log prefix when IANeighbours.debug
function applyPlayerStyleParamTable(style, p, debugPrefix)
	if style == nil or p == nil or style.configs == nil then
		return
	end
	local cfg = style.configs

	iaResolveHatHairstyleIndex(style, cfg, p, debugPrefix)
	if cfg.glasses then
		cfg.glasses.selectedItemIndex = 0
		cfg.glasses.selectedColorIndex = 1
	end
	if cfg.facegear then
		cfg.facegear.selectedItemIndex = 0
		cfg.facegear.selectedColorIndex = 1
	end
	if cfg.onepiece then
		cfg.onepiece.selectedItemIndex = 0
		cfg.onepiece.selectedColorIndex = 1
	end
	if cfg.bottom then
		cfg.bottom.selectedItemIndex = 0
		cfg.bottom.selectedColorIndex = 1
	end
	if cfg.face then
		cfg.face.selectedItemIndex = 1
		cfg.face.selectedColorIndex = 1
	end
	if cfg.top then
		cfg.top.selectedItemIndex = 0
		cfg.top.selectedColorIndex = 1
	end
	if cfg.gloves then
		cfg.gloves.selectedItemIndex = 0
		cfg.gloves.selectedColorIndex = 1
	end
	if cfg.headgear then
		cfg.headgear.selectedItemIndex = 0
		cfg.headgear.selectedColorIndex = 1
	end
	if cfg.footwear then
		cfg.footwear.selectedItemIndex = 0
		cfg.footwear.selectedColorIndex = 1
	end
	if cfg.hairStyle then
		cfg.hairStyle.selectedItemIndex = 0
		cfg.hairStyle.selectedColorIndex = 1
	end
	if cfg.beard then
		cfg.beard.selectedItemIndex = 0
		cfg.beard.selectedColorIndex = 1
	end

	local glasses = p.glasses or 0
	local glassesColorIndex = p.glassesColorIndex or 1
	local facegear = p.facegear or 0
	local facegearColorIndex = p.facegearColorIndex or 1
	local onepiece = p.onepiece or 0
	local onepieceColorIndex = p.onepieceColorIndex or 1
	local bottom = p.bottom or 0
	local bottomColorIndex = p.bottomColorIndex or 1
	local face = p.face or 1
	local faceColorIndex = p.faceColorIndex or 1
	local top = p.top or 0
	local topColorIndex = p.topColorIndex or 1
	-- One-piece replaces top + bottom; clear indices so we do not apply shirt/pants and iaCoerce does not pick item 1 as fallback.
	if onepiece > 0 then
		top = 0
		bottom = 0
		topColorIndex = 1
		bottomColorIndex = 1
	end
	local gloves = p.gloves or 0
	local glovesColorIndex = p.glovesColorIndex or 1
	local headgear = p.headgear or 0
	local headgearColorIndex = p.headgearColorIndex or 1
	local footwear = p.footwear or 1
	local footwearColorIndex = p.footwearColorIndex or 1
	local hairStyle = p.hairStyle or 1
	local hairStyleColorIndex = p.hairStyleColorIndex or 1
	local beard = p.beard or 0
	local beardColorIndex = p.beardColorIndex or 1

	if cfg.glasses and cfg.glasses.items then
		for i, item in pairs(cfg.glasses.items) do
			if i == glasses then
				cfg.glasses.selectedItemIndex = i
				if item.colorableSlots > 0 and glassesColorIndex > 0 then
					cfg.glasses.selectedColorIndex = glassesColorIndex
				else
					cfg.glasses.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.facegear and cfg.facegear.items then
		for i, item in pairs(cfg.facegear.items) do
			if i == facegear then
				cfg.facegear.selectedItemIndex = i
				if item.colorableSlots > 0 and facegearColorIndex > 0 then
					cfg.facegear.selectedColorIndex = facegearColorIndex
				else
					cfg.facegear.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.onepiece and cfg.onepiece.items then
		for i, item in pairs(cfg.onepiece.items) do
			if i == onepiece then
				cfg.onepiece.selectedItemIndex = i
				if item.colorableSlots > 0 and onepieceColorIndex > 0 then
					cfg.onepiece.selectedColorIndex = onepieceColorIndex
				else
					cfg.onepiece.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.bottom and cfg.bottom.items then
		for i, item in pairs(cfg.bottom.items) do
			if i == bottom and bottom ~= 0 then
				if item.colorableSlots > 0 then
					cfg.bottom.selectedItemIndex = i
					if bottomColorIndex > 0 then
						cfg.bottom.selectedColorIndex = bottomColorIndex
					else
						cfg.bottom.selectedColorIndex = 1
					end
				else
					if IANeighbours and IANeighbours.debug and debugPrefix then
						print(debugPrefix .. " - BOTTOM skip due to missing colorize")
					end
					cfg.bottom.selectedItemIndex = 1
					cfg.bottom.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.face and cfg.face.items then
		for i, item in pairs(cfg.face.items) do
			if i == face then
				cfg.face.selectedItemIndex = i
				if item.colorableSlots > 0 and faceColorIndex > 0 then
					cfg.face.selectedColorIndex = faceColorIndex
				else
					cfg.face.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.top and cfg.top.items then
		for i, item in pairs(cfg.top.items) do
			if i == top and top ~= 0 then
				if item.colorableSlots > 0 then
					cfg.top.selectedItemIndex = i
					if topColorIndex > 0 then
						cfg.top.selectedColorIndex = topColorIndex
					else
						cfg.top.selectedColorIndex = 1
					end
				else
					if IANeighbours and IANeighbours.debug and debugPrefix then
						print(debugPrefix .. " - TOP skip due to missing colorize")
					end
					cfg.top.selectedItemIndex = 1
					cfg.top.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.gloves and cfg.gloves.items then
		for i, item in pairs(cfg.gloves.items) do
			if i == gloves and i ~= 0 then
				if item.colorableSlots > 0 then
					cfg.gloves.selectedItemIndex = i
					if glovesColorIndex > 0 then
						cfg.gloves.selectedColorIndex = glovesColorIndex
					else
						cfg.gloves.selectedColorIndex = 1
					end
				else
					if IANeighbours and IANeighbours.debug and debugPrefix then
						print(debugPrefix .. " - Gloves skip due to missing colorize: " .. tostring(i))
					end
					cfg.gloves.selectedItemIndex = 1
					cfg.gloves.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.headgear and cfg.headgear.items then
		for i, item in pairs(cfg.headgear.items) do
			if i == headgear then
				cfg.headgear.selectedItemIndex = i
				if item.colorableSlots > 0 and headgearColorIndex > 0 then
					cfg.headgear.selectedColorIndex = headgearColorIndex
				else
					cfg.headgear.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.footwear and cfg.footwear.items then
		for i, item in pairs(cfg.footwear.items) do
			if i == footwear then
				cfg.footwear.selectedItemIndex = i
				if item.colorableSlots > 0 and footwearColorIndex > 0 then
					cfg.footwear.selectedColorIndex = footwearColorIndex
				else
					cfg.footwear.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.hairStyle and cfg.hairStyle.items then
		for i, item in pairs(cfg.hairStyle.items) do
			if i == hairStyle then
				cfg.hairStyle.selectedItemIndex = i
				if item.colorableSlots > 0 and hairStyleColorIndex > 0 then
					cfg.hairStyle.selectedColorIndex = hairStyleColorIndex
				else
					cfg.hairStyle.selectedColorIndex = 1
				end
			end
		end
	end
	if cfg.beard and cfg.beard.items then
		for i, item in pairs(cfg.beard.items) do
			if i == beard then
				cfg.beard.selectedItemIndex = i
				if item.colorableSlots > 0 and beardColorIndex > 0 then
					cfg.beard.selectedColorIndex = beardColorIndex
				else
					cfg.beard.selectedColorIndex = 1
				end
			end
		end
	end

	iaCoercePlayerStyleSlotItem(cfg.glasses, "glasses", glasses, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.facegear, "facegear", facegear, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.onepiece, "onepiece", onepiece, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.face, "face", face, debugPrefix)
	-- With a one-piece outfit, keep top/bottom at cleared reset (0); coercing "missing index 0" would pick item 1 and overlap meshes.
	if onepiece <= 0 then
		iaCoercePlayerStyleSlotItem(cfg.bottom, "bottom", bottom, debugPrefix)
		iaCoercePlayerStyleSlotItem(cfg.top, "top", top, debugPrefix)
	else
		if cfg.bottom ~= nil then
			cfg.bottom.selectedItemIndex = 0
			cfg.bottom.selectedColorIndex = 1
		end
		if cfg.top ~= nil then
			cfg.top.selectedItemIndex = 0
			cfg.top.selectedColorIndex = 1
		end
	end
	iaCoercePlayerStyleSlotItem(cfg.gloves, "gloves", gloves, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.headgear, "headgear", headgear, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.footwear, "footwear", footwear, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.hairStyle, "hairStyle", hairStyle, debugPrefix)
	iaCoercePlayerStyleSlotItem(cfg.beard, "beard", beard, debugPrefix)
end

--- Compute the 4 world-space corners of a place debug box. Order FL, FR, RR, RL so consecutive entries
-- (and last→first) form the 4 box edges for line drawing. Each corner Y is sampled from terrain per corner
-- (box follows the ground), lifted by `lift`; falls back to centerY when terrain is unavailable.
-- Single source of truth for both map-init place boxes and borrow return boxes (FS convention: rotation 0 = forward is −Z; front uses +local Z offset).
-- Box length/half-width come from IANeighbours.getPlaceDebugBoxLength / getPlaceDebugBoxSide.
-- @return table|nil corners array of { x = number, y = number, z = number }
function IAHelper_computePlaceDebugBoxCorners(centerX, centerY, centerZ, rotationY, withVehicle, withAttachment, sizeType, lift)
	if centerX == nil or centerZ == nil or getWorldPositionFromYawLocalOffset == nil or IANeighbours == nil then
		return nil
	end
	local boxLength = IANeighbours.getPlaceDebugBoxLength(withVehicle, withAttachment, sizeType)
	if boxLength == nil or boxLength <= 0 then
		return nil
	end
	local front = IANeighbours.PLACE_DEBUG_FRONT_M or 3
	local back = math.max(0, boxLength - front)
	local side = IANeighbours.getPlaceDebugBoxSide(withVehicle, withAttachment, sizeType) or IANeighbours.PLACE_DEBUG_SIDE_M or 1.5
	local rot = rotationY or 0
	local liftV = lift or 0.25
	local localOffsets = {
		{ -side,  front },
		{  side,  front },
		{  side, -back  },
		{ -side, -back  },
	}
	local corners = {}
	for _, off in ipairs(localOffsets) do
		local wx, _, wz = getWorldPositionFromYawLocalOffset(centerX, centerY or 0, centerZ, rot, off[1], 0, off[2])
		if wx == nil or wz == nil then
			return nil
		end
		local wy = centerY
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local ty = getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz)
			if ty ~= nil then
				wy = ty
			end
		end
		corners[#corners + 1] = { x = wx, y = (wy or 0) + liftV, z = wz }
	end
	return corners
end

--- Store a place debug box (4 connected edges) on ianeighbours.mapInitPlaceDebugBoxes, drawn as gray line
-- segments in update — same style as the borrow return boxes (no corner dots, no scene nodes). The center
-- label/point is handled separately by addPlaceDebugPointsAt. Does nothing when the place has no box size.
function IAHelper_addPlaceDebugBox(ianeighbours, x, y, z, rotationY, withVehicle, withAttachment, sizeType)
	if ianeighbours == nil then
		return
	end
	local corners = IAHelper_computePlaceDebugBoxCorners(x, y, z, rotationY, withVehicle, withAttachment, sizeType, 0.25)
	if corners == nil then
		return
	end
	ianeighbours.mapInitPlaceDebugBoxes = ianeighbours.mapInitPlaceDebugBoxes or {}
	table.insert(ianeighbours.mapInitPlaceDebugBoxes, {
		corners = corners,
		centerX = x,
		centerY = y or 0,
		centerZ = z,
	})
end

--- Draw all stored map-init place debug boxes as connected gray line segments (borrow-return box style).
-- Applies the same range filter as debug points; pass nil ref to skip filtering.
function IAHelper_drawMapInitPlaceDebugBoxes(ianeighbours, refX, refY, refZ, rangeSq)
	if ianeighbours == nil or ianeighbours.mapInitPlaceDebugBoxes == nil or drawDebugLine == nil then
		return
	end
	local maxSq = rangeSq or (50 * 50)
	for _, box in ipairs(ianeighbours.mapInitPlaceDebugBoxes) do
		if box ~= nil and box.corners ~= nil then
			local inRange = true
			if refX ~= nil and refY ~= nil and refZ ~= nil and box.centerX ~= nil and box.centerZ ~= nil then
				local dx, dy, dz = box.centerX - refX, (box.centerY or 0) - refY, box.centerZ - refZ
				inRange = (dx * dx + dy * dy + dz * dz) <= maxSq
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
			end
		end
	end
end

-- ============================================================================
-- Frame / function profiling
-- High-resolution wall-clock timing for measuring how long a block of code takes.
-- Pair IAHelper_frameTimerStart() with IAHelper_frameTimerEnd(...).
-- ============================================================================

--- Start a high-resolution wall-clock timer.
--- @return number|nil startSec high-precision seconds handle (nil if engine timer unavailable)
function IAHelper_frameTimerStart()
	if getTimeSec == nil then
		return nil
	end
	return getTimeSec()
end

--- Report the elapsed wall-clock time (ms) since startSec, printing only when it exceeds thresholdMs.
--- @param startSec number|nil value returned by IAHelper_frameTimerStart (nil = no-op, returns 0)
--- @param thresholdMs number|nil print only when elapsed is strictly greater than this (nil = always print)
--- @param label string|nil log prefix (defaults to "IA")
--- @return number elapsedMs milliseconds elapsed since startSec
function IAHelper_frameTimerEnd(startSec, thresholdMs, label)
	if startSec == nil or getTimeSec == nil then
		return 0
	end
	local elapsedMs = (getTimeSec() - startSec) * 1000
	if thresholdMs == nil or elapsedMs > thresholdMs then
		print(string.format("[%s] frame time: %.3f ms", label or "IA", elapsedMs))
	end
	return elapsedMs
end

--- Internal helper for IAHelper_profileWrap: report timing (after the wrapped call finished),
--- then transparently pass through every return value of the wrapped function (preserves nils/count).
--- @param startSec number|nil timer handle from IAHelper_frameTimerStart
--- @param label string|nil log prefix / function name
function IAHelper_frameTimerEndPassthrough(startSec, label, ...)
	local thresholdMs = (IANeighbours ~= nil) and IANeighbours.frameTimeLogThresholdMs or nil
	IAHelper_frameTimerEnd(startSec, thresholdMs, label)
	return ...
end

--- Wrap a function so every call is wall-clock profiled. The elapsed time is printed (with the
--- function name) only when it exceeds the shared threshold IANeighbours.frameTimeLogThresholdMs.
--- Arguments and all return values are preserved, so this is safe to apply to class methods
--- (the implicit self is passed through as the first argument).
--- @param label string log prefix / function name shown in the log
--- @param fn function function to wrap (returned unchanged if not callable)
--- @return function wrapped wrapped function (or the original value if fn was not a function)
function IAHelper_profileWrap(label, fn)
	if type(fn) ~= "function" then
		return fn
	end
	return function(...)
		local startSec = IAHelper_frameTimerStart()
		return IAHelper_frameTimerEndPassthrough(startSec, label, fn(...))
	end
end

-- ============================================================================
-- Combine auger pipe (spout) folding
-- The auger spout is driven by the Pipe specialization (vehicle.spec_pipe), NOT
-- by the generic Foldable spec. For this combine the dump shows:
--   foldMinState = 1 (pipe in / folded), foldMaxState = 2 (pipe out),
--   animation.name = "pipeAnim", foldMinTime = 0, foldMaxTime = 1.
-- So "folded in" = foldMinState, animation snapped to foldMinTime.
-- ============================================================================

--- Snap a vehicle's pipe animation to the time matching the given pipe state.
--- Handles cases where foldMinTime / foldMaxTime differ from the defaults, and
--- multi-section pipes with their own animation tracks (one call per vehicle).
--- @param vehicle table game vehicle (any object with setAnimationTime)
--- @param spec table spec_pipe from the vehicle
--- @param state number the pipe state that was just set (foldMinState or foldMaxState)
function IAHelper_snapPipeAnimation(vehicle, spec, state)
	if vehicle == nil or spec == nil then
		return
	end
	if type(vehicle.setAnimationTime) ~= "function" then
		return
	end

	-- When foldMinTime == foldMaxTime, the animation is clip-based (not a time blend).
	-- setAnimationTime has no visible effect in this case — the caller should handle
	-- visual update by calling setPipeState without instant flag instead.
	if spec.foldMinTime ~= nil and spec.foldMaxTime ~= nil
		and math.abs(spec.foldMinTime - spec.foldMaxTime) < 0.001 then
		return
	end

	-- Determine the animation time corresponding to the given state.
	local targetTime
	if state == spec.foldMinState then
		targetTime = spec.foldMinTime
	elseif state == spec.foldMaxState then
		targetTime = spec.foldMaxTime
	else
		-- Interpolate between min and max for intermediate states (rare, but safe).
		local minS = spec.foldMinState or 0
		local maxS = spec.foldMaxState or 1
		local minT = spec.foldMinTime or 0
		local maxT = spec.foldMaxTime or 1
		local rangeS = maxS - minS
		if rangeS ~= 0 then
			targetTime = minT + (state - minS) / rangeS * (maxT - minT)
		else
			targetTime = minT
		end
	end
	if targetTime == nil then
		targetTime = (state == spec.foldMinState) and (spec.foldMinTime or 0) or (spec.foldMaxTime or 1)
	end

	-- Snap the primary pipe animation on this vehicle.
	if spec.animation ~= nil and spec.animation.name ~= nil then
		pcall(function()
			vehicle:setAnimationTime(spec.animation.name, targetTime, true)
		end)
	end

	-- Some vehicles have a second pipe animation for a multi-section auger
	-- (e.g. John Deere S7.800). Try common secondary animation names.
	-- The game's Pipe spec only exposes the primary animation in spec.animation,
	-- but a secondary track may be registered under a different name.
	local secondaryNames = {
		"pipeAnim2",
		"foldPipe2",
		"pipeAnim1",
		"foldPipe1",
		"pipeFold1",
		"pipeFold2",
		spec.animation ~= nil and spec.animation.name ~= nil and spec.animation.name .. "2",
	}
	local seen = {}
	if spec.animation ~= nil and spec.animation.name ~= nil then
		seen[string.lower(spec.animation.name)] = true
	end
	for _, name in ipairs(secondaryNames) do
		if name ~= nil and not seen[string.lower(name)] then
			seen[string.lower(name)] = true
			pcall(function()
				vehicle:setAnimationTime(name, targetTime, true)
			end)
		end
	end
end

--- Internal: set a combine pipe to a specific state, handling clip-based vs time-blend
--- animations, S7 reversed clip direction, and child vehicle pipes (e.g. S7.800 multi-section).
--- @param vehicle table the GIANTS vehicle object (must carry spec_pipe)
--- @param targetState number the target pipe state
--- @return boolean ok true if the pipe state was applied
--- @return string msg human-readable result / reason
local function iaHelperSetPipeState(vehicle, targetState)
	if vehicle == nil then
		return false, "vehicle is nil"
	end
	local spec = vehicle.spec_pipe
	if spec == nil then
		return false, "no spec_pipe (vehicle has no movable pipe)"
	end
	if type(vehicle.setPipeState) ~= "function" then
		return false, "setPipeState not available on vehicle"
	end

	-- For clip-based animations (foldMinTime == foldMaxTime), setPipeState with instant=true
	-- sets the functional state but does NOT trigger the visual animation. We need to call
	-- setPipeState without instant so the game actually plays the animation clip.
	-- Some vehicles (S7.800) have their animation clip direction reversed relative to the
	-- state mapping, so we play the clip in BOTH directions (opposite→target) to ensure
	-- the visual ends up in the correct position regardless of clip orientation.
	if spec.foldMinTime ~= nil and spec.foldMaxTime ~= nil
		and math.abs(spec.foldMinTime - spec.foldMaxTime) < 0.001 then
		local okFunc, errFunc = pcall(function()
			vehicle:setPipeState(targetState, true)
		end)
		if not okFunc then
			return false, "setPipeState error: " .. tostring(errFunc)
		end
		local oppositeState = (targetState == spec.foldMinState) and spec.foldMaxState or spec.foldMinState
		pcall(function() vehicle:setPipeState(oppositeState, false) end)
		pcall(function() vehicle:setPipeState(targetState, false) end)
	else
		local ok, err = pcall(function()
			vehicle:setPipeState(targetState, true)
		end)
		if not ok then
			return false, "setPipeState error: " .. tostring(err)
		end
		IAHelper_snapPipeAnimation(vehicle, spec, targetState)
	end

	-- Handle multi-section combines (e.g. John Deere S7.800) with child vehicle pipes.
	if type(vehicle.getChildVehicles) == "function" then
		local okGet, children = pcall(function() return vehicle:getChildVehicles() end)
		if okGet and children and type(children) == "table" then
			for _, child in pairs(children) do
				if child and child.spec_pipe and type(child.setPipeState) == "function" then
					pcall(function() child:setPipeState(targetState, true) end)
					IAHelper_snapPipeAnimation(child, child.spec_pipe, targetState)
				end
			end
		end
	end

	return true, string.format("pipe set to state %d", targetState)
end

--- Fold a combine's auger pipe (spout) fully in. Mirrors tryFold intent for the Pipe spec.
--- Sets the pipe to its folded-in state and snaps the pipe animation instantly (no slow
--- unfold visible on spawn / parking).
--- @param vehicle table the GIANTS vehicle object (must carry spec_pipe)
--- @return boolean ok true if the pipe state was applied
--- @return string msg human-readable result / reason
function IAHelper_foldCombinePipeIn(vehicle)
	if vehicle == nil then
		return false, "vehicle is nil"
	end
	local spec = vehicle.spec_pipe
	if spec == nil then
		return false, "no spec_pipe (vehicle has no movable pipe)"
	end

	-- John Deere S7 has reversed pipe direction, so fold uses the max state.
	local isS7 = type(vehicle.getFullName) == "function"
		and (vehicle:getFullName():upper():find("S7") ~= nil
			or vehicle:getFullName():upper():find("JOHN DEERE") ~= nil)
	local targetState = isS7 and (spec.foldMaxState or 2) or (spec.foldMinState or 1)

	local ok, msg = iaHelperSetPipeState(vehicle, targetState)
	return ok, ok and (msg .. " (folded in)") or msg
end

--- Unfold a combine's auger pipe (spout) fully out. Inverse of IAHelper_foldCombinePipeIn.
--- Sets the pipe to its unfolded/out state and snaps the pipe animation instantly.
--- @param vehicle table the GIANTS vehicle object (must carry spec_pipe)
--- @return boolean ok true if the pipe state was applied
--- @return string msg human-readable result / reason
function IAHelper_unfoldCombinePipeOut(vehicle)
	if vehicle == nil then
		return false, "vehicle is nil"
	end
	local spec = vehicle.spec_pipe
	if spec == nil then
		return false, "no spec_pipe (vehicle has no movable pipe)"
	end

	-- John Deere S7 has reversed pipe direction, so unfold uses the min state.
	local isS7 = type(vehicle.getFullName) == "function"
		and (vehicle:getFullName():upper():find("S7") ~= nil
			or vehicle:getFullName():upper():find("JOHN DEERE") ~= nil)
	local targetState = isS7 and (spec.foldMinState or 1) or (spec.foldMaxState or 2)

	local ok, msg = iaHelperSetPipeState(vehicle, targetState)
	return ok, ok and (msg .. " (unfolded out)") or msg
end

--- Find the nearest vehicle that has a movable pipe (combine auger) to a world position.
--- Used by the temporary console command; the production fold logic takes the vehicle directly.
--- @param refX number reference world X
--- @param refY number reference world Y
--- @param refZ number reference world Z
--- @return table|nil vehicle nearest vehicle carrying spec_pipe (nil if none)
--- @return number|nil distSq squared distance to that vehicle
function IAHelper_findNearestVehicleWithPipe(refX, refY, refZ)
	if refX == nil or refY == nil or refZ == nil then
		return nil, nil
	end
	if g_currentMission == nil or g_currentMission.vehicleSystem == nil or g_currentMission.vehicleSystem.vehicles == nil then
		return nil, nil
	end

	local nearest, nearestDistSq = nil, nil
	for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
		if vehicle ~= nil and vehicle.spec_pipe ~= nil and vehicle.rootNode ~= nil then
			local x, y, z = getWorldTranslation(vehicle.rootNode)
			if x ~= nil then
				local dx, dy, dz = x - refX, y - refY, z - refZ
				local dSq = dx * dx + dy * dy + dz * dz
				if nearestDistSq == nil or dSq < nearestDistSq then
					nearestDistSq = dSq
					nearest = vehicle
				end
			end
		end
	end

	return nearest, nearestDistSq
end

--- Registers an NPC object in the engine's npcManager.
--- Encapsulates direct g_npcManager access.
---@param npc NPC the NPC engine object
---@param npcIndex number the index to register at
---@return boolean success
function IAHelper_registerNpcInManager(npc, npcIndex)
	if npc == nil then
		IAprintDebug("IAHelper_registerNpcInManager", "npc is nil for index " .. tostring(npcIndex))
		return false
	end
	if g_npcManager == nil or g_npcManager.npcs == nil then
		IAprintDebug("IAHelper_registerNpcInManager", "g_npcManager or g_npcManager.npcs is nil")
		return false
	end
	if g_npcManager.npcs[npcIndex] ~= nil then
		IAprintDebug("IAHelper_registerNpcInManager", "NPC slot " .. npcIndex .. " already occupied, overwriting")
	end
	g_npcManager.npcs[npcIndex] = npc
	IAprintDebug("IAHelper_registerNpcInManager", "Registered NPC at index " .. npcIndex)
	return true
end