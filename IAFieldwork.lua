--
-- FS25 - InteractiveNeighbours - Fieldwork Class
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 24.01.2026
-- @Version: 1.0.0.0
-- Enum class for fieldwork job types

IAFieldwork = {}
IAFieldwork._mt = Class(IAFieldwork)

-- Fieldwork job type enum
IAFieldwork.JobType = {
	CULTIVATE = "cultivate",
	HARROW = "harrow",
	HARVEST = "harvest",
	-- Fertilize subtypes — pick the one matching the implement's spread material.
	MANURESPREADING = "manure_spreading",
	SLURRYSPREADING = "slurry_spreading",
	FERTILIZEDSPREADING = "fertilizer_spreading",
	SPRAY = "spray",
	SEED = "seed",
	PLOW = "plow",
	-- Phone contract: success when sampled field state matches situation fieldStateOutcome.
	IA_FIELD_OUTCOME = "ia_field_outcome",
	-- Additional field outcome missions: fieldwork + delivery to farm.
	LIME = "lime",
	STONE_PICKING = "stone_picking",
	GRASS_MOWING = "grass_mowing",
	HARVEST_DELIVER_CORN = "harvest_deliver_corn",
}

--- Hard list of crops a Farmer neighbour is allowed to grow / harvest on their assigned farmlands.
--- "Possible seeds of the character" — anything seeded on an assigned field that is NOT in this list is
--- considered foreign and gets normalized to wheat (harvest-ready) on first load. Hardcoded for now.
IAFieldwork.CHARACTER_HARVEST_FRUIT_NAMES = {
	"WHEAT",
	"BARLEY",
	"CANOLA",
	"OAT",
	"SOYBEAN",
}

--- Crop the foreign fields are normalized to on first load (see CHARACTER_HARVEST_FRUIT_NAMES).
IAFieldwork.CHARACTER_DEFAULT_NORMALIZE_FRUIT_NAME = "WHEAT"

