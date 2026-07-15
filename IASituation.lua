IASituation = {}
IASituation._mt = Class(IASituation)
IASituation.id = nil
IASituation.neighbour = nil
IASituation.initialized = false
IASituation.loaded = false
-- When true, pre-AI physical setup (incl. attach) finished at least once; savegames may skip redundant attach on restore.
IASituation.initCommitted = false
IASituation.vehicle = nil
IASituation.attachmentBack = nil
IASituation.attachmentFront = nil
IASituation.positionX = nil
IASituation.positionY = nil
IASituation.positionZ = nil
IASituation.rotation = nil
IASituation.loadStep = 0
IASituation.activeDialog = nil
IASituation.dialogController = nil
IASituation.dialogMessages = {}
IASituation.dialogMessageId = 0
IASituation.farmlandId = nil
IASituation.jobType = nil
IASituation.fertilizeSprayTypeIndex = nil
IASituation.isRestored = nil
-- After XML restore, one shot: if AI still won't start, rerun managePositioning from step 1 (position + attach) before giving up.
IASituation.restoredFieldworkFullSetupTried = false
-- After XML restore, one shot: retry starting the saved AI job before doing the full step-1 setup retry.
IASituation.restoredFieldworkStartRetried = false
-- When true, expiration is not delayed by player proximity (situation can end even if player is nearby)
IASituation.ignorePlayerDistance = nil
IASituation.conversation = nil
IASituation.conversationCurrentId = nil
IASituation.conversationNextOptions = nil
--- True after field-border spawn pose applied in managePositioning (worker-only offset from polygon).
IASituation.iaBorderSpawnPoseApplied = false

function IASituation.new(config,neighbour,place,vehicle,farmlandId,attachmentBack,attachmentFront,jobType,isRestored,seedFruitTypeIndexOverride)
	local self = setmetatable({}, IASituation._mt)
	
	if place ~= nil then
		self.place = place
		self.positionX = place.x
		self.positionY = place.y
		self.positionZ = place.z
		self.rotation = place.rotation
	end

	self.config = config
	self.id = config.id
    self.neighbour = neighbour
	self.isRestored = isRestored

	local effectiveJobType = jobType
	if IAFieldwork ~= nil and type(IAFieldwork.resolveFieldworkJobTypeForSituation) == "function" then
		local r = IAFieldwork.resolveFieldworkJobTypeForSituation(config, jobType)
		if r ~= nil then
			effectiveJobType = r
		end
	end
	
	-- Use characterVisibility from config, with fallback to "yes"
	-- Handle "random" case by randomly selecting between "yes", "no", and "in_car"
	local configVisibility = config.characterVisibility or "yes"
	if configVisibility == "random" then
		local randomOptions = {"yes", "no", "in_car"}
		local randomIndex = math.random(1, #randomOptions)
		self.characterVisibility = randomOptions[randomIndex]
	else
		self.characterVisibility = configVisibility
	end
	if effectiveJobType ~= nil then
		self.characterVisibility = "no"
	end
	
	self.vehicle = vehicle
	self.attachmentBack = attachmentBack
	self.attachmentFront = attachmentFront
	self.farmlandId = farmlandId
	self.farmland = nil
	local farmlands = g_farmlandManager:getFarmlands()
	for _, farmland in pairs(farmlands) do
		if farmland ~= nil and farmland.id == self.farmlandId then
			self.farmland = farmland
			self.positionX = farmland.field.posX
			self.positionZ = farmland.field.posZ
			self.positionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, self.positionX, 0, self.positionZ), 1)
			self.rotation = 0
		end
	end

	-- Roadside on-foot: move spawn 4 m further to the road shoulder (same lateral as spline sample: (-dz,dx), opposite of up×forward).
	if self.vehicle == nil and self.farmland == nil and self.place ~= nil then
		local sem = (self.place.getSemanticType ~= nil and self.place:getSemanticType()) or self.place.type
		local ptype = sem ~= nil and string.lower(tostring(sem)) or ""
		if ptype == "roadside" then
			local rot = self.place.rotation or 0
			local fwdX, fwdZ = MathUtil.getDirectionFromYRotation(rot)
			local rightX, _, rightZ = MathUtil.crossProduct(0, 1, 0, fwdX, 0, fwdZ)
			local d = -2
			self.positionX = (self.positionX or 0) + rightX * d
			self.positionZ = (self.positionZ or 0) + rightZ * d
			if g_terrainNode ~= nil and self.positionX ~= nil and self.positionZ ~= nil then
				self.positionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, self.positionX, 0, self.positionZ), 1)
			end
		end
	end
	
	self.jobType = effectiveJobType
	self.initialized = false
	self.loadStep = 0
	self.initCommitted = false
	self.dialogMessageId = 0
	self.dialogMessages = {}
	self.iaBorderSpawnPoseApplied = false
	self.createdAt = nil  -- Track when situation was created (for expiration)
	self.startedAt = nil  -- Track when situation was started (in game hours)
	-- Per-situation random expiry jitter (0..59 minutes) added on top of config.maxDuration so that
	-- situations do not all expire (and trigger regeneration) on the same full game hour. This spreads
	-- the heavy selectRandomPlaceForSituation/generateNewSituation work across many frames instead of one.
	self.expireRandomOffsetMinutes = math.random(0, 59)
	self.currentAiJob = nil
	--- Consecutive loadStep-5 managePositioning ticks (~5s real time each) while AI reports active, speed below FIELDWORK_NO_MOVE_SPEED_KPH, and job not paused.
	self._fieldworkNoMoveTick = 0
	--- Incremented once per managePositioning() visit while loadStep == 5 (same cadence as game5Seconds).
	self._fieldworkManagePositioningTick = 0
	--- When set: do not treat "AI inactive" as finished until _fieldworkManagePositioningTick reaches this value (after proximity/conv resume).
	self._fieldworkInactiveCompleteAllowTick = nil
	--- After grace, AI still inactive: how many times we reran loadStep 1..4 (border reposition) instead of completeFieldwork.
	self._fieldworkInactiveRepositionAttempts = 0
	--- Accumulated real-time ms during which the AI job was active in loadStep 5 (used to decide whether "AI inactive" should respawn from step 1 or simply complete fieldwork).
	self.aiJobActiveElapsedMs = 0
	self.restoredFieldworkFullSetupTried = false
	self.restoredFieldworkStartRetried = false
	-- Player proximity hold: pause AI when player within PAUSE_ENTER_DISTANCE, resume when beyond PAUSE_LEAVE_DISTANCE (called once per enter/leave).
	self.playerHoldActive = false
	-- After closing situation conversation while still beside the vehicle: AI is resumed immediately; while true, proximity pause is skipped until player leaves PAUSE_ENTER_DISTANCE or enters a vehicle.
	self.fieldworkPauseSuppressedAfterConversation = false
	-- When AI is paused and vehicle at 0 kph for 5s, NPC is shown; cleared when player leaves.
	self.npcVisibleWhilePaused = false
	self.pausedAtZeroSpeedTimer = 0
	-- Seconds accumulated with getLastSpeed() >= 0.5 while player in encounter (for on-foot NPC hide hysteresis)
	self.encounterSpeedAboveHalfTimer = 0
	-- After on-foot show: call npc:updatePosition() only this many frames (cab snap) — not every frame (fights look-at / wobble)
	self.npcPostShowPoseSyncFrames = 0
	-- One-shot: custom style applied to vehicle in-cab character (AI driver) from neighbour's style.
	self.vehicleCharacterStyleApplied = false

	-- Conversation: load from mod conversations/<neighbour id>/<situation id>/<variant 1..x>/ (XML + sounds); variant chosen at random — not conversation_generation/
	self.conversation = IAConversation.new()
	local convDir = IAConversation.MOD_CONVERSATIONS_ROOT .. "/" .. tostring(self.neighbour.id) .. "/" .. tostring(self.id)
	self.conversation:loadFromDirectory(convDir, true)
	self:buildConversationMainMenuOptions()
	self.conversationCurrentId = 0
	self.conversationNextOptions = nil

	-- Resolve seed fruit type for SEED jobs: override (next crop) first, then config, then BARLEY fallback
	if self.jobType == IAFieldwork.JobType.SEED then
		if seedFruitTypeIndexOverride ~= nil and type(seedFruitTypeIndexOverride) == "number" then
			self.seedFruitTypeIndex = seedFruitTypeIndexOverride
		else
			self.seedFruitTypeIndex = self:getSeedFruitTypeIndexFromConfig()
			if self.seedFruitTypeIndex == nil then
				self.seedFruitTypeIndex = FruitType.BARLEY  -- fallback
			end
		end
	else
		self.seedFruitTypeIndex = nil
	end

	if IAFieldwork ~= nil and IAFieldwork.isFertilizeJobType(self.jobType) and type(IAFieldwork.getFertilizeSprayTypeIndexForJobType) == "function" then
		self.fertilizeSprayTypeIndex = IAFieldwork.getFertilizeSprayTypeIndexForJobType(self.jobType)
	else
		self.fertilizeSprayTypeIndex = nil
	end

    return self
end

-- Resolve config.seedFruitTypeIndex to a fruit type index. config.seedFruitTypeIndex is a single value (string or number), NOT an array.
-- @return number|nil - Fruit type index for use with setSeedFruitType / FieldUpdateTask:setFruit
function IASituation:getSeedFruitTypeIndexFromConfig()
	if self.config == nil or self.config.seedFruitTypeIndex == nil or self.config.seedFruitTypeIndex == "" then
		return nil
	end
	local value = self.config.seedFruitTypeIndex
	local asNumber = tonumber(value)
	if asNumber ~= nil then
		return asNumber
	end
	if g_fruitTypeManager == nil then
		return nil
	end
	local fruitTypes = g_fruitTypeManager:getFruitTypes()
	if fruitTypes == nil then
		return nil
	end
	local nameLower = string.lower(tostring(value))
	for _, fruitType in ipairs(fruitTypes) do
		if fruitType ~= nil and fruitType.name ~= nil and string.lower(fruitType.name) == nameLower then
			if IANeighbours.debug then
				print("--- IASituation:getSeedFruitTypeIndexFromConfig() - Fruit Type: "..tostring(fruitType.name)..", Index: "..tostring(fruitType.index))
			end
			return fruitType.index
		end
	end
	return nil
end

function IASituation:initialize()
	if self.initialized then
		return
	end

    if self.neighbour == nil then
        return false
    end

	-- Track creation time for expiration checking
	-- Note: gameSeconds should be passed when calling initialize, but for now we'll set it when available
	-- This will be set properly when isExpired is called with gameSeconds
	
	-- Set startedAt using getCurrentGameHours when scenario is initialized
	if self.startedAt == nil then
		self.startedAt = getCurrentGameHours()
	end

	-- Minimum real-time guard: situations must exist for at least 2 real minutes
	-- before game-time expiration can apply. This prevents mass-expiration when the
	-- player exits fast-forward (timeScale > 500).
	if self.createdWallClockSec == nil then
		self.createdWallClockSec = IANeighbours._wallClockSec or 0
	end
	
	self.initialized = true
	self:setSituationAttributeOnIANeighbourVehicles()
	local preserve = self:shouldPreserveSavedFieldworkPresence()
	if preserve then
		self:applyPreservedFieldworkPresenceDesiredOnly()
	else
		self:applyInitialConvoyHiddenPresence()
	end
	--self:clearFieldMissionForFieldwork() -- not necessary anymore, fieldwork missions are autom. removed when the farmid changes
	self:notifyPlayerFarmArrivalIfApplicable()
    return true
