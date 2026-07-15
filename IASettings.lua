--
-- FS25 - InteractiveNeighbours - Mod Settings
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
--
-- Single-file mod settings: persistence, savegame state, gameplay helpers and
-- the in-game General Settings page UI for one global setting (contract phone
-- calls per in-game day).
--
-- Player setting: modSettings/FS25_FIELDS_OF_STORIES/settings.xml
-- Savegame state: IANeighbours_outbound.xml (daily counter + day key)
--

IASettings = {}

IASettings.SETTINGS_FILE_NAME = "settings.xml"

-- 1-based UI option index → cap; -1 means "unlimited" (no cap).
IASettings.CONTRACT_CALLS_PER_DAY_CAPS = { 0, 1, 2, 3, 4, -1 }
IASettings.CONTRACT_CALLS_PER_DAY_LABELS = {
	"ia_settings_contractCallsPerDay_none",
	"ia_settings_contractCallsPerDay_1",
	"ia_settings_contractCallsPerDay_2",
	"ia_settings_contractCallsPerDay_3",
	"ia_settings_contractCallsPerDay_4",
	"ia_settings_contractCallsPerDay_unlimited",
}
IASettings.CONTRACT_CALLS_PER_DAY_DEFAULT_INDEX = 3  -- "2 per day"

IASettings.MISSION_OFFER_MODE_VALUES = { "classic", "realistic" }
IASettings.MISSION_OFFER_MODE_LABELS = {
	"ia_settings_missionOfferMode_classic",
	"ia_settings_missionOfferMode_realistic",
}
IASettings.MISSION_OFFER_MODE_DEFAULT_INDEX = 2   -- realistic

IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_CAPS = { 1, 2, 3, 4, 5, -1 }
IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_LABELS = {
	"ia_settings_contractMaxFieldsPerNeighbour_1",
	"ia_settings_contractMaxFieldsPerNeighbour_2",
	"ia_settings_contractMaxFieldsPerNeighbour_3",
	"ia_settings_contractMaxFieldsPerNeighbour_4",
	"ia_settings_contractMaxFieldsPerNeighbour_5",
	"ia_settings_contractMaxFieldsPerNeighbour_unlimited",
}
IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_DEFAULT_INDEX = 3  -- "3"

IASettings.FIELDWORK_COMPLETION_THRESHOLD_VALUES = { 60, 65, 70, 75, 80, 85, 90, 95, 100 }
IASettings.FIELDWORK_COMPLETION_THRESHOLD_LABELS = {
	"ia_settings_fieldworkCompletionThreshold_60",
	"ia_settings_fieldworkCompletionThreshold_65",
	"ia_settings_fieldworkCompletionThreshold_70",
	"ia_settings_fieldworkCompletionThreshold_75",
	"ia_settings_fieldworkCompletionThreshold_80",
	"ia_settings_fieldworkCompletionThreshold_85",
	"ia_settings_fieldworkCompletionThreshold_90",
	"ia_settings_fieldworkCompletionThreshold_95",
	"ia_settings_fieldworkCompletionThreshold_100",
}
IASettings.FIELDWORK_COMPLETION_THRESHOLD_DEFAULT_INDEX = 7  -- "90%"

IASettings.contractCallsPerDayIndex = IASettings.CONTRACT_CALLS_PER_DAY_DEFAULT_INDEX
IASettings.missionOfferModeIndex = IASettings.MISSION_OFFER_MODE_DEFAULT_INDEX
IASettings.contractMaxFieldsPerNeighbourIndex = IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_DEFAULT_INDEX
IASettings.fieldworkCompletionThresholdIndex = IASettings.FIELDWORK_COMPLETION_THRESHOLD_DEFAULT_INDEX
IASettings._initialized = false
IASettings._uiRegistered = false

-- In-memory daily counter; resets when the in-game calendar day rolls over.
IASettings._contractCallsDayKey = nil
IASettings._contractCallsDayCount = 0

local function clampIndex(v)
	local n = #IASettings.CONTRACT_CALLS_PER_DAY_CAPS
	v = tonumber(v) or IASettings.CONTRACT_CALLS_PER_DAY_DEFAULT_INDEX
	if v < 1 or v > n then
		v = IASettings.CONTRACT_CALLS_PER_DAY_DEFAULT_INDEX
	end
	return math.floor(v)
end

local function clampModeIndex(v)
	local n = #IASettings.MISSION_OFFER_MODE_VALUES
	v = tonumber(v) or IASettings.MISSION_OFFER_MODE_DEFAULT_INDEX
	if v < 1 or v > n then
		v = IASettings.MISSION_OFFER_MODE_DEFAULT_INDEX
	end
	return math.floor(v)
