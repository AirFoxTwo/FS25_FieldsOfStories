--
-- FS25 Fields of Stories - force-complete button on the standard contracts overview.
-- Adds a "Complete contract" button to InGameMenuContractsFrame (pause menu -> Contracts)
-- that finishes the currently selected, active Fields of Stories field contract.
-- Single-player only: IANeighbours:loadMap blocks the mod in multiplayer, so the click
-- handler can call mission:finish(...) directly instead of routing through a network event.
--

IAForceCompleteContract = {}

function IAForceCompleteContract.isFosMission(mission)
	if type(mission) ~= "table" then
		return false
	end
	if mission.iaFieldsOfStoriesMission == true then
		return true
	end
	if IAFieldOutcomeMission == nil or mission.getMissionTypeName == nil then
		return false
	end
	local ok, name = pcall(mission.getMissionTypeName, mission)
	return ok and name == IAFieldOutcomeMission.NAME
end

function IAForceCompleteContract.isRunningFosMission(mission)
	return IAForceCompleteContract.isFosMission(mission)
		and mission.status ~= nil
		and mission.status == MissionStatus.RUNNING
end

--- Walk the (small) selected-cell table looking for a mission object.
function IAForceCompleteContract.findMissionInData(value, depth, visited)
	if value == nil then
		return nil
	end
	if IAForceCompleteContract.isFosMission(value) then
		return value
	end
	if depth == nil then
		depth = 3
	end
	if depth <= 0 or type(value) ~= "table" then
		return nil
	end
	visited = visited or {}
	if visited[value] then
		return nil
	end
	visited[value] = true
	local preferred = { "mission", "selectedMission", "contract", "selectedContract", "item", "data", "entry" }
	for _, key in ipairs(preferred) do
		local found = IAForceCompleteContract.findMissionInData(value[key], depth - 1, visited)
		if found ~= nil then
			return found
		end
	end
	for _, child in pairs(value) do
		local found = IAForceCompleteContract.findMissionInData(child, depth - 1, visited)
		if found ~= nil then
			return found
		end
	end
	return nil
end

--- Resolve the currently selected mission from the contracts frame. Mirrors the proven
--- FS25_ContractTypeGenerator approach, plus the FS25 list field name (contractsListBox).
function IAForceCompleteContract.getSelectedMission(frame)
	if frame == nil then
		return nil
	end

	-- Preferred: FS25's InGameMenuContractsFrame exposes the selected entry via
	-- getSelectedContract(), which returns a wrapper table with a `.mission` field.
	-- Evidence: FS25_FarmReputation/scripts/ContractAcceptanceManager.lua does
	-- `self:getSelectedContract()` and then reads `contract.mission`.
	local function unwrapMission(value)
		if type(value) ~= "table" then
			return nil
		end
		if IAForceCompleteContract.isFosMission(value) then
			return value
		end
		if type(value.mission) == "table" then
			return value.mission
		end
		return nil
	end

	if type(frame.getSelectedContract) == "function" then
		local ok, contract = pcall(frame.getSelectedContract, frame)
		if ok then
			local mission = unwrapMission(contract)
			if mission ~= nil then
				return mission
			end
		end
	end

	local accessors = { "getSelectedMission", "getCurrentMission", "getCurrentContract" }
	for _, name in ipairs(accessors) do
		if type(frame[name]) == "function" then
			local ok, result = pcall(frame[name], frame)
			if ok then
				local mission = unwrapMission(result)
				if mission ~= nil then
					return mission
				end
			end
		end
	end

	-- Direct fields the frame may keep updated.
	local directFields = { "selectedMission", "currentMission", "selectedContract", "currentContract", "highlightedMission", "activeMission" }
	for _, key in ipairs(directFields) do
		local mission = unwrapMission(frame[key])
		if mission ~= nil then
			return mission
		end
	end

	-- Fallback: read the highlighted list entry (list element + data list).
	local listElement
	local section
	local index
	local listCandidates = { "contractsListBox", "contractsList", "contractList", "missionList", "missionsList", "list" }
	for _, key in ipairs(listCandidates) do
		local candidate = frame[key]
		if type(candidate) == "table" then
			listElement = candidate
			if type(candidate.getSelectedPath) == "function" then
				local ok, s, i = pcall(candidate.getSelectedPath, candidate)
				if ok then
					section, index = s, i
				end
			elseif type(candidate.getSelectedIndexInSection) == "function" then
				local ok, i = pcall(candidate.getSelectedIndexInSection, candidate)
				if ok then
					section, index = 1, i
				end
			end
			if index ~= nil then
				break
			end
		end
	end

	if index ~= nil and index > 0 then
		local dataCandidates = { "sortedMissions", "missions", "contracts", "items", "listItems" }
		for _, key in ipairs(dataCandidates) do
			local dataList = frame[key]
			if type(dataList) == "table" then
				local mission = IAForceCompleteContract.findMissionInData(dataList[index], 2)
				if mission ~= nil then
					return mission
				end
			end
		end
	end

	if listElement ~= nil and section ~= nil and index ~= nil and type(listElement.getElementAtSectionIndex) == "function" then
		local ok, cell = pcall(listElement.getElementAtSectionIndex, listElement, section, index)
		if ok and cell ~= nil then
			local mission = IAForceCompleteContract.findMissionInData(cell, 3)
			if mission ~= nil then
				return mission
			end
		end
	end

	return nil
