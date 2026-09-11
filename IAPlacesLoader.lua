--
-- FS25 - InteractiveNeighbours - Places Loader
--
-- Handles loading of all available places into IANeighbours.places:
-- - Places from map config XML
-- - Places from map init (dialog / saveAutoPlaces; persisted in fields_of_stories_<mapId>.xml)
-- - Methods to find and add places from placeables (e.g. g_currentMission.placeableSystem)
-- - Selling stations from economyManager.sellingStations (unload trigger aiNode + local offset)
-- - Vehicle shop spawn slots from g_currentMission.storeSpawnPlaces (type workshop; grid inside length x width parallelogram)
-- - Roadside auto samples from traffic splines (IAMapInitJob.positionAndRotationFromSplineSample + long-spline filters)
--

IAPlacesLoader = {}
IAPlacesLoader._mt = Class(IAPlacesLoader)

--- Create a new IAPlacesLoader instance.
-- @param table ianeighboursInstance - Reference to IANeighbours
function IAPlacesLoader.new(ianeighboursInstance)
	local self = setmetatable({}, IAPlacesLoader._mt)
	self.ianeighbours = ianeighboursInstance
	self.selectedPlaceable = nil  -- Optional; when set, Map Init save can write a placeable-relative entry to placeablePlaces.xml
	-- Relative targets (Shift+F6): nodes + placeables in range; Ctrl+Y first narrows to focused + forward, then cycles focus
	self.displayedRelativeTargets = {}
	self.focusedRelativeIndex = 0  -- 1-based index into displayedRelativeTargets; 0 = none focused
	-- After Ctrl+Y: show only the focused target + forward marker; Shift+F6 resets to showing all in range again
	self.relativeTargetsShowAll = true
	return self
end

--- Load all places from map config XML into IANeighbours.places.
-- New places from the init system are added via addPlaceFromMapInitEntry().
-- @return boolean - true if loading succeeded (at least map config attempted; places may be empty)
function IAPlacesLoader:loadAll()
	if self.ianeighbours == nil or self.ianeighbours.xmlHelper == nil then
		return false
	end
	-- Ensure places table exists (loadMapConfiguration will fill it from XML)
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end

	-- Load places from map config XML only. New places added via the init system are added through addPlaceFromMapInitEntry().
	self.ianeighbours.xmlHelper:loadMapConfiguration()

	return true
end

--- Next numeric place id that does not collide with any existing place.id (max existing + 1, same rule as resolvePlaceableRelativePlaces).
-- Do not use #places + 1: ids are not always dense (e.g. after auto-generation or XML edits).
function IAPlacesLoader:getNextFreeNumericPlaceId()
	if self.ianeighbours.places == nil then
		return 1
	end
	local nextId = 1
	for _, p in ipairs(self.ianeighbours.places) do
		if p and p.id ~= nil and type(p.id) == "number" and p.id >= nextId then
			nextId = p.id + 1
		end
	end
	return nextId
end

--- Add a single place from the map-init system to IANeighbours.places (e.g. when user defines a new place in the Map Init dialog).
-- Uses the same id/name logic as the map-init flow.
-- @param table entry - Map-init entry with type, x, y, z, rotation, optional characterNumber, optional withVehicle
function IAPlacesLoader:addPlaceFromMapInitEntry(entry)
	if entry == nil or entry.type == nil or (entry.x == nil and entry.id == nil) or (entry.z == nil and entry.id == nil) then
		return
	end
	if entry.x == nil or entry.z == nil then
		return
	end
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local id = entry.id
	if id == nil then
		id = self:getNextFreeNumericPlaceId()
	end
	local name = entry.name or ("Place " .. tostring(id))
	local place = IAMapPlace.new(id, name, entry.type, entry.x, entry.y or 0, entry.z, entry.rotation or 0, entry.withVehicle ~= false, entry.withAttachment == true, entry.sizeType, entry.characterNumber)
	if entry.ignoreCollision == true then
		place.ignoreCollision = true
	end
	if entry.job ~= nil and entry.job ~= "" then
		place.job = entry.job
	end
	if entry.description ~= nil and tostring(entry.description) ~= "" then
		place.description = tostring(entry.description)
	end
	if entry.resolvedMapNodeId ~= nil and entityExists(entry.resolvedMapNodeId) then
		place.resolvedMapNodeId = entry.resolvedMapNodeId
	end
	table.insert(self.ianeighbours.places, place)
	-- Silo hook: auto-spawn the farma400modified game placeable when a silo place is created manually
	if place.sizeType == "silo"
		and self.ianeighbours.xmlHelper ~= nil
		and self.ianeighbours.xmlHelper.ensureSiloPlaceableForPlace ~= nil then
		self.ianeighbours.xmlHelper:ensureSiloPlaceableForPlace(place, entry.characterNumber)
	end
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:addPlaceFromMapInitEntry() - Added place: " .. tostring(place.name) .. " (Type: " .. tostring(place.type) .. ", ID: " .. tostring(place.id) .. ")")
	end
end