end

local function clampMaxFieldsIndex(v)
	local n = #IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_CAPS
	v = tonumber(v) or IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_DEFAULT_INDEX
	if v < 1 or v > n then
		v = IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_DEFAULT_INDEX
	end
	return math.floor(v)
end

local function clampFieldworkCompletionThresholdIndex(v)
	local n = #IASettings.FIELDWORK_COMPLETION_THRESHOLD_VALUES
	v = tonumber(v) or IASettings.FIELDWORK_COMPLETION_THRESHOLD_DEFAULT_INDEX
	if v < 1 or v > n then
		v = IASettings.FIELDWORK_COMPLETION_THRESHOLD_DEFAULT_INDEX
	end
	return math.floor(v)
end

local function getCurrentDayKey()
	if g_currentMission == nil or type(getEnvironmentYearMonthDayInPeriod) ~= "function" then
		return nil
	end
	local y, m, d = getEnvironmentYearMonthDayInPeriod()
	if y == nil or m == nil or d == nil then
		return nil
	end
	return tostring(y) .. "_" .. tostring(m) .. "_" .. tostring(d)
end

local function refreshDayCounter()
	local key = getCurrentDayKey()
	if key == nil then
		return
	end
	if IASettings._contractCallsDayKey ~= key then
		IASettings._contractCallsDayKey = key
		IASettings._contractCallsDayCount = 0
	end
end

-- ============================================================================
-- Gameplay API (consumed by IAGameLoopHelper)
-- ============================================================================

--- @return number cap (0..N) or -1 for unlimited.
function IASettings.getContractCallsPerDayCap()
	return IASettings.CONTRACT_CALLS_PER_DAY_CAPS[clampIndex(IASettings.contractCallsPerDayIndex)]
end

function IASettings.isMissionOfferModeClassic()
	return IASettings.MISSION_OFFER_MODE_VALUES[clampModeIndex(IASettings.missionOfferModeIndex)] == "classic"
end

function IASettings.getMissionOfferMode()
	return IASettings.MISSION_OFFER_MODE_VALUES[clampModeIndex(IASettings.missionOfferModeIndex)]
end

--- @return number cap (1..N) or -1 for unlimited.
function IASettings.getContractMaxFieldsPerNeighbour()
	return IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_CAPS[clampMaxFieldsIndex(IASettings.contractMaxFieldsPerNeighbourIndex)]
end

--- @return number fieldwork completion threshold percentage (60-100).
function IASettings.getFieldworkCompletionThreshold()
	return IASettings.FIELDWORK_COMPLETION_THRESHOLD_VALUES[clampFieldworkCompletionThresholdIndex(IASettings.fieldworkCompletionThresholdIndex)]
end

--- @return boolean true if a new contract call ring is still allowed today.
function IASettings.canTriggerContractCallNow()
	refreshDayCounter()
	local cap = IASettings.getContractCallsPerDayCap()
	if cap < 0 then return true end
	if cap == 0 then return false end
	return IASettings._contractCallsDayCount < cap
end

--- Call after a contract call ring was actually shown to the player.
function IASettings.recordContractCallTriggered()
	refreshDayCounter()
	IASettings._contractCallsDayCount = (IASettings._contractCallsDayCount or 0) + 1
end

-- ============================================================================
-- Persistence (modSettings/FS25_FIELDS_OF_STORIES/settings.xml)
-- ============================================================================

local function settingsFilePath()
	local dir = (g_modSettingsDirectory or "") .. "FS25_FIELDS_OF_STORIES/"
	if folderExists ~= nil and not folderExists(dir) and createFolder ~= nil then
		createFolder(dir)
	end
	return dir .. IASettings.SETTINGS_FILE_NAME
end

function IASettings.load()
	local path = settingsFilePath()
	if fileExists ~= nil and fileExists(path) then
		local xml = loadXMLFile("IASettings", path)
		if xml ~= nil and xml ~= 0 then
			local idx = getXMLInt(xml, "IASettings.contractCallsPerDay#index")
			if idx ~= nil then
				IASettings.contractCallsPerDayIndex = clampIndex(idx)
			end
			local modeIdx = getXMLInt(xml, "IASettings.missionOfferMode#index")
			if modeIdx ~= nil then
				IASettings.missionOfferModeIndex = clampModeIndex(modeIdx)
			end
			local maxFieldsIdx = getXMLInt(xml, "IASettings.contractMaxFieldsPerNeighbour#index")
			if maxFieldsIdx ~= nil then
				IASettings.contractMaxFieldsPerNeighbourIndex = clampMaxFieldsIndex(maxFieldsIdx)
			end
			local fieldworkThresholdIdx = getXMLInt(xml, "IASettings.fieldworkCompletionThreshold#index")
			if fieldworkThresholdIdx ~= nil then
				IASettings.fieldworkCompletionThresholdIndex = clampFieldworkCompletionThresholdIndex(fieldworkThresholdIdx)
			end
			delete(xml)
		end
	end
	IASettings._initialized = true
