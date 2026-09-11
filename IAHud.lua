-- IAHud.lua
-- Fields of Stories in-game HUD overlay.
-- Hooks into GameInfoDisplay.draw to render screen-space text when the construction
-- menu is open and a FoS tool placeable is selected.

IAHud = {}

--- Position in normalized screen coordinates (0 = left/top, 1 = right/bottom).
IAHud.posX = 0.86
IAHud.posY = 0.15

--- Set via iaHudForceShow console command to bypass the construction-menu gate and always draw.
IAHud.forceShow = false
--- When true, prints a line to the log every frame the draw hook runs.
IAHud.debugDraw = false
--- Cached overall setup data (recomputed only when place count changes).
IAHud._overallCachePlaceCount = -1
IAHud._overallCacheTypes = nil
IAHud._overallCacheNeighbours = nil

--- Colorblind-safe status colors: blue = requirement met / complete, amber = below requirement.
-- Chosen instead of green/red so deuteranopia / protanopia players can still tell the states apart.
IAHud.COLOR_MET = { 0.10, 0.65, 1.00 }
IAHud.COLOR_BELOW = { 1.00, 0.60, 0.05 }
--- Header / note color (light blue, distinct from both status colors).
IAHud.COLOR_HEADER = { 0.70, 0.88, 1.00 }
--- Background box opacity for the setup overlay (reduced so the scene stays readable).
IAHud.BACKGROUND_ALPHA = 0.75

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Resolve the current size entry for the selected tool (mappingDef.sizes[currentIndex]).
-- Mirrors _getMappedSize / _getCurrentSizeIndex in IAPlaceablePlacementDetector.
local function _resolveMappedSize(mappingDef)
	if mappingDef == nil or mappingDef.sizes == nil then
		return nil, nil
	end
	local idx = 1
	if IANeighbours ~= nil and IANeighbours.placeableToolSizeIndex ~= nil then
		idx = IANeighbours.placeableToolSizeIndex
	end
	local mapped = mappingDef.sizes[idx]
	if mapped == nil then
		idx = mappingDef.defaultSize or 1
		mapped = mappingDef.sizes[idx]
	end
	return mapped, idx
end

--- Count places in IANeighbours.places whose semantic type matches ptype.
local function _countPlacesByType(ptype)
	if IANeighbours == nil or IANeighbours.places == nil then
		return 0
	end
	local n = 0
	for _, place in ipairs(IANeighbours.places) do
		if place ~= nil then
			local st = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
			if st == ptype then
				n = n + 1
			end
		end
	end
	return n
end

--- Count homebase places whose sizeType matches the given value.
local function _countHomebasePlacesBySize(sizeType)
	if IANeighbours == nil or IANeighbours.places == nil then
		return 0
	end
	local n = 0
	for _, place in ipairs(IANeighbours.places) do
		if place ~= nil then
			local st = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
			if st == "character_homebase" and place.sizeType == sizeType then
				n = n + 1
			end
		end
	end
	return n
end

--- Resolve the target neighbour for a homebase tool (by mappingDef.characterNumber).
local function _resolveHomebaseNeighbour(mappingDef)
	if mappingDef == nil or mappingDef.characterNumber == nil or IANeighbours == nil or IANeighbours.neighbours == nil then
		return nil
	end
	local cn = tonumber(mappingDef.characterNumber)
	if cn == nil then return nil end
	for _, n in pairs(IANeighbours.neighbours) do
		if n ~= nil and not n.isDeleted and n.id == cn then
			return n
		end
	end
	return nil
end

--- Map a place sizeType string to the key used in getActualHomebasePlaces/getRequiredHomebasePlaces.
local function _sizeTypeToCountKey(sizeType)
	local t = tostring(sizeType or "")
	if t == "character" then return "character"
	elseif t == "vehicle" then return "vehicle"
	elseif t == "vehicle_attachment" then return "vehicle_attachment"
	elseif t == "oversize_vehicle" then return "oversize_vehicle"
	elseif t == "large_area" then return "large_area"
	elseif t == "silo" then return "silo"
	end
	return nil
end

--- Expected minimum count for a place type (delegates to IAMapInitDialogGUI).
local function _expectedForType(ptype)
	if IAMapInitDialogGUI ~= nil and IAMapInitDialogGUI.getPlaceTypeMin ~= nil then
		return IAMapInitDialogGUI.getPlaceTypeMin(ptype)
	end
	return 0
end

