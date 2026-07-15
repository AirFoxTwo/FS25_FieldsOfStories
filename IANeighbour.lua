--
-- FS25 - InteractiveNeighbours - Neighbour Class
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 31.12.2025
-- @Version: 1.0.0.0
--

IANeighbour = {}
IANeighbour._mt = Class(IANeighbour)
IANeighbour.guyModel = nil
IANeighbour.hasAnimation = false
IANeighbour.guyModelAnimationLoaded = false
IANeighbour.npcInstance = nil
IANeighbour.styleApplied = false
IANeighbour.fullLoaded = false
IANeighbour.activeSituationId = nil
IANeighbour.activeSituation = nil
IANeighbour.spot = nil
-- Y position used when NPC is hidden so rootNode (collision/view box) does not block
IANeighbour.NPC_HIDDEN_Y = -10000
-- Rotate the visible NPC model toward the player when within this horizontal range (meters).
IANeighbour.NPC_LOOK_AT_PLAYER_MAX_DIST = 18
IANeighbour.NPC_LOOK_AT_PLAYER_MIN_DIST = 0.45
-- Maximum yaw rate toward the player (rad/s); `dt` is milliseconds (same as IANeighbours:update).
IANeighbour.NPC_LOOK_AT_TURN_SPEED = 7

--- Voice id per character id (1–21), from helper/voice_config.json "characterVariants".
-- Conversation OGG names: `{lang}_{gender}_{voiceId}_{entryId}.ogg`.
IANeighbour.CHARACTER_VOICE_IDS = {
	[1] = 8,
	[2] = 1,
	[3] = 7,
	[4] = 2,
	[5] = 9,
	[6] = 6,
	[7] = 17,
	[8] = 19,
	[9] = 16,
	[10] = 21,
	[11] = 14,
	[12] = 4,
	[13] = 5,
	[14] = 3,
	[15] = 20,
	[16] = 18,
	[17] = 12,
	[18] = 13,
	[19] = 15,
	[20] = 10,
	[21] = 11,
}

--- Static: TTS voice id for a character/neighbour id (typically 1–21).
-- @param characterId number|string|nil
-- @return number|nil voice id for filenames, or nil if not in CHARACTER_VOICE_IDS
function IANeighbour.getVoiceIdForCharacter(characterId)
	local id = tonumber(characterId)
	if id == nil then
		return nil
	end
	return IANeighbour.CHARACTER_VOICE_IDS[id]
end