end

function IASettings.save()
	IASettings.contractCallsPerDayIndex = clampIndex(IASettings.contractCallsPerDayIndex)
	local xml = createXMLFile("IASettings_save", settingsFilePath(), "IASettings")
	if xml == nil or xml == 0 then return end
	setXMLInt(xml, "IASettings.contractCallsPerDay#index", IASettings.contractCallsPerDayIndex)
	setXMLInt(xml, "IASettings.contractCallsPerDay#cap", IASettings.getContractCallsPerDayCap())
	IASettings.missionOfferModeIndex = clampModeIndex(IASettings.missionOfferModeIndex)
	setXMLInt(xml, "IASettings.missionOfferMode#index", IASettings.missionOfferModeIndex)
	setXMLString(xml, "IASettings.missionOfferMode#value", IASettings.getMissionOfferMode())
	IASettings.contractMaxFieldsPerNeighbourIndex = clampMaxFieldsIndex(IASettings.contractMaxFieldsPerNeighbourIndex)
	setXMLInt(xml, "IASettings.contractMaxFieldsPerNeighbour#index", IASettings.contractMaxFieldsPerNeighbourIndex)
	setXMLInt(xml, "IASettings.contractMaxFieldsPerNeighbour#cap", IASettings.getContractMaxFieldsPerNeighbour())
	IASettings.fieldworkCompletionThresholdIndex = clampFieldworkCompletionThresholdIndex(IASettings.fieldworkCompletionThresholdIndex)
	setXMLInt(xml, "IASettings.fieldworkCompletionThreshold#index", IASettings.fieldworkCompletionThresholdIndex)
	setXMLInt(xml, "IASettings.fieldworkCompletionThreshold#percent", IASettings.getFieldworkCompletionThreshold())
	saveXMLFile(xml)
	delete(xml)
end

function IASettings.initialize()
	if not IASettings._initialized then
		IASettings.load()
	end
end

-- ============================================================================
-- Savegame runtime state (IANeighbours_outbound.xml)
-- ============================================================================

function IASettings.saveStateToOutboundXML(xmlFile, rootKey)
	if xmlFile == nil or rootKey == nil then
		return
	end
	refreshDayCounter()
	if IASettings._contractCallsDayKey ~= nil then
		local key = rootKey .. ".settings.contractCallsPerDayState"
		setXMLString(xmlFile, key .. "#dayKey", IASettings._contractCallsDayKey)
		setXMLInt(xmlFile, key .. "#count", IASettings._contractCallsDayCount or 0)
	end
end

function IASettings.loadStateFromOutboundXML(xmlFile, rootKey)
	if xmlFile == nil or rootKey == nil then
		return
	end
	local key = rootKey .. ".settings.contractCallsPerDayState"
	local dayKey = getXMLString(xmlFile, key .. "#dayKey", nil)
	local count = getXMLInt(xmlFile, key .. "#count", nil)
	if dayKey ~= nil and count ~= nil then
		IASettings._contractCallsDayKey = dayKey
		IASettings._contractCallsDayCount = math.max(0, count)
	end
	refreshDayCounter()
end

-- ============================================================================
-- In-game settings UI (Pause menu → General settings)
-- ----------------------------------------------------------------------------
-- Clones the base game's existing sectionHeader + multiVolumeVoiceBox templates
-- to add one section "Fields of Stories" with one multi-choice control
-- "Contract phone calls per day". No external helper required.
-- ============================================================================

local function recursivelyAssignFocusIds(element)
	if element == nil then return end
	element.focusId = FocusManager:serveAutoFocusId()
	for _, child in pairs(element.elements) do
		recursivelyAssignFocusIds(child)
	end
end

local function applyContractCallsPerDayToUI()
	if IASettings._uiOption ~= nil then
		IASettings._uiOption:setState(clampIndex(IASettings.contractCallsPerDayIndex))
	end
end