--- Render one line of text with an optional colored count suffix.
-- actual/expected: if both provided, appends " (actual/expected)" in blue (met) or amber (below).
local function _renderLine(self, x, y, fontSize, label, actual, expected)
	setTextBold(true)
	renderText(x, y, fontSize, label)
	setTextBold(false)

	if actual == nil or expected == nil then
		return
	end

	local met = actual >= expected
	local r, g, b = IAHud.COLOR_BELOW[1], IAHud.COLOR_BELOW[2], IAHud.COLOR_BELOW[3]
	if met then
		r, g, b = IAHud.COLOR_MET[1], IAHud.COLOR_MET[2], IAHud.COLOR_MET[3]
	end

	local suffix = string.format(" (%d/%d)", actual, expected)
	local labelW = getTextWidth(fontSize, label)
	if labelW == nil then
		labelW = 0
	end
	setTextColor(r, g, b, 1)
	renderText(x + labelW, y, fontSize, suffix)
	setTextColor(1, 1, 1, 1)
end

--- Human-readable label for a sizeType value.
local function _sizeLabel(sizeType)
	local t = tostring(sizeType or "")
	if t == "character" then return "character"
	elseif t == "vehicle" then return "vehicle"
	elseif t == "vehicle_attachment" then return "vehicle + attachment"
	elseif t == "oversize_vehicle" then return "oversize"
	elseif t == "large_area" then return "large area"
	elseif t == "silo" then return "silo"
	else return t
	end
end

--- Total number of initialized neighbours (characters in the current scenario).
local function _characterCount()
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return 0
	end
	local n = 0
	for _ in pairs(IANeighbours.neighbours) do
		n = n + 1
	end
	return n
end