end

--- New situations (not restored from savegame) at a player_farm place: show an in-game notification with the neighbour's name.
--- Skipped for neighbours that belong to the player's farm (scenario.xml belongsToFarm="true"), since they live there.
function IASituation:notifyPlayerFarmArrivalIfApplicable()
	if self.isRestored == true then
		return
	end
	if self.place == nil or self.place.type ~= "player_farm" then
		return
	end
	if self.neighbour ~= nil and self.neighbour.belongsToFarm == true then
		return
	end
	if g_currentMission == nil or g_currentMission.addIngameNotification == nil or FSBaseMission == nil or g_i18n == nil or g_i18n.getText == nil then
		return
	end
	local tpl = g_i18n:getText("ingame_situation_at_player_farm")
	if tpl == nil or tpl == "" then
		return
	end
	local neighbourName = (self.neighbour ~= nil and self.neighbour.name) or ""
	local text = string.format(tpl, tostring(neighbourName))
	pcall(function()
		g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
	end)
end

-- When this is a fieldwork situation, remove or make unavailable the field's current mission so our situation owns the field work.
function IASituation:clearFieldMissionForFieldwork()
	if self.jobType == nil then
		return
	end
	if self.farmland == nil or self.farmland.field == nil then
		return
	end
	local field = self.farmland.field
	local mission = field.currentMission
	if mission ~= nil and g_currentMission ~= nil and g_currentMission.aiSystem ~= nil then
		g_currentMission.aiSystem:removeJob(mission)
	end
	field.currentMission = nil
end

-- Set activeSituationId and situation reference on IANeighbourVehicle instances (main vehicle and attachments).
-- Tells presence reconcile that a vehicle belongs to an active situation; situation ref used e.g. for roadside offset in findRelativePositionNpc.
function IASituation:setSituationAttributeOnIANeighbourVehicles()
	if self.id == nil then
		return
	end
	local function markSituationVehicle(ia)
		if ia == nil then
			return
		end
		ia.activeSituationId = self.id
		ia.situation = self
		if ia.clearOffSituationParking ~= nil then
			ia:clearOffSituationParking()
		end
		if IAEquipmentPresence ~= nil then
			IAEquipmentPresence.State.stripHomebaseDesiredForSituationMember(ia)
		end
	end
	markSituationVehicle(self.vehicle)
	markSituationVehicle(self.attachmentBack)
	markSituationVehicle(self.attachmentFront)
end

--- New situation: hide all convoy wrappers immediately (main + attachments). Attachment attach desired state is set later in loadStep 3.
function IASituation:applyInitialConvoyHiddenPresence()
	if IAEquipmentPresence == nil or IAEquipmentPresence.State == nil then
		return
	end
	if self.vehicle ~= nil then
		IAprintDebug("IASituation:applyInitialConvoyHiddenPresence()", "Setting desired hidden for: "..tostring(self.vehicle.vehicleName or self.vehicle.name or self.vehicle.xmlFilename), self.neighbour, self.vehicle, nil)
		IAEquipmentPresence.State.setDesiredHidden(self.vehicle)
	end
	if self.attachmentBack ~= nil then
		IAprintDebug("IASituation:applyInitialConvoyHiddenPresence()", "Setting desired hidden for: "..tostring(self.attachmentBack.vehicleName or self.attachmentBack.name or self.attachmentBack.xmlFilename), self.neighbour, self.attachmentBack, nil)
		IAEquipmentPresence.State.setDesiredHidden(self.attachmentBack)
	end
	if self.attachmentFront ~= nil then
		IAprintDebug("IASituation:applyInitialConvoyHiddenPresence()", "Setting desired hidden for: "..tostring(self.attachmentFront.vehicleName or self.attachmentFront.name or self.attachmentFront.xmlFilename), self.neighbour, self.attachmentFront, nil)
		IAEquipmentPresence.State.setDesiredHidden(self.attachmentFront)
	end
	self:reconcileSituationPresence()
end

--- Ordered convoy list for presence reconcile: main vehicle first, then attachments / other fleet members in this situation.
-- Includes self.attachmentBack/Front, optional extra refs, and any neighbour vehicle with matching activeSituationId.
-- @param ... IANeighbourVehicle optional extra wrappers to include (e.g. captured before a step clears a field)
-- @return table array of IANeighbourVehicle
function IASituation:collectSituationConvoyForPresence(...)
	local seen = {}
	local main = self.vehicle
	local attachments = {}

	local function isMain(ia)
		return main ~= nil and ia == main
	end

	local function addConvoyMember(ia)
		if ia == nil or seen[ia] then
			return
		end
		seen[ia] = true
		if isMain(ia) then
			return
		end
		table.insert(attachments, ia)
	end

	for i = 1, select("#", ...) do
		addConvoyMember(select(i, ...))
	end
	addConvoyMember(self.attachmentBack)
	addConvoyMember(self.attachmentFront)

	if self.neighbour ~= nil and self.neighbour.vehicles ~= nil and self.id ~= nil then
		local sid = tostring(self.id)
		for _, ia in pairs(self.neighbour.vehicles) do
			if ia ~= nil and ia.activeSituationId ~= nil and tostring(ia.activeSituationId) == sid then
				addConvoyMember(ia)
			end
		end
	end

	local convoy = {}
	if main ~= nil then
		seen[main] = true
		table.insert(convoy, main)
	end
	for _, ia in ipairs(attachments) do
		table.insert(convoy, ia)
	end
	return convoy
end

--- Reconcile presence for this situation's main vehicle and all convoy attachments.
-- @param ... IANeighbourVehicle|nil optional extra vehicles to reconcile (in addition to collectSituationConvoyForPresence)
function IASituation:reconcileSituationPresence(...)
	if IAEquipmentPresence == nil or IAEquipmentPresence.Reconcile == nil then
		return
	end
	local convoy = self:collectSituationConvoyForPresence(...)
	if #convoy == 0 then
		IAprintDebug("IASituation:reconcileSituationPresence()", "No convoy vehicles to reconcile", self.neighbour, nil, self)
		return
	end
	for _, ia in ipairs(convoy) do
		if ia ~= nil then
			self:safePcall("reconcileSituationPresence vehicle", function()
				IAprintDebug("IASituation:reconcileSituationPresence()", "Reconciling vehicle: "..tostring(ia.vehicleName or ia.name or ia.xmlFilename), self.neighbour, ia, self)
				IAEquipmentPresence.Reconcile.reconcileVehicle(ia)
			end)
		end
	end
end

function IASituation:buildSituationMainPose()
	if self.positionX == nil or self.positionZ == nil then
		return nil
	end
	local y = self.positionY
	if g_terrainNode ~= nil then
		y = getTerrainHeightAtWorldPos(g_terrainNode, self.positionX, 0, self.positionZ) + 0.2
	end
	return {
		x = self.positionX,
		y = y,
		z = self.positionZ,
		rotation = self.rotation or 0
	}
end

-- Clear activeSituationId and situation reference from IANeighbourVehicle instances (main vehicle and attachments).
function IASituation:clearSituationAttributeFromIANeighbourVehicles()
	if self.vehicle ~= nil then
		self.vehicle.activeSituationId = nil
		self.vehicle.situation = nil
	end
	if self.attachmentBack ~= nil then
		self.attachmentBack.activeSituationId = nil
		self.attachmentBack.situation = nil
	end
	if self.attachmentFront ~= nil then
		self.attachmentFront.activeSituationId = nil
		self.attachmentFront.situation = nil
	end
end

-- Check if the situation has expired.
-- When ignorePlayerDistance is false, an otherwise-expired situation is not considered expired while the player is nearby.
-- @return boolean - true if expired, false otherwise
function IASituation:isExpired()
	-- Minimum real-time guard: situations must exist for at least 2 real minutes
	-- before game-time expiration can apply. This prevents mass-expiration when the
	-- player exits fast-forward (timeScale > 500) where weeks of game-time elapsed
	-- in seconds of real time.
	local realSeconds = nil
	if self.createdWallClockSec ~= nil and IANeighbours._wallClockSec ~= nil then
		realSeconds = IANeighbours._wallClockSec - self.createdWallClockSec
		if realSeconds < 120 then
			return false
		end
	end

	-- If startedAt is not set, cannot check expiration
	if self.startedAt == nil then
		return false
	end
	local timeExpired = false
	if self.jobType ~= nil then
		timeExpired = (self.loaded == true)
	else
		-- If config or maxDuration is not set, situation doesn't expire
		if self.config == nil or self.config.maxDuration == nil then
			return false
		end
		local currentGameHours = getCurrentGameHours()
		local elapsedHours = currentGameHours - self.startedAt
		-- Add the per-situation random jitter (0..59 min) so expirations (and regenerations) are staggered.
		local maxDurationHours = self.config.maxDuration + ((self.expireRandomOffsetMinutes or 0) / 60)
		timeExpired = (elapsedHours >= maxDurationHours)

		-- Realtime max expiration: situation also expires when real time exceeds
		-- (maxDuration * 12) minutes, regardless of game-time progress.
		if not timeExpired and realSeconds ~= nil and self.config.maxDuration ~= nil then
			local realMaxSeconds = self.config.maxDuration * 12 * 60
			if realSeconds >= realMaxSeconds then
				timeExpired = true
			end
		end
	end

	if not timeExpired then
		return false
	end
	-- Time-expired: do not consider expired while player is nearby unless ignorePlayerDistance is set
	if not self.ignorePlayerDistance and self:isPlayerNearbyAtPosition() then
		return false
	end
	return true
end

-- Called by IANeighbour when the situation has expired, before delete(). Records completion state to the neighbour (e.g. SEED last/next crop).
function IASituation:onExpired()
	if self.jobType ~= IAFieldwork.JobType.SEED or self.farmlandId == nil or self.seedFruitTypeIndex == nil or self.neighbour == nil then
		return
	end
	local neighbour = self.neighbour
	if neighbour.assignedFarmlandLastCrop == nil then
		neighbour.assignedFarmlandLastCrop = {}
	end
	neighbour.assignedFarmlandLastCrop[self.farmlandId] = self.seedFruitTypeIndex
	if neighbour.assignedFarmlandNextCrop == nil then
		neighbour.assignedFarmlandNextCrop = {}
	end
	if IANeighbours.gameLoopHelper ~= nil then
		local nextCrop = IANeighbours.gameLoopHelper:getNextCropForField(neighbour, self.farmlandId)
		neighbour.assignedFarmlandNextCrop[self.farmlandId] = nextCrop
	end
	if IANeighbours.debug then
		local idx = self.seedFruitTypeIndex
		local ft = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(idx)
		local nameStr = (ft and ft.name) or tostring(idx)
		print("--- IASituation:onExpired() - SEED done: "..tostring(neighbour.name).." farmland "..tostring(self.farmlandId).." lastCrop -> "..tostring(nameStr).." ("..tostring(idx)..")")
	end
end

