--
-- FS25 - InteractiveNeighbours - Neighbour Vehicle Class
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 25.10.2022
-- @Version: 1.0.0.1
--

IANeighbourVehicle = {}
IANeighbourVehicle._mt = Class(IANeighbourVehicle)
IANeighbourVehicle.isActive = false
IANeighbourVehicle.uniqueId = nil
IANeighbourVehicle.xmlFilename = nil
IANeighbourVehicle.xmlFilenameAttachmentBack = nil
IANeighbourVehicle.xmlFilenameAttachmentFront = nil
IANeighbourVehicle.positionX = 0
IANeighbourVehicle.positionY = 0
IANeighbourVehicle.positionZ = 0
IANeighbourVehicle.rotation = 0
IANeighbourVehicle.farmId = nil
IANeighbourVehicle.activeSituationId = nil
IANeighbourVehicle.neighbour = nil
IANeighbourVehicle.externalId = nil
IANeighbourVehicle.npcOffsetX = nil
IANeighbourVehicle.npcOffsetY = nil
IANeighbourVehicle.npcOffsetZ = nil
IANeighbourVehicle.npcOffsetRotation = nil
IANeighbourVehicle.initialized = false
IANeighbourVehicle.vehicle = nil
IANeighbourVehicle.realPositionX = nil
IANeighbourVehicle.realPositionY = nil
IANeighbourVehicle.realPositionZ = nil
IANeighbourVehicle.realRotation = nil
IANeighbourVehicle.vehicleIsVisible = true
IANeighbourVehicle.npcPositionX = nil
IANeighbourVehicle.npcPositionY = nil
IANeighbourVehicle.npcPositionZ = nil
IANeighbourVehicle.npcRotation = nil
IANeighbourVehicle.currentJob = nil
IANeighbourVehicle.jobType = nil
IANeighbourVehicle.jobTargetX = nil
IANeighbourVehicle.jobTargetZ = nil
IANeighbourVehicle.aiJobPaused = false
IANeighbourVehicle.aiJobStopped = false
IANeighbourVehicle.attachmentBack = nil
IANeighbourVehicle.attachmentFront = nil
IANeighbourVehicle.type = nil
IANeighbourVehicle.category = nil
IANeighbourVehicle.colorIndex = nil
IANeighbourVehicle.fullLoaded = false
IANeighbourVehicle.situation = nil  -- reference to IASituation when this vehicle is in an active situation (set/cleared with activeSituationId)
-- Off-situation parking slot (homebase/shed or public_place); cleared when vehicle joins a situation
IANeighbourVehicle.parkingPlaceId = nil
IANeighbourVehicle.parkingPlaceSemantic = nil
IANeighbourVehicle.presenceState = nil
IANeighbourVehicle.isBorrowedByPlayer = false
-- Borrow: reserved homebase slot + world pose when player took the vehicle (persisted in outbound XML)
IANeighbourVehicle.borrowReturnParkingPlaceId = nil
IANeighbourVehicle.borrowReturnParkingPlaceSemantic = nil
IANeighbourVehicle.borrowPickupPositionX = nil
IANeighbourVehicle.borrowPickupPositionY = nil
IANeighbourVehicle.borrowPickupPositionZ = nil
IANeighbourVehicle.borrowPickupRotation = nil

--- Lowercase xml path substrings: park unfolded when detached (not folded). Extend as needed.
IANeighbourVehicle.UNFOLDED_PARKING_XML_PATTERNS = {
	"aresxl.xml",
	"aresxl/",
}

-- Create a new Neighbour Vehicle instance
-- @param string uniqueId - Unique ID of the vehicle (optional, can be nil)
-- @param number farmId - Farm ID
-- @param IANeighbour neighbour - Parent neighbour instance
function IANeighbourVehicle.new(uniqueId, farmId, neighbour)
	local self = setmetatable({}, IANeighbourVehicle._mt)
	
	self.uniqueId = uniqueId
	self.farmId = farmId or 1
	self.neighbour = neighbour
	
	-- Initialize all fields to nil/default values
	self.xmlFilename = nil
	self.externalId = nil
	self.type = nil
	self.category = nil
	self.colorIndex = nil
	
	-- Internal state
	self.initialized = false
	self.fullLoaded = false
	self.vehicle = nil
	
	-- Real position tracking (updated from vehicle)
	self.realPositionX = nil
	self.realPositionY = nil
	self.realPositionZ = nil
	self.realRotation = nil
	self.vehicleShouldBeVisible = true
	self.vehicleIsVisible = true

	self.npcPositionX = nil
	self.npcPositionY = nil
	self.npcPositionZ = nil
	self.npcRotation = nil
	-- nil = use vehicle size-based default when vehicle is available (no XML overwrite)
	self.npcOffsetX = nil
	self.npcOffsetY = 0
	self.npcOffsetZ = nil
	self.npcOffsetRotation = 0
	
	-- AI Job state
	self.currentJob = nil
	self.jobType = nil
	self.jobTargetX = nil
	self.jobTargetZ = nil
	self.aiJobPaused = false
	self.parkingPlaceId = nil
	self.parkingPlaceSemantic = nil
	self.presenceState = {
		owner = "none", mode = "hidden", pose = nil, attachment = nil, parkingPlaceId = nil
	}
	self.isBorrowedByPlayer = false
	self.borrowReturnParkingPlaceId = nil
	self.borrowReturnParkingPlaceSemantic = nil
	self.borrowPickupPositionX = nil
	self.borrowPickupPositionY = nil
	self.borrowPickupPositionZ = nil
	self.borrowPickupRotation = nil
	return self
end

--- Clear sticky off-situation parking (called when vehicle enters an active situation).
function IANeighbourVehicle:clearOffSituationParking()
	self.parkingPlaceId = nil
	self.parkingPlaceSemantic = nil
end

-- Initialize the vehicle (get reference to actual vehicle object)
-- @param function callbackUniqueId - Callback function(uniqueId, externalId, ia_vehicle)
function IANeighbourVehicle:initialize(callbackUniqueId)
	if self.initialized then
		IAprintDebug("IANeighbourVehicle:initialize()", "Vehicle "..tostring(self.uniqueId).." already initialized", self.neighbour, self, nil)
		if callbackUniqueId ~= nil then
			callbackUniqueId(self.uniqueId, self.externalId, self)
		end
		return
	end
	
	-- If uniqueId is not set but externalId is, try to look it up from mapping
	if self.uniqueId == nil and self.externalId ~= nil then
		self.uniqueId = IANeighbours:getVehicleUniqueIdByExternalId(self.externalId)
		if self.uniqueId ~= nil then
			IAprintDebug("IANeighbourVehicle:initialize()", "Looked up uniqueId from mapping: "..tostring(self.externalId).." -> "..tostring(self.uniqueId), self.neighbour, self, nil)
		end
	end
	
	IAprintDebug("IANeighbourVehicle:initialize()", "Initialize vehicle: "..tostring(self.uniqueId).." with xmlfilename: "..tostring(self.xmlFilename), self.neighbour, self, nil)
	
	local loaded = false
	-- If uniqueId exists, try to load existing vehicle
	if self.uniqueId ~= nil then
		loaded = self:loadVehicleById(self.uniqueId)
		
		if loaded and self.vehicle ~= nil then
			if callbackUniqueId ~= nil then
				callbackUniqueId(self.uniqueId, self.externalId, self)
			end
			--self.xmlFilenameAttachmentBack = "data/vehicles/krampe/bigBodyS750/bigBodyS750.xml"
			--self:spawnAttachmentBack(function(uniqueId)
			--	print("--- IANeighbourVehicle:initialize() - Spawned attachment: "..tostring(uniqueId))
--
			--	self:loadAttachmentBackById(uniqueId)
			--end)
			IAprintDebug("IANeighbourVehicle:initialize()", "Initialized vehicle: "..tostring(self.uniqueId), self.neighbour, self, nil)
		end
	end

	if loaded == false then
		-- If no uniqueId, spawn a new vehicle
		if self.xmlFilename == nil then
			IAprintDebug("IANeighbourVehicle:initialize()", "Cannot spawn: xmlFilename is nil", self.neighbour, self, nil)
			return
		end
		
		self:spawn((function(uniqueId)
			if callbackUniqueId ~= nil then
				callbackUniqueId(uniqueId, self.externalId, self)
			end
		end))
	end

	




	self.initialized = true

	
	--g_currentMission.hud:showInGameMessage("Interactive Neighbours", string.format("\nHallo Test"), -1, nil, nil, nil)
	--g_gui:showDialog("IADialogGUI")

	--local pl = Player.new(true,true)
	--pl.load()
	
	--printObj(pl,2,"pl")
--	printObj(pl.getPosition(),2,"pl.getPosition")
	--g_currentMission.playerSystem:addPlayer(pl)
	
	--dataS/character/playerM/playerM.xml
	--local guy = HumanModel.new()
	--guy:load("dataS/character/playerM/playerM.xml",false,true,true,(function(var1,var2,var3,var4)
	--	print("--- IANeighbourVehicle:handleHumanCreated() - Human created")
	--	printObj(guy.rootNode,1,"guy.rootNode")

	--	local guyGraphic = HumanGraphicsComponent.new()
	--	guyGraphic:setModel(guy)
	--	printObj(guyGraphic,1,"guyGraphic")
	--	setTranslation(guy.rootNode, self.positionX+5, self.positionY+1, self.positionZ+5)
	--	local x, y, z = getTranslation(guy.rootNode)
	--	print("--- IANeighbourVehicle:handleHumanCreated() - Translation: "..tostring(x)..", "..tostring(y)..", "..tostring(z))

	--end),self,{xmlFile})
	--printObj(guy,1,"guy")