--- Resolve CHARACTER_HARVEST_FRUIT_NAMES to a set { fruitTypeIndex = true } (skips names that don't resolve).
--- @return table set of allowed fruitTypeIndex -> true
function IAFieldwork.getCharacterHarvestFruitIndexSet()
	local set = {}
	for _, name in ipairs(IAFieldwork.CHARACTER_HARVEST_FRUIT_NAMES) do
		local idx = IAFieldwork.resolveFruitTypeNameOrIndex(name)
		if idx ~= nil then
			set[idx] = true
		end
	end
	return set
end

--- True when `fruitTypeIndex` is one of the character's allowed harvest crops.
--- @param number|nil fruitTypeIndex
--- @return boolean
function IAFieldwork.isFruitTypeInCharacterHarvestList(fruitTypeIndex)
	if fruitTypeIndex == nil then
		return false
	end
	return IAFieldwork.getCharacterHarvestFruitIndexSet()[fruitTypeIndex] == true
end

--- Pick a random resolvable crop from CHARACTER_HARVEST_FRUIT_NAMES.
--- @param number|nil excludeIndex optional fruitTypeIndex to avoid (returns it only when it's the sole option)
--- @return number|nil fruitTypeIndex, or nil if none resolve
function IAFieldwork.getRandomCharacterHarvestFruitIndex(excludeIndex)
	local candidates = {}
	for _, name in ipairs(IAFieldwork.CHARACTER_HARVEST_FRUIT_NAMES) do
		local idx = IAFieldwork.resolveFruitTypeNameOrIndex(name)
		if idx ~= nil and idx ~= excludeIndex then
			table.insert(candidates, idx)
		end
	end
	if #candidates == 0 then
		-- Fall back to the excluded one if it's the only thing that resolves.
		return IAFieldwork.resolveFruitTypeNameOrIndex(IAFieldwork.CHARACTER_DEFAULT_NORMALIZE_FRUIT_NAME)
	end
	return candidates[math.random(1, #candidates)]
end

--- Harvest-ready growth state for a fruit type (minHarvestingGrowthState = first ripe/harvestable state).
--- @param number|nil fruitTypeIndex
--- @return number|nil growthState, or nil if fruit type unknown
function IAFieldwork.getHarvestReadyGrowthStateForFruit(fruitTypeIndex)
	if fruitTypeIndex == nil or g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
		return nil
	end
	local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
	if fruit == nil then
		return nil
	end
	if fruit.minHarvestingGrowthState ~= nil and fruit.minHarvestingGrowthState > 0 then
		return fruit.minHarvestingGrowthState
	end
	if fruit.maxHarvestingGrowthState ~= nil and fruit.maxHarvestingGrowthState > 0 then
		return fruit.maxHarvestingGrowthState
	end
	return nil
end

--- Set a field to a standing, harvest-ready crop (defaults to wheat) via a FieldUpdateTask, enqueued.
--- Used on first load to normalize foreign crops on character-assigned farmlands.
--- @param table field field with fieldState / getDensityMapPolygon
--- @param number|nil fruitTypeIndex crop to set; defaults to CHARACTER_DEFAULT_NORMALIZE_FRUIT_NAME (wheat)
--- @return boolean true when a task was enqueued
function IAFieldwork.enqueueSetFieldToCropHarvestReady(field, fruitTypeIndex)
	if field == nil then
		return false
	end
	if fruitTypeIndex == nil then
		fruitTypeIndex = IAFieldwork.resolveFruitTypeNameOrIndex(IAFieldwork.CHARACTER_DEFAULT_NORMALIZE_FRUIT_NAME)
	end
	if fruitTypeIndex == nil then
		return false
	end
	local growthState = IAFieldwork.getHarvestReadyGrowthStateForFruit(fruitTypeIndex)
	if growthState == nil then
		return false
	end
	local state = {
		fruitTypeIndex = fruitTypeIndex,
		growthState = growthState,
		weedState = 0,
	}
	local task = IAFieldwork.buildFieldUpdateTaskFromExpectedState(field, state)
	if task == nil then
		return false
	end
	task:enqueue(true)
	return true
end

--- True when the job type is one of the fertilize subtypes (MANURESPREADING / SLURRYSPREADING / FERTILIZEDSPREADING).
function IAFieldwork.isFertilizeJobType(jt)
	return jt == IAFieldwork.JobType.MANURESPREADING
		or jt == IAFieldwork.JobType.SLURRYSPREADING
		or jt == IAFieldwork.JobType.FERTILIZEDSPREADING
end

--- Normalize situation / schedule fieldwork string to IAFieldwork.JobType value, or nil.
function IAFieldwork.normalizeFieldworkJobType(fieldworkStr)
	if fieldworkStr == nil or fieldworkStr == "" then
		return nil
	end
	local ret = nil
	local s = string.lower(tostring(fieldworkStr))
	if s == "stubble_cultivation" or s == "stubblecultivation" or s == "stubble" then
		ret = IAFieldwork.JobType.HARROW
	end
	if s == "cultivate" or s == "cultivating" then
		ret = IAFieldwork.JobType.CULTIVATE
	end
	if s == "harrow" or s == "harrowing" then
		ret = IAFieldwork.JobType.HARROW
	end
	if s == "harvest" or s == "harvesting" then
		ret = IAFieldwork.JobType.HARVEST
	end
	if s == "manurespreading" or s == "manure_spreading" or s == "manure spreading" then
		ret = IAFieldwork.JobType.MANURESPREADING
	end
	if s == "slurryspreading" or s == "slurry_spreading" or s == "slurry spreading" then
		ret = IAFieldwork.JobType.SLURRYSPREADING
	end
	if s == "fertilizedspreading" or s == "fertilizerspreading" or s == "fertilizer_spreading" or s == "fertilizer spreading" then
		ret = IAFieldwork.JobType.FERTILIZEDSPREADING
	end
	if s == "spray" or s == "spraying" then
		ret = IAFieldwork.JobType.SPRAY
	end
	if s == "seed" or s == "sow" or s == "sowing" then
		ret = IAFieldwork.JobType.SEED
	end
	if s == "plow" or s == "plowing" then
		ret = IAFieldwork.JobType.PLOW
	end
	if s == "ia_field_outcome" then
		ret = IAFieldwork.JobType.IA_FIELD_OUTCOME
	end
	if s == "lime" or s == "liming" or s == "lime_spreading" then
		ret = IAFieldwork.JobType.LIME
	end
	if s == "stone_picking" or s == "stonepicking" or s == "stone_pick" or s == "stones" then
		ret = IAFieldwork.JobType.STONE_PICKING
	end
	if s == "grass_mowing" or s == "grassmowing" or s == "mowing" or s == "mow" or s == "grass_mow" then
		ret = IAFieldwork.JobType.GRASS_MOWING
	end
	if s == "harvest_deliver_corn" or s == "harvestdelivercorn" or s == "harvest_corn_deliver" or s == "corn_deliver" then
		ret = IAFieldwork.JobType.HARVEST_DELIVER_CORN
	end
	--IAprintDebug("normalizeFieldworkJobType", ("ret: "..s.." -> "..(ret ~= nil and tostring(ret) or "nil")), nil, nil, nil)
	return ret
end

--- Localized short job name for UI and `{jobType}` conversation placeholders (same plain labels as phone missions).
--- @param string|nil rawFieldwork situation XML `fieldwork` string
--- @param number|nil nextCropFruitTypeIndex optional; when job is SEED, used for `ia_fieldwork_label_seed_with_crop`
--- @return string
function IAFieldwork.getLocalizedFieldworkJobTypeLabel(rawFieldwork, nextCropFruitTypeIndex, prefix)
	if prefix == nil then
		prefix = ""
	end
	if rawFieldwork == nil or rawFieldwork == "" then
		return ""
	end
	if g_i18n == nil then
		IAprintDebug("getLocalizedFieldworkJobTypeLabel", "rawFieldwork: "..tostring(rawFieldwork), nil, nil, nil)
		return tostring(rawFieldwork)
	end
	IAprintDebug("getLocalizedFieldworkJobTypeLabel", "rawFieldwork: "..tostring(rawFieldwork), nil, nil, nil)
	local jt = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(rawFieldwork)))
	if jt == nil then
		IAprintDebug("getLocalizedFieldworkJobTypeLabel", "rawFieldwork: "..tostring(rawFieldwork), nil, nil, nil)
		return tostring(rawFieldwork)
	end
	if jt == IAFieldwork.JobType.SEED then
		if nextCropFruitTypeIndex ~= nil and IAFieldOutcomeMission ~= nil and type(IAFieldOutcomeMission.iaFruitTypeDisplayTitle) == "function" then
			local crop = IAFieldOutcomeMission.iaFruitTypeDisplayTitle(nextCropFruitTypeIndex)
			if crop ~= nil and crop ~= "" then
				return string.format(g_i18n:getText(prefix.."ia_fieldwork_label_seed_with_crop"), crop)
			end
		end
		return g_i18n:getText(prefix.."ia_fieldwork_label_seed")
	end
	if jt == IAFieldwork.JobType.MANURESPREADING then
		return g_i18n:getText(prefix.."ia_fieldwork_label_manure")
	end
	if jt == IAFieldwork.JobType.SLURRYSPREADING then
		return g_i18n:getText(prefix.."ia_fieldwork_label_slurry")
	end
	if jt == IAFieldwork.JobType.FERTILIZEDSPREADING then
		return g_i18n:getText(prefix.."ia_fieldwork_label_fertilize_mineral")
	end
	if jt == IAFieldwork.JobType.LIME then
		return g_i18n:getText(prefix.."ia_fieldwork_label_lime")
	end
	if jt == IAFieldwork.JobType.STONE_PICKING then
		return g_i18n:getText(prefix.."ia_fieldwork_label_stone_picking")
	end
	if jt == IAFieldwork.JobType.GRASS_MOWING then
		return g_i18n:getText(prefix.."ia_fieldwork_label_grass_mowing")
	end
	if jt == IAFieldwork.JobType.HARVEST_DELIVER_CORN then
		return g_i18n:getText(prefix.."ia_fieldwork_label_harvest_deliver_corn")
	end
	if jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
		IAprintDebug("getLocalizedFieldworkJobTypeLabel", "ia_field_outcome: "..g_i18n:getText("ia_fieldwork_label_condition"), nil, nil, nil)
		return g_i18n:getText(prefix.."ia_fieldwork_label_condition")
	end
	local plainKeys = {
		[IAFieldwork.JobType.CULTIVATE] = "ia_fieldwork_label_cultivate",
		[IAFieldwork.JobType.HARROW] = "ia_fieldwork_label_harrow",
		[IAFieldwork.JobType.HARVEST] = "ia_fieldwork_label_harvest",
		[IAFieldwork.JobType.SPRAY] = "ia_fieldwork_label_spray",
		[IAFieldwork.JobType.PLOW] = "ia_fieldwork_label_plow",
	}
	IAprintDebug("getLocalizedFieldworkJobTypeLabel", "jt: "..tostring(jt), nil, nil, nil)
	local lk = plainKeys[jt]
	if lk ~= nil then
		IAprintDebug("getLocalizedFieldworkJobTypeLabel", "lk: "..(lk ~= nil and lk or "nil"), nil, nil, nil)
		IAprintDebug("getLocalizedFieldworkJobTypeLabel", "lk: "..g_i18n:getText(lk), nil, nil, nil)
		return g_i18n:getText(prefix..lk)
	end
	IAprintDebug("getLocalizedFieldworkJobTypeLabel", "rawFieldwork: "..tostring(rawFieldwork), nil, nil, nil)
	return tostring(rawFieldwork)
end

--- Localized implement label for `{vehicleNameWithArticle}` and similar conversation placeholders.
--- Returns the article-inflected, language-specific implement name (EN: "a cultivator", DE: "einen Grubber")
--- using the same `ia_fieldwork_equip_*` l10n keys as the phone mission equipment hint, so the player
--- choice line "I would have to use your {vehicleNameWithArticle}" reads naturally in both languages.
--- @param string|nil rawFieldwork situation XML `fieldwork` string
--- @return string
function IAFieldwork.getLocalizedFieldworkImplementLabel(rawFieldwork)
	if g_i18n == nil then
		return rawFieldwork ~= nil and tostring(rawFieldwork) or ""
	end
	if rawFieldwork == nil or rawFieldwork == "" then
		return g_i18n:getText("ia_fieldwork_equip_generic")
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(rawFieldwork)))
	if jt == nil then
		return g_i18n:getText("ia_fieldwork_equip_generic")
	end
	if jt == IAFieldwork.JobType.MANURESPREADING then
		return g_i18n:getText("ia_fieldwork_equip_manure")
	end
	if jt == IAFieldwork.JobType.SLURRYSPREADING then
		return g_i18n:getText("ia_fieldwork_equip_slurry")
	end
	if jt == IAFieldwork.JobType.FERTILIZEDSPREADING then
		return g_i18n:getText("ia_fieldwork_equip_mineral_fertilizer")
	end
	if jt == IAFieldwork.JobType.LIME then
		return g_i18n:getText("ia_fieldwork_equip_lime")
	end
	if jt == IAFieldwork.JobType.STONE_PICKING then
		return g_i18n:getText("ia_fieldwork_equip_stone_picker")
	end
	if jt == IAFieldwork.JobType.GRASS_MOWING then
		return g_i18n:getText("ia_fieldwork_equip_grass_mower")
	end
	if jt == IAFieldwork.JobType.HARVEST_DELIVER_CORN then
		return g_i18n:getText("ia_fieldwork_equip_harvest_deliver_corn")
	end
	if jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
		return g_i18n:getText("ia_fieldwork_equip_generic")
	end
	local equipKeys = {
		[IAFieldwork.JobType.CULTIVATE] = "ia_fieldwork_equip_cultivate",
		[IAFieldwork.JobType.HARROW] = "ia_fieldwork_equip_harrow",
		[IAFieldwork.JobType.HARVEST] = "ia_fieldwork_equip_harvest",
		[IAFieldwork.JobType.SPRAY] = "ia_fieldwork_equip_herbicide",
		[IAFieldwork.JobType.SEED] = "ia_fieldwork_equip_seed",
		[IAFieldwork.JobType.PLOW] = "ia_fieldwork_equip_plow",
	}
	IAprintDebug("getLocalizedFieldworkImplementLabel", "jt: "..tostring(jt), nil, nil, nil)
	local ek = equipKeys[jt]
	IAprintDebug("getLocalizedFieldworkImplementLabel", "ek: "..(ek ~= nil and ek or "nil"), nil, nil, nil)
	if ek ~= nil then
		return g_i18n:getText(ek)
	end
	return g_i18n:getText("ia_fieldwork_equip_generic")