end

function IAForceCompleteContract.getMissionCompletion(mission)
	if mission == nil then
		return 0
	end
	if type(mission.getCompletion) == "function" then
		local ok, comp = pcall(mission.getCompletion, mission)
		if ok and tonumber(comp) ~= nil then
			return tonumber(comp)
		end
	end
	return tonumber(mission.completion) or 0
end

function IAForceCompleteContract.refreshButtonState()
	if g_inGameMenu == nil or g_inGameMenu.iaForceCompleteButton == nil then
		return
	end
	local frame = g_inGameMenu.pageContracts
	local mission = IAForceCompleteContract.getSelectedMission(frame)
	local enabled = IAForceCompleteContract.isRunningFosMission(mission)
		and IAForceCompleteContract.getMissionCompletion(mission) > 0.70
	if type(g_inGameMenu.iaForceCompleteButton.setDisabled) == "function" then
		g_inGameMenu.iaForceCompleteButton:setDisabled(not enabled)
	end
end

function IAForceCompleteContract.onListIndexChanged(observer, index, count)
	IAForceCompleteContract.refreshButtonState()
end

function IAForceCompleteContract.onClick()
	local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
	local mission = IAForceCompleteContract.getSelectedMission(frame)
	if not IAForceCompleteContract.isRunningFosMission(mission) then
		if g_i18n ~= nil and InfoDialog ~= nil then
			InfoDialog.show(g_i18n:getText("ia_force_complete_no_mission"))
		end
		return
	end
	if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer() then
		return
	end
	if IAForceCompleteContract.getMissionCompletion(mission) <= 0.70 then
		return
	end
	mission:finish(MissionFinishState.SUCCESS)
	if frame ~= nil and type(frame.updateList) == "function" then
		pcall(frame.updateList, frame)
	end
end

function IAForceCompleteContract.onFrameOpen(frame)
	if g_inGameMenu == nil or g_inGameMenu.menuButton == nil or g_inGameMenu.menuButton[1] == nil then
		return
	end
	local menuButton = g_inGameMenu.menuButton[1]
	local container = menuButton.parent
	if container == nil then
		return
	end

	if g_inGameMenu.iaForceCompleteButton == nil then
		g_inGameMenu.iaForceCompleteButton = menuButton:clone(frame)
		g_inGameMenu.iaForceCompleteButton.onClickCallback = IAForceCompleteContract.onClick
		-- The cloned menu button inherits its input-action glyph (MENU_BACK -> "ESC").
		-- Clear the action and hide the keyboard glyph so no keybind icon is shown.
		g_inGameMenu.iaForceCompleteButton.inputActionName = nil
		g_inGameMenu.iaForceCompleteButton.hideKeyboardGlyph = true
		if g_i18n ~= nil then
			g_inGameMenu.iaForceCompleteButton:setText(g_i18n:getText("ia_force_complete_button"))
		end
	end
	if g_inGameMenu.iaForceCompleteButton.parent ~= container then
		container:addElement(g_inGameMenu.iaForceCompleteButton)
	end
	g_inGameMenu.iaForceCompleteButton.visible = true
	container:invalidateLayout()

	-- Refresh the enabled state now and whenever the selected list entry changes.
	IAForceCompleteContract.refreshButtonState()
	if not IAForceCompleteContract._observerRegistered then
		local list = frame.contractsListBox or frame.contractsList or frame.contractList or frame.missionList or frame.missionsList or frame.list
		if type(list) == "table" and type(list.addIndexChangeObserver) == "function" then
			IAForceCompleteContract._observedList = list
			list:addIndexChangeObserver(IAForceCompleteContract, IAForceCompleteContract.onListIndexChanged)
			IAForceCompleteContract._observerRegistered = true
		end
	end
end

function IAForceCompleteContract.onFrameClose()
	if g_inGameMenu ~= nil and g_inGameMenu.iaForceCompleteButton ~= nil then
		g_inGameMenu.iaForceCompleteButton.visible = false
	end
end

function IAForceCompleteContract.install()
	if IAForceCompleteContract._installed then
		return
	end
	if InGameMenuContractsFrame == nil then
		return
	end
	if type(InGameMenuContractsFrame.onFrameOpen) ~= "function" then
		return
	end
	InGameMenuContractsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuContractsFrame.onFrameOpen, IAForceCompleteContract.onFrameOpen)
	if type(InGameMenuContractsFrame.onFrameClose) == "function" then
		InGameMenuContractsFrame.onFrameClose = Utils.appendedFunction(InGameMenuContractsFrame.onFrameClose, IAForceCompleteContract.onFrameClose)
	end

	-- The list selection has no reliable exposed change event, so refresh the button
	-- state from the frame's own per-frame update while the menu is open.
	local originalUpdate = InGameMenuContractsFrame.update or (FrameElement ~= nil and FrameElement.update or nil)
	if type(originalUpdate) == "function" then
		InGameMenuContractsFrame.update = function(self, dt)
			originalUpdate(self, dt)
			IAForceCompleteContract.refreshButtonState()
		end
	end

	IAForceCompleteContract._installed = true
end