end


-- Update the vehicle (only if already initialized)
function IANeighbourVehicle:update(dt,gameSeconds)
	if not self.initialized then
		return
	end
	
	
	if self.vehicle == nil then
		return
	end
	if self.fullLoaded == false then
		return
	end
	if self.vehicle.rootNode == nil then
		self.vehicle = nil
		self.fullLoaded = false
		self.initialized = false
		return
	end

	--self.vehicle:setRandomVehicleCharacter()

	-- Update real position from vehicle
	local x, y, z = getWorldTranslation(self.vehicle.rootNode)
	self.realPositionX = x
	self.realPositionY = y
	self.realPositionZ = z
	
	local dirX, _, dirZ = localDirectionToWorld(self.vehicle.rootNode, 0, 0, 1)
	self.realRotation = MathUtil.getYRotationFromDirection(dirX, dirZ)

	self:findRelativePositionNpc()
end

--- Apply NPC offset from vehicle size for calculation. Auto calculation has priority over XML-loaded values (XML is loaded but not used for NPC position).
-- Sets npcOffsetX from vehicle.size.width; Z offset is not used (kept 0).
function IANeighbourVehicle:applyDefaultNpcOffsetFromVehicleSize()
	if self.vehicle == nil or self.vehicle.size == nil then
		return
	end
	local w = self.vehicle.size.width
	self.npcOffsetX = (type(w) == "number" and w > 0) and (w * 0.5 + 0.5) or 3
	self.npcOffsetZ = 0
end

function IANeighbourVehicle:findRelativePositionNpc()
	-- Apply size-based default NPC offset when not set from XML
	self:applyDefaultNpcOffsetFromVehicleSize()

	-- Assuming you have a vehicle with rootNode
	local vehicleRootNode = self.vehicle.rootNode  -- or your vehicle's transformId
	if vehicleRootNode == nil then
		return
	end
	-- Step 1: Get vehicle's world position
	local vehicleX, vehicleY, vehicleZ = getWorldTranslation(vehicleRootNode)

	-- Step 2: Get forward direction in world space (local 0,0,1 = forward)
	local forwardX, forwardY, forwardZ = localDirectionToWorld(vehicleRootNode, 0, 0, 1)

	-- Step 3: Calculate right direction using cross product (up × forward = right)
	local rightX, rightY, rightZ = MathUtil.crossProduct(0, 1, 0, forwardX, forwardY, forwardZ)

	-- Step 4: Get up direction in world space (local 0,1,0 = up)
	local upX, upY, upZ = localDirectionToWorld(vehicleRootNode, 0, 1, 0)

	-- Step 5: Apply offsets
	-- offsetX: negative = left, positive = right
	-- offsetY: positive = up, negative = down
	-- offsetZ: positive = forward, negative = backward
	local offsetX = self.npcOffsetX or 3  -- units left/right (fallback before vehicle loaded)
	local offsetY = self.npcOffsetY   -- units up/down (0 = same height as vehicle)
	local offsetZ = self.npcOffsetZ or 0   -- no Z offset (NPC beside vehicle, not in front/back)
	-- When situation is at a roadside place, reverse X offset so character spawns on the other side
	if self.situation ~= nil and self.situation.place ~= nil then
		local sem = (self.situation.place.getSemanticType ~= nil and self.situation.place:getSemanticType()) or self.situation.place.type
		if sem ~= nil and string.lower(tostring(sem)) == "roadside" then
			offsetX = (offsetX or 0) * -1
		end
	end

	local characterX = vehicleX + forwardX * offsetZ + rightX * offsetX + upX * offsetY
	local characterY = vehicleY + forwardY * offsetZ + rightY * offsetX + upY * offsetY
	local characterZ = vehicleZ + forwardZ * offsetZ + rightZ * offsetX + upZ * offsetY

	local playerX, playerY, playerZ = g_localPlayer:getPosition()

	local dx = playerX - characterX
	local dy = (playerY or 0) - (characterY or 0)
	local dz = playerZ - characterZ

	self.npcPositionX = MathUtil.round(characterX, 1)
	if offsetY ~= 0 then
		self.npcPositionY = MathUtil.round(characterY, 1)
	else
		self.npcPositionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, characterX, 0, characterZ), 1)
	end
	self.npcPositionZ = MathUtil.round(characterZ, 1)
	-- Yaw from vehicle forward (was incorrectly using vehicleY = world height)
	self.npcRotation = MathUtil.round(MathUtil.getYRotationFromDirection(forwardX, forwardZ) + (self.npcOffsetRotation or 0), 1)
	self.distanceToPlayer = math.sqrt(dx * dx + dy * dy + dz * dz)
	--print("--- IANeighbourVehicle:findRelativePosition() - isActive: "..tostring(self.isActive))
	--print("--- IANeighbourVehicle:findRelativePosition() - NPC Position: "..tostring(self.npcPositionX)..", "..tostring(self.npcPositionY)..", "..tostring(self.npcPositionZ))
	--print("--- IANeighbourVehicle:findRelativePosition() - Distance to target vehicle pos: "..tostring(self.distanceToPlayer))
	-- Now you have the world position for the character
	
end

-- Check if vehicle exists and is valid
-- @return boolean
function IANeighbourVehicle:isValid()
	if self.uniqueId == nil then
		return false
	end
	
	if not self.initialized then
		return false
	end
	
	return self.vehicle ~= nil
end

-- Calculate target position relative to vehicle
-- @param number offsetX - X offset
-- @param number offsetZ - Z offset
-- @return table with x, y, z, dirX, dirY, dirZ
function IANeighbourVehicle:calculateTarget(offsetX, offsetZ)
	if not self:isValid() then
		return nil
	end

	local x, y, z = 0, 0, 0
	local dirX, dirY, dirZ = 1, 0, 0

	x, y, z = getWorldTranslation(self.vehicle.rootNode)
	dirX, _, dirZ = localDirectionToWorld(self.vehicle.rootNode, 0, 0, 1)

	local normX, _, normZ = MathUtil.crossProduct(0, 1, 0, dirX, dirY, dirZ)
	offsetX = tonumber(offsetX) or 0
	offsetZ = tonumber(offsetZ) or 0
	x = x + dirX * offsetZ + normX * offsetX
	z = z + dirZ * offsetZ + normZ * offsetX
	
	local output = {
		x = x,
		y = y,
		z = z,
		dirX = dirX,
		dirY = dirY,
		dirZ = dirZ,
	}
	
	return output
end

-- Build a throwaway PlayerStyle clone for the in-cab driver: copies the neighbour's resolved style
-- (clothing/appearance selections) but forces the gender-appropriate base player model. We clone so we
-- never mutate the neighbour's shared resolvedPlayerStyle (it is also used by the standing character).
-- Returns the original style as a last-resort fallback if the PlayerStyle factory/copy API is missing.
function IANeighbourVehicle:cloneResolvedStyleForCabin(srcStyle, genderXml)
	if srcStyle == nil then
		return nil
	end
	if PlayerStyle == nil or type(PlayerStyle.new) ~= "function" or type(srcStyle.copyFrom) ~= "function" then
		return srcStyle
	end
	local ok, clone = pcall(PlayerStyle.new)
	if not ok or type(clone) ~= "table" then
		ok, clone = pcall(PlayerStyle.new, PlayerStyle)
	end
	if not ok or type(clone) ~= "table" then
		return srcStyle
	end
	local okCopy = pcall(clone.copyFrom, clone, srcStyle)
	if not okCopy then
		return srcStyle
	end
	clone.xmlFilename = genderXml
	-- Ensure the clone's configuration is loaded so setVehicleCharacter has valid selections to apply.
	if type(clone.loadConfigurationIfRequired) == "function" then
		pcall(clone.loadConfigurationIfRequired, clone)
	elseif type(clone.loadConfigurationXML) == "function" and type(clone.xmlFilename) == "string" then
		pcall(clone.loadConfigurationXML, clone, clone.xmlFilename)
	end
	return clone
end