--- Sorted place type keys with expected > 0.
local function _overallPlaceTypes()
	local out = {}
	if IAMapInitDialogGUI == nil or IAMapInitDialogGUI.PLACE_TYPE_MIN == nil then
		return out
	end
	for ptype, expected in pairs(IAMapInitDialogGUI.PLACE_TYPE_MIN) do
		if expected > 0 then
			out[#out + 1] = ptype
		end
	end
	table.sort(out)
	return out
end

--- All initialized neighbours sorted by id.
local function _overallNeighbours()
	local out = {}
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return out
	end
	for _, n in pairs(IANeighbours.neighbours) do
		if n ~= nil and n.initialized and not n.isDeleted and n.name ~= nil then
			out[#out + 1] = n
		end
	end
	table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
	return out
end

--- Render a bold section header.
local function _renderHeader(self, x, y, fontSize, text)
	setTextBold(true)
	setTextColor(IAHud.COLOR_HEADER[1], IAHud.COLOR_HEADER[2], IAHud.COLOR_HEADER[3], 1)
	renderText(x, y, fontSize, text)
	setTextColor(1, 1, 1, 1)
	setTextBold(false)
end

--- Render a compact status line: "  label (actual/expected)" colored blue/amber.
local function _renderStatusLine(self, x, y, fontSize, label, actual, expected)
	local met = actual >= expected
	local r, g, b = IAHud.COLOR_BELOW[1], IAHud.COLOR_BELOW[2], IAHud.COLOR_BELOW[3]
	if met then
		r, g, b = IAHud.COLOR_MET[1], IAHud.COLOR_MET[2], IAHud.COLOR_MET[3]
	end

	setTextBold(false)
	setTextColor(r, g, b, 1)
	renderText(x, y, fontSize, string.format("  %s (%d/%d)", label, actual, expected))
	setTextColor(1, 1, 1, 1)
end

--- Compact status word only (no numbers): "Required" (amber) or "Complete" (blue).
-- If `met` is provided (boolean), uses it directly; otherwise checks actual >= expected.
local function _renderStatusWord(self, x, y, fontSize, label, actual, expected, met)
	local complete
	if met ~= nil then
		complete = met
	else
		complete = actual >= expected
	end
	local r, g, b = IAHud.COLOR_BELOW[1], IAHud.COLOR_BELOW[2], IAHud.COLOR_BELOW[3]
	local word = "Required"
	if complete then
		r, g, b = IAHud.COLOR_MET[1], IAHud.COLOR_MET[2], IAHud.COLOR_MET[3]
		word = "Complete"
	end

	setTextBold(true)
	renderText(x, y, fontSize, label)
	setTextBold(false)

	local lw = getTextWidth(fontSize, label) or 0
	setTextColor(r, g, b, 1)
	renderText(x + lw + self:scalePixelToScreenWidth(8), y, fontSize, word)
	setTextColor(1, 1, 1, 1)
end

--- Sorted array of size indices defined in mappingDef.sizes.
local function _sortedSizeIndices(mappingDef)
	local out = {}
	if mappingDef == nil or mappingDef.sizes == nil then
		return out
	end
	for i in pairs(mappingDef.sizes) do
		out[#out + 1] = i
	end
	table.sort(out)
	return out
end

--- Friendly display name for a place type key.
local function _friendlyPlaceTypeName(ptype)
	local t = tostring(ptype or "")
	if t == "shop" then return "Shop"
	elseif t == "gas_station" then return "Gas Station"
	elseif t == "roadside" then return "Roadside"
	elseif t == "dirt_road" then return "Dirt Road"
	elseif t == "sell_point" then return "Sell Point"
	elseif t == "character_homebase" then return "Homebases"
	elseif t == "public_place" then return "Public Place"
	elseif t == "player_farm" then return "Player Farm"
	elseif t == "public_relax_place" then return "Public Relax"
	elseif t == "private_relax_place" then return "Private Relax"
	elseif t == "church" then return "Church"
	elseif t == "public_infrastructure" then return "Infrastructure"
	elseif t == "roadside_trees" then return "Roadside Trees"
	elseif t == "industry" then return "Industry"
	elseif t == "workshop" then return "Workshop"
	elseif t == "shed" then return "Shed"
	elseif t == "other" then return "Other"
	else return t
	end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

--- Called once after the vanilla HUD components are created (overwritten hook).
function IAHud:hudCreateDisplayComponents(superFunc, uiScale)
	superFunc(self, uiScale)
	IAprintDebug("IAHud:hudCreateDisplayComponents", "HUD components created")
end

--- Per-frame draw hook on GameInfoDisplay. Renders a screen-space overlay when the
--- construction menu is open and a Fields of Stories tool placeable is selected.
function IAHud:draw(superFunc)
	superFunc(self)

	local mappingDef = nil
	local active = IAHud.forceShow
	if not active and IAPlaceablePlacementDetector ~= nil then
		mappingDef, _ = IAPlaceablePlacementDetector:getSelectedToolInfo()
		if mappingDef ~= nil and mappingDef.placeType ~= "remove" then
			active = true
		end
	end

	if IAHud.debugDraw then
		print(string.format("--- IAHud:draw() active=%s forceShow=%s", tostring(active), tostring(IAHud.forceShow)))
	end

	if not active then
		return
	end

	-- Resolve selected tool info
	if mappingDef == nil and IAPlaceablePlacementDetector ~= nil then
		mappingDef, _ = IAPlaceablePlacementDetector:getSelectedToolInfo()
	end
	local _, curIdx = _resolveMappedSize(mappingDef)
	local ptype = mappingDef ~= nil and mappingDef.placeType or "?"
	local isHomebase = (ptype == "character_homebase")
	local sizeIndices = _sortedSizeIndices(mappingDef)

	-- Resolve homebase neighbour and its per-size counts
	local hbNeighbour = nil
	local hbActualCounts = nil
	local hbRequiredCounts = nil
	if isHomebase then
		hbNeighbour = _resolveHomebaseNeighbour(mappingDef)
		if hbNeighbour ~= nil then
			hbActualCounts = hbNeighbour:getActualHomebasePlaces()
			hbRequiredCounts = hbNeighbour:getRequiredHomebasePlaces()
		end
	end

	-- Type counts: for homebases, use per-neighbour totals; otherwise global
	local typeActual, typeExpected
	if isHomebase and hbActualCounts ~= nil and hbRequiredCounts ~= nil then
		typeActual = hbActualCounts.total
		typeExpected = hbRequiredCounts.total
	else
		typeActual = _countPlacesByType(ptype)
		typeExpected = _expectedForType(ptype)
	end

	-- Collect overall setup data (only when place count changes)
	local placeCount = IANeighbours and IANeighbours.places and #IANeighbours.places or 0
	if IAHud._overallCachePlaceCount ~= placeCount then
		IAHud._overallCachePlaceCount = placeCount
		IAHud._overallCacheTypes = {}
		IAHud._overallCacheNeighbours = {}

		local otypes = _overallPlaceTypes()
		for _, otype in ipairs(otypes) do
			IAHud._overallCacheTypes[#IAHud._overallCacheTypes + 1] = {
				label = _friendlyPlaceTypeName(otype),
				act = _countPlacesByType(otype),
				exp = _expectedForType(otype),
			}
		end

		local oneighbours = _overallNeighbours()
		for _, n in ipairs(oneighbours) do
			local act = n:getActualHomebasePlaces()
			local req = n:getRequiredHomebasePlaces()
			local actTotal = act and act.total or 0
			local reqTotal = req and req.total or 0
			-- Complete only when every per-size requirement is met
			local allMet = true
			if act and req then
				for k, rv in pairs(req) do
					if k ~= "total" and rv > 0 and (act[k] or 0) < rv then
						allMet = false
						break
					end
				end
			else
				allMet = false
			end
			IAHud._overallCacheNeighbours[#IAHud._overallCacheNeighbours + 1] = {
				name = n.name,
				act = actTotal,
				exp = reqTotal,
				met = allMet,
			}
		end
	end

	local overallTypeLines = #(IAHud._overallCacheTypes or {})
	local overallCharLines = #(IAHud._overallCacheNeighbours or {})
	local overallLines = (overallTypeLines > 0 or overallCharLines > 0) and (1 + overallTypeLines + overallCharLines) or 0

	-- Layout
	local posX = IAHud.posX
	local posY = IAHud.posY
	local lineH = self:scalePixelToScreenHeight(20)
	local lineHSm = self:scalePixelToScreenHeight(17)
	local fontSize = self:scalePixelToScreenHeight(13)
	local fontSizeHdr = self:scalePixelToScreenHeight(14)
	local fontSizeSm = self:scalePixelToScreenHeight(12)
	local paddingX = self:scalePixelToScreenWidth(10)
	local indentX = self:scalePixelToScreenWidth(16)
	local topPad = self:scalePixelToScreenHeight(10)

	local numSizeLines = #sizeIndices
	local currentLines = 3 + numSizeLines  -- header + sizes + type label

	local bgW = self:scalePixelToScreenWidth(310)
	local bgH = lineH * currentLines + lineH + topPad + self:scalePixelToScreenHeight(14)
	if overallLines > 0 then
		bgH = bgH + lineHSm * overallLines
	end

	-- Background box
	drawFilledRect(posX, posY, bgW, bgH, 0, 0, 0, IAHud.BACKGROUND_ALPHA)

	setTextAlignment(RenderText.ALIGN_LEFT)
	local curY = posY + topPad - self:scalePixelToScreenHeight(2)


    
	setTextColor(IAHud.COLOR_HEADER[1], IAHud.COLOR_HEADER[2], IAHud.COLOR_HEADER[3], 1)
	_renderLine(self, posX + paddingX, curY, fontSize, "Note Keybinds for Bulk-Remove and Size-Switch")
	setTextColor(1, 1, 1, 1)
    
	curY = curY + lineH
	-- Size lines: silo → character
	for i = #sizeIndices, 1, -1 do
		local si = sizeIndices[i]
		local sz = mappingDef.sizes[si]
		if sz ~= nil then
			local prefix = (si == curIdx) and "--> " or "    "
			local label = prefix .. _sizeLabel(sz.sizeType)
			local szActual, szExpected = nil, nil
			if isHomebase and hbActualCounts ~= nil and hbRequiredCounts ~= nil then
				local key = _sizeTypeToCountKey(sz.sizeType)
				if key ~= nil then
					szActual = hbActualCounts[key]
					szExpected = hbRequiredCounts[key]
				end
			end
			_renderLine(self, posX + indentX, curY, fontSize, label, szActual, szExpected)
			curY = curY + lineH
		end
	end
	_renderLine(self, posX + paddingX, curY, fontSize, "Place Size:")
	curY = curY + lineH

	-- Type label
	local typeLabel = mappingDef ~= nil and mappingDef.displayName or tostring(ptype)
	_renderLine(self, posX + paddingX, curY, fontSize, typeLabel, typeActual, typeExpected)

	-- === CURRENT SELECTION ===
	curY = curY + lineH
	_renderHeader(self, posX + paddingX, curY, fontSizeHdr, "Current Selection")


	-- === OVERALL SETUP ===
	if overallLines > 0 then
		curY = curY + lineH + self:scalePixelToScreenHeight(4)


		-- Place types
		for _, row in ipairs(IAHud._overallCacheTypes or {}) do
			_renderStatusWord(self, posX + paddingX, curY, fontSizeSm, row.label, row.act, row.exp)
			curY = curY + lineHSm
		end

		-- Characters
		for _, row in ipairs(IAHud._overallCacheNeighbours or {}) do
			_renderStatusWord(self, posX + paddingX, curY, fontSizeSm, row.name, row.act, row.exp, row.met)
			curY = curY + lineHSm
		end

		_renderHeader(self, posX + paddingX, curY, fontSizeHdr, "Overall Setup")
	end
end

--- Install hooks on the vanilla HUD / GameInfoDisplay system.
--- Safe to call multiple times (Utils.overwrittenFunction is idempotent).
function IAHud.installHooks()
	if IAHud._hooksInstalled then
		return
	end
	if HUD == nil or HUD.createDisplayComponents == nil then
		print("[IAHud] WARNING: HUD not available — hooks not installed")
		return
	end
	if GameInfoDisplay == nil or GameInfoDisplay.draw == nil then
		print("[IAHud] WARNING: GameInfoDisplay not available — hooks not installed")
		return
	end

	HUD.createDisplayComponents = Utils.overwrittenFunction(
		HUD.createDisplayComponents,
		IAHud.hudCreateDisplayComponents
	)

	GameInfoDisplay.draw = Utils.overwrittenFunction(
		GameInfoDisplay.draw,
		IAHud.draw
	)

	IAHud._hooksInstalled = true
	IAprintDebug("IAHud", "hooks installed on HUD / GameInfoDisplay (HUD=" .. tostring(HUD) .. " GameInfoDisplay=" .. tostring(GameInfoDisplay) .. ")")
end
