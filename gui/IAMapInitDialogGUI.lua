--
-- Map Init dialog (Shift+F3): one button per place type; clicking saves current position + that type to IANeighbours.places and map place file.
--
IAMapInitDialogGUI = {}
IAMapInitDialogGUI.modInstance = nil
IAMapInitDialogGUI.dialog = nil
IAMapInitDialogGUI.selectedPlaceSizeIndex = 1
IAMapInitDialogGUI.selectedCharacterIndex = 1
-- Active dialog tab: "story" (character relationships) or "settings" (place/character tools).
IAMapInitDialogGUI.activeTab = "story"

-- Layout constants for fallback height only (XML: placeButton 44px, elementSpacing 6px; real layout can be taller).
IAMapInitDialogGUI.PLACE_BUTTON_HEIGHT_PX = 44
IAMapInitDialogGUI.PLACE_ELEMENT_SPACING_PX = 15
-- When true or IANeighbours.debug, scroll height math is printed to the game log.
IAMapInitDialogGUI.DEBUG_SCROLL_HEIGHT = false
IAMapInitDialogGUI.PLACE_SIZE_OPTIONS = {
	{ withVehicle = false, withAttachment = false, l10nKey = "gui_mapinit_place_size_character" },
	{ withVehicle = true, withAttachment = false, l10nKey = "gui_mapinit_place_size_vehicle" },
	{ withVehicle = true, withAttachment = true, l10nKey = "gui_mapinit_place_size_vehicle_attachment" },
	-- Oversize vehicle: still saved as withVehicle+withAttachment for compatibility; sizeType differentiates (used for homebase parking).
	{ withVehicle = true, withAttachment = true, sizeType = "oversize_vehicle", l10nKey = "gui_mapinit_place_size_oversize_vehicle" },
	-- Large area: wider and longer than vehicle+attachment; intended for area-based situations (e.g. homebase vehicle preparation).
	{ withVehicle = true, withAttachment = true, sizeType = "large_area", l10nKey = "gui_mapinit_place_size_large_area" }
}

-- Map-init helper: nudge player vehicle sideways. One "tick" = this many metres (change if your grid uses another step).
IAMapInitDialogGUI.VEHICLE_NUDGE_TICK_METERS = 1
IAMapInitDialogGUI.VEHICLE_NUDGE_TICKS_LEFT = 5

--- In-game HUD notification for map-init actions (Shift+F3).
function IAMapInitDialogGUI.showMapInitOkNotification(text)
	if text == nil then
		return
	end
	local s = tostring(text)
	if s == "" then
		return
	end
	pcall(function()
		if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
			g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, s)
		end
	end)
end

--- Refresh place-size button text according to selectedPlaceSizeIndex.
function IAMapInitDialogGUI:updatePlaceSizeButtonText()
	local btn = self:getDescendantById("placeSizeButton")
	if btn == nil or btn.setText == nil then
		return
	end
	local option = IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[self.selectedPlaceSizeIndex or 1] or IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[1]
	local labelPrefix = g_i18n:getText("gui_mapinit_place_size_label")
	if labelPrefix == nil or labelPrefix == "" then
		labelPrefix = "Place size:"
	end
	local optionText = g_i18n:getText(option.l10nKey)
	if optionText == nil or optionText == "" then
		optionText = IAMapInitDialogGUI.getPlaceKindDebugSuffix(option.withVehicle, option.withAttachment)
	end
	btn:setText(string.format("<-    %s %s    ->", labelPrefix, optionText))
end

--- Get currently selected place-size flags.
function IAMapInitDialogGUI:getSelectedPlaceSizeFlags()
	local option = IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[self.selectedPlaceSizeIndex or 1] or IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[1]
	return option.withVehicle == true, option.withAttachment == true
end

--- Get currently selected place-size type string (character/vehicle/vehicle_attachment/oversize_vehicle/large_area).
function IAMapInitDialogGUI:getSelectedPlaceSizeType()
	local option = IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[self.selectedPlaceSizeIndex or 1] or IAMapInitDialogGUI.PLACE_SIZE_OPTIONS[1]
	if option.sizeType ~= nil then
		return tostring(option.sizeType)
	end
	if option.withAttachment == true then
		return "vehicle_attachment"
	end
	if option.withVehicle == true then
		return "vehicle"
	end
	return "character"
end

--- Set place-type button color: green when count is good, default dark otherwise.
function IAMapInitDialogGUI.setPlaceButtonColor(button, countGood)
	if button == nil or button.setImageColor == nil then
		return
	end
	if g_gui == nil or GuiUtils == nil or GuiOverlay == nil then
		return
	end
	local preset = countGood and (g_gui.presets and g_gui.presets["fs25_colorGreen"]) or (g_gui.presets and g_gui.presets["fs25_colorMainDark_90"])
	if preset == nil then
		return
	end
	local colorArray = GuiUtils.getColorArray(preset)
	if colorArray then
		button:setImageColor(GuiOverlay.STATE_NORMAL, unpack(colorArray))
		button:setImageColor(GuiOverlay.STATE_HIGHLIGHTED, unpack(colorArray))
		button:setImageColor(GuiOverlay.STATE_FOCUSED, unpack(colorArray))
	end
end

-- Place types for static buttons (character_homebase last: one button per neighbour in characterHomesContainer)
IAMapInitDialogGUI.PLACE_TYPES = {
	"shop",
	"gas_station",
	"roadside",
	"dirt_road",
	"public_place",
	"player_farm",
	"public_relax_place",
	"private_relax_place",
	"sell_point",
	"church",
	"public_infrastructure",
	"roadside_trees",
	"industry",
	"workshop",
	"shed",
	--"other",
	"character_homebase"  -- container at bottom; one button per neighbour
}

-- Minimum required count per place type (character_homebase = scenario character count via getCharacterHomebaseMin())
IAMapInitDialogGUI.PLACE_TYPE_MIN = {
	shop = 3,
	gas_station = 3,
	roadside = 20,
	dirt_road = 10,
	public_place = 0,
	player_farm = 0,
	public_relax_place = 0,
	private_relax_place = 0,
	sell_point = 5,
	church = 0,
	public_infrastructure = 0,
	roadside_trees = 0,
	industry = 0,
	workshop = 0,
	shed = 0,
	other = 0
	-- character_homebase: from getCharacterHomebaseMin()
}

--- Minimum character_homebase count = number of characters in the selected scenario (later: scenario selection before init).
function IAMapInitDialogGUI.getCharacterHomebaseMin()
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return 0
	end
	local n = 0
	for _ in pairs(IANeighbours.neighbours) do
		n = n + 1
	end
	return n
end

--- Get minimum required count for a place type.
function IAMapInitDialogGUI.getPlaceTypeMin(ptype)
	if ptype == "character_homebase" then
		return IAMapInitDialogGUI.getCharacterHomebaseMin()
	end
	return IAMapInitDialogGUI.PLACE_TYPE_MIN[ptype] or 0
end

--- True for place types not shown as Shift+F3 map-init debug markers (too many defaults, e.g. tree rows).
function IAMapInitDialogGUI.shouldExcludePlaceFromMapInitDebug(place)
	if place == nil then
		return true
	end
	local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
	return st == "roadside_trees"
end

--- Count existing places by type (all from IANeighbours.places).
function IAMapInitDialogGUI.countPlacesByType()
	local counts = {}
	local list = IANeighbours and IANeighbours.places or {}
	for _, place in ipairs(list) do
		if place and place.type then
			counts[place.type] = (counts[place.type] or 0) + 1
		end
	end
	return counts
end

--- Compare neighbour/place ids that may be number or string in XML/runtime.
local function iaMapInitIdsEqual(a, b)
	if a == nil or b == nil then
		return false
	end
	if a == b then
		return true
	end
	local na, nb = tonumber(tostring(a)), tonumber(tostring(b))
	return na ~= nil and nb ~= nil and na == nb
end

--- Get character name for a given neighbour id (e.g. from place.characterNumber). Returns name string or nil.
function IAMapInitDialogGUI.getCharacterNameByNumber(characterNumber)
	if characterNumber == nil then
		return nil
	end
	local neighbours = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	for _, n in ipairs(neighbours) do
		if n and iaMapInitIdsEqual(n.id, characterNumber) then
			return (n.name and tostring(n.name):gsub("^%s+", ""):gsub("%s+$", "")) or nil
		end
	end
	return nil
end