-- Apply the neighbour's appearance style to this vehicle's in-cab character (driver model).
-- Called automatically from startAIJob; can be called when restarting/restoring a job so the driver
-- style is reapplied (the style would otherwise revert to a random base-game helper after a reload).
--
-- IMPORTANT: We must NOT call getVehicleCharacter():loadCharacter(...) directly on an already-loaded,
-- AI-active base-game vehicle. Reloading the character in place invalidates scene-graph nodes that the
-- engine's Suspensions specialization has cached, producing the recurring
-- "Failed to update suspension node X. Node does not exist anymore!" error as soon as the player gets
-- within suspension update range. Instead we go through the Enterable spec's setVehicleCharacter(),
-- which swaps the driver cleanly (the same pattern FS25_PlayerWorkers uses without triggering the error).
function IANeighbourVehicle:applyVehicleCharacterStyle()
	if self.vehicle == nil then
		return
	end
	if self.neighbour == nil then
		return
	end
	-- Never touch the character while the local player is sitting in the vehicle: let the game own it.
	local enterable = self.vehicle.spec_enterable
	if enterable ~= nil and enterable.isEntered == true then
		return
	end
	local style = self.neighbour.getResolvedPlayerStyle ~= nil and self.neighbour:getResolvedPlayerStyle() or nil
	if style == nil then
		return
	end

	local genderLower = string.lower(tostring(self.neighbour.gender or "male"))
	local genderXml = (genderLower == "male") and "dataS/character/playerM/playerM.xml" or "dataS/character/playerF/playerF.xml"
	local styleToApply = self:cloneResolvedStyleForCabin(style, genderXml)
	if styleToApply == nil then
		IAprintDebug("IANeighbourVehicle:applyVehicleCharacterStyle()", "Could not build cabin style", self.neighbour, self, nil)
		return
	end

	-- Preferred safe path: Enterable:setVehicleCharacter() replaces the driver without breaking cached nodes.
	if type(self.vehicle.setVehicleCharacter) == "function" then
		local ok, err = pcall(self.vehicle.setVehicleCharacter, self.vehicle, styleToApply)
		if not ok then
			IAprintDebug("IANeighbourVehicle:applyVehicleCharacterStyle()", "setVehicleCharacter failed: " .. tostring(err), self.neighbour, self, nil)
		else
			-- Keep the in-cab driver hidden; mech_show / encounter handling toggles visibility when appropriate.
			local vc = self.vehicle.getVehicleCharacter ~= nil and self.vehicle:getVehicleCharacter() or nil
			if vc ~= nil and vc.setCharacterVisibility ~= nil then
				pcall(vc.setCharacterVisibility, vc, false)
			end
		end
		return
	end

	-- Fallback only when setVehicleCharacter is unavailable (very old API): legacy in-place reload.
	-- This may re-trigger the suspension warning, so it is intentionally the last resort.
	if self.vehicle.getVehicleCharacter == nil then
		return
	end
	local vehicleCharacter = self.vehicle:getVehicleCharacter()
	if vehicleCharacter == nil or not vehicleCharacter.loadCharacter then
		return
	end
	local function onVehicleCharacterLoaded(callbackSelf, success, _)
		if success and callbackSelf.vehicle ~= nil then
			local vc = callbackSelf.vehicle:getVehicleCharacter()
			if vc then
				if vc.setDirty then
					vc:setDirty(true)
				end
				if vc.updateIKChains then
					vc:updateIKChains()
				end
				if vc.setCharacterVisibility then
					vc:setCharacterVisibility(false)
				end
			end
		end
	end
	vehicleCharacter:loadCharacter(styleToApply, self, onVehicleCharacterLoaded, nil)
end

-- Start an AI job for this vehicle. Applies vehicle character style after starting so the driver matches the neighbour.
-- @param string jobType - Type of job (e.g., "GOTO", "FIELDWORK", or IAFieldwork.JobType values)
-- @param number targetX - Target X position (field position for fieldwork, destination for GOTO)
-- @param number targetZ - Target Z position (field position for fieldwork, destination for GOTO)
-- @param number farmlandId - Optional farmland ID for fieldwork jobs
function IANeighbourVehicle:startAIJob(jobType, targetX, targetZ, farmlandId)
	if not self:isValid() then
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Vehicle is not valid", self.neighbour, self, nil)
		return
	end

	local farmId = IANeighbours.DebugAiFarmId or self.farmId
	
	if self.vehicle:getIsAIActive() then
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Vehicle AI is already active", self.neighbour, self, nil)
		return
	end
	
	local vehicleX, vehicleY, vehicleZ = getWorldTranslation(self.vehicle.rootNode)
	local distance = MathUtil.vector2Length(targetX - vehicleX, targetZ - vehicleZ)
	
	IAprintDebug("IANeighbourVehicle:startAIJob()", "Distance: " .. tostring(distance), self.neighbour, self, nil)
	
	-- For GOTO jobs, check minimum distance
	if jobType == "GOTO" and distance < 30 then
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Distance is too short", self.neighbour, self, nil)
		return
	end

	-- Stop existing job if any
	if self.currentJob ~= nil then
		g_currentMission.aiSystem:removeJob(self.currentJob)
		self.currentJob = nil
	end
	self.vehicle:aiJobFinished()
	self.vehicle:reachedAITarget()
	self.vehicle:unsetAITarget()
	local prevJob = self.vehicle:getStartableAIJob()
	--local canstart = self:getCanStartAIVehicle()
	local spec_aiJobVehicle = self.vehicle.spec_aiJobVehicle
	local lastJob = self.vehicle.spec_aiJobVehicle.lastJob
	--printObj(spec_aiJobVehicle, 3, "spec_aiJobVehicle")
	--printObj(lastJob, 3, "lastJob")
	--printObj(prevJob, 3, "prevJob")
	self.vehicle.spec_aiJobVehicle.lastJob = nil
	--print("--- IANeighbourVehicle:startAIJob() - canstart: "..tostring(canstart))

	if jobType == "GOTO" then
		local target = self:calculateTarget(targetX, targetZ)
		
		local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
		job:resetTasks()
		
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Created GOTO job", self.neighbour, self, nil)
		
		local angle = MathUtil.getYRotationFromDirection(target.dirX, target.dirZ)
		job.vehicleParameter:setVehicle(self.vehicle)
		job.positionAngleParameter:setPosition(targetX, targetZ)
		job.positionAngleParameter:setAngle(angle)

		job:applyCurrentState(self.vehicle, g_currentMission, farmId, false)
		job:setValues()

		job.driveToTask:setTargetDirection(targetX, targetZ)
		local success, errorMessage = job:validate(farmId)
		
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Job validation - success: " .. tostring(success), self.neighbour, self, nil)
		if errorMessage then
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Error: " .. tostring(errorMessage), self.neighbour, self, nil)
		end
		
		if success then
			g_currentMission.aiSystem:startJob(job, farmId)
			self.currentJob = job
			self.jobType = jobType
			self.jobTargetX = targetX
			self.jobTargetZ = targetZ
			self:applyVehicleCharacterStyle()
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Started AI job", self.neighbour, self, nil)
		end
	elseif jobType == "FIELDWORK" or jobType == IAFieldwork.JobType.CULTIVATE or jobType == IAFieldwork.JobType.HARROW or jobType == IAFieldwork.JobType.SEED or jobType == IAFieldwork.JobType.HARVEST or IAFieldwork.isFertilizeJobType(jobType) or jobType == IAFieldwork.JobType.SPRAY or jobType == IAFieldwork.JobType.PLOW then
		-- Create a fieldwork job
		local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK)
		if job == nil then
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Failed to create FIELDWORK job", self.neighbour, self, nil)
			return
		end
		
		job:resetTasks()
		
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Created FIELDWORK job", self.neighbour, self, nil)
		
		-- Set vehicle parameter
		job.vehicleParameter:setVehicle(self.vehicle)
		
		-- Set field position parameter (targetX, targetZ should be a position on the field)
		if job.fieldPositionParameter ~= nil then
			job.fieldPositionParameter:setPosition(targetX, targetZ)
		elseif job.iaJobParameters ~= nil and job.iaJobParameters.fieldPosition ~= nil then
			job.iaJobParameters.fieldPosition:setPosition(targetX, targetZ)
		end
		
		-- Set farmland if provided
		if farmlandId ~= nil and job.farmlandParameter ~= nil then
			local farmlands = g_farmlandManager:getFarmlands()
			for _, farmland in pairs(farmlands) do
				if farmland ~= nil and farmland.id == farmlandId then
					job.farmlandParameter:setFarmland(farmland)
					break
				end
			end
		end
		
		-- Apply current state
		job:applyCurrentState(self.vehicle, g_currentMission, farmId, false)
		
		-- Set values
		job:setValues()
		
		-- Validate the job
		local success, errorMessage = job:validate(farmId)
		
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Job validation - success: " .. tostring(success), self.neighbour, self, nil)
		if errorMessage then
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Error: " .. tostring(errorMessage), self.neighbour, self, nil)
		end
		
		if success then
			-- For fieldwork jobs, field boundary detection might be needed
			-- This is typically handled automatically by the job, but we can trigger it if needed
			if job.detectFieldBoundary ~= nil then
				local hasField, isRunning, errorMsg = job:detectFieldBoundary()
				if not hasField and not isRunning then
					IAprintDebug("IANeighbourVehicle:startAIJob()", "Field boundary detection error: " .. tostring(errorMsg), self.neighbour, self, nil)
				end
			end
			
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Vehicle AI Job Farm ID: "..tostring(self.vehicle:getAIJobFarmId()), self.neighbour, self, nil)
			g_currentMission.aiSystem:startJob(job, farmId)
			self.currentJob = job
			self.jobType = jobType
			self.jobTargetX = targetX
			self.jobTargetZ = targetZ
			self:applyVehicleCharacterStyle()
			--printObj(job, 3, "job")
			
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Vehicle AI Job Farm ID: "..tostring(self.vehicle:getAIJobFarmId()), self.neighbour, self, nil)
			
			IAprintDebug("IANeighbourVehicle:startAIJob()", "Started FIELDWORK AI job", self.neighbour, self, nil)
			return job
		end
	else
		IAprintDebug("IANeighbourVehicle:startAIJob()", "Unknown job type: " .. tostring(jobType), self.neighbour, self, nil)
	end
	return nil
end