function IASituation:delete()
	if not self.initialized then
		return
	end

	-- [FOS_TEST] instrumentation: situation is ending
	if IATestRunner ~= nil and type(IATestRunner.onSituationComplete) == "function" then
		IATestRunner.onSituationComplete(self, "delete")
	end

	-- Stop AI / remove job first so field ownership and FieldUpdateTask run in a stable state
	if self.vehicle ~= nil and self.farmlandId ~= nil and self.vehicle.resumeAIJob ~= nil then
		self:safePcall("delete resumeAIJob", function()
			self.vehicle:resumeAIJob(self.farmlandId)
		end)
	end
	local function stopIaVehicle(iaVeh)
		if iaVeh ~= nil and iaVeh.stopAIJob ~= nil then
			self:safePcall("delete stopAIJob", function()
				iaVeh:stopAIJob()
			end)
		end
	end
	stopIaVehicle(self.vehicle)
	stopIaVehicle(self.attachmentBack)
	stopIaVehicle(self.attachmentFront)
	if self.currentAiJob ~= nil and g_currentMission ~= nil and g_currentMission.aiSystem ~= nil then
		self:safePcall("delete aiSystem.removeJob(currentAiJob)", function()
			g_currentMission.aiSystem:removeJob(self.currentAiJob)
		end)
		self.currentAiJob = nil
	end

	if self.jobType ~= nil then
		self:safePcall("delete clearFieldMissionForFieldwork", function()
			self:clearFieldMissionForFieldwork()
		end)
	end

	-- Fieldwork still in managePositioning before step 6: step 5 already ran completeFieldwork+unblock; step 6+ must not run them again
	local needsFieldworkFinish = self.jobType ~= nil and (self.loadStep == nil or self.loadStep < 6)
	if needsFieldworkFinish then
		self:safePcall("delete completeFieldwork", function()
			self:completeFieldwork()
		end)
		self:safePcall("delete unblockFarmland (incomplete fieldwork)", function()
			self:unblockFarmland()
		end)
	end

	-- Same order as IANeighbour:handleActiveSituation() before this refactor
	if self.neighbour ~= nil and self.neighbour.addSituationToHistory ~= nil then
		self:safePcall("delete addSituationToHistory", function()
			self.neighbour:addSituationToHistory(self)
		end)
	end
	self:safePcall("delete onExpired", function()
		self:onExpired()
	end)

	-- Clear situation attribute on IANeighbourVehicle instances so presence reconcile may hide them on next pass.
	self:clearSituationAttributeFromIANeighbourVehicles()

	-- Always unblock farmland if this situation blocked it (fieldwork situations; idempotent if already unblocked)
	-- This is important for teardown paths (e.g. "Remove Mod") where we need the field to become available again.
	if self.farmlandId ~= nil and self.farmland ~= nil and self.unblockFarmland ~= nil then
		self:safePcall("unblockFarmland", function()
			self:unblockFarmland()
		end)
	end

	if self.neighbour ~= nil then
		local okRm, errRm = pcall(function() self.neighbour:removeNPCSpot() end)
		if not okRm and IANeighbours.debug then
			print("--- IASituation:delete() - removeNPCSpot situation=" .. tostring(self.id) .. ": " .. tostring(errRm))
		end
	end

	if (self.loaded or self.loadStep > 1) and self.vehicle ~= nil and IAEquipmentPresence ~= nil then
		IAEquipmentPresence.State.setDesiredHidden(self.vehicle)
	end
	if self.neighbour ~= nil then
		local okNpc, errNpc = pcall(function() self.neighbour:hideNPC() end)
		if not okNpc and IANeighbours.debug then
			print("--- IASituation:delete() - hideNPC situation=" .. tostring(self.id) .. ": " .. tostring(errNpc))
		end
	end
	if (self.loaded or self.loadStep > 3) and self.attachmentBack ~= nil and IAEquipmentPresence ~= nil then
		IAEquipmentPresence.State.setDesiredHidden(self.attachmentBack)
	end
	if (self.loaded or self.loadStep > 3) and self.attachmentFront ~= nil and IAEquipmentPresence ~= nil then
		IAEquipmentPresence.State.setDesiredHidden(self.attachmentFront)
	end

	if self.neighbour ~= nil and self.neighbour.activeSituation == self then
		self.neighbour.activeSituation = nil
		self.neighbour.activeSituationId = nil
	end

	if self.neighbour ~= nil and IAEquipmentPresence ~= nil and IAEquipmentPresence.Reconcile ~= nil then
		self:reconcileSituationPresence()
		IAEquipmentPresence.Reconcile.reconcileNeighbourFleet(self.neighbour, { scenario = nil, computeHomebaseDesired = true })
	end

	self.initialized = false
    return true
end

--- Run fn in pcall; on failure print when IANeighbours.debug (avoids game-breaking error spam from vehicle/AI/attach APIs).
function IASituation:safePcall(label, fn)
	local ok, err = pcall(fn)
	if not ok and IANeighbours and IANeighbours.debug then
		print("--- IASituation:safePcall() " .. tostring(label) .. " situation=" .. tostring(self.id) .. ": " .. tostring(err))
	end
	return ok
end

--- Force-stop and remove this situation.
-- Used for teardown (e.g. "Remove Mod"). All teardown is implemented in delete().
function IASituation:forceExpireAndDelete()
	self:safePcall("forceExpireAndDelete delete", function()
		self:delete()
	end)
	if self.neighbour ~= nil and self.neighbour.activeSituation == self then
		self.neighbour.activeSituation = nil
		self.neighbour.activeSituationId = nil
	end
end

--- Restored fieldwork may skip re-attaching only if init was committed before save (avoids trusting half-finished init).
function IASituation:shouldTrustSavedAttachmentLayout()
	return self.isRestored == true and self.jobType ~= nil and self.initCommitted == true
end

--- Reloaded save with fieldwork in progress: set desired presence only — never hide/detach/teleport convoy (breaks AI).
function IASituation:shouldPreserveSavedFieldworkPresence()
	if self.jobType == nil then
		return false
	end
	if self:shouldTrustSavedAttachmentLayout() then
		return true
	end
	if self.isRestored ~= true then
		return false
	end
	local main = self.vehicle
	if main ~= nil and main.vehicle ~= nil and type(main.vehicle.getIsAIActive) == "function" then
		local ok, aiActive = pcall(function()
			return main.vehicle:getIsAIActive()
		end)
		if ok and aiActive == true then
			return true
		end
	end
	return false
end

--- Layer 1 only: desired presence for situation convoy (no reconcile).
-- @param table|nil opts { setMain = boolean|nil default true, setAttachments = boolean|nil default true }
function IASituation:setDesiredConvoyPresencePolicy(opts)
	if IAEquipmentPresence == nil or IAEquipmentPresence.State == nil then
		return
	end
	opts = opts or {}
	local setMain = opts.setMain ~= false
	local setAttachments = opts.setAttachments ~= false
	if setMain and self.vehicle ~= nil then
		IAEquipmentPresence.State.setDesiredSituationMain(self.vehicle, IAEquipmentPresence.State.buildPoseFromIA(self.vehicle))
	end
	if not setAttachments then
		return
	end
	local parentId = self.vehicle ~= nil and self.vehicle.uniqueId ~= nil and tostring(self.vehicle.uniqueId) or nil
	if parentId == nil then
		return
	end
	if self.attachmentBack ~= nil then
		IAEquipmentPresence.State.setDesiredSituationAttachment(self.attachmentBack, "back", parentId)
	end
	if self.attachmentFront ~= nil then
		IAEquipmentPresence.State.setDesiredSituationAttachment(self.attachmentFront, "front", parentId)
	end
end

--- Policy-only convoy state for restored fieldwork (matches save layout; reconcile skipped).
function IASituation:applyPreservedFieldworkPresenceDesiredOnly()
	IAprintDebug("IASituation:applyPreservedFieldworkPresenceDesiredOnly()", "Restored fieldwork: desired presence only (no reconcile)", self.neighbour, nil, self)
	self:setDesiredConvoyPresencePolicy()
end

-- Fills attachmentBack when applicable (sprayer → herbicide, manure spreader → manure). Fieldwork only; delegates to IANeighbourVehicle:fillSprayerOrSpreaderIfNeeded().
function IASituation:fillAttachmentBackIfNeeded()
	if self.jobType == nil then
		return
	end
	if self.attachmentBack ~= nil and self.attachmentBack.fillSprayerOrSpreaderIfNeeded ~= nil then
		self:safePcall("fillSprayerOrSpreaderIfNeeded", function()
			self.attachmentBack:fillSprayerOrSpreaderIfNeeded()
		end)
	end
end

--- Max work-area width (m) across main tractor and attachments (`getWorkAreaWidth` per work area; no unfold).
-- @return number width meters (may be 0 if work areas and size unavailable)
function IASituation:iaResolveCombinedFieldworkWidth()
	local maxW = 0
	local function considerWrapper(iv)
		if iv == nil then
			return
		end
		local w = 0
		if type(iv.resolveFieldworkWorkWidthMeters) == "function" then
			w = iv:resolveFieldworkWorkWidthMeters()
		elseif iv.vehicle ~= nil and iv.vehicle.size ~= nil and type(iv.vehicle.size.width) == "number" then
			w = iv.vehicle.size.width
		end
		if type(w) == "number" and w > maxW then
			maxW = w
		end
	end
	considerWrapper(self.vehicle)
	considerWrapper(self.attachmentFront)
	considerWrapper(self.attachmentBack)
	return maxW
end

--- One-shot: replace situation spawn position/rotation with longest-edge border pose (see IAHelper_computeFieldBorderSpawnPose).
function IASituation:iaApplyBorderSpawnPoseOnce()
	if self.iaBorderSpawnPoseApplied == true then
		return
	end
	if self.jobType == nil then
		return
	end
	if self.isRestored == true then
		return
	end
	if self.farmland == nil or self.farmland.field == nil then
		return
	end
	local field = self.farmland.field
	if field.polygonPoints == nil or type(field.polygonPoints) ~= "table" or #field.polygonPoints < 3 then
		return
	end
	if IAHelper_computeFieldBorderSpawnPose == nil or type(IAHelper_computeFieldBorderSpawnPose) ~= "function" then
		return
	end
	local combined = self:iaResolveCombinedFieldworkWidth()
	IAprintDebug("IASituation:iaApplyBorderSpawnPoseOnce()", "iaResolveCombinedFieldworkWidth: "..tostring(combined), self.neighbour, nil, self)
	local x, z, yaw = IAHelper_computeFieldBorderSpawnPose(field, combined, nil)
	if x == nil or z == nil or yaw == nil then
		return
	end
	self.positionX = x
	self.positionZ = z
	self.rotation = yaw
	if g_terrainNode ~= nil and self.positionX ~= nil and self.positionZ ~= nil then
		self.positionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, self.positionX, 0, self.positionZ), 1)
	end
	self.iaBorderSpawnPoseApplied = true
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:iaApplyBorderSpawnPoseOnce() %s combinedWidth=%.2f -> x=%.2f z=%.2f yaw=%.3f",
			tostring(self.id),
			combined,
			x,
			z,
			yaw
		))
	end
end