end

--- True when the implement for this fieldwork job consumes refillable material
--- (seeds / spray / fertilizer / slurry / manure / lime). Used by dynamic conversations
--- to decide whether the NPC adds a "refill at the farm" note when lending equipment.
--- @param string|nil rawFieldwork situation XML `fieldwork` string
--- @return boolean
function IAFieldwork.fieldworkImplementUsesRefillableConsumable(rawFieldwork)
	if rawFieldwork == nil or rawFieldwork == "" then
		return false
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(rawFieldwork)))
	return jt == IAFieldwork.JobType.SEED
		or IAFieldwork.isFertilizeJobType(jt)
		or jt == IAFieldwork.JobType.SPRAY
		or jt == IAFieldwork.JobType.LIME
end

--- Canonical `IASituation.jobType` / AI fieldwork enum (`IAFieldwork.JobType.*`) for Fieldwork situations.
--- Prefers current situation XML `fieldwork` (so saves with outdated `#jobType` still match mod); else normalizes persisted value.
--- @param table|nil config situation config (`type`, `fieldwork`)
--- @param string|nil persistedFromSave constructor or savegame `#jobType`
--- @return string|nil
function IAFieldwork.resolveFieldworkJobTypeForSituation(config, persistedFromSave)
	if config ~= nil and config.type ~= nil and string.lower(tostring(config.type)) == "fieldwork" then
		if config.fieldwork ~= nil and config.fieldwork ~= "" then
			local jt = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(config.fieldwork)))
			if jt ~= nil then
				return jt
			end
		end
	end
	if persistedFromSave ~= nil and tostring(persistedFromSave) ~= "" then
		local jt = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(persistedFromSave)))
		if jt ~= nil then
			return jt
		end
		return string.lower(tostring(persistedFromSave))
	end
	return nil