-- Stop the current AI job for this vehicle
function IANeighbourVehicle:stopAIJob()
	if not self:isValid() then
		IAprintDebug("IANeighbourVehicle:stopAIJob()", "Vehicle is not valid", self.neighbour, self, nil)
		return
	end
	
	-- Stop the job on the vehicle if AI is active
	if self.vehicle:getIsAIActive() then
		-- Get the current job from the vehicle
		local vehicleJob = self.vehicle:getJob()
		if vehicleJob ~= nil then
			-- Stop with a user-stopped message - this will call aiJobFinished internally
			self.vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
			
			-- Also remove from AI system
			g_currentMission.aiSystem:removeJob(vehicleJob)
			
			if IANeighbours.debug then
				IAprintDebug("IANeighbourVehicle:stopAIJob()", "Stopped and removed vehicle job", self.neighbour, self, nil)
			end
		else
			-- If no job found but AI is active, try to stop anyway
			self.vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
		end
		
		-- Force cleanup if needed
		if self.vehicle:getIsAIActive() then
			if self.vehicle.aiJobFinished ~= nil then
				self.vehicle:aiJobFinished()
			end
			
			-- Clear job from spec directly
			local spec = self.vehicle.spec_aiJobVehicle
			if spec ~= nil and spec.job ~= nil then
				spec.job = nil
			end
		end
	end
	
	-- Remove our tracked job reference
	if self.currentJob ~= nil then
		g_currentMission.aiSystem:removeJob(self.currentJob)
		self.currentJob = nil
	end
	
	-- Clear job tracking variables and pause state
	self.jobType = nil
	self.jobTargetX = nil
	self.jobTargetZ = nil
	self.aiJobPaused = false
	
	IAprintDebug("IANeighbourVehicle:stopAIJob()", "Stopped AI job", self.neighbour, self, nil)
end

-- Block the current AI job when player is nearby (vehicle holds, job stays active). Safe to call every frame.
-- Call resumeAIJob() when player leaves to unblock. Missing parts (e.g. engine/lights) to be investigated later.
function IANeighbourVehicle:pauseAIJob(dt)
	if not self:isValid() then
		IAprintDebug("IANeighbourVehicle:pauseAIJob()", "Vehicle is not valid", self.neighbour, self, nil)
		return
	end
	if not self.vehicle:getIsAIActive() then
		IAprintDebug("IANeighbourVehicle:pauseAIJob()", "Vehicle AI is not active", self.neighbour, self, nil)
		return
	end
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	if not self.aiJobPaused then
		self.aiJobPaused = true
		IAprintDebug("IANeighbourVehicle:pauseAIJob()", "Paused (blocking AI)", self.neighbour, self, nil)
	end
	-- Block AI job (root vehicle; fallback for implements)
	if rootVehicle.aiBlock and type(rootVehicle.aiBlock) == "function" then
		rootVehicle:aiBlock()
	else
		if rootVehicle.spec_aiJobVehicle then
			SpecializationUtil.raiseEvent(rootVehicle, "onAIJobVehicleBlock")
		end
		if rootVehicle.spec_aiFieldWorker then
			rootVehicle.spec_aiFieldWorker.isBlocked = true
		end
	end
end

-- Re-apply engine and lights (for use when job was stopped). Reserved for later investigation; not used with aiBlock.
function IANeighbourVehicle:keepEngineAndLightsOn()
	if not self:isValid() then
		return
	end
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	if rootVehicle.spec_lights and self._savedLightsMask ~= nil then
		if rootVehicle.setLightsTypesMask and type(rootVehicle.setLightsTypesMask) == "function" then
			rootVehicle:setLightsTypesMask(self._savedLightsMask, true, true)
		end
		if self._savedBeaconLights ~= nil and rootVehicle.setBeaconLightsVisibility and type(rootVehicle.setBeaconLightsVisibility) == "function" then
			rootVehicle:setBeaconLightsVisibility(self._savedBeaconLights, true, true)
		end
	end
end

--- Turn engine and lights on after the AI job was stopped (e.g. when player is nearby). Call from situation after stopAIJob().
function IANeighbourVehicle:setEngineAndLightsOnForPlayerNearby()
	if not self:isValid() then
		return
	end
	self:startEngineIfPossible()
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	if rootVehicle.spec_lights then
		pcall(function()
			if rootVehicle.setLightsTypesMask and type(rootVehicle.setLightsTypesMask) == "function" then
				local mask = (rootVehicle.spec_lights.automaticLightsTypesMask ~= nil) and rootVehicle.spec_lights.automaticLightsTypesMask or 1
				rootVehicle:setLightsTypesMask(mask, true, true)
			end
			if rootVehicle.setBeaconLightsVisibility and type(rootVehicle.setBeaconLightsVisibility) == "function" then
				rootVehicle:setBeaconLightsVisibility(true, true, true)
			end
		end)
	end
end

-- Unblock the AI job after pause (calls aiContinue). farmlandId optional, reserved for future use.
function IANeighbourVehicle:resumeAIJob(farmlandId)
	if not self:isValid() then
		return
	end
	if not self.aiJobPaused then
		return
	end
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	if rootVehicle.aiContinue and type(rootVehicle.aiContinue) == "function" then
		rootVehicle:aiContinue()
	else
		if rootVehicle.spec_aiJobVehicle then
			SpecializationUtil.raiseEvent(rootVehicle, "onAIJobVehicleContinue")
		end
		if rootVehicle.spec_aiFieldWorker then
			rootVehicle.spec_aiFieldWorker.isBlocked = false
		end
	end
	self.aiJobPaused = false
	if IANeighbours.debug then
		IAprintDebug("IANeighbourVehicle:resumeAIJob()", "Resumed (unblocked)", self.neighbour, self, nil)
	end
end

function IANeighbourVehicle:setFarmId(farmId)
	self.farmId = farmId
	if self.vehicle ~= nil then
		self.vehicle:setOwnerFarmId(farmId)
	end
end
-- Update vehicle data from XML
-- @param string xmlFilename - XML filename
-- @param string jobType - Job type
-- @param number jobTargetX - Job target X
-- @param number jobTargetZ - Job target Z
-- @param string externalId - External ID from XML
-- @param number npcOffsetX - NPC offset X
-- @param number npcOffsetY - NPC offset Y
-- @param number npcOffsetZ - NPC offset Z
-- @param number npcOffsetRotation - NPC offset rotation
-- @param string type - Vehicle type from XML
-- @param string category - Vehicle category from XML (optional)
-- @param string activeSituationId - Active situation ID
-- @param number colorIndex - Vehicle base color index from scenario/outbound XML (optional)
-- @return boolean - true if changed
function IANeighbourVehicle:updateFromXML(xmlFilename, jobType, jobTargetX, jobTargetZ, externalId, npcOffsetX, npcOffsetY, npcOffsetZ, npcOffsetRotation, type, category, activeSituationId, colorIndex)
	local changed = false
	local positionChanged = false
	
	if xmlFilename ~= nil and self.xmlFilename ~= xmlFilename then
		self.xmlFilename = xmlFilename
		changed = true
	end
	
	if externalId ~= nil and self.externalId ~= externalId then
		self.externalId = externalId
		changed = true
	end
	
	if type ~= nil and self.type ~= type then
		self.type = type
		changed = true
	end
	
	if category ~= nil and self.category ~= category then
		self.category = category
		changed = true
	end
	
	if jobType ~= nil and self.jobType ~= jobType then
		self.jobType = jobType
		changed = true
	end
	
	if jobTargetX ~= nil and self.jobTargetX ~= jobTargetX then
		self.jobTargetX = jobTargetX
		changed = true
	end
	
	if jobTargetZ ~= nil and self.jobTargetZ ~= jobTargetZ then
		self.jobTargetZ = jobTargetZ
		changed = true
	end

	if npcOffsetX ~= nil and self.npcOffsetX ~= npcOffsetX then
		self.npcOffsetX = npcOffsetX
		changed = true
	end
	
	if npcOffsetY ~= nil and self.npcOffsetY ~= npcOffsetY then
		self.npcOffsetY = npcOffsetY
		changed = true
	end
	
	if npcOffsetZ ~= nil and self.npcOffsetZ ~= npcOffsetZ then
		self.npcOffsetZ = npcOffsetZ
		changed = true
	end
	
	if npcOffsetRotation ~= nil and self.npcOffsetRotation ~= npcOffsetRotation then
		self.npcOffsetRotation = npcOffsetRotation
		changed = true
	end
	
	if activeSituationId ~= nil and self.activeSituationId ~= activeSituationId then
		self.activeSituationId = activeSituationId
		changed = true
	end
	
	if colorIndex ~= nil and self.colorIndex ~= colorIndex then
		self.colorIndex = colorIndex
		changed = true
	end
	
	--will be handled in Situation
	--if positionChanged then
		--self:handleChangePosition()
	--end
	
	if changed then
		IAprintDebug("IANeighbourVehicle:updateFromXML()", "Updated vehicle: "..tostring(self.uniqueId), self.neighbour, self, nil)
	end
	
	return changed
end

--- Layer 3: hide (mechanical only).
function IANeighbourVehicle:mech_hide()
	if self.vehicle == nil then
		return
	end
	self.vehicleIsVisible = false
	self.isActive = false
	self.vehicle:removeFromPhysics()
	self.vehicle:setVisibility(false)
end

--- Layer 3: show (mechanical only).
function IANeighbourVehicle:mech_show()
	if self.vehicle == nil then
		return
	end
	self.vehicleIsVisible = true
	self.isActive = true
	self.vehicle:addToPhysics()
	self.vehicle:setVisibility(true)
end