local function applyMissionOfferModeToUI()
	if IASettings._uiMissionModeOption ~= nil then
		IASettings._uiMissionModeOption:setState(clampModeIndex(IASettings.missionOfferModeIndex))
	end
end

local function applyContractMaxFieldsPerNeighbourToUI()
	if IASettings._uiMaxFieldsOption ~= nil then
		IASettings._uiMaxFieldsOption:setState(clampMaxFieldsIndex(IASettings.contractMaxFieldsPerNeighbourIndex))
	end
end

local function applyFieldworkCompletionThresholdToUI()
	if IASettings._uiFieldworkThresholdOption ~= nil then
		IASettings._uiFieldworkThresholdOption:setState(clampFieldworkCompletionThresholdIndex(IASettings.fieldworkCompletionThresholdIndex))
	end
end

--- MultiTextOptionElement callback: invoked with `IASettings` as `self`.\n
function IASettings.onContractCallsPerDayChanged(self, newState)
	IASettings.contractCallsPerDayIndex = clampIndex(newState)
	IASettings.save()
end

function IASettings.onMissionOfferModeChanged(self, newState)
	IASettings.missionOfferModeIndex = clampModeIndex(newState)
	IASettings.save()
end

function IASettings.onContractMaxFieldsPerNeighbourChanged(self, newState)
	IASettings.contractMaxFieldsPerNeighbourIndex = clampMaxFieldsIndex(newState)
	IASettings.save()
end

function IASettings.onFieldworkCompletionThresholdChanged(self, newState)
	IASettings.fieldworkCompletionThresholdIndex = clampFieldworkCompletionThresholdIndex(newState)
	IASettings.save()
end

local function buildSectionHeader(settingsPage)
	for _, elem in ipairs(settingsPage.gameSettingsLayout.elements) do
		if elem.name == "sectionHeader" then
			local section = elem:clone(settingsPage.gameSettingsLayout)
			section:setText(g_i18n:getText("ia_settings_section_title"))
			section.focusId = FocusManager:serveAutoFocusId()
			table.insert(settingsPage.controlsList, section)
			return section
		end
	end
end

local function buildChoiceControl(settingsPage)
	local box = settingsPage.multiVolumeVoiceBox:clone(settingsPage.gameSettingsLayout)
	recursivelyAssignFocusIds(box)
	box.id = "ia_settings_contractCallsPerDayBox"

	local option = box.elements[1]
	option.id = "ia_settings_contractCallsPerDay"
	option.target = IASettings
	option:setCallback("onClickCallback", "onContractCallsPerDayChanged")
	option:setDisabled(false)
	-- Workaround: FocusManager filters callbacks by target.name matching the page name.
	IASettings.name = settingsPage.name

	local texts = {}
	for _, key in ipairs(IASettings.CONTRACT_CALLS_PER_DAY_LABELS) do
		table.insert(texts, g_i18n:getText(key))
	end
	option:setTexts(texts)

	box.elements[2]:setText(g_i18n:getText("ia_settings_contractCallsPerDay_title"))
	option.elements[1]:setText(g_i18n:getText("ia_settings_contractCallsPerDay_info"))

	table.insert(settingsPage.controlsList, box)
	IASettings._uiBox = box
	IASettings._uiOption = option
end

local function buildMaxFieldsControl(settingsPage)
	local box = settingsPage.multiVolumeVoiceBox:clone(settingsPage.gameSettingsLayout)
	recursivelyAssignFocusIds(box)
	box.id = "ia_settings_contractMaxFieldsPerNeighbourBox"

	local option = box.elements[1]
	option.id = "ia_settings_contractMaxFieldsPerNeighbour"
	option.target = IASettings
	option:setCallback("onClickCallback", "onContractMaxFieldsPerNeighbourChanged")
	option:setDisabled(false)

	local texts = {}
	for _, key in ipairs(IASettings.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_LABELS) do
		table.insert(texts, g_i18n:getText(key))
	end
	option:setTexts(texts)

	box.elements[2]:setText(g_i18n:getText("ia_settings_contractMaxFieldsPerNeighbour_title"))
	option.elements[1]:setText(g_i18n:getText("ia_settings_contractMaxFieldsPerNeighbour_info"))

	table.insert(settingsPage.controlsList, box)
	IASettings._uiMaxFieldsBox = box
	IASettings._uiMaxFieldsOption = option
end