function IASituation:managePositioning()
	if self.loadStep == 0 then
		self.loadStep = 1
	end
	if self.loadStep == 1 then
		if IANeighbours.debug then
			print("--- IASituation:managePositioning() "..self.id.." - Vehicle: "..tostring(self.vehicle))
		end
		if self.vehicle ~= nil and self.vehicle.fullLoaded == true and self.neighbour.isStandingCharacterReady ~= nil and self.neighbour:isStandingCharacterReady() then
			if IANeighbours.debug then
				print("--- IASituation:update() "..self.id.." - Handling Vehicle Position")
				print("--- IASituation:update() "..self.id.." - Vehicle Position: "..tostring(self.positionX)..", "..tostring(self.positionY)..", "..tostring(self.positionZ)..", "..tostring(self.rotation))
				print("--- IASituation:update() "..self.id.." - isRestored: "..tostring(self.isRestored))
			end
			if self.isRestored == true and self.jobType ~= nil then
				if IANeighbours.debug then
					print("--- IASituation:managePositioning() "..self.id.." - Restored fieldwork: skipping vehicle teleport (save pose)")
				end
				-- Desired state already set in initialize() via applyPreservedFieldworkPresenceDesiredOnly().
				if not self:shouldPreserveSavedFieldworkPresence() and self.vehicle ~= nil then
					self:setDesiredConvoyPresencePolicy()
				end
			else
				local gameVehicle = self.vehicle.vehicle
				if gameVehicle == nil or gameVehicle.rootNode == nil then
					if IANeighbours.debug then
						print("--- IASituation:update() "..self.id.." - Skipping vehicle position update (vehicle or rootNode nil)")
					end
				else
					self:iaApplyBorderSpawnPoseOnce()
					local pose = self:buildSituationMainPose()
					if pose ~= nil and IAEquipmentPresence ~= nil then
						IAEquipmentPresence.State.setDesiredSituationMain(self.vehicle, pose)
						local okRec, errRec = pcall(function()
							self:reconcileSituationPresence(self.attachmentBack, self.attachmentFront)
							self.vehicle:setFarmId(IANeighbours.DebugAiFarmId or self.vehicle.farmId)
						end)
						if not okRec then
							print("--- IASituation:update() "..tostring(self.id).." - reconcileSituationPresence error: "..tostring(errRec))
							if IAEquipmentPresence ~= nil then
								IAEquipmentPresence.State.setDesiredHidden(self.vehicle)
							end
							pcall(function() self.vehicle:mech_hide() end)
							self.vehicle = nil
						end
					end
				end
			end
			

			
			if IANeighbours.debug then
				print("--- IASituation:update() "..self.id.." - Situation loaded")
			end
			self.loadStep = 2
			return true
		end
		if self.vehicle == nil then
			self.loadStep = 2
			return true
		end
	end
	if self.loadStep == 2 then
		-- Mark situation attribute on IANeighbourVehicle instances so presence reconcile keeps them visible.
		self:safePcall("loadStep2 setSituationAttributeOnIANeighbourVehicles", function()
			self:setSituationAttributeOnIANeighbourVehicles()
		end)

		-- Update neighbour position with situation coordinates
		if self.neighbour ~= nil then
			self.neighbour.positionX = self.positionX
			self.neighbour.positionY = self.positionY
			self.neighbour.positionZ = self.positionZ
			self.neighbour.rotation = self.rotation
		end
		
		-- Only show NPC if character visibility is "yes" or "in_car"
		if IANeighbours ~= nil and IANeighbours.debug then
			print("--- IASituation:update() "..self.id.." - Character Visibility: "..tostring(self.characterVisibility))
		end
		if self.vehicle ~= nil then
			self:safePcall("loadStep2 updateNPCPosition (vehicle)", function()
				self.neighbour:updateNPCPosition(self.vehicle.npcPositionX, self.vehicle.npcPositionY, self.vehicle.npcPositionZ, self.vehicle.npcRotation)
			end)
		else
			self:safePcall("loadStep2 updateNPCPosition (place)", function()
				self.neighbour:updateNPCPosition(self.positionX, self.positionY, self.positionZ, self.rotation)
			end)
		end

		if self.characterVisibility == "yes" and self.jobType == nil then
			self:safePcall("loadStep2 showNPC", function() self.neighbour:showNPC() end)
			self:safePcall("loadStep2 updateNPCName false", function() self.neighbour:updateNPCName(false) end)
			self:safePcall("loadStep2 updateNPCSpot", function() self.neighbour:updateNPCSpot() end)
		else
			if self.jobType ~= nil then
				self:safePcall("loadStep2 updateNPCName false-2", function() self.neighbour:updateNPCName(false) end)		
			else
				self:safePcall("loadStep2 updateNPCName true", function() self.neighbour:updateNPCName(true) end)		
			end
		end
		--self.neighbour:updateNPCSpot()
		

		if self.attachmentBack ~= nil or self.attachmentFront ~= nil then
			self.loadStep = 3
		else
			-- No attachments: start engine now (vehicle is positioned and visible)
			if self.vehicle ~= nil and self.vehicle.startEngineIfPossible ~= nil then
				--self.vehicle:startEngineIfPossible()--disabled
			end
			self.loadStep = 99
			self.loaded = true
			self.initCommitted = true
		end
		return true
	end
	if self.loadStep == 3 then
		-- Set situation attribute on attachment IANeighbourVehicle instances (already set in loadStep 2, ensure consistency)
		self:safePcall("loadStep3 setSituationAttributeOnIANeighbourVehicles", function()
			self:setSituationAttributeOnIANeighbourVehicles()
		end)

		if IANeighbours ~= nil and IANeighbours.debug then
			print("--- IASituation:update() "..self.id.." - Loading attachments (back / front)")
			print("--- IASituation:update() "..self.id.." - Attachment Back: "..tostring(self.attachmentBack)..", Front: "..tostring(self.attachmentFront))
			print("--- IASituation:update() "..self.id.." - Vehicle: "..tostring(self.vehicle))
		end

		-- Front attachment (e.g. weight) only if the main vehicle has a front attacher joint
		if self.attachmentFront ~= nil and self.vehicle ~= nil and self.vehicle.vehicle ~= nil and not vehicleHasFrontAttacherJoint(self.vehicle.vehicle) then
			if IANeighbours ~= nil and IANeighbours.debug then
				print("--- IASituation:managePositioning() "..tostring(self.id).." - Dropping attachmentFront (no front attacher joint on main vehicle)")
			end
			local af = self.attachmentFront
			af.activeSituationId = nil
			af.situation = nil
			if IAEquipmentPresence ~= nil then
				IAEquipmentPresence.State.setDesiredHidden(af)
				IAEquipmentPresence.Reconcile.reconcileVehicle(af)
			end
			self.attachmentFront = nil
		end

		if self.farmlandId ~= nil and self.farmland ~= nil then
			self:safePcall("loadStep3 blockFarmland", function() self:blockFarmland() end)
		end
		if self.vehicle == nil then
			-- Main vehicle was cleared after detach/position error; skip attachments and finish situation without vehicle
			if IANeighbours ~= nil and IANeighbours.debug then
				print("--- IASituation:update() "..self.id.." - No main vehicle, skipping attachment align and attach")
			end
		elseif self:shouldTrustSavedAttachmentLayout() then
			if IANeighbours ~= nil and IANeighbours.debug then
				print("--- IASituation:managePositioning() "..self.id.." - Restored fieldwork: skipping attachment align/attach (initCommitted)")
			end
		else
			if IANeighbours ~= nil and IANeighbours.debug then
				print("--- IASituation:managePositioning() "..self.id.." - Setting desired situation attachment")
			end
			if self.vehicle ~= nil and self.vehicle.uniqueId ~= nil then
				self:setDesiredConvoyPresencePolicy({ setMain = false })
				local convoyBack = self.attachmentBack
				local convoyFront = self.attachmentFront
				self:safePcall("loadStep3 reconcileSituationPresence", function()
					IAprintDebug("IASituation:managePositioning()", "Reconciling situation presence 1", self.neighbour, nil, self)
					self:reconcileSituationPresence(convoyBack, convoyFront)
					IAprintDebug("IASituation:managePositioning()", "Reconciled situation presence 2", self.neighbour, nil, self)
				end)
			end
			if self.attachmentBack ~= nil then
				self:safePcall("loadStep3 attachmentBack setFarmId", function()
					self.attachmentBack:setFarmId(IANeighbours.DebugAiFarmId or self.attachmentBack.farmId)
				end)
				self:fillAttachmentBackIfNeeded()
				if self.jobType == IAFieldwork.JobType.SEED and self.attachmentBack.vehicle ~= nil and self.seedFruitTypeIndex ~= nil then
					if IANeighbours ~= nil and IANeighbours.debug then
						print("--- IASituation:update() "..self.id.." - Setting seed fruit type from seedFruitTypeIndex: "..tostring(self.seedFruitTypeIndex))
					end
					self:safePcall("loadStep3 setSeedFruitType", function()
						self.attachmentBack.vehicle:setSeedFruitType(self.seedFruitTypeIndex, true)
					end)
				end
			end
			if self.attachmentFront ~= nil then
				self:safePcall("loadStep3 attachmentFront setFarmId", function()
					self.attachmentFront:setFarmId(IANeighbours.DebugAiFarmId or self.attachmentFront.farmId)
				end)
			end
		end

		-- Fold main vehicle and attachments only when NOT used in an AI job / fieldwork situation (attachments stay unfolded for work)
		if self.jobType == nil then
			if self.vehicle ~= nil and self.vehicle.tryFold ~= nil then
				self:safePcall("loadStep3 tryFold main", function() self.vehicle:tryFold("situation") end)
			end
			if self.attachmentBack ~= nil and self.attachmentBack.tryFold ~= nil then
				self:safePcall("loadStep3 tryFold back", function() self.attachmentBack:tryFold("back") end)
			end
			if self.attachmentFront ~= nil and self.attachmentFront.tryFold ~= nil then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:managePositioning() "..self.id.." - Trying to fold front attachment")
				end
				self:safePcall("loadStep3 tryFold front", function() self.attachmentFront:tryFold("front") end)
			end
		end
		-- Do not mark committed for fieldwork with no main vehicle (setup failed); otherwise restore would trust missing attach.
		if self.jobType == nil or self.vehicle ~= nil then
			self.initCommitted = true
		end
		if self.jobType ~= nil then
			self.loadStep = 4
		else
			self.loadStep = 99
			self.loaded = true
		end
		return true
	end
	if self.loadStep == 4 then
		-- Savegames do not restore running AI on NPC vehicles; restored fieldwork must start the job like a fresh situation.
		-- IANeighbourVehicle:startAIJob() no-ops if AI is already active.
		if self.isRestored == true and self.jobType ~= nil then
			if IANeighbours ~= nil and IANeighbours.debug then
				print("--- IASituation:managePositioning() "..self.id.." - Restored fieldwork: apply driver style, then start AI if inactive")
			end
			self:applyVehicleCharacterStyle()
		end
		if self.vehicle ~= nil then
			if IANeighbours ~= nil and IANeighbours.debug then
				if self.vehicle.vehicle ~= nil then
					print("--- IASituation:managePositioning() "..self.id.." - Vehicle Owner Farm ID: "..tostring(self.vehicle.vehicle.ownerFarmId))
				end
				local attachVehicle = self.attachmentBack or self.attachmentFront
				if attachVehicle ~= nil and attachVehicle.vehicle ~= nil then
					print("--- IASituation:managePositioning() "..self.id.." - Attach Owner Farm ID: "..tostring(attachVehicle.vehicle.ownerFarmId))
				end
				print("--- IASituation:managePositioning() "..self.id.." - Starting AI Job for vehicle: "..tostring(self.vehicle.name)..", jobType: "..tostring(self.jobType)..", farmlandId: "..tostring(self.farmlandId))
			end
			if (self.jobType == IAFieldwork.JobType.CULTIVATE or self.jobType == IAFieldwork.JobType.HARROW or self.jobType == IAFieldwork.JobType.SEED or self.jobType == IAFieldwork.JobType.HARVEST or IAFieldwork.isFertilizeJobType(self.jobType) or self.jobType == IAFieldwork.JobType.SPRAY or self.jobType == IAFieldwork.JobType.PLOW) and self.farmlandId ~= nil and self.farmland ~= nil then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:managePositioning() "..self.id.." - Fieldwork AI: "..tostring(self.jobType)..", farmlandId: "..tostring(self.farmlandId)..", field: "..tostring(self.farmland.id))
				end
				self:safePcall("loadStep4 startAIJob", function()
					self.currentAiJob = self.vehicle:startAIJob(self.jobType, self.farmland.field.posX, self.farmland.field.posZ, self.farmlandId)
				end)
			end
		end

		self.loadStep = 5
		-- [FOS_TEST] instrumentation: AI-active state reached
		if IATestRunner ~= nil and type(IATestRunner.onSituationLoadStepChanged) == "function" then
			IATestRunner.onSituationLoadStepChanged(self, 5)
		end
		return true
	end
	if self.loadStep == 5 then
		self:_fieldworkAdvanceManagePositioningTick()

		-- If harvest job, empty combine grain tank when over 80% full (simulate unloading)
		if self.jobType == IAFieldwork.JobType.HARVEST and self.vehicle ~= nil and self.vehicle.vehicle ~= nil then
			self:safePcall("loadStep5 harvest drain fill", function()
				local vehicle = self.vehicle.vehicle
				if vehicle.spec_combine ~= nil and vehicle.spec_combine.fillUnitIndex ~= nil then
					local fillUnitIndex = vehicle.spec_combine.fillUnitIndex
					local capacity = vehicle:getFillUnitCapacity(fillUnitIndex)
					if capacity and capacity > 0 then
						local fillLevel = vehicle:getFillUnitFillLevel(fillUnitIndex)
						local fillPct = fillLevel / capacity
						if fillPct > 0.8 then
							local fillTypeIndex = vehicle:getFillUnitFillType(fillUnitIndex)
							vehicle:addFillUnitFillLevel(self.vehicle.farmId, fillUnitIndex, -fillLevel, fillTypeIndex, ToolType.UNDEFINED, nil)
						end
					end
				end
			end)
		end

		-- AI active (running or blocked): normal logic. Else: complete situation.
		local aiActiveNow = self.vehicle ~= nil and self.vehicle.vehicle ~= nil and self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive()
		if aiActiveNow then
			-- Do not clear post-restart inactive grace here: getIsAIActive() often flickers true once after
			-- startAIJob before another inactive window; clearing would drop protection and trigger false completeFieldwork.
			-- Grace is cleared only in _fieldworkCompleteFieldworkAndGoToStep6.
			-- Same reason for _fieldworkInactiveRepositionAttempts: a one-tick flicker would otherwise reset the
			-- retry counter and cause an infinite reposition loop when the AI never truly starts (e.g. spawn on
			-- already-harvested field). Counter is cleared only in _fieldworkCompleteFieldworkAndGoToStep6.
			-- Restore recovery (retry start / full setup) only applies until AI has actually run once; after that, inactive AI means finished/stopped → complete situation.
			if self.isRestored == true and self.jobType ~= nil then
				self.isRestored = false
			end
			--print("--- IASituation:update() "..self.id.." - Vehicle AI is active")
			-- NPC position cache is updated once per frame in IANeighbourVehicle:update(); skip while on-foot NPC is shown
			if not self.npcVisibleWhilePaused and self.vehicle.npcPositionX ~= nil and self.vehicle.npcPositionY ~= nil and self.vehicle.npcPositionZ ~= nil then
				self:safePcall("loadStep5 updateNPCPosition (AI active)", function()
					self.neighbour:updateNPCPosition(self.vehicle.npcPositionX, self.vehicle.npcPositionY, self.vehicle.npcPositionZ, self.vehicle.npcRotation or 0)
				end)
			end
			--self.neighbour:updateNPCSpot()

			-- Pause/resume by player distance is handled every frame in update()

			-- If it is later than 23:30, end the working day: complete job and fieldwork
			local env = g_currentMission and g_currentMission.environment
			if env then
				local hour = env.currentHour or 0
				local minute = env.currentMinute or 0
				if hour == 23 and minute >= 30 then
					if IANeighbours ~= nil and IANeighbours.debug then
						print("--- IASituation:update() "..self.id.." - Working day ended, completing situation")
					end
					self:safePcall("loadStep5 end day resumeAIJob", function()
						if self.vehicle and self.vehicle.vehicle:getIsAIActive() then
							self.vehicle:resumeAIJob(self.farmlandId)
							self.vehicle:stopAIJob()
						end
					end)
					self:_fieldworkCompleteFieldworkAndGoToStep6("loadStep5 end day ")
					return true
				end
			end
			
			if g_currentMission.missionInfo.timeScale > 500 then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - TimeScale is greater than 500, remove AI Job and complete fieldwork")
				end
				self:safePcall("loadStep5 timeScale resume stop", function()
					self.vehicle:resumeAIJob(self.farmlandId)
					self.vehicle:stopAIJob()
				end)
				self:_fieldworkCompleteFieldworkAndGoToStep6("loadStep5 timeScale ")
				return true
			end
			
			local speedHolder = { kph = 999 }
			self:safePcall("loadStep5 getLastSpeed", function()
				speedHolder.kph = self.vehicle.vehicle:getLastSpeed()
			end)
			if self:_fieldworkTickNoMovementWhileAiRunning(speedHolder.kph, self.vehicle.aiJobPaused) then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:managePositioning() "..self.id.." - FIELDWORK no-move limit: stop AI and complete situation")
				end
				self:_fieldworkStopAiBeforeSituationComplete()
				self:_fieldworkCompleteFieldworkAndGoToStep6("loadStep5 stuck ")
			end
		else
			-- AI no longer active: complete situation and go to loadStep 6, unless we use stop and are waiting for player to leave (then restart)
			if IANeighbours ~= nil and IANeighbours.debug then
				local stopOrBlock = self:checkAIStopOrBlock()
				print(string.format(
					"--- IASituation:managePositioning() loadStep5 AI inactive | id=%s job=%s farmland=%s hold=%s stopOrBlock=%s restored=%s npcOnFoot=%s pauseAfterConv=%s",
					tostring(self.id),
					tostring(self.jobType),
					tostring(self.farmlandId),
					tostring(self.playerHoldActive),
					tostring(stopOrBlock),
					tostring(self.isRestored),
					tostring(self.npcVisibleWhilePaused),
					tostring(self.fieldworkPauseSuppressedAfterConversation)
				))
			end
			if self:checkAIStopOrBlock() and self.playerHoldActive then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:managePositioning() loadStep5 AI inactive -> wait (stop/block + hold)")
				end
				return true
			end
			if self.playerHoldActive and self.vehicle ~= nil then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:managePositioning() loadStep5 AI inactive -> resumeAIJob (hold was true)")
				end
				self:safePcall("loadStep5 resumeAIJob (AI inactive branch)", function()
					self.vehicle:resumeAIJob(self.farmlandId)
				end)
			end
			-- Restored save: AI often was never started; try again once before ending the situation.
			-- startAIJob can report active for one tick and then go inactive again, so mark the retry spent before checking active.
			local isFieldworkJob = self.jobType == IAFieldwork.JobType.CULTIVATE or self.jobType == IAFieldwork.JobType.HARROW or self.jobType == IAFieldwork.JobType.SEED or self.jobType == IAFieldwork.JobType.HARVEST or IAFieldwork.isFertilizeJobType(self.jobType) or self.jobType == IAFieldwork.JobType.SPRAY or self.jobType == IAFieldwork.JobType.PLOW
			if self.isRestored == true and isFieldworkJob and self.vehicle ~= nil and self.farmland ~= nil then
				if self.restoredFieldworkStartRetried ~= true then
					self.restoredFieldworkStartRetried = true
					self:safePcall("loadStep5 restored retry startAIJob", function()
						self.currentAiJob = self.vehicle:startAIJob(self.jobType, self.farmland.field.posX, self.farmland.field.posZ, self.farmlandId)
					end)
					if self.vehicle.vehicle ~= nil and self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive() then
						self.playerHoldActive = false
						return true
					end
				end
				if self.restoredFieldworkFullSetupTried ~= true then
					self.restoredFieldworkFullSetupTried = true
					self.isRestored = false
					if IANeighbours ~= nil and IANeighbours.debug then
						print("--- IASituation:managePositioning() "..self.id.." - Restored fieldwork AI still inactive; rerunning positioning from step 1")
					end
					self:_fieldworkRestartFieldworkSetupFromStepOne("restored_inactive_after_start_retry")
					return true
				end
			end
			if not self:_fieldworkMayCompleteWhileAiInactive() then
				return true
			end
			-- AI job ran long enough to be considered a real fieldwork pass: do not respawn from step 1, just complete.
			-- The respawn path is meant for "AI failed to start / immediately gave up" (< AI_JOB_RESPAWN_MAX_DURATION_MS active time).
			local aiActiveElapsedMs = self.aiJobActiveElapsedMs or 0
			if aiActiveElapsedMs >= IASituation.AI_JOB_RESPAWN_MAX_DURATION_MS then
				if IANeighbours ~= nil and IANeighbours.debug then
					print(string.format(
						"--- IASituation:managePositioning() loadStep5 AI inactive -> COMPLETE FIELDWORK (skip respawn, aiActiveElapsedMs=%d >= %d)",
						aiActiveElapsedMs,
						IASituation.AI_JOB_RESPAWN_MAX_DURATION_MS
					))
				end
				self:_fieldworkCompleteFieldworkAndGoToStep6("loadStep5 AI inactive (ran long) ")
				return true
			end
			local aiStillInactive = self.vehicle == nil or self.vehicle.vehicle == nil
				or self.vehicle.vehicle.getIsAIActive == nil or not self.vehicle.vehicle:getIsAIActive()
			if aiStillInactive
				and (self._fieldworkInactiveRepositionAttempts or 0) < IASituation.FIELDWORK_INACTIVE_REPOSITION_MAX_ATTEMPTS then
				self:_fieldworkRestartFieldworkSetupFromStepOne("inactive_after_grace")
				return true
			end
			if IANeighbours ~= nil and IANeighbours.debug then
				local aiAfter = self.vehicle ~= nil and self.vehicle.vehicle ~= nil and self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive()
				print(string.format(
					"--- IASituation:managePositioning() loadStep5 AI inactive -> COMPLETE FIELDWORK (aiActive after resume try=%s)",
					tostring(aiAfter)
				))
			end
			self:_fieldworkCompleteFieldworkAndGoToStep6("loadStep5 AI inactive ")
		end

		return true
	end
	if self.loadStep == 6 then
		self:safePcall("loadStep6 field state completion", function()
			local fieldgroundtype = self.farmland.field.fieldState.groundType
			if self.jobType == IAFieldwork.JobType.CULTIVATE and fieldgroundtype == FieldGroundType.CULTIVATED then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field ground type is cultivated, completing situation")
				end
				self.loadStep = 99
				self.loaded = true
			elseif self.jobType == IAFieldwork.JobType.SEED and fieldgroundtype == FieldGroundType.SEEDED then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field ground type is seeded, completing situation")
				end
				self.loadStep = 99
				self.loaded = true
			elseif self.jobType == IAFieldwork.JobType.HARVEST then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field is harvested, completing situation")
				end
				self.loadStep = 99
				self.loaded = true
			elseif self.jobType == IAFieldwork.JobType.HARROW and fieldgroundtype == FieldGroundType.STUBBLE_TILLAGE then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field ground type is stubble tillage, completing situation")
				end
				self.loadStep = 99
				self.loaded = true
			elseif self.jobType == IAFieldwork.JobType.PLOW and fieldgroundtype == FieldGroundType.PLOWED then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field ground type is plowed, completing situation")
				end
				self.loadStep = 99
				self.loaded = true
			elseif self.jobType == IAFieldwork.JobType.SPRAY then
				local weedState = (self.farmland.field.fieldState and self.farmland.field.fieldState.weedState) or nil
				if IAFieldwork ~= nil and type(IAFieldwork.isPostHerbicideWeedState) == "function" and IAFieldwork.isPostHerbicideWeedState(weedState) then
					if IANeighbours ~= nil and IANeighbours.debug then
						print("--- IASituation:update() "..self.id.." - Field weed state is sprayed ("..tostring(weedState).."), completing situation")
					end
					self.loadStep = 99
					self.loaded = true
				end
			end
			-- Fallback: complete situation (e.g. FERTILIZE, or when no specific completion state yet)
			if self.loadStep ~= 99 then
				if IANeighbours ~= nil and IANeighbours.debug then
					print("--- IASituation:update() "..self.id.." - Field ground type is not cultivated, starting new AI Job")
				end
				self.loadStep = 99
				self.loaded = true
			end
		end)
		return true
	end
	if self.loadStep == 99 then
		return true
	end