--- Layer 3: teleport to pose table { x, y?, z, rotation? } — no hide/show policy.
function IANeighbourVehicle:mech_teleportToPose(pose)
	if self.vehicle == nil or self.vehicle.rootNode == nil or pose == nil then
		return
	end
	if self.vehicle.getIsAIActive ~= nil and self.vehicle:getIsAIActive() then
		return
	end
	local targetX = MathUtil.round(pose.x, 0)
	local targetZ = MathUtil.round(pose.z, 0)
	local groundY = pose.y
	if groundY == nil and g_terrainNode ~= nil then
		groundY = getTerrainHeightAtWorldPos(g_terrainNode, targetX, 0, targetZ) + 0.2
	end
	groundY = MathUtil.round(groundY or 0, 0)
	local rot = pose.rotation or self.rotation or 0
	self.positionX = targetX
	self.positionY = groundY
	self.positionZ = targetZ
	self.rotation = rot
	self.vehicle:removeFromPhysics()
	local realX = MathUtil.round(self.realPositionX or 0, 0)
	local realZ = MathUtil.round(self.realPositionZ or 0, 0)
	if realX ~= targetX or realZ ~= targetZ then
		if self.vehicle.setWorldPosition ~= nil then
			self.vehicle:setRelativePosition(targetX, 0.5, targetZ, rot, true)
		else
			setTranslation(self.vehicle.rootNode, targetX, groundY, targetZ)
			setRotation(self.vehicle.rootNode, 0, rot, 0)
		end
	end
	if self.vehicleIsVisible then
		self.vehicle:addToPhysics()
	end
end

--- True when this unit should be unfolded (not folded) while unattached / before parking teleport.
function IANeighbourVehicle:shouldBeUnfoldedWhenUnattached()
	local fn = self.xmlFilename ~= nil and string.lower(tostring(self.xmlFilename)) or ""
	if fn ~= "" then
		for _, pattern in ipairs(IANeighbourVehicle.UNFOLDED_PARKING_XML_PATTERNS) do
			if string.find(fn, string.lower(pattern), 1, true) ~= nil then
				return true
			end
		end
		if string.find(fn, "plow", 1, true) ~= nil then
			return true
		end
	end
	local cat = self.category ~= nil and string.lower(tostring(self.category)) or ""
	if cat ~= "" and string.find(cat, "plow", 1, true) ~= nil then
		return true
	end
	local gv = self.vehicle
	if gv ~= nil and gv.spec_plow ~= nil then
		return true
	end
	return false
end

--- Layer 3: lift and fold, or unfold when required, before a presence teleport.
function IANeighbourVehicle:mech_prepareForTeleport()
	if self.vehicle == nil then
		return
	end
	-- Combine auger pipes are on the main vehicle's Pipe spec, so fold them before
	-- the attachment-only transport preparation below can return early.
	if type(IAHelper_foldCombinePipeIn) == "function" then
		pcall(function()
			IAHelper_foldCombinePipeIn(self.vehicle)
		end)
	end
	if self:shouldBeUnfoldedWhenUnattached() then
		if type(self.tryUnfold) == "function" then
			pcall(function()
				self:tryUnfold("teleport")
			end)
		end
		return
	end
	local vtype = (self.type ~= nil) and string.lower(tostring(self.type)) or ""
	if vtype ~= "attachment" then
		return
	end
	if type(self.tryLift) == "function" then
		pcall(function()
			self:tryLift("teleport")
		end)
	end
	if type(self.tryFold) == "function" then
		pcall(function()
			self:tryFold("teleport")
		end)
	end
end

function IANeighbourVehicle:mech_detachFromAttacher()
	self:detachFromCurrentAttacherIfNeeded()
end

function IANeighbourVehicle:mech_detachAllImplements()
	self:detachAttachments()
end

function IANeighbourVehicle:mech_attachBack(iaParent)
	self:alignAndAttach(iaParent)
end

function IANeighbourVehicle:mech_attachFront(iaParent)
	self:alignAndAttachFront(iaParent)
end

--- Legacy entry: applies pose via mechanics; visibility from presenceState when reconcile runs.
function IANeighbourVehicle:handleChangePosition()
	if self.vehicle == nil or self.vehicle.rootNode == nil then
		return
	end
	if self.vehicle:getIsAIActive() then
		return
	end
	local ps = self.presenceState
	if ps ~= nil and ps.mode == "hidden" then
		self:mech_hide()
		return
	end
	if self.positionX == 0 and self.positionZ == 0 then
		if IAEquipmentPresence ~= nil then
			IAEquipmentPresence.State.setDesiredHidden(self)
		end
		self:mech_hide()
		return
	end
	local pose = IAEquipmentPresence ~= nil and IAEquipmentPresence.State.buildPoseFromIA(self) or {
		x = self.positionX, y = self.positionY, z = self.positionZ, rotation = self.rotation
	}
	self:mech_teleportToPose(pose)
	if ps == nil or ps.mode == "visible" then
		self:mech_show()
	end
end

--- Start the engine on the root vehicle if the API is available. Call from situation after vehicle is positioned and (if any) attachments are attached.
function IANeighbourVehicle:startEngineIfPossible()
	if self.vehicle == nil then return end
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	pcall(function()
		rootVehicle:startMotor(true)
	end)
end

--- Keep the motor running when used in a situation. The game stops the motor after ~250 ms when no one is in the vehicle (automaticMotorStartEnabled). Reset the "motor not required" timer so it never triggers. Call from situation update every frame while loaded.
--- If the motor is already OFF (e.g. right after stopAIJob), restarting here avoids a stop/start loop where the timer logic never runs until something else calls startMotor again.
function IANeighbourVehicle:keepSituationMotorRunning()
	if self.vehicle == nil then return end
	local rootVehicle = self.vehicle.rootVehicle or self.vehicle
	local spec = rootVehicle.spec_motorized
	if spec == nil then return end
	-- MotorState.OFF is 0; any other state (IGNITION=1, STARTING=2, ON=3) means motor is on or starting
	if spec.motorState ~= nil and spec.motorState ~= 0 then
		spec.motorNotRequiredTimer = 0
	else
		pcall(function()
			rootVehicle:startMotor(true)
		end)
	end
end

function IANeighbourVehicle:detachAttachments()
	if self.vehicle == nil or self.vehicle.rootNode == nil then
		return
	end
	if self.vehicle.getAttachedImplements ~= nil then
		local attachedImplements = self.vehicle:getAttachedImplements()
		for _, entry in pairs(attachedImplements) do
			local obj = entry
			if type(entry) == "table" and entry.object ~= nil then
				obj = entry.object
			end
			if obj ~= nil then
				local implementIndex = nil
				if self.vehicle.getImplementIndexByObject ~= nil then
					local okIdx, idx = pcall(function()
						return self.vehicle:getImplementIndexByObject(obj)
					end)
					if okIdx then
						implementIndex = idx
					end
				end
				if implementIndex ~= nil then
					pcall(function()
						self.vehicle:detachImplement(implementIndex, true)
					end)
				end
			end
		end
	end
end

--- Detach this vehicle from whatever is currently towing it (so situation attach does not stack two hitch links).
function IANeighbourVehicle:detachFromCurrentAttacherIfNeeded()
	local gv = self.vehicle
	if gv == nil or gv.getAttacherVehicle == nil then
		return
	end
	local okA, att = pcall(function()
		return gv:getAttacherVehicle()
	end)
	if not okA or att == nil or att.detachImplement == nil then
		return
	end
	if att.getImplementIndexByObject ~= nil then
		local okIdx, implementIndex = pcall(function()
			return att:getImplementIndexByObject(gv)
		end)
		if okIdx and implementIndex ~= nil then
			pcall(function()
				att:detachImplement(implementIndex, true)
			end)
			return
		end
	end
	if att.getAttachedImplements == nil then
		return
	end
	local okL, list = pcall(function()
		return att:getAttachedImplements()
	end)
	if not okL or list == nil then
		return
	end
	for i, entry in pairs(list) do
		local obj = entry
		if type(entry) == "table" and entry.object ~= nil then
			obj = entry.object
		end
		if obj == gv then
			pcall(function()
				att:detachImplement(i, true)
			end)
			return
		end
	end
end

--- Max working width (m) from WorkArea `getWorkAreaWidth` across all work areas; falls back to `size.width`.
-- @return number
function IANeighbourVehicle:resolveFieldworkWorkWidthMeters()
	local gv = self.vehicle
	if gv == nil then
		return 0
	end
	local maxW = 0
	local spec = gv.spec_workArea
	if spec ~= nil and spec.workAreas ~= nil then
		local areas = spec.workAreas
		local n = #areas
		if type(gv.getWorkAreaWidth) == "function" then
			for i = 1, n do
				local ok, w = pcall(function()
					return gv:getWorkAreaWidth(i)
				end)
				if ok and type(w) == "number" and w > maxW then
					maxW = w
				end
			end
		else
			for i = 1, n do
				local area = areas[i]
				if area ~= nil and type(area.workWidth) == "number" and area.workWidth > maxW then
					maxW = area.workWidth
				end
			end
		end
	end
	if maxW <= 0 and gv.size ~= nil and type(gv.size.width) == "number" and gv.size.width > 0 then
		maxW = gv.size.width
	end
	return maxW
end