function IANeighbour.isFiniteNumber(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function IANeighbour.isFiniteCoords(x, y, z)
	return IANeighbour.isFiniteNumber(x) and IANeighbour.isFiniteNumber(y) and IANeighbour.isFiniteNumber(z)
end

--- Shortest signed difference b - a in radians, result in (-pi, pi].
function IANeighbour.shortestAngleDiffRadians(a, b)
	if not IANeighbour.isFiniteNumber(a) or not IANeighbour.isFiniteNumber(b) then
		return 0
	end
	local d = b - a
	d = (d + math.pi) % (2 * math.pi) - math.pi
	return d
end

--- Rotation from game logic (vehicle beside pose or place yaw) when leaving look-at while NPC stays visible.
function IANeighbour:restoreNpcRotationFromSituation()
	local sit = self.activeSituation
	if sit ~= nil and sit.vehicle ~= nil and sit.vehicle.npcRotation ~= nil then
		self.realRotation = sit.vehicle.npcRotation
		return
	end
	if sit ~= nil and sit.rotation ~= nil then
		self.realRotation = sit.rotation
		return
	end
	if self.rotation ~= nil then
		self.realRotation = self.rotation
	end
end

-- Smoothly rotate the active human NPC toward the local player when in range; restore scenario yaw when leaving range.
function IANeighbour:updateNPCLookAtPlayer(dt)
	local npc = self.npcInstance
	if not self.fullLoaded or npc == nil or not npc.isActive then
		self._npcLookAtPlayerActive = false
		return
	end
	if g_localPlayer == nil or not g_localPlayer.getPosition then
		self._npcLookAtPlayerActive = false
		return
	end
	local nx, nz = self.realPositionX, self.realPositionZ
	if not IANeighbour.isFiniteNumber(nx) or not IANeighbour.isFiniteNumber(nz) then
		self._npcLookAtPlayerActive = false
		return
	end
	local dist = self.distanceToPlayer
	if dist == nil then
		self._npcLookAtPlayerActive = false
		return
	end
	local maxD = IANeighbour.NPC_LOOK_AT_PLAYER_MAX_DIST
	local minD = IANeighbour.NPC_LOOK_AT_PLAYER_MIN_DIST
	if dist > maxD then
		if self._npcLookAtPlayerActive then
			self:restoreNpcRotationFromSituation()
			self:syncHumanModelWorldPose()
			if npc.updatePosition ~= nil then
				npc:updatePosition()
			end
		end
		self._npcLookAtPlayerActive = false
		return
	end
	if dist < minD then
		return
	end
	local px, _, pz = g_localPlayer:getPosition()
	if not IANeighbour.isFiniteNumber(px) or not IANeighbour.isFiniteNumber(pz) then
		return
	end
	local dx, dz = px - nx, pz - nz
	if not IANeighbour.isFiniteNumber(dx) or not IANeighbour.isFiniteNumber(dz) then
		return
	end
	local targetYaw = MathUtil.getYRotationFromDirection(dx, dz)
	local current = self.realRotation or self.rotation or 0
	local delta = IANeighbour.shortestAngleDiffRadians(current, targetYaw)
	local dtSec = (type(dt) == "number" and dt > 0) and (dt / 1000) or 0
	local maxStep = IANeighbour.NPC_LOOK_AT_TURN_SPEED * dtSec
	local step = delta
	if maxStep > 0 and math.abs(delta) > maxStep then
		step = (delta > 0) and maxStep or -maxStep
	end
	self.realRotation = current + step
	self:syncHumanModelWorldPose()
	if npc.updatePosition ~= nil then
		npc:updatePosition()
	end
	self._npcLookAtPlayerActive = true
end

-- Create a new Neighbour instance
-- @param string name - Name of the neighbour
-- @param boolean enabled - Whether the neighbour is enabled
-- @param number positionX - X position
-- @param number positionY - Y position
-- @param number positionZ - Z position
-- @param number rotation - Rotation in radians
-- @param string action - Action type
-- @param number farmId - Farm ID
-- @param string gender - Gender ("Male" or "Female")
-- @param string characterVisibility - Character visibility ("yes", "in_car", or other)
-- @param IANeighbours ianeighbours - Parent instance (optional; for assignHomebasePlace etc.)
function IANeighbour.new(id, name, enabled, positionX, positionY, positionZ, rotation, action, farmId, gender, characterVisibility, ianeighbours)
	local self = setmetatable({}, IANeighbour._mt)
	
	self.ianeighbours = ianeighbours  -- parent IANeighbours instance (set when neighbour is created by loader)
	self.name = name or "Unknown"
	self.id = id or math.random(10000,90000)
	self.enabled = enabled or false
	self.positionX = positionX
	self.positionY = positionY
	self.positionZ = positionZ
	self.rotation = rotation or 0
	self.action = action
	self.farmId = farmId
	self.gender = gender or "Male"
	self.characterVisibility = characterVisibility or "yes"
	self.activeSituationId = nil
	self.activeSituation = nil
	self.fullLoaded = false
	self.styleApplied = false
	self.npcInstance = nil
	self.humanModel = nil
	self.humanCharacter = nil
	self.resolvedPlayerStyle = nil
	self.humanModelStyleReady = false
	-- After HumanModel / PlayerStyle async steps the engine may toggle mesh visibility; re-run host show on the next neighbour tick.
	self.humanModelSubtreeShowDeferred = false
	self.standingIdleRetryHost = nil
	self.standingIdleRetryAccumS = nil
	self.standingIdleRetryCount = nil
	self.styleAttributes = nil  -- Store style attributes until NPC is loaded
	-- When true (e.g. after Shift+F3 character reset), keep styleAttributes for outbound XML but do not call updateStyle until next savegame load (new neighbour instances).
	self.suppressNpcStyleApplicationUntilSavegameLoad = false
	self.spot = nil
	
	-- Scenario-specific attributes (from scenario.xml)
	self.relationship = nil
	self.relationshipLevel = 1
	self.relationshipScore = 0
	self.role = nil
	self.job = nil
	self.belongsToFarm = false
	self.age = nil
	self.defaultPlaceId = nil
	self.roleScenarioDescription = nil
	self.behaviours = {}
	
	-- Internal state
	self.initialized = false

	self.vehicles = {}
	
	-- Real position tracking (updated from vehicle)
	self.realPositionX = nil
	self.realPositionY = nil
	self.realPositionZ = nil
	self.realRotation = nil
	
	-- Distance to player
	self.distanceToPlayer = nil

	self.lastJob = nil
	
	-- Map hotspot
	self.mapHotspot = nil
	
	-- Situation history (array of past situation data)
	self.situationHistory = {}
	
	-- Track if situation has been initialized from XML (first run)
	self.situationInitialized = false
	
	-- Assigned farmlands array
	self.assignedFarmlands = {}
	-- Last crop per assigned farmland (farmlandId -> fruitTypeIndex); used to compute next crop for SEED (must not repeat)
	self.assignedFarmlandLastCrop = {}
	-- Next crop per assigned farmland (farmlandId -> fruitTypeIndex); set when we set lastCrop so it stays stable across evaluations
	self.assignedFarmlandNextCrop = {}
	-- Daily fieldwork queue (game calendar day + ordered tasks); persisted in outbound XML
	self.fieldworkScheduleYear = nil
	self.fieldworkScheduleMonth = nil
	self.fieldworkScheduleDayInPeriod = nil
	self.fieldworkScheduleTasks = {}
	-- Hour (0..23) / minute (0..59) at which this neighbour will try to call the player (for contract offers, business logic pending).
	-- Set in rebuildDailyFieldworkSchedule once per game day; persisted in outbound XML.
	self.callPlayerHour = nil
	self.callPlayerMinute = nil
	-- When set to schedule day key "y_m_d": first contract ring of that day opened (plan lock for empty-queue rebuild; cleared in rebuildDailyFieldworkSchedule).
	self.contractCallTriggerFiredForScheduleKey = nil
	self.contractCallRingOpensCount = 0
	self.contractCallRingAnsweredToday = false
	-- When set to same schedule key, 15:00 fallback already cleared pending contract rows for that day (cleared in rebuildDailyFieldworkSchedule).
	self.contractFallbackToAiFiredForScheduleKey = nil
	-- Actual last ring time, used so missed-call retries wait a real in-game hour even if the planned slot was already late.
	self.contractCallLastRingScheduleKey = nil
	self.contractCallLastRingTotalMinutes = nil

	-- Homebase place ids (assignment stored on neighbour, not on places)
	self.assignedHomebasePlaceIds = {}
	-- Workplace place ids (type character_job); persisted like homebase in outbound + map config
	self.assignedWorkplacePlaceIds = {}

	self.dynamicConversationData = IANeighbourDynamicConversationData.new(self)

	return self
end

--- Resolved TTS voice id for conversation audio: `{lang}_{gender}_{voiceId}_{entryId}.ogg`.
-- Uses getVoiceIdForCharacter(self.id); unmapped ids use 1.
-- @return number
function IANeighbour:getVoiceId()
	local fromMap = IANeighbour.getVoiceIdForCharacter(self.id)
	if fromMap ~= nil then
		return fromMap
	end
	return 1
end

--- In-game time reached the daily contract-call window: play incoming ring + bundled dynamic conversation payload for all contract rows that day (player opens phone with IAStartConversation to answer).
--- @return boolean true if ring + payload were scheduled (caller may mark schedule-day fired)
function IANeighbour:onContractCallTimeTriggered()
	if IANeighbours == nil then
		return false
	end
	local helper = self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper or nil
	if helper == nil then
		return false
	end

	local contractOpenList = {}
	local farmlandSeen = {}
	local farmlandIdsOrdered = {}
	-- If this neighbour is already actively doing fieldwork on a farmland, do not offer it via phone.
	local blockedFarmlandId = (self.activeSituation ~= nil and self.activeSituation.jobType ~= nil and self.activeSituation.farmlandId ~= nil) and tonumber(self.activeSituation.farmlandId) or nil
	if self.fieldworkScheduleTasks ~= nil then
		-- Iterate backwards so we can prune stale contract rows (fieldwork already done / no longer matches config).
		for i = #self.fieldworkScheduleTasks, 1, -1 do
			local row = self.fieldworkScheduleTasks[i]
			if row ~= nil and row.contractEnabled == true then
				if blockedFarmlandId ~= nil and tonumber(row.farmlandId) == blockedFarmlandId then
					-- Keep row but do not offer it while neighbour is actively working it.
				else
					local openFw = helper:validateScheduleEntry(self, row)
					if openFw ~= nil then
						table.insert(contractOpenList, openFw)
						local fid = openFw.farmlandId
						if fid ~= nil and not farmlandSeen[fid] then
							farmlandSeen[fid] = true
							table.insert(farmlandIdsOrdered, fid)
						end
					else
						-- Stale contract-enabled schedule entry: remove so it won't be re-offered again.
						table.remove(self.fieldworkScheduleTasks, i)
					end
				end
			end
		end
	end

	table.sort(farmlandIdsOrdered)

	if #contractOpenList == 0 then
		if IANeighbours.debug then
			print("--- IANeighbour:onContractCallTimeTriggered() - no valid contract rows for neighbour " .. tostring(self.name))
		end
		return false
	end

	local jobConfig = contractOpenList[1].config
	local totalHaRounded = helper:sumRoundedHectaresForFarmlandIds(farmlandIdsOrdered)
	-- Dynamic conversation variables: see IANeighbourDynamicConversationData header for the
	-- contract. jobType and vehicleNameWithArticle share the IAFieldwork.JobType enum value as
	-- catalog key; extraRefillNote is "needed" only for implements that consume refillable
	-- material (seed/spray/fertilizer); the rest are raw strings displayed verbatim.
	local jobTypeEnum = IAFieldwork.normalizeFieldworkJobType(jobConfig.fieldwork) or "other"
	local usesRefillable = IAFieldwork.fieldworkImplementUsesRefillableConsumable(jobConfig.fieldwork)
	local mission = {
		config = jobConfig,
		farmlandIds = farmlandIdsOrdered,
		farmlandId = farmlandIdsOrdered[1],
		contractOpenFieldworkList = contractOpenList,
		variableMap = {
			jobType                = jobTypeEnum,
			vehicleNameWithArticle = jobTypeEnum,
			extraRefillNote        = usesRefillable and "needed" or nil,
			fieldNumber            = tostring(farmlandIdsOrdered[1]),
			fieldNumbers           = table.concat(farmlandIdsOrdered, ", "),
			totalHectares          = tostring(totalHaRounded),
			situationId            = jobConfig.id ~= nil and tostring(jobConfig.id) or nil,
		},
	}

	if self.dynamicConversationData == nil then
		return false
	end

	local n = self
	local callbacksByAction = {
		accept = function()
			local h = n.ianeighbours and n.ianeighbours.gameLoopHelper
			if h ~= nil and type(h.markAllContractRowsAsAcceptedByPlayer) == "function" then
				h:markAllContractRowsAsAcceptedByPlayer(n)
			end
			local farmId = (g_localPlayer ~= nil and g_localPlayer.farmId) or (g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId()) or nil
			if farmId ~= nil and h ~= nil and type(h.createAndRegisterFieldMissionsForOpenFieldworkList) == "function" then
				h:createAndRegisterFieldMissionsForOpenFieldworkList(mission.contractOpenFieldworkList or {}, farmId, false, nil)
			end
		end,
		accept_with_equipment = function()
			local h = n.ianeighbours and n.ianeighbours.gameLoopHelper
			if h ~= nil and type(h.markAllContractRowsAsAcceptedByPlayer) == "function" then
				h:markAllContractRowsAsAcceptedByPlayer(n)
			end
			local farmId = (g_localPlayer ~= nil and g_localPlayer.farmId) or (g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId()) or nil
			if farmId ~= nil and h ~= nil and type(h.createAndRegisterFieldMissionsWithBorrow) == "function" then
				h:createAndRegisterFieldMissionsWithBorrow(n, mission.contractOpenFieldworkList or {}, farmId, nil)
			end
		end,
		accept_half = function()
			local h = n.ianeighbours and n.ianeighbours.gameLoopHelper
			local openList = mission.contractOpenFieldworkList or {}
			local takeCount = math.max(1, math.floor(#openList / 2))
			if h ~= nil and type(h.markAcceptedContractRowsAndDemoteRest) == "function" then
				h:markAcceptedContractRowsAndDemoteRest(n, openList, takeCount)
			end
			local farmId = (g_localPlayer ~= nil and g_localPlayer.farmId) or (g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId()) or nil
			if farmId ~= nil and h ~= nil and type(h.createAndRegisterFieldMissionsForOpenFieldworkList) == "function" then
				h:createAndRegisterFieldMissionsForOpenFieldworkList(openList, farmId, false, takeCount)
			end
		end,
		accept_half_with_equipment = function()
			local h = n.ianeighbours and n.ianeighbours.gameLoopHelper
			local openList = mission.contractOpenFieldworkList or {}
			local takeCount = math.max(1, math.floor(#openList / 2))
			if h ~= nil and type(h.markAcceptedContractRowsAndDemoteRest) == "function" then
				h:markAcceptedContractRowsAndDemoteRest(n, openList, takeCount)
			end
			local farmId = (g_localPlayer ~= nil and g_localPlayer.farmId) or (g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId()) or nil
			if farmId ~= nil and h ~= nil and type(h.createAndRegisterFieldMissionsWithBorrow) == "function" then
				h:createAndRegisterFieldMissionsWithBorrow(n, openList, farmId, takeCount)
			end
		end,
		decline = function()
			local h = n.ianeighbours and n.ianeighbours.gameLoopHelper
			if h ~= nil and type(h.applyContractFallbackToAi) == "function" then
				h:applyContractFallbackToAi(n, "decline")
			end
		end,
		-- callbackOnPlaybackEnd hooks: hang up cleanly after the NPC's closing line so the contract
		-- phone call ends instead of falling through to the smalltalk main menu (set by
		-- IANeighbours.answerIncomingPhoneFromPayload). Safe to call stop() inside the playback-end
		-- callback: IAConversation:advanceNext() bails out when currentId is nil after stop().
		after_accept = function(conv)
			if conv ~= nil and type(conv.stop) == "function" then
				conv:stop(false)
			end
		end,
		after_accept_half = function(conv)
			if conv ~= nil and type(conv.stop) == "function" then
				conv:stop(false)
			end
		end,
		after_decline = function(conv)
			if conv ~= nil and type(conv.stop) == "function" then
				conv:stop(false)
			end
		end,
	}

	local topic = IANeighbourDynamicConversationData.TOPIC_FIELD_MISSION_OFFER
	if #farmlandIdsOrdered == 1 then
		topic = IANeighbourDynamicConversationData.TOPIC_FIELD_MISSION_OFFER_SINGLE
	end
	local entryFilter = nil
	if IAMissionBorrow ~= nil and type(IAMissionBorrow.buildContractEntryAvailabilityFilter) == "function" then
		entryFilter = IAMissionBorrow.buildContractEntryAvailabilityFilter(n, mission.contractOpenFieldworkList or {})
	end
	local conv = self.dynamicConversationData:createLoadedConversationForMission(topic, mission, callbacksByAction, entryFilter)
	if conv == nil and topic == IANeighbourDynamicConversationData.TOPIC_FIELD_MISSION_OFFER_SINGLE then
		topic = IANeighbourDynamicConversationData.TOPIC_FIELD_MISSION_OFFER
		conv = self.dynamicConversationData:createLoadedConversationForMission(topic, mission, callbacksByAction, entryFilter)
	end
	if conv == nil then
		if IANeighbours.debug then
			print("--- IANeighbour:onContractCallTimeTriggered() - failed to load dynamic conversation for topic " .. tostring(topic))
		end
		return false
	end
	if IANeighbours.debug then
		print("--- IANeighbour:onContractCallTimeTriggered() - id=" .. tostring(self.id) .. " name=" .. tostring(self.name) .. " fields=" .. tostring(#farmlandIdsOrdered) .. " ha=" .. tostring(totalHaRounded))
	end
	IANeighbours.pendingIncomingPhoneNeighbourId = self.id
	local showed = IANeighbours.tryShowIncomingPhoneRing(self, {
		neighbourId = self.id,
		neighbourName = self.name,
		conversation = conv,
		isContractFieldMissionOffer = true,
	})
	if not showed then
		IANeighbours.pendingIncomingPhoneNeighbourId = nil
	end
	return showed
end

--- Write neighbourHomebaseAssignments / neighbourWorkplaceAssignments to fields_of_stories_<mapId>.xml (outbound alone does not update map config).
-- @param string reason optional debug label (shown when IANeighbours.debug)
local function iaPersistNeighbourAssignmentsToMapConfig(ianeighbours, reason)
	local xh = ianeighbours and ianeighbours.xmlHelper
	if xh == nil or xh.saveMapConfigToFile == nil then
		return
	end
	local m = g_currentMission
	if m == nil or m.missionInfo == nil or m.missionInfo.mapId == nil then
		return
	end
	if IANeighbours and IANeighbours.debug then
		print("--- saveMapConfigToFile caller: iaPersistNeighbourAssignmentsToMapConfig mapId=" .. tostring(m.missionInfo.mapId) .. " reason=" .. tostring(reason or "?"))
	end
	pcall(function()
		xh:saveMapConfigToFile(m.missionInfo.mapId)
	end)
end

local function iaNeighbourIdsEqual(a, b)
	if a == nil or b == nil then
		return false
	end
	if a == b then
		return true
	end
	local na, nb = tonumber(tostring(a)), tonumber(tostring(b))
	return na ~= nil and nb ~= nil and na == nb
end

--- Add a character_homebase place to this neighbour's assigned list (by place id). Persists map config immediately; outbound on next career save.
-- Does not create a new place or set place.characterNumber; the place already exists in places.
-- @param IAMapPlace place - The place to assign (place.id is added to assignedHomebasePlaceIds)
-- @return boolean - true if added and persisted
function IANeighbour:assignHomebasePlace(place)
	if place == nil or place.id == nil then
		return false
	end
	if self.assignedHomebasePlaceIds == nil then
		self.assignedHomebasePlaceIds = {}
	end
	for _, id in ipairs(self.assignedHomebasePlaceIds) do
		if iaNeighbourIdsEqual(id, place.id) then
			return true  -- already in list
		end
	end
	table.insert(self.assignedHomebasePlaceIds, place.id)
	local ianeighbours = self.ianeighbours
	if IANeighbours and IANeighbours.debug then
		print("--- IANeighbour:assignHomebasePlace() - Assigned place id " .. tostring(place.id) .. " for " .. tostring(self.name))
	end
	iaPersistNeighbourAssignmentsToMapConfig(ianeighbours, "IANeighbour:assignHomebasePlace id=" .. tostring(self.id))
	return true
end

--- Add a character_job workplace place to this neighbour's assigned list (by place id). Persists map config immediately; outbound on next career save.
-- @param IAMapPlace place
-- @return boolean
function IANeighbour:assignWorkplacePlace(place)
	if place == nil or place.id == nil then
		return false
	end
	if self.assignedWorkplacePlaceIds == nil then
		self.assignedWorkplacePlaceIds = {}
	end
	for _, id in ipairs(self.assignedWorkplacePlaceIds) do
		if id == place.id then
			return true
		end
	end
	table.insert(self.assignedWorkplacePlaceIds, place.id)
	local ianeighbours = self.ianeighbours
	if IANeighbours and IANeighbours.debug then
		print("--- IANeighbour:assignWorkplacePlace() - Assigned workplace place id " .. tostring(place.id) .. " for " .. tostring(self.name))
	end
	iaPersistNeighbourAssignmentsToMapConfig(ianeighbours, "IANeighbour:assignWorkplacePlace id=" .. tostring(self.id))
	return true
end

--- Add relationship score and handle level-ups. Outbound persists on next career save.
-- Positive amount: increments score, may level up, plays success/levelup sound, awards money mirror.
-- Negative amount: decrements score (clamped at 0, no level-down), plays failed sound, no money —
-- used e.g. when an IAFieldOutcomeMission ends as CANCELED / FAILED / TIMED_OUT.
-- @param amount number points to add (positive) or remove (negative); 0 is a no-op
function IANeighbour:addScore(amount)
	local add = tonumber(amount) or 0
	if add == 0 then
		return
	end
	if self.relationshipLevel == nil then
		self.relationshipLevel = 1
	end
	if self.relationshipScore == nil then
		self.relationshipScore = 0
	end
	local beforeLevel = tonumber(self.relationshipLevel) or 1
	local scoreDecreased = add < 0
	self.relationshipScore = self.relationshipScore + add

	local levelUp = false
	if not scoreDecreased then
		local threshold = 500 * beforeLevel
		if self.relationshipScore >= threshold then
			self.relationshipLevel = beforeLevel + 1
			self.relationshipScore = 0
			levelUp = true
		end
	elseif self.relationshipScore < 0 then
		self.relationshipScore = 0
	end

	-- Play feedback sound (best-effort). Keep sample handle until it finishes (cleanup in update()).
	-- Positive delta: success or level-up sound. Negative delta: failed sound.
	if IANeighbours ~= nil and IANeighbours.dir ~= nil then
		local rel
		if scoreDecreased then
			rel = "sound/failed_sound.ogg"
		elseif levelUp then
			rel = "sound/levelup_sound.ogg"
		else
			rel = "sound/success_sound.ogg"
		end
		local fileName = Utils.getFilename(rel, IANeighbours.dir)
		if fileName ~= nil and fileName ~= "" and fileExists(fileName) then
			if self.scoreSample ~= nil then
				delete(self.scoreSample)
				self.scoreSample = nil
			end
			local sample = createSample("IANeighbour_score")
			if sample ~= nil and sample ~= 0 then
				if loadSample(sample, fileName, false) then
					playSample(sample, 1, 1, 0, 0, 0)
					self.scoreSample = sample
				else
					delete(sample)
				end
			end
		end
	end

	-- Notification (translated)
	if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and g_i18n ~= nil and g_i18n.getText ~= nil and FSBaseMission ~= nil then
		local key
		local notifLevel
		if scoreDecreased then
			key = "ingame_relationship_decreased"
			notifLevel = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
		elseif levelUp then
			key = "ingame_relationship_levelup"
			notifLevel = FSBaseMission.INGAME_NOTIFICATION_OK
		else
			key = "ingame_relationship_improved"
			notifLevel = FSBaseMission.INGAME_NOTIFICATION_OK
		end
		local tpl = g_i18n:getText(key)
		if tpl ~= nil and tpl ~= "" then
			local text = nil
			if levelUp then
				text = string.format(tpl, tostring(self.name), tostring(self.relationshipLevel))
			elseif scoreDecreased then
				text = string.format(tpl, tostring(self.name), tostring(-add))
			else
				text = string.format(tpl, tostring(self.name), tostring(add))
			end
			g_currentMission:addIngameNotification(notifLevel, text)
		end
	end

	-- Reward player money on positive deltas only: score gain + (on level-up) 500 * previous level.
	-- Negative deltas never deduct money; the relationship penalty is the entire effect.
	if not scoreDecreased and g_currentMission ~= nil and g_currentMission.addMoney ~= nil and g_currentMission.playerSystem ~= nil and MoneyType ~= nil then
		local player = g_currentMission.playerSystem:getLocalPlayer()
		if player ~= nil and player.farmId ~= nil then
			local money = add
			if levelUp then
				money = money + (500 * beforeLevel)
			end
			if money ~= 0 then
				g_currentMission:addMoney(money, player.farmId, MoneyType.OTHER)
			end
		end
	end

end

function IANeighbour:_isFemaleGender()
	return string.lower(tostring(self.gender or "male")) == "female"
end

function IANeighbour:_playerCharacterXmlPath()
	if self:_isFemaleGender() then
		return "dataS/character/playerF/playerF.xml"
	end
	return "dataS/character/playerM/playerM.xml"
end

function IANeighbour:_styleTemplateForGender()
	if IANeighbours == nil then
		return nil
	end
	if self:_isFemaleGender() then
		return IANeighbours.femaleStyleTemplate
	end
	return IANeighbours.maleStyleTemplate
end

function IANeighbour:_mergeSpawnStyleParams()
	local p = {
		hathair = 12,
		glasses = 0,
		glassesColorIndex = 1,
		facegear = 0,
		facegearColorIndex = 1,
		onepiece = 5,
		onepieceColorIndex = 1,
		bottom = 0,
		bottomColorIndex = 1,
		face = 1,
		faceColorIndex = 1,
		top = 0,
		topColorIndex = 1,
		gloves = 0,
		glovesColorIndex = 1,
		headgear = 0,
		headgearColorIndex = 1,
		footwear = 1,
		footwearColorIndex = 1,
		hairStyle = 1,
		hairStyleColorIndex = 1,
		beard = 0,
		beardColorIndex = 1,
	}
	local usedDefaults = true
	if self.styleAttributes ~= nil then
		usedDefaults = false
		for k, v in pairs(self.styleAttributes) do
			p[k] = v
		end
	end
	if p.onepiece ~= nil and p.onepiece > 0 then
		p.top = 0
		p.bottom = 0
		p.topColorIndex = 1
		p.bottomColorIndex = 1
	end
	IAprintDebug("_mergeSpawnStyleParams", "usedDefaults=" .. tostring(usedDefaults) .. " onepiece=" .. tostring(p.onepiece) .. " top=" .. tostring(p.top) .. " bottom=" .. tostring(p.bottom) .. " footwear=" .. tostring(p.footwear), self)
	return p
end

function IANeighbour:createNpcCompatStub()
	local neighbour = self
	local stub = {}
	stub.node = nil
	stub.name = self.name
	stub.title = self.name
	stub.playerGraphics = { style = nil }
	stub.isActive = false
	stub.lastUpdate = 0
	stub.mapHotspot = nil
	stub.spotRef = nil
	function stub:setSpot(spot)
		self.spotRef = spot
	end
	function stub:updateVisibility(_visible)
	end
	function stub:updatePosition()
		if self.node ~= nil and neighbour.realPositionX ~= nil and neighbour.realPositionZ ~= nil then
			local y = neighbour.realPositionY
			if y == nil then
				y = 0
			end
			setWorldTranslation(self.node, neighbour.realPositionX, y, neighbour.realPositionZ)
			setWorldRotation(self.node, 0, neighbour.realRotation or 0, 0)
		end
	end
	function stub:update(_dt)
		self.lastUpdate = g_currentMission.time
	end
	function stub:delete()
	end
	return stub
end

function IANeighbour:syncHumanModelWorldPose()
	local model = nil
	if self.humanCharacter ~= nil then
		model = self.humanCharacter:getModel()
	end
	if model == nil then
		model = self.humanModel
	end
	if model == nil or model.rootNode == nil then
		return
	end
	local x = self.realPositionX or self.positionX
	local z = self.realPositionZ or self.positionZ
	local y = self.realPositionY or self.positionY
	if x == nil or z == nil then
		return
	end
	if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
		y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 300, z)
	elseif y == nil then
		y = 0
	end
	local rot = self.realRotation or self.rotation or 0
	setWorldTranslation(model.rootNode, x, y, z)
	setWorldRotation(model.rootNode, 0, rot, 0)
	if self.npcInstance ~= nil then
		self.npcInstance.node = model.rootNode
	end
end

function IANeighbour:disposeHumanModel()
	self.humanModelSubtreeShowDeferred = false
	self.standingIdleRetryHost = nil
	self.standingIdleRetryAccumS = nil
	self.standingIdleRetryCount = nil
	self.humanModelStyleReady = false
	if self.humanCharacter ~= nil then
		self.humanCharacter:dispose()
		self.humanCharacter = nil
	end
	self.humanModel = nil
	self.resolvedPlayerStyle = nil
	if self.npcInstance ~= nil and self.npcInstance.playerGraphics ~= nil then
		self.npcInstance.playerGraphics.style = nil
	end
	if self.npcInstance ~= nil then
		self.npcInstance.node = nil
	end
end

function IANeighbour:finishHumanModelIdleSetup()
	local hc = self.humanCharacter
	if hc == nil then
		return
	end
	local female = self:_isFemaleGender()
	if not hc:tryStartStandingIdle(female) then
		self.standingIdleRetryHost = hc
		self.standingIdleRetryAccumS = 0
		self.standingIdleRetryCount = 0
	else
		self.standingIdleRetryHost = nil
	end
end

function IANeighbour.onHumanModelBaseLoaded(obj, loadingState)
	local self = obj
	if self == nil or self.isDeleted then
		IAprintDebug("onHumanModelBaseLoaded", "SKIP obj=nil or deleted")
		return
	end
	IAprintDebug("onHumanModelBaseLoaded", "loadingState=" .. tostring(loadingState) .. " hasStyleAttributes=" .. tostring(self.styleAttributes ~= nil) .. " styleApplied=" .. tostring(self.styleApplied), self)
	if loadingState ~= HumanModelLoadingState.OK then
		IAprintDebug("onHumanModelBaseLoaded", "FAILED state=" .. tostring(loadingState), self)
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbour: HumanModel base load failed state=" .. tostring(loadingState))
		end
		self:disposeHumanModel()
		return
	end
	local model = self.humanModel
	if model == nil then
		IAprintDebug("onHumanModelBaseLoaded", "model=nil", self)
		return
	end
	link(getRootNode(), model.rootNode)
	self:syncHumanModelWorldPose()
	-- Do NOT forceVisible here: the model has no style yet — loadFromStyleAsync
	-- below is async. Showing now flashes an unstyled/base-default character for
	-- up to ~800 ms until onHumanModelStyleLoaded completes.
	-- Visibility happens in onHumanModelStyleLoaded (style ready) or via the
	-- humanModelSubtreeShowDeferred path in update() (no-template fallback).
	IAprintDebug("onHumanModelBaseLoaded", "linked+posed, deferring visibility", self)
	local template = self:_styleTemplateForGender()
	if template == nil or not template.isConfigurationLoaded then
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbour: No PlayerStyle template — HumanModel unstyled")
		end
		self.resolvedPlayerStyle = nil
		self.humanModelStyleReady = true
		self:finishHumanModelIdleSetup()
		self.humanModelSubtreeShowDeferred = true
		if not self.fullLoaded then
			self:finishLoading()
		end
		return
	end
	local style = PlayerStyle.new()
	style:copyConfigurationFrom(template)
	applyPlayerStyleParamTable(style, self:_mergeSpawnStyleParams(), "--- IANeighbour:spawnStyle id=" .. tostring(self.id))
	self.resolvedPlayerStyle = style
	if self.npcInstance ~= nil then
		self.npcInstance.playerGraphics.style = style
	end
	model:loadFromStyleAsync(style, IANeighbour.onHumanModelStyleLoaded, self)
end

function IANeighbour.onHumanModelStyleLoaded(obj, loadingState)
	local self = obj
	if self == nil or self.isDeleted or self.humanModel == nil then
		IAprintDebug("onHumanModelStyleLoaded", "SKIP obj=nil/deleted/noModel")
		return
	end
	IAprintDebug("onHumanModelStyleLoaded", "loadingState=" .. tostring(loadingState) .. " fullLoaded=" .. tostring(self.fullLoaded), self)
	if loadingState ~= HumanModelLoadingState.OK then
		-- loadingState=2: redundant style reload from update() while model busy.
		-- Do NOT forceVisible — the real clothing meshes haven't loaded yet.
		-- Just set styleApplied=true to block update() from triggering another reload.
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbour: loadFromStyleAsync warning state=" .. tostring(loadingState))
		end
		self.styleApplied = true
		IAprintDebug("onHumanModelStyleLoaded", "state=" .. tostring(loadingState) .. " NOT OK, styleApplied=true, NOT forceVisible", self)
		return
	end
	-- loadingState == OK: style meshes are fully loaded. Now safe to show.
	IAprintDebug("onHumanModelStyleLoaded", "state=OK, forceVisible", self)
	if self.humanCharacter ~= nil then
		self.humanCharacter:forceVisible()
	end
	-- Hide immediately: the model must be force-visible for async style mesh
	-- consistency, but the situation decides whether the NPC should actually be
	-- rendered.  hideNPC moves the rootNode to Y=-10000 and sets isActive=false.
	self:hideNPC()
	self.humanModelStyleReady = true
	-- Mark style as applied so a later updateFromXML → update() → updateStyle() path
	-- (which sets styleAttributes again and triggers a redundant reload) returns early.
	self.styleApplied = true
	self:finishHumanModelIdleSetup()
	self.humanModelSubtreeShowDeferred = true
	if not self.fullLoaded then
		self:finishLoading()
	end
	IAprintDebug("onHumanModelStyleLoaded", "DONE fullLoaded=" .. tostring(self.fullLoaded) .. " styleApplied=" .. tostring(self.styleApplied), self)
end

function IANeighbour.onHumanModelStyleReloaded(obj, loadingState)
	IANeighbour.onHumanModelStyleLoaded(obj, loadingState)
end

function IANeighbour:reloadHumanModelStyleAsync()
	local model = self.humanCharacter ~= nil and self.humanCharacter:getModel() or self.humanModel
	if model == nil or self.resolvedPlayerStyle == nil then
		return
	end
	model:loadFromStyleAsync(self.resolvedPlayerStyle, IANeighbour.onHumanModelStyleReloaded, self)
end

function IANeighbour:beginHumanModelSpawn()
	IAprintDebug("beginHumanModelSpawn", "hasStyleAttributes=" .. tostring(self.styleAttributes ~= nil), self)
	self:disposeHumanModel()
	if IANeighbours ~= nil then
		IANeighbours.initPlayerStyleTemplates()
	end
	local xmlPath = self:_playerCharacterXmlPath()
	local model = HumanModel.new()
	model.initIKChains = false
	self.humanModel = model
	self.humanCharacter = IAHumanCharacter.forHumanModel(model)
	model:load(xmlPath, false, false, true, IANeighbour.onHumanModelBaseLoaded, self)
end

--- World node for spatial audio / compatibility with conversation code paths.
function IANeighbour:getCharacterWorldNode()
	if self.npcInstance ~= nil and self.npcInstance.node ~= nil then
		return self.npcInstance.node
	end
	return nil
end

--- PlayerStyle shared by standing character and vehicle cabin clone.
function IANeighbour:getResolvedPlayerStyle()
	return self.resolvedPlayerStyle
end

--- Standing character usable by situations (HumanModel + style async complete).
function IANeighbour:isStandingCharacterReady()
	local m = self.humanCharacter ~= nil and self.humanCharacter:getModel() or self.humanModel
	return self.fullLoaded == true and m ~= nil and self.humanModelStyleReady == true
end

-- Initialize the neighbour (spawn vehicle if enabled)
function IANeighbour:initialize()
	if self.initialized then
		if IANeighbours.debug then
			print("--- IANeighbour:initialize() - Neighbour "..self.name.." already initialized")
		end
		return
	end
	
	if not self.enabled then
		if IANeighbours.debug then
			print("--- IANeighbour:initialize() - Neighbour "..self.name.." is disabled")
		end
		if self.dynamicConversationData ~= nil then
			self.dynamicConversationData:initialize()
		end
		self.initialized = true
		return
	end
	
	-- Spawn the vehicle
	IAprintDebug("initialize", "hasStyleAttributes=" .. tostring(self.styleAttributes ~= nil) .. " gender=" .. tostring(self.gender), self)
	if IANeighbours.debug then
		print("--- IANeighbour:initialize() - Initializing neighbour: "..self.name)
	end

	self.npcInstance = self:createNpcCompatStub()
	self.npcInstance.name = self.name
	self.npcInstance.title = self.name
	self:beginHumanModelSpawn()

	if IANeighbours.debug then
		print("--- IANeighbour:initialize() - HumanModel spawn started id=" .. tostring(self.id))
	end

	self:tryAutoAssignHomebasePlacesIfNeeded()
	self:tryAutoAssignWorkplacePlacesIfNeeded()

	if self.dynamicConversationData ~= nil then
		self.dynamicConversationData:initialize()
	end

	self.initialized = true
end

--- Prefer outbound/savegame homebases when valid in places; else neighbourHomebaseAssignments from map XML (loadMapConfiguration); else random unassigned slots.
-- Call after deferred map places bootstrap when places were empty at initialize().
function IANeighbour:tryAutoAssignHomebasePlacesIfNeeded()
	if not self.enabled then
		return
	end
	local ianeighbours = self.ianeighbours
	if ianeighbours == nil or ianeighbours.gameLoopHelper == nil then
		return
	end
	local helper = ianeighbours.gameLoopHelper
	if helper:neighbourHasHomebasePlace(self) then
		return
	end
	local pending = ianeighbours.mapConfigNeighbourHomebaseAssignments
	if pending ~= nil and self.id ~= nil then
		local fromMap = pending[self.id]
		if fromMap ~= nil and #fromMap > 0 then
			self.assignedHomebasePlaceIds = {}
			for i = 1, #fromMap do
				self.assignedHomebasePlaceIds[i] = fromMap[i]
			end
		end
	end
	if helper:neighbourHasHomebasePlace(self) then
		return
	end
	self.assignedHomebasePlaceIds = {}
	local unassigned = helper:getUnassignedHomebasePlaces()
	local toAssign = helper:selectHomebasesForNeighbour(unassigned)
	for _, place in ipairs(toAssign) do
		table.insert(self.assignedHomebasePlaceIds, place.id)
	end
	if #toAssign > 0 then
		iaPersistNeighbourAssignmentsToMapConfig(ianeighbours, "IANeighbour:tryAutoAssignHomebasePlacesIfNeeded id=" .. tostring(self.id) .. " assignedCount=" .. tostring(#toAssign))
	end
end

--- Prefer outbound/savegame workplaces when valid in places; else neighbourWorkplaceAssignments from map XML (loadMapConfiguration); else job-matched unassigned pool.
-- Must consume map pending here (same order as homebase): initialize() runs before IAXMLHelper:applyMapConfigNeighbourWorkplaceAssignments in loadData().
function IANeighbour:tryAutoAssignWorkplacePlacesIfNeeded()
	if not self.enabled then
		return
	end
	local ianeighbours = self.ianeighbours
	if ianeighbours == nil or ianeighbours.gameLoopHelper == nil then
		return
	end
	local helper = ianeighbours.gameLoopHelper
	if helper:neighbourHasWorkplacePlace(self) then
		return
	end
	local pending = ianeighbours.mapConfigNeighbourWorkplaceAssignments
	if pending ~= nil and self.id ~= nil then
		local fromMap = pending[self.id]
		if fromMap ~= nil and #fromMap > 0 then
			self.assignedWorkplacePlaceIds = {}
			for i = 1, #fromMap do
				self.assignedWorkplacePlaceIds[i] = fromMap[i]
			end
		end
	end
	if helper:neighbourHasWorkplacePlace(self) then
		return
	end
	self.assignedWorkplacePlaceIds = {}
	local unassigned = helper:getUnassignedWorkplacePlaces()
	local toAssign = helper:selectWorkplacesForNeighbour(self, unassigned)
	for _, place in ipairs(toAssign) do
		table.insert(self.assignedWorkplacePlaceIds, place.id)
	end
	if #toAssign > 0 then
		iaPersistNeighbourAssignmentsToMapConfig(ianeighbours, "IANeighbour:tryAutoAssignWorkplacePlacesIfNeeded id=" .. tostring(self.id) .. " assignedCount=" .. tostring(#toAssign))
	end
end


-- Update the neighbour (only if already initialized)
function IANeighbour:update(dt,gameSeconds,game5Seconds)
	if not self.initialized then
		return
	end

	if self.dynamicConversationData ~= nil then
		self.dynamicConversationData:update(dt)
	end

	if self.scoreSample ~= nil and not isSamplePlaying(self.scoreSample) then
		delete(self.scoreSample)
		self.scoreSample = nil
	end

	--print("--- IANeighbourVehicle:LOOP() - NPC Instance: "..tostring(self.npcInstance))
	if self.npcInstance ~= nil then
		if self.humanModelSubtreeShowDeferred then
			self.humanModelSubtreeShowDeferred = false
			if self.humanCharacter ~= nil and self.humanCharacter:getModel() ~= nil then
				self.humanCharacter:forceVisible()
			end
			-- See onHumanModelStyleLoaded: force-visible for mesh consistency,
			-- then immediately hide so the enforcement decides actual visibility.
			self:hideNPC()
		end
		if self.standingIdleRetryHost ~= nil then
			self.standingIdleRetryAccumS = (self.standingIdleRetryAccumS or 0) + dt / 1000
			if self.standingIdleRetryAccumS >= 0.5 then
				self.standingIdleRetryAccumS = 0
				self.standingIdleRetryCount = (self.standingIdleRetryCount or 0) + 1
				local hc = self.standingIdleRetryHost
				if hc == nil or hc:getModel() == nil then
					self.standingIdleRetryHost = nil
				elseif self.standingIdleRetryCount <= 20 then
					if hc:tryStartStandingIdle(self:_isFemaleGender()) then
						self.standingIdleRetryHost = nil
					end
				else
					self.standingIdleRetryHost = nil
				end
			end
		end
		-- Apply style attributes once HumanModel style exists (skip live apply when reset until next savegame load)
		if self.styleAttributes ~= nil and not self.suppressNpcStyleApplicationUntilSavegameLoad and self.resolvedPlayerStyle ~= nil then
			IAprintDebug("update", "calling updateStyle (styleApplied=" .. tostring(self.styleApplied) .. ")", self)
			self:updateStyle(
				self.styleAttributes.hathair,
				self.styleAttributes.glasses,
				self.styleAttributes.glassesColorIndex,
				self.styleAttributes.facegear,
				self.styleAttributes.facegearColorIndex,
				self.styleAttributes.onepiece,
				self.styleAttributes.onepieceColorIndex,
				self.styleAttributes.bottom,
				self.styleAttributes.bottomColorIndex,
				self.styleAttributes.face,
				self.styleAttributes.faceColorIndex,
				self.styleAttributes.top,
				self.styleAttributes.topColorIndex,
				self.styleAttributes.gloves,
				self.styleAttributes.glovesColorIndex,
				self.styleAttributes.headgear,
				self.styleAttributes.headgearColorIndex,
				self.styleAttributes.footwear,
				self.styleAttributes.footwearColorIndex,
				self.styleAttributes.hairStyle,
				self.styleAttributes.hairStyleColorIndex,
				self.styleAttributes.beard,
				self.styleAttributes.beardColorIndex
			)
			self.styleAttributes = nil
		end

		if self.fullLoaded then
			--print("--- IANeighbour:update() "..self.name.." - NPC is full loaded")
			-- Remove activatable and interaction trigger node to prevent interaction notice (keybind info)
			--if self.npcInstance.activatable ~= nil then
				--self.npcInstance.activatable = nil
				--self.npcInstance.interactionTriggerNode = nil
			--end
			
			-- handleActiveSituation: XML/first-run init every frame; expiration + new scenario only on IANeighbours 5s tick
			self:handleActiveSituation(dt, game5Seconds)
			
			--print("--- IANeighbour:update() "..self.name.." - Updating active situation: "..tostring(self.activeSituation ~= nil))
			-- Update active situation if it exists
			if self.activeSituation ~= nil then
				--print("--- IANeighbour:update() "..self.name.." - Updating Situation: "..tostring(self.activeSituation.id))
				self.activeSituation:update(dt,gameSeconds,game5Seconds)
				-- Bidirectional NPC visibility enforcement: show or hide based on situation state.
				-- Handles the race where showNPC() fails silently during async model loading
				-- by retrying once the human model is ready.
				if self.activeSituation ~= nil then
					local vis = self.activeSituation.characterVisibility
					local shouldBeVisible = (vis == "yes" or self.activeSituation.npcVisibleWhilePaused == true)
					local isVisible = self:isNpcActuallyVisible()
					if shouldBeVisible then
						if not isVisible and self:isNpcReadyToShow() then
							self:showNPC()
						end
					else
						-- Always call hideNPC when the NPC should not be visible.
						-- Loading calls forceVisible (async style mesh fix) which
						-- makes the model visible; hideNPC puts it at Y=-10000.
						-- managePositioning→updateNPCPosition moves it back every
						-- ~5s, so we re-hide here. hideNPC is idempotent.
						self:hideNPC()
					end
				end
			end

		end

	end

	
	
	
	--print("--- IANeighbour:update() - g_localPlayer: "..tostring(g_localPlayer))
	-- Measure distance from neighbour to player

	self.distanceToPlayer = distanceToPlayer(self.realPositionX, self.realPositionY, self.realPositionZ)
	
	--print("--- IANeighbour:update() - vehicles: "..tostring(self.vehicles))
	--printObj(self.vehicles,1,"self.vehicles")
	for _, vehicle in pairs(self.vehicles) do
	--	print("--- IANeighbour:update() - vehicle".._..": "..tostring(vehicle))
	--	printObj(vehicle,1,"vehicle")
		vehicle:update(dt,gameSeconds)
	end

	--if self._iaPostSituationHomebaseTimerMs ~= nil then
	--	self._iaPostSituationHomebaseTimerMs = self._iaPostSituationHomebaseTimerMs - (dt or 0)
	--	if self._iaPostSituationHomebaseTimerMs <= 0 then
	--		self._iaPostSituationHomebaseTimerMs = nil
	--		local mi = g_currentMission and g_currentMission.missionInfo
	--		local ts = mi ~= nil and mi.timeScale or 1
	--		if self.activeSituation == nil and (ts == nil or ts <= 500) then
	--			local helper = self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper or nil
	--			if helper ~= nil and type(helper.spawnNonSituationVehiclesToHomebase) == "function" then
	--				pcall(function()
	--					helper:spawnNonSituationVehiclesToHomebase(self, nil)
	--				end)
	--			end
	--		end
	--	end
	--end

	-- Briefly re-apply pose after on-foot show only (cab snap). Every-frame updatePosition() resets rotation and fights look-at (wobble).
	if self.fullLoaded and self.npcInstance ~= nil and self.activeSituation ~= nil and self.activeSituation.npcVisibleWhilePaused
		and (self.activeSituation.npcPostShowPoseSyncFrames or 0) > 0
		and self.npcInstance.isActive and self.npcInstance.updatePosition then
		self.npcInstance:updatePosition()
		self.activeSituation.npcPostShowPoseSyncFrames = self.activeSituation.npcPostShowPoseSyncFrames - 1
	end

	local ih = self.ianeighbours
	if ih ~= nil and ih.gameLoopHelper ~= nil then
		-- Throttle contract evaluation stack: avoid per-frame schedule/field checks.
		-- Runs at most every 30s per neighbour (dt is ms). Reduced to 1s when a test
		-- is active so waitForNaturalContractCall doesn't race with the 30s window.
		local evalIntervalMs = (IATestRunner ~= nil and IATestRunner._testActive) and 1000 or 30000
		self._iaContractEvalTimerMs = (self._iaContractEvalTimerMs or evalIntervalMs) + (dt or 0)
		if self._iaContractEvalTimerMs >= evalIntervalMs then
			self._iaContractEvalTimerMs = 0
			if type(ih.gameLoopHelper.evaluateContractPlayerCallTrigger) == "function" then
				ih.gameLoopHelper:evaluateContractPlayerCallTrigger(self)
			end
			if type(ih.gameLoopHelper.evaluateContractFallbackToAiAt1500) == "function" then
				ih.gameLoopHelper:evaluateContractFallbackToAiAt1500(self)
			end
		end
	end

	-- Periodic fleet drift cleanup: ensures off-duty vehicles (not borrowed, not in
	-- active situation, AI/player not driving) are physically at their desired
	-- homebase pose. Repairs orphan attachments left visible on a field after a
	-- large-timeScale day-skip that completed fieldwork while
	-- IANeighbour:handleActiveSituation was suspended (the normal teardown
	-- reconcile never fired, so presence reports "homebase/visible" but the unit
	-- still sits on the field with collision).
	--
	-- Suppressed while timeScale > 500 because handleActiveSituation itself is
	-- suspended in that window and a teardown is potentially mid-flight; we run
	-- after the player returns to normal time, which is exactly when the stuck
	-- attachment would otherwise be noticed.
	if self.fullLoaded == true
		and IAEquipmentPresence ~= nil
		and IAEquipmentPresence.Reconcile ~= nil
		and type(IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet) == "function" then
		self._iaFleetDriftCleanupTimerMs = (self._iaFleetDriftCleanupTimerMs or 0) + (dt or 0)
		if self._iaFleetDriftCleanupTimerMs >= 60000 then
			self._iaFleetDriftCleanupTimerMs = 0
			local mi = g_currentMission and g_currentMission.missionInfo
			local ts = mi ~= nil and mi.timeScale or 1
			if ts == nil or ts <= 500 then
				pcall(function()
					IAEquipmentPresence.Reconcile.cleanupDriftedNeighbourFleet(self)
				end)
			end
		end
	end

	-- After vehicles + pose sync: rotate visible NPC toward player (runs last so it wins over updateNPCPosition this frame).
	self:updateNPCLookAtPlayer(dt)

	if self.fullLoaded and self.enabled then
		self:updateMapHotspot()
	end
end
-- Get the next scenario data (config, place, vehicle) for this neighbour
-- @return table|nil - Table with keys: config (IASituationConfig), place (IAMapPlace), vehicle (IANeighbourVehicle), or nil if generation failed
function IANeighbour:getNextSituation()
	if IANeighbours.gameLoopHelper == nil then
		if IANeighbours.debug then
			print("--- IANeighbour:getNextSituation() - GameLoopHelper is not initialized")
		end
		return nil
	end
	
	local scenarioData = IANeighbours.gameLoopHelper:generateNewSituation(self)
	
	if scenarioData == nil then
		if IANeighbours.debug then
			--print("--- IANeighbour:handleActiveSituation() - No scenario data generated")
		end
		return
	end

	local okScenario, scenarioErr = IANeighbours.gameLoopHelper:validateScenarioFleetVehicles(scenarioData)
	if not okScenario then
		if IANeighbours.debug then
			print("--- IANeighbour:getNextSituation() - " .. tostring(scenarioErr) .. " for neighbour=" .. tostring(self.name))
		end
		return nil
	end

	-- Readiness gate:
	-- Only start creating an IASituation once all vehicles that would be used by this scenario are fully loaded.
	-- This prevents situations (and their side effects like homebase vehicle placement) from starting while vehicles are still spawning/loading.
	local function isVehicleReady(ia_vehicle)
		-- nil = scenario doesn't use this vehicle
		if ia_vehicle == nil then
			return true
		end
		if not IANeighbours.gameLoopHelper:isFleetVehicleAvailableForSituation(ia_vehicle) then
			return false
		end
		-- Require both wrapper fullLoaded and an actual game vehicle object.
		-- This ensures "initialize" doesn't run while the vehicle is still loading/spawn-in-progress.
		return ia_vehicle.fullLoaded == true and ia_vehicle.vehicle ~= nil and ia_vehicle.vehicle.rootNode ~= nil
	end

	-- vehicles=Force means a main vehicle must exist (otherwise we would create the situation with no car yet).
	local vehiclesMode = scenarioData.config and scenarioData.config.vehicles or nil
	local requiresMainVehicle = vehiclesMode ~= nil and string.lower(tostring(vehiclesMode)) == "force"
	if requiresMainVehicle and scenarioData.vehicle == nil then
		if IANeighbours.debug then
			print("--- IANeighbour:getNextSituation() - Waiting for main vehicle (Force) to be available for neighbour=" .. tostring(self.name))
		end
		return nil
	end

	if not isVehicleReady(scenarioData.vehicle) or not isVehicleReady(scenarioData.attachmentBack) or not isVehicleReady(scenarioData.attachmentFront) then
		if IANeighbours.debug then
			print("--- IANeighbour:getNextSituation() - Waiting for vehicles (fullLoaded or borrowed) for neighbour=" .. tostring(self.name))
		end
		return nil
	end

	-- Set the active situation ID if a config was generated (only after readiness gate passed)
	if scenarioData ~= nil and scenarioData.config ~= nil then
		self.activeSituationId = scenarioData.config.id
	end
	
	-- Create and initialize the situation (optional 10th param: seedFruitTypeIndex override for SEED fieldwork)
	local scenario = IASituation.new(scenarioData.config, self, scenarioData.place, scenarioData.vehicle, scenarioData.farmlandId, scenarioData.attachmentBack, scenarioData.attachmentFront, scenarioData.jobType, false, scenarioData.seedFruitTypeIndex)
	
	return scenario
end

-- Add a situation to the history before it's deleted
-- @param IASituation situation - The situation to add to history
function IANeighbour:addSituationToHistory(situation)
	if situation == nil then
		return
	end
	
	-- Create situation data structure
	local situationData = {
		situationId = situation.id,
		placeId = nil,
		vehicleIds = {},
		startedAt = nil
	}
	
	-- Get place id if available
	if situation.place ~= nil and situation.place.id ~= nil then
		situationData.placeId = situation.place.id
	end
	
	-- Get vehicle ids if available
	if situation.vehicle ~= nil and situation.vehicle.uniqueId ~= nil then
		table.insert(situationData.vehicleIds, tostring(situation.vehicle.uniqueId))
	end
	if situation.attachmentBack ~= nil and situation.attachmentBack.uniqueId ~= nil then
		table.insert(situationData.vehicleIds, tostring(situation.attachmentBack.uniqueId))
	end
	if situation.attachmentFront ~= nil and situation.attachmentFront.uniqueId ~= nil then
		table.insert(situationData.vehicleIds, tostring(situation.attachmentFront.uniqueId))
	end
	
	-- Get startedAt if available
	if situation.startedAt ~= nil then
		situationData.startedAt = situation.startedAt
	end
	
	-- Add to history
	table.insert(self.situationHistory, situationData)
	
	-- Keep only the last 100 situations (remove oldest if count exceeds 100)
	local maxHistorySize = 100
	if #self.situationHistory > maxHistorySize then
		-- Remove items from the beginning until we have only maxHistorySize items
		while #self.situationHistory > maxHistorySize do
			table.remove(self.situationHistory, 1)  -- Remove oldest item (first in array)
		end
		if IANeighbours.debug then
			print("--- IANeighbour:addSituationToHistory() - Trimmed situation history to "..tostring(maxHistorySize).." items")
		end
	end
end

-- Get the last occurrence time (startedAt) of a specific situation for this neighbour
-- @param string situationId - The situation ID to search for
-- @return number|nil - The startedAt value (in game hours) of the most recent occurrence, or nil if not found
function IANeighbour:getLastSituationOccurence(situationId)
	if situationId == nil or self.situationHistory == nil or #self.situationHistory == 0 then
		return nil
	end
	
	-- Search history backwards (most recent first) to find the last occurrence
	for i = #self.situationHistory, 1, -1 do
		local historyItem = self.situationHistory[i]
		if historyItem ~= nil and historyItem.situationId ~= nil and tostring(historyItem.situationId) == tostring(situationId) then
			return historyItem.startedAt
		end
	end
	
	return nil
end

-- Handle active situation: check for XML restoration on first run; expiration and new scenarios only every 5s (IANeighbours game5Seconds tick)
-- @param number dt - Delta time
-- @param boolean game5Seconds - True on the once-per-~5s tick from IANeighbours:update
function IANeighbour:handleActiveSituation(dt, game5Seconds)
	-- First Run Check: Initialize situation loaded from XML if not yet initialized
	if not self.situationInitialized then
		if self.activeSituation ~= nil and not self.activeSituation.initialized then
			-- Readiness gate for XML-restored situations:
			-- If the situation requires a vehicle (config.vehicles == "Force"), delay initialization until
			-- all relevant IANeighbourVehicle objects are fully loaded (fullLoaded == true).
			local function isVehicleReady(ia_vehicle)
				-- nil = scenario doesn't use this vehicle slot
				if ia_vehicle == nil then
					return true
				end
				if IANeighbours.gameLoopHelper ~= nil and not IANeighbours.gameLoopHelper:isFleetVehicleAvailableForSituation(ia_vehicle) then
					return false
				end
				return ia_vehicle.fullLoaded == true
			end
			local vehiclesMode = (self.activeSituation.config and self.activeSituation.config.vehicles) or nil
			local requiresVehicle = vehiclesMode ~= nil and string.lower(tostring(vehiclesMode)) == "force"
			if requiresVehicle then
				if not isVehicleReady(self.activeSituation.vehicle) or not isVehicleReady(self.activeSituation.attachmentBack) or not isVehicleReady(self.activeSituation.attachmentFront) then
					if IANeighbours.debug then
						print("--- IANeighbour:handleActiveSituation() - Waiting for vehicles (XML restore; fullLoaded or borrowed) for neighbour=" .. tostring(self.name) .. ", situation=" .. tostring(self.activeSituation.id))
					end
					return
				end
			end

			if IANeighbours.debug then
				print("--- IANeighbour:handleActiveSituation() - Initializing situation loaded from XML: "..tostring(self.activeSituation.id))
			end
			self.activeSituation:initialize()
			self.situationInitialized = true
			return
		end
		-- Mark as initialized even if no situation was loaded
		if IANeighbours.debug then
			print("--- IANeighbour:handleActiveSituation() - Situation is not initialized, marking as initialized")
		end
		self.situationInitialized = true
	end

	if not game5Seconds then
		return
	end
	
	-- Expiration Check: Check if current situation has expired (player-nearby delay is handled inside isExpired)
	if self.activeSituation ~= nil then
		if self.activeSituation:isExpired() then
			if IANeighbours.debug then
				print("--- IANeighbour:handleActiveSituation() - Situation expired: "..tostring(self.activeSituation.id))
			end

			-- Teardown (history, onExpired, AI stop, fieldwork completion, fleet reconcile, …) is centralized in IASituation:delete()
			self.activeSituation:delete()
			self.activeSituation = nil
			self.activeSituationId = nil
			self._iaPostSituationHomebaseTimerMs = 1500
		else
			--print("--- IANeighbour:handleActiveSituation() - Situation is still active, no need to create a new one")
			-- Situation is still active, no need to create a new one
			return
		end
	end
	
	-- New Situation Creation: Create new situation if none exists
	if self.activeSituation == nil then
		--print("--- IANeighbour:handleActiveSituation() - Creating new situation")
		local scenario = self:getNextSituation()
		
		if scenario == nil then
			if IANeighbours.debug then
				--print("--- IANeighbour:handleActiveSituation() - No scenario data generated")
			end
			return
		end
		
		-- Create and initialize the situation
		self.activeSituation = scenario
		self.activeSituationId = scenario.config.id
		if IANeighbours.debug then
			print("--- IANeighbour:handleActiveSituation() - Initializing Situation: "..tostring(self.activeSituation.id))
		end
		self.activeSituation:initialize()
		-- Spawn non-situation vehicles/attachments to character homebase places; on foot: place last used vehicle at nearby public_place
		if self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper ~= nil then
			self.ianeighbours.gameLoopHelper:spawnNonSituationVehiclesToHomebase(self, scenario)
		end
	end
end

--- Replace the active situation with a new fieldwork situation immediately (developer console).
-- Ignores time-of-day and normal "farmer + history" fieldwork gating; still uses selectNewFieldwork (fields, configs, vehicles).
-- @return boolean ok, string|nil errorMessage
function IANeighbour:forceNewFieldworkSituation()
	if not self.enabled then
		return false, "neighbour disabled"
	end
	if IANeighbours.gameLoopHelper == nil then
		return false, "gameLoopHelper not ready"
	end
	if not IANeighbours.gameLoopHelper:neighbourHasHomebasePlace(self) then
		return false, "no homebase place"
	end

	if self.activeSituation ~= nil then
		self.activeSituation:delete()
		if self.activeSituation ~= nil then
			self.activeSituation = nil
			self.activeSituationId = nil
		end
	end

	local scenarioData, genErr = IANeighbours.gameLoopHelper:generateForcedFieldworkSituation(self)
	if scenarioData == nil then
		return false, genErr or "no matching fieldwork (farmlands, situation XML, or vehicles borrowed)"
	end

	local okScenario, scenarioErr = IANeighbours.gameLoopHelper:validateScenarioFleetVehicles(scenarioData)
	if not okScenario then
		return false, scenarioErr or "required fleet vehicle borrowed by player"
	end

	local function isVehicleReady(ia_vehicle)
		if ia_vehicle == nil then
			return true
		end
		if not IANeighbours.gameLoopHelper:isFleetVehicleAvailableForSituation(ia_vehicle) then
			return false
		end
		return ia_vehicle.fullLoaded == true and ia_vehicle.vehicle ~= nil and ia_vehicle.vehicle.rootNode ~= nil
	end
	local vehiclesMode = scenarioData.config and scenarioData.config.vehicles or nil
	local requiresMainVehicle = vehiclesMode ~= nil and string.lower(tostring(vehiclesMode)) == "force"
	if requiresMainVehicle and scenarioData.vehicle == nil then
		return false, "config requires main vehicle (Force) but none available (borrowed or missing)"
	end
	if not isVehicleReady(scenarioData.vehicle) or not isVehicleReady(scenarioData.attachmentBack) or not isVehicleReady(scenarioData.attachmentFront) then
		return false, "vehicles not fully loaded or borrowed (wait and retry)"
	end

	local scenario = IASituation.new(scenarioData.config, self, scenarioData.place, scenarioData.vehicle, scenarioData.farmlandId, scenarioData.attachmentBack, scenarioData.attachmentFront, scenarioData.jobType, false, scenarioData.seedFruitTypeIndex)
	self.activeSituation = scenario
	self.activeSituationId = scenario.config ~= nil and scenario.config.id or nil
	self.situationInitialized = true
	self.activeSituation:initialize()
	if self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper ~= nil then
		self.ianeighbours.gameLoopHelper:spawnNonSituationVehiclesToHomebase(self, scenario)
	end
	if IAHelper_teleportLocalPlayerToWorldXZ ~= nil then
		local tx, tz = nil, nil
		if scenarioData.place ~= nil then
			tx, tz = scenarioData.place.x, scenarioData.place.z
		end
		if scenario.farmland ~= nil and scenario.farmland.field ~= nil then
			local field = scenario.farmland.field
			if type(field.getCenterOfFieldWorldPosition) == "function" then
				local cx, cz = field:getCenterOfFieldWorldPosition()
				if cx ~= nil and cz ~= nil then
					tx, tz = cx, cz
				end
			elseif field.posX ~= nil and field.posZ ~= nil then
				tx, tz = field.posX, field.posZ
			end
		end
		IAHelper_teleportLocalPlayerToWorldXZ(tx, tz)
	end
	return true, nil
end

--- Replace the active situation with a specific situation id (developer console).
-- Uses generateForcedSituation (eligibility rules only; skips random pick, first-relax, and time-of-day farmer gating).
-- @param string|number situationId
-- @return boolean ok, string|nil errorMessage
function IANeighbour:forceNewSituation(situationId, forceVisible)
	if not self.enabled then
		return false, "neighbour disabled"
	end
	if IANeighbours.gameLoopHelper == nil then
		return false, "gameLoopHelper not ready"
	end
	if situationId == nil or tostring(situationId) == "" then
		return false, "situation id required"
	end

	if self.activeSituation ~= nil then
		self.activeSituation:delete()
		if self.activeSituation ~= nil then
			self.activeSituation = nil
			self.activeSituationId = nil
		end
	end

	local scenarioData, genErr = IANeighbours.gameLoopHelper:generateForcedSituation(self, situationId)
	if scenarioData == nil then
		return false, genErr or "could not generate forced situation"
	end

	local okScenario, scenarioErr = IANeighbours.gameLoopHelper:validateScenarioFleetVehicles(scenarioData)
	if not okScenario then
		return false, scenarioErr or "required fleet vehicle borrowed by player"
	end

	local function isVehicleReady(ia_vehicle)
		if ia_vehicle == nil then
			return true
		end
		if not IANeighbours.gameLoopHelper:isFleetVehicleAvailableForSituation(ia_vehicle) then
			return false
		end
		return ia_vehicle.fullLoaded == true and ia_vehicle.vehicle ~= nil and ia_vehicle.vehicle.rootNode ~= nil
	end
	local vehiclesMode = scenarioData.config and scenarioData.config.vehicles or nil
	local requiresMainVehicle = vehiclesMode ~= nil and string.lower(tostring(vehiclesMode)) == "force"
	if requiresMainVehicle and scenarioData.vehicle == nil then
		return false, "config requires main vehicle (Force) but none available (borrowed or missing)"
	end
	if not isVehicleReady(scenarioData.vehicle) or not isVehicleReady(scenarioData.attachmentBack) or not isVehicleReady(scenarioData.attachmentFront) then
		return false, "vehicles not fully loaded or borrowed (wait and retry)"
	end

	local scenario = IASituation.new(scenarioData.config, self, scenarioData.place, scenarioData.vehicle, scenarioData.farmlandId, scenarioData.attachmentBack, scenarioData.attachmentFront, scenarioData.jobType, false, scenarioData.seedFruitTypeIndex)
	self.activeSituation = scenario
	self.activeSituationId = scenario.config ~= nil and scenario.config.id or nil
	self.situationInitialized = true
	self.activeSituation:initialize()
	-- Force NPC visibility if requested (used by test framework)
	if forceVisible == true then
		scenario.characterVisibility = "yes"
		self:showNPC()
	end
	if self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper ~= nil then
		self.ianeighbours.gameLoopHelper:spawnNonSituationVehiclesToHomebase(self, scenario)
	end
	if IAHelper_teleportLocalPlayerToWorldXZ ~= nil then
		local tx, tz = nil, nil
		if scenarioData.place ~= nil then
			tx, tz = scenarioData.place.x, scenarioData.place.z
		end
		if scenario.farmland ~= nil and scenario.farmland.field ~= nil then
			local field = scenario.farmland.field
			if type(field.getCenterOfFieldWorldPosition) == "function" then
				local cx, cz = field:getCenterOfFieldWorldPosition()
				if cx ~= nil and cz ~= nil then
					tx, tz = cx, cz
				end
			elseif field.posX ~= nil and field.posZ ~= nil then
				tx, tz = field.posX, field.posZ
			end
		end
		IAHelper_teleportLocalPlayerToWorldXZ(tx, tz)
	end
	return true, nil
end

function IANeighbour:finishLoading()
	self.fullLoaded = true
	-- Place non-situation vehicles on homebase (and on-foot: last used at public_place) after character is initialized,
	-- so vehicles are positioned before presence reconcile runs; otherwise they stay hidden.
	if self.ianeighbours ~= nil and self.ianeighbours.gameLoopHelper ~= nil then
		local scenario

		--TODO: Refactor this to use the new situation data structure
		if self.activeSituation ~= nil then
			scenario = {
				vehicle = self.activeSituation.vehicle,
				attachmentBack = self.activeSituation.attachmentBack,
				attachmentFront = self.activeSituation.attachmentFront,
				place = self.activeSituation.place,
				config = self.activeSituation.config
			}
		else
			scenario = { vehicle = nil, attachmentBack = nil, attachmentFront = nil, place = nil, config = nil }
		end
		self.ianeighbours.gameLoopHelper:spawnNonSituationVehiclesToHomebase(self, scenario)
	end
	self:updateMapHotspot()
end
function IANeighbour:showNPC()
	local npc = self.npcInstance
	local hm = self.humanCharacter ~= nil and self.humanCharacter:getModel() or self.humanModel
	local style = self.resolvedPlayerStyle
	if npc == nil or hm == nil or style == nil then
		IAprintDebug("showNPC", "BLOCKED: npc="..tostring(npc).." hm="..tostring(hm).." style="..tostring(style), self)
		return
	end
	if not self.humanModelStyleReady then
		IAprintDebug("showNPC", "BLOCKED: humanModelStyleReady=false", self)
		return
	end
	if not style.isConfigurationLoaded then
		IAprintDebug("showNPC", "BLOCKED: isConfigurationLoaded=false", self)
		return
	end
	if style.configs.face == nil or style.configs.face.selectedItemIndex == nil or style.configs.face.selectedItemIndex <= 0 then
		IAprintDebug("showNPC", "BLOCKED: face config missing/invalid (face="..tostring(style.configs.face).." selIdx="..tostring(style.configs.face and style.configs.face.selectedItemIndex)..")", self)
		return
	end
	if style.configs.face.items == nil or #style.configs.face.items == 0 then
		IAprintDebug("showNPC", "BLOCKED: face items empty", self)
		return
	end

	if self.humanCharacter ~= nil then
		self.humanCharacter:forceVisible()
	end
	self:syncHumanModelWorldPose()
	npc.isActive = true
	npc:updateVisibility(true)
	npc:updatePosition()
	self:updateNPCSpot()
	self:updateMapHotspot()

	IAprintDebug("showNPC", "Character visible", self)
end
function IANeighbour:hideNPC()
	local npc = self.npcInstance
	if npc == nil then
		return
	end
	if self.humanCharacter ~= nil then
		self.humanCharacter:setEngineVisibility(false)
	end
	npc.isActive = false
	npc:updateVisibility(false)
	if self.realPositionX ~= nil and self.realPositionZ ~= nil and npc.node ~= nil then
		setWorldTranslation(npc.node, self.realPositionX, IANeighbour.NPC_HIDDEN_Y, self.realPositionZ)
	end
end

--- Returns true if all prerequisites for showNPC() are met right now.
-- Must stay in sync with showNPC() guard clauses.
function IANeighbour:isNpcReadyToShow()
	if self.npcInstance == nil then return false end
	if self.humanCharacter == nil then return false end
	if self.humanCharacter:getModel() == nil then return false end
	if self.resolvedPlayerStyle == nil then return false end
	if not self.humanModelStyleReady then return false end
	if not self.resolvedPlayerStyle.isConfigurationLoaded then return false end
	if self.resolvedPlayerStyle.configs == nil then return false end
	if self.resolvedPlayerStyle.configs.face == nil then return false end
	if self.resolvedPlayerStyle.configs.face.selectedItemIndex == nil or self.resolvedPlayerStyle.configs.face.selectedItemIndex <= 0 then return false end
	if self.resolvedPlayerStyle.configs.face.items == nil or #self.resolvedPlayerStyle.configs.face.items == 0 then return false end
	return true
end

--- Returns true if the NPC is currently active and visible in the game world.
function IANeighbour:isNpcActuallyVisible()
	return self.npcInstance ~= nil and self.npcInstance.isActive
end

function IANeighbour:updateNPCPosition(targetX, targetY, targetZ, targetRotation)
	if targetX == nil or targetY == nil or targetZ == nil or targetRotation == nil then
		return
	end
	local function round1(v)
		if v == nil then
			return nil
		end
		return MathUtil.round(v, 1)
	end
	local realPositionX = round1(self.realPositionX)
	local realPositionY = round1(self.realPositionY)
	local realPositionZ = round1(self.realPositionZ)
	local realRotation = round1(self.realRotation)
	if realPositionX ~= targetX or realPositionY ~= targetY or realPositionZ ~= targetZ or realRotation ~= targetRotation then
		self.realPositionX = targetX
		self.realPositionY = targetY
		self.realPositionZ = targetZ
		self.realRotation = targetRotation
		if self.npcInstance ~= nil and IANeighbour.isFiniteCoords(targetX, targetY, targetZ) then
			self:syncHumanModelWorldPose()
			self:updateNPCSpot()
			self:updateMapHotspot()
		end
	end
end
function IANeighbour:updateNPCSpot(vehicle)
	local x, y, z = self.realPositionX, self.realPositionY, self.realPositionZ
	if vehicle ~= nil and vehicle.rootNode ~= nil then
		x, y, z = getWorldTranslation(vehicle.rootNode)
	end
	if not IANeighbour.isFiniteCoords(x, y, z) then
		if self.spot ~= nil then
			self.spot:delete()
			self.spot = nil
		end
		if self.npcInstance ~= nil and self.npcInstance.setSpot then
			self.npcInstance:setSpot(nil)
		end
		return
	end

	if self.spot ~= nil then
		self.spot:delete()
		self.spot = nil
	end
	local spot = NPCSpot.new()
	--	print("--- IANeighbour:initialize() - CREATE NPC Spot")
	--spot:setPosition(10,20,30)
	local createdspot = spot:create(self.npcInstance,x,y,z,0,3,0,true,"NPC_SPOT_"..self.id)
	createdspot.uniqueId = "NPC_SPOT_"..self.id
	createdspot.needsSaving = false
	--	printObj(createdspot,3,"createdspot")
	g_npcManager:addSpot(createdspot)
	self.npcInstance:setSpot(createdspot)
	self.spot = createdspot
end

-- Remove the NPC spot (e.g. when situation is completed).
function IANeighbour:removeNPCSpot()
	if self.spot ~= nil then
		self.spot:delete()
		self.spot = nil
	end
	if self.npcInstance ~= nil and self.npcInstance.setSpot then
		self.npcInstance:setSpot(nil)
	end
end

--- Resolved path to `images/<characterId>.dds` for the in-map detail panel; falls back if missing.
function IANeighbour:_characterPortraitImagePathForMap()
	local dir = IANeighbours and IANeighbours.dir
	if dir == nil or dir == "" then
		return ""
	end
	local idStr = self.id ~= nil and tostring(self.id) or "1"
	local path = Utils.getFilename("images/" .. idStr .. ".dds", dir)
	if fileExists(path) then
		return path
	end
	local fb = Utils.getFilename("images/mapicon.dds", dir)
	if fileExists(fb) then
		return fb
	end
	return Utils.getFilename("icon_FieldsOfStories.dds", dir)
end

--- Minimal placeable stand-in so InGameMenuMapFrame shows name + portrait (`getImageFilename`).
function IANeighbour:_createMapHotspotPlaceableProxy()
	local neighbour = self
	local farmId = self.farmId
	if farmId == nil and g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
		farmId = g_localPlayer.farmId
	end
	if farmId == nil then
		farmId = 1
	end
	return setmetatable({
		canBeSold = function()
			return false
		end,
		getName = function()
			if neighbour.npcInstance ~= nil and neighbour.npcInstance.name ~= nil then
				return tostring(neighbour.npcInstance.name)
			end
			return tostring(neighbour.name or "NPC")
		end,
		getImageFilename = function()
			return neighbour:_characterPortraitImagePathForMap()
		end,
		getDailyUpkeep = function()
			return 0
		end,
		getAge = function()
			return 0
		end,
		ownerFarmId = farmId,
		storeItem = nil,
		specializations = {},
	}, {
		__index = function(_, k)
			if type(k) == "string" and k:sub(1, 5) == "spec_" then
				return nil
			end
			return function()
				return nil
			end
		end,
	})
end

--- Engine NPC no longer supplies a map hotspot; create a PlaceableHotspot once coordinates exist.
function IANeighbour:ensureMapHotspotCreated()
	if self.isDeleted or not self.enabled then
		return
	end
	if self.mapHotspot ~= nil or PlaceableHotspot == nil or g_currentMission == nil then
		return
	end
	local worldX = self.realPositionX or self.positionX
	local worldZ = self.realPositionZ or self.positionZ
	if worldX == nil or worldZ == nil then
		return
	end
	if IANeighbours ~= nil and IANeighbours.registerNpcMapHotspotTexture ~= nil then
		IANeighbours.registerNpcMapHotspotTexture()
	end
	local sliceMain = IA_NPC_MAP_OVERLAY_SLICE
	local sliceSmall = IA_NPC_MAP_OVERLAY_SLICE_SMALL
	local pathSmallAtlas = IANeighbours ~= nil and IANeighbours.dir .. "textures/iaNpcMapHotspotSmall.xml" or nil
	if pathSmallAtlas == nil or not fileExists(pathSmallAtlas) then
		sliceSmall = sliceMain
	end
	local mainW, mainH = 40, 40
	local smallW, smallH = 15, 15
	if getNormalizedScreenValues ~= nil then
		mainW, mainH = getNormalizedScreenValues(40, 40)
		smallW, smallH = getNormalizedScreenValues(15, 15)
	end
	local mapHotspot = PlaceableHotspot.new()
	mapHotspot.isADMarker = true
	mapHotspot.iaFosNeighbourMarker = true
	mapHotspot.width, mapHotspot.height = mainW, mainH
	if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
		mapHotspot.icon = g_overlayManager:createOverlay(sliceMain, 0, 0, mainW, mainH)
		mapHotspot.iconSmall = g_overlayManager:createOverlay(sliceSmall, 0, 0, smallW, smallH)
	end
	-- No setTeleportWorldPosition: engine only offers "Visit" when a teleport target exists (GDN placeable hotspots).
	mapHotspot:setWorldPosition(worldX, worldZ)
	mapHotspot:setName(self.name or "NPC")
	if mapHotspot.setPlaceable ~= nil then
		pcall(function()
			mapHotspot:setPlaceable(self:_createMapHotspotPlaceableProxy())
		end)
		if g_overlayManager ~= nil and g_overlayManager.createOverlay ~= nil then
			mapHotspot.icon = g_overlayManager:createOverlay(sliceMain, 0, 0, mainW, mainH)
			mapHotspot.iconSmall = g_overlayManager:createOverlay(sliceSmall, 0, 0, smallW, smallH)
		end
	end
	if iaAddMapHotspotToMission(mapHotspot) then
		self.mapHotspot = mapHotspot
		if self.npcInstance ~= nil then
			self.npcInstance.mapHotspot = mapHotspot
		end
		IAprintDebug("IANeighbour:ensureMapHotspotCreated()", string.format(
			"[HOTSPOT] NPC mapHotspot CREATED name=%s wx=%.1f wz=%.1f", tostring(self.name), worldX, worldZ
		), self, nil, nil)
	elseif mapHotspot.delete ~= nil then
		IAprintDebug("IANeighbour:ensureMapHotspotCreated()", string.format(
			"[HOTSPOT] NPC mapHotspot create FAILED (iaAddMapHotspotToMission=false) name=%s -> deleting orphan",
			tostring(self.name)
		), self, nil, nil)
		mapHotspot:delete()
	end
end

-- Update map hotspot position. Optional vehicle: IANeighbourVehicle (uses realPositionX/Z) or game vehicle (uses rootNode). If nil, uses self.realPositionX/Z.
function IANeighbour:updateMapHotspot(vehicle)
	local worldX, worldZ = self.realPositionX, self.realPositionZ
	if vehicle ~= nil then
		if vehicle.realPositionX ~= nil and vehicle.realPositionZ ~= nil then
			worldX, worldZ = vehicle.realPositionX, vehicle.realPositionZ
		elseif vehicle.rootNode ~= nil then
			local x, _, z = getWorldTranslation(vehicle.rootNode)
			worldX, worldZ = x, z
		end
	end
	if worldX == nil or worldZ == nil then
		return
	end
	self:ensureMapHotspotCreated()
	if self.mapHotspot == nil then
		return
	end
	local lx, lz = self._iaMapHotspotLastX, self._iaMapHotspotLastZ
	if lx ~= nil and lz ~= nil and math.abs(lx - worldX) < 0.02 and math.abs(lz - worldZ) < 0.02 then
		return
	end
	self._iaMapHotspotLastX = worldX
	self._iaMapHotspotLastZ = worldZ
	if self.mapHotspot.setWorldPosition ~= nil then
		self.mapHotspot:setWorldPosition(worldX, worldZ)
	else
		self.mapHotspot.worldX = worldX
		self.mapHotspot.worldZ = worldZ
	end
end

function IANeighbour:updateNPCName(unavailable)
	if self.npcInstance == nil then
		return
	end
	if unavailable then
		local suffix = g_i18n:getText("ia_npc_unavailable")
		self.npcInstance.name = self.name .. suffix
		self.npcInstance.title = self.name .. suffix
	else
		self.npcInstance.name = self.name
		self.npcInstance.title = self.name
	end
	if self.mapHotspot ~= nil and self.mapHotspot.setName ~= nil then
		self.mapHotspot:setName(self.npcInstance.name)
	end
end
function IANeighbour:updateStyle(hathair,glasses,glassesColorIndex,facegear,facegearColorIndex,onepiece,onepieceColorIndex,bottom,bottomColorIndex,face,faceColorIndex,top,topColorIndex,gloves,glovesColorIndex,headgear,headgearColorIndex,footwear,footwearColorIndex,hairStyle,hairStyleColorIndex,beard,beardColorIndex)
	IAprintDebug("updateStyle", "styleApplied=" .. tostring(self.styleApplied) .. " onepiece=" .. tostring(onepiece) .. " top=" .. tostring(top) .. " bottom=" .. tostring(bottom), self)
	if self.styleApplied then
		IAprintDebug("updateStyle", "BLOCKED: styleApplied already true", self)
		return
	end

	local style = self.resolvedPlayerStyle
	if style == nil then
		IAprintDebug("updateStyle", "BLOCKED: resolvedPlayerStyle nil", self)
		return
	end

	if IANeighbours.debug then
		print("--- IANeighbour:updateStyle() "..self.id.." - Applying indices to PlayerStyle")
	end
	IAprintDebug("updateStyle", "applying params, will reload style async", self)

	local p = {
		hathair = hathair,
		glasses = glasses,
		glassesColorIndex = glassesColorIndex,
		facegear = facegear,
		facegearColorIndex = facegearColorIndex,
		onepiece = onepiece,
		onepieceColorIndex = onepieceColorIndex,
		bottom = bottom,
		bottomColorIndex = bottomColorIndex,
		face = face,
		faceColorIndex = faceColorIndex,
		top = top,
		topColorIndex = topColorIndex,
		gloves = gloves,
		glovesColorIndex = glovesColorIndex,
		headgear = headgear,
		headgearColorIndex = headgearColorIndex,
		footwear = footwear,
		footwearColorIndex = footwearColorIndex,
		hairStyle = hairStyle,
		hairStyleColorIndex = hairStyleColorIndex,
		beard = beard,
		beardColorIndex = beardColorIndex,
	}
	applyPlayerStyleParamTable(style, p, "--- IANeighbour:updateStyle() "..tostring(self.id))

	if self.npcInstance ~= nil and self.npcInstance.playerGraphics ~= nil then
		self.npcInstance.playerGraphics.style = style
	end

	self.styleApplied = true

	if self.humanCharacter ~= nil and self.humanCharacter:getModel() ~= nil then
		self:reloadHumanModelStyleAsync()
	end
end
function IANeighbour:getActiveVehicle()

	for _, ia_vehicle in pairs(self.vehicles) do
		if ia_vehicle.isActive then
			return ia_vehicle
		end
	end
	return nil
end

function IANeighbour:getVehicle(uniqueId)
	for _, ia_vehicle in pairs(self.vehicles) do
		if ia_vehicle.uniqueId == uniqueId then
			return ia_vehicle
		end
	end
	return nil
end

function IANeighbour:getVehicleByExternalId(externalId)
	if externalId == nil then
		return nil
	end
	for _, ia_vehicle in pairs(self.vehicles) do
		if ia_vehicle.externalId == externalId then
			return ia_vehicle
		end
	end
	return nil
end

function IANeighbour:addVehicle(ia_vehicle)
	self.vehicles[ia_vehicle.uniqueId] = ia_vehicle
end

function IANeighbour:updateFromXML(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, glassesColorIndex, facegear, facegearColorIndex, onepiece, onepieceColorIndex, bottom, bottomColorIndex, face, faceColorIndex, top, topColorIndex, gloves, glovesColorIndex, headgear, headgearColorIndex, footwear, footwearColorIndex, hairStyle, hairStyleColorIndex, beard, beardColorIndex, characterVisibility)
	IAprintDebug("updateFromXML", "onepiece=" .. tostring(onepiece) .. " top=" .. tostring(top) .. " bottom=" .. tostring(bottom) .. " footwear=" .. tostring(footwear) .. " initialized=" .. tostring(self.initialized), self)
	return self:_updateFromXMLImpl(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, glassesColorIndex, facegear, facegearColorIndex, onepiece, onepieceColorIndex, bottom, bottomColorIndex, face, faceColorIndex, top, topColorIndex, gloves, glovesColorIndex, headgear, headgearColorIndex, footwear, footwearColorIndex, hairStyle, hairStyleColorIndex, beard, beardColorIndex, characterVisibility)
end

-- Update neighbour data from XML (safe before :initialize(); used when XML load defers initialize until after map assignments)
-- @param boolean enabled - Whether the neighbour is enabled
-- @param number positionX - X position
-- @param number positionY - Y position
-- @param number positionZ - Z position
-- @param number rotation - Rotation
-- @param string action - Action type
-- @param number farmId - Farm ID
-- @param string activeSituationId - Active situation ID from XML (optional)
-- @param number hathair - Hat/hair style index (optional)
-- @param number glasses - Glasses index (optional)
-- @param number facegear - Face gear index (optional)
-- @param number onepiece - One piece clothing index (optional)
-- @param number bottom - Bottom clothing index (optional)
-- @param number face - Face index (optional)
-- @param number top - Top clothing index (optional)
-- @param number gloves - Gloves index (optional)
-- @param number headgear - Headgear index (optional)
-- @param number footwear - Footwear index (optional)
-- @param number hairStyle - Hair style index (optional)
-- @param number hairStyleColorIndex - Hair style color index (optional)
-- @param number beard - Beard index (optional)
-- @param number beardColorIndex - Beard color index (optional)
-- @param string characterVisibility - Character visibility ("yes", "in_car", or other) (optional)
function IANeighbour:_updateFromXMLImpl(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, glassesColorIndex, facegear, facegearColorIndex, onepiece, onepieceColorIndex, bottom, bottomColorIndex, face, faceColorIndex, top, topColorIndex, gloves, glovesColorIndex, headgear, headgearColorIndex, footwear, footwearColorIndex, hairStyle, hairStyleColorIndex, beard, beardColorIndex, characterVisibility)
	local changed = false
	local styleChanged = false

	if enabled ~= nil and self.enabled ~= enabled then
		self.enabled = enabled
		changed = true
	end
	
	if positionX ~= nil then
		self.positionX = positionX
		changed = true
	end
	
	if positionY ~= nil then
		self.positionY = positionY
		changed = true
	end
	
	if positionZ ~= nil then
		self.positionZ = positionZ
		changed = true
	end
	
	if rotation ~= nil then
		self.rotation = rotation
		changed = true
	end
	
	if action ~= nil and self.action ~= action then
		self.action = action
		changed = true
	end
	
	if farmId ~= nil and self.farmId ~= farmId then
		self.farmId = farmId
		changed = true
	end
	
	if activeSituationId ~= nil and self.activeSituationId ~= activeSituationId then
		self.activeSituationId = activeSituationId
		changed = true
	end
	
	if characterVisibility ~= nil and self.characterVisibility ~= characterVisibility then
		self.characterVisibility = characterVisibility
		changed = true
	end
	
	if changed and IANeighbours.debug then
		--print("--- IANeighbour:updateFromXML() - Updated neighbour: "..self.name)
	end
	
	-- Store style attributes if appearance values are provided from XML
	-- Use provided values or fall back to defaults if nil
	-- Store in array to apply later when NPC is fully loaded
	if hathair ~= nil or glasses ~= nil or facegear ~= nil or onepiece ~= nil or bottom ~= nil or 
	   face ~= nil or top ~= nil or gloves ~= nil or headgear ~= nil or footwear ~= nil or 
	   hairStyle ~= nil or beard ~= nil then
		local hasOnePiece = onepiece ~= nil and onepiece > 0
		local topIdx = hasOnePiece and 0 or (top or 0)
		local bottomIdx = hasOnePiece and 0 or (bottom or 0)
		local topCol = hasOnePiece and 1 or (topColorIndex or 1)
		local bottomCol = hasOnePiece and 1 or (bottomColorIndex or 1)
		self.styleAttributes = {
			-- Lua: (0 or 12) is 0; hat index 0 crashes PlayerStyle async (nil.filename).
			hathair = (hathair ~= nil and hathair > 0) and hathair or 12,
			glasses = glasses or 0,
			glassesColorIndex = glassesColorIndex or 1,
			facegear = facegear or 0,
			facegearColorIndex = facegearColorIndex or 1,
			onepiece = onepiece or 5,
			onepieceColorIndex = onepieceColorIndex or 1,
			bottom = bottomIdx,
			bottomColorIndex = bottomCol,
			face = face or 1,
			faceColorIndex = faceColorIndex or 1,
			top = topIdx,
			topColorIndex = topCol,
			gloves = gloves or 0,
			glovesColorIndex = glovesColorIndex or 1,
			headgear = headgear or 0,
			headgearColorIndex = headgearColorIndex or 1,
			footwear = footwear or 1,
			footwearColorIndex = footwearColorIndex or 1,
			hairStyle = hairStyle or 1,
			hairStyleColorIndex = hairStyleColorIndex or 1,
			beard = beard or 0,
			beardColorIndex = beardColorIndex or 1
		}
	end

	return changed
end

-- Delete the neighbour: active situation, vehicles (game + IA), NPC, map hotspot.
function IANeighbour:delete()
	if self.isDeleted then
		return
	end

	if self.scoreSample ~= nil then
		delete(self.scoreSample)
		self.scoreSample = nil
	end

	if self.activeSituation ~= nil then
		local s = self.activeSituation
		pcall(function() s:forceExpireAndDelete() end)
		self.activeSituation = nil
		self.activeSituationId = nil
	end

	if self.vehicles ~= nil then
		for key, iaVeh in pairs(self.vehicles) do
			if iaVeh ~= nil then
				if iaVeh.stopAIJob then
					pcall(function() iaVeh:stopAIJob() end)
				end
				if iaVeh.detachAttachments then
					pcall(function() iaVeh:detachAttachments() end)
				end
				if iaVeh.vehicle ~= nil and iaVeh.vehicle.delete ~= nil and iaVeh.vehicle.isDeleted ~= true then
					pcall(function() iaVeh.vehicle:delete(true) end)
				end
				if iaVeh.delete then
					pcall(function() iaVeh:delete() end)
				end
			end
			self.vehicles[key] = nil
		end
	end
	self.vehicles = {}

	if self.removeNPCSpot then
		pcall(function() self:removeNPCSpot() end)
	end
	if self.hideNPC then
		pcall(function() self:hideNPC() end)
	end
	self:disposeHumanModel()
	if self.npcInstance ~= nil and self.npcInstance.setSpot then
		pcall(function() self.npcInstance:setSpot(nil) end)
	end
	self.npcInstance = nil

	if self.mapHotspot ~= nil then
		IAprintDebug("IANeighbour:delete()", string.format(
			"[HOTSPOT] NPC mapHotspot REMOVE (delete) name=%s", tostring(self.name)
		), self, nil, nil)
		pcall(function()
			iaRemoveMapHotspotFromMission(self.mapHotspot)
			if self.mapHotspot.delete ~= nil then
				self.mapHotspot:delete()
			end
		end)
		self.mapHotspot = nil
	end
	self._iaMapHotspotLastX = nil
	self._iaMapHotspotLastZ = nil

	self.situationHistory = {}
	self.initialized = false
	self.isDeleted = true
end