end
function IASituation:update(dt,gameSeconds,game5Seconds)
	if not self.initialized then
		return
	end

	-- Track how long the AI job has actually been active while in loadStep 5: used in the AI-inactive branch
	-- to distinguish a legitimate fieldwork completion (long run) from an immediate failure to start (short run).
	if self.loadStep == 5 and self.vehicle ~= nil and self.vehicle.vehicle ~= nil
		and self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive() then
		self.aiJobActiveElapsedMs = (self.aiJobActiveElapsedMs or 0) + (dt or 0)
	end

	if self.conversation ~= nil then
		self.conversation:update(dt)
	end

	-- Reset motor timer (or restart if OFF) before encounter logic so stopAIJob / engine kill does not leave us with a full frame of OFF + rising timer.
	if self.vehicle ~= nil and self.vehicle.keepSituationMotorRunning ~= nil then
		if self:shouldKeepSituationMotorRunning() then
			self.vehicle:keepSituationMotorRunning()
		end
	end

	self:manageVehicleEncounter(dt)

	self:updateHotspots()

	if game5Seconds then
		self:managePositioning()
	end

	-- Same again after encounter: setEngineAndLightsOnForPlayerNearby runs inside manageVehicleEncounter; this frame keeps timer at 0 / catches OFF after stop.
	if self.vehicle ~= nil and self.vehicle.keepSituationMotorRunning ~= nil then
		if self:shouldKeepSituationMotorRunning() then
			self.vehicle:keepSituationMotorRunning()
		end
	end

	return true