--- Try to fold this vehicle (attachments only). Called by situation on attachmentBack/attachmentFront after attach; also when unused vehicles spawn and situation vehicle spawns.
--- Cars, tractors and combines are excluded (no folding). Uses Foldable.setAnimTime(vehicle, 1, true) then clears foldMoveDirection and moveToMiddle.
--- @param string foldKind - "back", "front", "roadside", "homebase", "spawn", "situation" (for debug)
--- @return boolean - true if fold was applied without error
function IANeighbourVehicle:tryFold(foldKind)
	local gv = self.vehicle
	local name = self.vehicleName or self.name or self.xmlFilename
	local foldKindStr = foldKind or "?"
	if gv == nil then
		return false
	end
	-- Combine auger pipe (spout): always fold it in. This is driven by the Pipe spec
	-- (spec_pipe), not Foldable, so it must run before the attachment-only check below
	-- (combines are excluded from the Foldable path). Safe no-op for vehicles without a pipe.
	if type(IAHelper_foldCombinePipeIn) == "function" then
		local okP, msgP = IAHelper_foldCombinePipeIn(gv)
		if IANeighbours and IANeighbours.debug and okP then
			print("--- IANeighbourVehicle:tryFold() - pipe folded in (" .. tostring(foldKindStr) .. ") " .. tostring(msgP) .. " name=" .. tostring(name))
		end
	end
	-- Only fold attachments; exclude cars, tractors, combines
	local vtype = (self.type ~= nil) and string.lower(tostring(self.type)) or ""
	if vtype ~= "attachment" then
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbourVehicle:tryFold() - skipped (not attachment, type=" .. tostring(self.type) .. ") " .. tostring(name))
		end
		return false
	end
	if Foldable == nil or type(Foldable.setAnimTime) ~= "function" then
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbourVehicle:tryFold() - Foldable.setAnimTime not available")
		end
		return false
	end
	local function applyFoldedState(vehicle)
		if vehicle == nil or vehicle.spec_foldable == nil then return false end
		Foldable.setAnimTime(vehicle, 1, true)
		vehicle.spec_foldable.foldMoveDirection = 0
		vehicle.spec_foldable.moveToMiddle = false
		return true
	end
	local ok, err = pcall(function()
		applyFoldedState(gv)
	end)
	if IANeighbours and IANeighbours.debug then
		local namePart = (name ~= nil and name ~= "") and (" name=" .. tostring(name)) or ""
		if ok then
			print("--- IANeighbourVehicle:tryFold() - setAnimTime(1) ok" .. namePart)
		else
			print("--- IANeighbourVehicle:tryFold() - setAnimTime error: " .. tostring(err) .. namePart)
		end
		print("--- IANeighbourVehicle:tryFold() - done ok=" .. tostring(ok) .. " (" .. tostring(foldKindStr) .. ") uniqueId=" .. tostring(self.uniqueId))
	end
	-- Also set folded state on child vehicles (compound attachments)
	if ok and type(gv.getChildVehicles) == "function" then
		local okGet, children = pcall(function() return gv:getChildVehicles() end)
		if okGet and children and type(children) == "table" then
			for i, child in pairs(children) do
				if child and child.spec_foldable then
					local okC, errC = pcall(function()
						applyFoldedState(child)
					end)
					if IANeighbours and IANeighbours.debug then
						print("--- IANeighbourVehicle:tryFold() - setAnimTime(child[" .. tostring(i) .. "]) " .. (okC and "ok" or ("error: " .. tostring(errC))))
					end
				end
			end
		end
	end
	return ok
end

--- Try to unfold this vehicle (attachments only).
--- Intended for implements that shouldBeUnfoldedWhenUnattached (plows, aresxl, etc.).
--- Uses Foldable.setAnimTime(vehicle, 0, true) then clears foldMoveDirection and moveToMiddle.
--- @param string unfoldKind - for debug
--- @return boolean - true if unfold was applied without error
function IANeighbourVehicle:tryUnfold(unfoldKind)
	local gv = self.vehicle
	local name = self.vehicleName or self.name or self.xmlFilename
	local unfoldKindStr = unfoldKind or "?"
	if gv == nil then
		return false
	end
	-- Only unfold attachments; exclude cars, tractors, combines
	local vtype = (self.type ~= nil) and string.lower(tostring(self.type)) or ""
	if vtype ~= "attachment" then
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbourVehicle:tryUnfold() - skipped (not attachment, type=" .. tostring(self.type) .. ") " .. tostring(name))
		end
		return false
	end
	if Foldable == nil or type(Foldable.setAnimTime) ~= "function" then
		if IANeighbours and IANeighbours.debug then
			print("--- IANeighbourVehicle:tryUnfold() - Foldable.setAnimTime not available")
		end
		return false
	end
	local function applyUnfoldedState(vehicle)
		if vehicle == nil or vehicle.spec_foldable == nil then return false end
		Foldable.setAnimTime(vehicle, 0, true)
		vehicle.spec_foldable.foldMoveDirection = 0
		vehicle.spec_foldable.moveToMiddle = false
		return true
	end
	local ok, err = pcall(function()
		applyUnfoldedState(gv)
	end)
	if IANeighbours and IANeighbours.debug then
		local namePart = (name ~= nil and name ~= "") and (" name=" .. tostring(name)) or ""
		if ok then
			print("--- IANeighbourVehicle:tryUnfold() - setAnimTime(0) ok" .. namePart)
		else
			print("--- IANeighbourVehicle:tryUnfold() - setAnimTime error: " .. tostring(err) .. namePart)
		end
		print("--- IANeighbourVehicle:tryUnfold() - done ok=" .. tostring(ok) .. " (" .. tostring(unfoldKindStr) .. ") uniqueId=" .. tostring(self.uniqueId))
	end
	-- Also set unfolded state on child vehicles (compound attachments)
	if ok and type(gv.getChildVehicles) == "function" then
		local okGet, children = pcall(function() return gv:getChildVehicles() end)
		if okGet and children and type(children) == "table" then
			for i, child in pairs(children) do
				if child and child.spec_foldable then
					local okC, errC = pcall(function()
						applyUnfoldedState(child)
					end)
					if IANeighbours and IANeighbours.debug then
						print("--- IANeighbourVehicle:tryUnfold() - setAnimTime(child[" .. tostring(i) .. "]) " .. (okC and "ok" or ("error: " .. tostring(errC))))
					end
				end
			end
		end
	end
	return ok
end

--- Fills a vehicle's fill unit to capacity with the given fill type. Class method (no self); used by emptyFillUnits refill and situation attachment fill.
--- @param table vehicle - Game vehicle (with getFillUnitSupportsFillType, getFillUnitCapacity, getFillUnitFillLevel, addFillUnitFillLevel)
--- @param number farmId - Farm ID for addFillUnitFillLevel
--- @param number fillUnitIndex - Fill unit index
--- @param number fillType - FillType (e.g. FillType.FUEL, FillType.HERBICIDE, FillType.MANURE)
function IANeighbourVehicle.fillVehicleFillUnitToCapacity(vehicle, farmId, fillUnitIndex, fillType)
	if vehicle == nil or farmId == nil or fillUnitIndex == nil or fillType == nil then
		return
	end
	if vehicle.getFillUnitSupportsFillType == nil or not vehicle:getFillUnitSupportsFillType(fillUnitIndex, fillType) then
		return
	end
	local capacity = vehicle.getFillUnitCapacity and vehicle:getFillUnitCapacity(fillUnitIndex) or nil
	if capacity == nil or capacity <= 0 then
		return
	end
	local fillLevel = vehicle.getFillUnitFillLevel and vehicle:getFillUnitFillLevel(fillUnitIndex) or 0
	local toAdd = capacity - fillLevel
	if toAdd > 0 and vehicle.addFillUnitFillLevel ~= nil then
		pcall(function()
			vehicle:addFillUnitFillLevel(farmId, fillUnitIndex, toAdd, fillType, ToolType.UNDEFINED, nil)
		end)
	end
end

--- Fills this vehicle's sprayer/spreader fill unit when applicable: category "Sprayer" → herbicide; "Manure Spreader" → manure. Called by situation after attach.
function IANeighbourVehicle:fillSprayerOrSpreaderIfNeeded()
	local gv = self.vehicle
	if gv == nil or gv.spec_sprayer == nil or gv.getSprayerFillUnitIndex == nil then
		return
	end
	local fillUnitIndex = gv:getSprayerFillUnitIndex()
	local fillType = nil
	local cat = (self.category ~= nil) and string.lower(tostring(self.category)) or ""
	if cat == "sprayer" then
		fillType = FillType.HERBICIDE
	elseif cat == "manure spreader" then
		fillType = FillType.MANURE
	elseif cat == "fertilizer spreader" then
		fillType = FillType.FERTILIZER
	elseif cat == "seeder" then
		fillType = FillType.SEEDS
	elseif cat == "slurry tank" then
		fillType = FillType.LIQUIDMANURE
	end
	
	if fillUnitIndex ~= nil and fillType ~= nil then
		IANeighbourVehicle.fillVehicleFillUnitToCapacity(gv, self.farmId or 1, fillUnitIndex, fillType)
	end
end

