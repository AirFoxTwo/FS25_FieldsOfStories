--
-- FS25 Fields of Stories — HumanModel host: create with IAHumanCharacter.forHumanModel(model).
-- PlayerStyle index application: applyPlayerStyleParamTable (IAHelper.lua).
--

IAHumanCharacter = {}

local HumanModelHost = {}
HumanModelHost.__index = HumanModelHost

function HumanModelHost:_findFirstAnimCharSet(nodeId)
	if nodeId == nil or nodeId == 0 then
		return 0
	end
	local cs = getAnimCharacterSet(nodeId)
	if cs ~= nil and cs ~= 0 then
		return cs
	end
	for i = 0, getNumOfChildren(nodeId) - 1 do
		cs = self:_findFirstAnimCharSet(getChildAt(nodeId, i))
		if cs ~= nil and cs ~= 0 then
			return cs
		end
	end
	return 0
end

function HumanModelHost:_assignLoopingClip(charSet, clipName)
	local ix = getAnimClipIndex(charSet, clipName)
	if ix < 0 then
		return false
	end
	assignAnimTrackClip(charSet, 0, ix)
	setAnimTrackLoopState(charSet, 0, true)
	enableAnimTrack(charSet, 0)
	return true
end

function HumanModelHost:_startFirstMatchingIdle(charSet, clipNames)
	for i = 1, #clipNames do
		if self:_assignLoopingClip(charSet, clipNames[i]) then
			return true
		end
	end
	return false
end

function HumanModelHost:_idleClipNamesForGender(isFemale)
	if isFemale then
		return { "idle1FemaleSource", "NPCFemaleIdle01Source", "NPCFemaleIdle02Source", "idle1Source" }
	end
	return { "idle1Source", "NPCMaleIdle01Source", "NPCMaleIdle02Source" }
end

function HumanModelHost:_resolveCharSetAfterClone(skeleton)
	if skeleton == nil then
		return nil
	end
	local charSet = nil
	if getNumOfChildren(skeleton) > 0 then
		charSet = getAnimCharacterSet(getChildAt(skeleton, 0))
	end
	if charSet == nil or charSet == 0 then
		charSet = getAnimCharacterSet(skeleton)
	end
	if charSet == nil or charSet == 0 then
		return nil
	end
	return charSet
end

--- @param humanModel HumanModel
--- @return HumanModelHost
function IAHumanCharacter.forHumanModel(humanModel)
	return setmetatable({ model = humanModel }, HumanModelHost)
end

function HumanModelHost:getModel()
	return self.model
end

function HumanModelHost:forceVisible()
	local model = self.model
	if model == nil or model.rootNode == nil then
		return
	end
	if model.setVisibility then
		model:setVisibility(true)
	end
	iaSetNodeSubtreeVisible(model.rootNode, true)
end

function HumanModelHost:setEngineVisibility(visible)
	local model = self.model
	if model == nil or model.rootNode == nil then
		return
	end
	if model.setVisibility then
		model:setVisibility(visible == true)
	end
	iaSetNodeSubtreeVisible(model.rootNode, visible == true)
end

--- @return boolean false if rig not ready (caller may retry)
function HumanModelHost:tryStartStandingIdle(isFemale)
	local model = self.model
	if model == nil or model.rootNode == nil then
		return false
	end
	local female = isFemale == true
	local names = self:_idleClipNamesForGender(female)
	local charSet = self:_findFirstAnimCharSet(model.rootNode)
	if charSet ~= 0 then
		self:_startFirstMatchingIdle(charSet, names)
		return true
	end
	if model.skeleton == nil then
		return false
	end
	if g_animCache == nil or AnimationCache == nil or AnimationCache.CHARACTER == nil then
		return false
	end
	local animNode = g_animCache:getNode(AnimationCache.CHARACTER)
	if animNode == nil or animNode == 0 then
		return false
	end
	local animRoot = (getNumOfChildren(animNode) > 0) and getChildAt(animNode, 0) or animNode
	cloneAnimCharacterSet(animRoot, model.skeleton)
	charSet = self:_resolveCharSetAfterClone(model.skeleton)
	if charSet == nil then
		return false
	end
	if not self:_startFirstMatchingIdle(charSet, names) then
		self:_assignLoopingClip(charSet, "idle1Source")
	end
	return true
end

function HumanModelHost:dispose()
	local model = self.model
	if model ~= nil and model.delete then
		model:delete()
	end
	self.model = nil
end