end

-- When true, situation update will run keepSituationMotorRunning() twice per frame (before/after encounter). Only for fieldwork situations (jobType set); non-fieldwork never uses per-frame motor keep-alive.
function IASituation:shouldKeepSituationMotorRunning()
	if self.vehicle == nil or self.jobType == nil then
		return false
	end
	if not (self.loaded or (self.loadStep ~= nil and self.loadStep >= 1)) then
		return false
	end
	-- Active fieldwork on the field: need game vehicle reference.
	if self.loadStep == 5 then
		return self.vehicle.vehicle ~= nil
	end
	return true
end

-- When vehicle AI is active: update neighbour map hotspot position and remove all vehicle/AI map hotspots.
function IASituation:updateHotspots()
	if self.loadStep ~= 5 or self.vehicle == nil or self.vehicle.vehicle == nil then
		return
	end
	if not (self.vehicle.vehicle.getIsAIActive and self.vehicle.vehicle:getIsAIActive()) then
		return
	end

	self:safePcall("updateHotspots", function()
		--if self.vehicle.npcPositionX ~= nil and self.vehicle.npcPositionY ~= nil and self.vehicle.npcPositionZ ~= nil then
		--	drawDebugPoint(self.vehicle.npcPositionX, self.vehicle.npcPositionY, self.vehicle.npcPositionZ, 0, 255, 0, 150, false)
		--end
		-- Spot is only created when world coords are finite (IANeighbour:updateNPCSpot); use game vehicle position while AI is active.
		-- Skip while on-foot NPC is visible (spot set once in showNPC); still strip vehicle/AI map hotspots below.
		if not self.npcVisibleWhilePaused then
			self.neighbour:updateNPCSpot(self.vehicle.vehicle)
		end
		local function removeVehicleHotspots(gameVehicle)
			if gameVehicle == nil then return end
			--IAprintDebug("IASituation.updateHotspots.removeVehicleHotspots()", string.format(
			--	"[HOTSPOT] AI-active strip mapHotspotPresent=%s mapAIHotspotPresent=%s",
			--	tostring(gameVehicle.mapHotspot ~= nil),
			--	tostring(gameVehicle.spec_aiJobVehicle ~= nil and gameVehicle.spec_aiJobVehicle.mapAIHotspot ~= nil)
			--), nil, gameVehicle, nil)
			gameVehicle:deleteMapHotspot()
			local spec = gameVehicle.spec_aiJobVehicle
			if spec ~= nil and spec.mapAIHotspot ~= nil then
				if g_currentMission ~= nil and g_currentMission.removeMapHotspot then
					g_currentMission:removeMapHotspot(spec.mapAIHotspot)
				end
				if spec.mapAIHotspot.delete then
					spec.mapAIHotspot:delete()
				end
				-- Intentionally NOT setting spec.mapAIHotspot = nil: leave the field as-is so engine-side
				-- ownership/lifecycle remains the single source of truth. delete() above already detaches it.
				--IAprintDebug("IASituation.updateHotspots.removeVehicleHotspots()", "[HOTSPOT] mapAIHotspot REMOVED", nil, gameVehicle, nil)
			end
			--IAprintDebug("IASituation.updateHotspots.removeVehicleHotspots()", string.format(
			--	"[HOTSPOT] post-strip mapHotspotPresent=%s",
			--	tostring(gameVehicle.mapHotspot ~= nil)
			--), nil, gameVehicle, nil)
		end
		removeVehicleHotspots(self.vehicle.vehicle)
		if self.attachmentBack ~= nil then
			removeVehicleHotspots(self.attachmentBack.vehicle)
		end
		if self.attachmentFront ~= nil then
			removeVehicleHotspots(self.attachmentFront.vehicle)
		end
	end)
end

-- Apply the neighbour's appearance style to the AI vehicle's in-cab character (driver model).
-- Delegates to IANeighbourVehicle:applyVehicleCharacterStyle(); one-shot guard for situation-level callers (e.g. isRestored path).
function IASituation:applyVehicleCharacterStyle()
	if self.vehicleCharacterStyleApplied then
		return
	end
	if self.vehicle ~= nil and self.vehicle.applyVehicleCharacterStyle then
		self:safePcall("applyVehicleCharacterStyle", function()
			self.vehicle:applyVehicleCharacterStyle()
		end)
	end
	self.vehicleCharacterStyleApplied = true
end

-- True if encounter should use stop/resume (restart job when player leaves); false to use block/pause (aiBlock, aiContinue).
-- Use stop when jobType is CULTIVATE, HARROW, HARVEST, or PLOW; otherwise use block.
function IASituation:checkAIStopOrBlock()
	if self.jobType == IAFieldwork.JobType.CULTIVATE or self.jobType == IAFieldwork.JobType.HARVEST or self.jobType == IAFieldwork.JobType.PLOW or self.jobType == IAFieldwork.JobType.HARROW then
		return true
	end
	return false
end

--- Once per managePositioning() when loadStep == 5 (same ~5s cadence as IANeighbours.game5Seconds).
function IASituation:_fieldworkAdvanceManagePositioningTick()
	self._fieldworkManagePositioningTick = (self._fieldworkManagePositioningTick or 0) + 1
end

--- After encounter resume: block "AI inactive → complete" until enough positioning ticks have passed.
function IASituation:_fieldworkScheduleInactiveCompleteGraceAfterResume()
	local t = self._fieldworkManagePositioningTick or 0
	local want = t + IASituation.FIELDWORK_POST_RESTART_INACTIVE_GRACE_TICKS
	if self._fieldworkInactiveCompleteAllowTick == nil or want > self._fieldworkInactiveCompleteAllowTick then
		self._fieldworkInactiveCompleteAllowTick = want
	end
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:_fieldworkScheduleInactiveCompleteGraceAfterResume() id=%s allowCompleteAtTick>=%s (manageTick=%s)",
			tostring(self.id),
			tostring(self._fieldworkInactiveCompleteAllowTick),
			tostring(t)
		))
	end
end

function IASituation:_fieldworkClearInactiveCompleteGrace()
	-- Only call when tearing down fieldwork (step 6) — never because AI briefly reported active.
	self._fieldworkInactiveCompleteAllowTick = nil
end

--- @return boolean true if "AI inactive" may run completeFieldwork (grace elapsed or no recent restart).
function IASituation:_fieldworkMayCompleteWhileAiInactive()
	if self._fieldworkInactiveCompleteAllowTick == nil then
		return true
	end
	local t = self._fieldworkManagePositioningTick or 0
	if t >= self._fieldworkInactiveCompleteAllowTick then
		return true
	end
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:_fieldworkMayCompleteWhileAiInactive() id=%s DEFER inactive complete tick=%s need>=%s",
			tostring(self.id),
			tostring(t),
			tostring(self._fieldworkInactiveCompleteAllowTick)
		))
	end
	return false
end

--- While AI is active: count consecutive slow managePositioning ticks; @return true if we should force-complete (long no-move).
function IASituation:_fieldworkTickNoMovementWhileAiRunning(speedKph, aiJobPaused)
	if speedKph < IASituation.FIELDWORK_NO_MOVE_SPEED_KPH and not aiJobPaused then
		self._fieldworkNoMoveTick = (self._fieldworkNoMoveTick or 0) + 1
		if self._fieldworkNoMoveTick > IASituation.FIELDWORK_NO_MOVE_TICKS_MAX then
			return true
		end
	else
		self._fieldworkNoMoveTick = 0
	end
	return false
end

function IASituation:_fieldworkStopAiBeforeSituationComplete()
	self:safePcall("fieldwork stop AI before situation complete", function()
		if self.vehicle ~= nil and self.farmlandId ~= nil and self.vehicle.vehicle ~= nil
			and self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive() then
			self.vehicle:resumeAIJob(self.farmlandId)
			self.vehicle:stopAIJob()
		end
	end)