--- Sets seed type and tops up seeder fill units when applicable (phone borrow / situations).
--- The seed fruit type index is optional: when provided (active borrow session) it is
--- (re)asserted on the seeder; when nil (e.g. after a save/load restore where the borrow
--- session's seedByUid table is not persisted) the tanks are still topped up, since the
--- seeder retains its own seed fruit type in the savegame and we only need to refill levels.
-- @param number|nil seedFruitTypeIndex
function IANeighbourVehicle:fillSeederIfNeeded(seedFruitTypeIndex)
	local gv = self.vehicle
	IAprintDebug("IANeighbourVehicle:fillSeederIfNeeded()", "Filling seeder with seed fruit type index: " .. tostring(seedFruitTypeIndex), self.neighbour, self, nil)
	if gv == nil then
		return
	end
	local cat = (self.category ~= nil) and string.lower(tostring(self.category)) or ""
	if cat ~= "seeder" then
		return
	end
	if seedFruitTypeIndex ~= nil and type(gv.setSeedFruitType) == "function" then
		IAprintDebug("IANeighbourVehicle:fillSeederIfNeeded()", "Setting seed fruit type: " .. tostring(seedFruitTypeIndex), self.neighbour, self, nil)
		pcall(function()
			gv:setSeedFruitType(seedFruitTypeIndex, true)
		end)
	end
	if gv.spec_fillUnit ~= nil and gv.spec_fillUnit.fillUnits ~= nil and FillType ~= nil then
		-- Top up every fill unit a seeder may have: the seed tank plus any
		-- secondary tanks for fertilizer / liquid fertilizer / lime. Candidates
		-- are tried in priority order so each unit is filled with the most
		-- appropriate supported type (seeds first, then fertilizers).
		local candidateFillTypes = { FillType.SEEDS, FillType.FERTILIZER, FillType.LIQUIDFERTILIZER, FillType.LIME }
		for fillUnitIndex, unit in pairs(gv.spec_fillUnit.fillUnits) do
			if unit ~= nil and gv.getFillUnitSupportsFillType ~= nil then
				local targetFillType = nil
				-- Prefer the type currently loaded in this unit (avoids mixing types).
				if gv.getFillUnitFillType ~= nil then
					local okT, currentType = pcall(gv.getFillUnitFillType, gv, fillUnitIndex)
					if okT and currentType ~= nil and currentType ~= FillType.UNKNOWN
						and gv:getFillUnitSupportsFillType(fillUnitIndex, currentType) then
						-- Only auto-fill currently-loaded type if it is one we manage.
						for _, ft in ipairs(candidateFillTypes) do
							if ft ~= nil and ft == currentType then
								targetFillType = currentType
								break
							end
						end
					end
				end
				IAprintDebug("IANeighbourVehicle:fillSeederIfNeeded()", "Target fill type: " .. tostring(targetFillType), self.neighbour, self, nil)
				if targetFillType == nil then
					for _, ft in ipairs(candidateFillTypes) do
						if ft ~= nil and gv:getFillUnitSupportsFillType(fillUnitIndex, ft) then
							targetFillType = ft
							break
						end
					end
				end
				if targetFillType ~= nil then
					IANeighbourVehicle.fillVehicleFillUnitToCapacity(gv, self.farmId or 1, fillUnitIndex, targetFillType)
				end
			end
		end
	end
end

--- Fill types to refill to capacity after emptying (fuel/diesel/AdBlue so the vehicle can run).


--- Empty all fill units on this vehicle, then refill fuel/diesel/AdBlue to capacity so the vehicle can run.
--- Delegates to emptyAllFillUnits(), then refills fuel-type fill units via spec_fillUnit.fillUnits using fillVehicleFillUnitToCapacity.
function IANeighbourVehicle:emptyFillUnits()
	local gv = self.vehicle
	local FILL_TYPES_TO_REFILL = { FillType.DIESEL }
	if gv == nil or gv.emptyAllFillUnits == nil then
		return
	end
	pcall(function()
		gv:emptyAllFillUnits()
	end)
	local spec = gv.spec_fillUnit
	if spec == nil or spec.fillUnits == nil then
		return
	end
	local farmId = self.farmId
	if farmId == nil then
		if type(gv.getOwnerFarmId) == "function" then
			farmId = gv:getOwnerFarmId()
		elseif gv.ownerFarmId ~= nil then
			farmId = gv.ownerFarmId
		end
	end
	if farmId == nil then
		return
	end
	for fillUnitIndex, _ in pairs(spec.fillUnits) do
		--print("--- IANeighbourVehicle:emptyFillUnits() - Emptying fill unit " .. tostring(fillUnitIndex) .. " on " .. tostring(gv.configFileName))
		for _, fillType in ipairs(FILL_TYPES_TO_REFILL) do
			--print("--- IANeighbourVehicle:emptyFillUnits() - Fill type: " .. tostring(fillType))
			--print("--- IANeighbourVehicle:emptyFillUnits() - Fill unit index: " .. tostring(fillUnitIndex))
			--print("--- IANeighbourVehicle:emptyFillUnits() - Get fill unit supports fill type: " .. tostring(gv.getFillUnitSupportsFillType))
			--print("--- IANeighbourVehicle:emptyFillUnits() - Get fill unit supports fill type result: " .. tostring(gv:getFillUnitSupportsFillType(fillUnitIndex, fillType)))
			if fillType ~= nil and gv.getFillUnitSupportsFillType and gv:getFillUnitSupportsFillType(fillUnitIndex, fillType) then
				--print("--- IANeighbourVehicle:emptyFillUnits() - Filling fill unit " .. tostring(fillUnitIndex) .. " with fill type " .. tostring(fillType))
				IANeighbourVehicle.fillVehicleFillUnitToCapacity(gv, farmId, fillUnitIndex, fillType)

				break
			end
		end
	end
end

--- Try to lower this attachment. Uses the game's lower/raise action: attacher:handleLowerImplementEvent(implement) (same as player key; toggles lower/lift).
--- @param string kind - "back" or "front" (for debug)
--- @return boolean - true if handleLowerImplementEvent was called without error
function IANeighbourVehicle:tryLower(kind)
	local gv = self.vehicle
	if gv == nil or type(gv.getAttacherVehicle) ~= "function" then
		return false
	end
	local attacher = gv:getAttacherVehicle()
	if attacher == nil or type(attacher.handleLowerImplementEvent) ~= "function" then
		return false
	end
	local ok, err = pcall(function()
		attacher:handleLowerImplementEvent(gv)
	end)
	if IANeighbours and IANeighbours.debug then
		local namePart = (self.vehicleName or self.name or self.xmlFilename) and (" name=" .. tostring(self.vehicleName or self.name or self.xmlFilename)) or ""
		print("--- IANeighbourVehicle:tryLower() (" .. tostring(kind or "?") .. ") uniqueId=" .. tostring(self.uniqueId) .. namePart .. " ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or ""))
	end
	return ok
end

--- Try to lift this attachment. Uses the game's lower/raise action: attacher:handleLowerImplementEvent(implement) (same as player key; toggles lower/lift).
--- Must be lifted before folding (game shows "cannot be folded until it is lifted" otherwise).
--- @param string kind - "back" or "front" (for debug)
--- @return boolean - true if handleLowerImplementEvent was called without error
function IANeighbourVehicle:tryLift(kind)
	local gv = self.vehicle
	if gv == nil or type(gv.getAttacherVehicle) ~= "function" then
		return false
	end
	local attacher = gv:getAttacherVehicle()
	if attacher == nil or type(attacher.handleLowerImplementEvent) ~= "function" then
		return false
	end
	local ok, err = pcall(function()
		attacher:handleLowerImplementEvent(gv)
	end)
	if IANeighbours and IANeighbours.debug then
		local namePart = (self.vehicleName or self.name or self.xmlFilename) and (" name=" .. tostring(self.vehicleName or self.name or self.xmlFilename)) or ""
		print("--- IANeighbourVehicle:tryLift() (" .. tostring(kind or "?") .. ") uniqueId=" .. tostring(self.uniqueId) .. namePart .. " ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or ""))
	end
	return ok
end

function IANeighbourVehicle:alignAndAttach(ia_vehicle)
	pcall(function()
		self:detachFromCurrentAttacherIfNeeded()
	end)
	local attachmentJoint, vehicleAttachIndex, attachmentNode, vehicleAttacherNode = identifyAttachmentJoint(self.vehicle, ia_vehicle.vehicle)
	if attachmentJoint ~= nil and vehicleAttachIndex ~= nil then
		--printObj(self.vehicle.vehicle.spec_attacherJoints.attacherJoints, 3, "attacherJoints")
		--print("--- IASituation:attachAttachmentBack() - ALL NODES: AttachmentJoint: "..tostring(attachmentJoint)..", vehicleAttachIndex: "..tostring(vehicleAttachIndex)..", AttachmentNode: "..tostring(attachmentNode)..", VehicleAttacherNode: "..tostring(vehicleAttacherNode))
		local attachmentRootX, attachmentRootY, attachmentRootZ = calculateAttachmentRootPosition2(ia_vehicle.vehicle.rootNode, self.vehicle.rootNode, vehicleAttacherNode, attachmentNode)
		--print("--- IASituation:attachAttachmentBack() - AttachmentRoot Position: "..tostring(attachmentRootX)..", "..tostring(attachmentRootY)..", "..tostring(attachmentRootZ)..", "..tostring(self.rotation))
		self.positionX = attachmentRootX
		self.positionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, attachmentRootX, 0, attachmentRootZ), 1)+0.5
		self.positionZ = attachmentRootZ
		self.rotation = ia_vehicle.rotation
		self:handleChangePosition()
		-- [COMPAT] ManualAttach: prevent auto-detach of PTO/hoses on NPC attach
		pcall(function()
			if self.vehicle.spec_manualAttachPowerTakeOff then
				self.vehicle.spec_manualAttachPowerTakeOff.isBlockingInitialPtoDetach = true
			end
		end)
		pcall(function()
			if self.vehicle.spec_manualAttachConnectionHoses then
				local spec = self.vehicle.spec_manualAttachConnectionHoses
				spec.isBlockingInitialHoseDetach = true
			end
		end)
		ia_vehicle.vehicle:attachImplement(self.vehicle, attachmentJoint, vehicleAttachIndex, true, nil, nil, false)
	end
end

-- Align and attach this attachment to a front attacher joint on the main vehicle (e.g. Header / Cutter on combine).
function IANeighbourVehicle:alignAndAttachFront(ia_vehicle)
	pcall(function()
		self:detachFromCurrentAttacherIfNeeded()
	end)
	local attachmentJoint, vehicleAttachIndex, attachmentNode, vehicleAttacherNode = identifyAttachmentJointFront(self.vehicle, ia_vehicle.vehicle)
	IAprintDebug("IANeighbourVehicle:alignAndAttachFront()", "AttachmentJoint: "..tostring(attachmentJoint)..", VehicleAttachIndex: "..tostring(vehicleAttachIndex)..", AttachmentNode: "..tostring(attachmentNode)..", VehicleAttacherNode: "..tostring(vehicleAttacherNode), self.neighbour, self, nil)
	if attachmentJoint ~= nil and vehicleAttachIndex ~= nil then
		local attachmentRootX, attachmentRootY, attachmentRootZ = calculateAttachmentRootPosition2(ia_vehicle.vehicle.rootNode, self.vehicle.rootNode, vehicleAttacherNode, attachmentNode)
		self.positionX = attachmentRootX
		self.positionY = MathUtil.round(getTerrainHeightAtWorldPos(g_terrainNode, attachmentRootX, 0, attachmentRootZ), 1)+0.5
		self.positionZ = attachmentRootZ
		self.rotation = ia_vehicle.rotation
		self:handleChangePosition()
		IAprintDebug("IANeighbourVehicle:alignAndAttachFront()", "AttachmentRoot Position: "..tostring(attachmentRootX)..", "..tostring(attachmentRootY)..", "..tostring(attachmentRootZ)..", "..tostring(self.rotation), self.neighbour, self, nil)
		-- [COMPAT] ManualAttach: prevent auto-detach of PTO/hoses on NPC front attach
		pcall(function()
			if self.vehicle.spec_manualAttachPowerTakeOff then
				self.vehicle.spec_manualAttachPowerTakeOff.isBlockingInitialPtoDetach = true
			end
		end)
		pcall(function()
			if self.vehicle.spec_manualAttachConnectionHoses then
				local spec = self.vehicle.spec_manualAttachConnectionHoses
				spec.isBlockingInitialHoseDetach = true
			end
		end)
		ia_vehicle.vehicle:attachImplement(self.vehicle, attachmentJoint, vehicleAttachIndex, true, nil, nil, false)
	end
end

function IANeighbourVehicle:hideVehicle()
	if IAEquipmentPresence ~= nil then
		IAEquipmentPresence.State.setDesiredHidden(self)
	end
	self:mech_hide()
end

function IANeighbourVehicle:showVehicle()
	self:mech_show()
end
function IANeighbourVehicle:addPhysics()
	self.vehicle:addToPhysics()
end

-- Delete the vehicle
function IANeighbourVehicle:delete()
	-- Stop any active AI jobs
	if self.currentJob ~= nil then
		self:stopAIJob()
	end
	
	-- Note: Actual vehicle deletion should be handled by the game/neighbour system
	-- This just cleans up our reference
	self.vehicle = nil
	self.initialized = false
end

function IANeighbourVehicle:loadVehicleById(uniqueId)
	if uniqueId == nil then
		IAprintDebug("IANeighbourVehicle:loadVehicleById()", "uniqueId is nil", self.neighbour, self, nil)
		return false
	end
	
	if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
		IAprintDebug("IANeighbourVehicle:loadVehicleById()", "Vehicle system not available", self.neighbour, self, nil)
		return false
	end
	
	self.uniqueId = uniqueId
	self.vehicle = g_currentMission.vehicleSystem.vehicleByUniqueId[uniqueId]
	
	if self.vehicle ~= nil then
		self.fullLoaded = true
		-- First hotspot apply once the game vehicle is attached: reflects restored borrowed state from XML or removes default hotspot otherwise.
		if IAEquipmentPresence ~= nil and IAEquipmentPresence.State ~= nil then
			IAEquipmentPresence.State.applyVehicleHotspotForPresence(self)
		end
		-- Active situation convoy: save layout is authoritative; situation init sets desired presence.
		if self.activeSituationId ~= nil and tostring(self.activeSituationId) ~= "" then
			IAprintDebug("IANeighbourVehicle:loadVehicleById()", "Skipping homebase/hidden bootstrap (activeSituationId=" .. tostring(self.activeSituationId) .. ")", self.neighbour, self, nil)
			return true
		end
		if not self.vehicle:getIsAIActive() then
			-- Hide until parked unless we already have a real world pose (save/XML); avoids empty farm when parking runs later.
			local px, pz = self.positionX, self.positionZ
			if px ~= nil and pz ~= nil and not (px == 0 and pz == 0) then
				if IAEquipmentPresence ~= nil then
					IAEquipmentPresence.State.setDesiredHomebase(self, IAEquipmentPresence.State.buildPoseFromIA(self), self.parkingPlaceId)
				end
				pcall(function() IAEquipmentPresence.Reconcile.reconcileVehicle(self) end)
			else
				if IAEquipmentPresence ~= nil then
					IAEquipmentPresence.State.setDesiredHidden(self)
				end
				self:mech_hide()
			end
		end
		return true
	else
		IAprintDebug("IANeighbourVehicle:loadVehicleById()", "Vehicle not found: "..tostring(uniqueId), self.neighbour, self, nil)
		return false
	end
end

--- Assign a random license plate to this vehicle's game object (server-side, after load).
--- No-op when the vehicle has no plate nodes, plates aren't available on the map, or a plate
--- (with characters) is already assigned (e.g. restored from savegame). The plate data is then
--- persisted by the LicensePlates spec and streamed to clients on the vehicle's initial sync.
function IANeighbourVehicle:applyRandomLicensePlatesIfPossible()
	local gv = self.vehicle
	if gv == nil or gv.getHasLicensePlates == nil or not gv:getHasLicensePlates() then
		return
	end
	if g_licensePlateManager == nil or not g_licensePlateManager:getAreLicensePlatesAvailable() then
		return
	end
	-- Don't overwrite an existing plate (savegame-restored vehicles already carry one)
	if gv.getLicensePlatesData ~= nil then
		local existing = gv:getLicensePlatesData()
		if existing ~= nil and existing.characters ~= nil then
			return
		end
	end
	local data = g_licensePlateManager:getRandomLicensePlateData()
	if data == nil or data.characters == nil then
		return
	end
	pcall(function()
		gv:setLicensePlatesData(data)
	end)
	IAprintDebug("IANeighbourVehicle:applyRandomLicensePlatesIfPossible()", "Applied random license plate to "..tostring(self.uniqueId), self.neighbour, self, nil)
end

-- Spawn the vehicle
function IANeighbourVehicle:spawn(callbackFunction)
    if g_server == nil then
		IAprintDebug("IANeighbourVehicle:spawn()", "Can only spawn vehicles on server", self.neighbour, self, nil)
		return
	end
	
	IAprintDebug("IANeighbourVehicle:spawn()", "TRY SPAWN vehicle: "..self.xmlFilename.." at ("..tostring(self.positionX)..", "..tostring(self.positionY)..", "..tostring(self.positionZ)..")", self.neighbour, self, nil)
	--if self.xmlFilename == nil or self.positionX == nil or self.positionZ == nil then
--		if IANeighbours.debug then
			--print("--- IANeighbours:spawnVehicle() - Missing required parameters")
		--end
		--return
	--end
	
	
	-- Get terrain height if y is not provided
	local spawnY = self.positionY
	if spawnY == nil then
		spawnY = getTerrainHeightAtWorldPos(g_terrainNode, self.positionX, 0, self.positionZ) + 0.2
	end
	
	-- Create vehicle loading data
	local data = VehicleLoadingData.new()
	data:setFilename(self.xmlFilename)
	data:setPosition(0,0,0)--self.positionX, spawnY, self.positionZ)
	data:setRotation(0, 0, 0)--self.rotation, 0)
	--data:setPropertyState(VehiclePropertyState.OWNED)
	if self.colorIndex ~= nil and self.colorIndex > 0 then
		data:setConfigurations({ baseColor = self.colorIndex })
	end
	data:setOwnerFarmId(self.farmId)

	
	-- Default callback if none provided
	local asyncCallbackFunction = function(_, vehicle, loadingState)
		if loadingState == VehicleLoadingState.OK then
			local spawnedUniqueId = vehicle[1].uniqueId
			self:loadVehicleById(spawnedUniqueId)
			-- Assign a random license plate to freshly spawned vehicles (skipped if already plated)
			pcall(function() self:applyRandomLicensePlatesIfPossible() end)
			-- Fold the vehicle when situation vehicle spawns (same logic as unused-vehicle placement)
			if self.tryFold ~= nil then
				pcall(function() self:tryFold("spawn") end)
			end
			if callbackFunction ~= nil then
				callbackFunction(spawnedUniqueId)
			end
			IAprintDebug("IANeighbourVehicle:spawn()", "Spawned! UniqueId: "..tostring(spawnedUniqueId), self.neighbour, self, nil)
		else
			IAprintDebug("IANeighbourVehicle:spawn()", "Spawn Error", self.neighbour, self, nil)
			printCallstack()
		end
	end
	
	-- Load the vehicle
	data:load(asyncCallbackFunction)
	
	IAprintDebug("IANeighbourVehicle:spawn()", "Spawning vehicle: "..self.xmlFilename.." at ("..tostring(self.positionX)..", "..tostring(spawnY)..", "..tostring(self.positionZ)..")", self.neighbour, self, nil)
end