end

--- Resolve XML / config fruit reference: numeric string → number; crop name (e.g. `BARLEY`) → `fruitType.index`; else nil.
--- @param string|number|nil name
--- @return number|nil
function IAFieldwork.resolveFruitTypeNameOrIndex(name)
	if name == nil or name == "" or g_fruitTypeManager == nil then
		return nil
	end
	local asNumber = tonumber(name)
	if asNumber ~= nil then
		return asNumber
	end
	if type(g_fruitTypeManager.getFruitTypes) ~= "function" then
		return nil
	end
	local fruitTypes = g_fruitTypeManager:getFruitTypes()
	if fruitTypes == nil then
		return nil
	end
	local nameLower = string.lower(tostring(name))
	for _, fruitType in ipairs(fruitTypes) do
		if fruitType ~= nil and fruitType.name ~= nil and string.lower(tostring(fruitType.name)) == nameLower then
			return fruitType.index
		end
	end
	return nil
end

--- Density-map value for mineral / artificial fertilizer (FieldSprayType.FERTILIZER). Do not assume this is 1 — FS uses FieldManager + getValueByType.
-- @return number
function IAFieldwork.getFertilizerFieldSprayTypeIndex()
	if g_fieldManager ~= nil and g_fieldManager.sprayTypeFertilizer ~= nil then
		return g_fieldManager.sprayTypeFertilizer
	end
	if FieldSprayType ~= nil and FieldSprayType.FERTILIZER ~= nil and type(FieldSprayType.getValueByType) == "function" then
		local ok, v = pcall(FieldSprayType.getValueByType, FieldSprayType.FERTILIZER)
		if ok and v ~= nil then
			return v
		end
	end
	return 1
end

--- Growth state to apply after harvest for the crop currently on `field` (uses cutState when valid, else 1). Nil if field state or fruit manager is missing.
-- @param table field
-- @return number|nil
function IAFieldwork.getPostHarvestGrowthStateForFieldCrop(field)
	if field == nil or field.fieldState == nil or field.fieldState.fruitTypeIndex == nil or g_fruitTypeManager == nil then
		return nil
	end
	local fruitTypeIndex = field.fieldState.fruitTypeIndex
	local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
	if fruitTypeDesc ~= nil and fruitTypeDesc.cutState ~= nil and fruitTypeDesc.cutState > 0 then
		return fruitTypeDesc.cutState
	end
	return 1
end

--- @param string enumName e.g. "FERTILIZER", "MANURE", "LIQUID_MANURE"
-- @return number|nil density map spray type index
function IAFieldwork.getFieldSprayTypeIndexForEnumName(enumName)
	if FieldSprayType == nil or type(FieldSprayType.getValueByType) ~= "function" or enumName == nil then
		return nil
	end
	local typ = FieldSprayType[enumName]
	if typ == nil then
		return nil
	end
	local ok, v = pcall(FieldSprayType.getValueByType, typ)
	if ok and v ~= nil then
		return v
	end
	return nil
end

--- FieldState.sprayType (density index) for slurry application: SprayTypeManager `sprayGroundType` (LIQUIDMANURE / DIGESTATE / LIQUID_MANURE).
-- Falls back to FERTILIZER channel if the spray type manager doesn't expose a slurry channel.
-- @return number
function IAFieldwork.getSlurryFieldSprayTypeIndex()
	if g_sprayTypeManager ~= nil and type(g_sprayTypeManager.getSprayTypeByName) == "function" then
		for _, name in ipairs({ "LIQUIDMANURE", "DIGESTATE", "LIQUID_MANURE" }) do
			local ok, st = pcall(function()
				return g_sprayTypeManager:getSprayTypeByName(name)
			end)
			if ok and st ~= nil and st.sprayGroundType ~= nil then
				return st.sprayGroundType
			end
		end
	end
	local enumLm = tonumber(IAFieldwork.getFieldSprayTypeIndexForEnumName("LIQUID_MANURE"))
	if enumLm == 3 then
		return 5
	end
	if enumLm ~= nil then
		return enumLm
	end
	return IAFieldwork.getFertilizerFieldSprayTypeIndex()
end

--- FieldState.sprayType for solid-manure spreading (FieldSprayType.MANURE).
-- @return number
function IAFieldwork.getManureFieldSprayTypeIndex()
	return IAFieldwork.getFieldSprayTypeIndexForEnumName("MANURE") or IAFieldwork.getFertilizerFieldSprayTypeIndex()
end