end

function IASituation:_fieldworkCompleteFieldworkAndGoToStep6(safeTagPrefix)
	self.playerHoldActive = false
	self._fieldworkNoMoveTick = 0
	self._fieldworkInactiveRepositionAttempts = 0
	self:_fieldworkClearInactiveCompleteGrace()
	self:safePcall(safeTagPrefix .. " completeFieldwork", function() self:completeFieldwork() end)
	self:safePcall(safeTagPrefix .. " unblockFarmland", function() self:unblockFarmland() end)
	self.loadStep = 6
end

--- AI never stayed active after resume / grace (e.g. field job fails on border): stop stray AI, reset encounter flags, allow border pose again, rerun steps 1–4.
function IASituation:_fieldworkRestartFieldworkSetupFromStepOne(reason)
	self._fieldworkInactiveRepositionAttempts = (self._fieldworkInactiveRepositionAttempts or 0) + 1
	self:_fieldworkStopAiBeforeSituationComplete()
	self:_fieldworkClearInactiveCompleteGrace()
	self._fieldworkNoMoveTick = 0
	-- New attempt: previous active time no longer counts toward the respawn-skip threshold.
	self.aiJobActiveElapsedMs = 0
	self.playerHoldActive = false
	self.npcVisibleWhilePaused = false
	self.pausedAtZeroSpeedTimer = 0
	self.encounterSpeedAboveHalfTimer = 0
	self.npcPostShowPoseSyncFrames = 0
	self.currentAiJob = nil
	self.iaBorderSpawnPoseApplied = false
	self.vehicleCharacterStyleApplied = false
	self.initCommitted = false
	self.loadStep = 1
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:_fieldworkRestartFieldworkSetupFromStepOne() id=%s attempt=%s/%s reason=%s",
			tostring(self.id),
			tostring(self._fieldworkInactiveRepositionAttempts),
			tostring(IASituation.FIELDWORK_INACTIVE_REPOSITION_MAX_ATTEMPTS),
			tostring(reason)
		))
	end
end

-- When player is within PAUSE_ENTER_DISTANCE: block AI (aiBlock), show NPC after 3s at 0 kph.
-- When player leaves PAUSE_LEAVE_DISTANCE: resumeAIJob() unblocks (aiContinue). Missing parts to be investigated later.
function IASituation:manageVehicleEncounter(dt)
	if self.loadStep ~= 5 or self.vehicle == nil or self.vehicle.vehicle == nil then
		return
	end
	-- Run when AI is active (so we can block) or when we're holding (playerHoldActive) so we can resume on leave
	if not (self.vehicle.vehicle.getIsAIActive and self.vehicle.vehicle:getIsAIActive()) and not self.playerHoldActive then
		return
	end
	-- Only stop/block when the player is on foot (not in a vehicle)
	local playerVehicle = g_localPlayer and g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if self.fieldworkPauseSuppressedAfterConversation then
		if playerVehicle ~= nil or not self:isPlayerNearbyAtPosition(IASituation.PAUSE_ENTER_DISTANCE) then
			self.fieldworkPauseSuppressedAfterConversation = false
		end
	end
	if self:isPlayerNearbyAtPosition(IASituation.PAUSE_ENTER_DISTANCE) and playerVehicle == nil
		and not self.fieldworkPauseSuppressedAfterConversation then
		--print("--- IASituation:manageVehicleEncounter() "..self.id.." - Player is nearby at position")
		if self:checkAIStopOrBlock() then
			local aiActive = false
			self:safePcall("manageVehicleEncounter getIsAIActive (stop path)", function()
				aiActive = self.vehicle.vehicle:getIsAIActive()
			end)
			if aiActive then
				self:safePcall("manageVehicleEncounter stopAIJob", function() self.vehicle:stopAIJob() end)
				if self.vehicle.setEngineAndLightsOnForPlayerNearby then
					self:safePcall("manageVehicleEncounter setEngineAndLightsOnForPlayerNearby", function()
						self.vehicle:setEngineAndLightsOnForPlayerNearby()
					end)
				end
			end
			self.playerHoldActive = true
		else
			self:safePcall("manageVehicleEncounter pauseAIJob", function() self.vehicle:pauseAIJob(dt) end)
			self.playerHoldActive = true
		end
		local speedHolder = { kph = 999 }
		self:safePcall("manageVehicleEncounter getLastSpeed", function()
			if self.vehicle.vehicle.getLastSpeed then
				speedHolder.kph = self.vehicle.vehicle:getLastSpeed()
			end
		end)
		local speedKph = speedHolder.kph
		-- Speed noise while "stopped" often exceeds 0.5 kph briefly; that used to hide the on-foot NPC and reset the 3s timer every time.
		if speedKph >= 0.5 then
			self.encounterSpeedAboveHalfTimer = (self.encounterSpeedAboveHalfTimer or 0) + dt
		else
			self.encounterSpeedAboveHalfTimer = 0
		end
		if speedKph >= 0.5 then
			local hideForApproach = not self.npcVisibleWhilePaused
			local hideOnFoot = self.npcVisibleWhilePaused
				and (speedKph >= IASituation.NPC_ONFOOT_HIDE_SPEED_KPH
					or (self.encounterSpeedAboveHalfTimer or 0) >= IASituation.NPC_ONFOOT_HIDE_SUSTAINED_SEC)
			if hideForApproach or hideOnFoot then
				if self.neighbour and self.neighbour.hideNPC then
					self:safePcall("manageVehicleEncounter hideNPC (moving)", function() self.neighbour:hideNPC() end)
				end
				self.npcVisibleWhilePaused = false
				self.pausedAtZeroSpeedTimer = 0
				self.encounterSpeedAboveHalfTimer = 0
				self.npcPostShowPoseSyncFrames = 0
			end
		else
			-- Vehicle stopped: beside-vehicle coords cached in IANeighbourVehicle:update(); one-shot apply at show only (see below).
			-- After 3s at 0 kph while blocked/stopped, show NPC (driver visible)
			self.pausedAtZeroSpeedTimer = self.pausedAtZeroSpeedTimer + dt
			if self.pausedAtZeroSpeedTimer >= 3000 and not self.npcVisibleWhilePaused then
				self.npcVisibleWhilePaused = true
				if self.neighbour and self.neighbour.showNPC then
					-- neighbour:update runs situation before vehicle:update; refresh beside-vehicle sample now so spawn uses current root transform
					self:safePcall("manageVehicleEncounter findRelativePositionNpc before show", function()
						if self.vehicle ~= nil and self.vehicle.findRelativePositionNpc ~= nil
							and self.vehicle.vehicle ~= nil and self.vehicle.vehicle.rootNode ~= nil then
							self.vehicle:findRelativePositionNpc()
						end
					end)
					if self.vehicle.npcPositionX ~= nil and self.vehicle.npcPositionY ~= nil and self.vehicle.npcPositionZ ~= nil and self.vehicle.npcRotation ~= nil then
						self:safePcall("manageVehicleEncounter updateNPCPosition before show", function()
							self.neighbour:updateNPCPosition(self.vehicle.npcPositionX, self.vehicle.npcPositionY, self.vehicle.npcPositionZ, self.vehicle.npcRotation)
						end)
					end
					self:safePcall("manageVehicleEncounter showNPC (paused)", function() self.neighbour:showNPC() end)
					self.npcPostShowPoseSyncFrames = IASituation.NPC_POST_SHOW_POSE_SYNC_FRAMES
				end
			end
		end
		-- While on-foot NPC is visible: do not re-sync position each frame (avoids jitter / spot thrash); hide in-cab driver still.
		if self.npcVisibleWhilePaused and self.neighbour then
			self:safePcall("manageVehicleEncounter setCharacterVisibility", function()
				local vehicleCharacter = self.vehicle.vehicle:getVehicleCharacter()
				if vehicleCharacter then
					vehicleCharacter:setCharacterVisibility(false)
				end
			end)
		end
	elseif not self:isPlayerNearbyAtPosition(IASituation.PAUSE_LEAVE_DISTANCE) then
		if self.playerHoldActive then
			self:resumeFieldworkAfterProximityHold()
		end
	end
end

--- Hide on-foot NPC, restart or unblock fieldwork AI, clear encounter timers. Used when player leaves PAUSE_LEAVE_DISTANCE while hold is active (same logic as that branch in manageVehicleEncounter).
function IASituation:resumeFieldworkAfterProximityHold()
	if self.vehicle == nil or self.vehicle.vehicle == nil then
		return
	end
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:resumeFieldworkAfterProximityHold() id=%s job=%s holdBefore=%s aiBefore=%s",
			tostring(self.id),
			tostring(self.jobType),
			tostring(self.playerHoldActive),
			tostring(self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive())
		))
	end
	-- Hide NPC directly when vehicle is about to move again
	if self.neighbour and self.neighbour.hideNPC then
		self:safePcall("manageVehicleEncounter hideNPC (resume)", function() self.neighbour:hideNPC() end)
	end
	if self:checkAIStopOrBlock() and self.farmland ~= nil and self.farmland.field ~= nil then
		self:safePcall("manageVehicleEncounter startAIJob (resume)", function()
			self.currentAiJob = self.vehicle:startAIJob(self.jobType, self.farmland.field.posX, self.farmland.field.posZ, self.farmlandId)
		end)
		if IANeighbours ~= nil and IANeighbours.debug then
			print("--- IASituation:resumeFieldworkAfterProximityHold() used startAIJob (stop/block path)")
		end
	else
		self:safePcall("manageVehicleEncounter resumeAIJob", function()
			self.vehicle:resumeAIJob(self.farmlandId)
		end)
		if IANeighbours ~= nil and IANeighbours.debug then
			print("--- IASituation:resumeFieldworkAfterProximityHold() used resumeAIJob (pause path)")
		end
	end
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:resumeFieldworkAfterProximityHold() done aiAfter=%s holdAfter=false",
			tostring(self.vehicle.vehicle.getIsAIActive ~= nil and self.vehicle.vehicle:getIsAIActive())
		))
	end
	self:_fieldworkScheduleInactiveCompleteGraceAfterResume()
	self.playerHoldActive = false
	self.npcVisibleWhilePaused = false
	self.pausedAtZeroSpeedTimer = 0
	self.encounterSpeedAboveHalfTimer = 0
	self.npcPostShowPoseSyncFrames = 0
end

--- After Goodbye: same resume as leaving PAUSE_LEAVE_DISTANCE, plus suppress proximity re-pause while player stays inside PAUSE_ENTER_DISTANCE.
function IASituation:resumeFieldworkAfterConversation()
	if self.loadStep ~= 5 or self.vehicle == nil or self.vehicle.vehicle == nil then
		if IANeighbours ~= nil and IANeighbours.debug then
			print(string.format(
				"--- IASituation:resumeFieldworkAfterConversation() SKIP id=%s loadStep=%s",
				tostring(self.id),
				tostring(self.loadStep)
			))
		end
		return
	end
	if IANeighbours ~= nil and IANeighbours.debug then
		print(string.format(
			"--- IASituation:resumeFieldworkAfterConversation() id=%s hold=%s willResume=%s",
			tostring(self.id),
			tostring(self.playerHoldActive),
			tostring(self.playerHoldActive == true)
		))
	end
	self.fieldworkPauseSuppressedAfterConversation = true
	if self.playerHoldActive then
		self:resumeFieldworkAfterProximityHold()
	end