--- Add roadside places along traffic splines (same rules as map-init auto generation: right offset, long splines only).
-- Uses IANeighbours:getTrafficSplineShapeIds(), IAMapInitJob.positionAndRotationFromSplineSample, then addPlaceFromMapInitEntry.
-- @param table options - placeType (default "roadside"), skipSave, rightOffsetM (default 1.5), sampleCount (12), minSplineLengthM (100), minStartEndDistM (5), minRoadsideSpacingM (default 50) — min distance in XZ to any existing place of the same type (all splines + map config)
-- @return number - Number of places added
function IAPlacesLoader:addPlacesFromTrafficSplines(options)
	options = options or {}
	local placeType = options.placeType or "roadside"
	local skipSave = options.skipSave == true
	local rightOffsetM = options.rightOffsetM or 1.5
	local sampleCount = options.sampleCount or 12
	local minSplineLengthM = options.minSplineLengthM or 100
	local minStartEndDistM = options.minStartEndDistM or 5
	local minRoadsideSpacingM = options.minRoadsideSpacingM or 50
	local m = g_currentMission
	if m == nil or m.missionInfo == nil or m.missionInfo.mapId == nil then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:addPlacesFromTrafficSplines() - No mission or mapId")
		end
		return 0
	end
	if self.ianeighbours.getTrafficSplineShapeIds == nil then
		return 0
	end
	local shapeIds = self.ianeighbours:getTrafficSplineShapeIds() or {}
	if #shapeIds == 0 then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:addPlacesFromTrafficSplines() - No traffic splines found")
		end
		return 0
	end

	local terrainBounds = getTerrainBoundsRect()
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local places = self.ianeighbours.places
	local added = 0
	--- True if (px,pz) is within minRoadsideSpacingM (XZ plane) of any place with matching type (already on map or added earlier in this run).
	local function isTooCloseToAnySameType(px, pz)
		if minRoadsideSpacingM == nil or minRoadsideSpacingM <= 0 or px == nil or pz == nil then
			return false
		end
		local minSq = minRoadsideSpacingM * minRoadsideSpacingM
		for _, p in ipairs(places) do
			if p ~= nil and p.type == placeType and p.x ~= nil and p.z ~= nil then
				local dx = px - p.x
				local dz = pz - p.z
				if dx * dx + dz * dz < minSq then
					return true
				end
			end
		end
		return false
	end
	local getSplinePosition = getSplinePosition
	local getSplineLength = getSplineLength
	local entityExists = entityExists
	for splineIdx, shapeId in ipairs(shapeIds) do
		if shapeId ~= nil and entityExists(shapeId) and getSplinePosition then
			local splineLen = (getSplineLength and getSplineLength(shapeId)) or 0
			if splineLen > minSplineLengthM then
				local x0, y0, z0 = getSplinePosition(shapeId, 0)
				local x1, y1, z1 = getSplinePosition(shapeId, 1)
				for k = 0, sampleCount - 1 do
					local t = (sampleCount > 1) and (k / (sampleCount - 1)) or 0
					local x, y, z = getSplinePosition(shapeId, t)
					if x ~= nil and z ~= nil then
						if y == nil or y ~= y then
							y = g_terrainNode and getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.2 or 0
						end
						local distToStart = (x0 ~= nil and z0 ~= nil) and math.sqrt((x - x0) ^ 2 + ((y or 0) - (y0 or 0)) ^ 2 + (z - z0) ^ 2) or math.huge
						local distToEnd = (x1 ~= nil and z1 ~= nil) and math.sqrt((x - x1) ^ 2 + ((y or 0) - (y1 or 0)) ^ 2 + (z - z1) ^ 2) or math.huge
						if (t > 0 and t < 1) and (distToStart >= minStartEndDistM or distToEnd >= minStartEndDistM) then
							local tNext = math.min(1, t + 0.05)
							local xNext, yNext, zNext = getSplinePosition(shapeId, tNext)
							local px, py, pz, rotationYaw = IAMapInitJob.positionAndRotationFromSplineSample(x, y, z, xNext, yNext, zNext, rightOffsetM)
							if px ~= nil and pz ~= nil then
								-- Enforce minimum spacing in XZ vs every other place of this type (parallel splines, map-loaded places, etc.).
								if not isTooCloseToAnySameType(px, pz) then
									local name = "Roadside (auto " .. tostring(splineIdx) .. "." .. tostring(k) .. ")"
									local entry = {
										type = placeType,
										name = name,
										x = px,
										y = py,
										z = pz,
										rotation = rotationYaw or 0,
										withVehicle = true,
										withAttachment = true
									}
									if isWithinTerrainBoundsRect(entry.x, entry.z, terrainBounds) then
										self:addPlaceFromMapInitEntry(entry)
										added = added + 1
									elseif self.ianeighbours.debug then
										local boundsStr = (terrainBounds ~= nil)
											and (" bounds=(" .. tostring(terrainBounds.minX) .. "," .. tostring(terrainBounds.maxX) .. "," .. tostring(terrainBounds.minZ) .. "," .. tostring(terrainBounds.maxZ) .. ")")
											or " bounds=<unknown>"
										print("--- IAPlacesLoader:addPlacesFromTrafficSplines() - Skipping roadside place outside terrain bounds: name=" .. tostring(name) .. " pos=(" .. tostring(entry.x) .. "," .. tostring(entry.z) .. ")" .. boundsStr)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if added > 0 and not skipSave and self.ianeighbours.xmlHelper then
		if self.ianeighbours.debug then
			print("--- saveMapConfigToFile caller: IAPlacesLoader:addPlacesFromTrafficSplines mapId=" .. tostring(m.missionInfo.mapId) .. " added=" .. tostring(added))
		end
		self.ianeighbours.xmlHelper:saveMapConfigToFile(m.missionInfo.mapId)
	end
	if self.ianeighbours.debug and added > 0 then
		print("--- IAPlacesLoader:addPlacesFromTrafficSplines() - Added " .. tostring(added) .. " places (" .. placeType .. ") from " .. tostring(#shapeIds) .. " splines")
	end
	return added
end

--- Add one place per unload trigger with a valid aiNode (world pos = aiNode + local offset, default -2.5 local Z).
-- Uses g_currentMission.economyManager.sellingStations: each entry is often a wrapper { station = <SellingStation> };
-- unloadTriggers / supportedFillTypes live on the inner .station table (falls back to the entry if already flat).
-- @param table options - placeType, skipSave, offsetLocalX/Y/Z, dedupeTolerance (default 0.5)
-- @return number - places added
function IAPlacesLoader:addPlacesFromSellingStations(options)
	options = options or {}
	local placeType = options.placeType or "sell_point"
	local skipSave = options.skipSave == true
	local ox = options.offsetLocalX or 0
	local oy = options.offsetLocalY or 0
	local oz = options.offsetLocalZ or -2.5
	local tol = options.dedupeTolerance or 0.5
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:addPlacesFromSellingStations() - start")
	end
	local m = g_currentMission
	local stations = m and m.missionInfo and m.missionInfo.mapId and m.economyManager and m.economyManager.sellingStations
	if stations == nil then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:addPlacesFromSellingStations() - end added=0 (no mission/mapId/economy/sellingStations)")
		end
		return 0
	end

	local terrainBounds = getTerrainBoundsRect()
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local places = self.ianeighbours.places
	local added = 0
	for si, entry in ipairs(stations) do
		local station = entry
		if entry ~= nil and type(entry.station) == "table" then
			station = entry.station
		end
		if station ~= nil and station.unloadTriggers ~= nil then
			local fillParts = {}
			if station.supportedFillTypes ~= nil then
				for ftId, ok in pairs(station.supportedFillTypes) do
					if ok then
						local n = tonumber(ftId)
						if n ~= nil then
							fillParts[#fillParts + 1] = tostring(n)
						end
					end
				end
			end
			local fillsStr = table.concat(fillParts, ",")
			for ti, trig in ipairs(station.unloadTriggers) do
				if trig ~= nil and trig.aiNode ~= nil and entityExists(trig.aiNode) then
					local aiNode = trig.aiNode
					local x, y, z = getWorldPositionFromNodeLocalOffset(aiNode, ox, oy, oz)
					if x ~= nil and z ~= nil then
						if y ~= y then
							y = g_terrainNode and getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.2 or 0
						end
						local fx, _, fz = localDirectionToWorld(aiNode, 0, 0, 1)
						local rotation = (fx ~= nil and fz ~= nil) and math.atan2(fx, fz) or 0
						local label = station.rootNodeName
						if label == nil or label == "" then
							label = "station" .. tostring(si)
						end
						local desc = string.format(
							"ownerFarmId=%s; isSellingPoint=%s; rootNodeName=%s; supportedFillTypes=%s; unloadTriggerIndex=%s; aiNode=%s; stationId=%s",
							tostring(station.ownerFarmId),
							tostring(station.isSellingPoint == true),
							tostring(station.rootNodeName or ""),
							fillsStr,
							tostring(ti),
							tostring(aiNode),
							tostring(station.id)
						)
						if isWithinTerrainBoundsRect(x, z, terrainBounds) and not self:placeExistsAtPosition(x, z, placeType, tol) then
							self:addPlaceFromMapInitEntry({
								type = placeType,
								name = "Sell point (" .. tostring(label) .. " T" .. tostring(ti) .. ")",
								x = x,
								y = y,
								z = z,
								rotation = rotation,
								withVehicle = true,
								withAttachment = true,
								description = desc,
								resolvedMapNodeId = aiNode
							})
							added = added + 1
						end
					end
				end
			end
		end
	end

	if added > 0 and not skipSave and self.ianeighbours.xmlHelper then
		if self.ianeighbours.debug then
			print("--- saveMapConfigToFile caller: IAPlacesLoader:addPlacesFromSellingStations mapId=" .. tostring(m.missionInfo.mapId) .. " added=" .. tostring(added))
		end
		self.ianeighbours.xmlHelper:saveMapConfigToFile(m.missionInfo.mapId)
	end
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:addPlacesFromSellingStations() - end added=" .. tostring(added) .. " type=" .. tostring(placeType))
	end
	return added
end

--- Normalize a 3D vector; returns nil if length is near zero.
local function iaNormalizeVec3(x, y, z)
	x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
	local len = math.sqrt(x * x + y * y + z * z)
	if len < 1e-6 then
		return nil
	end
	return x / len, y / len, z / len
end

--- Axis-aligned center positions in [0, extentM]: first center edgePad + pitch/2, then +pitch (no overlap).
local function iaStoreSpawnAxisCenters(extentM, edgePad, pitch)
	local centers = {}
	if extentM == nil or pitch == nil or pitch <= 0 then
		return centers
	end
	edgePad = edgePad or 0
	if extentM <= edgePad * 2 + 1e-4 then
		return centers
	end
	local lo = edgePad + pitch * 0.5
	local hi = extentM - edgePad - pitch * 0.5
	if hi < lo - 1e-4 then
		centers[1] = edgePad + (extentM - 2 * edgePad) * 0.5
		return centers
	end
	local c = lo
	while c <= hi + 1e-4 do
		centers[#centers + 1] = c
		c = c + pitch
	end
	return centers
end

--- Pick spacing along dir (s) vs dirPerp (t) from shop yaw vs rectangle axes (vehicle length along row).
local function iaStoreSpawnPitchesFromRotation(rotY, ux, uz, vx, vz, minAlong, minAcross)
	local fyX = math.sin(rotY or 0)
	local fyZ = math.cos(rotY or 0)
	local flen = math.sqrt(fyX * fyX + fyZ * fyZ)
	if flen > 1e-6 then
		fyX, fyZ = fyX / flen, fyZ / flen
	end
	local dotDir = math.abs(fyX * ux + fyZ * uz)
	local dotPerp = math.abs(fyX * vx + fyZ * vz)
	-- Vehicle length (~minAlong) should follow the axis where forward points; row steps use the other axis (~minAcross).
	if dotDir >= dotPerp then
		return minAlong, minAcross
	end
	return minAcross, minAlong
end

--- Grid of type `workshop` places inside each g_currentMission.storeSpawnPlaces rectangle (vehicle shop spawn grid).
-- World position: start + dir * s + dirPerp * t with s in [0,length], t in [0,width] (after edge padding).
-- Spacing along dir / dirPerp is chosen from rotY vs dir so a row advances "left/right" (dirPerp) with pitch >= vehicle length when the shop faces that way.
-- @param table options placeType (default "workshop"), skipSave, dedupeTolerance (default 0.75),
--   minSlotAlongM (default 14) vehicle+attachment length, minSlotAcrossM (default 4.5) vehicle width,
--   pitchAlongDirM / pitchAlongPerpM optional overrides (skip auto from rotation),
--   edgePadM (default 2.5) inset from spawn rectangle edges — keeps slot centers away from border props/walls
--   terrainYOffsetM (default 0.15) when sampling terrain height
-- @return number places added
function IAPlacesLoader:addPlacesFromStoreSpawnPlaces(options)
	options = options or {}
	local placeType = options.placeType or "workshop"
	local skipSave = options.skipSave == true
	local tol = options.dedupeTolerance or 0.75
	local minAlong = options.minSlotAlongM or 14
	local minAcross = options.minSlotAcrossM or 4.5
	-- Generous default: 0.75m was flush with map geometry at many shop spawn outlines.
	local edgePad = options.edgePadM or 0
	local terrainYOffset = options.terrainYOffsetM or 0.01

	local m = g_currentMission
	local list = m and m.storeSpawnPlaces
	if list == nil or type(list) ~= "table" or #list == 0 then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:addPlacesFromStoreSpawnPlaces() - end added=0 (no storeSpawnPlaces)")
		end
		return 0
	end
	if m.missionInfo == nil or m.missionInfo.mapId == nil then
		return 0
	end

	local terrainBounds = getTerrainBoundsRect()
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local added = 0

	for si, spawn in ipairs(list) do
		if spawn ~= nil and type(spawn) == "table" then
			local sx = tonumber(spawn.startX)
			local sy = tonumber(spawn.startY)
			local sz = tonumber(spawn.startZ)
			-- storeSpawnPlaces uses length/width opposite to our convention (in practice width acts as "along dir", length as "along dirPerp").
			-- Swap so L always corresponds to the "dir" axis extent and W to the "dirPerp" axis extent.
			local L = tonumber(spawn.width)
			local W = tonumber(spawn.length)
			if L == nil or W == nil or sx == nil or sz == nil then
				if self.ianeighbours.debug then
					print("--- IAPlacesLoader:addPlacesFromStoreSpawnPlaces() - skip store #" .. tostring(si) .. " (missing start or length/width)")
				end
			else
				local maxL = tonumber(spawn.maxWidth)
				local maxW = tonumber(spawn.maxLength)
				if maxL ~= nil and maxL > 0 and maxL < math.huge and maxL < L then
					L = maxL
				end
				if maxW ~= nil and maxW > 0 and maxW < math.huge and maxW < W then
					W = maxW
				end
				if L > edgePad * 2 and W > edgePad * 2 and minAlong > 0 and minAcross > 0 then
					local ux, uy, uz = iaNormalizeVec3(spawn.dirX, spawn.dirY, spawn.dirZ)
					local vx, vy, vz = iaNormalizeVec3(spawn.dirPerpX, spawn.dirPerpY, spawn.dirPerpZ)
					if ux ~= nil and vx ~= nil then
						local yOff = tonumber(spawn.yOffset) or 0
						local rotY = tonumber(spawn.rotY) or 0
						local palletOff = tonumber(spawn.palletRotationOffset) or 0
						local rotation = rotY + palletOff
						local pitchS = tonumber(options.pitchAlongDirM)
						local pitchT = tonumber(options.pitchAlongPerpM)
						if pitchS == nil or pitchT == nil then
							local autoS, autoT = iaStoreSpawnPitchesFromRotation(rotY, ux, uz, vx, vz, minAlong, minAcross)
							pitchS = pitchS or autoS
							pitchT = pitchT or autoT
						end
						local sCenters = iaStoreSpawnAxisCenters(L, edgePad, pitchS)
						local tCenters = iaStoreSpawnAxisCenters(W, edgePad, pitchT)
						local startNode = spawn.startNode
						local nodeOk = startNode ~= nil and entityExists(startNode)

						-- Outer s (along dir) = row depth; inner t (along dirPerp) = next slot to the side in one row.
						for is, s in ipairs(sCenters) do
							for it, t in ipairs(tCenters) do
								local x = sx + ux * s + vx * t
								local y = (sy or 0) + uy * s + vy * t + yOff
								local z = sz + uz * s + vz * t
								if g_terrainNode and getTerrainHeightAtWorldPos then
									local th = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
									if th ~= nil and th == th then
										y = th + terrainYOffset
									end
								end
								local name = string.format("Shop spawn (store %d row %d col %d)", si, is, it)
								local desc = string.format(
									"storeSpawnPlaces[%d]; s=%.2f t=%.2f; L=%.2f W=%.2f; pitchS=%.2f pitchT=%.2f; startNode=%s",
									si, s, t, L, W, pitchS, pitchT, tostring(startNode)
								)
								if isWithinTerrainBoundsRect(x, z, terrainBounds) and not self:placeExistsAtPosition(x, z, placeType, tol) then
									local entry = {
										type = placeType,
										name = name,
										x = x,
										y = y,
										z = z,
										rotation = rotation,
										withVehicle = true,
										withAttachment = true,
										description = desc
									}
									if nodeOk then
										entry.resolvedMapNodeId = startNode
									end
									self:addPlaceFromMapInitEntry(entry)
									added = added + 1
								end
							end
						end
						if self.ianeighbours.debug then
							print(string.format(
								"--- IAPlacesLoader:addPlacesFromStoreSpawnPlaces() - store #%d: %d x %d slots (L=%.1f W=%.1f pitch dir=%.2f perp=%.2f)",
								si, #sCenters, #tCenters, L, W, pitchS, pitchT
							))
						end
					elseif self.ianeighbours.debug then
						print("--- IAPlacesLoader:addPlacesFromStoreSpawnPlaces() - skip store #" .. tostring(si) .. " (invalid dir or dirPerp)")
					end
				end
			end
		end
	end

	if added > 0 and not skipSave and self.ianeighbours.xmlHelper then
		if self.ianeighbours.debug then
			print("--- saveMapConfigToFile caller: IAPlacesLoader:addPlacesFromStoreSpawnPlaces mapId=" .. tostring(m.missionInfo.mapId) .. " added=" .. tostring(added))
		end
		self.ianeighbours.xmlHelper:saveMapConfigToFile(m.missionInfo.mapId)
	end
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:addPlacesFromStoreSpawnPlaces() - end added=" .. tostring(added) .. " type=" .. tostring(placeType))
	end
	return added
end

--- Return true if places already has a place at (x,z) with same type within tolerance (avoid duplicate when map place file already loaded).
function IAPlacesLoader:placeExistsAtPosition(x, z, placeType, tolerance)
	if x == nil or z == nil or placeType == nil or self.ianeighbours.places == nil then
		return false
	end
	tolerance = tolerance or 1.0
	for _, p in ipairs(self.ianeighbours.places) do
		if p and p.type == placeType and p.x ~= nil and p.z ~= nil then
			if math.abs(p.x - x) < tolerance and math.abs(p.z - z) < tolerance then
				return true
			end
		end
	end
	return false
end

--- Resolve all placeable-relative places: one definition -> N absolute places (one per matching placeable). Removes relative entries from places.
-- Call after loading placeablePlaces. Each placeable-relative place is replaced by one IAMapPlace per matching placeable instance.
-- @return number - Count of new places added (total resolved instances)
function IAPlacesLoader:resolvePlaceableRelativePlaces()
	if self.ianeighbours.places == nil then
		return 0
	end

	local terrainBounds = getTerrainBoundsRect()

	local placeableSystem = g_currentMission and g_currentMission.placeableSystem
	if placeableSystem == nil or placeableSystem.placeables == nil then
		return 0
	end
	-- Next free id for new places
	local maxId = 0
	for _, p in ipairs(self.ianeighbours.places) do
		if p and p.id and p.id > maxId then
			maxId = p.id
		end
	end
	local nextId = maxId + 1
	local newPlaces = {}
	local indicesToRemove = {}
	for i, place in ipairs(self.ianeighbours.places) do
		if place and place.isPlaceableRelative and place:isPlaceableRelative() and place.placeableFilename then
			local matching = {}
			local xh = self.ianeighbours and self.ianeighbours.xmlHelper
			for _, placeable in ipairs(placeableSystem.placeables) do
				local same = false
				if placeable and placeable.configFileName then
					if xh ~= nil and xh.pathMatchKey ~= nil then
						local ka, kb = xh:pathMatchKey(placeable.configFileName), xh:pathMatchKey(place.placeableFilename)
						same = (ka ~= nil and kb ~= nil and ka == kb)
					else
						same = (placeable.configFileName == place.placeableFilename)
					end
				end
				if same then
					table.insert(matching, placeable)
				end
			end
			for j, placeable in ipairs(matching) do
				local name = place.name or ("Place " .. tostring(nextId))
				if #matching > 1 then
					name = (place.name or "Place") .. " #" .. tostring(j)
				end
				local clone = IAMapPlace.new(
					nextId,
					name,
					place.type,
					0, 0, 0, 0,
					place.withVehicle ~= false,
					place.withAttachment == true,
					place.sizeType,
					nil,
					place.placeableFilename,
					place.offsetX,
					place.offsetY,
					place.offsetZ,
					place.relRotation
				)
				clone.ignoreCollision = place.ignoreCollision == true
				if place.job ~= nil and place.job ~= "" then
					clone.job = place.job
				end
				if place.description ~= nil and place.description ~= "" then
					clone.description = place.description
				end
				if clone:resolveFromPlaceable(placeable) then
					if placeable.rootNode ~= nil and entityExists(placeable.rootNode) then
						clone.resolvedMapNodeId = placeable.rootNode
					end
					-- Terrain bounds filter.
					if not isWithinTerrainBoundsRect(clone.x, clone.z, terrainBounds) then
						if self.ianeighbours.debug then
							local boundsStr = (terrainBounds ~= nil)
								and (" bounds=(" .. tostring(terrainBounds.minX) .. "," .. tostring(terrainBounds.maxX) .. "," .. tostring(terrainBounds.minZ) .. "," .. tostring(terrainBounds.maxZ) .. ")")
								or " bounds=<unknown>"
							print("--- IAPlacesLoader:resolvePlaceableRelativePlaces() - Skipping place outside terrain bounds: name=" .. tostring(clone.name) .. " type=" .. tostring(clone.type) .. " pos=(" .. tostring(clone.x) .. "," .. tostring(clone.z) .. ")" .. boundsStr)
						end
					else
						clone.placeableFilename = nil
						clone.offsetX = nil
						clone.offsetY = nil
						clone.offsetZ = nil
						clone.relRotation = nil
						-- Deduplicate: skip if map place file already has a place at this position (e.g. from previous save)
						if not self:placeExistsAtPosition(clone.x, clone.z, clone.type) then
							table.insert(newPlaces, clone)
							nextId = nextId + 1
						end
						if self.ianeighbours.debug then
							print("--- IAPlacesLoader:resolvePlaceableRelativePlaces() - Resolved " .. tostring(name) .. " at " .. place.placeableFilename)
						end
					end
				end
			end
			table.insert(indicesToRemove, i)
		end
	end
	-- Remove placeable-relative places from back to front so indices stay valid
	for i = #indicesToRemove, 1, -1 do
		table.remove(self.ianeighbours.places, indicesToRemove[i])
	end
	for _, p in ipairs(newPlaces) do
		table.insert(self.ianeighbours.places, p)
	end
	return #newPlaces
end

--- Resolve all node-relative places to world position using current map nodes (by name).
-- Call after loading placeablePlaces so x,y,z,rotation are set for spawning.
-- @return number - Count of places resolved
function IAPlacesLoader:resolveNodeRelativePlaces()
	if self.ianeighbours.places == nil then
		return 0
	end
	local list = IAMapInitJob and IAMapInitJob.getAllMapNodesWithTransform and IAMapInitJob.getAllMapNodesWithTransform({ maxNodes = 10000 }) or {}
	-- Key by referenceFilename, refId, or display name; also by I3D #name (nodeName) so nodeName-only places resolve (same as loadPlaceablePlacesFromFile aliases).
	local xh = self.ianeighbours and self.ianeighbours.xmlHelper
	local byKey = {}
	for _, entry in ipairs(list) do
		if entry then
			local key = nil
			if entry.referenceFilename and entry.referenceFilename ~= "" then
				key = (xh ~= nil and xh.pathMatchKey ~= nil) and xh:pathMatchKey(entry.referenceFilename) or entry.referenceFilename
			elseif entry.referenceId ~= nil then
				key = "refId:" .. tostring(entry.referenceId)
			elseif entry.name and entry.name ~= "" then
				key = entry.name
			end
			if key and byKey[key] == nil then
				byKey[key] = entry
			end
			if entry.nodeName and entry.nodeName ~= "" and entry.nodeName ~= key and byKey[entry.nodeName] == nil then
				byKey[entry.nodeName] = entry
			end
		end
	end
	local resolved = 0
	for _, place in ipairs(self.ianeighbours.places) do
		if place and place.isNodeRelative and place:isNodeRelative() and place.nodeName then
			local matchKey = nil
			if place.referenceFilename and place.referenceFilename ~= "" then
				matchKey = (xh ~= nil and xh.pathMatchKey ~= nil) and xh:pathMatchKey(place.referenceFilename) or place.referenceFilename
			elseif place.referenceId ~= nil then
				matchKey = "refId:" .. tostring(place.referenceId)
			else
				matchKey = place.nodeName
			end
			local node = byKey[matchKey]
			if node and node.position and node.rotation then
				local nx = node.position.x
				local ny = node.position.y or 0
				local nz = node.position.z
				local ry = (node.rotation.y ~= nil) and node.rotation.y or 0
				if place:resolveFromMapNode(nx, ny, nz, ry) then
					resolved = resolved + 1
					if self.ianeighbours.debug then
						print("--- IAPlacesLoader:resolveNodeRelativePlaces() - Resolved " .. tostring(place.name) .. " at " .. tostring(matchKey))
					end
				end
			end
		end
	end
	return resolved
end

--- Set the selected placeable (used when saving places relative to it from Map Init).
function IAPlacesLoader:setSelectedPlaceable(placeable)
	self.selectedPlaceable = placeable
end

--- Get the currently selected placeable, if any.
function IAPlacesLoader:getSelectedPlaceable()
	return self.selectedPlaceable
end

local function iaGetLocalPlayerWorldXZ()
	if g_localPlayer == nil then
		return nil, nil
	end
	local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) and getWorldTranslation ~= nil then
		local x, _, z = getWorldTranslation(v.rootNode)
		if x ~= nil and z ~= nil then
			return x, z
		end
	end
	if g_localPlayer.getPosition then
		local x, _, z = g_localPlayer:getPosition()
		return x, z
	end
	return nil, nil
end

function IAPlacesLoader:getRelativeTargetWorldXZ(entry)
	if entry == nil then
		return nil, nil
	end
	-- Prefer runtime positions when available so sorting matches what debug points show.
	if entry.type == "node" then
		local rtId = entry.resolvedRuntimeNodeId
		if rtId ~= nil and rtId ~= 0 and entityExists(rtId) and getWorldTranslation ~= nil then
			local x, _, z = getWorldTranslation(rtId)
			if x ~= nil and z ~= nil then
				return x, z
			end
		end
	elseif entry.type == "placeable" then
		local p = entry.placeable
		if p ~= nil and p.rootNode ~= nil and entityExists(p.rootNode) and getWorldTranslation ~= nil then
			local x, _, z = getWorldTranslation(p.rootNode)
			if x ~= nil and z ~= nil then
				return x, z
			end
		end
	end
	if entry.position ~= nil then
		return entry.position.x, entry.position.z
	end
	return nil, nil
end

function IAPlacesLoader:sortDisplayedRelativeTargetsByDistance()
	if self.displayedRelativeTargets == nil or #self.displayedRelativeTargets <= 1 then
		return false
	end
	local px, pz = iaGetLocalPlayerWorldXZ()
	if px == nil or pz == nil then
		return false
	end

	local focusedEntry = self:getFocusedRelativeTarget()

	table.sort(self.displayedRelativeTargets, function(a, b)
		local ax, az = self:getRelativeTargetWorldXZ(a)
		local bx, bz = self:getRelativeTargetWorldXZ(b)
		if ax == nil or az == nil then
			return false
		end
		if bx == nil or bz == nil then
			return true
		end
		local adx, adz = ax - px, az - pz
		local bdx, bdz = bx - px, bz - pz
		local da = adx * adx + adz * adz
		local db = bdx * bdx + bdz * bdz
		if da == db then
			-- Stable-ish tie-breaker (keeps deterministic order within identical distances).
			return tostring(a.name or a.label or a.type or "") < tostring(b.name or b.label or b.type or "")
		end
		return da < db
	end)

	if focusedEntry ~= nil then
		for i, e in ipairs(self.displayedRelativeTargets) do
			if e == focusedEntry then
				self.focusedRelativeIndex = i
				break
			end
		end
	end
	return true
end

--- Set the list of displayed relative targets (nodes + placeables). Resets focus to first and rebuilds debug points.
-- @param table targets - Array of { type = "node", name, position, rotation, ... } or { type = "placeable", placeable, position, rotation, label }
function IAPlacesLoader:setDisplayedRelativeTargets(targets)
	self.displayedRelativeTargets = targets or {}
	self.focusedRelativeIndex = (#self.displayedRelativeTargets > 0) and 1 or 0
	self.relativeTargetsShowAll = true
	self:sortDisplayedRelativeTargetsByDistance()
	self:rebuildRelativeTargetDebugPoints()
end

--- Get the currently focused relative target (node or placeable entry), or nil.
-- @return table entry - { type = "node"|"placeable", ... } or nil
function IAPlacesLoader:getFocusedRelativeTarget()
	if self.displayedRelativeTargets == nil or #self.displayedRelativeTargets == 0 or self.focusedRelativeIndex < 1 or self.focusedRelativeIndex > #self.displayedRelativeTargets then
		return nil
	end
	return self.displayedRelativeTargets[self.focusedRelativeIndex]
end

--- Cycle focus to the next displayed relative target (Ctrl+Y) and rebuild debug points so the focused one is labeled "focused".
-- First Ctrl+Y after Shift+F6: hide other targets and show only the current focus + forward marker (same index). Further Ctrl+Y: advance focus.
function IAPlacesLoader:cycleFocusedRelativeTargetAndRebuild()
	if self.displayedRelativeTargets == nil or #self.displayedRelativeTargets == 0 then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:cycleFocusedRelativeTargetAndRebuild() - No displayed targets (press Shift+F6 first)")
		end
		return
	end

	-- Always keep cycle order closest-first based on current player/vehicle position.
	self:sortDisplayedRelativeTargetsByDistance()

	if self.relativeTargetsShowAll then
		self.relativeTargetsShowAll = false
	else
		self.focusedRelativeIndex = self.focusedRelativeIndex + 1
		if self.focusedRelativeIndex > #self.displayedRelativeTargets then
			self.focusedRelativeIndex = 1
		end
	end
	self:rebuildRelativeTargetDebugPoints()
	local entry = self:getFocusedRelativeTarget()
	if self.ianeighbours.debug and entry then
		local label = (entry.type == "placeable" and entry.label) or entry.name or tostring(entry.type)
		print("--- IAPlacesLoader:cycleFocusedRelativeTargetAndRebuild() - Focused " .. tostring(self.focusedRelativeIndex) .. "/" .. tostring(#self.displayedRelativeTargets) .. " " .. tostring(label))
	end
end

--- Cycle focus to the previous displayed relative target (Ctrl+Shift+Z) and rebuild debug points.
function IAPlacesLoader:cycleFocusedRelativeTargetBackAndRebuild()
	if self.displayedRelativeTargets == nil or #self.displayedRelativeTargets == 0 then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:cycleFocusedRelativeTargetBackAndRebuild() - No displayed targets (press Shift+F6 first)")
		end
		return
	end

	-- Always keep cycle order closest-first based on current player/vehicle position.
	self:sortDisplayedRelativeTargetsByDistance()

	if self.relativeTargetsShowAll then
		self.relativeTargetsShowAll = false
	else
		self.focusedRelativeIndex = self.focusedRelativeIndex - 1
		if self.focusedRelativeIndex < 1 then
			self.focusedRelativeIndex = #self.displayedRelativeTargets
		end
	end
	self:rebuildRelativeTargetDebugPoints()
	local entry = self:getFocusedRelativeTarget()
	if self.ianeighbours.debug and entry then
		local label = (entry.type == "placeable" and entry.label) or entry.name or tostring(entry.type)
		print("--- IAPlacesLoader:cycleFocusedRelativeTargetBackAndRebuild() - Focused " .. tostring(self.focusedRelativeIndex) .. "/" .. tostring(#self.displayedRelativeTargets) .. " " .. tostring(label))
	end
end

local function iaRelativeTargetIsI3dEntry(entry)
	if entry == nil then
		return false
	end
	if entry.referenceFilename ~= nil and string.find(tostring(entry.referenceFilename), "%.i3d") then
		return true
	end
	if entry.name ~= nil and string.find(tostring(entry.name), "%.i3d") then
		return true
	end
	if entry.label ~= nil and string.find(tostring(entry.label), "%.i3d") then
		return true
	end
	return false
end

--- Jump focus to the next displayed relative target that references an .i3d (wrap) and rebuild debug points.
function IAPlacesLoader:cycleFocusedRelativeTargetToNextI3dAndRebuild()
	if self.displayedRelativeTargets == nil or #self.displayedRelativeTargets == 0 then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:cycleFocusedRelativeTargetToNextI3dAndRebuild() - No displayed targets (press Shift+F6 first)")
		end
		return
	end

	-- Always keep cycle order closest-first based on current player/vehicle position.
	self:sortDisplayedRelativeTargetsByDistance()

	local n = #self.displayedRelativeTargets
	if self.focusedRelativeIndex < 1 or self.focusedRelativeIndex > n then
		self.focusedRelativeIndex = 1
	end

	if self.relativeTargetsShowAll then
		self.relativeTargetsShowAll = false
	end

	local start = self.focusedRelativeIndex
	local i = start
	for _ = 1, n do
		i = i + 1
		if i > n then i = 1 end
		local e = self.displayedRelativeTargets[i]
		if iaRelativeTargetIsI3dEntry(e) then
			self.focusedRelativeIndex = i
			self:rebuildRelativeTargetDebugPoints()
			if self.ianeighbours.debug then
				local label = (e.type == "placeable" and e.label) or e.name or tostring(e.type)
				print("--- IAPlacesLoader:cycleFocusedRelativeTargetToNextI3dAndRebuild() - Focused " .. tostring(self.focusedRelativeIndex) .. "/" .. tostring(n) .. " " .. tostring(label))
			end
			return
		end
	end

	-- No .i3d entry found: keep focus, still rebuild (ensures showAll->focused view applies).
	self:rebuildRelativeTargetDebugPoints()
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:cycleFocusedRelativeTargetToNextI3dAndRebuild() - No .i3d entries in displayed targets")
	end
end

-- Distance (m) from node/placeable origin to the "forward" debug marker in the horizontal plane of baseYaw.
local RELATIVE_TARGET_FORWARD_MARKER_M = 3

--- World yaw (rad) used as base rotation for map-node-relative places: same as relRotation anchor in savePlaceAtFocusedMapNode.
-- Runtime: local +Z of the matched scene node → MathUtil.getYRotationFromDirection or atan2. Fallback: map XML entry.rotation.y (rad).
function IAPlacesLoader:computeMapNodeBaseYawRad(entry, runtimeNodeId)
	if entry == nil or entry.type ~= "node" then
		return 0
	end
	if runtimeNodeId ~= nil and runtimeNodeId ~= 0 and entityExists(runtimeNodeId) and localDirectionToWorld ~= nil then
		local fx, _, fz = localDirectionToWorld(runtimeNodeId, 0, 0, 1)
		if fx ~= nil and fz ~= nil then
			local yaw = (MathUtil and MathUtil.getYRotationFromDirection and MathUtil.getYRotationFromDirection(fx, fz)) or math.atan2(fx, fz)
			if yaw ~= nil then
				return yaw
			end
		end
	end
	return (entry.rotation and entry.rotation.y) or 0
end

local function iaAddRelativeTargetForwardDebugPoint(ianeighbours, px, py, pz, baseYawRad)
	if ianeighbours == nil or px == nil or pz == nil or baseYawRad == nil or baseYawRad ~= baseYawRad then
		return
	end
	local dist = RELATIVE_TARGET_FORWARD_MARKER_M
	local sinr, cosr = math.sin(baseYawRad), math.cos(baseYawRad)
	local fx = px + sinr * dist
	local fz = pz + cosr * dist
	local fy = py or 0
	if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		local th = getTerrainHeightAtWorldPos(g_terrainNode, fx, 0, fz)
		if th ~= nil and th == th then
			fy = th + 0.15
		end
	end
	ianeighbours:addDebugPointAtPosition(fx, fy, fz, "→ forward", nil)
end

--- Rebuild debug points from displayedRelativeTargets; the focused entry is labeled "focused".
-- Shift+F6: all targets in range + focused gets a second "→ forward" marker along node/placeable +Z.
-- Ctrl+Y: only the focused target (position + forward); press Shift+F6 again to show all markers.
function IAPlacesLoader:rebuildRelativeTargetDebugPoints()
	if self.ianeighbours == nil then
		return
	end
	self.ianeighbours:clearAllDebugPoints()
	local list = self.displayedRelativeTargets or {}
	if #list == 0 then
		return
	end
	local mapRoot = IAMapInitJob and IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
	local runtimeNodes = (mapRoot and IAMapInitJob.collectRuntimeMapNodes and IAMapInitJob.collectRuntimeMapNodes(mapRoot)) or {}
	local showAll = self.relativeTargetsShowAll ~= false
	local i0, i1 = 1, #list
	if not showAll then
		if self.focusedRelativeIndex < 1 or self.focusedRelativeIndex > #list then
			return
		end
		i0, i1 = self.focusedRelativeIndex, self.focusedRelativeIndex
	end

	for i = i0, i1 do
		local entry = list[i]
		local isFocused = (i == self.focusedRelativeIndex)
		local px, py, pz, rotY, label = nil, nil, nil, nil, ""
		local rtIdForForward = nil
		local placeableForForward = nil
		local forwardBaseYawRad = nil
		if entry.type == "node" then
			if entry.position and entry.position.x ~= nil and entry.position.y ~= nil and entry.position.z ~= nil then
				local nm = entry.name or ""
				if not string.find(nm or "", "%.gdm") and string.sub(nm, 1, 3) ~= "LOD" then
					px, py, pz = entry.position.x, entry.position.y, entry.position.z
					rotY = (entry.rotation and entry.rotation.y ~= nil) and entry.rotation.y or nil
					if entry.lockedGroup then
						label = "locked: " .. tostring(nm)
					else
						local i3dFull = (entry.referenceFilename and entry.referenceFilename ~= "") and entry.referenceFilename or (nm ~= "" and nm or nil)
						local i3dName = i3dFull and (i3dFull:match("([^/\\]+)$") or i3dFull) or nil
						if i3dName then
							label = "i3d: " .. tostring(i3dName)
						elseif entry.referenceId ~= nil then
							label = (nm ~= "" and nm .. " " or "") .. "[refId=" .. tostring(entry.referenceId) .. "]"
						else
							label = nm
						end
					end
					local xmlX, xmlY, xmlZ = entry.position.x, entry.position.y or 0, entry.position.z
					local rtId = entry.resolvedRuntimeNodeId
					if rtId == nil or rtId == 0 or not entityExists(rtId) then
						rtId = IAMapInitJob.findRuntimeNodeForXmlEntry and IAMapInitJob.findRuntimeNodeForXmlEntry(entry, runtimeNodes)
					end
					rtIdForForward = rtId
					local wx, wy, wz = nil, nil, nil
					if rtId ~= nil and rtId ~= 0 and entityExists(rtId) and getWorldTranslation then
						wx, wy, wz = getWorldTranslation(rtId)
					end
					if wx ~= nil and wz ~= nil then
						px, py, pz = wx, wy or 0, wz
						label = tostring(label) .. string.format(" | xml %.2f,%.2f,%.2f | node %.2f,%.2f,%.2f", xmlX, xmlY, xmlZ, px, py, pz)
					else
						label = tostring(label) .. string.format(" | xml %.2f,%.2f,%.2f | node --", xmlX, xmlY, xmlZ)
					end
					forwardBaseYawRad = self:computeMapNodeBaseYawRad(entry, rtIdForForward)
				end
			end
		elseif entry.type == "placeable" then
			if entry.position and entry.position.x ~= nil and entry.position.z ~= nil then
				px = entry.position.x
				py = entry.position.y or 0
				pz = entry.position.z
				rotY = entry.rotation
				label = entry.label or "placeable"
				placeableForForward = entry.placeable
				if placeableForForward ~= nil then
					forwardBaseYawRad = self:getPlaceableRotation(placeableForForward)
				end
			end
		end
		if px ~= nil and pz ~= nil then
			if isFocused then
				label = "focused: " .. tostring(label)
			end
			self.ianeighbours:addDebugPointAtPosition(px, py or 0, pz, label, rotY)
			if isFocused then
				iaAddRelativeTargetForwardDebugPoint(self.ianeighbours, px, py or 0, pz, forwardBaseYawRad)
			end
		end
	end
end

--- Save the current player/vehicle position as a place at the focused map node; add to IANeighbours.places and save to placeablePlaces.xml.
-- Uses the focused relative target when it is type "node". Call from dialog when getFocusedRelativeTarget().type == "node".
-- @param string placeType - Optional. Place type (e.g. "shop", "character_homebase"). If nil, uses "mapNode".
-- @param number characterNumber - Optional. Character number for character_homebase places.
-- @param boolean withVehicle - Optional. Whether place allows vehicles (default true when omitted).
-- @param boolean withAttachment - Optional. Whether place allows vehicle+attachment (default false when omitted).
-- @return boolean - true if saved
function IAPlacesLoader:savePlaceAtFocusedMapNode(placeType, characterNumber, withVehicle, withAttachment, sizeType)
	if withVehicle == nil then
		withVehicle = true
	end
	if withAttachment == nil then
		withAttachment = false
	end
	local focused = self:getFocusedRelativeTarget()
	if focused == nil or focused.type ~= "node" then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:savePlaceAtFocusedMapNode() - No focused map node")
		end
		return false
	end
	local x, y, z, rotation = nil, nil, nil, 0
	if g_localPlayer then
		local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
		if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) then
			x, y, z = getWorldTranslation(v.rootNode)
			rotation = getNodeYawFromForward(v.rootNode, 0)
		end
		if x == nil and g_localPlayer.getPosition then
			x, y, z = g_localPlayer:getPosition()
		end
	end
	if x == nil or z == nil then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:savePlaceAtFocusedMapNode() - No vehicle/player position")
		end
		return false
	end
	y = y or 0
	local nodeName = focused.name or ("MapNode " .. tostring(self.focusedRelativeIndex))
	local ptype = placeType or "mapNode"
	local nx = (focused.position and focused.position.x) or 0
	local ny = (focused.position and focused.position.y) or 0
	local nz = (focused.position and focused.position.z) or 0
	local dx = (x or 0) - nx
	local dy = (y or 0) - ny
	local dz = (z or 0) - nz
	local offsetX, offsetY, offsetZ
	local relRotation
	local mapRoot = IAMapInitJob and IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
	local runtimeNodeId = focused.resolvedRuntimeNodeId
	if (runtimeNodeId == nil or runtimeNodeId == 0 or not entityExists(runtimeNodeId)) and mapRoot then
		local runtimeNodes = IAMapInitJob.collectRuntimeMapNodes and IAMapInitJob.collectRuntimeMapNodes(mapRoot) or {}
		runtimeNodeId = IAMapInitJob.findRuntimeNodeForXmlEntry and IAMapInitJob.findRuntimeNodeForXmlEntry(focused, runtimeNodes)
	end
	-- Base yaw: shared with forward debug (computeMapNodeBaseYawRad) and IAMapPlace:resolveFromMapNodeWithRuntimeNode convention
	local nodeYaw = self:computeMapNodeBaseYawRad(focused, runtimeNodeId)
	if runtimeNodeId and entityExists(runtimeNodeId) then
		offsetX, offsetY, offsetZ = worldDirectionToLocal(runtimeNodeId, dx, dy, dz)
		relRotation = (rotation or 0) - nodeYaw
	else
		local cosRy = math.cos(nodeYaw)
		local sinRy = math.sin(nodeYaw)
		offsetX = dx * cosRy - dz * sinRy
		offsetY = dy
		offsetZ = dx * sinRy + dz * cosRy
		relRotation = (rotation or 0) - nodeYaw
	end
	while relRotation > math.pi do relRotation = relRotation - 2 * math.pi end
	while relRotation < -math.pi do relRotation = relRotation + 2 * math.pi end

	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local nextId = self:getNextFreeNumericPlaceId()
	local name
	if ptype == "character_homebase" then
		name = "Character homebase at " .. tostring(nodeName)
	elseif ptype == "mapNode" then
		name = "MapNode: " .. tostring(nodeName)
	else
		name = ptype .. " at " .. tostring(nodeName)
	end
	local place = IAMapPlace.new(nextId, name, ptype, 0, 0, 0, 0, withVehicle, withAttachment, sizeType, characterNumber, nil, offsetX, offsetY, offsetZ, relRotation)
	place.nodeName = nodeName
	if focused.referenceId ~= nil then place.referenceId = focused.referenceId end
	if focused.referenceFilename and focused.referenceFilename ~= "" then place.referenceFilename = focused.referenceFilename end
	if focused.id ~= nil then
		local idStr = tostring(focused.id)
		local idNum = tonumber(idStr)
		IAprintDebug("IAPlacesLoader:savePlaceAtFocusedMapNode()","idNum: " .. tostring(idNum),nil,nil,nil)
		local refData = IAMapInitJob and IAMapInitJob.getMapReferenceData and IAMapInitJob.getMapReferenceData()
		if idNum and refData and refData[idNum] then
			place.mapRefNodeId = idStr
			place.collisionExcludeRefIds = { idStr }
		end
	end
	if runtimeNodeId ~= nil and entityExists(runtimeNodeId) then
		place.resolvedMapNodeId = runtimeNodeId
	end
	table.insert(self.ianeighbours.places, place)
	if self.ianeighbours.xmlHelper then
		self.ianeighbours.xmlHelper:appendPlaceToPlaceablePlacesFile(place)
	end
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:savePlaceAtFocusedMapNode() - Saved to placeablePlaces.xml type=" .. tostring(ptype) .. " node=" .. tostring(nodeName) .. " offset=" .. tostring(offsetX) .. "," .. tostring(offsetZ))
	end
	return true
end

--- Save the current player/vehicle position as a place at the focused placeable; add to IANeighbours.places and save to placeablePlaces.xml.
-- Uses the focused relative target when it is type "placeable". Call from dialog when getFocusedRelativeTarget().type == "placeable".
-- @param string placeType - Optional. Place type.
-- @param number characterNumber - Optional. Character number for character_homebase places.
-- @param boolean withVehicle - Optional. Whether place allows vehicles (default true when omitted).
-- @param boolean withAttachment - Optional. Whether place allows vehicle+attachment (default false when omitted).
-- @return boolean - true if saved
function IAPlacesLoader:savePlaceAtFocusedPlaceable(placeType, characterNumber, withVehicle, withAttachment, sizeType)
	if withVehicle == nil then
		withVehicle = true
	end
	if withAttachment == nil then
		withAttachment = false
	end
	local focused = self:getFocusedRelativeTarget()
	if focused == nil or focused.type ~= "placeable" or focused.placeable == nil or focused.placeable.rootNode == nil or not focused.placeable.configFileName then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:savePlaceAtFocusedPlaceable() - No focused placeable")
		end
		return false
	end
	local placeable = focused.placeable
	local px, py, pz = self:getPlaceablePosition(placeable)
	local placeableRot = self:getPlaceableRotation(placeable)
	if px == nil or pz == nil then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:savePlaceAtFocusedPlaceable() - No placeable position")
		end
		return false
	end
	local x, y, z, rotation = nil, nil, nil, 0
	if g_localPlayer then
		local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
		if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) then
			x, y, z = getWorldTranslation(v.rootNode)
			rotation = getNodeYawFromForward(v.rootNode, 0)
		end
		if x == nil and g_localPlayer.getPosition then
			x, y, z = g_localPlayer:getPosition()
		end
	end
	if x == nil or z == nil then
		if self.ianeighbours.debug then
			print("--- IAPlacesLoader:savePlaceAtFocusedPlaceable() - No vehicle/player position")
		end
		return false
	end
	y = y or 0
	py = py or 0
	rotation = normalizeYawPi(rotation or 0)
	local relRotation = normalizeYawPi((rotation or 0) - (placeableRot or 0))
	-- Store offsets in placeable-local space so they resolve correctly on rotated instances.
	local dx = (x or 0) - px
	local dy = (y or 0) - py
	local dz = (z or 0) - pz
	local offsetX, offsetY, offsetZ = worldDirectionToLocal(placeable.rootNode, dx, dy, dz)
	if self.ianeighbours and self.ianeighbours.debug then
		print("--- IAPlacesLoader:savePlaceAtFocusedPlaceable() - playerYaw=" .. tostring(rotation) .. " placeableYaw=" .. tostring(placeableRot) .. " relRotation=" .. tostring(relRotation))
	end

	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local nextId = self:getNextFreeNumericPlaceId()
	local id = (characterNumber ~= nil) and characterNumber or nextId
	local ptype = placeType or "placeable"
	local name = (characterNumber ~= nil) and ("Character " .. tostring(characterNumber)) or ("Place " .. tostring(id))
	if ptype == "character_homebase" then
		name = "Character homebase at " .. tostring(focused.label or placeable.configFileName or "placeable")
	elseif ptype ~= "placeable" then
		name = ptype .. " at " .. tostring(focused.label or placeable.configFileName or "placeable")
	end
	local place = IAMapPlace.new(id, name, ptype, x or 0, y or 0, z or 0, rotation or 0, withVehicle, withAttachment, sizeType, characterNumber, placeable.configFileName, offsetX, offsetY, offsetZ, relRotation)
	table.insert(self.ianeighbours.places, place)
	if self.ianeighbours.xmlHelper then
		self.ianeighbours.xmlHelper:appendPlaceToPlaceablePlacesFile(place)
	end
	if self.ianeighbours.debug then
		print("--- IAPlacesLoader:savePlaceAtFocusedPlaceable() - Saved to placeablePlaces.xml type=" .. tostring(ptype) .. " placeable=" .. tostring(placeable.configFileName))
	end
	return true
end

--- Get world position from a placeable (x, y, z). Uses world space so offsets are truly relative.
-- @param table placeable - Placeable instance (e.g. from placeableSystem.placeables)
-- @return number x, number y, number z - or nil,nil,nil if invalid
function IAPlacesLoader:getPlaceablePosition(placeable)
	if placeable == nil or placeable.rootNode == nil then
		return nil, nil, nil
	end
	local x, y, z = getWorldTranslation(placeable.rootNode)
	return x, y, z
end

--- Get world yaw from a placeable in radians. Uses world space so relRotation is truly relative.
-- @param table placeable - Placeable instance
-- @return number rotation - y rotation in radians, or 0 if invalid
function IAPlacesLoader:getPlaceableRotation(placeable)
	if placeable == nil or placeable.rootNode == nil then
		return 0
	end
	return getNodeYawFromForward(placeable.rootNode, 0)
end

--- Check if a place already exists near the given position (within threshold).
-- @param number x, number z - world position
-- @param number threshold - distance threshold in meters (default 2)
-- @return boolean - true if a place is already near this position
function IAPlacesLoader:hasPlaceNear(x, z, threshold)
	threshold = threshold or 2
	if self.ianeighbours.places == nil then
		return false
	end
	for _, p in ipairs(self.ianeighbours.places) do
		if p and p.x ~= nil and p.z ~= nil then
			local dx = (p.x - x)
			local dz = (p.z - z)
			if (dx * dx + dz * dz) <= (threshold * threshold) then
				return true
			end
		end
	end
	return false
end

--- Find places from the placeable system and add them to IANeighbours.places.
-- Uses placeable rootNode position and configFileName (or typeName) as place type.
-- Skips placeables that already have a place near their position.
-- @param table placeableSystem - Optional. Defaults to g_currentMission.placeableSystem.
-- @param table options - Optional. { typeFilter = "string" } to only add placeables whose type contains this; skipDuplicateRadius = number (default 2) }
-- @return number - Number of new places added
function IAPlacesLoader:findPlacesFromPlaceables(placeableSystem, options)
	placeableSystem = placeableSystem or (g_currentMission and g_currentMission.placeableSystem)
	if placeableSystem == nil or placeableSystem.placeables == nil then
		return 0
	end
	options = options or {}
	local typeFilter = options.typeFilter  -- e.g. "shop" or "gasStation"
	local skipRadius = options.skipDuplicateRadius or 2
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end

	local added = 0
	local nextId = self:getNextFreeNumericPlaceId()

	for _, placeable in ipairs(placeableSystem.placeables) do
		if placeable ~= nil and placeable.rootNode ~= nil then
			local x, y, z = self:getPlaceablePosition(placeable)
			if x ~= nil and z ~= nil and not self:hasPlaceNear(x, z, skipRadius) then
				local placeType = placeable.configFileName or placeable.typeName or "placeable"
				local passFilter = (typeFilter == nil or typeFilter == "") or (string.find(string.lower(placeType), string.lower(typeFilter)) ~= nil)
				if passFilter then
					local name = placeable.getName and placeable:getName() or placeType
					if type(name) ~= "string" or name == "" then
						name = placeType .. " " .. tostring(nextId)
					end
					local rotation = self:getPlaceableRotation(placeable)
					local place = IAMapPlace.new(nextId, name, placeType, x, y or 0, z, rotation, true, false, nil, nil)
					table.insert(self.ianeighbours.places, place)
					nextId = nextId + 1
					added = added + 1
					if self.ianeighbours.debug then
						print("--- IAPlacesLoader:findPlacesFromPlaceables() - Added place: " .. tostring(name) .. " (" .. tostring(placeType) .. ") at " .. tostring(x) .. "," .. tostring(z))
					end
				end
			end
		end
	end

	return added
end

--- Find places from placeables that match a given type name (e.g. "shop", "gasStation").
-- Convenience wrapper around findPlacesFromPlaceables with typeFilter.
-- @param string placeableTypeName - Substring to match in placeable type/config name (case-insensitive)
-- @param table placeableSystem - Optional. Defaults to g_currentMission.placeableSystem.
-- @return number - Number of new places added
function IAPlacesLoader:findPlacesFromPlaceablesByType(placeableTypeName, placeableSystem)
	return self:findPlacesFromPlaceables(placeableSystem, { typeFilter = placeableTypeName })
end

--- Add a single place from a placeable to IANeighbours.places.
-- @param table placeable - Placeable instance
-- @param string overrideType - Optional. Use this as place type instead of placeable's config/type.
-- @param string overrideName - Optional. Use this as place name instead of placeable's name.
-- @return IAMapPlace place - The created place, or nil if invalid
function IAPlacesLoader:addPlaceFromPlaceable(placeable, overrideType, overrideName)
	if placeable == nil or placeable.rootNode == nil then
		return nil
	end
	local x, y, z = self:getPlaceablePosition(placeable)
	if x == nil or z == nil then
		return nil
	end
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end
	local nextId = self:getNextFreeNumericPlaceId()
	local placeType = overrideType or placeable.configFileName or placeable.typeName or "placeable"
	local name = overrideName or (placeable.getName and placeable:getName()) or (placeType .. " " .. tostring(nextId))
	if type(name) ~= "string" or name == "" then
		name = placeType .. " " .. tostring(nextId)
	end
	local rotation = self:getPlaceableRotation(placeable)
	local place = IAMapPlace.new(nextId, name, placeType, x, y or 0, z, rotation, true, false, nil, nil)
	table.insert(self.ianeighbours.places, place)
	return place
end