--- For character_homebase and shed places without entry.characterNumber: assignment is neighbour.assignedHomebasePlaceIds (homebase + paired shed ids in map config).
--- Returns display string of assigned character name(s), or nil.
function IAMapInitDialogGUI.getAssignedCharacterNamesForHomebasePlace(place)
	if place == nil or place.id == nil or IANeighbours == nil or IANeighbours.neighbours == nil then
		return nil
	end
	local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
	if st ~= "character_homebase" and st ~= "shed" then
		return nil
	end
	local seen = {}
	local out = {}
	for _, n in pairs(IANeighbours.neighbours) do
		if n and not n.isDeleted and n.assignedHomebasePlaceIds ~= nil then
			for _, pid in ipairs(n.assignedHomebasePlaceIds) do
				if iaMapInitIdsEqual(pid, place.id) then
					local key = n.id ~= nil and tostring(n.id) or nil
					if key ~= nil and not seen[key] then
						seen[key] = true
						local nm = (n.name and tostring(n.name):gsub("^%s+", ""):gsub("%s+$", "")) or nil
						if nm ~= nil and nm ~= "" then
							out[#out + 1] = nm
						else
							out[#out + 1] = "#" .. tostring(n.id)
						end
					end
					break
				end
			end
		end
	end
	if #out == 0 then
		return nil
	end
	return table.concat(out, " / ")
end

--- Return place kind suffix for debug labels: "Character", "Vehicle", or "Vehicle+Attach".
function IAMapInitDialogGUI.getPlaceKindDebugSuffix(withVehicle, withAttachment)
	if withAttachment == true then
		return "Vehicle+Attach"
	end
	if withVehicle == true then
		return "Vehicle"
	end
	return "Character"
end

--- Preferred: return place kind suffix when sizeType is available.
function IAMapInitDialogGUI.getPlaceKindDebugSuffixBySizeType(sizeType, withVehicle, withAttachment)
	local st = sizeType ~= nil and string.lower(tostring(sizeType)) or nil
	if st == "large_area" then
		return "LargeArea"
	end
	if st == "oversize_vehicle" then
		return "Oversize"
	end
	if st == "vehicle_attachment" then
		return "Vehicle+Attach"
	end
	if st == "vehicle" then
		return "Vehicle"
	end
	if st == "character" then
		return "Character"
	end
	return IAMapInitDialogGUI.getPlaceKindDebugSuffix(withVehicle, withAttachment)
end

local function iaSafeText(v)
	if v == nil then
		return "-"
	end
	local s = tostring(v)
	s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return "-"
	end
	return s
end

local function iaBasenameNoExt(path)
	if path == nil then
		return nil
	end
	local s = tostring(path)
	s = s:gsub("\\", "/")
	local base = s:match("([^/]+)$") or s
	base = base:gsub("%.xml$", "")
	return base
end

--- Resolve a situation id to a human-readable name (from loaded situation configs).
-- Uses IASituationConfig.intent as the "name" (fallback: type).
function IAMapInitDialogGUI.getSituationDisplayNameById(situationId)
	if situationId == nil then
		return nil
	end
	local sid = tostring(situationId)
	IAMapInitDialogGUI._situationNameById = IAMapInitDialogGUI._situationNameById or {}
	local cached = IAMapInitDialogGUI._situationNameById[sid]
	if cached ~= nil then
		return cached
	end

	local configs = IANeighbours and IANeighbours.situationConfigs or nil
	local best = nil
	if configs ~= nil then
		for _, cfg in ipairs(configs) do
			if cfg ~= nil and cfg.id ~= nil and tostring(cfg.id) == sid then
				best = cfg.intent or cfg.type or cfg.id
				break
			end
		end
	end
	if best == nil or tostring(best) == "" then
		best = sid
	end
	best = tostring(best)
	IAMapInitDialogGUI._situationNameById[sid] = best
	return best
end

--- Display label for one IA vehicle entry (same rules as the vehicles list).
function IAMapInitDialogGUI.getDisplayNameForIaVehicle(v)
	if v == nil then
		return nil
	end
	local label = nil
	if v.vehicle ~= nil and v.vehicle.getName ~= nil then
		local ok, name = pcall(v.vehicle.getName, v.vehicle)
		if ok and name ~= nil and tostring(name) ~= "" then
			label = tostring(name)
		end
	end
	if label == nil then
		local typeStr = v.type ~= nil and tostring(v.type) or nil
		local catStr = v.category ~= nil and tostring(v.category) or nil
		local xmlBase = iaBasenameNoExt(v.xmlFilename)
		label = xmlBase or typeStr or catStr or v.uniqueId or v.externalId
	end
	if label == nil then
		return nil
	end
	return iaSafeText(label)
end

--- Locate the loaded IASituationConfig for a situation id (used to enrich schedule rows with intent/type/fieldwork).
function IAMapInitDialogGUI.getSituationConfigById(situationId)
	if situationId == nil then
		return nil
	end
	local sid = tostring(situationId)
	local configs = IANeighbours and IANeighbours.situationConfigs or nil
	if configs == nil then
		return nil
	end
	for _, cfg in ipairs(configs) do
		if cfg ~= nil and cfg.id ~= nil and tostring(cfg.id) == sid then
			return cfg
		end
	end
	return nil
end

--- Resolve a fruit type index (number) to its uppercase fruit type name (e.g. "WHEAT").
local function iaResolveFruitTypeName(idx)
	if idx == nil then
		return nil
	end
	local n = tonumber(idx)
	if n == nil then
		return nil
	end
	if g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
		return tostring(n)
	end
	local ok, ft = pcall(g_fruitTypeManager.getFruitTypeByIndex, g_fruitTypeManager, n)
	if not ok or ft == nil then
		return tostring(n)
	end
	return ft.name or tostring(n)
end

--- Format neighbour vehicles as a bullet-ish text list.
function IAMapInitDialogGUI.formatVehiclesList(neighbour)
	local vehicles = neighbour and neighbour.vehicles or nil
	if vehicles == nil or next(vehicles) == nil then
		return "-"
	end

	-- vehicles is a map keyed by uniqueId, not an array (so ipairs/# won't work).
	local list = {}
	for _, v in pairs(vehicles) do
		if v ~= nil then
			list[#list + 1] = v
		end
	end
	table.sort(list, function(a, b)
		local ka = a and (a.uniqueId or a.externalId or a.xmlFilename or "") or ""
		local kb = b and (b.uniqueId or b.externalId or b.xmlFilename or "") or ""
		return tostring(ka) < tostring(kb)
	end)

	local lines = {}
	for _, v in ipairs(list) do
		if v ~= nil then
			local label = IAMapInitDialogGUI.getDisplayNameForIaVehicle(v)
			if label ~= nil and label ~= "" then
				lines[#lines + 1] = "- " .. label
			end
		end
	end
	if #lines == 0 then
		return "-"
	end
	return table.concat(lines, "\n")
end

--- Format current situation info in a user-friendly way.
function IAMapInitDialogGUI.formatCurrentSituation(neighbour)
	if neighbour == nil then
		return "-"
	end
	local s = neighbour.activeSituation
	local id = neighbour.activeSituationId
	if s == nil and id == nil then
		return "-"
	end
	local sid = (s ~= nil and s.id ~= nil) and s.id or id
	local disp = IAMapInitDialogGUI.getSituationDisplayNameById(sid)

	-- Localized format string for place label
	local iaAtPlaceFmt = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_detail_at_place_fmt") or nil
	if iaAtPlaceFmt == nil or iaAtPlaceFmt == "" or iaAtPlaceFmt == "gui_mapinit_detail_at_place_fmt" then
		iaAtPlaceFmt = "at %s"
	end

	-- Collect human-readable parts
	local parts = {}
	parts[#parts + 1] = disp  -- e.g. "Harvest wheat"

	if s ~= nil then
		-- Place info (name/type) when available
		if s.place ~= nil then
			local ptype = nil
			if s.place.getSemanticType ~= nil then
				local ok, sem = pcall(s.place.getSemanticType, s.place)
				if ok then ptype = sem end
			end
			if ptype == nil or tostring(ptype) == "" then
				ptype = s.place.type
			end
			if ptype ~= nil and tostring(ptype) ~= "" then
				-- Translate place type
				local l10nKey = "gui_mapinit_place_type_" .. tostring(ptype)
				local placeLabel = (g_i18n and g_i18n.getText) and g_i18n:getText(l10nKey) or nil
				if placeLabel == nil or placeLabel == "" or placeLabel == l10nKey then
					placeLabel = tostring(ptype)
				end
				parts[#parts + 1] = string.format(iaAtPlaceFmt, placeLabel)
			end
		end

		local function addVeh(prefix, iaVeh)
			if iaVeh == nil then return end
			local lbl = IAMapInitDialogGUI.getDisplayNameForIaVehicle(iaVeh)
			if lbl ~= nil and lbl ~= "" then
				parts[#parts + 1] = prefix .. ": " .. lbl
			end
		end
		addVeh("Vehicle", s.vehicle)
		addVeh("Back attachment", s.attachmentBack)
		addVeh("Front attachment", s.attachmentFront)
	end

	if #parts == 0 then
		return disp
	end
	return table.concat(parts, "\n")
end

--- Format the neighbour's planned fieldwork schedule for today in a readable form.
function IAMapInitDialogGUI.formatFieldworkSchedule(neighbour)
	if neighbour == nil then
		return "-"
	end
	local lines = {}

	-- Header: schedule day, daily contract call window, ring counters.
	local headerParts = {}
	if neighbour.fieldworkScheduleYear ~= nil
		and neighbour.fieldworkScheduleMonth ~= nil
		and neighbour.fieldworkScheduleDayInPeriod ~= nil
	then
		headerParts[#headerParts + 1] = string.format("Day %s-%s-%s",
			tostring(neighbour.fieldworkScheduleYear),
			tostring(neighbour.fieldworkScheduleMonth),
			tostring(neighbour.fieldworkScheduleDayInPeriod))
	else
		headerParts[#headerParts + 1] = "Day -"
	end
	if neighbour.callPlayerHour ~= nil and neighbour.callPlayerMinute ~= nil then
		headerParts[#headerParts + 1] = string.format("Call at %02d:%02d",
			tonumber(neighbour.callPlayerHour) or 0,
			tonumber(neighbour.callPlayerMinute) or 0)
	else
		headerParts[#headerParts + 1] = "Call time -"
	end
	local openCount = tonumber(neighbour.contractCallRingOpensCount) or 0
	local maxOpens = (IAGameLoopHelper ~= nil and IAGameLoopHelper.CONTRACT_CALL_MAX_RING_OPENS_PER_DAY) or 0
	headerParts[#headerParts + 1] = string.format("Rings: %d / %d", openCount, maxOpens)
	local answered = neighbour.contractCallRingAnsweredToday == true
	headerParts[#headerParts + 1] = answered and "Answered today" or "Not answered yet"
	local fallbackKey = (neighbour.contractFallbackToAiFiredForScheduleKey ~= nil and tostring(neighbour.contractFallbackToAiFiredForScheduleKey) ~= "") and true or false
	headerParts[#headerParts + 1] = fallbackKey and "AI fallback: yes" or "AI fallback: no"
	lines[#lines + 1] = table.concat(headerParts, "  |  ")

	local tasks = neighbour.fieldworkScheduleTasks
	if tasks == nil or #tasks == 0 then
		lines[#lines + 1] = "(No fieldwork planned for today)"
		return table.concat(lines, "\n")
	end

	for i, row in ipairs(tasks) do
		if row ~= nil then
			local status
			if row.acceptedByPlayer == true then
				status = "Player"
			elseif row.contractEnabled == true then
				status = "Contract"
			else
				status = "AI"
			end
			local fid = row.farmlandId ~= nil and tostring(row.farmlandId) or "-"
			local sid = row.situationId ~= nil and tostring(row.situationId) or "-"
			local cfg = IAMapInitDialogGUI.getSituationConfigById(sid)
			local intent = (cfg ~= nil and (cfg.intent or cfg.type)) or sid
			local job = (cfg ~= nil and cfg.fieldwork ~= nil and tostring(cfg.fieldwork) ~= "") and tostring(cfg.fieldwork) or nil

			local parts = { string.format("%d. [%s]", i, status) }
			parts[#parts + 1] = iaSafeText(intent)
			if job ~= nil then
				parts[#parts + 1] = "(" .. iaSafeText(job) .. ")"
			end
			parts[#parts + 1] = "on field " .. fid
			if row.seedFruitTypeIndex ~= nil then
				local seedName = iaResolveFruitTypeName(row.seedFruitTypeIndex)
				if seedName ~= nil and seedName ~= "" then
					parts[#parts + 1] = "- " .. iaSafeText(seedName)
				end
			end
			lines[#lines + 1] = table.concat(parts, " ")
		end
	end
	return table.concat(lines, "\n")
end

function IAMapInitDialogGUI:setSelectedCharacterIndex(newIndex)
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local count = list and #list or 0
	if count <= 0 then
		self.selectedCharacterIndex = 1
		return
	end
	local idx = tonumber(newIndex) or 1
	if idx < 1 then
		idx = count
	elseif idx > count then
		idx = 1
	end
	self.selectedCharacterIndex = idx
end

--- Points required to reach the next relationship level at a given level.
function IAMapInitDialogGUI.getRelationshipThreshold(level)
	local lv = tonumber(level) or 1
	if lv < 1 then
		lv = 1
	end
	return 500 * lv
end

--- Localized relationship type label (Known, Friend, Family, …).
function IAMapInitDialogGUI.getRelationshipDisplayText(neighbour)
	if neighbour == nil or neighbour.relationship == nil then
		return "-"
	end
	local rel = tostring(neighbour.relationship):gsub("^%s+", ""):gsub("%s+$", "")
	if rel == "" then
		return "-"
	end
	local key = "gui_relationship_" .. string.lower(rel):gsub("%s+", "_")
	if g_i18n ~= nil and g_i18n.getText ~= nil then
		local text = g_i18n:getText(key)
		if text ~= nil and text ~= "" and text ~= key then
			return text
		end
	end
	return rel
end

--- Apply character portrait to a story-tab Bitmap (slice atlas or direct DDS fallback).
function IAMapInitDialogGUI.setStoryCharacterPortrait(bitmap, neighbour)
	if bitmap == nil then
		return
	end
	if IANeighbours ~= nil and IANeighbours.registerCharacterPortraitTextures ~= nil then
		IANeighbours.registerCharacterPortraitTextures()
	end
	if neighbour ~= nil and neighbour.id ~= nil and IANeighbours ~= nil and IANeighbours.getCharacterPortraitSliceId ~= nil then
		local sliceId = IANeighbours.getCharacterPortraitSliceId(neighbour.id)
		if sliceId ~= nil and g_overlayManager ~= nil and g_overlayManager.getSliceInfoById ~= nil then
			local slice = g_overlayManager:getSliceInfoById(sliceId)
			if slice ~= nil and bitmap.setImageSlice ~= nil then
				bitmap:setImageSlice(nil, sliceId)
				return
			end
		end
	end
	if neighbour ~= nil and neighbour._characterPortraitImagePathForMap ~= nil and bitmap.setImageFilename ~= nil then
		local path = neighbour:_characterPortraitImagePathForMap()
		if path ~= nil and path ~= "" then
			bitmap:setImageFilename(path)
		end
	end
end

--- Highlight the selected entry in the story-tab character list (green = selected).
function IAMapInitDialogGUI:updateStoryCharacterListHighlight()
	local box = self:getDescendantById("storyCharacterListBox")
	if box == nil or box.elements == nil then
		return
	end
	local selectedIdx = tonumber(self.selectedCharacterIndex) or 1
	for _, el in ipairs(box.elements) do
		if el ~= nil and el.characterIndex ~= nil then
			IAMapInitDialogGUI.setPlaceButtonColor(el, el.characterIndex == selectedIdx)
		end
	end
end

--- Build the scrollable story-tab character list from neighbours (one button per character).
function IAMapInitDialogGUI:populateStoryCharacterList()
	local container = self:getDescendantById("storyCharacterListBox")
	local template = self:getDescendantById("storyCharacterButtonTemplate")
	if container == nil or template == nil then
		return
	end
	if template.setVisible ~= nil then
		template:setVisible(false)
	end
	if container.elements ~= nil and container.removeElement ~= nil then
		while #container.elements > 1 do
			container:removeElement(container.elements[#container.elements])
		end
	end
	local neighbours = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local selectedIdx = tonumber(self.selectedCharacterIndex) or 1
	for i, n in ipairs(neighbours) do
		local clone = template:clone(container, false, false)
		clone.characterIndex = i
		if clone.setText ~= nil then
			clone:setText(iaSafeText(n.name))
		end
		IAMapInitDialogGUI.setPlaceButtonColor(clone, i == selectedIdx)
		if clone.setVisible ~= nil then
			clone:setVisible(true)
		end
	end
	if container.invalidateLayout ~= nil then
		container:invalidateLayout()
	end
	local scroll = self:getDescendantById("storyCharacterListScrollingLayout")
	if scroll ~= nil and scroll.invalidateLayout ~= nil then
		scroll:invalidateLayout()
	end
	self:refreshScrollBoxHeight("storyCharacterListBox", "storyCharacterListScrollingLayout", false, 12, 6)
end

--- Refresh story-tab right panel: portrait, relationship, level, points progress bar.
function IAMapInitDialogGUI:updateStoryCharacterDetailsUI()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local count = list and #list or 0
	local idx = tonumber(self.selectedCharacterIndex) or 1
	local function set(id, txt)
		local el = self:getDescendantById(id)
		if el ~= nil and el.setText ~= nil then
			el:setText(txt)
		end
	end
	local bg = self:getDescendantById("storyRelationshipProgressBg")
	local fill = self:getDescendantById("storyRelationshipProgressFill")
	local function setProgressFill(fraction)
		if bg == nil or fill == nil or fill.setSize == nil then
			return
		end
		local totalW = (bg.size and bg.size[1]) or 0
		local totalH = (bg.size and bg.size[2]) or (fill.size and fill.size[2]) or 0
		local fillW = 0
		if fraction > 0 and totalW > 0 then
			fillW = math.max(totalW * 0.02, totalW * fraction)
		end
		fill:setSize(fillW, totalH)
	end
	if count <= 0 then
		set("storyCharacterDataTitle", "-")
		set("storyRelationshipValue", "-")
		set("storyRelationshipLevelValue", "-")
		set("storyRelationshipProgressText", "0 / 0")
		setProgressFill(0)
		local portrait = self:getDescendantById("storyCharacterPortrait")
		IAMapInitDialogGUI.setStoryCharacterPortrait(portrait, nil)
		self:updateStoryCharacterListHighlight()
		return
	end
	if idx < 1 then
		idx = 1
	elseif idx > count then
		idx = count
	end
	local n = list[idx]
	set("storyCharacterDataTitle", iaSafeText(n.name))
	set("storyRelationshipValue", IAMapInitDialogGUI.getRelationshipDisplayText(n))
	local level = tonumber(n.relationshipLevel) or 1
	set("storyRelationshipLevelValue", tostring(level))
	local score = tonumber(n.relationshipScore) or 0
	local threshold = IAMapInitDialogGUI.getRelationshipThreshold(level)
	local fmt = (g_i18n ~= nil and g_i18n.getText ~= nil) and g_i18n:getText("gui_mapinit_story_relationship_points_fmt") or nil
	if fmt == nil or fmt == "" or fmt == "gui_mapinit_story_relationship_points_fmt" then
		fmt = "%d / %d"
	end
	set("storyRelationshipProgressText", string.format(fmt, score, threshold))
	local fraction = 0
	if threshold > 0 then
		fraction = math.min(1, math.max(0, score / threshold))
	end
	setProgressFill(fraction)
	local portrait = self:getDescendantById("storyCharacterPortrait")
	IAMapInitDialogGUI.setStoryCharacterPortrait(portrait, n)
	self:updateStoryCharacterListHighlight()
end

function IAMapInitDialogGUI:onClickStoryCharacter(triggerElement)
	local source = triggerElement
	if source == nil then
		local scroll = self:getDescendantById("storyCharacterListScrollingLayout")
		source = scroll and scroll.focusElement
	end
	local idx = source and source.characterIndex
	if idx == nil then
		return
	end
	self:setSelectedCharacterIndex(idx)
	self:updateStoryCharacterListHighlight()
	self:updateStoryCharacterDetailsUI()
end

function IAMapInitDialogGUI:updateCharacterDetailsUI()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local count = list and #list or 0
	local idx = tonumber(self.selectedCharacterIndex) or 1
	if count <= 0 then
		local label = self:getDescendantById("characterSelectedLabel")
		if label and label.setText then
			label:setText("-")
		end
		local function set(id, txt)
			local el = self:getDescendantById(id)
			if el and el.setText then
				el:setText(txt)
			end
		end
		set("characterDetailName", "-")
		set("characterDetailJob", "-")
		set("characterDetailRole", "-")
		set("characterDetailRelationship", "-")
		set("characterDetailVehiclesList", "-")
		set("characterDetailCurrentSituation", "-")
		set("characterDetailSchedule", "-")
		return
	end
	if idx < 1 then
		idx = 1
	elseif idx > count then
		idx = count
	end
	local n = list[idx]
	local selectedLabel = self:getDescendantById("characterSelectedLabel")
	if selectedLabel and selectedLabel.setText then
		selectedLabel:setText(string.format("%s (%d/%d)", iaSafeText(n.name), idx, count))
	end

	local function set(id, txt)
		local el = self:getDescendantById(id)
		if el and el.setText then
			el:setText(txt)
		end
	end
	set("characterDetailName", iaSafeText(n.name))
	set("characterDetailJob", iaSafeText(n.job))
	set("characterDetailRole", iaSafeText(n.role))

	-- Relationship line: type, level, points combined in a readable format
	local relDisplay = IAMapInitDialogGUI.getRelationshipDisplayText(n)
	local level = tonumber(n.relationshipLevel) or 1
	local score = tonumber(n.relationshipScore) or 0
	local threshold = IAMapInitDialogGUI.getRelationshipThreshold(level)
	local relFmt = (g_i18n ~= nil and g_i18n.getText ~= nil) and g_i18n:getText("gui_mapinit_detail_relationship_fmt") or nil
	if relFmt == nil or relFmt == "" or relFmt == "gui_mapinit_detail_relationship_fmt" then
		relFmt = "%s (Level %d, %d / %d pts)"
	end
	set("characterDetailRelationship", string.format(relFmt, relDisplay, level, score, threshold))

	set("characterDetailVehiclesList", IAMapInitDialogGUI.formatVehiclesList(n))
	set("characterDetailCurrentSituation", IAMapInitDialogGUI.formatCurrentSituation(n))
	set("characterDetailSchedule", IAMapInitDialogGUI.formatFieldworkSchedule(n))

	-- Force layout refresh to avoid overlapping auto-height texts after setText()
	local detailsBox = self:getDescendantById("characterDetailsBox")
	local scroll = self:getDescendantById("characterDetailsScrollingLayout")
	local container = self:getDescendantById("characterDetailsScrollContainer")
	if detailsBox and detailsBox.invalidateLayout then
		detailsBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
	if container and container.invalidateLayout then
		container:invalidateLayout()
	end

	self:refreshCharacterDetailsScrollHeight()

	-- Reset scroll to top on character switch (if supported)
	if scroll and scroll.scrollTo ~= nil then
		scroll:scrollTo(0, true, false)
	end
end
--- Build debug label for an IAMapPlace (name/type + place kind suffix). Use for placeable-relative and node-relative places in debug display.
function IAMapInitDialogGUI.getDebugLabelForPlace(place)
	if place == nil then
		return nil
	end
	local s = (place.name or place.type or "place") .. " - " .. IAMapInitDialogGUI.getPlaceKindDebugSuffixBySizeType(place.sizeType, place.withVehicle, place.withAttachment)
	if place.id ~= nil then
		s = s .. " [id=" .. tostring(place.id) .. "]"
	end
	return s
end

--- Build debug label for a mapInitPlace entry (same as used when saving). Appends place kind (Character/Vehicle/Vehicle+Attach).
function IAMapInitDialogGUI.getLabelForMapInitPlaceEntry(entry)
	if entry == nil or entry.type == nil then
		return nil
	end
	local label = entry.type
	if entry.characterNumber ~= nil then
		label = label .. " (" .. tostring(entry.characterNumber) .. ")"
		local charName = IAMapInitDialogGUI.getCharacterNameByNumber(entry.characterNumber)
		if charName ~= nil and charName ~= "" then
			label = label .. " - " .. charName
		end
	else
		local assignedNames = IAMapInitDialogGUI.getAssignedCharacterNamesForHomebasePlace(entry)
		if assignedNames ~= nil and assignedNames ~= "" then
			label = label .. " - " .. assignedNames
		end
	end
	label = label .. " - " .. IAMapInitDialogGUI.getPlaceKindDebugSuffixBySizeType(entry.sizeType, entry.withVehicle, entry.withAttachment)
	if entry.id ~= nil then
		label = label .. " [id=" .. tostring(entry.id) .. "]"
	end
	return label
end

--- Count assigned character_homebase places per neighbour (excludes paired shed ids on assignedHomebasePlaceIds).
--- Returns map neighbour_id -> count.
function IAMapInitDialogGUI.countCharacterHomebaseByNumber()
	local byNum = {}
	local places = IANeighbours and IANeighbours.places or {}
	local placeById = {}
	for _, p in ipairs(places) do
		if p and p.id ~= nil then
			placeById[p.id] = p
		end
	end
	local neighbours = IANeighbours and IANeighbours.neighbours or {}
	for _, n in pairs(neighbours) do
		if n and n.id ~= nil and not n.isDeleted then
			local count = 0
			if n.assignedHomebasePlaceIds then
				for _, id in ipairs(n.assignedHomebasePlaceIds) do
					local p = placeById[id]
					if p ~= nil then
						local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
						if st == "character_homebase" then
							count = count + 1
						end
					end
				end
			end
			byNum[n.id] = count
		end
	end
	return byNum
end

--- Neighbours in stable order (sorted by id).
function IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return {}
	end
	local list = {}
	for _, n in pairs(IANeighbours.neighbours) do
		if n and not n.isDeleted then
			table.insert(list, n)
		end
	end
	table.sort(list, function(a, b)
		local idA = a.id and tonumber(tostring(a.id)) or 0
		local idB = b.id and tonumber(tostring(b.id)) or 0
		return idA < idB
	end)
	return list
end

local IAMapInitDialogGUI_mt = Class(IAMapInitDialogGUI, DialogElement)

function IAMapInitDialogGUI.new(target)
	local self = DialogElement.new(target, IAMapInitDialogGUI_mt)
	return self
end

function IAMapInitDialogGUI:setModInstance(modInstance)
	IAMapInitDialogGUI.modInstance = modInstance
end

function IAMapInitDialogGUI:setDialog(dialog)
	self.dialog = dialog
end

--- Resize characterDetailsBox so ScrollingLayout has content height > viewport (same need as place list).
function IAMapInitDialogGUI:refreshCharacterDetailsScrollHeight()
	local scrollBox = self:getDescendantById("characterDetailsBox")
	local scroll = self:getDescendantById("characterDetailsScrollingLayout")
	if scrollBox == nil or scrollBox.setSize == nil then
		return
	end
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
	local visibleChildren = {}
	for _, child in ipairs(scrollBox.elements or {}) do
		if child and (child.visible == nil or child.visible) then
			table.insert(visibleChildren, child)
		end
	end
	if #visibleChildren == 0 then
		return
	end
	local w = (scrollBox.size and scrollBox.size[1]) or 1
	local firstEl = visibleChildren[1]
	local lastEl = visibleChildren[#visibleChildren]
	local firstTop = (firstEl.position and firstEl.position[2]) or 0
	local lastTop = (lastEl.position and lastEl.position[2]) or 0
	local lastH = (lastEl.size and lastEl.size[2]) or 0
	local refH = (g_referenceScreenHeight and g_referenceScreenHeight > 0) and g_referenceScreenHeight or 1080
	local spacingNorm = 6 / refH
	local span = (lastTop - firstTop) + lastH
	local h = span + spacingNorm * 3
	if span <= 0 and #visibleChildren > 0 then
		h = 0
		for i, el in ipairs(visibleChildren) do
			local sh = (el.size and el.size[2]) or 0
			if i > 1 then
				h = h + spacingNorm
			end
			h = h + sh
		end
		h = h + spacingNorm * 2
	end
	if h <= 0 then
		return
	end
	if scroll and scroll.contentSize and scroll.contentSize > h then
		h = scroll.contentSize
	end
	scrollBox:setSize(w, h)
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
end

--- Resize placeButtonsBox so ScrollingLayout can reach all rows (call from onOpen after list is built).
--- Do not add firstEl.position[2] (firstTop) to h: setSize height is content extent only; including firstTop
--- caused firstTop to drift upward each dialog open and h to grow without bound.
function IAMapInitDialogGUI:refreshPlaceButtonsScrollHeight()
	local function scrollHeightDebugEnabled()
		return IAMapInitDialogGUI.DEBUG_SCROLL_HEIGHT == true or (IANeighbours ~= nil and IANeighbours.debug == true)
	end

	local scrollBox = self:getDescendantById("placeButtonsBox")
	local scroll = self:getDescendantById("placeButtonsScrollingLayout")
	if scrollBox == nil or scrollBox.setSize == nil then
		if scrollHeightDebugEnabled() then
			print("[IAMapInitDialogGUI] refreshPlaceButtonsScrollHeight: placeButtonsBox missing or no setSize")
		end
		return
	end
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end

	local visibleChildren = {}
	for _, child in ipairs(scrollBox.elements or {}) do
		if child and (child.visible == nil or child.visible) then
			table.insert(visibleChildren, child)
		end
	end
	if #visibleChildren == 0 then
		if scrollHeightDebugEnabled() then
			print("[IAMapInitDialogGUI] refreshPlaceButtonsScrollHeight: no visible children in placeButtonsBox")
		end
		return
	end

	local totalElements = scrollBox.elements and #scrollBox.elements or 0
	local w = (scrollBox.size and scrollBox.size[1]) or 1
	local firstEl = visibleChildren[1]
	local lastEl = visibleChildren[#visibleChildren]
	local numRows = #visibleChildren
	local firstTop = (firstEl.position and firstEl.position[2]) or 0
	local lastH = (lastEl.size and lastEl.size[2]) or 0

	-- Largest positive step between consecutive row tops (conservative vs averaging).
	local rowPitch = 0
	for i = 1, numRows - 1 do
		local a = visibleChildren[i]
		local b = visibleChildren[i + 1]
		local y0 = a and a.position and a.position[2]
		local y1 = b and b.position and b.position[2]
		if y0 ~= nil and y1 ~= nil then
			local p = y1 - y0
			if p > rowPitch then
				rowPitch = p
			end
		end
	end
	local rowPitchFromFallback = false
	if rowPitch <= 0 and firstEl.size and firstEl.size[2] and firstEl.size[2] > 0 then
		local refH = (g_referenceScreenHeight and g_referenceScreenHeight > 0) and g_referenceScreenHeight or 1080
		rowPitch = firstEl.size[2] + (IAMapInitDialogGUI.PLACE_ELEMENT_SPACING_PX / refH)
		rowPitchFromFallback = true
	end

	local h
	local branch
	if rowPitch > 0 and lastH > 0 then
		-- Content height only (no firstTop): (n-1) steps between row tops + last row + one rowPitch slack at bottom.
		h = (numRows - 1) * rowPitch + lastH + rowPitch
		branch = "stacked"
	elseif numRows == 1 and firstEl.size and firstEl.size[2] and firstEl.size[2] > 0 then
		local refH = (g_referenceScreenHeight and g_referenceScreenHeight > 0) and g_referenceScreenHeight or 1080
		local onePitch = firstEl.size[2] + (IAMapInitDialogGUI.PLACE_ELEMENT_SPACING_PX / refH)
		h = firstEl.size[2] + onePitch
		branch = "single_row"
	else
		local refHeightPx = (g_referenceScreenHeight and g_referenceScreenHeight > 0) and g_referenceScreenHeight or 1080
		local rowH = (firstEl.size and firstEl.size[2] > 0) and firstEl.size[2] or (IAMapInitDialogGUI.PLACE_BUTTON_HEIGHT_PX / refHeightPx)
		local spacingNorm = IAMapInitDialogGUI.PLACE_ELEMENT_SPACING_PX / refHeightPx
		h = (numRows * rowH) + ((numRows - 1) * spacingNorm) + rowH + spacingNorm
		branch = "fallback_constants"
	end

	local hBeforeContentSize = h
	local contentSizeUsed = false
	if scroll and scroll.contentSize and scroll.contentSize > h then
		h = scroll.contentSize
		contentSizeUsed = true
	end

	if scrollHeightDebugEnabled() then
		self._scrollHeightLogSeq = (self._scrollHeightLogSeq or 0) + 1
		local lastTop = (lastEl.position and lastEl.position[2]) or 0
		local span = lastTop - firstTop
		local visH = scroll and scroll.absSize and scroll.absSize[2]
		local cs = scroll and scroll.contentSize
		print(string.format(
			"[IAMapInitDialogGUI] scroll height #%d | visibleRows=%d totalElements=%d | branch=%s rowPitch=%.6f rowPitchFallback=%s firstTop=%.6f lastTop=%.6f span=%.6f lastH=%.6f | h_content=%.6f (no firstTop in setSize) contentSize=%s h_final=%.6f w=%.6f | visViewport_absH=%s",
			self._scrollHeightLogSeq,
			numRows,
			totalElements,
			tostring(branch),
			rowPitch,
			tostring(rowPitchFromFallback),
			firstTop,
			lastTop,
			span,
			lastH,
			hBeforeContentSize,
			cs ~= nil and string.format("%.6f", cs) or "nil",
			h,
			w,
			visH ~= nil and string.format("%.6f", visH) or "nil"
		))
		if contentSizeUsed then
			print("[IAMapInitDialogGUI]   -> h bumped to scroll.contentSize")
		end
	end

	scrollBox:setSize(w, h)
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
end

--- Generic scroll-height refresh for a vertical BoxLayout inside a ScrollingLayout.
--- Set `allowShrink` for content that changes between large and small states; otherwise stale
--- ScrollingLayout.contentSize can keep the box at its previous larger height.
--- `extraBottomPx` adds headroom below the last element so it is not clipped by the viewport.
function IAMapInitDialogGUI:refreshScrollBoxHeight(boxId, scrollId, allowShrink, extraBottomPx, elementSpacingPx)
	local scrollBox = self:getDescendantById(boxId)
	local scroll = self:getDescendantById(scrollId)
	if scrollBox == nil or scrollBox.setSize == nil then
		return
	end
	local w = (scrollBox.size and scrollBox.size[1]) or 1
	if allowShrink then
		scrollBox:setSize(w, 0)
	end
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
	local visibleChildren = {}
	for _, child in ipairs(scrollBox.elements or {}) do
		if child and (child.visible == nil or child.visible) then
			table.insert(visibleChildren, child)
		end
	end
	if #visibleChildren == 0 then
		return
	end
	local firstEl = visibleChildren[1]
	local lastEl = visibleChildren[#visibleChildren]
	local firstTop = (firstEl.position and firstEl.position[2]) or 0
	local lastTop = (lastEl.position and lastEl.position[2]) or 0
	local lastH = (lastEl.size and lastEl.size[2]) or 0
	local refH = (g_referenceScreenHeight and g_referenceScreenHeight > 0) and g_referenceScreenHeight or 1080
	local spacingNorm = ((elementSpacingPx ~= nil and elementSpacingPx) or 6) / refH
	local positionSpan = math.abs(lastTop - firstTop)
	local h = 0
	if positionSpan > 0.000001 and lastH > 0 then
		h = positionSpan + lastH + spacingNorm * 3
	elseif #visibleChildren > 0 then
		h = 0
		for i, el in ipairs(visibleChildren) do
			local sh = (el.size and el.size[2]) or 0
			if i > 1 then
				h = h + spacingNorm
			end
			h = h + sh
		end
		h = h + spacingNorm * 2
	end
	if h <= 0 then
		return
	end
	if extraBottomPx ~= nil and extraBottomPx > 0 then
		h = h + (extraBottomPx / refH)
	end
	if not allowShrink and scroll and scroll.contentSize and scroll.contentSize > h then
		h = scroll.contentSize
	end
	scrollBox:setSize(w, h)
	if scrollBox.invalidateLayout then
		scrollBox:invalidateLayout()
	end
	if scroll and scroll.invalidateLayout then
		scroll:invalidateLayout()
	end
end

function IAMapInitDialogGUI:onOpen()
	IAMapInitDialogGUI:superClass().onOpen(self)
	self:setActiveTab(self.activeTab or "story")
	if self.selectedPlaceSizeIndex == nil then
		self.selectedPlaceSizeIndex = 1
	end
	self:updatePlaceSizeButtonText()
	-- Initialize character details panel
	if self.selectedCharacterIndex == nil then
		self.selectedCharacterIndex = 1
	end
	self:setSelectedCharacterIndex(self.selectedCharacterIndex)
	self:populateStoryCharacterList()
	self:updateStoryCharacterDetailsUI()
	self:updateCharacterDetailsUI()
	self:updateTogglePlaceMarkersButtonText()
	if self.titleElement ~= nil then
		local titleText = g_i18n:getText("gui_mapinit_dialog_title")
		if titleText == nil or titleText == "" then
			titleText = "Fields of Stories – Map init"
		end
		self.titleElement:setText(titleText)
	end
	local counts = IAMapInitDialogGUI.countPlacesByType()
	local charHomeCounts = IAMapInitDialogGUI.countCharacterHomebaseByNumber()
	local box = self:getDescendantById("placeButtonsBox")
	if box and box.elements then
		for i, ptype in ipairs(IAMapInitDialogGUI.PLACE_TYPES) do
			local el = box.elements[i]
			if ptype == "character_homebase" then
				-- el is characterHomesContainer: populate from template, one button per neighbour
				local container = self:getDescendantById("placeButtonsBox")
				local template = container and container:getDescendantById("characterHomeButtonTemplate")
				if container and template then
					template:setVisible(false)
					-- Remove previous clones: all elements after the template (template is last static child in placeButtonsBox)
					if container.elements and container.removeElement then
						local templateIndex = #IAMapInitDialogGUI.PLACE_TYPES
						while #container.elements > templateIndex do
							container:removeElement(container.elements[#container.elements])
						end
					end
					local neighbours = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
					for _, n in ipairs(neighbours) do
						local num = n.id or 0
						local current = charHomeCounts[num] or 0
						local nameStr = (n.name and tostring(n.name):gsub("^%s+", ""):gsub("%s+$", "")) or ""
						local roleStr = (n.role and tostring(n.role):gsub("^%s+", ""):gsub("%s+$", "")) or ""
						local jobStr = (n.job and tostring(n.job):gsub("^%s+", ""):gsub("%s+$", "")) or ""
						local subParts = {}
						if roleStr ~= "" then
							table.insert(subParts, roleStr)
						end
						if jobStr ~= "" then
							table.insert(subParts, jobStr)
						end
						local sub = table.concat(subParts, ", ")
						local label
						if nameStr ~= "" then
							label = (sub ~= "") and string.format("Home of %s (%s)", nameStr, sub) or ("Home of " .. nameStr)
						elseif sub ~= "" then
							label = string.format("Home of (%s)", sub)
						else
							label = "Home of"
						end
						label = label:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
						if label == "Home of" then
							label = "Home of (character " .. tostring(num) .. ")"
						end
						local clone = template:clone(container, false, false)
						clone.placeType = "character_homebase"
						clone.characterNumber = num  -- neighbour id (for button context when saving)
						if clone.setText then
							clone:setText(string.format("%s (%d)", label, current))
						end
						IAMapInitDialogGUI.setPlaceButtonColor(clone, false)
						clone:setVisible(true)
					end
					-- Force layout so homebase buttons stack vertically and don't overlap
					if container.invalidateLayout then
						container:invalidateLayout()
					end
					local scroll = self:getDescendantById("placeButtonsScrollingLayout")
					if scroll and scroll.invalidateLayout then
						scroll:invalidateLayout()
					end
					local box = self:getDescendantById("placeButtonsBox")
					if box and box.invalidateLayout then
						box:invalidateLayout()
					end
				end
			elseif el and el.setText then
				el.placeType = ptype
				local current = counts[ptype] or 0
				local minCount = IAMapInitDialogGUI.getPlaceTypeMin(ptype)
				local label = g_i18n:getText("gui_mapinit_place_type_" .. ptype)
				if label == nil or label == "" then
					label = ptype
				end
				el:setText(string.format("%s (%d)", label, current))
				IAMapInitDialogGUI.setPlaceButtonColor(el, current >= minCount)
			end
		end
		self:refreshPlaceButtonsScrollHeight()
	end
	-- Second pass after full dialog layout (character texts need measured heights for ScrollingLayout).
	self:refreshCharacterDetailsScrollHeight()
	-- Story progress bar width depends on laid-out container size.
	self:updateStoryCharacterDetailsUI()
end

function IAMapInitDialogGUI:onClickCharacterPrev()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	if list == nil or #list == 0 then
		return
	end
	self:setSelectedCharacterIndex((self.selectedCharacterIndex or 1) - 1)
	self:updateStoryCharacterListHighlight()
	self:updateStoryCharacterDetailsUI()
	self:updateCharacterDetailsUI()
end

function IAMapInitDialogGUI:onClickCharacterNext()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	if list == nil or #list == 0 then
		return
	end
	self:setSelectedCharacterIndex((self.selectedCharacterIndex or 1) + 1)
	self:updateStoryCharacterListHighlight()
	self:updateStoryCharacterDetailsUI()
	self:updateCharacterDetailsUI()
end

--- Detect if player is in a vehicle and if that vehicle has an attachment. Used when saving a place to set withVehicle and withAttachment.
-- @return boolean withVehicle - true if player is in a vehicle
-- @return boolean withAttachment - true if that vehicle has at least one attached implement
function IAMapInitDialogGUI.getWithVehicleAndAttachmentFromPlayer()
	local withVehicle = false
	local withAttachment = false
	if g_localPlayer and g_localPlayer.getCurrentVehicle then
		local v = g_localPlayer:getCurrentVehicle()
		if v ~= nil and not (v.isDeleted) then
			withVehicle = true
			if v.getAttachedImplements and type(v.getAttachedImplements) == "function" then
				local attached = v:getAttachedImplements()
				if attached and #attached > 0 then
					withAttachment = true
				end
			end
		end
	end
	return withVehicle, withAttachment
end

--- Get current player position (or vehicle if in one): x, y, z, rotationY (world space).
-- Uses same method as vehicle positioning: forward direction then MathUtil.getYRotationFromDirection (avoids getWorldRotation Euler clamp at Â±Ï€/2).
function IAMapInitDialogGUI:getCurrentPosition()
	if g_localPlayer == nil then
		return 0, 0, 0, 0
	end
	local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) then
		local x, y, z = getWorldTranslation(v.rootNode)
		local dirX, _, dirZ = localDirectionToWorld(v.rootNode, 0, 0, 1)
		local ry = MathUtil.getYRotationFromDirection and MathUtil.getYRotationFromDirection(dirX, dirZ) or 0
		return x or 0, y or 0, z or 0, ry or 0
	end
	local x, y, z = g_localPlayer:getPosition()
	local ry = g_localPlayer.getMovementYaw and g_localPlayer:getMovementYaw() or 0
	return x or 0, y or 0, z or 0, ry or 0
end

function IAMapInitDialogGUI:savePlaceType(ptype, characterNumber, withVehicleOverride, withAttachmentOverride)
	local x, y, z, rotation = self:getCurrentPosition()
	local withVehicle, withAttachment
	local sizeType = nil
	if withVehicleOverride ~= nil then
		withVehicle = withVehicleOverride == true
		withAttachment = withAttachmentOverride == true
		sizeType = self:getSelectedPlaceSizeType()
	else
		withVehicle, withAttachment = IAMapInitDialogGUI.getWithVehicleAndAttachmentFromPlayer()
	end
	local entry = {
		x = x,
		y = y,
		z = z,
		rotation = rotation,
		type = ptype,
		withVehicle = withVehicle,
		withAttachment = withAttachment,
		sizeType = sizeType
	}
	if characterNumber ~= nil then
		entry.characterNumber = characterNumber
	end

	local loader = IANeighbours.placesLoader
	local focused = loader and loader.getFocusedRelativeTarget and loader:getFocusedRelativeTarget()
	if focused and focused.type == "placeable" then
		loader:savePlaceAtFocusedPlaceable(ptype, characterNumber, withVehicle, withAttachment, sizeType)
	elseif focused and focused.type == "node" then
		loader:savePlaceAtFocusedMapNode(ptype, characterNumber, withVehicle, withAttachment, sizeType)
	else
		local selectedPlaceable = loader and loader.getSelectedPlaceable and loader:getSelectedPlaceable()
		if selectedPlaceable ~= nil and selectedPlaceable.rootNode ~= nil and selectedPlaceable.configFileName then
			-- Placeable-relative save when a selected placeable is set on the loader
			local px, py, pz = loader:getPlaceablePosition(selectedPlaceable)
			local placeableRot = loader:getPlaceableRotation(selectedPlaceable)
			if px ~= nil and pz ~= nil then
				local relRotation = (rotation or 0) - (placeableRot or 0)
				while relRotation > math.pi do
					relRotation = relRotation - 2 * math.pi
				end
				while relRotation < -math.pi do
					relRotation = relRotation + 2 * math.pi
				end
				local nextId = (loader.getNextFreeNumericPlaceId and loader:getNextFreeNumericPlaceId()) or ((IANeighbours.places and #IANeighbours.places + 1) or 1)
				local id = (characterNumber ~= nil) and characterNumber or nextId
				local name = (characterNumber ~= nil) and ("Character " .. tostring(characterNumber)) or ("Place " .. tostring(id))
				local place = IAMapPlace.new(
					id, name, ptype,
					x or 0, y or 0, z or 0, rotation or 0,
					withVehicle, withAttachment, sizeType, characterNumber,
					selectedPlaceable.configFileName,
					(x or 0) - px, (y or 0) - (py or 0), (z or 0) - pz,
					relRotation
				)
				if IANeighbours.places == nil then
					IANeighbours.places = {}
				end
				table.insert(IANeighbours.places, place)
				if IANeighbours.xmlHelper then
					IANeighbours.xmlHelper:appendPlaceToPlaceablePlacesFile(place)
				end
			end
		else
			-- No focused target and no selected placeable: add absolute place and save map place file
			if IANeighbours.places == nil then
				IANeighbours.places = {}
			end
			IANeighbours:addPlaceFromMapInitEntry(entry)
			if IANeighbours.xmlHelper and g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
				if IANeighbours.debug then
					print("--- saveMapConfigToFile caller: IAMapInitDialogGUI.savePlaceType (absolute place) mapId=" .. tostring(g_currentMission.missionInfo.mapId))
				end
				IANeighbours.xmlHelper:saveMapConfigToFile(g_currentMission.missionInfo.mapId)
			end
		end
	end

	-- When saving a character_homebase for a specific character, assign the place to that neighbour's assignedHomebasePlaceIds
	if ptype == "character_homebase" and characterNumber ~= nil and IANeighbours.places and #IANeighbours.places > 0 then
		local place = IANeighbours.places[#IANeighbours.places]
		if place and place.id ~= nil and IANeighbours.neighbours then
			for _, n in pairs(IANeighbours.neighbours) do
				if n and not n.isDeleted and iaMapInitIdsEqual(n.id, characterNumber) and n.assignHomebasePlace then
					n:assignHomebasePlace(place)
					break
				end
			end
		end
	end

	-- Draw a debug point at this position every frame with place type, character name, and place kind (Vehicle for new places from dialog)
	local label = ptype
	if characterNumber ~= nil then
		label = ptype .. " (" .. tostring(characterNumber) .. ")"
		local charName = IAMapInitDialogGUI.getCharacterNameByNumber(characterNumber)
		if charName ~= nil and charName ~= "" then
			label = label .. " - " .. charName
		end
	end
	label = label .. " - " .. IAMapInitDialogGUI.getPlaceKindDebugSuffixBySizeType(entry.sizeType, entry.withVehicle, entry.withAttachment)
	local newPlace = IANeighbours.places and IANeighbours.places[#IANeighbours.places]
	IANeighbours:addPlaceDebugPointsAt(x, y, z, rotation, label, entry.withVehicle, entry.withAttachment, nil, nil, newPlace, entry.sizeType)
	local l10nKey = "gui_mapinit_place_type_" .. tostring(ptype)
	local typeLabel = (g_i18n and g_i18n.getText) and g_i18n:getText(l10nKey) or nil
	if typeLabel == nil or typeLabel == "" or typeLabel == l10nKey then
		typeLabel = tostring(ptype)
	end
	if characterNumber ~= nil then
		local cn = IAMapInitDialogGUI.getCharacterNameByNumber(characterNumber)
		if cn ~= nil and cn ~= "" then
			typeLabel = typeLabel .. " (" .. cn .. ")"
		else
			typeLabel = typeLabel .. " (#" .. tostring(characterNumber) .. ")"
		end
	end
	local msgFmt = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_place_saved") or nil
	if msgFmt == nil or msgFmt == "" or msgFmt == "gui_mapinit_notify_place_saved" then
		msgFmt = "Place saved: %s"
	end
	g_gui:closeDialog(self.dialog)
	IAMapInitDialogGUI.showMapInitOkNotification(string.format(msgFmt, typeLabel))
end

--- Single handler for all place-type buttons; triggerElement.placeType (and optional characterNumber) set in onOpen.
function IAMapInitDialogGUI:onClickPlaceType(triggerElement)
	local source = triggerElement
	if source == nil then
		local scroll = self:getDescendantById("placeButtonsScrollingLayout")
		source = scroll and scroll.focusElement
	end
	local ptype = source and source.placeType
	if ptype then
		local charNum = source.characterNumber
		local withVehicle, withAttachment = self:getSelectedPlaceSizeFlags()
		self:savePlaceType(ptype, charNum, withVehicle, withAttachment)
	end
end

function IAMapInitDialogGUI:onClickPlaceSize()
	local current = self.selectedPlaceSizeIndex or 1
	current = current + 1
	if current > #IAMapInitDialogGUI.PLACE_SIZE_OPTIONS then
		current = 1
	end
	self.selectedPlaceSizeIndex = current
	self:updatePlaceSizeButtonText()
end

--- Highlight the tab buttons according to the active tab (green = active).
function IAMapInitDialogGUI:updateTabButtonHighlight()
	local storyBtn = self:getDescendantById("tabStoryButton")
	local settingsBtn = self:getDescendantById("tabSettingsButton")
	local isStory = (self.activeTab or "story") == "story"
	IAMapInitDialogGUI.setPlaceButtonColor(storyBtn, isStory)
	IAMapInitDialogGUI.setPlaceButtonColor(settingsBtn, not isStory)
end

--- Switch between the "story" (empty for now) and "settings" tabs.
function IAMapInitDialogGUI:setActiveTab(tabName)
	self.activeTab = tabName or "story"
	local showSettings = self.activeTab == "settings"
	local storyContainer = self:getDescendantById("storyContainer")
	local settingsContainer = self:getDescendantById("settingsContainer")
	if storyContainer then
		storyContainer.ignoreLayout = showSettings
		if storyContainer.setVisible then
			storyContainer:setVisible(not showSettings)
		end
	end
	if settingsContainer then
		settingsContainer.ignoreLayout = not showSettings
		if settingsContainer.setVisible then
			settingsContainer:setVisible(showSettings)
		end
	end
	local contentLayout = self:getDescendantById("contentLayoutElement")
	if contentLayout and contentLayout.invalidateLayout then
		contentLayout:invalidateLayout()
	end
	self:updateTabButtonHighlight()
	if not showSettings then
		self:updateStoryCharacterDetailsUI()
	end
end

function IAMapInitDialogGUI:onClickTabStory()
	self:setActiveTab("story")
end

function IAMapInitDialogGUI:onClickTabSettings()
	self:setActiveTab("settings")
end

function IAMapInitDialogGUI:onClickCancel()
	g_gui:closeDialog(self.dialog)
end

--- Move the vehicle the player is in six ticks to its local left (driver's left). Uses VEHICLE_NUDGE_TICK_METERS per tick.
function IAMapInitDialogGUI:onClickNudgeVehicleLeft()
	local msgNeedVehicle = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_nudge_vehicle_no_vehicle") or nil
	if msgNeedVehicle == nil or msgNeedVehicle == "" or msgNeedVehicle == "gui_mapinit_notify_nudge_vehicle_no_vehicle" then
		msgNeedVehicle = "You must be in a vehicle."
	end
	if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
		IAMapInitDialogGUI.showMapInitOkNotification(msgNeedVehicle)
		return
	end
	local vehicle = g_localPlayer:getCurrentVehicle()
	if vehicle == nil or vehicle.isDeleted then
		IAMapInitDialogGUI.showMapInitOkNotification(msgNeedVehicle)
		return
	end
	local root = vehicle.rootVehicle or vehicle
	if root.getIsAIActive and root:getIsAIActive() then
		local msgAi = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_nudge_vehicle_ai") or nil
		if msgAi == nil or msgAi == "" or msgAi == "gui_mapinit_notify_nudge_vehicle_ai" then
			msgAi = "Cannot nudge while vehicle AI is active."
		end
		IAMapInitDialogGUI.showMapInitOkNotification(msgAi)
		return
	end
	if root.rootNode == nil or not entityExists(root.rootNode) then
		IAMapInitDialogGUI.showMapInitOkNotification(msgNeedVehicle)
		return
	end
	if g_terrainNode == nil then
		return
	end

	local x, y, z = getWorldTranslation(root.rootNode)
	local forwardX, forwardY, forwardZ = localDirectionToWorld(root.rootNode, 0, 0, 1)
	local rightX, rightY, rightZ = MathUtil.crossProduct(0, 1, 0, forwardX, forwardY, forwardZ)
	local lenH = math.sqrt(rightX * rightX + rightZ * rightZ)
	if lenH < 1e-5 then
		return
	end
	rightX, rightZ = rightX / lenH, rightZ / lenH
	local ticks = IAMapInitDialogGUI.VEHICLE_NUDGE_TICKS_LEFT or 5
	local step = IAMapInitDialogGUI.VEHICLE_NUDGE_TICK_METERS or 1
	local dist = ticks * step
	-- Same convention as NPC beside vehicle: negative along right = left.
	local newX = x - rightX * dist
	local newZ = z - rightZ * dist
	local dirX, _, dirZ = localDirectionToWorld(root.rootNode, 0, 0, 1)
	local rotationY = (MathUtil.getYRotationFromDirection and MathUtil.getYRotationFromDirection(dirX, dirZ)) or 0

	local ok, err = pcall(function()
		root:removeFromPhysics()
		if root.setWorldPosition ~= nil then
			root:setRelativePosition(newX, 0.5, newZ, rotationY, true)
		else
			local groundY = getTerrainHeightAtWorldPos(g_terrainNode, newX, 0, newZ) + 0.2
			setTranslation(root.rootNode, newX, groundY, newZ)
			setRotation(root.rootNode, 0, rotationY, 0)
		end
		root:addToPhysics()
	end)
	if not ok then
		local msgFail = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_nudge_vehicle_failed") or nil
		if msgFail == nil or msgFail == "" or msgFail == "gui_mapinit_notify_nudge_vehicle_failed" then
			msgFail = "Could not move vehicle: " .. tostring(err)
		else
			msgFail = string.format(msgFail, tostring(err))
		end
		IAMapInitDialogGUI.showMapInitOkNotification(msgFail)
		pcall(function()
			root:addToPhysics()
		end)
	end
end

--- Sync the show/hide place-markers toggle label with IANeighbours.mapInitPlaceMarkersVisible.
function IAMapInitDialogGUI:updateTogglePlaceMarkersButtonText()
	local btn = self:getDescendantById("togglePlaceMarkersButton")
	if btn == nil or btn.setText == nil then
		return
	end
	local visible = IANeighbours and IANeighbours.mapInitPlaceMarkersVisible == true
	local key = visible and "gui_mapinit_hide_place_markers" or "gui_mapinit_show_place_markers"
	local text = (g_i18n and g_i18n.getText) and g_i18n:getText(key) or nil
	if text == nil or text == "" or text == key then
		text = visible and "Hide place markers" or "Show place markers"
	end
	btn:setText(text)
end

function IAMapInitDialogGUI:onClickTogglePlaceDebugMarkers()
	if IANeighbours == nil then
		return
	end
	if IANeighbours.mapInitPlaceMarkersVisible == true then
		IANeighbours:clearAllDebugPoints()
		IANeighbours.mapInitPlaceMarkersVisible = false
	else
		IANeighbours:rebuildMapInitDebugPoints()
		IANeighbours.mapInitPlaceMarkersVisible = true
	end
	self:updateTogglePlaceMarkersButtonText()
end

function IAMapInitDialogGUI:onClickRemoveNearestPlace()
	local removed = IANeighbours:removeNearestPlace() == true
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	local key = removed and "gui_mapinit_notify_remove_nearest_ok" or "gui_mapinit_notify_remove_nearest_none"
	local msg = (g_i18n and g_i18n.getText) and g_i18n:getText(key) or ""
	if msg == "" or msg == key then
		msg = removed and "Nearest place removed." or "No place found to remove."
	end
	IAMapInitDialogGUI.showMapInitOkNotification(msg)
end

--- Remove the nearest map object whose node name contains "gate" (delete + persist in map config).
function IAMapInitDialogGUI:onClickHideNearestGate()
	local removed, name = false, nil
	if IANeighbours ~= nil and IANeighbours.hideNearestGateObject ~= nil then
		removed, name = IANeighbours:hideNearestGateObject()
	end
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	local key = removed and "gui_mapinit_notify_hide_gate_ok" or "gui_mapinit_notify_hide_gate_none"
	local msg = (g_i18n and g_i18n.getText) and g_i18n:getText(key) or ""
	if msg == "" or msg == key then
		msg = removed and "Nearest gate removed: %s" or "No gate object found nearby."
	end
	if removed and string.find(msg, "%%s") ~= nil then
		local label = (name ~= nil and tostring(name) ~= "") and tostring(name) or "?"
		msg = string.format(msg, label)
	end
	IAMapInitDialogGUI.showMapInitOkNotification(msg)
end

function IAMapInitDialogGUI:onClickEndInitPhase()
	IANeighbours:endInitPhase()
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	local msg = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_end_init") or ""
	if msg == "" or msg == "gui_mapinit_notify_end_init" then
		msg = "Init phase ended."
	end
	IAMapInitDialogGUI.showMapInitOkNotification(msg)
end

function IAMapInitDialogGUI:onClickRemoveMod()
	-- Close dialogs first (avoids UI accessing deleted objects)
	if g_gui and g_gui.currentDialog then
		pcall(function() g_gui:closeDialog(g_gui.currentDialog) end)
	end
	if IANeighbours ~= nil and IANeighbours.requestRemoveMod ~= nil then
		IANeighbours:requestRemoveMod()
	end
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	local msg = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_remove_mod") or ""
	if msg == "" or msg == "gui_mapinit_notify_remove_mod" then
		msg = "Fields of Stories mod data was cleared. Save the game."
	end
	IAMapInitDialogGUI.showMapInitOkNotification(msg)
end

--- Reset selected character to default scenario definition (map homebase/workplace reapplied from map config).
function IAMapInitDialogGUI:onClickResetCharacter()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local idx = tonumber(self.selectedCharacterIndex) or 1
	local n = list[idx]
	if n == nil or n.id == nil then
		return
	end
	local nid = n.id
	local charName = iaSafeText(n.name)
	if charName == "-" then
		charName = tostring(nid)
	end
	local xmlHelper = IANeighbours and IANeighbours.xmlHelper
	if xmlHelper == nil or xmlHelper.reloadSingleCharacter == nil or IANeighbours.deleteNeighbour == nil then
		return
	end
	IANeighbours:deleteNeighbour(n)
	local ok = false
	pcall(function()
		ok = xmlHelper:reloadSingleCharacter(nid) == true
	end)
	if not ok and IANeighbours.debug then
		print("--- IAMapInitDialogGUI:onClickResetCharacter() - reload failed for neighbour id "..tostring(nid))
	end
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	if ok then
		local msgFmt = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_reset_character") or nil
		if msgFmt == nil or msgFmt == "" or msgFmt == "gui_mapinit_notify_reset_character" then
			msgFmt = "Character %s was reset."
		end
		IAMapInitDialogGUI.showMapInitOkNotification(string.format(msgFmt, charName))
	end
end

--- Remove selected character from the mod (no scenario reload); outbound on next career save; closes dialog.
function IAMapInitDialogGUI:onClickDeleteCharacter()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local idx = tonumber(self.selectedCharacterIndex) or 1
	local n = list[idx]
	if n == nil or n.id == nil then
		return
	end
	if IANeighbours == nil or IANeighbours.deleteNeighbour == nil then
		return
	end
	local charName = iaSafeText(n.name)
	if charName == "-" then
		charName = tostring(n.id)
	end
	IANeighbours:deleteNeighbour(n)
	local msgFmt = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_delete_character") or nil
	if msgFmt == nil or msgFmt == "" or msgFmt == "gui_mapinit_notify_delete_character" then
		msgFmt = "%s was removed from the mod."
	end
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	IAMapInitDialogGUI.showMapInitOkNotification(string.format(msgFmt, charName))
end

--- Assign the nearest character_homebase place (2D distance from player) to the selected neighbour.
--- Removes that place id from other neighbours first so it is exclusive. Persists via assignHomebasePlace / save helpers.
function IAMapInitDialogGUI:onClickAddNearestHomebase()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local idx = tonumber(self.selectedCharacterIndex) or 1
	local n = list[idx]
	if n == nil or n.id == nil or n.assignHomebasePlace == nil then
		return
	end
	local places = IANeighbours and IANeighbours.places
	if places == nil or #places == 0 then
		return
	end
	local px, _, pz = self:getCurrentPosition()
	local best = nil
	local bestD2 = nil
	for _, place in ipairs(places) do
		if place and place.id ~= nil and place.x ~= nil and place.z ~= nil then
			local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			if st == "character_homebase" then
				local dx = px - place.x
				local dz = pz - place.z
				local d2 = dx * dx + dz * dz
				if bestD2 == nil or d2 < bestD2 then
					bestD2 = d2
					best = place
				end
			end
		end
	end
	if best == nil then
		return
	end

	local removedOthers = false
	if IANeighbours.neighbours then
		for _, other in pairs(IANeighbours.neighbours) do
			if other and not other.isDeleted and other.id ~= nil and not iaMapInitIdsEqual(other.id, n.id) and other.assignedHomebasePlaceIds then
				local newIds = {}
				for _, pid in ipairs(other.assignedHomebasePlaceIds) do
					if iaMapInitIdsEqual(pid, best.id) then
						removedOthers = true
					else
						newIds[#newIds + 1] = pid
					end
				end
				other.assignedHomebasePlaceIds = newIds
			end
		end
	end

	local already = false
	if n.assignedHomebasePlaceIds then
		for _, pid in ipairs(n.assignedHomebasePlaceIds) do
			if iaMapInitIdsEqual(pid, best.id) then
				already = true
				break
			end
		end
	end

	if not already then
		n:assignHomebasePlace(best)
	elseif removedOthers then
		local xh = IANeighbours and IANeighbours.xmlHelper
		if xh ~= nil and xh.saveMapConfigToFile and g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
			if IANeighbours.debug then
				print("--- saveMapConfigToFile caller: IAMapInitDialogGUI.onClickAddNearestHomebase (persist after reassignment) mapId=" .. tostring(g_currentMission.missionInfo.mapId))
			end
			pcall(function() xh:saveMapConfigToFile(g_currentMission.missionInfo.mapId) end)
		end
	end

	local charName = iaSafeText(n.name)
	if charName == "-" then
		charName = tostring(n.id)
	end
	local msgFmt = g_i18n and g_i18n.getText and g_i18n:getText("gui_mapinit_add_nearest_homebase_info") or nil
	if msgFmt == nil or msgFmt == "" then
		msgFmt = "Der nächste Ort wurde dem Charakter %s zugewiesen"
	end
	local msg = string.format(msgFmt, charName)
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	IAMapInitDialogGUI.showMapInitOkNotification(msg)
end

--- Remove homebase place assignments for selected character (does not delete places; just unassigns them).
function IAMapInitDialogGUI:onClickRemoveHomeplaces()
	local list = IAMapInitDialogGUI.getNeighboursInCharacterOrder()
	local idx = tonumber(self.selectedCharacterIndex) or 1
	local n = list[idx]
	if n == nil or n.id == nil then
		return
	end
	local charName = iaSafeText(n.name)
	if charName == "-" then
		charName = tostring(n.id)
	end

	-- Clear assignments (homebase + paired shed slots stored on assignedHomebasePlaceIds)
	n.assignedHomebasePlaceIds = {}

	-- Persist map config (so map-based assignment is cleared too); outbound on next career save
	local xmlHelper = IANeighbours and IANeighbours.xmlHelper
	if xmlHelper ~= nil and xmlHelper.saveMapConfigToFile ~= nil and g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.mapId ~= nil then
		if IANeighbours.debug then
			print("--- saveMapConfigToFile caller: IAMapInitDialogGUI.onClickRemoveHomeplaces mapId=" .. tostring(g_currentMission.missionInfo.mapId))
		end
		pcall(function() xmlHelper:saveMapConfigToFile(g_currentMission.missionInfo.mapId) end)
	end

	local msgFmt = (g_i18n and g_i18n.getText) and g_i18n:getText("gui_mapinit_notify_remove_homeplaces") or nil
	if msgFmt == nil or msgFmt == "" or msgFmt == "gui_mapinit_notify_remove_homeplaces" then
		msgFmt = "Home places were removed for %s."
	end
	if self.dialog ~= nil and g_gui ~= nil and g_gui.closeDialog then
		g_gui:closeDialog(self.dialog)
	end
	IAMapInitDialogGUI.showMapInitOkNotification(string.format(msgFmt, charName))
end

function IAMapInitDialogGUI:onEscPressed()
	self:onClickCancel()
end
