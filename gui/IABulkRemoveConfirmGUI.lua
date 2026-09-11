--
-- IABulkRemoveConfirmGUI.lua
-- Confirmation dialog for the bulk-remove-places keybind on the construction screen.
-- Shows the number and type of places that will be removed and provides Confirm / Cancel.
--
IABulkRemoveConfirmGUI = {}
IABulkRemoveConfirmGUI.dialog = nil

local IABulkRemoveConfirmGUI_mt = Class(IABulkRemoveConfirmGUI, DialogElement)

function IABulkRemoveConfirmGUI.new(target)
	local self = DialogElement.new(target, IABulkRemoveConfirmGUI_mt)
	return self
end

function IABulkRemoveConfirmGUI:setDialog(dialog)
	self.dialog = dialog
end

--- Populate the message text from the pending bulk-remove data.
function IABulkRemoveConfirmGUI:refreshMessage()
	local pending = IAPlaceablePlacementDetector ~= nil and IAPlaceablePlacementDetector._pendingBulkRemove or nil
	if pending == nil then
		if self.messageElement ~= nil then
			self.messageElement:setText("")
		end
		return
	end

	local count = pending.count or 0
	local ptype = pending.ptype or "?"
	local characterId = pending.characterId
	local characterName = nil

	if characterId ~= nil and IANeighbours ~= nil and IANeighbours.neighbours ~= nil then
		for _, n in pairs(IANeighbours.neighbours) do
			if n ~= nil and not n.isDeleted and n.id == characterId and n.name ~= nil then
				characterName = n.name
				break
			end
		end
	end

	local msg
	if characterId ~= nil and characterName ~= nil then
		msg = (g_i18n and g_i18n:getText("gui_fos_bulk_remove_confirm_char")) or "Remove %d place(s) for '%s'?"
		msg = string.format(msg, count, characterName)
	else
		local typeLabel = ptype
		-- Try to get display name from the tool mapping
		if IAPlaceablePlacementDetector ~= nil then
			local mappingDef, _ = IAPlaceablePlacementDetector:getSelectedToolInfo()
			if mappingDef ~= nil and mappingDef.displayName ~= nil then
				typeLabel = mappingDef.displayName
			end
		end
		msg = (g_i18n and g_i18n:getText("gui_fos_bulk_remove_confirm")) or "Remove %d place(s) of type '%s'?"
		msg = string.format(msg, count, typeLabel)
	end

	if self.messageElement ~= nil then
		self.messageElement:setText(msg)
	end
end

function IABulkRemoveConfirmGUI:onOpen()
	if IANeighbours and IANeighbours.debug then
		print("--- BULK_REMOVE_DLG onOpen")
	end
	IABulkRemoveConfirmGUI:superClass().onOpen(self)
	self:refreshMessage()
end

function IABulkRemoveConfirmGUI:onClickConfirm()
	if IANeighbours and IANeighbours.debug then
		print("--- BULK_REMOVE_DLG onClickConfirm dialog=" .. tostring(self.dialog) .. " gui=" .. tostring(g_gui))
	end
	-- Close dialog first to avoid UI issues during place removal
	if g_gui ~= nil and self.dialog ~= nil then
		g_gui:closeDialog(self.dialog)
		if IANeighbours and IANeighbours.debug then
			print("--- BULK_REMOVE_DLG dialog closed")
		end
	else
		if IANeighbours and IANeighbours.debug then
			print("--- BULK_REMOVE_DLG cannot close: g_gui=" .. tostring(g_gui) .. " dialog=" .. tostring(self.dialog))
		end
	end
	-- Execute the pending bulk removal
	if IAPlaceablePlacementDetector ~= nil then
		if IANeighbours and IANeighbours.debug then
			print("--- BULK_REMOVE_DLG calling executeBulkRemove")
		end
		IAPlaceablePlacementDetector:executeBulkRemove()
	else
		if IANeighbours and IANeighbours.debug then
			print("--- BULK_REMOVE_DLG IAPlaceablePlacementDetector is nil")
		end
	end
end

function IABulkRemoveConfirmGUI:onClickCancel()
	if IANeighbours and IANeighbours.debug then
		print("--- BULK_REMOVE_DLG onClickCancel dialog=" .. tostring(self.dialog))
	end
	if g_gui ~= nil and self.dialog ~= nil then
		g_gui:closeDialog(self.dialog)
	end
	-- Clear pending data
	if IAPlaceablePlacementDetector ~= nil then
		IAPlaceablePlacementDetector._pendingBulkRemove = nil
	end
end

function IABulkRemoveConfirmGUI:onEscPressed()
	if IANeighbours and IANeighbours.debug then
		print("--- BULK_REMOVE_DLG onEscPressed")
	end
	self:onClickCancel()
end