--- FieldState.sprayType (density index) for a fertilize-subtype job. Returns nil for non-fertilize jobs.
-- @param string|nil jobType IAFieldwork.JobType.* value
-- @return number|nil
function IAFieldwork.getFertilizeSprayTypeIndexForJobType(jobType)
	if jobType == IAFieldwork.JobType.SLURRYSPREADING then
		return IAFieldwork.getSlurryFieldSprayTypeIndex()
	end
	if jobType == IAFieldwork.JobType.MANURESPREADING then
		return IAFieldwork.getManureFieldSprayTypeIndex()
	end
	if jobType == IAFieldwork.JobType.FERTILIZEDSPREADING then
		return IAFieldwork.getFertilizerFieldSprayTypeIndex()
	end
	return nil
end

--- Post-herbicide "withered" weed states (from WeedSystem herbicide replacements):
-- vanilla FS25: 7 = small withered, 8 = medium withered, 9 = large withered (PF may also target 9).
function IAFieldwork.collectPostHerbicideWeedStates()
	local states = { [7] = true, [8] = true }
	if g_currentMission ~= nil and g_currentMission.weedSystem ~= nil then
		local ws = g_currentMission.weedSystem
		if type(ws.getHerbicideReplacements) == "function" then
			local ok, rd = pcall(ws.getHerbicideReplacements, ws)
			if ok and rd ~= nil and rd.weed ~= nil and rd.weed.replacements ~= nil then
				for _, target in pairs(rd.weed.replacements) do
					local t = tonumber(target)
					if t ~= nil and t ~= 0 then
						states[t] = true
					end
				end
			end
		end
	end
	return states
end

function IAFieldwork.isPostHerbicideWeedState(weedState)
	local n = tonumber(weedState)
	if n == nil then
		return false
	end
	return IAFieldwork.collectPostHerbicideWeedStates()[n] == true
end

--- Expected weedState after herbicide spray (phone contracts / NPC field-update tasks).
--- Vanilla maps small weeds (3) -> 7 ("small withered") and larger weeds -> 8/9, but a whole-field
--- completion only sets one state. Prefer the small withered state (7) so a field that only had
--- small weeds is never inflated into the larger withered states.
function IAFieldwork.getExpectedPostHerbicideWeedState()
	local states = IAFieldwork.collectPostHerbicideWeedStates()
	if states[7] then
		return 7
	end
	local best = nil
	for s in pairs(states) do
		local n = tonumber(s)
		if n ~= nil and (best == nil or n < best) then
			best = n
		end
	end
	return best or 7
end