end

function IASituation:startConversation()
	if IANeighbours.debug then
		print("--- IASituation:startConversation() "..self.id)
	end
	self.fieldworkPauseSuppressedAfterConversation = false
	if self.conversation ~= nil then
		self.conversation:start(0, self.neighbour.name or "Neighbour", self)
	end
end
function IASituation:hideConversation()
	if IANeighbours.debug then
		print("--- IASituation:hideConversation() "..self.id)
	end

	if self.conversation ~= nil then
		self.conversation:stop()
	end
	self.conversationCurrentId = 0
	self.conversationNextOptions = nil
	if self.activeDialog ~= nil then
		g_gui:closeDialog(self.activeDialog)
		self.activeDialog = nil
	end
end

--- Build main menu options (smalltalks by role/job + Goodbye) and store on conversation. Called at init after loading main conversation.
function IASituation:buildConversationMainMenuOptions()
	if self.conversation == nil then
		return
	end
	local roleKey = "default"
	local jobKey = "default"
	if self.config then
		if self.config.characterRoles and self.config.characterRoles[1] then
			roleKey = self.config.characterRoles[1]
		end
		if self.config.characterJobs and self.config.characterJobs[1] then
			jobKey = self.config.characterJobs[1]
		end
	end
	self.conversation.mainMenuOptions = IAConversation.buildMainMenuOptionsFromRoleAndJob(roleKey, jobKey)
end

--- Call when player selects an option at a choice point. Forwards to conversation (handles advance + dialog).
-- @param entryId string|number id of the chosen entry (from situation.conversation.nextOptions[i].id)
function IASituation:selectConversationOption(entryId)
	if self.conversation ~= nil then
		self.conversation:selectOption(entryId)
	end
end

function IASituation:sendDialogAnswer(text)

	--print("--- IASituation:sendDialogAnswer() "..self.id.." - "..text)

	self.dialogMessageId = self.dialogMessageId + 1
	table.insert(self.dialogMessages, {id = self.dialogMessageId, text = text, sender = "You"})
	--print("--- IASituation:sendDialogAnswer() "..self.id.." - Dialog Message ID: "..tostring(self.dialogMessageId))
end
function IASituation:mergeMessagesFromXML(messages)
	if messages == nil or #messages == 0 then
		return 0
	end
	
	-- Filter messages with IDs higher than current dialogMessageId
	local newMessages = {}
	local highestId = self.dialogMessageId
	
	for _, message in ipairs(messages) do
		if message.id ~= nil and message.id > self.dialogMessageId then
			-- Check for duplicates
			local isDuplicate = false
			for _, existingMessage in ipairs(self.dialogMessages) do
				if existingMessage.id == message.id then
					isDuplicate = true
					break
				end
			end
			
			if not isDuplicate then
				table.insert(newMessages, message)
				if message.id > highestId then
					highestId = message.id
				end
			end
		end
	end
	
	-- Sort new messages by ID to maintain order
	table.sort(newMessages, function(a, b)
		return (a.id or 0) < (b.id or 0)
	end)
	
	-- Add new messages to dialogMessages
	for _, message in ipairs(newMessages) do
		table.insert(self.dialogMessages, message)
	end
	
	-- Update dialogMessageId to the highest ID found
	if highestId > self.dialogMessageId then
		self.dialogMessageId = highestId
	end
	
	-- Update dialog GUI if it's open
	if #newMessages > 0 then
		self:updateDialogWithNewMessages(newMessages)
	end
	
	if IANeighbours.debug then
		print("--- IASituation:mergeMessagesFromXML() "..self.id.." - Added "..tostring(#newMessages).." new messages, dialogMessageId now: "..tostring(self.dialogMessageId))
	end
	
	return #newMessages
end
function IASituation:updateDialogWithNewMessages(newMessages)
	if self.activeDialog == nil or self.dialogController == nil then
		return
	end
	
	-- Add each new message to the dialog GUI
	for _, message in ipairs(newMessages) do
		if message.text ~= nil and message.sender ~= nil then
			self.dialogController:addMessage(message.sender, message.text)
		end
	end
end
function IASituation:completeFieldwork()
	if IANeighbours ~= nil and IANeighbours.debug then
		print("--- IASituation:completeFieldwork() "..self.id)
	end

	local function foldIfFoldable(gameVehicle)
		if gameVehicle == nil then return end
		local spec = gameVehicle.spec_foldable
		if spec == nil or #spec.foldingParts == 0 then return end
		gameVehicle:setFoldState(spec.turnOnFoldDirection, true)
	end
	foldIfFoldable(self.vehicle and self.vehicle.vehicle or nil)
	if self.attachmentBack ~= nil then foldIfFoldable(self.attachmentBack.vehicle) end
	if self.attachmentFront ~= nil then foldIfFoldable(self.attachmentFront.vehicle) end

	if self.vehicle ~= nil and self.vehicle.emptyFillUnits ~= nil then
		self.vehicle:emptyFillUnits()
	end
	if self.attachmentBack ~= nil and self.attachmentBack.emptyFillUnits ~= nil then
		self.attachmentBack:emptyFillUnits()
	end
	if self.attachmentFront ~= nil and self.attachmentFront.emptyFillUnits ~= nil then
		self.attachmentFront:emptyFillUnits()
	end

	--for _, field in ipairs (g_fieldManager:getFields()) do

	if self.farmlandId ~= nil and self.farmland ~= nil and self.farmland.field ~= nil and IAFieldwork ~= nil and IAFieldwork.enqueueCompleteFieldworkFieldUpdate ~= nil then
		IAFieldwork.enqueueCompleteFieldworkFieldUpdate(self.farmland.field, self.jobType, self.seedFruitTypeIndex, self.fertilizeSprayTypeIndex)
	end
end
function IASituation:blockFarmland()
	if IANeighbours.debug then
		print("--- IASituation:blockFarmland() "..self.id)
	end

	if self.farmlandId ~= nil and self.farmland ~= nil and self.vehicle ~= nil then
		-- Save the original owner so we can restore it in unblockFarmland.
		-- This prevents player-owned fields from becoming unowned after NPC fieldwork completes.
		self._preBlockFarmlandOwnerFarmId = self.farmland.farmId
		self._preBlockFarmlandFieldStateOwnerFarmId = self.farmland.field.fieldState.ownerFarmId
		g_farmlandManager:setLandOwnership(self.farmland.id, self.vehicle.farmId)
		self.farmland:setOwnerFarmId( self.vehicle.farmId)
		-- NPC index is managed by IANeighbours:updateFarmlands() on the 5-second cycle.
		--self.farmland.showOnFarmlandsScreen = false
		self.farmland.field.fieldState.ownerFarmId = self.vehicle.farmId
	end
end
function IASituation:unblockFarmland()
	if IANeighbours.debug then
		print("--- IASituation:unblockFarmland() "..self.id)
	end

	if self.farmlandId ~= nil and self.farmland ~= nil and self.vehicle ~= nil then
		-- Restore the original owner that was saved in blockFarmland.
		-- If the field was player-owned before the NPC started, it stays player-owned.
		local restoreFarmId = self._preBlockFarmlandOwnerFarmId or 0
		local restoreFieldStateFarmId = self._preBlockFarmlandFieldStateOwnerFarmId or 0
		g_farmlandManager:setLandOwnership(self.farmland.id, restoreFarmId)
		self.farmland:setOwnerFarmId(restoreFarmId)
		-- NPC index is managed by IANeighbours:updateFarmlands() on the 5-second cycle.
		--self.farmland.showOnFarmlandsScreen = true
		self.farmland.field.fieldState.ownerFarmId = restoreFieldStateFarmId
		-- Clear saved state to avoid stale values on next use
		self._preBlockFarmlandOwnerFarmId = nil
		self._preBlockFarmlandFieldStateOwnerFarmId = nil
	end
end

-- Default distance (meters) within which the player is considered "nearby" for blocking situation changes
IASituation.PLAYER_NEARBY_DISTANCE = 80
-- Pause vehicle AI when player enters this distance (meters); resume when player leaves PAUSE_LEAVE_DISTANCE.
IASituation.PAUSE_ENTER_DISTANCE = 20
IASituation.PAUSE_LEAVE_DISTANCE = 35
-- While on-foot NPC is visible: brief speed noise (>= 0.5 kph) must not hide and restart the 3s timer.
IASituation.NPC_ONFOOT_HIDE_SPEED_KPH = 3.0
IASituation.NPC_ONFOOT_HIDE_SUSTAINED_SEC = 0.85
IASituation.NPC_POST_SHOW_POSE_SYNC_FRAMES = 10

--- Fieldwork progress / stuck handling (managePositioning runs on IANeighbours ~5s real-time tick).
IASituation.FIELDWORK_NO_MOVE_SPEED_KPH = 2
--- Number of consecutive slow ticks before we stop AI and run completeFieldwork (~5s per tick).
IASituation.FIELDWORK_NO_MOVE_TICKS_MAX = 10
--- After startAIJob/resumeAIJob from encounter resume: minimum managePositioning ticks before "AI inactive" may end the situation (avoids false complete while AI spawns).
IASituation.FIELDWORK_POST_RESTART_INACTIVE_GRACE_TICKS = 6
--- After grace, if AI is still inactive: rerun managePositioning from step 1 (border spawn + attach + start) this many times before completeFieldwork (large maps / border field detection).
--- Kept at 1 (one full retry): if the AI fails to start even after a fresh border spawn + attach, the field is
--- likely unworkable for this vehicle (e.g. already harvested) and further retries would loop forever.
IASituation.FIELDWORK_INACTIVE_REPOSITION_MAX_ATTEMPTS = 1
--- If the AI job was active for at least this many real ms before going inactive, treat it as a normal completion
--- (loadStep 5 -> 6) instead of trying to respawn the convoy from step 1. The step-1 respawn is meant only for
--- "AI failed to ever start / immediately gave up" cases; once the job has been running long enough, an inactive
--- AI just means the fieldwork is finished.
IASituation.AI_JOB_RESPAWN_MAX_DURATION_MS = 10000

-- Returns true if the player is within maxDistance of the situation's real position.
-- Position is taken automatically inside: vehicle world position if loaded, else neighbour real position, else situation place position.
function IASituation:isPlayerNearbyAtPosition(maxDistance)
	if g_localPlayer == nil then
		return false
	end
	local x, y, z
	if self.vehicle ~= nil and self.vehicle.vehicle ~= nil and self.vehicle.vehicle.rootNode ~= nil then
		x, y, z = getWorldTranslation(self.vehicle.vehicle.rootNode)
	elseif self.neighbour ~= nil and self.neighbour.realPositionX ~= nil and self.neighbour.realPositionZ ~= nil then
		x = self.neighbour.realPositionX
		y = self.neighbour.realPositionY or 0
		z = self.neighbour.realPositionZ
	else
		x = self.positionX
		y = self.positionY or 0
		z = self.positionZ
	end
	if x == nil or z == nil then
		return false
	end
	local dist = maxDistance or IASituation.PLAYER_NEARBY_DISTANCE
	local d = distanceToPlayer(x, y or 0, z)
	if d == nil then
		return false
	end
	return d <= dist
end