--- Idempotent; safe to call from every InGameMenu.onMenuOpened.\n
function IASettings.registerInGameMenuSettings()
	if IASettings._uiRegistered then
		applyContractCallsPerDayToUI()
		return
	end
	local screen = g_gui and g_gui.screenControllers and g_gui.screenControllers[InGameMenu]
	if screen == nil or screen.pageSettings == nil then return end
	local settingsPage = screen.pageSettings
	if settingsPage.multiVolumeVoiceBox == nil or settingsPage.gameSettingsLayout == nil then
		return
	end

	IASettings.initialize()

	IASettings._uiSection = buildSectionHeader(settingsPage)
	buildChoiceControl(settingsPage)

	-- Mission Offer Mode choice control
	local modeBox = settingsPage.multiVolumeVoiceBox:clone(settingsPage.gameSettingsLayout)
	recursivelyAssignFocusIds(modeBox)
	modeBox.id = "ia_settings_missionOfferModeBox"

	local modeOption = modeBox.elements[1]
	modeOption.id = "ia_settings_missionOfferMode"
	modeOption.target = IASettings
	modeOption:setCallback("onClickCallback", "onMissionOfferModeChanged")
	modeOption:setDisabled(false)

	local modeTexts = {}
	for _, key in ipairs(IASettings.MISSION_OFFER_MODE_LABELS) do
		table.insert(modeTexts, g_i18n:getText(key))
	end
	modeOption:setTexts(modeTexts)

	modeBox.elements[2]:setText(g_i18n:getText("ia_settings_missionOfferMode_title"))
	modeOption.elements[1]:setText(g_i18n:getText("ia_settings_missionOfferMode_info"))

	table.insert(settingsPage.controlsList, modeBox)
	IASettings._uiMissionModeBox = modeBox
	IASettings._uiMissionModeOption = modeOption

	-- Contract Max Fields Per Neighbour choice control
	buildMaxFieldsControl(settingsPage)

	-- Fieldwork Completion Threshold choice control
	local thresholdBox = settingsPage.multiVolumeVoiceBox:clone(settingsPage.gameSettingsLayout)
	recursivelyAssignFocusIds(thresholdBox)
	thresholdBox.id = "ia_settings_fieldworkCompletionThresholdBox"

	local thresholdOption = thresholdBox.elements[1]
	thresholdOption.id = "ia_settings_fieldworkCompletionThreshold"
	thresholdOption.target = IASettings
	thresholdOption:setCallback("onClickCallback", "onFieldworkCompletionThresholdChanged")
	thresholdOption:setDisabled(false)

	local thresholdTexts = {}
	for _, key in ipairs(IASettings.FIELDWORK_COMPLETION_THRESHOLD_LABELS) do
		table.insert(thresholdTexts, g_i18n:getText(key))
	end
	thresholdOption:setTexts(thresholdTexts)

	thresholdBox.elements[2]:setText(g_i18n:getText("ia_settings_fieldworkCompletionThreshold_title"))
	thresholdOption.elements[1]:setText(g_i18n:getText("ia_settings_fieldworkCompletionThreshold_info"))

	table.insert(settingsPage.controlsList, thresholdBox)
	IASettings._uiFieldworkThresholdBox = thresholdBox
	IASettings._uiFieldworkThresholdOption = thresholdOption

	-- Re-apply value (and re-validate against UI) whenever the frame re-opens.
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
		InGameMenuSettingsFrame.onFrameOpen, applyContractCallsPerDayToUI)
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
		InGameMenuSettingsFrame.onFrameOpen, applyMissionOfferModeToUI)
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
		InGameMenuSettingsFrame.onFrameOpen, applyContractMaxFieldsPerNeighbourToUI)
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
		InGameMenuSettingsFrame.onFrameOpen, applyFieldworkCompletionThresholdToUI)

	-- Register our cloned controls with the FocusManager when a GUI gets shown.
	FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, _)
		for _, ctrl in ipairs({ IASettings._uiSection, IASettings._uiBox, IASettings._uiMissionModeBox, IASettings._uiMaxFieldsBox, IASettings._uiFieldworkThresholdBox }) do
			if ctrl ~= nil
				and (ctrl.focusId == nil
					or not FocusManager.currentFocusData.idToElementMapping[ctrl.focusId])
			then
				FocusManager:loadElementFromCustomValues(ctrl, nil, nil, false, false)
			end
		end
		if settingsPage.gameSettingsLayout ~= nil then
			settingsPage.gameSettingsLayout:invalidateLayout()
		end
	end)

	applyContractCallsPerDayToUI()
	applyMissionOfferModeToUI()
	applyContractMaxFieldsPerNeighbourToUI()
	applyFieldworkCompletionThresholdToUI()
	settingsPage.gameSettingsLayout:invalidateLayout()
	IASettings._uiRegistered = true
end