--- FieldState keys after NPC fieldwork completes (same semantics as enqueueCompleteFieldworkFieldUpdate / IASituation:completeFieldwork).
-- Used by phone IAFieldOutcomeMission targets; optional XML fieldStateOutcome merges on top in IAGameLoopHelper.
-- @param string|nil jobType IAFieldwork.JobType.* or nil
-- @param table|nil field field with fieldState and getDensityMapPolygon
-- @param number|nil seedFruitTypeIndex for SEED only
-- @param number|nil fertilizeSprayTypeIndex unused (sprayType is not asserted on fertilize-family contracts; see IAFieldOutcomeMissionProbeEvaluator.fertilizeSprayTypeKeyMatches)
-- @return table numeric FieldState subset
function IAFieldwork.getExpectedFieldStateAfterJob(jobType, field, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	local out = {}
	if field == nil or jobType == nil then
		return out
	end
	if jobType == IAFieldwork.JobType.CULTIVATE then
		out.groundType = FieldGroundType.CULTIVATED
		out.weedState = 0
		out.fruitTypeIndex = FruitType.UNKNOWN
		out.growthState = 1
		out.stubbleShredLevel = 0
	elseif jobType == IAFieldwork.JobType.SEED then
		if seedFruitTypeIndex == nil then
			return out
		end
		out.fruitTypeIndex = seedFruitTypeIndex
		out.growthState = 1
		out.weedState = 1
		out.groundType = FieldGroundType.SOWN
	elseif IAFieldwork.isFertilizeJobType(jobType) then
		local sl = 0
		if field.fieldState ~= nil and field.fieldState.sprayLevel ~= nil then
			sl = field.fieldState.sprayLevel
		end
		out.sprayLevel = sl + 1
		-- sprayType intentionally not asserted on the contract: FS25 may write FERTILIZER/MANURE
		-- interchangeably (see IAFieldOutcomeMissionProbeEvaluator.fertilizeSprayTypeKeyMatches).
	elseif jobType == IAFieldwork.JobType.SPRAY then
		-- FS25: herbicide leaves the weed map in a post-spray "withered" state; use the small
		-- withered state (7) so small-weed fields aren't inflated to the larger withered states.
		out.weedState = IAFieldwork.getExpectedPostHerbicideWeedState()
	elseif jobType == IAFieldwork.JobType.HARVEST then
		local fruitTypeIndex = field.fieldState ~= nil and field.fieldState.fruitTypeIndex or nil
		local harvestedGrowthState = IAFieldwork.getPostHarvestGrowthStateForFieldCrop(field)
		if fruitTypeIndex == nil or harvestedGrowthState == nil then
			return out
		end
		out.weedState = 0
		out.fruitTypeIndex = fruitTypeIndex
		out.growthState = harvestedGrowthState
		out.sprayLevel = 0
		out.clearHeightTypes = true
	elseif jobType == IAFieldwork.JobType.HARROW then
		out.fruitTypeIndex = FruitType.UNKNOWN
		out.growthState = 1
		out.groundType = FieldGroundType.STUBBLE_TILLAGE
	elseif jobType == IAFieldwork.JobType.PLOW then
		out.fruitTypeIndex = FruitType.UNKNOWN
		out.growthState = 1
		out.weedState = 0
		out.groundType = FieldGroundType.PLOWED
		out.stubbleShredLevel = 0
	elseif jobType == IAFieldwork.JobType.LIME then
		out.limeLevel = 0
		if g_fieldManager ~= nil and g_fieldManager.limeLevelMaxValue ~= nil then
			out.limeLevel = g_fieldManager.limeLevelMaxValue
		end
	elseif jobType == IAFieldwork.JobType.STONE_PICKING then
		out.stoneLevel = 0
	elseif jobType == IAFieldwork.JobType.GRASS_MOWING then
		local fruitTypeIndex = field.fieldState ~= nil and field.fieldState.fruitTypeIndex or nil
		local mowedGrowthState = IAFieldwork.getPostHarvestGrowthStateForFieldCrop(field)
		if fruitTypeIndex == nil or mowedGrowthState == nil then
			return out
		end
		out.fruitTypeIndex = fruitTypeIndex
		out.growthState = mowedGrowthState
		out.clearHeightTypes = true
	elseif jobType == IAFieldwork.JobType.HARVEST_DELIVER_CORN then
		local fruitTypeIndex = field.fieldState ~= nil and field.fieldState.fruitTypeIndex or nil
		local harvestedGrowthState = IAFieldwork.getPostHarvestGrowthStateForFieldCrop(field)
		if fruitTypeIndex == nil or harvestedGrowthState == nil then
			return out
		end
		out.weedState = 0
		out.fruitTypeIndex = fruitTypeIndex
		out.growthState = harvestedGrowthState
		out.sprayLevel = 0
		out.clearHeightTypes = true
	end
	return out
end

--- FieldState keys phone outcome missions should match at probes: only what that job can change (not trigger crops for spray/fertilize).
-- @param string|nil jobEnum IAFieldwork.JobType.* after normalize
-- @return table|nil map key -> true, or nil = do not prune (author-defined ia_field_outcome / unknown)
function IAFieldwork.getValidationKeySetForOutcomeJob(jobEnum)
	if jobEnum == nil or IAFieldwork.JobType == nil then
		return nil
	end
	if jobEnum == IAFieldwork.JobType.SPRAY then
		return { weedState = true }
	elseif IAFieldwork.isFertilizeJobType(jobEnum) then
		return { sprayLevel = true }--, sprayType = true
	elseif jobEnum == IAFieldwork.JobType.SEED then
		return { fruitTypeIndex = true, growthState = true, groundType = true }
	elseif jobEnum == IAFieldwork.JobType.HARVEST then
		return { fruitTypeIndex = true, growthState = true }
	elseif jobEnum == IAFieldwork.JobType.CULTIVATE then
		return { groundType = true }
	elseif jobEnum == IAFieldwork.JobType.HARROW then
		return { groundType = true, stubbleShredLevel = true }
	elseif jobEnum == IAFieldwork.JobType.PLOW then
		return { groundType = true }
	elseif jobEnum == IAFieldwork.JobType.LIME then
		return { limeLevel = true }
	elseif jobEnum == IAFieldwork.JobType.STONE_PICKING then
		return { stoneLevel = true }
	elseif jobEnum == IAFieldwork.JobType.GRASS_MOWING then
		return { fruitTypeIndex = true, growthState = true }
	elseif jobEnum == IAFieldwork.JobType.HARVEST_DELIVER_CORN then
		return { fruitTypeIndex = true, growthState = true }
	elseif jobEnum == IAFieldwork.JobType.IA_FIELD_OUTCOME then
		return nil
	end
	return nil
end

--- Remove keys from `expected` that are not validated for this job (in-place).
function IAFieldwork.pruneExpectedFieldStateForValidation(expected, jobEnum)
	if expected == nil or type(expected) ~= "table" then
		return
	end
	local set = IAFieldwork.getValidationKeySetForOutcomeJob(jobEnum)
	if set == nil then
		return
	end
	local remove = {}
	for k in pairs(expected) do
		if not set[k] then
			table.insert(remove, k)
		end
	end
	for i = 1, #remove do
		expected[remove[i]] = nil
	end
end

--- Build the same FieldUpdateTask as IASituation:completeFieldwork / enqueueCompleteFieldworkFieldUpdate, without enqueueing.
--- Derived from `getExpectedFieldStateAfterJob` + `buildFieldUpdateTaskFromExpectedState` so task and preview state stay aligned.
--- Spray jobs force post-herbicide weed state after build (`buildFieldUpdateTaskFromExpectedState` may zero when weeds are disabled).
-- Caller adds it via g_fieldManager:addFieldUpdateTask (AbstractFieldMission:finishField) or enqueues explicitly.
-- @param table field
-- @param string jobType IAFieldwork.JobType.*
-- @param number|nil seedFruitTypeIndex for SEED
-- @param number|nil fertilizeSprayTypeIndex for fertilize-family jobs
-- @return FieldUpdateTask|nil
function IAFieldwork.buildFieldUpdateTaskForCompleteFieldwork(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	if field == nil or jobType == nil or FieldUpdateTask == nil or type(FieldUpdateTask.new) ~= "function" then
		return nil
	end
	local state = IAFieldwork.getExpectedFieldStateAfterJob(jobType, field, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	local hasAny = false
	for _ in pairs(state) do
		hasAny = true
		break
	end
	if not hasAny then
		return nil
	end
	local task = IAFieldwork.buildFieldUpdateTaskFromExpectedState(field, state)
	if task == nil then
		return nil
	end
	if jobType == IAFieldwork.JobType.SPRAY then
		task:setWeedState(IAFieldwork.getExpectedPostHerbicideWeedState())
	end
	return task
end

--- FieldUpdateTask applying numeric FieldState keys (aligned with IAHelper iaApplyFieldState task setup). Does not enqueue.
-- @param table state keys like fruitTypeIndex, growthState, groundType, sprayType, sprayLevel, …
-- @return FieldUpdateTask|nil
function IAFieldwork.buildFieldUpdateTaskFromExpectedState(field, state)
	if field == nil or state == nil or type(state) ~= "table" or FieldUpdateTask == nil or type(FieldUpdateTask.new) ~= "function" then
		return nil
	end
	local hasAny = false
	for _ in pairs(state) do
		hasAny = true
		break
	end
	if not hasAny then
		return nil
	end
	local task = FieldUpdateTask.new()
	task:setField(field)
	if field.getDensityMapPolygon ~= nil then
		task:setArea(field:getDensityMapPolygon())
	end
	if state.fruitTypeIndex ~= nil then
		task:setFruit(state.fruitTypeIndex, state.growthState or 1)
	end
	if state.groundType ~= nil then
		task:setGroundType(state.groundType)
	end
	local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
	if state.groundAngle ~= nil then
		task:setGroundAngle(-(state.groundAngle or 0))
	end
	if state.weedState ~= nil then
		task:setWeedState((missionInfo ~= nil and missionInfo.weedsEnabled) and state.weedState or 0)
	end
	if state.stoneLevel ~= nil then
		task:setStoneLevel((missionInfo ~= nil and missionInfo.stonesEnabled) and state.stoneLevel or 0)
	end
	if state.sprayType ~= nil then
		task:setSprayType(state.sprayType)
	end
	if state.sprayLevel ~= nil then
		task:setSprayLevel(state.sprayLevel)
	end
	if state.limeLevel ~= nil then
		task:setLimeLevel(state.limeLevel)
	end
	if state.plowLevel ~= nil then
		task:setPlowLevel(state.plowLevel)
	end
	if state.rollerLevel ~= nil then
		task:setRollerLevel(state.rollerLevel)
	end
	if state.stubbleShredLevel ~= nil then
		task:setStubbleShredLevel(state.stubbleShredLevel)
	end
	if state.clearHeightTypes == true then
		task:clearHeight()
	end
	task:resetDisplacement()
	task:clearTireTracks()
	return task
end

--- Apply the same field density update as IASituation:completeFieldwork (single source of truth).
-- @param table field
-- @param string jobType IAFieldwork.JobType.*
-- @param number|nil seedFruitTypeIndex for SEED
-- @param number|nil fertilizeSprayTypeIndex for fertilize-family jobs
function IAFieldwork.enqueueCompleteFieldworkFieldUpdate(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	local t = IAFieldwork.buildFieldUpdateTaskForCompleteFieldwork(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	if t ~= nil then
		t:enqueue(true)
	end
end

--- Day-rollover variant of buildFieldUpdateTaskForCompleteFieldwork.
--- Auto-completion of unworked scheduled fieldwork runs AFTER the calendar already advanced, so the
--- engine has applied a full day of growth (and withering). Compensate so the result matches what the
--- field would look like had the NPC done the work yesterday:
---   * SEED: a freshly-sown crop would have advanced one growth stage overnight, so bump growthState +1.
---   * HARVEST: getExpectedFieldStateAfterJob already derives the cut state from the field's current crop,
---     so a crop that withered overnight is still left in the harvested (cut) state.
-- @param table field
-- @param string jobType IAFieldwork.JobType.*
-- @param number|nil seedFruitTypeIndex for SEED
-- @param number|nil fertilizeSprayTypeIndex for fertilize-family jobs
-- @return FieldUpdateTask|nil
function IAFieldwork.buildFieldUpdateTaskForDayEndFieldwork(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	if field == nil or jobType == nil or FieldUpdateTask == nil or type(FieldUpdateTask.new) ~= "function" then
		return nil
	end
	local state = IAFieldwork.getExpectedFieldStateAfterJob(jobType, field, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	if jobType == IAFieldwork.JobType.SEED and state.growthState ~= nil then
		state.growthState = state.growthState + 1
	end
	local hasAny = false
	for _ in pairs(state) do
		hasAny = true
		break
	end
	if not hasAny then
		return nil
	end
	local task = IAFieldwork.buildFieldUpdateTaskFromExpectedState(field, state)
	if task == nil then
		return nil
	end
	if jobType == IAFieldwork.JobType.SPRAY then
		task:setWeedState(IAFieldwork.getExpectedPostHerbicideWeedState())
	end
	return task
end

--- Enqueue the day-rollover completion task (see buildFieldUpdateTaskForDayEndFieldwork).
-- @return boolean true when a task was enqueued
function IAFieldwork.enqueueCompleteFieldworkFieldUpdateForDayEnd(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	local t = IAFieldwork.buildFieldUpdateTaskForDayEndFieldwork(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
	if t ~= nil then
		t:enqueue(true)
		return true
	end
	return false
end

--- True when the job requires delivering harvest to the farm after fieldwork is done.
--- GRASS_MOWING: mow grass, then deliver it (bales or loose) to the farm.
--- HARVEST / HARVEST_DELIVER_CORN: harvest crop, then deliver grain to the farm.
--- @param string|nil jobType IAFieldwork.JobType.* after normalize
--- @return boolean
function IAFieldwork.isDeliveryRequiredJobType(jobType)
	if IAFieldwork.JobType == nil then
		return false
	end
	return jobType == IAFieldwork.JobType.GRASS_MOWING
		or jobType == IAFieldwork.JobType.HARVEST
		or jobType == IAFieldwork.JobType.HARVEST_DELIVER_CORN
end

--- True when the job type is only fieldwork (no delivery), using the existing probe system.
--- @param string|nil jobType IAFieldwork.JobType.* after normalize
--- @return boolean
function IAFieldwork.isFieldworkOnlyJobType(jobType)
	return jobType ~= nil
		and not IAFieldwork.isDeliveryRequiredJobType(jobType)
end

--------------------------------------------------------------------------------
-- Equipment availability checks for fieldwork scheduling
--------------------------------------------------------------------------------

--- Required vehicle types for a job type (used to check if a neighbour has the equipment).
--- Returns a table { vehicleTypes = {...}, attachmentCategories = {...} } or nil.
--- @param string|nil jobType IAFieldwork.JobType.* after normalize
--- @return table|nil
function IAFieldwork.getRequiredEquipmentForJob(jobType)
	if jobType == nil or IAFieldwork.JobType == nil then
		return nil
	end

	if jobType == IAFieldwork.JobType.CULTIVATE then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "cultivator" } }
	elseif jobType == IAFieldwork.JobType.HARROW then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "harrow", "cultivator" } }
	elseif jobType == IAFieldwork.JobType.PLOW then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "plow" } }
	elseif jobType == IAFieldwork.JobType.SEED then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "seeder", "sowingMachine", "sower", "planter" } }
	elseif jobType == IAFieldwork.JobType.HARVEST then
		return { vehicleTypes = { "harvester", "combine" }, attachmentCategories = { "cutter", "header", "grainHeader", "cornHeader" } }
	elseif jobType == IAFieldwork.JobType.SPRAY then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "sprayer", "fieldSprayer" } }
	elseif IAFieldwork.isFertilizeJobType(jobType) then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "spreader", "sprayer", "fertilizer" } }
	elseif jobType == IAFieldwork.JobType.LIME then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "spreader", "limeSpreader", "fertilizer" } }
	elseif jobType == IAFieldwork.JobType.STONE_PICKING then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "stonePicker", "stoneCollector" } }
	elseif jobType == IAFieldwork.JobType.GRASS_MOWING then
		return { vehicleTypes = { "tractor" }, attachmentCategories = { "mower", "forageWagon", "baler", "loaderWagon" } }
	elseif jobType == IAFieldwork.JobType.HARVEST_DELIVER_CORN then
		return { vehicleTypes = { "harvester", "combine" }, attachmentCategories = { "cutter", "header", "cornHeader", "grainHeader" } }
	elseif jobType == IAFieldwork.JobType.IA_FIELD_OUTCOME then
		return nil -- Generic; equipment varies.
	end
	return nil
