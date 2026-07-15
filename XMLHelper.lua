--
-- FS25 - InteractiveNeighbours - XML Helper
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 25.10.2022
-- @Version: 1.0.0.1
-- Helper class for XML operations

IAXMLHelper = {}
IAXMLHelper._mt = Class(IAXMLHelper)

-- Create a new IAXMLHelper instance
-- @param table ianeighboursInstance - Reference to IANeighbours instance
function IAXMLHelper.new(ianeighboursInstance)
	local self = setmetatable({}, IAXMLHelper._mt)
	self.ianeighbours = ianeighboursInstance
	self.mapConfigFile = nil
	self.scenarioConfigFile = nil
	self.mapConfigFileNotFound = false  -- true when mapId exists but no config file found
	self.modSettingsDirectory = nil  -- set in checkConfiguration: (g_modSettingsDirectory or "") .. "FS25_FIELDS_OF_STORIES/"
	self.conversationsStructureLoaded = false
	return self
end

--- Mod settings directory (persistent over savegames). Use this for places XML etc.
function IAXMLHelper:getModSettingsDirectory()
	if self.modSettingsDirectory ~= nil then
		return self.modSettingsDirectory
	end
	return (g_modSettingsDirectory or "") .. "FS25_FIELDS_OF_STORIES/"
end