end

--- True when the neighbour's fleet contains at least one vehicle/attachment matching the required equipment.
--- @param table|nil neighbour IANeighbour instance (must have .vehicles table)
--- @param string|nil jobType IAFieldwork.JobType.* after normalize
--- @return boolean
function IAFieldwork.neighbourHasFleetEquipmentForJobType(neighbour, jobType)
	if neighbour == nil or neighbour.vehicles == nil or jobType == nil then
		return false
	end
	local req = IAFieldwork.getRequiredEquipmentForJob(jobType)
	if req == nil then
		-- No specific equipment required (e.g. IA_FIELD_OUTCOME); treat as always available.
		return true
	end

	local hasVehicleType = false
	local hasAttachmentCategory = false

	for _, ia in pairs(neighbour.vehicles) do
		if ia ~= nil then
			-- Skip borrowed vehicles.
			if ia.isBorrowedByPlayer == true then
				-- Not counted as available fleet.
			else
				local vType = (ia.type ~= nil) and string.lower(tostring(ia.type)) or nil
				local vCat = (ia.category ~= nil) and string.lower(tostring(ia.category)) or nil

				-- Check vehicle type match.
				if not hasVehicleType and req.vehicleTypes ~= nil then
					for _, vt in ipairs(req.vehicleTypes) do
						local vtLower = string.lower(tostring(vt))
						if vType == vtLower then
							hasVehicleType = true
							break
						end
					end
				end

				-- Check attachment category match (both type="attachment" and main vehicles count).
				if not hasAttachmentCategory and req.attachmentCategories ~= nil and #req.attachmentCategories > 0 then
					for _, ac in ipairs(req.attachmentCategories) do
						local acLower = string.lower(tostring(ac))
						if vCat == acLower or vType == acLower then
							hasAttachmentCategory = true
							break
						end
					end
				end
			end
		end
	end

	-- A job needs at minimum the main vehicle type.
	-- Attachment is optional for some jobs (e.g. the neighbour might have a harvester without header).
	if not hasVehicleType then
		return false
	end
	-- For attachment-required jobs: also check attachment availability.
	if req.attachmentCategories ~= nil and #req.attachmentCategories > 0 and not hasAttachmentCategory then
		return false
	end
	return true
end

--- True when a job type can ONLY be offered as a player contract (equipment missing).
--- @param table|nil neighbour
--- @param string|nil jobType
--- @return boolean
function IAFieldwork.isJobTypeContractOnlyForNeighbour(neighbour, jobType)
	if not IAFieldwork.isDeliveryRequiredJobType(jobType) then
		-- Non-delivery jobs: contract-only if no equipment.
		return not IAFieldwork.neighbourHasFleetEquipmentForJobType(neighbour, jobType)
	end
	-- Delivery jobs: contract-only if missing the fieldwork implement.
	if not IAFieldwork.neighbourHasFleetEquipmentForJobType(neighbour, jobType) then
		return true
	end
	return false
end

--- Resolve the windrow fill type index for GRASS (cut grass swath on the ground).
--- Uses FillType.GRASS_WINDROW or falls back to fruitTypeManager mapping.
--- @return number|nil windrowFillTypeIndex, or nil if unresolvable
function IAFieldwork.getGrassWindrowFillTypeIndex()
	-- Primary: FillType.GRASS_WINDROW
	if FillType ~= nil and FillType.GRASS_WINDROW ~= nil then
		local idx = tonumber(FillType.GRASS_WINDROW)
		if idx ~= nil then
			return idx
		end
	end
	-- Fallback: resolve via fruit type manager windrow mapping
	local grassIndex = IAFieldwork.resolveFruitTypeNameOrIndex("GRASS")
	if grassIndex ~= nil
		and g_fruitTypeManager ~= nil
		and g_fruitTypeManager.fruitTypeIndexToWindrowFillTypeIndex ~= nil
	then
		local wfIdx = g_fruitTypeManager.fruitTypeIndexToWindrowFillTypeIndex[grassIndex]
		if wfIdx ~= nil then
			return tonumber(wfIdx)
		end
	end
	return nil
end

return IAFieldwork