--- Turn absolute paths under this install's mods / current mod into portable relative paths.
-- Strips the longest matching prefix among g_modSettingsDirectory, g_currentModDirectory, and IANeighbours.dir (same as g_currentModDirectory when set).
-- @param string p - placeableFilename, referenceFilename, etc.
-- @return string - forward slashes; relative tail if a known base matched, else unchanged (except slash normalization)
function IAXMLHelper:normalizeFsRelativePath(p)
	if p == nil then
		return nil
	end
	if type(p) ~= "string" then
		p = tostring(p)
	end
	if p == "" then
		return p
	end
	if string.sub(p, 1, 5) == "$data" or string.sub(p, 1, 5) == "data/" or string.sub(p, 1, 5) == "data\\" then
		return p:gsub("\\", "/")
	end

	local s = p:gsub("\\", "/")
	local bases = {}
	local function addBase(b)
		if b ~= nil and type(b) == "string" and b ~= "" then
			bases[#bases + 1] = b:gsub("\\", "/")
		end
	end
	addBase(g_modSettingsDirectory)
	addBase(g_currentModDirectory)
	if self.ianeighbours ~= nil then
		addBase(self.ianeighbours.dir)
	end
	-- Parent chain of current mod dir (e.g. .../mods/THIS_MOD -> .../mods matches other mods' paths)
	local cur = g_currentModDirectory
	if cur ~= nil and cur ~= "" then
		cur = cur:gsub("\\", "/")
		for _ = 1, 6 do
			local parent = cur:match("^(.*)/[^/]+$")
			if parent == nil or parent == "" or parent == cur then
				break
			end
			addBase(parent)
			cur = parent
		end
	end

	table.sort(bases, function(a, b)
		return #a > #b
	end)

	local sl = string.lower(s)
	for _, base in ipairs(bases) do
		local prefix = base
		if string.sub(prefix, -1) ~= "/" then
			prefix = prefix .. "/"
		end
		local pl = string.lower(prefix)
		if #pl > 0 and string.sub(sl, 1, #pl) == pl then
			local rest = string.sub(s, #prefix + 1)
			if string.sub(rest, 1, 1) == "/" then
				rest = string.sub(rest, 2)
			end
			return rest
		end
	end
	-- Fallback: MS Store / Steam / Epic differ; g_modSettingsDirectory may not match this absolute path.
	-- Keep portable tail from first "/mods/" segment onward (e.g. .../mods/FS25_x/file.xml -> mods/FS25_x/file.xml).
	local modsIdx = string.find(sl, "/mods/", 1, true)
	if modsIdx ~= nil then
		return string.sub(s, modsIdx + 1)
	end
	return s
end

--- Canonical key for comparing mod paths (placeableFilename vs configFileName) and i3d paths (referenceFilename).
-- Uses normalizeFsRelativePath, forward slashes, strips one leading "mods/" for non-$data paths, lowercases mod paths.
-- @param string p
-- @return string|nil
function IAXMLHelper:pathMatchKey(p)
	if p == nil then
		return nil
	end
	if type(p) ~= "string" then
		p = tostring(p)
	end
	if p == "" then
		return p
	end
	local s = self:normalizeFsRelativePath(p)
	if s == nil then
		return nil
	end
	s = s:gsub("\\", "/")
	-- Game / map data paths: keep case (may matter on some platforms)
	if string.sub(s, 1, 5) == "$data" or string.sub(s, 1, 5) == "data/" then
		return s
	end
	-- Mod folder relative: engine often omits "mods/" prefix; XML may include it
	if string.sub(string.lower(s), 1, 5) == "mods/" then
		s = string.sub(s, 6)
	end
	return string.lower(s)
end

-- Recursive function to dump XML structure
function IAXMLHelper:dumpXML(xml, name, schema)
	--local xmlnewmethod = XMLFile.loadIfExists(rootnode, "dataS/character/playerM/playerM.xml", PlayerSystem.xmlSchema)
	--printObj(xmlnewmethod,2,"xmlnewmethod222")

	local xmlobj = XMLFile.loadIfExists("", xml, schema or nil)
	if xmlobj ~= nil then
		local rootname = xmlobj:getRootName()
		print(name.." - rootname: "..tostring(rootname))
		--printObj(getmetatable(XMLFile),2,name.." - getmetatable(XMLFile)")
		--printObj(getmetatable(xmlobj),2,name.." - getmetatable(xmlobj)")
		if xmlobj ~= nil then
			print("--- IAXMLHelper:dumpXML() - "..name..": "..tostring(xmlobj:getAsString()))
		else
			print("--- IAXMLHelper:dumpXML() - "..name..": null")
		end
	else
		print("--- IAXMLHelper:dumpXML() - "..name..": null!!")
	end
end

-- Decode XML entities in a string
-- @param string text - Text containing XML entities
-- @return string - Decoded text
function IAXMLHelper:decodeXMLEntities(text)
	if text == nil then
		return nil
	end
	
	-- Common XML entity mappings
	local entities = {
		["&amp;"] = "&",
		["&lt;"] = "<",
		["&gt;"] = ">",
		["&quot;"] = "\"",
		["&apos;"] = "'",
		["&#039;"] = "'",
		["&#39;"] = "'"
	}
	
	local decoded = text
	for entity, replacement in pairs(entities) do
		decoded = string.gsub(decoded, entity, replacement)
	end
	
	-- Also handle numeric entities like &#039; (decimal) and &#x27; (hex)
	decoded = string.gsub(decoded, "&#(%d+);", function(num)
		return string.char(tonumber(num))
	end)
	decoded = string.gsub(decoded, "&#x([%da-fA-F]+);", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	
	return decoded
end

function IAXMLHelper:saveInboundXMLToXMLFile()
    if g_server ~= nil then
        local spec = self.ianeighbours
		local xmlFile = nil
        local file = string.format("%s/IANeighbours_inbound.xml", g_currentMission.missionInfo.savegameDirectory)
        
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:saveInboundXMLToXMLFile() - File: "..file)
			print("--- IAXMLHelper:saveInboundXMLToXMLFile() - IANeighbours.inboundXML: "..tostring(self.ianeighbours.inboundXML))
		end
		if self.ianeighbours.inboundXML ~= nil then
			saveXMLFile(self.ianeighbours.inboundXML)
            if self.ianeighbours.debug then
				print("--- IAXMLHelper:saveInboundXMLToXMLFile() - IANeighbours.inboundXML is not nil and will be saved")
			end
		else
			xmlFile = createXMLFile("IANeighbours_xml_temp", file, "IANeighboursInbound")
			
			-- Create empty settings element
			setXMLString(xmlFile, "IANeighboursInbound.settings", "")
			
			-- Create empty neighbours element (without neighbour entries)
			setXMLString(xmlFile, "IANeighboursInbound.neighbours", "")
			
			-- Create empty actions element
			setXMLString(xmlFile, "IANeighboursInbound.actions", "")
			saveXMLFile(xmlFile)
			delete(xmlFile)

			if self.ianeighbours.debug then
				print("--- IAXMLHelper:saveInboundXMLToXMLFile() - IANeighbours.inboundXML is nil and will be created empty")
			end
		end
    end
end

-- Check if the inbound XML file has changed by checking for trigger file
-- This is much more efficient than parsing XML every second
-- @return boolean - true if file has changed, false otherwise
function IAXMLHelper:checkInboundXMLChanged()
	if g_currentMission.missionInfo.savegameDirectory == nil then
		return false
	end
	
	local triggerFilePath = g_currentMission.missionInfo.savegameDirectory.."/IANeighbours_inbound.trigger"
	
	-- Check if trigger file exists (indicates inbound XML was updated)
	-- PowerShell script will delete the trigger file after 5 seconds
	if fileExists(triggerFilePath) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkInboundXMLChanged() - Trigger file found, inbound XML was updated")
		end
		return true
	end
	
	-- No trigger file, no changes
	return false
end

function IAXMLHelper:loadInboundXML()
	-- DISABLED: Now using loadOutboundXML() instead
	-- This method is kept for backward compatibility but does nothing
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadInboundXML() - DISABLED: Use loadOutboundXML() instead")
	end
	return false
	
	--[[ DISABLED CODE - Now using loadOutboundXML() instead
	-- Load vehicle ID mapping from outbound XML first
	if g_currentMission.missionInfo.savegameDirectory == nil then
		return
	end

	self.ianeighbours:loadVehicleIdMapping()

	local filePath = g_currentMission.missionInfo.savegameDirectory.."/IANeighbours_inbound.xml"
	
	if not fileExists(filePath) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadInboundXML() - File does not exist: "..filePath)
		end
		self:saveInboundXMLToXMLFile()
		--self.ianeighbours.inboundXML = nil
		--return false
	end
	
	local xmlFile = loadXMLFile("IANeighboursInbound", filePath)
	
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadInboundXML() - Failed to load XML file: "..filePath)
		end
		self.ianeighbours.inboundXML = nil
		return false
	end
	
	self.ianeighbours.inboundXML = xmlFile
	
	-- Read XML values and store in IANeighbours attributes
	local rootKey = "IANeighboursInbound"
	
	-- Parse settings element (if it has attributes, read them here)
	self.ianeighbours.settings = {}
	-- Settings is empty in the example, but we can add parsing here if needed
	
	-- Parse neighbours list
	local i = 0
	while true do
		local neighbourKey = rootKey..".neighbours.neighbour("..i..")"
		local neighbourName = getXMLString(xmlFile, neighbourKey.."#name", nil)
		
		if neighbourName == nil then
			break
		end
		
		-- Read all neighbour attributes
		local enabled = getXMLBool(xmlFile, neighbourKey.."#enabled", true)
		local neighbourId = getXMLInt(xmlFile, neighbourKey.."#id", nil)
		local positionX = getXMLFloat(xmlFile, neighbourKey.."#positionX", nil)
		local positionY = getXMLFloat(xmlFile, neighbourKey.."#positionY", nil)
		local positionZ = getXMLFloat(xmlFile, neighbourKey.."#positionZ", nil)
		local rotation = getXMLFloat(xmlFile, neighbourKey.."#rotation", nil)
		local action = getXMLString(xmlFile, neighbourKey.."#action", nil)
		local farmId = getXMLInt(xmlFile, neighbourKey.."#farmId", nil)
		local xmlFilename = getXMLString(xmlFile, neighbourKey.."#xmlFilename", nil)
		local activeSituationId = getXMLString(xmlFile, neighbourKey.."#activeSituationId", nil)
		local gender = getXMLString(xmlFile, neighbourKey.."#gender", nil)
		local characterVisibility = getXMLString(xmlFile, neighbourKey.."#characterVisibility", nil)
		
		-- Read appearance attributes
		local hathair = getXMLInt(xmlFile, neighbourKey.."#hathair", nil)
		local glasses = getXMLInt(xmlFile, neighbourKey.."#glasses", nil)
		local glassesColorIndex = getXMLInt(xmlFile, neighbourKey.."#glassesColorIndex", nil)
		local facegear = getXMLInt(xmlFile, neighbourKey.."#facegear", nil)
		local facegearColorIndex = getXMLInt(xmlFile, neighbourKey.."#facegearColorIndex", nil)
		local onepiece = getXMLInt(xmlFile, neighbourKey.."#onepiece", nil)
		local onepieceColorIndex = getXMLInt(xmlFile, neighbourKey.."#onepieceColorIndex", nil)
		local bottom = getXMLInt(xmlFile, neighbourKey.."#bottom", nil)
		local bottomColorIndex = getXMLInt(xmlFile, neighbourKey.."#bottomColorIndex", nil)
		local face = getXMLInt(xmlFile, neighbourKey.."#face", nil)
		local faceColorIndex = getXMLInt(xmlFile, neighbourKey.."#faceColorIndex", nil)
		local top = getXMLInt(xmlFile, neighbourKey.."#top", nil)
		local topColorIndex = getXMLInt(xmlFile, neighbourKey.."#topColorIndex", nil)
		local gloves = getXMLInt(xmlFile, neighbourKey.."#gloves", nil)
		local glovesColorIndex = getXMLInt(xmlFile, neighbourKey.."#glovesColorIndex", nil)
		local headgear = getXMLInt(xmlFile, neighbourKey.."#headgear", nil)
		local headgearColorIndex = getXMLInt(xmlFile, neighbourKey.."#headgearColorIndex", nil)
		local footwear = getXMLInt(xmlFile, neighbourKey.."#footwear", nil)
		local footwearColorIndex = getXMLInt(xmlFile, neighbourKey.."#footwearColorIndex", nil)
		local hairStyle = getXMLInt(xmlFile, neighbourKey.."#hairStyle", nil)
		local hairStyleColorIndex = getXMLInt(xmlFile, neighbourKey.."#hairStyleColorIndex", nil)
		local beard = getXMLInt(xmlFile, neighbourKey.."#beard", nil)
		local beardColorIndex = getXMLInt(xmlFile, neighbourKey.."#beardColorIndex", nil)
		
		
		-- Check if neighbour already exists
		local existingNeighbour = nil
		for _, neighbour in pairs(self.ianeighbours.neighbours) do
			if neighbour.name == neighbourName then
				existingNeighbour = neighbour
				break
			end
		end
		
		if existingNeighbour ~= nil then
			-- Update existing neighbour (only if already initialized)
			--existingNeighbour:updateFromXML(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, facegear, onepiece, bottom, face, top, gloves, headgear, footwear, hairStyle, beard)
			
			if self.ianeighbours.debug then
				--print("--- IAXMLHelper:loadInboundXML() - Updated neighbour: "..neighbourName)
			end
		else
			-- Create new neighbour instance (don't initialize yet)
			local neighbour = IANeighbour.new(neighbourId, neighbourName, enabled, positionX, positionY, positionZ, rotation, action, farmId, gender, characterVisibility, self.ianeighbours)
			table.insert(self.ianeighbours.neighbours, neighbour)
			
			if farmId ~= nil and farmId ~= 1 then
				local farm_manager = FarmManager.new()
				farm_manager:createFarm("AIFarm "..farmId,2,"admin",farmId)

				if self.ianeighbours.debug then
					--print("--- IAXMLHelper:loadInboundXML() - Added Farm: "..tostring(farm_manager:getFarmById(farmId)))
				end
			end
			
			-- Initialize the neighbour
			neighbour:initialize()
			existingNeighbour = neighbour
			--existingNeighbour:updateFromXML(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, facegear, onepiece, bottom, face, top, gloves, headgear, footwear, hairStyle, beard)
		end

		if existingNeighbour ~= nil then
			existingNeighbour:updateFromXML(enabled, positionX, positionY, positionZ, rotation, action, farmId, activeSituationId, hathair, glasses, glassesColorIndex, facegear, facegearColorIndex, onepiece, onepieceColorIndex, bottom, bottomColorIndex, face, faceColorIndex, top, topColorIndex, gloves, glovesColorIndex, headgear, headgearColorIndex, footwear, footwearColorIndex, hairStyle, hairStyleColorIndex, beard, beardColorIndex, characterVisibility)
		end


		-- Parse multiple vehicles under this neighbour
		local vehicles = {}
		local vehicleIndex = 0
		while true do
			local vehicleKey = neighbourKey..".vehicle("..vehicleIndex..")"
			local vehicleXmlFilename = getXMLString(xmlFile, vehicleKey.."#xmlFilename", nil)
			
			if self.ianeighbours.debug then
				--print("--- IAXMLHelper:loadInboundXML() - get xml content for vehicle-"..vehicleIndex..": "..tostring(vehicleXmlFilename))
			end
			if vehicleXmlFilename == nil then
				break
			end

			-- Read vehicle position values
			local vehiclePositionX = getXMLFloat(xmlFile, vehicleKey.."#positionX", nil)
			local vehiclePositionY = getXMLFloat(xmlFile, vehicleKey.."#positionY", nil)
			local vehiclePositionZ = getXMLFloat(xmlFile, vehicleKey.."#positionZ", nil)
			local vehicleRotation = getXMLFloat(xmlFile, vehicleKey.."#rotation", rotation or 0)
			local vehicleExternalId = getXMLString(xmlFile, vehicleKey.."#id", nil)
			local vehicleJobType = getXMLString(xmlFile, vehicleKey.."#jobType", nil)
			local vehicleJobTargetX = getXMLFloat(xmlFile, vehicleKey.."#jobTargetX", nil)
			local vehicleJobTargetZ = getXMLFloat(xmlFile, vehicleKey.."#jobTargetZ", nil)
			local npcOffsetX = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetX", nil)
			local npcOffsetY = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetY", nil)
			local npcOffsetZ = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetZ", nil)
			local npcOffsetRotation = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetRotation", nil)
			local vehicleType = getXMLString(xmlFile, vehicleKey.."#type", nil)
			local vehicleCategory = getXMLString(xmlFile, vehicleKey.."#category", nil)
			local vehicleActiveSituationId = getXMLString(xmlFile, vehicleKey.."#activeSituationId", nil)
			local vehicleColorIndex = getXMLInt(xmlFile, vehicleKey.."#colorIndex", nil)
			local vehicleParkingPlaceIdStr = getXMLString(xmlFile, vehicleKey.."#parkingPlaceId", nil)
			local vehicleParkingPlaceSemantic = getXMLString(xmlFile, vehicleKey.."#parkingPlaceSemantic", nil)
			local vehicleBorrowedByPlayer = getXMLBool(xmlFile, vehicleKey.."#borrowedByPlayer", false)
			local borrowReturnPlaceIdStr = getXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceId", nil)
			local borrowReturnPlaceSemantic = getXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceSemantic", nil)
			local borrowPickupX = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionX", nil)
			local borrowPickupY = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionY", nil)
			local borrowPickupZ = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionZ", nil)
			local borrowPickupRotation = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupRotation", nil)
			-- Look up uniqueId from mapping using externalId
			local vehicleUniqueId = nil
			if vehicleExternalId ~= nil then
				vehicleUniqueId = self.ianeighbours:getVehicleUniqueIdByExternalId(vehicleExternalId)
			end
			
			-- Check if vehicle already exists (by uniqueId or externalId)
			local existingVehicle = nil
			if vehicleUniqueId ~= nil then
				existingVehicle = existingNeighbour:getVehicle(vehicleUniqueId)
			end
			-- Also check by externalId if not found by uniqueId
			if existingVehicle == nil and vehicleExternalId ~= nil then
				existingVehicle = existingNeighbour:getVehicleByExternalId(vehicleExternalId)
				-- If found by externalId, update the uniqueId and mapping
				if existingVehicle ~= nil and existingVehicle.uniqueId ~= nil then
					vehicleUniqueId = existingVehicle.uniqueId
					self.ianeighbours:setVehicleIdMapping(vehicleExternalId, vehicleUniqueId)
				end
			end
			
			-- Get or create vehicle instance
			local vehicle = existingVehicle
			local isNewVehicle = false
			if vehicle == nil then
				-- Create new vehicle (uniqueId may be nil, will be looked up from mapping or generated on spawn)
				vehicle = IANeighbourVehicle.new(vehicleUniqueId, existingNeighbour.farmId, existingNeighbour)
				isNewVehicle = true
				if self.ianeighbours.debug then
					--print("--- IAXMLHelper:loadInboundXML() - Creating new vehicle: "..tostring(vehicleUniqueId))
				end
			else
				-- Update existing vehicle
				if self.ianeighbours.debug then
					--print("--- IAXMLHelper:loadInboundXML() - Updating existing vehicle: "..tostring(vehicleUniqueId))
				end
			end
			
			-- Update vehicle with all XML values (works for both new and existing vehicles)
			vehicle:updateFromXML(vehicleXmlFilename, vehicleJobType, vehicleJobTargetX, vehicleJobTargetZ, vehicleExternalId, npcOffsetX, npcOffsetY, npcOffsetZ, npcOffsetRotation, vehicleType, vehicleCategory, vehicleActiveSituationId, vehicleColorIndex)
			if vehiclePositionX ~= nil then
				vehicle.positionX = vehiclePositionX
			end
			if vehiclePositionY ~= nil then
				vehicle.positionY = vehiclePositionY
			end
			if vehiclePositionZ ~= nil then
				vehicle.positionZ = vehiclePositionZ
			end
			if vehicleParkingPlaceIdStr ~= nil then
				local pidn = tonumber(vehicleParkingPlaceIdStr)
				vehicle.parkingPlaceId = pidn or vehicleParkingPlaceIdStr
			end
			if vehicleParkingPlaceSemantic ~= nil then
				vehicle.parkingPlaceSemantic = vehicleParkingPlaceSemantic
			end
			if borrowReturnPlaceIdStr ~= nil then
				local pidn = tonumber(borrowReturnPlaceIdStr)
				vehicle.borrowReturnParkingPlaceId = pidn or borrowReturnPlaceIdStr
			end
			if borrowReturnPlaceSemantic ~= nil then
				vehicle.borrowReturnParkingPlaceSemantic = borrowReturnPlaceSemantic
			end
			if borrowPickupX ~= nil then
				vehicle.borrowPickupPositionX = borrowPickupX
			end
			if borrowPickupY ~= nil then
				vehicle.borrowPickupPositionY = borrowPickupY
			end
			if borrowPickupZ ~= nil then
				vehicle.borrowPickupPositionZ = borrowPickupZ
			end
			if borrowPickupRotation ~= nil then
				vehicle.borrowPickupRotation = borrowPickupRotation
			end
			if vehicleBorrowedByPlayer == true then
				if vehicle.borrowReturnParkingPlaceId == nil and vehicle.parkingPlaceId ~= nil then
					vehicle.borrowReturnParkingPlaceId = vehicle.parkingPlaceId
					vehicle.borrowReturnParkingPlaceSemantic = vehicle.parkingPlaceSemantic or "homebase"
				end
				vehicle.isBorrowedByPlayer = true
				if IAEquipmentPresence ~= nil then
					IAEquipmentPresence.State.setDesiredBorrowed(vehicle)
				end
			end
			
			-- Initialize new vehicles after updateFromXML
			if vehicle.initialized == false or isNewVehicle then
				vehicle:initialize(function(uniqueId, externalId, ia_vehicle)
					-- Update mapping when vehicle gets a uniqueId
					if externalId ~= nil and uniqueId ~= nil then
						self.ianeighbours:setVehicleIdMapping(externalId, uniqueId)
					end
					existingNeighbour:addVehicle(vehicle)
				end)
			end


			
			--if  vehicleUniqueId ~= nil then
			--	if vehicleJobType == "GOTO" then
			--		existingNeighbour:startAIJob(existingNeighbour:getVehicle(vehicleUniqueId),vehicleJobTargetX,vehicleJobTargetZ)
					--local vehicle = existingNeighbour:getVehicle(vehicleUniqueId)
					--if vehicle ~= nil then
					--	printObj(vehicle.spec_autodrive:GetAvailableDestinations(),2,"vehicle.spec_autodrive:GetAvailableDestinations()")
					--end
			--	else
			--		existingNeighbour:stopAIJob(existingNeighbour:getVehicle(vehicleUniqueId))
			--	end
			--end
			
			
			
			vehicleIndex = vehicleIndex + 1
		end

		
		i = i + 1
	end
	
	-- Parse nearbySituation element
	local nearbySituationKey = rootKey..".nearbySituation"
	local nearbySituationId = getXMLString(xmlFile, nearbySituationKey.."#id", nil)
	
	if nearbySituationId ~= nil then
		-- Check if IANeighbours has a nearbySituation and if the ID matches
		if self.ianeighbours.nearbySituation ~= nil then
			local situation = self.ianeighbours.nearbySituation
			local situationIdStr = tostring(situation.id)
			
			if situationIdStr == nearbySituationId then
				-- Parse dialog messages from XML
				local parsedMessages = {}
				local messageIndex = 0
				while true do
					local messageKey = nearbySituationKey..".dialogMessages.message("..messageIndex..")"
					local messageId = getXMLInt(xmlFile, messageKey.."#id", nil)
					
					if messageId == nil then
						break
					end
					
					local messageText = getXMLString(xmlFile, messageKey.."#text", nil)
					local messageSender = getXMLString(xmlFile, messageKey.."#sender", nil)
					
					if messageText ~= nil and messageSender ~= nil then
						-- Decode XML entities (like &#039; to ')
						messageText = self:decodeXMLEntities(messageText)
						
						table.insert(parsedMessages, {
							id = messageId,
							text = messageText,
							sender = messageSender
						})
					end
					
					messageIndex = messageIndex + 1
				end
				
				-- Merge new messages into the situation
				if #parsedMessages > 0 then
					local newMessageCount = situation:mergeMessagesFromXML(parsedMessages)
					if self.ianeighbours.debug then
						print("--- IAXMLHelper:loadInboundXML() - Merged "..tostring(newMessageCount).." new messages into situation "..nearbySituationId)
					end
				end
			else
				if self.ianeighbours.debug then
					print("--- IAXMLHelper:loadInboundXML() - Situation ID mismatch: XML="..nearbySituationId..", current="..situationIdStr)
				end
			end
		else
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadInboundXML() - No nearbySituation found, skipping message merge for situation "..nearbySituationId)
			end
		end
	end
	
	-- Parse actions element (if it has attributes, read them here)
	self.ianeighbours.actions = {}
	-- Actions is empty in the example, but we can add parsing here if needed
	
	-- Collect all uniqueIds from vehicles in the inbound XML
	local vehiclesInXML = {}
	for _, neighbour in pairs(self.ianeighbours.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia_vehicle in pairs(neighbour.vehicles) do
				if ia_vehicle ~= nil and ia_vehicle.uniqueId ~= nil then
					vehiclesInXML[ia_vehicle.uniqueId] = true
				end
			end
		end
	end
	
	-- Also collect uniqueIds from the mapping (vehicles that might not be initialized yet)
	for externalId, uniqueId in pairs(self.ianeighbours.vehicleIdMapping) do
		if uniqueId ~= nil then
			vehiclesInXML[uniqueId] = true
		end
	end
	
	-- Find lost/old vehicles: vehicles with ownerFarmId 0, 6, or 7 that are not in the inbound XML
	if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
		local lostVehicles = {}
		for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
			if vehicle ~= nil then
				local uniqueId = vehicle:getUniqueId()
				if uniqueId ~= nil then
					-- Try to get ownerFarmId (method or property)
					local ownerFarmId = nil
					if vehicle.getOwnerFarmId ~= nil then
						ownerFarmId = vehicle:getOwnerFarmId()
					elseif vehicle.ownerFarmId ~= nil then
						ownerFarmId = vehicle.ownerFarmId
					end
					
					if ownerFarmId ~= nil and (ownerFarmId == 0) then
						-- Check if this vehicle is not in the inbound XML
						if not vehiclesInXML[uniqueId] then
							table.insert(lostVehicles, {
								uniqueId = uniqueId,
								ownerFarmId = ownerFarmId
							})
							vehicle:removeFromPhysics()
							vehicle:setVisibility(false)
							vehicle:delete(true)
							if self.ianeighbours.debug then
								print("--- IAXMLHelper:loadInboundXML() - Found lost/old vehicle (isDeleted: "..tostring(vehicle.isDeleted).."): uniqueId="..tostring(uniqueId)..", ownerFarmId="..tostring(ownerFarmId))
							end
						end
					end
				end
			end
		end
		
		if #lostVehicles > 0 then
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadInboundXML() - Found "..tostring(#lostVehicles).." lost/old vehicles")
			end
			-- Store lost vehicles for potential cleanup or reporting
			self.ianeighbours.lostVehicles = lostVehicles
		end
	end
	
	if self.ianeighbours.debug then
		--print("--- IAXMLHelper:loadInboundXML() - Successfully loaded XML file: "..filePath)
		--print("--- Loaded "..tostring(#self.ianeighbours.neighbours).." neighbours")
	end
	
	return true
	end --]]
end

-- Check if configuration data is set before loading XML
-- @return boolean - true if configuration is valid, false otherwise
function IAXMLHelper:checkConfiguration()
	if g_currentMission == nil or g_currentMission.missionInfo == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Mission info not available")
		end
		return false
	end
	
	-- Mod settings directory (persistent over savegames)
	local modSettingsDirectory = (g_modSettingsDirectory or "") .. "FS25_FIELDS_OF_STORIES/"
	self.modSettingsDirectory = modSettingsDirectory
	
	-- Initialize mod settings directory if it doesn't exist
	if not folderExists(modSettingsDirectory) then
		createFolder(modSettingsDirectory)
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Created mod settings directory: "..modSettingsDirectory)
		end
	end
	
	-- Check for map-specific config file
	local mapId = g_currentMission.missionInfo.mapId
	if mapId == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Map ID is nil")
		end
		return false
	end
	

	-- Single map config file: fields_of_stories_<mapId>.xml with priority mod settings > mod folder
	local mapConfigFileCustom = modSettingsDirectory .. "fields_of_stories_" .. mapId .. ".xml"
	local mapConfigFileDefault = self.ianeighbours.dir .. "default_maps/fields_of_stories_" .. mapId .. ".xml"
	if fileExists(mapConfigFileCustom) then
		self.mapConfigFile = mapConfigFileCustom
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Map config file (mod settings): "..self.mapConfigFile)
		end
	elseif fileExists(mapConfigFileDefault) then
		self.mapConfigFile = mapConfigFileDefault
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Map config file (mod folder): "..self.mapConfigFile)
		end
	else
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Map config file not found (tried mod settings and mod folder)")
		end
	end
	
	if self.mapConfigFile ~= nil then
		self.mapConfigFileNotFound = false
	else
		self.mapConfigFileNotFound = (mapId ~= nil)  -- true when we have mapId but no config file; still load neighbours/vehicles below
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Map config file not found, will still load scenario/neighbours if available")
		end
	end
	
	-- Check for scenario config file in savegame directory (only available once the game has been saved).
	-- Missing savegame dir is no longer fatal: the mod-folder preset below seeds a fresh game before the first save.
	if g_currentMission.missionInfo.savegameDirectory ~= nil then
		local scenarioConfigFile = g_currentMission.missionInfo.savegameDirectory .. "/fields_of_stories_scenario.xml"
		if not fileExists(scenarioConfigFile) then
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:checkConfiguration() - Scenario config file not found: "..scenarioConfigFile)
			end
		else 
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:checkConfiguration() - Scenario config file found: "..scenarioConfigFile)
			end
			self.scenarioConfigFile = scenarioConfigFile
		end
	elseif self.ianeighbours.debug then
		print("--- IAXMLHelper:checkConfiguration() - Savegame directory is nil; using preset scenario seed")
	end

	local scenarioConfigFilePreset =  self.ianeighbours.dir .. "default_scenarios/fields_of_stories_scenario.xml"
	if not fileExists(scenarioConfigFilePreset) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Scenario config file preset not found: "..scenarioConfigFilePreset)
		end
	else 
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkConfiguration() - Scenario config file preset found: "..scenarioConfigFilePreset)
		end
		self.scenarioConfigFile = scenarioConfigFilePreset
	end

	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:checkConfiguration() - Configuration is valid (scenarioConfigFile="..tostring(self.scenarioConfigFile)..")")
	end
	
	return true
end

-- Load a single neighbour from XML (handles both outbound and scenario formats)
-- @param xmlFile - The XML file handle
-- @param neighbourKey - The XML key path for the neighbour (e.g., "IANeighboursOutbound.neighbours.neighbour(0)")
-- @param rootKey - The root key of the XML document (optional, for compatibility)
-- @param deferInitialize boolean|nil - If true, skip :initialize() for a newly created neighbour (caller must call after map assignments)
-- @return IANeighbour|nil - The loaded or updated neighbour, or nil if not found
function IAXMLHelper:loadNeighbourFromXML(xmlFile, neighbourKey, rootKey, deferInitialize)
	local nameEn = getXMLString(xmlFile, neighbourKey.."#name", nil)
	if nameEn == nil then
		return nil
	end
	local nameDe = getXMLString(xmlFile, neighbourKey.."#nameDe", nil)
	local neighbourName = nameEn
	if getDisplayLanguageCode() == "de" and nameDe ~= nil and nameDe ~= "" then
		neighbourName = nameDe
	end
	
	-- Read common neighbour attributes (both formats)
	local neighbourId = getXMLInt(xmlFile, neighbourKey.."#id", nil)
	local gender = getXMLString(xmlFile, neighbourKey.."#gender", nil)
	
	-- Read outbound XML format attributes (may be nil for scenario format)
	local enabled = true--getXMLBool(xmlFile, neighbourKey.."#enabled", true)
	local positionX = getXMLFloat(xmlFile, neighbourKey.."#positionX", nil)
	local positionY = getXMLFloat(xmlFile, neighbourKey.."#positionY", nil)
	local positionZ = getXMLFloat(xmlFile, neighbourKey.."#positionZ", nil)
	local rotation = getXMLFloat(xmlFile, neighbourKey.."#rotation", nil)
	local action = getXMLString(xmlFile, neighbourKey.."#action", nil)
	local farmId = getXMLInt(xmlFile, neighbourKey.."#farmId", nil)
	local characterVisibility = getXMLString(xmlFile, neighbourKey.."#characterVisibility", nil)
	local activeSituationId = getXMLString(xmlFile, neighbourKey.."#activeSituationId", nil)
	
	
	-- Read scenario XML format attributes (may be nil for outbound format)
	local age = getXMLString(xmlFile, neighbourKey.."#age", nil)
	local relationship = getXMLString(xmlFile, neighbourKey.."#relationship", nil)
	local relationshipLevel = getXMLInt(xmlFile, neighbourKey.."#relationshipLevel", nil)
	local relationshipScore = getXMLInt(xmlFile, neighbourKey.."#relationshipScore", nil)
	local role = getXMLString(xmlFile, neighbourKey.."#role", nil)
	local job = getXMLString(xmlFile, neighbourKey.."#job", nil)
	local belongsToFarm = getXMLBool(xmlFile, neighbourKey.."#belongsToFarm", nil)
	local defaultPlaceId = getXMLInt(xmlFile, neighbourKey.."#defaultPlaceId", nil)
	local assignedHomebasePlaceIds = {}
	local placeIdIndex = 0
	while true do
		local id = getXMLInt(xmlFile, neighbourKey..".assignedHomebasePlaceIds.placeId("..placeIdIndex..")#id", nil)
		if id == nil then
			break
		end
		table.insert(assignedHomebasePlaceIds, id)
		placeIdIndex = placeIdIndex + 1
	end
	local assignedWorkplacePlaceIds = {}
	local workplacePlaceIdIndex = 0
	while true do
		local wid = getXMLInt(xmlFile, neighbourKey..".assignedWorkplacePlaceIds.placeId("..workplacePlaceIdIndex..")#id", nil)
		if wid == nil then
			break
		end
		table.insert(assignedWorkplacePlaceIds, wid)
		workplacePlaceIdIndex = workplacePlaceIdIndex + 1
	end
	local roleScenarioDescription = getXMLString(xmlFile, neighbourKey..".roleScenarioDescription", nil)
	local roleScenarioDescriptionDe = getXMLString(xmlFile, neighbourKey..".roleScenarioDescriptionDe", nil)
	
	-- Read behaviour items (scenario format)
	local behaviours = {}
	local behaviourIndex = 0
	while true do
		local behaviourKey = neighbourKey..".behaviour.item("..behaviourIndex..")"
		local behaviour = getXMLString(xmlFile, behaviourKey, nil)
		if behaviour == nil then
			break
		end
		table.insert(behaviours, behaviour)
		behaviourIndex = behaviourIndex + 1
	end
	
	-- Read style attributes (both formats)
	local hathair = getXMLInt(xmlFile, neighbourKey.."#hathair", nil)
	local glasses = getXMLInt(xmlFile, neighbourKey.."#glasses", nil)
	local glassesColorIndex = getXMLInt(xmlFile, neighbourKey.."#glassesColorIndex", nil)
	local facegear = getXMLInt(xmlFile, neighbourKey.."#facegear", nil)
	local facegearColorIndex = getXMLInt(xmlFile, neighbourKey.."#facegearColorIndex", nil)
	local onepiece = getXMLInt(xmlFile, neighbourKey.."#onepiece", nil)
	local onepieceColorIndex = getXMLInt(xmlFile, neighbourKey.."#onepieceColorIndex", nil)
	local bottom = getXMLInt(xmlFile, neighbourKey.."#bottom", nil)
	local bottomColorIndex = getXMLInt(xmlFile, neighbourKey.."#bottomColorIndex", nil)
	local face = getXMLInt(xmlFile, neighbourKey.."#face", nil)
	local faceColorIndex = getXMLInt(xmlFile, neighbourKey.."#faceColorIndex", nil)
	local top = getXMLInt(xmlFile, neighbourKey.."#top", nil)
	local topColorIndex = getXMLInt(xmlFile, neighbourKey.."#topColorIndex", nil)
	local gloves = getXMLInt(xmlFile, neighbourKey.."#gloves", nil)
	local glovesColorIndex = getXMLInt(xmlFile, neighbourKey.."#glovesColorIndex", nil)
	local headgear = getXMLInt(xmlFile, neighbourKey.."#headgear", nil)
	local headgearColorIndex = getXMLInt(xmlFile, neighbourKey.."#headgearColorIndex", nil)
	local footwear = getXMLInt(xmlFile, neighbourKey.."#footwear", nil)
	local footwearColorIndex = getXMLInt(xmlFile, neighbourKey.."#footwearColorIndex", nil)
	local hairStyle = getXMLInt(xmlFile, neighbourKey.."#hairStyle", nil)
	local hairStyleColorIndex = getXMLInt(xmlFile, neighbourKey.."#hairStyleColorIndex", nil)
	local beard = getXMLInt(xmlFile, neighbourKey.."#beard", nil)
	local beardColorIndex = getXMLInt(xmlFile, neighbourKey.."#beardColorIndex", nil)
	
	-- Set defaults for scenario format if outbound format fields are missing
	if farmId == nil then
		farmId = 99  -- Default farm ID for NPCs
	end
	if characterVisibility == nil then
		characterVisibility = "yes"
	end
	
	-- Check if neighbour already exists (by id or name)
	local existingNeighbour = nil
	if neighbourId ~= nil then
		for _, neighbour in pairs(self.ianeighbours.neighbours) do
			if neighbour.id == neighbourId then
				existingNeighbour = neighbour
				break
			end
		end
	end
	if existingNeighbour == nil then
		for _, neighbour in pairs(self.ianeighbours.neighbours) do
			if neighbour.name == neighbourName then
				existingNeighbour = neighbour
				break
			end
		end
	end
	
	-- Create or update neighbour
	if existingNeighbour == nil then
		existingNeighbour = IANeighbour.new(neighbourId, neighbourName, enabled, nil, nil, nil, nil, nil, farmId, gender, nil, self.ianeighbours)
		table.insert(self.ianeighbours.neighbours, existingNeighbour)
		
		-- Store scenario-specific data if present
		if age ~= nil then existingNeighbour.age = age end
		if relationship ~= nil then existingNeighbour.relationship = relationship end
		if relationshipLevel ~= nil then existingNeighbour.relationshipLevel = relationshipLevel end
		if relationshipScore ~= nil then existingNeighbour.relationshipScore = relationshipScore end
		if role ~= nil then existingNeighbour.role = role end
		if job ~= nil then existingNeighbour.job = job end
		if belongsToFarm ~= nil then existingNeighbour.belongsToFarm = belongsToFarm end
		if defaultPlaceId ~= nil then existingNeighbour.defaultPlaceId = defaultPlaceId end
		if #assignedHomebasePlaceIds > 0 then existingNeighbour.assignedHomebasePlaceIds = assignedHomebasePlaceIds end
		if #assignedWorkplacePlaceIds > 0 then existingNeighbour.assignedWorkplacePlaceIds = assignedWorkplacePlaceIds end
		if roleScenarioDescription ~= nil then existingNeighbour.roleScenarioDescription = roleScenarioDescription end
		if roleScenarioDescriptionDe ~= nil then existingNeighbour.roleScenarioDescriptionDe = roleScenarioDescriptionDe end
		if nameEn ~= nil then existingNeighbour.nameEn = nameEn end
		if nameDe ~= nil then existingNeighbour.nameDe = nameDe end
		if #behaviours > 0 then existingNeighbour.behaviours = behaviours end
		
		-- Create farm if needed
		if farmId ~= nil and farmId ~= 1 then
			local farm_manager = FarmManager.new()
			farm_manager:createFarm("AIFarm "..farmId, 2, "admin", farmId)
		end
		
		-- Pre-set styleAttributes from saved XML BEFORE initialize() starts async HumanModel spawn.
		-- If onHumanModelBaseLoaded fires before updateFromXML runs, _mergeSpawnStyleParams()
		-- would use hardcoded defaults (onepiece=5 → top=0, bottom=0) → NPC appears without clothes.
		-- By setting styleAttributes here, the async spawn callback already sees saved clothing values.
		if hathair ~= nil or glasses ~= nil or facegear ~= nil or onepiece ~= nil or bottom ~= nil or
		   face ~= nil or top ~= nil or gloves ~= nil or headgear ~= nil or footwear ~= nil or
		   hairStyle ~= nil or beard ~= nil then
			local hasOnePiece = onepiece ~= nil and onepiece > 0
			local topIdx = hasOnePiece and 0 or (top or 0)
			local bottomIdx = hasOnePiece and 0 or (bottom or 0)
			local topCol = hasOnePiece and 1 or (topColorIndex or 1)
			local bottomCol = hasOnePiece and 1 or (bottomColorIndex or 1)
			existingNeighbour.styleAttributes = {
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
				beardColorIndex = beardColorIndex or 1,
			}
			IAprintDebug("IAXMLHelper:loadNeighbourFromXML", "SET styleAttributes BEFORE initialize id=" .. tostring(neighbourId) .. " name=" .. tostring(neighbourName) .. " onepiece=" .. tostring(onepiece) .. " top=" .. tostring(top) .. " bottom=" .. tostring(bottom) .. " footwear=" .. tostring(footwear))
		else
			IAprintDebug("IAXMLHelper:loadNeighbourFromXML", "NO styleAttributes from XML, will use defaults id=" .. tostring(neighbourId) .. " name=" .. tostring(neighbourName))
		end
		
		if deferInitialize ~= true then
			IAprintDebug("IAXMLHelper:loadNeighbourFromXML", "CALLING initialize() id=" .. tostring(neighbourId) .. " name=" .. tostring(neighbourName))
			existingNeighbour:initialize()
		else
			IAprintDebug("IAXMLHelper:loadNeighbourFromXML", "DEFERRED initialize id=" .. tostring(neighbourId) .. " name=" .. tostring(neighbourName))
		end

		
		-- Load assigned farmlands and last crop per farmland
		if existingNeighbour.assignedFarmlands == nil then
			existingNeighbour.assignedFarmlands = {}
		end
		if existingNeighbour.assignedFarmlandLastCrop == nil then
			existingNeighbour.assignedFarmlandLastCrop = {}
		end
		if existingNeighbour.assignedFarmlandNextCrop == nil then
			existingNeighbour.assignedFarmlandNextCrop = {}
		end
		local farmlandIndex = 0
		while true do
			local farmlandKey = neighbourKey..".assignedFarmlands.farmland("..farmlandIndex..")"
			local farmlandId = getXMLInt(xmlFile, farmlandKey.."#id", nil)
			if farmlandId == nil then
				break
			end
			table.insert(existingNeighbour.assignedFarmlands, farmlandId)
			local lastCrop = getXMLInt(xmlFile, farmlandKey.."#lastCrop", nil)
			if lastCrop ~= nil then
				existingNeighbour.assignedFarmlandLastCrop[farmlandId] = lastCrop
			end
			local nextCrop = getXMLInt(xmlFile, farmlandKey.."#nextCrop", nil)
			if nextCrop ~= nil then
				existingNeighbour.assignedFarmlandNextCrop[farmlandId] = nextCrop
			end
			farmlandIndex = farmlandIndex + 1
		end
		
		
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadNeighbourFromXML() - Created new neighbour: "..neighbourName)
		end
	else
		-- Update existing neighbour
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadNeighbourFromXML() - Updating existing neighbour: "..neighbourName)
		end
		
		-- Update scenario-specific data if present
		if age ~= nil then existingNeighbour.age = age end
		if relationship ~= nil then existingNeighbour.relationship = relationship end
		if relationshipLevel ~= nil then existingNeighbour.relationshipLevel = relationshipLevel end
		if relationshipScore ~= nil then existingNeighbour.relationshipScore = relationshipScore end
		if role ~= nil then existingNeighbour.role = role end
		if job ~= nil then existingNeighbour.job = job end
		if belongsToFarm ~= nil then existingNeighbour.belongsToFarm = belongsToFarm end
		if defaultPlaceId ~= nil then existingNeighbour.defaultPlaceId = defaultPlaceId end
		if #assignedHomebasePlaceIds > 0 then existingNeighbour.assignedHomebasePlaceIds = assignedHomebasePlaceIds end
		if #assignedWorkplacePlaceIds > 0 then existingNeighbour.assignedWorkplacePlaceIds = assignedWorkplacePlaceIds end
		if roleScenarioDescription ~= nil then existingNeighbour.roleScenarioDescription = roleScenarioDescription end
		if roleScenarioDescriptionDe ~= nil then existingNeighbour.roleScenarioDescriptionDe = roleScenarioDescriptionDe end
		if nameEn ~= nil then existingNeighbour.nameEn = nameEn end
		if nameDe ~= nil then existingNeighbour.nameDe = nameDe end
		if #behaviours > 0 then existingNeighbour.behaviours = behaviours end
		
		-- Load assigned farmlands and last crop per farmland
		if existingNeighbour.assignedFarmlands == nil then
			existingNeighbour.assignedFarmlands = {}
		end
		if existingNeighbour.assignedFarmlandLastCrop == nil then
			existingNeighbour.assignedFarmlandLastCrop = {}
		end
		if existingNeighbour.assignedFarmlandNextCrop == nil then
			existingNeighbour.assignedFarmlandNextCrop = {}
		end
		local farmlandIndex = 0
		while true do
			local farmlandKey = neighbourKey..".assignedFarmlands.farmland("..farmlandIndex..")"
			local farmlandId = getXMLInt(xmlFile, farmlandKey.."#id", nil)
			if farmlandId == nil then
				break
			end
			table.insert(existingNeighbour.assignedFarmlands, farmlandId)
			local lastCrop = getXMLInt(xmlFile, farmlandKey.."#lastCrop", nil)
			if lastCrop ~= nil then
				existingNeighbour.assignedFarmlandLastCrop[farmlandId] = lastCrop
			end
			local nextCrop = getXMLInt(xmlFile, farmlandKey.."#nextCrop", nil)
			if nextCrop ~= nil then
				existingNeighbour.assignedFarmlandNextCrop[farmlandId] = nextCrop
			end
			farmlandIndex = farmlandIndex + 1
		end
		
	end

	-- Daily fieldwork schedule (year/month/dayInPeriod + ordered tasks)
	if existingNeighbour ~= nil then
		local fsKey = neighbourKey..".fieldworkSchedule"
		existingNeighbour.fieldworkScheduleYear = getXMLInt(xmlFile, fsKey.."#year", nil)
		existingNeighbour.fieldworkScheduleMonth = getXMLInt(xmlFile, fsKey.."#month", nil)
		existingNeighbour.fieldworkScheduleDayInPeriod = getXMLInt(xmlFile, fsKey.."#dayInPeriod", nil)
		existingNeighbour.fieldworkScheduleTasks = {}
		local taskIndex = 0
		while true do
			local taskKey = fsKey..".task("..taskIndex..")"
			local situationIdStr = getXMLString(xmlFile, taskKey.."#situationId", nil)
			if situationIdStr == nil or situationIdStr == "" then
				break
			end
			local farmlandIdSched = getXMLInt(xmlFile, taskKey.."#farmlandId", nil)
			if farmlandIdSched ~= nil then
				local row = { situationId = situationIdStr, farmlandId = farmlandIdSched }
				local seedIdx = getXMLInt(xmlFile, taskKey.."#seedFruitTypeIndex", nil)
				if seedIdx ~= nil then
					row.seedFruitTypeIndex = seedIdx
				end
				if getXMLBool(xmlFile, taskKey.."#contractEnabled", false) then
					row.contractEnabled = true
				end
				if getXMLBool(xmlFile, taskKey.."#acceptedByPlayer", false) then
					row.acceptedByPlayer = true
				end
				table.insert(existingNeighbour.fieldworkScheduleTasks, row)
			end
			taskIndex = taskIndex + 1
		end
		existingNeighbour.callPlayerHour = getXMLInt(xmlFile, neighbourKey.."#callPlayerHour", nil)
		existingNeighbour.callPlayerMinute = getXMLInt(xmlFile, neighbourKey.."#callPlayerMinute", nil)
		local cfs = getXMLString(xmlFile, neighbourKey.."#contractCallTriggerFiredForScheduleKey", "")
		existingNeighbour.contractCallTriggerFiredForScheduleKey = (cfs ~= nil and cfs ~= "") and cfs or nil
		local cff = getXMLString(xmlFile, neighbourKey.."#contractFallbackToAiFiredForScheduleKey", "")
		existingNeighbour.contractFallbackToAiFiredForScheduleKey = (cff ~= nil and cff ~= "") and cff or nil
		local clrsk = getXMLString(xmlFile, neighbourKey.."#contractCallLastRingScheduleKey", "")
		existingNeighbour.contractCallLastRingScheduleKey = (clrsk ~= nil and clrsk ~= "") and clrsk or nil
		existingNeighbour.contractCallLastRingTotalMinutes = getXMLInt(xmlFile, neighbourKey.."#contractCallLastRingTotalMinutes", nil)
		local rc = tonumber(getXMLInt(xmlFile, neighbourKey.."#contractCallRingOpensCount", 0)) or 0
		if rc < 0 then
			rc = 0
		end
		local rcMax = tonumber((IAGameLoopHelper ~= nil and IAGameLoopHelper.CONTRACT_CALL_MAX_RING_OPENS_PER_DAY) or 3) or 3
		if rc > rcMax then
			rc = rcMax
		end
		existingNeighbour.contractCallRingOpensCount = rc
		existingNeighbour.contractCallRingAnsweredToday = getXMLBool(xmlFile, neighbourKey.."#contractCallRingAnsweredToday", false)
	end

	-- Backward compatibility: old outbound XMLs won't have these fields yet.
	if existingNeighbour ~= nil and existingNeighbour.relationshipLevel == nil then
		existingNeighbour.relationshipLevel = 1
	end
	if existingNeighbour ~= nil and existingNeighbour.relationshipScore == nil then
		existingNeighbour.relationshipScore = 0
	end
	
	-- Ensure assignedHomebasePlaceIds exists on existing neighbour (for update path when no ids in XML)
	if existingNeighbour ~= nil and existingNeighbour.assignedHomebasePlaceIds == nil then
		existingNeighbour.assignedHomebasePlaceIds = {}
	end
	if existingNeighbour ~= nil and existingNeighbour.assignedWorkplacePlaceIds == nil then
		existingNeighbour.assignedWorkplacePlaceIds = {}
	end
	
	-- Update neighbour with all XML values
	if existingNeighbour ~= nil then
		
		-- Update real position and rotation if available (outbound format)
		local situationId = nil


		-- Create situation from first assigned homebase place id (or defaultPlaceId) if no situation exists
		if existingNeighbour.activeSituation == nil and self.ianeighbours.places ~= nil then
			local place = nil
			if existingNeighbour.assignedHomebasePlaceIds ~= nil and #existingNeighbour.assignedHomebasePlaceIds > 0 then
				local firstId = existingNeighbour.assignedHomebasePlaceIds[1]
				for _, p in pairs(self.ianeighbours.places) do
					if p ~= nil and p.id == firstId then
						place = p
						break
					end
				end
				if place ~= nil then
					situationId = "place_"..tostring(firstId)
				end
			end
			if place == nil and defaultPlaceId ~= nil then
				for _, p in pairs(self.ianeighbours.places) do
					if p ~= nil and p.id == defaultPlaceId then
						place = p
						break
					end
				end
				if place ~= nil then
					situationId = "place_"..tostring(defaultPlaceId)
				end
			end
			if place ~= nil then
				positionX = place.x
				positionY = place.y
				positionZ = place.z
				rotation = place.rotation
				if self.ianeighbours.debug then
					print("--- IAXMLHelper:loadNeighbourFromXML() - Created situation from place for existing neighbour: "..place.name.." (place id "..tostring(place.id)..")")
				end
			else
				if self.ianeighbours.debug and (existingNeighbour.assignedHomebasePlaceIds == nil or #existingNeighbour.assignedHomebasePlaceIds == 0) and defaultPlaceId == nil then
					print("--- IAXMLHelper:loadNeighbourFromXML() - No place found for neighbour: "..neighbourName)
				end
			end
		end

			IAprintDebug("IAXMLHelper:loadNeighbourFromXML", "LATE updateFromXML id=" .. tostring(neighbourId) .. " name=" .. tostring(neighbourName) .. " onepiece=" .. tostring(onepiece) .. " top=" .. tostring(top) .. " bottom=" .. tostring(bottom))
		existingNeighbour:updateFromXML(enabled, positionX, positionY, positionZ, rotation, nil, farmId, situationId, hathair, glasses, glassesColorIndex, facegear, facegearColorIndex, onepiece, onepieceColorIndex, bottom, bottomColorIndex, face, faceColorIndex, top, topColorIndex, gloves, glovesColorIndex, headgear, headgearColorIndex, footwear, footwearColorIndex, hairStyle, hairStyleColorIndex, beard, beardColorIndex, characterVisibility)
		


	end

	if existingNeighbour ~= nil and neighbourName ~= nil then
		existingNeighbour.name = neighbourName
	end

	return existingNeighbour
end

function IAXMLHelper:removeOutboundFileIfExists(path)
	if path == nil or path == "" then
		return
	end
	-- Savegame paths may be visible to fileExists but deleteFile/removeFile are blocked by the mod sandbox; pcall so LUA errors never propagate.
	local existsOk, stillThere = false, false
	if fileExists ~= nil then
		existsOk, stillThere = pcall(fileExists, path)
	end
	if not existsOk or not stillThere then
		return
	end
	local function tryDelete(fn, p)
		if fn == nil then
			return
		end
		local ok, err = pcall(fn, p)
		if not ok and self.ianeighbours ~= nil and self.ianeighbours.debug then
			print("--- IAXMLHelper:removeOutboundFileIfExists() - could not delete "..tostring(p)..": "..tostring(err))
		end
	end
	if deleteFile ~= nil then
		tryDelete(deleteFile, path)
	end
	if fileExists ~= nil then
		local ok2, left = pcall(fileExists, path)
		if ok2 and left and removeFile ~= nil then
			tryDelete(removeFile, path)
		end
	end
	if fileExists ~= nil then
		local ok3, left2 = pcall(fileExists, path)
		if ok3 and left2 and os ~= nil and os.remove ~= nil then
			tryDelete(os.remove, path)
		end
	end
end

-- Load vehicles for a neighbour from XML (handles both outbound and scenario formats)
-- @param xmlFile - The XML file handle
-- @param neighbourKey - The XML key path for the neighbour (e.g., "IANeighboursOutbound.neighbours.neighbour(0)")
-- @param existingNeighbour - The IANeighbour instance to add vehicles to
function IAXMLHelper:loadVehiclesFromXML(xmlFile, neighbourKey, existingNeighbour)
	if existingNeighbour == nil then
		return
	end

	-- Parse vehicles for this neighbour
	local vehicleIndex = 0
	while true do
		local vehicleKey = neighbourKey..".vehicle("..vehicleIndex..")"
		
		-- Try to detect format: outbound has uniqueId, scenario has id
		local vehicleUniqueIdStr = getXMLString(xmlFile, vehicleKey.."#uniqueId", nil)
		local vehicleId = getXMLString(xmlFile, vehicleKey.."#id", nil)
		
		-- If neither exists, no more vehicles
		if vehicleUniqueIdStr == nil and vehicleId == nil then
			break
		end

		local vehicleUniqueId = nil
		if vehicleUniqueIdStr ~= nil then
			vehicleUniqueId = vehicleUniqueIdStr
		end
		
		-- Read outbound XML format attributes
		local vehicleExternalId = getXMLString(xmlFile, vehicleKey.."#id", nil)
		local xmlFilename = getXMLString(xmlFile, vehicleKey.."#xmlFilename", nil)
		local vehiclePositionX = getXMLFloat(xmlFile, vehicleKey.."#positionX", nil)
		local vehiclePositionY = getXMLFloat(xmlFile, vehicleKey.."#positionY", nil)
		local vehiclePositionZ = getXMLFloat(xmlFile, vehicleKey.."#positionZ", nil)
		local vehicleRotation = getXMLFloat(xmlFile, vehicleKey.."#rotation", nil)
		--local vehicleFarmId = getXMLInt(xmlFile, vehicleKey.."#farmId", nil)
		local vehicleActiveSituationId = getXMLString(xmlFile, vehicleKey.."#activeSituationId", nil)
		local vehicleType = getXMLString(xmlFile, vehicleKey.."#type", nil)
		local npcOffsetX = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetX", nil)
		local npcOffsetY = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetY", nil)
		local npcOffsetZ = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetZ", nil)
		local npcOffsetRotation = getXMLFloat(xmlFile, vehicleKey.."#npcOffsetRotation", nil)
		local realPositionX = getXMLFloat(xmlFile, vehicleKey.."#realPositionX", nil)
		local realPositionY = getXMLFloat(xmlFile, vehicleKey.."#realPositionY", nil)
		local realPositionZ = getXMLFloat(xmlFile, vehicleKey.."#realPositionZ", nil)
		local realRotation = getXMLFloat(xmlFile, vehicleKey.."#realRotation", nil)
		local npcPositionX = getXMLFloat(xmlFile, vehicleKey.."#npcPositionX", nil)
		local npcPositionY = getXMLFloat(xmlFile, vehicleKey.."#npcPositionY", nil)
		local npcPositionZ = getXMLFloat(xmlFile, vehicleKey.."#npcPositionZ", nil)
		local npcRotation = getXMLFloat(xmlFile, vehicleKey.."#npcRotation", nil)
		local jobType = getXMLString(xmlFile, vehicleKey.."#jobType", nil)
		local jobTargetX = getXMLFloat(xmlFile, vehicleKey.."#jobTargetX", nil)
		local jobTargetZ = getXMLFloat(xmlFile, vehicleKey.."#jobTargetZ", nil)
		local parkingPlaceIdStr = getXMLString(xmlFile, vehicleKey.."#parkingPlaceId", nil)
		local parkingPlaceSemantic = getXMLString(xmlFile, vehicleKey.."#parkingPlaceSemantic", nil)
		local vehicleBorrowedByPlayer = getXMLBool(xmlFile, vehicleKey.."#borrowedByPlayer", false)
		local borrowReturnPlaceIdStr = getXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceId", nil)
		local borrowReturnPlaceSemantic = getXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceSemantic", nil)
		local borrowPickupX = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionX", nil)
		local borrowPickupY = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionY", nil)
		local borrowPickupZ = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionZ", nil)
		local borrowPickupRotation = getXMLFloat(xmlFile, vehicleKey.."#borrowPickupRotation", nil)
		
		-- Read scenario XML format attributes
		local vehicleVehicleId = getXMLString(xmlFile, vehicleKey.."#vehicleId", nil)
		local vehicleName = getXMLString(xmlFile, vehicleKey.."#name", nil)
		local manufacturer = getXMLString(xmlFile, vehicleKey.."#manufacturer", nil)
		local category = getXMLString(xmlFile, vehicleKey.."#category", nil)
		local colorIndex = getXMLInt(xmlFile, vehicleKey.."#colorIndex", nil)
		
		-- For scenario format, use id as externalId if not already set
		if vehicleExternalId == nil and vehicleId ~= nil then
			vehicleExternalId = vehicleId
		end
		
		-- Check if vehicle already exists
		local existingVehicle = nil
		if vehicleUniqueId ~= nil then
			existingVehicle = existingNeighbour:getVehicle(vehicleUniqueId)
		end
		if existingVehicle == nil and vehicleExternalId ~= nil then
			existingVehicle = existingNeighbour:getVehicleByExternalId(vehicleExternalId)
			if existingVehicle ~= nil and existingVehicle.uniqueId ~= nil then
				vehicleUniqueId = existingVehicle.uniqueId
				--self.ianeighbours:setVehicleIdMapping(vehicleExternalId, vehicleUniqueId)
			end
		end
		
		-- Create or update vehicle
		if existingVehicle == nil then
			existingVehicle = IANeighbourVehicle.new(vehicleUniqueId, existingNeighbour.farmId, existingNeighbour)
			if vehicleExternalId ~= nil then
				existingVehicle.externalId = vehicleExternalId
			end
			
			if self.ianeighbours.debug then
				local vehicleDisplayId = vehicleUniqueId or vehicleExternalId or "unknown"
				print("--- IAXMLHelper:loadVehiclesFromXML() - Created new vehicle: "..tostring(vehicleDisplayId))
			end
		else
			if self.ianeighbours.debug then
				local vehicleDisplayId = vehicleUniqueId or vehicleExternalId or "unknown"
				print("--- IAXMLHelper:loadVehiclesFromXML() - Updating existing vehicle: "..tostring(vehicleDisplayId))
			end
		end
		
		-- Update vehicle with all XML values
		existingVehicle:updateFromXML(xmlFilename, jobType, jobTargetX, jobTargetZ, vehicleExternalId, npcOffsetX, npcOffsetY, npcOffsetZ, npcOffsetRotation, vehicleType, category, vehicleActiveSituationId, colorIndex)
		
		-- Update outbound format vehicle attributes
		if vehiclePositionX ~= nil then
			existingVehicle.positionX = vehiclePositionX
		end
		if vehiclePositionY ~= nil then
			existingVehicle.positionY = vehiclePositionY
		end
		if vehiclePositionZ ~= nil then
			existingVehicle.positionZ = vehiclePositionZ
		end
		if vehicleRotation ~= nil then
			existingVehicle.rotation = vehicleRotation
		end
		if realPositionX ~= nil then
			existingVehicle.realPositionX = realPositionX
		end
		if realPositionY ~= nil then
			existingVehicle.realPositionY = realPositionY
		end
		if realPositionZ ~= nil then
			existingVehicle.realPositionZ = realPositionZ
		end
		if realRotation ~= nil then
			existingVehicle.realRotation = realRotation
		end
		if npcPositionX ~= nil then
			existingVehicle.npcPositionX = npcPositionX
		end
		if npcPositionY ~= nil then
			existingVehicle.npcPositionY = npcPositionY
		end
		if npcPositionZ ~= nil then
			existingVehicle.npcPositionZ = npcPositionZ
		end
		if npcRotation ~= nil then
			existingVehicle.npcRotation = npcRotation
		end
		if parkingPlaceIdStr ~= nil then
			local pidn = tonumber(parkingPlaceIdStr)
			existingVehicle.parkingPlaceId = pidn or parkingPlaceIdStr
		end
		if parkingPlaceSemantic ~= nil then
			existingVehicle.parkingPlaceSemantic = parkingPlaceSemantic
		end
		if borrowReturnPlaceIdStr ~= nil then
			local pidn = tonumber(borrowReturnPlaceIdStr)
			existingVehicle.borrowReturnParkingPlaceId = pidn or borrowReturnPlaceIdStr
		end
		if borrowReturnPlaceSemantic ~= nil then
			existingVehicle.borrowReturnParkingPlaceSemantic = borrowReturnPlaceSemantic
		end
		if borrowPickupX ~= nil then
			existingVehicle.borrowPickupPositionX = borrowPickupX
		end
		if borrowPickupY ~= nil then
			existingVehicle.borrowPickupPositionY = borrowPickupY
		end
		if borrowPickupZ ~= nil then
			existingVehicle.borrowPickupPositionZ = borrowPickupZ
		end
		if borrowPickupRotation ~= nil then
			existingVehicle.borrowPickupRotation = borrowPickupRotation
		end
		if vehicleBorrowedByPlayer == true then
			if existingVehicle.borrowReturnParkingPlaceId == nil and existingVehicle.parkingPlaceId ~= nil then
				existingVehicle.borrowReturnParkingPlaceId = existingVehicle.parkingPlaceId
				existingVehicle.borrowReturnParkingPlaceSemantic = existingVehicle.parkingPlaceSemantic or "homebase"
			end
			existingVehicle.isBorrowedByPlayer = true
			if IAEquipmentPresence ~= nil then
				IAEquipmentPresence.State.setDesiredBorrowed(existingVehicle)
			end
		end
		
		-- Store scenario-specific vehicle data if present
		if vehicleVehicleId ~= nil then
			existingVehicle.vehicleId = vehicleVehicleId
		end
		if vehicleName ~= nil then
			existingVehicle.vehicleName = vehicleName
		end
		if manufacturer ~= nil then
			existingVehicle.manufacturer = manufacturer
		end
		if category ~= nil then
			existingVehicle.category = category
		end
		
		-- Initialize vehicle if needed
		if not existingVehicle.initialized or existingVehicle.uniqueId == nil then
			existingVehicle:initialize(function(uniqueId, externalId, ia_vehicle)
				if externalId ~= nil and uniqueId ~= nil then
					--self.ianeighbours:setVehicleIdMapping(externalId, uniqueId)
				end
				existingNeighbour:addVehicle(existingVehicle)
			end)
		else
			-- Ensure vehicle is added to neighbour (only if it has a uniqueId)
			if existingVehicle.uniqueId ~= nil then
				existingNeighbour:addVehicle(existingVehicle)
			else
				if self.ianeighbours.debug then
					print("--- IAXMLHelper:loadVehiclesFromXML() - Warning: Vehicle has no uniqueId, cannot add to neighbour yet")
				end
			end
		end
		
		vehicleIndex = vehicleIndex + 1
	end
end

-- Load situation for a neighbour from XML
-- @param xmlFile - The XML file handle
-- @param neighbourKey - The XML key path for the neighbour (e.g., "IANeighboursOutbound.neighbours.neighbour(0)")
-- @param existingNeighbour - The IANeighbour instance to add situation to
-- @return IASituation|nil - The loaded situation, or nil if not found
function IAXMLHelper:loadSituationFromXML(xmlFile, neighbourKey, existingNeighbour)
	if existingNeighbour == nil then
		return nil
	end
	
	local situationKey = neighbourKey..".situation"
	local configIdStr = getXMLString(xmlFile, situationKey.."#configId", nil)
	
	-- If no configId, no situation exists
	if configIdStr == nil then
		return nil
	end
	
	-- Find situation config by ID
	local situationConfig = nil
	if self.ianeighbours.situationConfigs ~= nil then
		for _, config in ipairs(self.ianeighbours.situationConfigs) do
			if config ~= nil and tostring(config.id) == configIdStr then
				situationConfig = config
				break
			end
		end
	end
	
	if situationConfig == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadSituationFromXML() - Situation config not found for ID: "..tostring(configIdStr))
		end
		return nil
	end
	
	-- Load constructor parameters
	local placeId = getXMLInt(xmlFile, situationKey.."#placeId", nil)
	local farmlandId = getXMLInt(xmlFile, situationKey.."#farmlandId", nil)
	local jobType = getXMLString(xmlFile, situationKey.."#jobType", nil)
	local vehicleUniqueIdStr = getXMLString(xmlFile, situationKey.."#vehicleUniqueId", nil)
	local vehicleExternalId = getXMLString(xmlFile, situationKey.."#vehicleExternalId", nil)
	local attachmentBackUniqueIdStr = getXMLString(xmlFile, situationKey.."#attachmentBackUniqueId", nil)
	local attachmentBackExternalId = getXMLString(xmlFile, situationKey.."#attachmentBackExternalId", nil)
	local attachmentFrontUniqueIdStr = getXMLString(xmlFile, situationKey.."#attachmentFrontUniqueId", nil)
	local attachmentFrontExternalId = getXMLString(xmlFile, situationKey.."#attachmentFrontExternalId", nil)
	
	-- Find place by ID if placeId exists
	local place = nil
	if placeId ~= nil and self.ianeighbours.places ~= nil then
		for _, p in ipairs(self.ianeighbours.places) do
			if p ~= nil and p.id == placeId then
				place = p
				break
			end
		end
	end
	
	-- Find vehicle by uniqueId or externalId
	local vehicle = nil
	if vehicleUniqueIdStr ~= nil then
		vehicle = existingNeighbour:getVehicle(vehicleUniqueIdStr)
	elseif vehicleExternalId ~= nil then
		vehicle = existingNeighbour:getVehicleByExternalId(vehicleExternalId)
	end
	
	-- Find attachmentBack by uniqueId or externalId
	local attachmentBack = nil
	if attachmentBackUniqueIdStr ~= nil then
		attachmentBack = existingNeighbour:getVehicle(attachmentBackUniqueIdStr)
	elseif attachmentBackExternalId ~= nil then
		attachmentBack = existingNeighbour:getVehicleByExternalId(attachmentBackExternalId)
	end
	
	-- Find attachmentFront by uniqueId or externalId
	local attachmentFront = nil
	if attachmentFrontUniqueIdStr ~= nil then
		attachmentFront = existingNeighbour:getVehicle(attachmentFrontUniqueIdStr)
	elseif attachmentFrontExternalId ~= nil then
		attachmentFront = existingNeighbour:getVehicleByExternalId(attachmentFrontExternalId)
	end
	
	-- Create IASituation instance with constructor parameters
	local situation = IASituation.new(situationConfig, existingNeighbour, place, vehicle, farmlandId, attachmentBack, attachmentFront, jobType, true)
	
	-- Set state attributes AFTER creation (not constructor parameters)
	local startedAt = getXMLFloat(xmlFile, situationKey.."#startedAt", nil)
	if startedAt ~= nil then
		situation.startedAt = startedAt
	end
	if jobType ~= nil and string.lower(tostring(jobType)) == "seed" then
		local savedSeedFruitTypeIndex = getXMLInt(xmlFile, situationKey.."#seedFruitTypeIndex", nil)
		if savedSeedFruitTypeIndex ~= nil then
			situation.seedFruitTypeIndex = savedSeedFruitTypeIndex
		end
	end
	situation.initCommitted = getXMLBool(xmlFile, situationKey.."#initCommitted", false)
	situation._preBlockFarmlandOwnerFarmId = getXMLInt(xmlFile, situationKey.."#preBlockFarmlandOwnerFarmId", nil)
	situation._preBlockFarmlandFieldStateOwnerFarmId = getXMLInt(xmlFile, situationKey.."#preBlockFarmlandFieldStateOwnerFarmId", nil)
	
	-- Load dialog messages
	local dialogMessages = {}
	local messageIndex = 0
	while true do
		local messageKey = situationKey..".dialogMessages.message("..messageIndex..")"
		local messageId = getXMLInt(xmlFile, messageKey.."#id", nil)
		
		if messageId == nil then
			break
		end
		
		local messageText = getXMLString(xmlFile, messageKey.."#text", nil)
		local messageSender = getXMLString(xmlFile, messageKey.."#sender", nil)
		
		if messageText ~= nil and messageSender ~= nil then
			messageText = self:decodeXMLEntities(messageText)
			table.insert(dialogMessages, {
				id = messageId,
				text = messageText,
				sender = messageSender
			})
		end
		
		messageIndex = messageIndex + 1
	end
	
	if #dialogMessages > 0 then
		situation.dialogMessages = dialogMessages
	end
	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadSituationFromXML() - Loaded situation: "..tostring(situation.id).." for neighbour: "..existingNeighbour.name)
	end
	
	return situation
end

-- Load data from outbound XML file and recreate/update all objects
function IAXMLHelper:loadOutboundXML()
	if g_currentMission.missionInfo.savegameDirectory == nil then
		return false
	end

	-- Load vehicle ID mapping from outbound XML first
	--self.ianeighbours:loadVehicleIdMapping()

	local filePath = g_currentMission.missionInfo.savegameDirectory.."/IANeighbours_outbound.xml"
	
	if not fileExists(filePath) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadOutboundXML() - File does not exist: "..filePath)
		end
		return false
	end
	
	local xmlFile = loadXMLFile("IANeighboursOutbound", filePath)
	
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadOutboundXML() - Failed to load XML file: "..filePath)
		end
		return false
	end
	
	local rootKey = "IANeighboursOutbound"

	if IASettings ~= nil and type(IASettings.loadStateFromOutboundXML) == "function" then
		pcall(IASettings.loadStateFromOutboundXML, xmlFile, rootKey)
	end
	
	-- Parse all neighbours from outbound XML
	local neighbourIndex = 0
	while true do
		local neighbourKey = rootKey..".neighbours.neighbour("..neighbourIndex..")"
		local existingNeighbour = self:loadNeighbourFromXML(xmlFile, neighbourKey, rootKey)
		
		if existingNeighbour == nil then
			break
		end
		
		-- Load vehicles for this neighbour
		self:loadVehiclesFromXML(xmlFile, neighbourKey, existingNeighbour)
		
		-- Load situation for this neighbour
		local loadedSituation = self:loadSituationFromXML(xmlFile, neighbourKey, existingNeighbour)
		if loadedSituation ~= nil then
			existingNeighbour.activeSituation = loadedSituation
			existingNeighbour.activeSituationId = loadedSituation.config.id
			-- Set situation reference on vehicles that belong to this situation (activeSituationId was set in updateFromXML)
			local situationId = loadedSituation.config and loadedSituation.config.id
			if situationId ~= nil and existingNeighbour.vehicles ~= nil then
				for _, iaVehicle in pairs(existingNeighbour.vehicles) do
					if iaVehicle ~= nil and iaVehicle.activeSituationId == situationId then
						iaVehicle.situation = loadedSituation
					end
				end
			end
		end
		
		-- Load situation history
		local historyKey = neighbourKey..".situationHistory"
		local historyIndex = 0
		local loadedHistory = {}
		
		while true do
			local historyItemKey = historyKey..".situation("..historyIndex..")"
			local situationId = getXMLString(xmlFile, historyItemKey.."#situationId", nil)
			
			if situationId == nil then
				break
			end
			
			local historyItem = {
				situationId = situationId,
				placeId = getXMLInt(xmlFile, historyItemKey.."#placeId", nil),
				startedAt = getXMLFloat(xmlFile, historyItemKey.."#startedAt", nil),
				vehicleIds = {}
			}
			
			-- Load vehicle ids array
			local vehicleIdIndex = 0
			while true do
				local vehicleIdKey = historyItemKey..".vehicleIds.vehicleId("..vehicleIdIndex..")"
				local vehicleId = getXMLString(xmlFile, vehicleIdKey, nil)
				
				if vehicleId == nil then
					break
				end
				
				table.insert(historyItem.vehicleIds, vehicleId)
				vehicleIdIndex = vehicleIdIndex + 1
			end
			
			table.insert(loadedHistory, historyItem)
			historyIndex = historyIndex + 1
		end
		
		-- Restore situation history to neighbour
		if #loadedHistory > 0 then
			existingNeighbour.situationHistory = loadedHistory
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadOutboundXML() - Loaded "..tostring(#loadedHistory).." situation history entries for neighbour: "..existingNeighbour.name)
			end
		end
		
		neighbourIndex = neighbourIndex + 1
	end
	
	delete(xmlFile)
	
	if neighbourIndex == 0 then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadOutboundXML() - Outbound file exists but has no neighbours; loading default scenario instead: "..filePath)
		end
		return false
	end
	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadOutboundXML() - Successfully loaded outbound XML file: "..filePath)
		print("--- Loaded "..tostring(neighbourIndex).." neighbours")
	end
	
	return true
end

-- Initialize scenario from scenarioConfigFile
-- Processing will be done later
function IAXMLHelper:scenarioInitialize()
	if self.scenarioConfigFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:scenarioInitialize() - Scenario config file is nil")
		end
		return false
	end
	
	if not fileExists(self.scenarioConfigFile) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:scenarioInitialize() - Scenario config file does not exist: "..self.scenarioConfigFile)
		end
		return false
	end
	
	local xmlFile = loadXMLFile("FieldsOfStoriesScenario", self.scenarioConfigFile)
	
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:scenarioInitialize() - Failed to load scenario config file: "..self.scenarioConfigFile)
		end
		return false
	end
	
	local rootKey = "scenario"
	
	-- Read scenario data (optional, for reference)
	local scenarioDataKey = rootKey..".scenarioData"
	local scenarioId = getXMLString(xmlFile, scenarioDataKey.."#id", nil)
	local scenarioTitle = getXMLString(xmlFile, scenarioDataKey..".title", nil)
	local scenarioDescription = getXMLString(xmlFile, scenarioDataKey..".description", nil)
	local roleplayScenario = getXMLString(xmlFile, scenarioDataKey..".roleplayScenario", nil)
	
	if self.ianeighbours.debug then
		if scenarioTitle ~= nil then
			print("--- IAXMLHelper:scenarioInitialize() - Loading scenario: "..scenarioTitle)
		end
	end
	
	-- Load neighbours using unified method (handles both formats)
	local neighbourIndex = 0
	while true do
		local neighbourKey = rootKey..".neighbours.neighbour("..neighbourIndex..")"
		local existingNeighbour = self:loadNeighbourFromXML(xmlFile, neighbourKey, rootKey)
		
		if existingNeighbour == nil then
			break
		end
		
		-- Load vehicles using unified method (handles both formats)
		self:loadVehiclesFromXML(xmlFile, neighbourKey, existingNeighbour)
		
		neighbourIndex = neighbourIndex + 1
	end
	
	delete(xmlFile)
	

	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:scenarioInitialize() - Successfully loaded scenario config file: "..self.scenarioConfigFile)
		print("--- Loaded "..tostring(neighbourIndex).." neighbours from scenario")
	end
	
	return true
end

--- First run for a map: load placeablePlaces.xml, resolve placeable-relative entries, save fields_of_stories_<mapId>.xml.
-- Call only when mapConfigFileNotFound; updates mapConfigFile / mapConfigFileNotFound after a successful save path exists.
-- @return boolean - true if bootstrap ran (was needed), false if skipped (config already known to exist)
function IAXMLHelper:bootstrapFirstRunMapPlaces()
	if self.mapConfigFileNotFound ~= true then
		return false
	end
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:bootstrapFirstRunMapPlaces() - Bootstrapping places from placeablePlaces.xml")
	end
	self:loadPlaceablePlacesFromFile()
	if self.ianeighbours.placesLoader then
		self.ianeighbours.placesLoader:resolvePlaceableRelativePlaces()
	end
	local mapId = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId
	if mapId then
		if self.ianeighbours.debug then
			print("--- saveMapConfigToFile caller: IAXMLHelper:bootstrapFirstRunMapPlaces mapId=" .. tostring(mapId))
		end
		self:saveMapConfigToFile(mapId)
	end
	local dir = self.modSettingsDirectory
	if dir == nil or dir == "" then
		dir = (g_modSettingsDirectory or "") .. "FS25_FIELDS_OF_STORIES/"
	end
	if mapId and dir ~= "" then
		local path = dir .. "fields_of_stories_" .. tostring(mapId) .. ".xml"
		self.mapConfigFile = path
		if fileExists(path) then
			self.mapConfigFileNotFound = false
		end
	end
	return true
end

--- Voice pack OK if major.minor match; patch (3rd+ segments) ignored. Empty/missing minor treated as "0".
local function voicePackVersionsCompatible(requiredStr, packStr)
	local req = tostring(requiredStr or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local pack = tostring(packStr or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if req == "" or pack == "" then
		return false
	end
	local function majorMinor(s)
		local t = {}
		for p in string.gmatch(s, "[^.]+") do
			t[#t + 1] = p
			if #t >= 2 then
				break
			end
		end
		return t[1], t[2]
	end
	local rMaj, rMin = majorMinor(req)
	local pMaj, pMin = majorMinor(pack)
	if rMaj ~= pMaj then
		return false
	end
	if rMin == nil then
		rMin = "0"
	end
	if pMin == nil then
		pMin = "0"
	end
	return rMin == pMin
end

--- Compare modSettings/.../conversations/voice_pack_version.xml to IANeighbours.requiredVoicePackVersion (major.minor only; patch/third segment may differ).
-- Sets IANeighbours.pendingVoicePackWarning when the file is missing, unreadable, or version mismatches.
-- Sets IANeighbours.voicePackLoaded (IAConversation skips createAndPlayVoiceSample when false).
-- Sets IANeighbours.voicePackLanguage from voicePack#language when version matches (overrides game language for mod voice + conversation text).
function IAXMLHelper:checkVoicePackVersionFile()
	if IANeighbours == nil then
		return
	end
	local required = IANeighbours.requiredVoicePackVersion
	if required == nil or required == "" then
		IANeighbours.pendingVoicePackWarning = false
		IANeighbours.voicePackLoaded = true
		IANeighbours.voicePackLanguage = nil
		return
	end
	local path = self:getModSettingsDirectory() .. "conversations/voice_pack_version.xml"
	if not fileExists(path) then
		IANeighbours.pendingVoicePackWarning = true
		IANeighbours.voicePackLoaded = false
		IANeighbours.voicePackLanguage = nil
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkVoicePackVersionFile() - Missing: " .. tostring(path))
		end
		return
	end
	local xmlFile = loadXMLFile("IAVoicePackVersion", path)
	if xmlFile == nil or xmlFile == 0 then
		IANeighbours.pendingVoicePackWarning = true
		IANeighbours.voicePackLoaded = false
		IANeighbours.voicePackLanguage = nil
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkVoicePackVersionFile() - loadXMLFile failed: " .. tostring(path))
		end
		return
	end
	local ver = getXMLString(xmlFile, "voicePack#version", "")
	local rawPackLang = getXMLString(xmlFile, "voicePack#language", "")
	delete(xmlFile)
	if ver == nil then
		ver = ""
	end
	IANeighbours.voicePackLanguage = nil
	if not voicePackVersionsCompatible(required, ver) then
		IANeighbours.pendingVoicePackWarning = true
		IANeighbours.voicePackLoaded = false
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:checkVoicePackVersionFile() - Version mismatch (major.minor): got '" .. tostring(ver) .. "', need '" .. tostring(required) .. "' (patch may differ)")
		end
	else
		IANeighbours.pendingVoicePackWarning = false
		IANeighbours.voicePackLoaded = true
		if IAConversation ~= nil and IAConversation._normalizeVoicePackLanguage ~= nil then
			local packLang = IAConversation._normalizeVoicePackLanguage(rawPackLang)
			if packLang ~= nil then
				IANeighbours.voicePackLanguage = packLang
			end
		end
		if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil and g_i18n ~= nil and g_i18n.getText ~= nil then
			local noteText = g_i18n:getText("gui_voice_pack_warn_ok_notification")
			if noteText ~= nil and noteText ~= "" then
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, noteText)
			end
		end
	end
end

--- Mod root file: maps character/situation → variant folder ids (zip-safe; no directory scan). Fills IAConversation.situationVariantIds (keyed by character #index) and folder-id → index map; does not load conversation.xml.
function IAXMLHelper:loadConversationsStructureRegistry()
	if self.conversationsStructureLoaded then
		return
	end
	self.conversationsStructureLoaded = true
	if IAConversation == nil then
		return
	end
	IAConversation.situationVariantIds = {}
	IAConversation.structureCharacterIndexByFolderId = {}
	local modBaseDir = self.ianeighbours ~= nil and self.ianeighbours.dir or nil
	if modBaseDir == nil or modBaseDir == "" then
		return
	end
	local structName = "conversations-structure.xml"
	local structPath = Utils.getFilename(structName, modBaseDir)
	if not fileExists(structPath) then
		if self.ianeighbours ~= nil and self.ianeighbours.debug then
			print("--- IAXMLHelper:loadConversationsStructureRegistry() - missing " .. tostring(structName) .. " — situation variants need filesystem scan (fails in zip)")
		end
		return
	end
	local structXml = loadXMLFile("IAConversationsStructure", structPath)
	if structXml == nil then
		return
	end
	local rootKey = "conversationsData"
	local charIndex = 0
	while true do
		local charKey = rootKey .. ".character(" .. charIndex .. ")"
		local charId = getXMLString(structXml, charKey .. "#index", nil)
		if charId == nil then
			break
		end
		local charStructureIndex = getXMLString(structXml, charKey .. "#index", nil)
		if charStructureIndex == nil or charStructureIndex == "" then
			if self.ianeighbours ~= nil and self.ianeighbours.debug then
				print("--- IAXMLHelper:loadConversationsStructureRegistry() - skip character id=" .. tostring(charId) .. " (missing #index)")
			end
			charIndex = charIndex + 1
		else
			charId = tostring(charId)
			charStructureIndex = tostring(charStructureIndex)
			IAConversation.structureCharacterIndexByFolderId[charId] = charStructureIndex
			if IAConversation.situationVariantIds[charStructureIndex] == nil then
				IAConversation.situationVariantIds[charStructureIndex] = {}
			end
			local sitIndex = 0
			while true do
				local sitKey = charKey .. ".situation(" .. sitIndex .. ")"
				local sitId = getXMLString(structXml, sitKey .. "#id", nil)
				if sitId == nil then
					break
				end
				local variantIds = {}
				local varIndex = 0
				while true do
					local varKey = sitKey .. ".variant(" .. varIndex .. ")"
					local varIdStr = getXMLString(structXml, varKey .. "#id", nil)
					if varIdStr == nil then
						break
					end
					table.insert(variantIds, varIdStr)
					varIndex = varIndex + 1
				end
				IAConversation.situationVariantIds[charStructureIndex][sitId] = variantIds
				sitIndex = sitIndex + 1
			end
			charIndex = charIndex + 1
		end
	end
	delete(structXml)
	if self.ianeighbours ~= nil and self.ianeighbours.debug then
		print("--- IAXMLHelper:loadConversationsStructureRegistry() - OK")
	end
end

-- Load data: try outbound XML first, fallback to scenarioInitialize
function IAXMLHelper:loadData()
	self:checkVoicePackVersionFile()
	self:loadConversationsStructureRegistry()
	-- Load map configuration from single file (fields_of_stories_<mapId>.xml, priority mod settings > mod folder)
	self:loadMapConfiguration()

	-- Bootstrap from placeablePlaces only when no map config exists yet.
	-- With GUI: defer heavy bootstrap until user confirms (see IANeighbours.pendingMapPlacesBootstrap + dialog).
	-- Without GUI (e.g. headless): run immediately as before.
	if self.mapConfigFileNotFound == true then
		if g_gui ~= nil and IANeighbours ~= nil then
			IANeighbours.pendingMapPlacesBootstrap = true
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadData() - No map config; deferred bootstrap until user confirms in dialog")
			end
		else
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadData() - No map config found, bootstrapping places from placeablePlaces.xml")
			end
			self:bootstrapFirstRunMapPlaces()
			-- Roadside samples from traffic splines (same as IANeighbours:update when GUI defers bootstrap)
			if IAMapInitJob and IAMapInitJob.saveAutoPlaces and g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
				IAMapInitJob.saveAutoPlaces(self.ianeighbours)
			end
			if self.ianeighbours then
				self.ianeighbours.mapInitJobRun = true
			end
			if IANeighbours ~= nil and IANeighbours.refreshHomebaseAssignmentsAfterPlacesBootstrap ~= nil then
				IANeighbours.refreshHomebaseAssignmentsAfterPlacesBootstrap()
			end
		end
	elseif self.ianeighbours.debug then
		print("--- IAXMLHelper:loadData() - Map config exists, skipping placeablePlaces resolve bootstrap")
	end
	-- Load situation configurations
	self:loadSituationConfigs()
	
	-- Try outbound savegame file first. If missing, or present but empty (no neighbour entries), use scenarioInitialize below.
	if self:loadOutboundXML() then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadData() - Successfully loaded from outbound XML")
		end
		-- Merge map-config homebase + workplace assignments into neighbours (add-only: never removes outbound/savegame assignments).
		self:mergeMapConfigNeighbourHomebaseAssignments()
		self:applyMapConfigNeighbourWorkplaceAssignments()
		if self.ianeighbours ~= nil and self.ianeighbours.reclassifyPlacesByPlayerFarmland ~= nil then
			self.ianeighbours:reclassifyPlacesByPlayerFarmland()
		end
		if IAFieldOutcomeMission ~= nil and IAFieldOutcomeMission.tryApplyOutboundRestoreAfterLoad ~= nil then
			pcall(function()
				IAFieldOutcomeMission.tryApplyOutboundRestoreAfterLoad()
			end)
		end
		self:removeOrphanedFarm99Vehicles()
		return true
	end
	
	-- Fallback to scenarioInitialize
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadData() - Outbound XML not available, trying scenarioInitialize")
	end
	
	local success = self:scenarioInitialize()
	if success then
		-- Merge map-config homebase + workplace assignments into neighbours (add-only: never removes outbound/savegame assignments).
		self:mergeMapConfigNeighbourHomebaseAssignments()
		self:applyMapConfigNeighbourWorkplaceAssignments()
	end
	self:removeOrphanedFarm99Vehicles()
	if self.ianeighbours ~= nil and self.ianeighbours.reclassifyPlacesByPlayerFarmland ~= nil then
		self.ianeighbours:reclassifyPlacesByPlayerFarmland()
	end
	if IAFieldOutcomeMission ~= nil and IAFieldOutcomeMission.tryApplyOutboundRestoreAfterLoad ~= nil then
		pcall(function()
			IAFieldOutcomeMission.tryApplyOutboundRestoreAfterLoad()
		end)
	end

	return success
end

-- Remove all vehicles with farmId 99 that are not part of the neighbours
-- This method cleans up orphaned vehicles that belong to farm 99 but are not tracked in any neighbour's vehicle list
-- @return number - Number of vehicles removed
function IAXMLHelper:removeOrphanedFarm99Vehicles()
	if self.ianeighbours == nil then
		return 0
	end
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - Removing orphaned farm 99 vehicles")
	end
	-- Collect all uniqueIds from vehicles in the neighbours
	local vehiclesInNeighbours = {}
	for _, neighbour in pairs(self.ianeighbours.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia_vehicle in pairs(neighbour.vehicles) do
				if ia_vehicle ~= nil and ia_vehicle.uniqueId ~= nil then
					vehiclesInNeighbours[ia_vehicle.uniqueId] = true
				end
			end
		end
	end
	
	-- Also collect uniqueIds from the mapping (vehicles that might not be initialized yet)
	for externalId, uniqueId in pairs(self.ianeighbours.vehicleIdMapping) do
		if uniqueId ~= nil then
			vehiclesInNeighbours[uniqueId] = true
		end
	end
	
	-- Find and remove vehicles with farmId 99 that are not in the neighbours
	local removedVehicles = {}
	if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
		-- Copy the vehicle list before iterating to avoid undefined behavior when deleting inside the loop
		local vehiclesCopy = {}
		for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
			if vehicle ~= nil then
				table.insert(vehiclesCopy, vehicle)
			end
		end
		for _, vehicle in ipairs(vehiclesCopy) do
			local uniqueId = vehicle:getUniqueId()
			if uniqueId ~= nil then
				-- Try to get ownerFarmId (method or property)
				local ownerFarmId = nil
				if vehicle.getOwnerFarmId ~= nil then
					ownerFarmId = vehicle:getOwnerFarmId()
				elseif vehicle.ownerFarmId ~= nil then
					ownerFarmId = vehicle.ownerFarmId
				end
				if self.ianeighbours.debug then
					print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - "..tostring(uniqueId).." ownerFarmId: "..tostring(ownerFarmId))
					print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - "..tostring(uniqueId).." vehiclesInNeighbours: "..tostring(vehiclesInNeighbours[uniqueId]))
				end
				if ownerFarmId ~= nil and (ownerFarmId == 99) then
					-- Check if this vehicle is not in the neighbours
					if not vehiclesInNeighbours[uniqueId] then
						table.insert(removedVehicles, {
							uniqueId = uniqueId,
							ownerFarmId = ownerFarmId
						})

						for _, job in pairs(g_currentMission.aiSystem.activeJobs) do
							--if job.startedFarmId == 99 then
								if self.ianeighbours.debug then
									print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - Removing job: "..tostring(job.id))
								end
								--job:stop(AIMessageSuccessStoppedByUser.new())
								--g_currentMission.aiSystem:removeJob(job)
							--end
						end
						
						--vehicle:setVisibility(false)
						--vehicle:removeFromPhysics()
						vehicle:delete(true)
						if self.ianeighbours.debug then
							print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - Removed orphaned farm 99 vehicle (isDeleted: "..tostring(vehicle.isDeleted).."): uniqueId="..tostring(uniqueId)..", ownerFarmId="..tostring(ownerFarmId))
						end
					end
				end
			end
		end
		
		if #removedVehicles > 0 then
			print("--- IAXMLHelper:removeOrphanedFarm99Vehicles() - Removed "..tostring(#removedVehicles).." orphaned farm 99 vehicles")
		end
	end
	
	return #removedVehicles
end

-- Load situation configurations from situations XML file
function IAXMLHelper:loadSituationConfigs()
	local situationsFilePath = self.ianeighbours.dir .. "situations/fields_of_stories_situations.xml"
	
	if not fileExists(situationsFilePath) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadSituationConfigs() - Situations file does not exist: "..situationsFilePath)
		end
		return false
	end
	
	local xmlFile = loadXMLFile("FieldsOfStoriesSituations", situationsFilePath)
	
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadSituationConfigs() - Failed to load situations XML file: "..situationsFilePath)
		end
		return false
	end
	
	local rootKey = "situations"
	
	-- Clear existing situation configs
	self.ianeighbours.situationConfigs = {}
	
	-- Parse all situations
	local situationIndex = 0
	while true do
		local situationKey = rootKey..".situation("..situationIndex..")"
		local situationId = getXMLString(xmlFile, situationKey.."#id", nil)
		
		if situationId == nil then
			break
		end
		
		-- Read all situation attributes and elements
		local data = {}
		data.id = situationId
		data.type = getXMLString(xmlFile, situationKey..".type", nil)
		data.intent = getXMLString(xmlFile, situationKey..".intent", nil)
		data.occurrence = getXMLString(xmlFile, situationKey..".occurrence", nil)
		data.trigger = getXMLString(xmlFile, situationKey..".trigger", nil)
		data.createdAt = getXMLString(xmlFile, situationKey..".createdAt", nil)
		data.updatedAt = getXMLString(xmlFile, situationKey..".updatedAt", nil)
		data.minFrequency = getXMLInt(xmlFile, situationKey..".minFrequency", nil)
		data.vehicles = getXMLString(xmlFile, situationKey..".vehicles", nil)
		local ignorePlayerDistanceStr = getXMLString(xmlFile, situationKey..".ignorePlayerDistance", nil)
		data.ignorePlayerDistance = (ignorePlayerDistanceStr ~= nil and (ignorePlayerDistanceStr == "true" or string.lower(ignorePlayerDistanceStr) == "true"))
		data.daytime = getXMLString(xmlFile, situationKey..".daytime", nil)
		data.maxDuration = getXMLInt(xmlFile, situationKey..".maxDuration", nil)
		data.characterVisibility = getXMLString(xmlFile, situationKey..".characterVisibility", nil)
		data.fieldwork = getXMLString(xmlFile, situationKey..".fieldwork", nil)

		-- Optional expected FieldState snapshot keys for job ia_field_outcome (see IAFieldOutcomeMission).
		data.fieldStateOutcome = {}
		local fsOutKey = situationKey..".fieldStateOutcome"
		local outcomeAttrs = {
			"fruitTypeIndex", "growthState", "weedState", "weedFactor", "stoneLevel",
			"groundType", "sprayLevel", "sprayType", "limeLevel", "rollerLevel",
			"plowLevel", "stubbleShredLevel", "waterLevel"
		}
		for _, an in ipairs(outcomeAttrs) do
			local v = getXMLInt(xmlFile, fsOutKey.."#"..an, nil)
			if v ~= nil then
				data.fieldStateOutcome[an] = v
			end
		end
		
		-- Read array elements
		-- triggerFruitTypeIndex
		data.triggerFruitTypeIndex = {}
		local fruitTypeIndex = 0
		while true do
			local fruitTypeKey = situationKey..".triggerFruitTypeIndex.item("..fruitTypeIndex..")"
			local fruitType = getXMLString(xmlFile, fruitTypeKey, nil)
			if fruitType == nil then
				break
			end
			table.insert(data.triggerFruitTypeIndex, fruitType)
			fruitTypeIndex = fruitTypeIndex + 1
		end

		-- seedFruitTypeIndex (for fieldwork seed situations: single fruit type name or index for seeder and field)
		data.seedFruitTypeIndex = getXMLString(xmlFile, situationKey..".seedFruitTypeIndex", nil)
		
		-- triggerGrowthState
		data.triggerGrowthState = {}
		local growthStateIndex = 0
		while true do
			local growthStateKey = situationKey..".triggerGrowthState.item("..growthStateIndex..")"
			local growthState = getXMLString(xmlFile, growthStateKey, nil)
			if growthState == nil then
				break
			end
			table.insert(data.triggerGrowthState, growthState)
			growthStateIndex = growthStateIndex + 1
		end

		-- triggerWeedState
		data.triggerWeedState = {}
		local weedStateIndex = 0
		while true do
			local weedStateKey = situationKey..".triggerWeedState.item("..weedStateIndex..")"
			local weedState = getXMLInt(xmlFile, weedStateKey, nil)
			if weedState == nil then
				break
			end
			table.insert(data.triggerWeedState, weedState)
			weedStateIndex = weedStateIndex + 1
		end

		-- triggerSprayLevel
		data.triggerSprayLevel = {}
		local sprayLevelIndex = 0
		while true do
			local sprayLevelKey = situationKey..".triggerSprayLevel.item("..sprayLevelIndex..")"
			local sprayLevel = getXMLInt(xmlFile, sprayLevelKey, nil)
			if sprayLevel == nil then
				break
			end
			table.insert(data.triggerSprayLevel, sprayLevel)
			sprayLevelIndex = sprayLevelIndex + 1
		end
		
		-- placetypes
		data.placetypes = {}
		local placetypeIndex = 0
		while true do
			local placetypeKey = situationKey..".placetypes.item("..placetypeIndex..")"
			local placetype = getXMLString(xmlFile, placetypeKey, nil)
			if placetype == nil then
				break
			end
			table.insert(data.placetypes, placetype)
			placetypeIndex = placetypeIndex + 1
		end

		-- placeSizes (optional): when present, a place is only eligible if its sizeType is in this list.
		-- When absent, exclusive sizes (e.g. "large_area") are excluded from situation selection.
		data.placeSizes = {}
		local placeSizeIndex = 0
		while true do
			local placeSizeKey = situationKey..".placeSizes.item("..placeSizeIndex..")"
			local placeSize = getXMLString(xmlFile, placeSizeKey, nil)
			if placeSize == nil then
				break
			end
			table.insert(data.placeSizes, placeSize)
			placeSizeIndex = placeSizeIndex + 1
		end

		-- vehicleTypes
		data.vehicleTypes = {}
		local vehicleTypeIndex = 0
		while true do
			local vehicleTypeKey = situationKey..".vehicleTypes.item("..vehicleTypeIndex..")"
			local vehicleType = getXMLString(xmlFile, vehicleTypeKey, nil)
			if vehicleType == nil then
				break
			end
			table.insert(data.vehicleTypes, vehicleType)
			vehicleTypeIndex = vehicleTypeIndex + 1
		end
		
		-- attachmentCategories
		data.attachmentCategories = {}
		local attachmentCategoryIndex = 0
		while true do
			local attachmentCategoryKey = situationKey..".attachmentCategories.item("..attachmentCategoryIndex..")"
			local attachmentCategory = getXMLString(xmlFile, attachmentCategoryKey, nil)
			if attachmentCategory == nil then
				break
			end
			table.insert(data.attachmentCategories, attachmentCategory)
			attachmentCategoryIndex = attachmentCategoryIndex + 1
		end
		-- attachmentFrontCategories: categories that attach to front (e.g. Header / Cutter, Weight)
		data.attachmentFrontCategories = {}
		for _, cat in ipairs(data.attachmentCategories) do
			if cat == "Header / Cutter" or cat == "Weight" then
				table.insert(data.attachmentFrontCategories, cat)
			end
		end
		
		-- season
		data.season = {}
		local seasonIndex = 0
		while true do
			local seasonKey = situationKey..".season.item("..seasonIndex..")"
			local season = getXMLString(xmlFile, seasonKey, nil)
			if season == nil then
				break
			end
			table.insert(data.season, season)
			seasonIndex = seasonIndex + 1
		end
		
		-- triggerGroundType
		data.triggerGroundType = {}
		local groundTypeIndex = 0
		while true do
			local groundTypeKey = situationKey..".triggerGroundType.item("..groundTypeIndex..")"
			local groundType = getXMLString(xmlFile, groundTypeKey, nil)
			if groundType == nil then
				break
			end
			table.insert(data.triggerGroundType, groundType)
			groundTypeIndex = groundTypeIndex + 1
		end
		
		-- characterRoles
		data.characterRoles = {}
		local characterRoleIndex = 0
		while true do
			local characterRoleKey = situationKey..".characterRoles.item("..characterRoleIndex..")"
			local characterRole = getXMLString(xmlFile, characterRoleKey, nil)
			if characterRole == nil then
				break
			end
			table.insert(data.characterRoles, characterRole)
			characterRoleIndex = characterRoleIndex + 1
		end
		
		-- characterJobs
		data.characterJobs = {}
		local characterJobIndex = 0
		while true do
			local characterJobKey = situationKey..".characterJobs.item("..characterJobIndex..")"
			local characterJob = getXMLString(xmlFile, characterJobKey, nil)
			if characterJob == nil then
				break
			end
			table.insert(data.characterJobs, characterJob)
			characterJobIndex = characterJobIndex + 1
		end
		
		-- months (1-12, situation only valid in these months)
		data.months = {}
		local monthIndex = 0
		while true do
			local monthKey = situationKey..".months.item("..monthIndex..")"
			local monthVal = getXMLString(xmlFile, monthKey, nil)
			if monthVal == nil then
				break
			end
			local monthNum = tonumber(monthVal)
			if monthNum ~= nil then
				table.insert(data.months, monthNum)
			end
			monthIndex = monthIndex + 1
		end
		
		-- Create IASituationConfig instance
		local situationConfig = IASituationConfig.new(data)
		table.insert(self.ianeighbours.situationConfigs, situationConfig)
		
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadSituationConfigs() - Loaded situation config: "..situationId.." (Type: "..tostring(data.type)..")")
		end
		
		situationIndex = situationIndex + 1
	end
	
	delete(xmlFile)
	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadSituationConfigs() - Successfully loaded "..tostring(situationIndex).." situation configurations")
	end
	
	return true
end

-- Load map configuration from mapConfigFile
-- Loads map information and places
function IAXMLHelper:loadMapConfiguration()
	if self.mapConfigFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadMapConfiguration() - Map config file is nil")
		end
		return false
	end
	
	if not fileExists(self.mapConfigFile) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadMapConfiguration() - Map config file does not exist: "..self.mapConfigFile)
		end
		return false
	end
	
	local xmlFile = loadXMLFile("FieldsOfStoriesMapConfig", self.mapConfigFile)
	
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadMapConfiguration() - Failed to load map config file: "..self.mapConfigFile)
		end
		return false
	end
	
	local rootKey = "mapConfiguration"
	
	-- Read map information
	local mapKey = rootKey..".map"
	local mapId = getXMLString(xmlFile, mapKey.."#id", nil)
	local mapName = getXMLString(xmlFile, mapKey..".name", nil)
	local mapGameId = getXMLString(xmlFile, mapKey..".mapGameId", nil)
	
	if self.ianeighbours.debug then
		if mapName ~= nil then
			print("--- IAXMLHelper:loadMapConfiguration() - Loading map: "..mapName.." (ID: "..tostring(mapId)..")")
		end
	end
	
	-- Store map information
	if mapId ~= nil then
		self.ianeighbours.mapId = mapId
	end
	if mapName ~= nil then
		self.ianeighbours.mapName = mapName
	end
	if mapGameId ~= nil then
		self.ianeighbours.mapGameId = mapGameId
	end

	-- Load places (assignment is on neighbour.assignedHomebasePlaceIds, not characterNumber on place)
	local placeIndex = 0
	while true do
		local placeKey = rootKey..".places.place("..placeIndex..")"
		local placeId = getXMLString(xmlFile, placeKey.."#id", nil)
		local placeType = getXMLString(xmlFile, placeKey.."#type", nil) or getXMLString(xmlFile, placeKey..".type", nil)
		if placeId == nil or placeType == nil then
			break
		end
		
		local placeIdNum = tonumber(placeId)
		local placeName = getXMLString(xmlFile, placeKey..".name", nil)
		if placeName == nil then
			placeName = "Place " .. tostring(placeIdNum or placeIndex)
		end
		local placeX = getXMLFloat(xmlFile, placeKey..".x", nil)
		local placeY = getXMLFloat(xmlFile, placeKey..".y", nil)
		local placeZ = getXMLFloat(xmlFile, placeKey..".z", nil)
		local placeRotation = getXMLFloat(xmlFile, placeKey..".rotation", nil)
		local placeWithVehicle = getXMLBool(xmlFile, placeKey..".withVehicle", false)
		local placeWithAttachment = getXMLBool(xmlFile, placeKey..".withAttachment", false)
		local placeSizeType = getXMLString(xmlFile, placeKey..".sizeType", nil)
		local placeIgnoreCollision = getXMLBool(xmlFile, placeKey..".ignoreCollision", false)
		local placeJob = getXMLString(xmlFile, placeKey..".job", nil)
		local placeDescription = getXMLString(xmlFile, placeKey..".description", nil)
		local refFilename = self:normalizeFsRelativePath(getXMLString(xmlFile, placeKey.."#referenceFilename", nil))
		local refNodeName = getXMLString(xmlFile, placeKey.."#nodeName", nil)
		local refIdAttr = getXMLInt(xmlFile, placeKey.."#referenceId", nil)
		local mapRefNodeIdStr = getXMLString(xmlFile, placeKey.."#mapRefNodeId", nil)
		local offX = getXMLFloat(xmlFile, placeKey..".offsetX", nil)
		local offY = getXMLFloat(xmlFile, placeKey..".offsetY", nil)
		local offZ = getXMLFloat(xmlFile, placeKey..".offsetZ", nil)
		local offRelRot = getXMLFloat(xmlFile, placeKey..".relRotation", nil)
		
		if placeIdNum ~= nil then
			local place = IAMapPlace.new(placeIdNum, placeName, placeType, placeX, placeY, placeZ, placeRotation, placeWithVehicle, placeWithAttachment, placeSizeType, nil)
			place.ignoreCollision = placeIgnoreCollision
			if placeJob ~= nil and placeJob ~= "" then
				place.job = placeJob
			end
			if placeDescription ~= nil and placeDescription ~= "" then
				place.description = placeDescription
			end
			if refFilename ~= nil and refFilename ~= "" then
				place.referenceFilename = refFilename
			end
			if refNodeName ~= nil and refNodeName ~= "" then
				place.nodeName = refNodeName
			end
			if refIdAttr ~= nil then
				place.referenceId = refIdAttr
			end
			if mapRefNodeIdStr ~= nil and mapRefNodeIdStr ~= "" then
				place.mapRefNodeId = mapRefNodeIdStr
			end
			if offX ~= nil then place.offsetX = offX end
			if offY ~= nil then place.offsetY = offY end
			if offZ ~= nil then place.offsetZ = offZ end
			if offRelRot ~= nil then place.relRotation = offRelRot end
			local crefIdx = 0
			local crefList = {}
			while true do
				local cid = getXMLString(xmlFile, placeKey..".collisionExcludeRefId("..crefIdx..")#id", nil)
				if cid == nil or cid == "" then
					break
				end
				crefList[#crefList + 1] = cid
				crefIdx = crefIdx + 1
			end
			if #crefList > 0 then
				place.collisionExcludeRefIds = crefList
			end
			table.insert(self.ianeighbours.places, place)
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:loadMapConfiguration() - Loaded place: "..placeName.." (ID: "..tostring(placeIdNum)..", Type: "..tostring(placeType)..")")
			end
		end
		
		placeIndex = placeIndex + 1
	end
	
	-- Load neighbour homebase assignments (consumed in tryAutoAssignHomebasePlacesIfNeeded during neighbour load; cleared in loadData after load)
	self.ianeighbours.mapConfigNeighbourHomebaseAssignments = {}
	local assignKey = rootKey..".neighbourHomebaseAssignments"
	local neighbourIdx = 0
	while true do
		local nKey = assignKey..".neighbour("..neighbourIdx..")"
		local neighbourId = getXMLInt(xmlFile, nKey.."#id", nil)
		if neighbourId == nil then
			break
		end
		local placeIds = {}
		local placeIdIdx = 0
		while true do
			local pid = getXMLInt(xmlFile, nKey..".placeId("..placeIdIdx..")#id", nil)
			if pid == nil then
				break
			end
			table.insert(placeIds, pid)
			placeIdIdx = placeIdIdx + 1
		end
		if #placeIds > 0 then
			self.ianeighbours.mapConfigNeighbourHomebaseAssignments[neighbourId] = placeIds
		end
		neighbourIdx = neighbourIdx + 1
	end
	
	self.ianeighbours.mapConfigNeighbourWorkplaceAssignments = {}
	local wpAssignKey = rootKey..".neighbourWorkplaceAssignments"
	local wpNeighbourIdx = 0
	while true do
		local wKey = wpAssignKey..".neighbour("..wpNeighbourIdx..")"
		local wpNeighbourId = getXMLInt(xmlFile, wKey.."#id", nil)
		if wpNeighbourId == nil then
			break
		end
		local wpPlaceIds = {}
		local wpPidIdx = 0
		while true do
			local wpid = getXMLInt(xmlFile, wKey..".placeId("..wpPidIdx..")#id", nil)
			if wpid == nil then
				break
			end
			table.insert(wpPlaceIds, wpid)
			wpPidIdx = wpPidIdx + 1
		end
		if #wpPlaceIds > 0 then
			self.ianeighbours.mapConfigNeighbourWorkplaceAssignments[wpNeighbourId] = wpPlaceIds
		end
		wpNeighbourIdx = wpNeighbourIdx + 1
	end
	
	-- Load hidden map objects (gates/doors). Re-located and removed from the live scene below.
	self.ianeighbours.hiddenMapObjects = {}
	local hidKey = rootKey..".hiddenObjects"
	local hidIndex = 0
	while true do
		local oKey = hidKey..".object("..hidIndex..")"
		local oName = getXMLString(xmlFile, oKey.."#name", nil)
		if oName == nil then
			break
		end
		table.insert(self.ianeighbours.hiddenMapObjects, {
			name = oName,
			index = getXMLString(xmlFile, oKey.."#index", nil),
			x = getXMLFloat(xmlFile, oKey.."#x", nil),
			y = getXMLFloat(xmlFile, oKey.."#y", nil),
			z = getXMLFloat(xmlFile, oKey.."#z", nil)
		})
		hidIndex = hidIndex + 1
	end
	
	delete(xmlFile)
	
	-- Remove persisted hidden objects (gates/doors) from the live scene (delete, not just hide)
	if self.ianeighbours.applyHiddenMapObjects ~= nil then
		local removedHidden = self.ianeighbours:applyHiddenMapObjects()
		if self.ianeighbours.debug and removedHidden > 0 then
			print("--- IAXMLHelper:loadMapConfiguration() - Removed "..tostring(removedHidden).." hidden map object(s)")
		end
	end
	
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadMapConfiguration() - Successfully loaded map config file: "..self.mapConfigFile)
		print("--- Loaded "..tostring(placeIndex).." places")
	end
	
	return true
end

--- Apply map-config neighbour workplace (character_job) assignments. Call after neighbours are loaded (scenario/outbound).
function IAXMLHelper:applyMapConfigNeighbourWorkplaceAssignments()
	local assignments = self.ianeighbours.mapConfigNeighbourWorkplaceAssignments
	if assignments == nil or self.ianeighbours.neighbours == nil then
		return
	end
	for _, neighbour in pairs(self.ianeighbours.neighbours) do
		if neighbour ~= nil and neighbour.id ~= nil and assignments[neighbour.id] ~= nil then
			if neighbour.assignedWorkplacePlaceIds == nil then
				neighbour.assignedWorkplacePlaceIds = {}
			end
			local existing = {}
			for _, pid in ipairs(neighbour.assignedWorkplacePlaceIds) do
				existing[pid] = true
			end
			local added = 0
			for _, pid in ipairs(assignments[neighbour.id]) do
				if not existing[pid] then
					table.insert(neighbour.assignedWorkplacePlaceIds, pid)
					existing[pid] = true
					added = added + 1
				end
			end
			if self.ianeighbours.debug and added > 0 then
				print("--- IAXMLHelper:applyMapConfigNeighbourWorkplaceAssignments() - Merged "..tostring(added).." new workplace place(s) for neighbour id "..tostring(neighbour.id))
			end
		end
	end
	self.ianeighbours.mapConfigNeighbourWorkplaceAssignments = nil
end

--- Merge map-config homebase assignments into existing neighbours (add-only: never removes outbound/savegame assignments).
-- Call after outbound XML load or scenarioInitialize to ensure map-XML-defined mandatory homebases are present.
function IAXMLHelper:mergeMapConfigNeighbourHomebaseAssignments()
	local assignments = self.ianeighbours.mapConfigNeighbourHomebaseAssignments
	if assignments == nil or self.ianeighbours.neighbours == nil then
		return
	end
	for _, neighbour in pairs(self.ianeighbours.neighbours) do
		if neighbour ~= nil and neighbour.id ~= nil and assignments[neighbour.id] ~= nil then
			if neighbour.assignedHomebasePlaceIds == nil then
				neighbour.assignedHomebasePlaceIds = {}
			end
			local existing = {}
			for _, pid in ipairs(neighbour.assignedHomebasePlaceIds) do
				existing[pid] = true
			end
			local added = 0
			for _, pid in ipairs(assignments[neighbour.id]) do
				if not existing[pid] then
					table.insert(neighbour.assignedHomebasePlaceIds, pid)
					existing[pid] = true
					added = added + 1
				end
			end
			if self.ianeighbours.debug and added > 0 then
				print("--- IAXMLHelper:mergeMapConfigNeighbourHomebaseAssignments() - Merged "..tostring(added).." new homebase place(s) for neighbour id "..tostring(neighbour.id))
			end
		end
	end
	self.ianeighbours.mapConfigNeighbourHomebaseAssignments = nil
end

--- Re-read neighbour homebase/workplace assignment lists from map config for one neighbour (after initial apply* cleared global tables).
-- @param IANeighbour neighbour
-- @return boolean true if map file was read (assignments may still be unchanged if no rows match)
function IAXMLHelper:applyMapAssignmentsForNeighbourFromMapFile(neighbour)
	if neighbour == nil or neighbour.id == nil or self.mapConfigFile == nil or not fileExists(self.mapConfigFile) then
		return false
	end
	local xmlFile = loadXMLFile("FieldsOfStoriesMapCfgSingle", self.mapConfigFile)
	if xmlFile == nil then
		return false
	end
	local rootKey = "mapConfiguration"
	local nid = neighbour.id

	local assignKey = rootKey..".neighbourHomebaseAssignments"
	local neighbourIdx = 0
	while true do
		local nKey = assignKey..".neighbour("..neighbourIdx..")"
		local neighbourId = getXMLInt(xmlFile, nKey.."#id", nil)
		if neighbourId == nil then
			break
		end
		if neighbourId == nid then
			local placeIds = {}
			local placeIdIdx = 0
			while true do
				local pid = getXMLInt(xmlFile, nKey..".placeId("..placeIdIdx..")#id", nil)
				if pid == nil then
					break
				end
				table.insert(placeIds, pid)
				placeIdIdx = placeIdIdx + 1
			end
			if #placeIds > 0 then
				neighbour.assignedHomebasePlaceIds = placeIds
			end
			break
		end
		neighbourIdx = neighbourIdx + 1
	end

	local wpAssignKey = rootKey..".neighbourWorkplaceAssignments"
	local wpNeighbourIdx = 0
	while true do
		local wKey = wpAssignKey..".neighbour("..wpNeighbourIdx..")"
		local wpNeighbourId = getXMLInt(xmlFile, wKey.."#id", nil)
		if wpNeighbourId == nil then
			break
		end
		if wpNeighbourId == nid then
			local wpPlaceIds = {}
			local wpPidIdx = 0
			while true do
				local wpid = getXMLInt(xmlFile, wKey..".placeId("..wpPidIdx..")#id", nil)
				if wpid == nil then
					break
				end
				table.insert(wpPlaceIds, wpid)
				wpPidIdx = wpPidIdx + 1
			end
			if #wpPlaceIds > 0 then
				neighbour.assignedWorkplacePlaceIds = wpPlaceIds
			end
			break
		end
		wpNeighbourIdx = wpNeighbourIdx + 1
	end

	delete(xmlFile)
	return true
end

--- Load one character from default scenario XML by neighbour id (caller must remove the old IANeighbour first).
-- @param number|string neighbourId - scenario #id
-- @return boolean
function IAXMLHelper:reloadSingleCharacter(neighbourId)
	if neighbourId == nil or self.scenarioConfigFile == nil or not fileExists(self.scenarioConfigFile) then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:reloadSingleCharacter() - missing scenario or id")
		end
		return false
	end
	local wantId = tonumber(tostring(neighbourId))
	if wantId == nil then
		return false
	end

	local xmlFile = loadXMLFile("FieldsOfStoriesScenarioReload", self.scenarioConfigFile)
	if xmlFile == nil then
		return false
	end

	local rootKey = "scenario"
	local neighbourKey = nil
	local neighbourIndex = 0
	while true do
		local key = rootKey..".neighbours.neighbour("..neighbourIndex..")"
		if getXMLString(xmlFile, key.."#name", nil) == nil then
			break
		end
		local xmlId = getXMLInt(xmlFile, key.."#id", nil)
		if xmlId ~= nil and tonumber(tostring(xmlId)) == wantId then
			neighbourKey = key
			break
		end
		neighbourIndex = neighbourIndex + 1
	end

	if neighbourKey == nil then
		delete(xmlFile)
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:reloadSingleCharacter() - neighbour id "..tostring(neighbourId).." not in scenario")
		end
		return false
	end

	local nb = self:loadNeighbourFromXML(xmlFile, neighbourKey, rootKey, true)
	if nb == nil then
		delete(xmlFile)
		return false
	end

	self:applyMapAssignmentsForNeighbourFromMapFile(nb)
	nb:initialize()
	self:loadVehiclesFromXML(xmlFile, neighbourKey, nb)
	-- Persist scenario appearance on the neighbour for outbound save; do not apply to the live NPC until the next savegame load (style stack not safe mid-session).
	nb.suppressNpcStyleApplicationUntilSavegameLoad = true
	delete(xmlFile)

	if self.ianeighbours ~= nil and self.ianeighbours.reclassifyPlacesByPlayerFarmland ~= nil then
		pcall(function() self.ianeighbours:reclassifyPlacesByPlayerFarmland() end)
	end

	if self.ianeighbours.debug then
		print("--- IAXMLHelper:reloadSingleCharacter() - reloaded neighbour id "..tostring(wantId).." ("..tostring(nb.name)..")")
	end
	return true
end

--- Append a single place to placeablePlaces.xml (used when user adds a place via Place Dialog or at focused map node).
-- Creates the file with one place if it does not exist; otherwise loads, appends at next index, saves.
-- @param IAMapPlace place - The place to append (placeable-relative or node-relative)
-- @return boolean true if appended, false on error
function IAXMLHelper:appendPlaceToPlaceablePlacesFile(place)
	if place == nil or not place.type then
		return false
	end

	local dir = self:getModSettingsDirectory()
	if not folderExists(dir) then
		createFolder(dir)
	end
	local path = dir .. "placeablePlaces.xml"
	local rootKey = "placeablePlaces"
	local xmlFile = nil
	local placeIndex = 0
	if fileExists(path) then
		xmlFile = loadXMLFile("FieldsOfStoriesPlaceablePlaces", path)
		if xmlFile == nil or xmlFile == 0 then
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:appendPlaceToPlaceablePlacesFile() - Failed to load: "..path)
			end
			return false
		end
		while getXMLString(xmlFile, rootKey..".place("..placeIndex..")#type", nil) ~= nil do
			placeIndex = placeIndex + 1
		end
	else
		xmlFile = createXMLFile("FieldsOfStoriesPlaceablePlaces", path, rootKey)
		if xmlFile == nil or xmlFile == 0 then
			if self.ianeighbours.debug then
				print("--- IAXMLHelper:appendPlaceToPlaceablePlacesFile() - Failed to create: "..path)
			end
			return false
		end
	end
	local placeKey = rootKey..".place("..placeIndex..")"
	if place.isPlaceableRelative and place:isPlaceableRelative() and place.placeableFilename then
		setXMLString(xmlFile, placeKey.."#placeableFilename", self:normalizeFsRelativePath(place.placeableFilename))
		local sem = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
		setXMLString(xmlFile, placeKey.."#type", tostring(sem))
		if place.job ~= nil and place.job ~= "" then
			setXMLString(xmlFile, placeKey.."#job", tostring(place.job))
		end
		setXMLFloat(xmlFile, placeKey..".offsetX", place.offsetX or 0)
		setXMLFloat(xmlFile, placeKey..".offsetY", place.offsetY or 0)
		setXMLFloat(xmlFile, placeKey..".offsetZ", place.offsetZ or 0)
		setXMLFloat(xmlFile, placeKey..".relRotation", place.relRotation or 0)
		if place.sizeType ~= nil and tostring(place.sizeType) ~= "" then
			setXMLString(xmlFile, placeKey..".sizeType", tostring(place.sizeType))
		end
		setXMLBool(xmlFile, placeKey..".withVehicle", place.withVehicle ~= false)
		setXMLBool(xmlFile, placeKey..".withAttachment", place.withAttachment == true)
		if place.ignoreCollision == true then
			setXMLBool(xmlFile, placeKey..".ignoreCollision", true)
		end
	elseif (place.nodeName and place.nodeName ~= "") or (place.referenceFilename and place.referenceFilename ~= "") or place.referenceId ~= nil then
		-- Node-relative place: identified by nodeName, referenceFilename, or referenceId
		local semNode = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type or "mapNode"
		setXMLString(xmlFile, placeKey.."#type", tostring(semNode))
		if place.job ~= nil and place.job ~= "" then
			setXMLString(xmlFile, placeKey.."#job", tostring(place.job))
		end
		setXMLString(xmlFile, placeKey.."#nodeName", tostring(place.nodeName or place.name or ""))
		if place.referenceId ~= nil then
			setXMLInt(xmlFile, placeKey.."#referenceId", place.referenceId)
		end
		if place.referenceFilename and place.referenceFilename ~= "" then
			setXMLString(xmlFile, placeKey.."#referenceFilename", self:normalizeFsRelativePath(place.referenceFilename))
		end
		setXMLFloat(xmlFile, placeKey..".offsetX", place.offsetX or 0)
		setXMLFloat(xmlFile, placeKey..".offsetY", place.offsetY or 0)
		setXMLFloat(xmlFile, placeKey..".offsetZ", place.offsetZ or 0)
		setXMLFloat(xmlFile, placeKey..".relRotation", place.relRotation or 0)
		if place.sizeType ~= nil and tostring(place.sizeType) ~= "" then
			setXMLString(xmlFile, placeKey..".sizeType", tostring(place.sizeType))
		end
		setXMLBool(xmlFile, placeKey..".withVehicle", place.withVehicle ~= false)
		setXMLBool(xmlFile, placeKey..".withAttachment", place.withAttachment == true)
		if place.name and place.name ~= "" then
			setXMLString(xmlFile, placeKey..".name", tostring(place.name))
		end
		if place.ignoreCollision == true then
			setXMLBool(xmlFile, placeKey..".ignoreCollision", true)
		end
	else
		delete(xmlFile)
		return false
	end
	saveXMLFile(xmlFile)
	delete(xmlFile)
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:appendPlaceToPlaceablePlacesFile() - Appended place("..tostring(placeIndex)..") to "..path)
	end
	return true
end

--- Load placeablePlaces.xml and add IAMapPlace instances to IANeighbours.places.
-- Prefer the file in the mod settings directory; if it does not exist, use placeablePlaces.xml from the mod's default_maps directory.
-- Node-relative places are expanded: one IAMapPlace per matching map node (resolved immediately).
-- @return boolean true if file was loaded, false if no file or error
function IAXMLHelper:loadPlaceablePlacesFromFile()
	local path = self:getModSettingsDirectory() .. "placeablePlaces.xml"
	if not fileExists(path) and self.ianeighbours and self.ianeighbours.dir then
		path = self.ianeighbours.dir .. "default_maps/placeablePlaces.xml"
	end
	if not fileExists(path) then
		return false
	end
	local rootKey = "placeablePlaces"
	local xmlFile = loadXMLFile("FieldsOfStoriesPlaceablePlaces", path)
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Failed to load: "..path)
		end
		return false
	end
	if self.ianeighbours.places == nil then
		self.ianeighbours.places = {}
	end

	-- Build lookup: key (referenceFilename, "refId:"..referenceId, or nodeName) -> array of { position, rotation, localTranslation, localRotation, ... }
	-- ReferenceNode rows are keyed by .i3d path, but placeablePlaces often uses #nodeName (I3D #name) only — alias those so every instance matches (e.g. gardenTrampoline).
	local nodesByKey = {}
	local function appendNodeForPlaceableMatch(map, key, entry)
		if key == nil or key == "" or entry == nil then
			return
		end
		if map[key] == nil then
			map[key] = {}
		end
		table.insert(map[key], entry)
	end
	local allNodes = IAMapInitJob and IAMapInitJob.getAllMapNodesWithTransform and IAMapInitJob.getAllMapNodesWithTransform({ maxNodes = 1000000 }) or {}
	for _, entry in ipairs(allNodes) do
		if entry and (entry.name and entry.name ~= "" or entry.referenceId or entry.referenceFilename) then
			local key = nil
			if entry.referenceFilename and entry.referenceFilename ~= "" then
				key = self:pathMatchKey(entry.referenceFilename)
			elseif entry.referenceId ~= nil then
				key = "refId:" .. tostring(entry.referenceId)
			else
				key = entry.name or ""
			end
			if key ~= "" then
				if self.ianeighbours.debug then
					print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Adding node: "..tostring(entry.name).." key="..tostring(key).." id="..tostring(entry.id))
				end
				appendNodeForPlaceableMatch(nodesByKey, key, entry)
				if entry.nodeName and entry.nodeName ~= "" and entry.nodeName ~= key then
					appendNodeForPlaceableMatch(nodesByKey, entry.nodeName, entry)
					if self.ianeighbours.debug then
						print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Alias nodeName=" .. tostring(entry.nodeName) .. " id=" .. tostring(entry.id))
					end
				end
			end
		end
	end

	-- Collect runtime map nodes from main map root (g_currentMission.maps[1]) for getWorldTranslation-based resolution
	local runtimeNodes = {}
	local usedRuntimeNodeIds = {}
	-- Cache: same logical map node (matchKey + node.id) -> runtimeNodeId; so multiple place entries for the same node reuse the same runtime node
	local nodeKeyToRuntimeNode = {}
	local mapRoot = IAMapInitJob and IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
	if mapRoot then
		runtimeNodes = IAMapInitJob.collectRuntimeMapNodes and IAMapInitJob.collectRuntimeMapNodes(mapRoot) or {}
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Map root found, collected " .. tostring(#runtimeNodes) .. " runtime nodes for matching")
		end
	end

	local terrainBounds = getTerrainBoundsRect()

	local placeIndex = 0
	local nextId = #self.ianeighbours.places + 1
	local nodeCreatedCount = 0

	while true do
		local placeKey = rootKey..".place("..placeIndex..")"
		local placeableFilename = self:normalizeFsRelativePath(getXMLString(xmlFile, placeKey.."#placeableFilename", nil))
		local placeType = getXMLString(xmlFile, placeKey.."#type", nil)
		if placeType == nil then
			break
		end
		local ignoreCollision = getXMLBool(xmlFile, placeKey..".ignoreCollision", false)
		local placeJob = getXMLString(xmlFile, placeKey.."#job", nil)
		local sizeType = getXMLString(xmlFile, placeKey..".sizeType", nil)
		local nodeName = getXMLString(xmlFile, placeKey.."#nodeName", nil)
		local referenceId = getXMLInt(xmlFile, placeKey.."#referenceId", nil)
		local referenceFilename = self:normalizeFsRelativePath(getXMLString(xmlFile, placeKey.."#referenceFilename", nil))
		if (nodeName ~= nil and nodeName ~= "") or (referenceFilename ~= nil and referenceFilename ~= "") or referenceId ~= nil then
			-- Node-relative: match by referenceFilename, referenceId, or nodeName (nodeName may be empty when using referenceFilename only)
			local effectiveNodeName = (nodeName and nodeName ~= "") and nodeName or referenceFilename or ("refId:" .. tostring(referenceId))
			local baseName = getXMLString(xmlFile, placeKey..".name", nil) or (tostring(placeType or "mapNode") .. " at " .. tostring(effectiveNodeName))
			local offsetX = getXMLFloat(xmlFile, placeKey..".offsetX", nil)
			local withVehicle = getXMLBool(xmlFile, placeKey..".withVehicle", true)
			local withAttachment = getXMLBool(xmlFile, placeKey..".withAttachment", false)
			-- Match by referenceFilename (unique), then referenceId, then nodeName
			local matchKey = nil
			if referenceFilename and referenceFilename ~= "" then
				matchKey = self:pathMatchKey(referenceFilename)
			elseif referenceId ~= nil then
				matchKey = "refId:" .. tostring(referenceId)
			else
				matchKey = nodeName
			end
			local matchingNodes = nodesByKey[matchKey] or {}
			if #matchingNodes == 0 and self.ianeighbours.debug then
				print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - No nodes found for key: "..tostring(matchKey))
			end
			for i, node in ipairs(matchingNodes) do
				local name = baseName
				if #matchingNodes > 1 then
					name = baseName .. " #" .. tostring(i)
				end
				local place
				if offsetX ~= nil then
					place = IAMapPlace.new(
						nextId, name, placeType or "mapNode",
						0, 0, 0, 0,
						withVehicle, withAttachment,
						sizeType, nil, nil,
						offsetX,
						getXMLFloat(xmlFile, placeKey..".offsetY", 0),
						getXMLFloat(xmlFile, placeKey..".offsetZ", 0),
						getXMLFloat(xmlFile, placeKey..".relRotation", 0)
					)
					place.nodeName = (nodeName and nodeName ~= "") and nodeName or referenceFilename or ("refId:" .. tostring(referenceId))
					if referenceId ~= nil then place.referenceId = referenceId end
					if referenceFilename and referenceFilename ~= "" then place.referenceFilename = referenceFilename end
					place.ignoreCollision = ignoreCollision
					if placeJob ~= nil and placeJob ~= "" then
						place.job = placeJob
					end
					if node.id ~= nil then
						local idStr = tostring(node.id)
						place.mapRefNodeId = idStr
						place.collisionExcludeRefIds = { idStr }
					end
					local nodeKey = matchKey .. "_" .. tostring(node.id or i)
					local runtimeNodeId = nodeKeyToRuntimeNode[nodeKey]
					if not (runtimeNodeId and entityExists(runtimeNodeId)) then
						runtimeNodeId = IAMapInitJob and IAMapInitJob.findRuntimeNodeForXmlEntry and IAMapInitJob.findRuntimeNodeForXmlEntry(node, runtimeNodes, usedRuntimeNodeIds)
						if runtimeNodeId and entityExists(runtimeNodeId) then
							nodeKeyToRuntimeNode[nodeKey] = runtimeNodeId
							usedRuntimeNodeIds[runtimeNodeId] = true
						end
					end
					if runtimeNodeId and entityExists(runtimeNodeId) then
						place:resolveFromMapNodeWithRuntimeNode(runtimeNodeId)
					else
						local nx = node.position and node.position.x or 0
						local ny = node.position and node.position.y or 0
						local nz = node.position and node.position.z or 0
						local ry = node.rotation and node.rotation.y or 0
						if self.ianeighbours.debug then
							print(string.format("--- IAXMLHelper:loadPlaceablePlacesFromFile() [DEBUG] node-relative place #%d/%d nodeName=%s (XML fallback) nodePos=(%.3f,%.3f,%.3f) nodeYaw=%.2f deg",
								i, #matchingNodes, tostring(nodeName), nx, ny, nz, ry and math.deg(ry) or 0))
						end
						place:resolveFromMapNode(nx, ny, nz, ry)
					end
				else
					place = IAMapPlace.new(
						nextId, name, placeType or "mapNode",
						getXMLFloat(xmlFile, placeKey..".x", 0),
						getXMLFloat(xmlFile, placeKey..".y", 0),
						getXMLFloat(xmlFile, placeKey..".z", 0),
						getXMLFloat(xmlFile, placeKey..".rotation", 0),
						withVehicle, withAttachment,
						sizeType, nil, nil, nil, nil, nil, nil
					)
					place.nodeName = (nodeName and nodeName ~= "") and nodeName or referenceFilename or ("refId:" .. tostring(referenceId))
					if referenceId ~= nil then place.referenceId = referenceId end
					if referenceFilename and referenceFilename ~= "" then place.referenceFilename = referenceFilename end
					place.ignoreCollision = ignoreCollision
					if placeJob ~= nil and placeJob ~= "" then
						place.job = placeJob
					end
				end
				-- Terrain bounds filter first, then dedupe.
				if not isWithinTerrainBoundsRect(place.x, place.z, terrainBounds) then
					if self.ianeighbours.debug then
						local boundsStr = (terrainBounds ~= nil)
							and (" bounds=(" .. tostring(terrainBounds.minX) .. "," .. tostring(terrainBounds.maxX) .. "," .. tostring(terrainBounds.minZ) .. "," .. tostring(terrainBounds.maxZ) .. ")")
							or " bounds=<unknown>"
						print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Skipping node place outside terrain bounds: name=" .. tostring(place.name) .. " type=" .. tostring(place.type) .. " pos=(" .. tostring(place.x) .. "," .. tostring(place.z) .. ")" .. boundsStr)
					end
				else
					-- Deduplicate: skip if map place file already has a place at this position (e.g. from loadMapConfiguration)
					local skipDuplicate = (self.ianeighbours.placesLoader and self.ianeighbours.placesLoader.placeExistsAtPosition and place.x ~= nil and place.z ~= nil) and self.ianeighbours.placesLoader:placeExistsAtPosition(place.x, place.z, place.type or "mapNode")
					if not skipDuplicate then
						table.insert(self.ianeighbours.places, place)
						nextId = nextId + 1
						nodeCreatedCount = nodeCreatedCount + 1
					end
				end
			end
		elseif placeableFilename ~= nil then
			local name = getXMLString(xmlFile, placeKey..".name", nil) or ("Place " .. tostring(nextId))
			local place = IAMapPlace.new(
				nextId,
				name,
				placeType,
				0, 0, 0, 0,
				getXMLBool(xmlFile, placeKey..".withVehicle", true),
				getXMLBool(xmlFile, placeKey..".withAttachment", false),
				sizeType,
				nil,
				placeableFilename,
				getXMLFloat(xmlFile, placeKey..".offsetX", 0),
				getXMLFloat(xmlFile, placeKey..".offsetY", 0),
				getXMLFloat(xmlFile, placeKey..".offsetZ", 0),
				getXMLFloat(xmlFile, placeKey..".relRotation", 0)
			)
			place.ignoreCollision = ignoreCollision
			if placeJob ~= nil and placeJob ~= "" then
				place.job = placeJob
			end
			table.insert(self.ianeighbours.places, place)
			nextId = nextId + 1
		end
		placeIndex = placeIndex + 1
	end
	delete(xmlFile)
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:loadPlaceablePlacesFromFile() - Loaded "..tostring(placeIndex).." XML entries, created "..tostring(nodeCreatedCount).." node places into IANeighbours.places")
	end
	return true
end

--- Save map config (map info + all places with absolute coords) to mod settings as fields_of_stories_<mapId>.xml (single file, mapConfiguration format).
-- Builds list from ianeighbours.places: every place that has valid absolute x,y,z.
-- @param string mapId - Map ID (e.g. "MapUS")
-- @return boolean true if saved, false on error or missing mapId
function IAXMLHelper:saveMapConfigToFile(mapId)
	if mapId == nil or mapId == "" then
		return false
	end
	local places = self.ianeighbours.places
	if places == nil then
		places = {}
	end
	-- Build list of places with valid absolute coordinates (full snapshot for persistence)
	local list = {}
	for _, place in ipairs(places) do
		if place and place.type and place.x ~= nil and place.z ~= nil then
			local semanticType = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
			local entry = {
				id = place.id,
				name = place.name,
				type = semanticType,
				x = place.x,
				y = place.y or 0,
				z = place.z,
				rotation = place.rotation or 0,
				withVehicle = place.withVehicle ~= false,
				withAttachment = place.withAttachment == true,
				ignoreCollision = place.ignoreCollision == true
			}
			if place.sizeType ~= nil and tostring(place.sizeType) ~= "" then
				entry.sizeType = tostring(place.sizeType)
			end
			if place.job ~= nil and place.job ~= "" then
				entry.job = place.job
			end
			if place.description ~= nil and place.description ~= "" then
				entry.description = place.description
			end
			if place.referenceFilename ~= nil and place.referenceFilename ~= "" then
				entry.referenceFilename = place.referenceFilename
			end
			if place.nodeName ~= nil and place.nodeName ~= "" then
				entry.nodeName = place.nodeName
			end
			if place.referenceId ~= nil then
				entry.referenceId = place.referenceId
			end
			if place.mapRefNodeId ~= nil and place.mapRefNodeId ~= "" then
				entry.mapRefNodeId = place.mapRefNodeId
			end
			if place.offsetX ~= nil then entry.offsetX = place.offsetX end
			if place.offsetY ~= nil then entry.offsetY = place.offsetY end
			if place.offsetZ ~= nil then entry.offsetZ = place.offsetZ end
			if place.relRotation ~= nil then entry.relRotation = place.relRotation end
			local exclRefs = {}
			if place.collisionExcludeRefIds ~= nil then
				for _, r in ipairs(place.collisionExcludeRefIds) do
					if r ~= nil and tostring(r) ~= "" then
						exclRefs[#exclRefs + 1] = tostring(r)
					end
				end
			end
			if #exclRefs == 0 and place.mapRefNodeId ~= nil and tostring(place.mapRefNodeId) ~= "" then
				exclRefs[1] = tostring(place.mapRefNodeId)
			end
			if #exclRefs > 0 then
				entry.collisionExcludeRefIds = exclRefs
			end
			list[#list + 1] = entry
		end
	end
	local dir = self:getModSettingsDirectory()
	if not folderExists(dir) then
		createFolder(dir)
	end
	local path = dir .. "fields_of_stories_" .. tostring(mapId) .. ".xml"
	local rootKey = "mapConfiguration"
	local xmlFile = createXMLFile("FieldsOfStoriesMapConfig", path, rootKey)
	if xmlFile == nil then
		if self.ianeighbours.debug then
			print("--- IAXMLHelper:saveMapConfigToFile() - Failed to create: "..path)
		end
		return false
	end
	-- Map section (same as load)
	local mapKey = rootKey..".map"
	setXMLString(xmlFile, mapKey.."#id", tostring(mapId))
	local mapDisplayName = nil
	if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
		local mt = g_currentMission.missionInfo.mapTitle
		if mt ~= nil and mt ~= "" then
			mapDisplayName = mt
		end
	end
	if mapDisplayName == nil or mapDisplayName == "" then
		mapDisplayName = self.ianeighbours.mapName
	end
	if mapDisplayName == nil or mapDisplayName == "" then
		local idStr = tostring(mapId)
		if string.sub(idStr, 1, 3) == "Map" then
			mapDisplayName = idStr
		else
			mapDisplayName = "Map " .. idStr
		end
	end
	setXMLString(xmlFile, mapKey..".name", mapDisplayName)
	if self.ianeighbours.mapGameId ~= nil then
		setXMLString(xmlFile, mapKey..".mapGameId", tostring(self.ianeighbours.mapGameId))
	end
	-- Places (same structure as load: mapConfiguration.places.place(i))
	for i, entry in ipairs(list) do
		if entry and entry.type then
			local placeKey = rootKey..".places.place("..(i - 1)..")"
			local placeId = entry.id or i
			setXMLInt(xmlFile, placeKey.."#id", placeId)
			if entry.name ~= nil and entry.name ~= "" then
				setXMLString(xmlFile, placeKey..".name", tostring(entry.name))
			end
			setXMLString(xmlFile, placeKey..".type", tostring(entry.type))
			setXMLFloat(xmlFile, placeKey..".x", entry.x or 0)
			setXMLFloat(xmlFile, placeKey..".y", entry.y or 0)
			setXMLFloat(xmlFile, placeKey..".z", entry.z or 0)
			setXMLFloat(xmlFile, placeKey..".rotation", entry.rotation or 0)
			if entry.sizeType ~= nil and tostring(entry.sizeType) ~= "" then
				setXMLString(xmlFile, placeKey..".sizeType", tostring(entry.sizeType))
			end
			setXMLBool(xmlFile, placeKey..".withVehicle", entry.withVehicle ~= false)
			setXMLBool(xmlFile, placeKey..".withAttachment", entry.withAttachment == true)
			if entry.ignoreCollision == true then
				setXMLBool(xmlFile, placeKey..".ignoreCollision", true)
			end
			if entry.job ~= nil and entry.job ~= "" then
				setXMLString(xmlFile, placeKey..".job", tostring(entry.job))
			end
			if entry.description ~= nil and entry.description ~= "" then
				setXMLString(xmlFile, placeKey..".description", tostring(entry.description))
			end
			if entry.referenceFilename ~= nil and entry.referenceFilename ~= "" then
				setXMLString(xmlFile, placeKey.."#referenceFilename", self:normalizeFsRelativePath(entry.referenceFilename))
			end
			if entry.nodeName ~= nil and entry.nodeName ~= "" then
				setXMLString(xmlFile, placeKey.."#nodeName", tostring(entry.nodeName))
			end
			if entry.referenceId ~= nil then
				setXMLInt(xmlFile, placeKey.."#referenceId", entry.referenceId)
			end
			if entry.mapRefNodeId ~= nil and entry.mapRefNodeId ~= "" then
				setXMLString(xmlFile, placeKey.."#mapRefNodeId", tostring(entry.mapRefNodeId))
			end
			if entry.offsetX ~= nil then
				setXMLFloat(xmlFile, placeKey..".offsetX", entry.offsetX)
			end
			if entry.offsetY ~= nil then
				setXMLFloat(xmlFile, placeKey..".offsetY", entry.offsetY)
			end
			if entry.offsetZ ~= nil then
				setXMLFloat(xmlFile, placeKey..".offsetZ", entry.offsetZ)
			end
			if entry.relRotation ~= nil then
				setXMLFloat(xmlFile, placeKey..".relRotation", entry.relRotation)
			end
			if entry.collisionExcludeRefIds ~= nil then
				for j, rid in ipairs(entry.collisionExcludeRefIds) do
					if rid ~= nil and tostring(rid) ~= "" then
						setXMLString(xmlFile, placeKey..".collisionExcludeRefId("..(j - 1)..")#id", tostring(rid))
					end
				end
			end
		end
	end
	-- Save neighbour homebase assignments (assignedHomebasePlaceIds) so character homebases persist with the map
	local assignKey = rootKey..".neighbourHomebaseAssignments"
	local neighbourIdx = 0
	for _, neighbour in pairs(self.ianeighbours.neighbours or {}) do
		if neighbour ~= nil and neighbour.id ~= nil and neighbour.assignedHomebasePlaceIds ~= nil and #neighbour.assignedHomebasePlaceIds > 0 then
			local nKey = assignKey..".neighbour("..neighbourIdx..")"
			setXMLInt(xmlFile, nKey.."#id", neighbour.id)
			for pidIdx, placeId in ipairs(neighbour.assignedHomebasePlaceIds) do
				setXMLInt(xmlFile, nKey..".placeId("..(pidIdx - 1)..")#id", placeId)
			end
			neighbourIdx = neighbourIdx + 1
		end
	end
	-- Save neighbour workplace assignments (character_job place ids)
	local wpAssignKey = rootKey..".neighbourWorkplaceAssignments"
	local wpNeighbourIdx = 0
	for _, neighbour in pairs(self.ianeighbours.neighbours or {}) do
		if neighbour ~= nil and neighbour.id ~= nil and neighbour.assignedWorkplacePlaceIds ~= nil and #neighbour.assignedWorkplacePlaceIds > 0 then
			local wKey = wpAssignKey..".neighbour("..wpNeighbourIdx..")"
			setXMLInt(xmlFile, wKey.."#id", neighbour.id)
			for wpidIdx, wPlaceId in ipairs(neighbour.assignedWorkplacePlaceIds) do
				setXMLInt(xmlFile, wKey..".placeId("..(wpidIdx - 1)..")#id", wPlaceId)
			end
			wpNeighbourIdx = wpNeighbourIdx + 1
		end
	end
	-- Save hidden map objects (gates/doors removed at runtime; re-applied as deletions on load)
	local hidden = self.ianeighbours.hiddenMapObjects
	if hidden ~= nil and #hidden > 0 then
		local hidKey = rootKey..".hiddenObjects"
		for i, h in ipairs(hidden) do
			if h ~= nil and h.name ~= nil then
				local oKey = hidKey..".object("..(i - 1)..")"
				setXMLString(xmlFile, oKey.."#name", tostring(h.name))
				if h.index ~= nil and tostring(h.index) ~= "" then
					setXMLString(xmlFile, oKey.."#index", tostring(h.index))
				end
				setXMLFloat(xmlFile, oKey.."#x", h.x or 0)
				setXMLFloat(xmlFile, oKey.."#y", h.y or 0)
				setXMLFloat(xmlFile, oKey.."#z", h.z or 0)
			end
		end
	end
	saveXMLFile(xmlFile)
	delete(xmlFile)
	if self.ianeighbours.debug then
		print("--- IAXMLHelper:saveMapConfigToFile() - Saved "..tostring(#list).." places to "..path)
	end
	return true
end

--- Save map places to mod settings (delegates to saveMapConfigToFile; same single file fields_of_stories_<mapId>.xml).
-- @param string mapId - Map ID (e.g. "MapUS")
-- @return boolean true if saved, false on error or missing mapId
function IAXMLHelper:saveMapInitPlacesToFile(mapId)
	if self.ianeighbours and self.ianeighbours.debug then
		print("--- saveMapConfigToFile caller: IAXMLHelper:saveMapInitPlacesToFile mapId=" .. tostring(mapId))
	end
	return self:saveMapConfigToFile(mapId)
end

-- Minimal outbound (root + savegame metadata only): no neighbours, vehicles, or farmlands. Used after remove-mod so the next load uses default scenario.
-- @param string outboundPath - Full path to IANeighbours_outbound.xml
-- @return boolean
function IAXMLHelper:saveMinimalOutboundXML(outboundPath)
	if outboundPath == nil or outboundPath == "" or g_currentMission == nil or g_currentMission.missionInfo == nil then
		return false
	end
	local xmlFile = createXMLFile("IANeighbours_xml_min_out", outboundPath, "IANeighboursOutbound")
	if xmlFile == nil then
		return false
	end
	local mi = g_currentMission.missionInfo
	if mi.savegameDirectory ~= nil then
		setXMLString(xmlFile, "IANeighboursOutbound#savegamePath", mi.savegameDirectory)
	end
	if mi.mapId ~= nil then
		setXMLString(xmlFile, "IANeighboursOutbound#mapId", mi.mapId)
	end
	if mi.savegameName ~= nil then
		setXMLString(xmlFile, "IANeighboursOutbound#savegameName", mi.savegameName)
	end
	if mi.mapTitle ~= nil then
		setXMLString(xmlFile, "IANeighboursOutbound#mapTitle", mi.mapTitle)
	end
	saveXMLFile(xmlFile)
	delete(xmlFile)
	return true
end

function IAXMLHelper:saveOutboundXMLToXMLFile()
    if g_server ~= nil then
		
        local spec = self.ianeighbours
        if spec == nil or spec.neighbours == nil or g_currentMission == nil or g_currentMission.missionInfo == nil or g_currentMission.missionInfo.savegameDirectory == nil then
            return
        end

        local outboundPath = string.format("%s/IANeighbours_outbound.xml", g_currentMission.missionInfo.savegameDirectory)

		-- Remove-mod path: write minimal outbound (no neighbours/vehicles) so next load uses default scenario; avoids sandbox delete issues on savegame folder.
		if spec.removeModRequested == true then
			if spec.debug then
				IAprintDebug("IAXMLHelper:saveOutboundXMLToXMLFile()", "removeModRequested=true, writing minimal outbound (no neighbours)", nil, nil, nil)
			end
			self:saveMinimalOutboundXML(outboundPath)
			return
		end

        -- Every enabled character has at least one vehicle; do not write outbound until async spawns have registered at least one per neighbour
        for _, neighbour in pairs(spec.neighbours) do
            if neighbour ~= nil and neighbour.enabled and next(neighbour.vehicles) == nil then
                if spec.debug then
                    IAprintDebug("IAXMLHelper:saveOutboundXMLToXMLFile()", "Skipping outbound save: neighbour " .. tostring(neighbour.name) .. " has no vehicles registered yet (async spawn pending); removing outbound file if present", nil, nil, nil)
                end
                self:removeOutboundFileIfExists(outboundPath)
                return
            end
        end

        local file = outboundPath
        local xmlFile = createXMLFile("IANeighbours_xml_temp_out", file, "IANeighboursOutbound")

		
		local playerX, playerY, playerZ = g_localPlayer:getPosition()
		local playerr1 = g_localPlayer:getMovementYaw()
		local playerVehicle = g_localPlayer:getCurrentVehicle()
		if playerVehicle ~= nil then
			playerX, playerY, playerZ = getWorldTranslation(playerVehicle.rootNode)
			local dirX, _, dirZ = localDirectionToWorld(playerVehicle.rootNode, 0, 0, 1)
			playerr1 = MathUtil.getYRotationFromDirection(dirX, dirZ)
			IAprintDebug("IAXMLHelper:saveOutboundXMLToXMLFile()", "Player Vehicle: X: "..tostring(playerX)..", Y: "..tostring(playerY)..", Z: "..tostring(playerZ)..", R: "..tostring(playerr1), nil, nil, nil)
		end
		--local playerr1, playerr2, playerr3 = g_localPlayer:getCurrentFacingDirection();
		setXMLFloat(xmlFile, "IANeighboursOutbound#playerX", playerX)
		setXMLFloat(xmlFile, "IANeighboursOutbound#playerY", playerY)
		setXMLFloat(xmlFile, "IANeighboursOutbound#playerZ", playerZ)
		setXMLFloat(xmlFile, "IANeighboursOutbound#playerR1", playerr1)
		--setXMLFloat(xmlFile, "IANeighboursOutbound#playerR2", playerr2)

		setXMLString(xmlFile, "IANeighboursOutbound#savegamePath", g_currentMission.missionInfo.savegameDirectory)
		setXMLString(xmlFile, "IANeighboursOutbound#mapId", g_currentMission.missionInfo.mapId)
		

		
		setXMLFloat(xmlFile, "IANeighboursOutbound#mapHeight", g_currentMission.mapHeight)
		setXMLFloat(xmlFile, "IANeighboursOutbound#mapWidth", g_currentMission.mapWidth)
		if g_currentMission.missionInfo.money ~= nil then
			setXMLFloat(xmlFile, "IANeighboursOutbound#money", g_currentMission.missionInfo.money)
		else 
			setXMLFloat(xmlFile, "IANeighboursOutbound#money", g_currentMission.missionInfo.initialMoney)
		end
		setXMLString(xmlFile, "IANeighboursOutbound#savegameName", g_currentMission.missionInfo.savegameName)
		if g_currentMission.missionInfo.savegameIndex ~= nil then
			setXMLInt(xmlFile, "IANeighboursOutbound#savegameIndex", g_currentMission.missionInfo.savegameIndex)
		end
		setXMLString(xmlFile, "IANeighboursOutbound#mapTitle", g_currentMission.missionInfo.mapTitle)
		setXMLFloat(xmlFile, "IANeighboursOutbound#ingameMonth", g_currentMission.environment.currentPeriod)
		setXMLString(xmlFile, "IANeighboursOutbound#ingameTime", g_currentMission.environment.currentHour..":"..g_currentMission.environment.currentMinute) 
        
		-- Save player appearance
		if g_localPlayer ~= nil and g_localPlayer.graphicsComponent ~= nil and g_localPlayer.graphicsComponent.style ~= nil and g_localPlayer.graphicsComponent.style.configs ~= nil then
			local styleConfigs = g_localPlayer.graphicsComponent.style.configs
			local appearanceKey = "IANeighboursOutbound.PlayerAppearance"
			
			-- List of appearance categories to save
			local appearanceCategories = {
				"facegear",
				"onepiece",
				"bottom",
				"face",
				"top",
				"gloves",
				"headgear",
				"glasses",
				"footwear",
				"hairStyle",
				"beard"
			}
			
			for _, category in ipairs(appearanceCategories) do
				if styleConfigs[category] ~= nil then
					if styleConfigs[category].selectedItemIndex ~= nil then
						setXMLInt(xmlFile, appearanceKey.."#"..category.."SelectedItemIndex", styleConfigs[category].selectedItemIndex)
					end
					if styleConfigs[category].selectedColorIndex ~= nil then
						setXMLInt(xmlFile, appearanceKey.."#"..category.."SelectedColorIndex", styleConfigs[category].selectedColorIndex)
					end
				end
			end
		end
        
		-- Save vehicle ID mappings
		local vehicleIndex = 0
		for _, neighbour in pairs(self.ianeighbours.neighbours) do
			if neighbour ~= nil and neighbour.vehicles ~= nil then
				for _, ia_vehicle in pairs(neighbour.vehicles) do
					if ia_vehicle ~= nil and ia_vehicle.externalId ~= nil and ia_vehicle.uniqueId ~= nil then
						local vehicleKey = "IANeighboursOutbound.vehicles.vehicle("..vehicleIndex..")"
						setXMLString(xmlFile, vehicleKey.."#externalId", ia_vehicle.externalId)
						setXMLString(xmlFile, vehicleKey.."#uniqueId", ia_vehicle.uniqueId)
						vehicleIndex = vehicleIndex + 1
					end
				end
			end
		end
		
		-- Save all neighbours with all their attributes, vehicles, and situations
		local neighbourIndex = 0
		for _, neighbour in pairs(self.ianeighbours.neighbours) do
			if neighbour ~= nil then
				local neighbourKey = "IANeighboursOutbound.neighbours.neighbour("..neighbourIndex..")"
				
				-- Save basic neighbour attributes
				if neighbour.id ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#id", neighbour.id)
				end
				-- Persist English name canonically in #name (loader treats #name as English); German variant in #nameDe.
				local outName = neighbour.nameEn
				if outName == nil or outName == "" then
					outName = neighbour.name
				end
				if outName ~= nil then
					setXMLString(xmlFile, neighbourKey.."#name", outName)
				end
				if neighbour.nameDe ~= nil and neighbour.nameDe ~= "" then
					setXMLString(xmlFile, neighbourKey.."#nameDe", neighbour.nameDe)
				end
				if neighbour.enabled ~= nil then
					setXMLBool(xmlFile, neighbourKey.."#enabled", neighbour.enabled)
				end
				if neighbour.positionX ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#positionX", neighbour.positionX)
				end
				if neighbour.positionY ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#positionY", neighbour.positionY)
				end
				if neighbour.positionZ ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#positionZ", neighbour.positionZ)
				end
				if neighbour.rotation ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#rotation", neighbour.rotation)
				end
				if neighbour.action ~= nil then
					setXMLString(xmlFile, neighbourKey.."#action", neighbour.action)
				end
				if neighbour.farmId ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#farmId", neighbour.farmId)
				end
				if neighbour.gender ~= nil then
					setXMLString(xmlFile, neighbourKey.."#gender", neighbour.gender)
				end
				if neighbour.characterVisibility ~= nil then
					setXMLString(xmlFile, neighbourKey.."#characterVisibility", neighbour.characterVisibility)
				end
				if neighbour.activeSituationId ~= nil then
					setXMLString(xmlFile, neighbourKey.."#activeSituationId", tostring(neighbour.activeSituationId))
				end
				
				
				if neighbour.defaultPlaceId ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#defaultPlaceId", neighbour.defaultPlaceId)
				end
				if neighbour.assignedHomebasePlaceIds ~= nil and #neighbour.assignedHomebasePlaceIds > 0 then
					for idx, placeId in ipairs(neighbour.assignedHomebasePlaceIds) do
						setXMLInt(xmlFile, neighbourKey..".assignedHomebasePlaceIds.placeId("..(idx-1)..")#id", placeId)
					end
				end
				if neighbour.assignedWorkplacePlaceIds ~= nil and #neighbour.assignedWorkplacePlaceIds > 0 then
					for idx, placeId in ipairs(neighbour.assignedWorkplacePlaceIds) do
						setXMLInt(xmlFile, neighbourKey..".assignedWorkplacePlaceIds.placeId("..(idx-1)..")#id", placeId)
					end
				end
				if neighbour.relationship ~= nil then
					setXMLString(xmlFile, neighbourKey.."#relationship", neighbour.relationship)
				end
				if neighbour.relationshipLevel ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#relationshipLevel", neighbour.relationshipLevel)
				end
				if neighbour.relationshipScore ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#relationshipScore", neighbour.relationshipScore)
				end
				if neighbour.role ~= nil then
					setXMLString(xmlFile, neighbourKey.."#role", neighbour.role)
				end
				if neighbour.job ~= nil then
					setXMLString(xmlFile, neighbourKey.."#job", neighbour.job)
				end
				if neighbour.belongsToFarm ~= nil then
					setXMLBool(xmlFile, neighbourKey.."#belongsToFarm", neighbour.belongsToFarm)
				end
				if neighbour.age ~= nil then
					setXMLString(xmlFile, neighbourKey.."#age", tostring(neighbour.age))
				end
				if neighbour.roleScenarioDescription ~= nil and neighbour.roleScenarioDescription ~= "" then
					setXMLString(xmlFile, neighbourKey..".roleScenarioDescription", neighbour.roleScenarioDescription)
				end
				if neighbour.roleScenarioDescriptionDe ~= nil and neighbour.roleScenarioDescriptionDe ~= "" then
					setXMLString(xmlFile, neighbourKey..".roleScenarioDescriptionDe", neighbour.roleScenarioDescriptionDe)
				end
				if neighbour.behaviours ~= nil and #neighbour.behaviours > 0 then
					for bi, behaviour in ipairs(neighbour.behaviours) do
						if behaviour ~= nil then
							setXMLString(xmlFile, neighbourKey..".behaviour.item("..(bi - 1)..")", tostring(behaviour))
						end
					end
				end
				
				-- Save assigned farmlands and last crop per farmland
				if neighbour.assignedFarmlands ~= nil and #neighbour.assignedFarmlands > 0 then
					local farmlandIndex = 0
					for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
						local farmlandKey = neighbourKey..".assignedFarmlands.farmland("..farmlandIndex..")"
						setXMLInt(xmlFile, farmlandKey.."#id", farmlandId)
						if neighbour.assignedFarmlandLastCrop ~= nil and neighbour.assignedFarmlandLastCrop[farmlandId] ~= nil then
							setXMLInt(xmlFile, farmlandKey.."#lastCrop", neighbour.assignedFarmlandLastCrop[farmlandId])
						end
						if neighbour.assignedFarmlandNextCrop ~= nil and neighbour.assignedFarmlandNextCrop[farmlandId] ~= nil then
							setXMLInt(xmlFile, farmlandKey.."#nextCrop", neighbour.assignedFarmlandNextCrop[farmlandId])
						end
						farmlandIndex = farmlandIndex + 1
					end
				end

				local fsKey = neighbourKey..".fieldworkSchedule"
				if neighbour.fieldworkScheduleYear ~= nil and neighbour.fieldworkScheduleMonth ~= nil and neighbour.fieldworkScheduleDayInPeriod ~= nil then
					setXMLInt(xmlFile, fsKey.."#year", neighbour.fieldworkScheduleYear)
					setXMLInt(xmlFile, fsKey.."#month", neighbour.fieldworkScheduleMonth)
					setXMLInt(xmlFile, fsKey.."#dayInPeriod", neighbour.fieldworkScheduleDayInPeriod)
					if neighbour.fieldworkScheduleTasks ~= nil then
						for ti, task in ipairs(neighbour.fieldworkScheduleTasks) do
							local taskKey = fsKey..".task("..(ti - 1)..")"
							if task.situationId ~= nil then
								setXMLString(xmlFile, taskKey.."#situationId", tostring(task.situationId))
							end
							if task.farmlandId ~= nil then
								setXMLInt(xmlFile, taskKey.."#farmlandId", task.farmlandId)
							end
							if task.seedFruitTypeIndex ~= nil then
								setXMLInt(xmlFile, taskKey.."#seedFruitTypeIndex", task.seedFruitTypeIndex)
							end
							if task.contractEnabled == true then
								setXMLBool(xmlFile, taskKey.."#contractEnabled", true)
							end
							if task.acceptedByPlayer == true then
								setXMLBool(xmlFile, taskKey.."#acceptedByPlayer", true)
							end
						end
					end
				end

				if neighbour.callPlayerHour ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#callPlayerHour", neighbour.callPlayerHour)
				end
				if neighbour.callPlayerMinute ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#callPlayerMinute", neighbour.callPlayerMinute)
				end
				setXMLString(xmlFile, neighbourKey.."#contractCallTriggerFiredForScheduleKey", neighbour.contractCallTriggerFiredForScheduleKey or "")
				setXMLString(xmlFile, neighbourKey.."#contractFallbackToAiFiredForScheduleKey", neighbour.contractFallbackToAiFiredForScheduleKey or "")
				setXMLString(xmlFile, neighbourKey.."#contractCallLastRingScheduleKey", neighbour.contractCallLastRingScheduleKey or "")
				if neighbour.contractCallLastRingTotalMinutes ~= nil then
					setXMLInt(xmlFile, neighbourKey.."#contractCallLastRingTotalMinutes", neighbour.contractCallLastRingTotalMinutes)
				end
				setXMLInt(xmlFile, neighbourKey.."#contractCallRingOpensCount", tonumber(neighbour.contractCallRingOpensCount) or 0)
				setXMLBool(xmlFile, neighbourKey.."#contractCallRingAnsweredToday", neighbour.contractCallRingAnsweredToday == true)

				-- Save real position and rotation (if available)
				if neighbour.realPositionX ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#realPositionX", neighbour.realPositionX)
				end
				if neighbour.realPositionY ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#realPositionY", neighbour.realPositionY)
				end
				if neighbour.realPositionZ ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#realPositionZ", neighbour.realPositionZ)
				end
				if neighbour.realRotation ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#realRotation", neighbour.realRotation)
				end
				if neighbour.distanceToPlayer ~= nil then
					setXMLFloat(xmlFile, neighbourKey.."#distanceToPlayer", neighbour.distanceToPlayer)
				end
				
				-- Save style attributes
				-- First check if styleAttributes exists (stored before NPC is loaded)
				local styleData = nil
				if neighbour.styleAttributes ~= nil then
					styleData = neighbour.styleAttributes
				elseif neighbour.resolvedPlayerStyle ~= nil and neighbour.resolvedPlayerStyle.configs ~= nil then
					local style = neighbour.resolvedPlayerStyle
					styleData = {}
					if style.hatHairstyleIndex ~= nil then
						styleData.hathair = style.hatHairstyleIndex
					end
					if style.configs ~= nil then
						local configs = style.configs
						if configs.glasses ~= nil then
							styleData.glasses = configs.glasses.selectedItemIndex
							styleData.glassesColorIndex = configs.glasses.selectedColorIndex
						end
						if configs.facegear ~= nil then
							styleData.facegear = configs.facegear.selectedItemIndex
							styleData.facegearColorIndex = configs.facegear.selectedColorIndex
						end
						if configs.onepiece ~= nil then
							styleData.onepiece = configs.onepiece.selectedItemIndex
							styleData.onepieceColorIndex = configs.onepiece.selectedColorIndex
						end
						if configs.bottom ~= nil then
							styleData.bottom = configs.bottom.selectedItemIndex
							styleData.bottomColorIndex = configs.bottom.selectedColorIndex
						end
						if configs.face ~= nil then
							styleData.face = configs.face.selectedItemIndex
							styleData.faceColorIndex = configs.face.selectedColorIndex
						end
						if configs.top ~= nil then
							styleData.top = configs.top.selectedItemIndex
							styleData.topColorIndex = configs.top.selectedColorIndex
						end
						if configs.gloves ~= nil then
							styleData.gloves = configs.gloves.selectedItemIndex
							styleData.glovesColorIndex = configs.gloves.selectedColorIndex
						end
						if configs.headgear ~= nil then
							styleData.headgear = configs.headgear.selectedItemIndex
							styleData.headgearColorIndex = configs.headgear.selectedColorIndex
						end
						if configs.footwear ~= nil then
							styleData.footwear = configs.footwear.selectedItemIndex
							styleData.footwearColorIndex = configs.footwear.selectedColorIndex
						end
						if configs.hairStyle ~= nil then
							styleData.hairStyle = configs.hairStyle.selectedItemIndex
							styleData.hairStyleColorIndex = configs.hairStyle.selectedColorIndex
						end
						if configs.beard ~= nil then
							styleData.beard = configs.beard.selectedItemIndex
							styleData.beardColorIndex = configs.beard.selectedColorIndex
						end
					end
				end
				
				-- Save style attributes to XML
				if styleData ~= nil then
					if styleData.hathair ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#hathair", styleData.hathair)
					end
					if styleData.glasses ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#glasses", styleData.glasses)
					end
					if styleData.glassesColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#glassesColorIndex", styleData.glassesColorIndex)
					end
					if styleData.facegear ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#facegear", styleData.facegear)
					end
					if styleData.facegearColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#facegearColorIndex", styleData.facegearColorIndex)
					end
					if styleData.onepiece ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#onepiece", styleData.onepiece)
					end
					if styleData.onepieceColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#onepieceColorIndex", styleData.onepieceColorIndex)
					end
					if styleData.bottom ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#bottom", styleData.bottom)
					end
					if styleData.bottomColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#bottomColorIndex", styleData.bottomColorIndex)
					end
					if styleData.face ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#face", styleData.face)
					end
					if styleData.faceColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#faceColorIndex", styleData.faceColorIndex)
					end
					if styleData.top ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#top", styleData.top)
					end
					if styleData.topColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#topColorIndex", styleData.topColorIndex)
					end
					if styleData.gloves ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#gloves", styleData.gloves)
					end
					if styleData.glovesColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#glovesColorIndex", styleData.glovesColorIndex)
					end
					if styleData.headgear ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#headgear", styleData.headgear)
					end
					if styleData.headgearColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#headgearColorIndex", styleData.headgearColorIndex)
					end
					if styleData.footwear ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#footwear", styleData.footwear)
					end
					if styleData.footwearColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#footwearColorIndex", styleData.footwearColorIndex)
					end
					if styleData.hairStyle ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#hairStyle", styleData.hairStyle)
					end
					if styleData.hairStyleColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#hairStyleColorIndex", styleData.hairStyleColorIndex)
					end
					if styleData.beard ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#beard", styleData.beard)
					end
					if styleData.beardColorIndex ~= nil then
						setXMLInt(xmlFile, neighbourKey.."#beardColorIndex", styleData.beardColorIndex)
					end
				end
				
				-- Save all vehicles for this neighbour
				if neighbour.vehicles ~= nil then
					local vehicleIndex = 0
					for _, ia_vehicle in pairs(neighbour.vehicles) do
						if ia_vehicle ~= nil then
							local vehicleKey = neighbourKey..".vehicle("..vehicleIndex..")"
							
							-- Save vehicle attributes
							if ia_vehicle.uniqueId ~= nil then
								setXMLString(xmlFile, vehicleKey.."#uniqueId", tostring(ia_vehicle.uniqueId))
							end
							if ia_vehicle.externalId ~= nil then
								setXMLString(xmlFile, vehicleKey.."#id", ia_vehicle.externalId)
							end
							if ia_vehicle.xmlFilename ~= nil then
								setXMLString(xmlFile, vehicleKey.."#xmlFilename", ia_vehicle.xmlFilename)
							end
							if ia_vehicle.positionX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#positionX", ia_vehicle.positionX)
							end
							if ia_vehicle.positionY ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#positionY", ia_vehicle.positionY)
							end
							if ia_vehicle.positionZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#positionZ", ia_vehicle.positionZ)
							end
							if ia_vehicle.rotation ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#rotation", ia_vehicle.rotation)
							end
							if ia_vehicle.parkingPlaceId ~= nil then
								setXMLString(xmlFile, vehicleKey.."#parkingPlaceId", tostring(ia_vehicle.parkingPlaceId))
							end
							if ia_vehicle.parkingPlaceSemantic ~= nil then
								setXMLString(xmlFile, vehicleKey.."#parkingPlaceSemantic", tostring(ia_vehicle.parkingPlaceSemantic))
							end
							if ia_vehicle.isBorrowedByPlayer == true then
								setXMLBool(xmlFile, vehicleKey.."#borrowedByPlayer", true)
							end
							if ia_vehicle.borrowReturnParkingPlaceId ~= nil then
								setXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceId", tostring(ia_vehicle.borrowReturnParkingPlaceId))
							end
							if ia_vehicle.borrowReturnParkingPlaceSemantic ~= nil then
								setXMLString(xmlFile, vehicleKey.."#borrowReturnParkingPlaceSemantic", tostring(ia_vehicle.borrowReturnParkingPlaceSemantic))
							end
							if ia_vehicle.borrowPickupPositionX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionX", ia_vehicle.borrowPickupPositionX)
							end
							if ia_vehicle.borrowPickupPositionY ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionY", ia_vehicle.borrowPickupPositionY)
							end
							if ia_vehicle.borrowPickupPositionZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#borrowPickupPositionZ", ia_vehicle.borrowPickupPositionZ)
							end
							if ia_vehicle.borrowPickupRotation ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#borrowPickupRotation", ia_vehicle.borrowPickupRotation)
							end
							if ia_vehicle.farmId ~= nil then
								setXMLInt(xmlFile, vehicleKey.."#farmId", ia_vehicle.farmId)
							end
							if ia_vehicle.activeSituationId ~= nil then
								setXMLString(xmlFile, vehicleKey.."#activeSituationId", tostring(ia_vehicle.activeSituationId))
							end
							if ia_vehicle.type ~= nil then
								setXMLString(xmlFile, vehicleKey.."#type", ia_vehicle.type)
							end
							if ia_vehicle.category ~= nil then
								setXMLString(xmlFile, vehicleKey.."#category", ia_vehicle.category)
							end
							if ia_vehicle.npcOffsetX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcOffsetX", ia_vehicle.npcOffsetX)
							end
							if ia_vehicle.npcOffsetY ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcOffsetY", ia_vehicle.npcOffsetY)
							end
							if ia_vehicle.npcOffsetZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcOffsetZ", ia_vehicle.npcOffsetZ)
							end
							if ia_vehicle.npcOffsetRotation ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcOffsetRotation", ia_vehicle.npcOffsetRotation)
							end
							if ia_vehicle.realPositionX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#realPositionX", ia_vehicle.realPositionX)
							end
							if ia_vehicle.realPositionY ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#realPositionY", ia_vehicle.realPositionY)
							end
							if ia_vehicle.realPositionZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#realPositionZ", ia_vehicle.realPositionZ)
							end
							if ia_vehicle.realRotation ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#realRotation", ia_vehicle.realRotation)
							end
							if ia_vehicle.npcPositionX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcPositionX", ia_vehicle.npcPositionX)
							end
							if ia_vehicle.npcPositionY ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcPositionY", ia_vehicle.npcPositionY)
							end
							if ia_vehicle.npcPositionZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcPositionZ", ia_vehicle.npcPositionZ)
							end
							if ia_vehicle.npcRotation ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#npcRotation", ia_vehicle.npcRotation)
							end
							if ia_vehicle.jobType ~= nil then
								setXMLString(xmlFile, vehicleKey.."#jobType", ia_vehicle.jobType)
							end
							if ia_vehicle.jobTargetX ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#jobTargetX", ia_vehicle.jobTargetX)
							end
							if ia_vehicle.jobTargetZ ~= nil then
								setXMLFloat(xmlFile, vehicleKey.."#jobTargetZ", ia_vehicle.jobTargetZ)
							end
							if ia_vehicle.colorIndex ~= nil then
								setXMLInt(xmlFile, vehicleKey.."#colorIndex", ia_vehicle.colorIndex)
							end
							
							vehicleIndex = vehicleIndex + 1
						end
					end
				end
				
				-- Save active situation for this neighbour
				if neighbour.activeSituation ~= nil then
					local situation = neighbour.activeSituation
					local situationKey = neighbourKey..".situation"
					
					-- Save constructor parameters (needed for recreation)
					if situation.config ~= nil and situation.config.id ~= nil then
						setXMLString(xmlFile, situationKey.."#configId", tostring(situation.config.id))
					end
					if situation.place ~= nil and situation.place.id ~= nil then
						setXMLInt(xmlFile, situationKey.."#placeId", situation.place.id)
					end
					if situation.farmlandId ~= nil then
						setXMLInt(xmlFile, situationKey.."#farmlandId", situation.farmlandId)
					end
					if situation.jobType ~= nil then
						setXMLString(xmlFile, situationKey.."#jobType", tostring(situation.jobType))
					end
					if situation.jobType ~= nil and string.lower(tostring(situation.jobType)) == "seed" and situation.seedFruitTypeIndex ~= nil then
						setXMLInt(xmlFile, situationKey.."#seedFruitTypeIndex", situation.seedFruitTypeIndex)
					end
					
					-- Save vehicle and attachment references
					if situation.vehicle ~= nil then
						if situation.vehicle.uniqueId ~= nil then
							setXMLString(xmlFile, situationKey.."#vehicleUniqueId", tostring(situation.vehicle.uniqueId))
						end
						if situation.vehicle.externalId ~= nil then
							setXMLString(xmlFile, situationKey.."#vehicleExternalId", situation.vehicle.externalId)
						end
					end
					if situation.attachmentBack ~= nil then
						if situation.attachmentBack.uniqueId ~= nil then
							setXMLString(xmlFile, situationKey.."#attachmentBackUniqueId", tostring(situation.attachmentBack.uniqueId))
						end
						if situation.attachmentBack.externalId ~= nil then
							setXMLString(xmlFile, situationKey.."#attachmentBackExternalId", situation.attachmentBack.externalId)
						end
					end
					if situation.attachmentFront ~= nil then
						if situation.attachmentFront.uniqueId ~= nil then
							setXMLString(xmlFile, situationKey.."#attachmentFrontUniqueId", tostring(situation.attachmentFront.uniqueId))
						end
						if situation.attachmentFront.externalId ~= nil then
							setXMLString(xmlFile, situationKey.."#attachmentFrontExternalId", situation.attachmentFront.externalId)
						end
					end
					
					-- Save state attributes (set after creation)
					if situation.startedAt ~= nil then
						setXMLFloat(xmlFile, situationKey.."#startedAt", situation.startedAt)
					end
					if situation.loadStep ~= nil then
						setXMLInt(xmlFile, situationKey.."#loadStep", situation.loadStep)
					end
					if situation.loaded ~= nil then
						setXMLBool(xmlFile, situationKey.."#loaded", situation.loaded)
					end
					if situation.initCommitted ~= nil then
						setXMLBool(xmlFile, situationKey.."#initCommitted", situation.initCommitted)
					end
					if situation._preBlockFarmlandOwnerFarmId ~= nil then
						setXMLInt(xmlFile, situationKey.."#preBlockFarmlandOwnerFarmId", situation._preBlockFarmlandOwnerFarmId)
					end
					if situation._preBlockFarmlandFieldStateOwnerFarmId ~= nil then
						setXMLInt(xmlFile, situationKey.."#preBlockFarmlandFieldStateOwnerFarmId", situation._preBlockFarmlandFieldStateOwnerFarmId)
					end
					if situation.dialogMessageId ~= nil then
						setXMLInt(xmlFile, situationKey.."#dialogMessageId", situation.dialogMessageId)
					end
					
					-- Save dialog messages
					if situation.dialogMessages ~= nil and #situation.dialogMessages > 0 then
						for messageIndex, message in ipairs(situation.dialogMessages) do
							local messageKey = situationKey..".dialogMessages.message("..(messageIndex - 1)..")"
							if message.id ~= nil then
								setXMLInt(xmlFile, messageKey.."#id", message.id)
							end
							if message.text ~= nil then
								setXMLString(xmlFile, messageKey.."#text", message.text)
							end
							if message.sender ~= nil then
								setXMLString(xmlFile, messageKey.."#sender", message.sender)
							end
						end
					end
				end
				
				-- Save situation history
				if neighbour.situationHistory ~= nil and #neighbour.situationHistory > 0 then
					local historyKey = neighbourKey..".situationHistory"
					for historyIndex, historyItem in ipairs(neighbour.situationHistory) do
						local historyItemKey = historyKey..".situation("..(historyIndex - 1)..")"
						
						if historyItem.situationId ~= nil then
							setXMLString(xmlFile, historyItemKey.."#situationId", tostring(historyItem.situationId))
						end
						if historyItem.placeId ~= nil then
							setXMLInt(xmlFile, historyItemKey.."#placeId", historyItem.placeId)
						end
						if historyItem.startedAt ~= nil then
							setXMLFloat(xmlFile, historyItemKey.."#startedAt", historyItem.startedAt)
						end
						-- Save vehicle ids as array
						if historyItem.vehicleIds ~= nil and #historyItem.vehicleIds > 0 then
							for vehicleIdIndex, vehicleId in ipairs(historyItem.vehicleIds) do
								setXMLString(xmlFile, historyItemKey..".vehicleIds.vehicleId("..(vehicleIdIndex - 1)..")", tostring(vehicleId))
							end
						end
					end
				end
				
				neighbourIndex = neighbourIndex + 1
			end
		end
		
		-- Save nearby situation details if it exists
		if self.ianeighbours.nearbySituation ~= nil then
			local situation = self.ianeighbours.nearbySituation
			setXMLString(xmlFile, "IANeighboursOutbound.nearbySituation#id", tostring(situation.id))
			
			-- Save position and rotation
			if situation.positionX ~= nil then
				setXMLFloat(xmlFile, "IANeighboursOutbound.nearbySituation#positionX", situation.positionX)
			end
			if situation.positionY ~= nil then
				setXMLFloat(xmlFile, "IANeighboursOutbound.nearbySituation#positionY", situation.positionY)
			end
			if situation.positionZ ~= nil then
				setXMLFloat(xmlFile, "IANeighboursOutbound.nearbySituation#positionZ", situation.positionZ)
			end
			if situation.rotation ~= nil then
				setXMLFloat(xmlFile, "IANeighboursOutbound.nearbySituation#rotation", situation.rotation)
			end
			
			-- Save neighbour information
			if situation.neighbour ~= nil then
				setXMLString(xmlFile, "IANeighboursOutbound.nearbySituation.neighbour#id", tostring(situation.neighbour.id))
				setXMLString(xmlFile, "IANeighboursOutbound.nearbySituation.neighbour#name", situation.neighbour.name)
				if situation.neighbour.farmId ~= nil then
					setXMLInt(xmlFile, "IANeighboursOutbound.nearbySituation.neighbour#farmId", situation.neighbour.farmId)
				end
			end
			
			-- Save dialog messages
			if situation.dialogMessages ~= nil and #situation.dialogMessages > 0 then
				for messageIndex, message in ipairs(situation.dialogMessages) do
					local messageKey = "IANeighboursOutbound.nearbySituation.dialogMessages.message("..(messageIndex - 1)..")"
					if message.id ~= nil then
						setXMLInt(xmlFile, messageKey.."#id", message.id)
					end
					if message.text ~= nil then
						setXMLString(xmlFile, messageKey.."#text", message.text)
					end
					if message.sender ~= nil then
						setXMLString(xmlFile, messageKey.."#sender", message.sender)
					end
				end
			end
		end

		local fruitTypes = g_fruitTypeManager:getFruitTypes()
		local fruitTypeIndex = 0
		for _, fruitType in ipairs(fruitTypes) do
			setXMLString(xmlFile, "IANeighboursOutbound.fruitTypes.fruitType("..fruitTypeIndex..")", fruitType.name)
			fruitTypeIndex = fruitTypeIndex + 1
		end
		
		local farmlands = g_farmlandManager:getFarmlands()
		local farmlandIndex = 0
		for _, farmland in pairs(farmlands) do
			local farmlandKey = "IANeighboursOutbound.farmlands.farmland("..farmlandIndex..")"
			setXMLInt(xmlFile, farmlandKey.."#id", farmland.id)
			setXMLInt(xmlFile, farmlandKey.."#farmId", farmland.farmId)
			setXMLFloat(xmlFile, farmlandKey.."#areaInHa", farmland.areaInHa)
			setXMLFloat(xmlFile, farmlandKey.."#price", farmland.price)
			setXMLFloat(xmlFile, farmlandKey.."#xWorldPos", farmland.xWorldPos)
			setXMLFloat(xmlFile, farmlandKey.."#zWorldPos", farmland.zWorldPos)
			setXMLString(xmlFile, farmlandKey.."#isOwned", tostring(farmland.isOwned))
			--printObj(farmland,3,"farmland")
			--printObj(farmland.field,3,"farmland.field")
			if farmland.field ~= nil then
				local field = farmland.field
				-- Prefer live density sample at field center (FieldState:update) over cached field.fieldState / getFieldState().
				local fs = nil
				if FieldState ~= nil and type(FieldState.new) == "function" then
					local cx, cz = nil, nil
					if type(field.getCenterOfFieldWorldPosition) == "function" then
						cx, cz = field:getCenterOfFieldWorldPosition()
					end
					if cx ~= nil and cz ~= nil then
						local probe = FieldState.new()
						if type(probe.update) == "function" then
							local okUp, _ = pcall(probe.update, probe, cx, cz)
							if okUp then
								fs = probe
							end
						end
					end
				end
				if fs == nil and type(field.getFieldState) == "function" then
					local okG, g = pcall(field.getFieldState, field)
					if okG and g ~= nil then
						fs = g
					end
				end
				if fs == nil and field.fieldState ~= nil then
					fs = field.fieldState
				end
				if fs ~= nil then
					setXMLInt(xmlFile, farmlandKey.."#fruitTypeIndex", fs.fruitTypeIndex)
					for _, fruitType in ipairs(fruitTypes) do
						if fs.fruitTypeIndex == fruitType.index then
							setXMLString(xmlFile, farmlandKey.."#fruitType", fruitType.name)
						end
					end
					for _, fruitType in ipairs(fruitTypes) do
						if fs.fruitTypeIndex == fruitType.index then
							for i, name in ipairs(fruitType.growthStateToName) do
								if i == fs.growthState then
									setXMLString(xmlFile, farmlandKey.."#growthStateName", name)
								end
							end
						end
					end
					setXMLInt(xmlFile, farmlandKey.."#growthState", fs.growthState)
					setXMLInt(xmlFile, farmlandKey.."#weedState", fs.weedState)
					setXMLInt(xmlFile, farmlandKey.."#weedFactor", fs.weedFactor or 0)
					setXMLInt(xmlFile, farmlandKey.."#stoneLevel", fs.stoneLevel)
					setXMLInt(xmlFile, farmlandKey.."#groundType", fs.groundType)
					local groundTypes = FieldGroundType.getAllOrdered()
					for _, groundType in ipairs(groundTypes) do
						local name = FieldGroundType.getName(groundType)
						if groundType == fs.groundType then
							setXMLString(xmlFile, farmlandKey.."#groundTypeName", name)
						end
					end
					setXMLInt(xmlFile, farmlandKey.."#sprayType", fs.sprayType)
					setXMLInt(xmlFile, farmlandKey.."#sprayLevel", fs.sprayLevel)
					setXMLInt(xmlFile, farmlandKey.."#limeLevel", fs.limeLevel)
					setXMLInt(xmlFile, farmlandKey.."#rollerLevel", fs.rollerLevel)
					setXMLInt(xmlFile, farmlandKey.."#plowLevel", fs.plowLevel)
				end
			end
			
			farmlandIndex = farmlandIndex + 1
		end

		if IAFieldOutcomeMission ~= nil and IAFieldOutcomeMission.appendOutboundFieldOutcomeMissionsXml ~= nil then
			pcall(IAFieldOutcomeMission.appendOutboundFieldOutcomeMissionsXml, xmlFile)
		end

		if IASettings ~= nil and type(IASettings.saveStateToOutboundXML) == "function" then
			pcall(IASettings.saveStateToOutboundXML, xmlFile, "IANeighboursOutbound")
		end

        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
end

