--
-- FS25 Fields of Stories - field outcome mission (phone contract).
-- Subclasses AbstractFieldMission so Field.currentMission / contracts UI bind like vanilla field work.
-- Completion: FieldState:update at vertex inset probes (IAHelper_getBorderInsetProbePoints) plus random interior samples (IAHelper_getRandomPointsInField); all must match expected keys.
-- Expected-vs-probe key matching (incl. fertilize spray equivalence) lives in IAFieldOutcomeMissionProbeEvaluator.lua (loaded after IAFieldwork in IANeighbours.lua).
-- Border probe count is capped (MAX_PROBES - MIN_INTERIOR_PROBE_SLOTS) so interior samples always get budget on large / high-vertex fields.
-- Persistence: phone field-outcome contracts are stored under IANeighbours_outbound.xml (fieldOutcomeMissions), not missions.xml.
--

IAFieldOutcomeMission = {}
IAFieldOutcomeMission.NAME = "iaFieldOutcomeMission"
IAFieldOutcomeMission.MAX_NUM_INSTANCES = 8
--- Reference $/ha for map XML `rewardPerHa` scaling (see `getRewardPerHa`). Job-specific bases below are tuned to this reference.
IAFieldOutcomeMission.DEFAULT_REWARD_PER_HA = 1800
--- Phone contracts: player uses own machines — pay band reflects labour/wear/fuel only, not full contractor hire.
--- Relative spread loosely follows UK NAAC-style 2024 guide £/ha ratios (e.g. combine vs disc harrow vs plough vs drilling),
--- compressed into FS money and ~55% of list-like contractor splits so totals stay playable vs old flat 1800.
IAFieldOutcomeMission.WORKER_ONLY_REWARD_PER_HA = {
	[IAFieldwork.JobType.HARROW] = 980,
	[IAFieldwork.JobType.CULTIVATE] = 1080,
	[IAFieldwork.JobType.PLOW] = 1380,
	[IAFieldwork.JobType.SEED] = 1200,
	[IAFieldwork.JobType.MANURESPREADING] = 1140,
	[IAFieldwork.JobType.SLURRYSPREADING] = 1140,
	[IAFieldwork.JobType.FERTILIZEDSPREADING] = 1140,
	[IAFieldwork.JobType.SPRAY] = 1000,
	[IAFieldwork.JobType.HARVEST] = 1980,
	[IAFieldwork.JobType.IA_FIELD_OUTCOME] = 860,
}
IAFieldOutcomeMission.WORKER_ONLY_REWARD_FALLBACK_PER_HA = 1100
--- Reward multipliers applied directly in resolveWorkerOnlyRewardPerHaFromJobRaw when the player borrows equipment.
IAFieldOutcomeMission.BORROW_REWARD_MULT_DEFAULT = 0.75
IAFieldOutcomeMission.BORROW_REWARD_MULT_CONSUMABLE = 0.55
--- How often `update` runs the full probe FieldState scan (all probe points). Lower = smoother HUD, higher = less CPU.
--- `iaRebuildProbePositions` still calls `iaSyncProbeEvaluation` once right after probes change.
IAFieldOutcomeMission.PROBE_CHECK_INTERVAL_MS = 15000
IAFieldOutcomeMission.NUM_INTERIOR_RANDOM = 24
--- Minimum slots reserved for interior random probes; border inset probes use at most MAX_PROBES minus this (capped by NUM_INTERIOR_RANDOM).
IAFieldOutcomeMission.MIN_INTERIOR_PROBE_SLOTS = 24
IAFieldOutcomeMission.MAX_PROBES = 64
IAFieldOutcomeMission.BORDER_INSET_MIN_M = 5
IAFieldOutcomeMission.BORDER_INSET_MAX_M = 10
--- Fraction of probes that must match expected FieldState for the mission to be considered finished.
--- Now read from IASettings (default 0.9 = 90%); user-configurable in game settings.
function IAFieldOutcomeMission.getProbeCompletionThreshold()
	return (IASettings.getFieldworkCompletionThreshold() or 90) / 100
end

-- Persisted on outbound fieldOutcomeMission rows (#<key>); order drives save + restore.
-- When MissionManager refuses startMission (e.g. another contract still PREPARING), entries are retried from processDeferredOutboundRestoreStarts.
IAFieldOutcomeMission._deferredOutboundRestoreStarts = {}

IAFieldOutcomeMission.OUTCOME_KEY_ORDER = {
	"fruitTypeIndex",
	"growthState",
	"weedState",
	"weedFactor",
	"stoneLevel",
	"groundType",
	"sprayLevel",
	"sprayType",
	"limeLevel",
	"rollerLevel",
	"plowLevel",
	"stubbleShredLevel",
	"waterLevel",
}

-- Stable sprayType log labels (pairs() order on FieldSprayType is random).
IAFieldOutcomeMission.SPRAY_TYPE_LOG_ORDER = {
	"NONE",
	"FERTILIZER",
	"LIQUID_MANURE",
	"MANURE",
	"LIME",
	"WEED",
	"HERBICIDE",
}

--- Set true for extra probe logs in addition to `IANeighbours.debug` (see `iaDbg`).
IAFieldOutcomeMission.DEBUG_COMPLETION = false

local IAFieldOutcomeMission_mt = Class(IAFieldOutcomeMission, AbstractFieldMission)
InitObjectClass(IAFieldOutcomeMission, "IAFieldOutcomeMission")

--- Static i18n keys for jobs where label/equipment do not depend on crop or fertilize subtype.
local PLAIN_JOB_LABEL_KEY = {
	[IAFieldwork.JobType.CULTIVATE] = "ia_fieldwork_label_cultivate",
	[IAFieldwork.JobType.HARROW] = "ia_fieldwork_label_harrow",
	[IAFieldwork.JobType.HARVEST] = "ia_fieldwork_label_harvest",
	[IAFieldwork.JobType.SPRAY] = "ia_fieldwork_label_spray",
	[IAFieldwork.JobType.PLOW] = "ia_fieldwork_label_plow",
}
local PLAIN_JOB_EQUIP_KEY = {
	[IAFieldwork.JobType.CULTIVATE] = "ia_fieldwork_equip_cultivate",
	[IAFieldwork.JobType.HARROW] = "ia_fieldwork_equip_harrow",
	[IAFieldwork.JobType.HARVEST] = "ia_fieldwork_equip_harvest",
	[IAFieldwork.JobType.SPRAY] = "ia_fieldwork_equip_herbicide",
	[IAFieldwork.JobType.SEED] = "ia_fieldwork_equip_seed",
	[IAFieldwork.JobType.PLOW] = "ia_fieldwork_equip_plow",
}

--------------------------------------------------------------------------------
-- Internal helpers on IAFieldOutcomeMission (static `.` or instance `:`).
--------------------------------------------------------------------------------

function IAFieldOutcomeMission.iaDbg()
	return IAFieldOutcomeMission.DEBUG_COMPLETION == true or (IANeighbours ~= nil and IANeighbours.debug == true)
end

function IAFieldOutcomeMission.iaLog(msg)
	if not IAFieldOutcomeMission.iaDbg() then
		return
	end
	print(string.format("[IAFieldOutcomeMission] %s", tostring(msg)))
end

function IAFieldOutcomeMission.iaOutcomeSummary(t)
	if t == nil or type(t) ~= "table" then
		return "{}"
	end
	local keys = IAHelper_sortedMapKeys(t)
	if #keys == 0 then
		return "{}"
	end
	local parts = {}
	for i = 1, math.min(16, #keys) do
		local k = keys[i]
		table.insert(parts, string.format("%s=%s", k, tostring(t[k])))
	end
	if #keys > 16 then
		table.insert(parts, string.format("...+%d", #keys - 16))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function IAFieldOutcomeMission.iaSprayTypeAnnotate(idx)
	if idx == nil then
		return "nil"
	end
	if FieldSprayType == nil or type(FieldSprayType.getValueByType) ~= "function" then
		return tostring(idx)
	end
	local order = IAFieldOutcomeMission.SPRAY_TYPE_LOG_ORDER
	local hits = {}
	for _, key in ipairs(order) do
		local typ = FieldSprayType[key]
		if typ ~= nil and type(typ) ~= "function" then
			local ok, v = pcall(FieldSprayType.getValueByType, typ)
			if ok and v ~= nil and tonumber(v) == tonumber(idx) then
				table.insert(hits, key)
			end
		end
	end
	if #hits > 0 then
		return string.format("%s(%s)", tostring(idx), table.concat(hits, "|"))
	end
	for key, typ in pairs(FieldSprayType) do
		if type(key) == "string" and typ ~= nil and type(typ) ~= "function" then
			local known = false
			for i = 1, #order do
				if order[i] == key then
					known = true
					break
				end
			end
			if not known then
				local ok, v = pcall(FieldSprayType.getValueByType, typ)
				if ok and v ~= nil and tonumber(v) == tonumber(idx) then
					return string.format("%s(%s)", tostring(idx), key)
				end
			end
		end
	end
	return tostring(idx)
end

function IAFieldOutcomeMission.iaFruitIndexAnnotate(idx)
	if idx == nil then
		return "nil"
	end
	if g_fruitTypeManager == nil or type(g_fruitTypeManager.getFruitTypeByIndex) ~= "function" then
		return tostring(idx)
	end
	local ok, ft = pcall(g_fruitTypeManager.getFruitTypeByIndex, g_fruitTypeManager, idx)
	if ok and ft ~= nil and ft.name ~= nil and tostring(ft.name) ~= "" then
		return string.format("%s(%s)", tostring(idx), tostring(ft.name))
	end
	return tostring(idx)
end

--- Readable crop label for mission UI. Uses engine fill-type titles only (no mod `fillType_*` lookups — those log missing FILLTYPE_* if absent from active l10n).
function IAFieldOutcomeMission.iaFruitTypeDisplayTitle(fruitTypeIndex)
	if fruitTypeIndex == nil or g_fruitTypeManager == nil or type(g_fruitTypeManager.getFruitTypeByIndex) ~= "function" then
		return nil
	end
	local ok, ft = pcall(g_fruitTypeManager.getFruitTypeByIndex, g_fruitTypeManager, fruitTypeIndex)
	if not ok or ft == nil then
		return nil
	end

	-- Resolve a fill type index for this fruit type so we can use the engine's
	-- localized fill-type title (e.g. German "Raps" instead of the raw fruit
	-- name "CANOLA"). FS25 stores the associated fill type on the fruit desc as
	-- `fillType` (a FillTypeDesc); some shapes also expose a `fillTypes` array.
	-- As a last resort, ask the manager to map fruit index -> fill index.
	local fillIdx = nil

	-- 1) fruitTypeDesc.fillType (FillTypeDesc table or numeric index)
	if ft.fillType ~= nil then
		if type(ft.fillType) == "table" then
			fillIdx = ft.fillType.index or ft.fillType.fillTypeIndex
		elseif type(ft.fillType) == "number" then
			fillIdx = ft.fillType
		end
	end

	-- 2) fruitTypeDesc.fillTypes (array of FillTypeDesc tables or numeric indices)
	if fillIdx == nil and ft.fillTypes ~= nil then
		local first = ft.fillTypes[1]
		if type(first) == "table" then
			fillIdx = first.fillTypeIndex or first.index
		elseif type(first) == "number" then
			fillIdx = first
		end
	end

	-- 3) manager mapping fruitTypeIndex -> fillTypeIndex
	if fillIdx == nil and type(g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex) == "function" then
		local okMap, mapped = pcall(g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex, g_fruitTypeManager, fruitTypeIndex)
		if okMap and mapped ~= nil then
			fillIdx = mapped
		end
	end

	IAprintDebug(
		"iaFruitTypeDisplayTitle",
		string.format(
			"fruitTypeIndex=%s name=%s fillIdx=%s (ft.fillType=%s ft.fillTypes=%s)",
			tostring(fruitTypeIndex), tostring(ft.name), tostring(fillIdx),
			tostring(ft.fillType), tostring(ft.fillTypes)
		),
		nil, nil, nil
	)

	if fillIdx ~= nil and g_fillTypeManager ~= nil and type(g_fillTypeManager.getFillTypeTitleByIndex) == "function" then
		local ok2, title = pcall(g_fillTypeManager.getFillTypeTitleByIndex, g_fillTypeManager, fillIdx)
		if ok2 and title ~= nil and tostring(title) ~= "" then
			IAprintDebug("iaFruitTypeDisplayTitle", "resolved localized fill title: " .. tostring(title), nil, nil, nil)
			return tostring(title)
		end
	end

	-- Direct FillTypeDesc title (table form), in case the manager lookup failed.
	if type(ft.fillType) == "table" and ft.fillType.title ~= nil and tostring(ft.fillType.title) ~= "" then
		IAprintDebug("iaFruitTypeDisplayTitle", "resolved localized fill title (desc.title): " .. tostring(ft.fillType.title), nil, nil, nil)
		return tostring(ft.fillType.title)
	end

	IAprintDebug("iaFruitTypeDisplayTitle", "FALLBACK to raw fruit name (no localized fill title found)", nil, nil, nil)

	if g_fruitTypeManager.getFruitTypeNameByIndex ~= nil then
		local ok3, name = pcall(g_fruitTypeManager.getFruitTypeNameByIndex, g_fruitTypeManager, fruitTypeIndex)
		if ok3 and name ~= nil and tostring(name) ~= "" then
			return IAFieldOutcomeMission.iaPrettyRawJob(string.lower(tostring(name)))
		end
	end
	if ft.name ~= nil and tostring(ft.name) ~= "" then
		return IAFieldOutcomeMission.iaPrettyRawJob(string.lower(tostring(ft.name)))
	end
	return nil
end

function IAFieldOutcomeMission.iaFormatStateForExpectedKeys(exp, state)
	if exp == nil then
		return "expected=nil"
	end
	if state == nil then
		return "FieldState_sample=nil"
	end
	local keys = IAHelper_sortedMapKeys(exp)
	if #keys < 1 then
		return "{}"
	end
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		local a = state[k]
		local av = tostring(a)
		if k == "sprayType" then
			av = IAFieldOutcomeMission.iaSprayTypeAnnotate(a)
		elseif k == "fruitTypeIndex" then
			av = IAFieldOutcomeMission.iaFruitIndexAnnotate(a)
		end
		table.insert(parts, string.format("%s=%s", k, av))
	end
	return table.concat(parts, ", ")
end

function IAFieldOutcomeMission:iaDebugFieldPreamble(totalProbes, nVertex, nInterior)
	local chunks = {}
	local field = self:iaResolveField()
	if field ~= nil and field.name ~= nil and tostring(field.name) ~= "" then
		table.insert(chunks, string.format('field="%s"', tostring(field.name)))
	end
	if self.iaFieldFarmlandId ~= nil then
		table.insert(chunks, string.format("farmlandId=%s", tostring(self.iaFieldFarmlandId)))
	end
	if self.iaFoSFieldworkJob ~= nil and tostring(self.iaFoSFieldworkJob) ~= "" then
		table.insert(chunks, string.format("job=%s", tostring(self.iaFoSFieldworkJob)))
	end
	table.insert(
		chunks,
		string.format("probes total=%d vertex=%d interior=%d", totalProbes or 0, nVertex or 0, nInterior or 0)
	)
	return table.concat(chunks, " | ")
end

function IAFieldOutcomeMission.iaFormatMissHistogram(missCounts)
	if missCounts == nil then
		return ""
	end
	local keys = {}
	for k, c in pairs(missCounts) do
		if type(k) == "string" and (c or 0) > 0 then
			table.insert(keys, k)
		end
	end
	if #keys < 1 then
		return ""
	end
	table.sort(keys, function(a, b)
		local ca = missCounts[a] or 0
		local cb = missCounts[b] or 0
		if ca ~= cb then
			return ca > cb
		end
		return a < b
	end)
	local parts = {}
	for i = 1, math.min(10, #keys) do
		local k = keys[i]
		table.insert(parts, string.format("%s:%d", k, missCounts[k] or 0))
	end
	local s = "firstKeyMismatch_counts " .. table.concat(parts, ", ")
	if #keys > 10 then
		s = s .. string.format(" ...+%d", #keys - 10)
	end
	return s
end

function IAFieldOutcomeMission.iaPrettyRawJob(s)
	local nicer = tostring(s):gsub("_", " ")
	if nicer:len() > 0 then
		local first = nicer:sub(1, 1):upper()
		return first .. nicer:sub(2)
	end
	return nicer
end

function IAFieldOutcomeMission:iaJobDisplayLabel(raw, expectedFieldState)
	if raw == nil or raw == "" then
		return nil
	end
	local s = tostring(raw)
	if g_i18n == nil then
		return IAFieldOutcomeMission.iaPrettyRawJob(s)
	end
	if IAFieldwork ~= nil and IAFieldwork.JobType ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" then
		local jt = IAFieldwork.normalizeFieldworkJobType(s)
		if jt == IAFieldwork.JobType.SLURRYSPREADING then
			return g_i18n:getText("ia_fieldwork_label_slurry")
		end
		if jt == IAFieldwork.JobType.MANURESPREADING then
			return g_i18n:getText("ia_fieldwork_label_manure")
		end
		if jt == IAFieldwork.JobType.FERTILIZEDSPREADING then
			return g_i18n:getText("ia_fieldwork_label_fertilize_mineral")
		end
		if jt == IAFieldwork.JobType.HARROW then
			IAprintDebug("iaJobDisplayLabel", "harrow: "..g_i18n:getText("ia_fieldwork_label_harrow"), nil, nil, nil)
			return g_i18n:getText("ia_fieldwork_label_harrow")
		end
		if jt == IAFieldwork.JobType.SEED then
			local crop = IAFieldOutcomeMission.iaFruitTypeDisplayTitle(expectedFieldState ~= nil and expectedFieldState.fruitTypeIndex or nil)
			if crop ~= nil and crop ~= "" then
				return string.format(g_i18n:getText("ia_fieldwork_label_seed_with_crop"), crop)
			end
			return g_i18n:getText("ia_fieldwork_label_seed")
		end
		if jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
			return g_i18n:getText("ia_fieldwork_label_condition")
		end
		local lk = jt ~= nil and PLAIN_JOB_LABEL_KEY[jt] or nil
		if lk ~= nil then
			return g_i18n:getText(lk)
		end
	end
	return IAFieldOutcomeMission.iaPrettyRawJob(s)
end

function IAFieldOutcomeMission:iaEquipmentHint(raw, expectedFieldState)
	if g_i18n == nil then
		return ""
	end
	if raw == nil or raw == "" then
		return g_i18n:getText("ia_fieldwork_equip_generic")
	end
	local s = tostring(raw)
	if IAFieldwork ~= nil and IAFieldwork.JobType ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" then
		local jt = IAFieldwork.normalizeFieldworkJobType(s)
		if jt == IAFieldwork.JobType.SLURRYSPREADING then
			return g_i18n:getText("ia_fieldwork_equip_slurry")
		end
		if jt == IAFieldwork.JobType.MANURESPREADING then
			return g_i18n:getText("ia_fieldwork_equip_manure")
		end
		if jt == IAFieldwork.JobType.FERTILIZEDSPREADING then
			return g_i18n:getText("ia_fieldwork_equip_mineral_fertilizer")
		end
		if jt == IAFieldwork.JobType.HARROW then
			return g_i18n:getText("ia_fieldwork_equip_harrow")
		end
		if jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
			return g_i18n:getText("ia_fieldwork_equip_generic")
		end
		local ek = jt ~= nil and PLAIN_JOB_EQUIP_KEY[jt] or nil
		if ek ~= nil then
			return g_i18n:getText(ek)
		end
	end
	return g_i18n:getText("ia_fieldwork_equip_generic")
end

function IAFieldOutcomeMission:iaTargetSubtitle()
	if self == nil or self.iaExpectedFieldState == nil or g_i18n == nil then
		return ""
	end
	local exp = self.iaExpectedFieldState
	local raw = self.iaFoSFieldworkJob
	if raw == nil or IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return ""
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(raw))
	if IAFieldwork.isFertilizeJobType(jt) then
		local sl = exp.sprayLevel
		if sl == nil then
			sl = 1
		end
		local n = tonumber(sl) or sl
		if jt == IAFieldwork.JobType.SLURRYSPREADING then
			return string.format(g_i18n:getText("ia_field_outcome_target_slurry"), n)
		end
		if jt == IAFieldwork.JobType.MANURESPREADING then
			return string.format(g_i18n:getText("ia_field_outcome_target_manure"), n)
		end
		return string.format(g_i18n:getText("ia_field_outcome_target_fertilizer"), n)
	end
	if jt == IAFieldwork.JobType.SPRAY then
		return g_i18n:getText("ia_field_outcome_target_herbicide")
	end
	if jt == IAFieldwork.JobType.SEED then
		local crop = IAFieldOutcomeMission.iaFruitTypeDisplayTitle(exp.fruitTypeIndex)
		if crop ~= nil and crop ~= "" then
			return string.format(g_i18n:getText("ia_field_outcome_target_seed"), crop)
		end
	end
	return ""
end

function IAFieldOutcomeMission:iaMergeFoSContext(context)
	if context == nil then
		return
	end
	local rawJob = context.fieldworkRaw or context.fieldworkJob
	if rawJob ~= nil and tostring(rawJob) ~= "" then
		self.iaFoSFieldworkJob = tostring(rawJob)
	end
	local nf = context.neighbourFirstName
	if nf ~= nil and tostring(nf) ~= "" then
		self.iaFoSNeighbourFirstName = tostring(nf)
	end
	local nid = tonumber(context.neighbourId)
	if nid ~= nil and nid > 0 then
		self.iaFoSNeighbourId = nid
	end
	-- iaFoSSituationId: schedule-row identity (combined with iaFieldFarmlandId) so
	-- IAGameLoopHelper:applyAcceptedContractMissionEndToSchedule can locate the source
	-- row on finish/cancel/fail and update its acceptedByPlayer flag.
	local sid = context.situationId
	if sid ~= nil and tostring(sid) ~= "" then
		self.iaFoSSituationId = tostring(sid)
	end
	if context.usesBorrowedEquipment == true then
		self.iaFoSUsesBorrowedEquipment = true
	end
end

--- Probe completion only compares FieldState keys the job can change (see IAFieldwork.getValidationKeySetForOutcomeJob).
function IAFieldOutcomeMission:iaPruneExpectedFieldStateForJobType()
	if self.iaExpectedFieldState == nil or IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return
	end
	if type(IAFieldwork.pruneExpectedFieldStateForValidation) ~= "function" then
		return
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(self.iaFoSFieldworkJob or ""))
	IAFieldwork.pruneExpectedFieldStateForValidation(self.iaExpectedFieldState, jt)
end

function IAFieldOutcomeMission.iaEnableWorkAreaTypeByEnumName(out, enumName)
	if WorkAreaType == nil or enumName == nil then
		return
	end
	local idx = WorkAreaType[enumName]
	if idx ~= nil then
		out[idx] = true
	end
end

function IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, names)
	if names == nil then
		return
	end
	for i = 1, #names do
		IAFieldOutcomeMission.iaEnableWorkAreaTypeByEnumName(out, names[i])
	end
end

--- AbstractFieldMission:setField sets progressTitle from self.title; refresh after title changes.
function IAFieldOutcomeMission:iaSyncProgressTitle(field)
	field = field or self.field
	if field == nil or g_i18n == nil or self.title == nil then
		return
	end
	if type(field.getId) ~= "function" then
		return
	end
	local ok, fieldId = pcall(field.getId, field)
	if ok and fieldId ~= nil then
		self.progressTitle = string.format(
			"%s (%s %d)",
			self.title,
			g_i18n:getText("contract_details_field"),
			fieldId
		)
	end
end

function IAFieldOutcomeMission.iaProbeMismatchAnnotators()
	return {
		sprayType = IAFieldOutcomeMission.iaSprayTypeAnnotate,
		fruitTypeIndex = IAFieldOutcomeMission.iaFruitIndexAnnotate,
	}
end

--- After registerMission: run startMission; optionally updateMissions(0). @return true if mission left CREATED.
-- @param boolean runPostUpdate When false, skip updateMissions (required when called from processDeferredOutboundRestoreStarts — otherwise updateMissions re-enters the appended hook and overflows the stack).
function IAFieldOutcomeMission.tryStartAfterRegister(mission, farmId, spawnVehicles, runPostUpdate)
	if g_missionManager == nil or mission == nil or farmId == nil then
		return false
	end
	if runPostUpdate == nil then
		runPostUpdate = true
	end
	local ok, res = pcall(g_missionManager.startMission, g_missionManager, mission, farmId, spawnVehicles == true)
	-- When no vehicles are spawned, the engine sets PREPARING but the async vehicle
	-- spawn never completes, so the mission stays PREPARING indefinitely. This blocks
	-- subsequent startMission calls in the same batch (bundled phone contracts),
	-- because vanilla refuses all new starts while any mission is PREPARING.
	-- Force PREPARING -> RUNNING immediately for vehicle-less missions.
	if ok and res == (MissionStartState ~= nil and MissionStartState.OK or 0) and not spawnVehicles then
		if MissionStatus ~= nil and mission.status == MissionStatus.PREPARING then
			mission.status = MissionStatus.RUNNING
		end
	end
	if runPostUpdate and g_missionManager.updateMissions ~= nil then
		g_missionManager:updateMissions(0)
	end
	if not ok then
		if runPostUpdate then
			IAFieldOutcomeMission.iaLog("startMission pcall failed: " .. tostring(res))
		end
		return false
	end
	-- MissionStartState: OK means started; other values (often small integers e.g. 5) mean "refused" (another mission PREPARING, limit reached, etc.). Deferred retries would log every frame — only log on synchronous attempts.
	if MissionStartState ~= nil and MissionStartState.OK ~= nil and res ~= nil and res ~= MissionStartState.OK then
		if runPostUpdate then
			IAFieldOutcomeMission.iaLog(
				string.format(
					"startMission returned %s (not OK; mission still CREATED=%s). Engine is blocking start — often another field contract is PREPARING/RUNNING; will retry from deferred queue.",
					tostring(res),
					tostring(mission.status == MissionStatus.CREATED)
				)
			)
		end
		return mission.status ~= MissionStatus.CREATED
	end
	return mission.status ~= MissionStatus.CREATED
end

function IAFieldOutcomeMission.queueDeferredStartIfStillCreated(mission, farmId, spawnVehicles)
	if mission == nil or mission.status ~= MissionStatus.CREATED or farmId == nil then
		return
	end
	table.insert(IAFieldOutcomeMission._deferredOutboundRestoreStarts, {
		mission = mission,
		farmId = farmId,
		spawnVehicles = spawnVehicles == true,
		attempts = 0,
	})
end

--- Phone accept + savegame restore: start now, or queue until MissionManager allows it.
function IAFieldOutcomeMission.tryStartAfterRegisterOrDefer(mission, farmId, spawnVehicles)
	if IAFieldOutcomeMission.tryStartAfterRegister(mission, farmId, spawnVehicles) then
		return
	end
	IAFieldOutcomeMission.queueDeferredStartIfStillCreated(mission, farmId, spawnVehicles)
end

function IAFieldOutcomeMission.processDeferredOutboundRestoreStarts()
	if g_server == nil or g_missionManager == nil then
		return
	end
	if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer() then
		return
	end
	local list = IAFieldOutcomeMission._deferredOutboundRestoreStarts
	if list == nil or #list == 0 then
		return
	end
	local entry = list[1]
	local m = entry ~= nil and entry.mission or nil
	if m == nil then
		table.remove(list, 1)
		return
	end
	if m.status ~= MissionStatus.CREATED then
		table.remove(list, 1)
		return
	end
	entry.attempts = (entry.attempts or 0) + 1
	if IAFieldOutcomeMission.tryStartAfterRegister(m, entry.farmId, entry.spawnVehicles, false) then
		table.remove(list, 1)
	elseif IAFieldOutcomeMission.iaDbg() and (entry.attempts == 1 or entry.attempts % 600 == 1) then
		IAFieldOutcomeMission.iaLog(
			string.format(
				"deferred start pending #%d farmlandId=%s status=%s (startMission often returns non-OK until MissionManager allows another active field mission)",
				entry.attempts,
				tostring(m.iaFieldFarmlandId),
				tostring(m.status)
			)
		)
	end
end

--- Register savegame paths on MissionManager schemas only (legacy saves that still contain iaFieldOutcomeMission in missions.xml).
function IAFieldOutcomeMission.ensureSavegameSchemaRegistered(xmlFile)
	local function iaInstallMissionLoadSchemaHookOnce()
		if MissionManager == nil or MissionManager.loadFromXMLFile == nil or IAFieldOutcomeMission._missionManagerLoadFromXmlPrepended then
			return
		end
		IAFieldOutcomeMission._missionManagerLoadFromXmlPrepended = true
		MissionManager.loadFromXMLFile = Utils.prependedFunction(MissionManager.loadFromXMLFile, function(...)
			IAFieldOutcomeMission.ensureSavegameSchemaRegistered()
		end)
	end
	iaInstallMissionLoadSchemaHookOnce()
	local schemas = {}
	local function add(s)
		if s ~= nil then
			schemas[#schemas + 1] = s
		end
	end
	if MissionManager ~= nil then
		add(MissionManager.xmlSchemaSavegame)
	end
	if g_missionManager ~= nil then
		add(g_missionManager.xmlSchemaSavegame)
	end
	if xmlFile ~= nil and xmlFile.xmlSchema ~= nil then
		add(xmlFile.xmlSchema)
	end
	if #schemas == 0 then
		return
	end
	local maxInst = IAFieldOutcomeMission.MAX_NUM_INSTANCES or 8
	if g_missionManager ~= nil and g_missionManager.getMissionTypeDataByName ~= nil then
		local data = g_missionManager:getMissionTypeDataByName(IAFieldOutcomeMission.NAME)
		if data ~= nil and data.maxNumInstances ~= nil then
			maxInst = math.max(1, math.floor(data.maxNumInstances))
		end
	end
	for si = 1, #schemas do
		local schema = schemas[si]
		for i = 0, maxInst - 1 do
			local key = string.format("missions.%s(%d)", IAFieldOutcomeMission.NAME, i)
			local ok, err = pcall(function()
				IAFieldOutcomeMission.registerSavegameXMLPaths(schema, key)
			end)
			if not ok then
				print(string.format("[IAFieldOutcomeMission] registerSavegameXMLPaths failed key=%s err=%s", key, tostring(err)))
			end
		end
	end
end

--- Rows read from IANeighbours_outbound.xml fieldOutcomeMissions (internal).
IAFieldOutcomeMission._restoreQueue = {}

function IAFieldOutcomeMission.queueRestoreFromOutboundXml(xmlFile, rootKey)
	IAFieldOutcomeMission._restoreQueue = {}
	if xmlFile == nil or rootKey == nil or hasXMLProperty == nil then
		return
	end
	local i = 0
	while true do
		local key = rootKey .. ".fieldOutcomeMissions.fieldOutcomeMission(" .. i .. ")"
		if not hasXMLProperty(xmlFile, key) then
			break
		end
		local farmlandId = getXMLInt(xmlFile, key .. "#farmlandId", 0)
		local fj = getXMLString(xmlFile, key .. "#fieldworkJob", "")
		if fj == nil or fj == "" then
			fj = nil
		end
		local nn = getXMLString(xmlFile, key .. "#neighbourFirstName", "")
		if nn == nil or nn == "" then
			nn = nil
		end
		local usesBorrow = getXMLBool(xmlFile, key .. "#usesBorrowedEquipment", false)
		local spawnVehicles = getXMLBool(xmlFile, key .. "#spawnVehicles", false)
		if not usesBorrow and spawnVehicles then
			usesBorrow = true
		end
		local borrowSessionId = getXMLString(xmlFile, key .. "#borrowSessionId", "")
		if borrowSessionId == "" then
			borrowSessionId = nil
		end
		local neighbourId = getXMLInt(xmlFile, key .. "#neighbourId", 0)
		if neighbourId ~= nil and neighbourId <= 0 then
			neighbourId = nil
		end
		local situationId = getXMLString(xmlFile, key .. "#situationId", "")
		if situationId == nil or situationId == "" then
			situationId = nil
		end
		local row = {
			farmlandId = farmlandId,
			farmId = getXMLInt(xmlFile, key .. "#farmId", 0),
			status = getXMLInt(xmlFile, key .. "#status", 0),
			spawnVehicles = spawnVehicles,
			usesBorrowedEquipment = usesBorrow,
			borrowSessionId = borrowSessionId,
			neighbourId = neighbourId,
			situationId = situationId,
			fieldworkJob = fj,
			neighbourFirstName = nn,
			expected = {},
		}
		for _, attr in ipairs(IAFieldOutcomeMission.OUTCOME_KEY_ORDER) do
			if hasXMLProperty(xmlFile, key .. "#" .. attr) then
				row.expected[attr] = getXMLInt(xmlFile, key .. "#" .. attr, 0)
			end
		end
		if farmlandId ~= nil and farmlandId > 0 then
			table.insert(IAFieldOutcomeMission._restoreQueue, row)
		end
		i = i + 1
	end
end

--- Append active FoS phone field-outcome missions to outbound XML (setXML* API).
function IAFieldOutcomeMission.appendOutboundFieldOutcomeMissionsXml(xmlFile)
	if xmlFile == nil or g_missionManager == nil or g_missionManager.missions == nil then
		return
	end
	local idx = 0
	for _, mission in ipairs(g_missionManager.missions) do
		if mission ~= nil and mission.iaFieldsOfStoriesMission == true and mission.getMissionTypeName ~= nil then
			local okName, typeName = pcall(mission.getMissionTypeName, mission)
			if okName and typeName == IAFieldOutcomeMission.NAME and mission.status ~= MissionStatus.FINISHED then
				local base = string.format("IANeighboursOutbound.fieldOutcomeMissions.fieldOutcomeMission(%d)", idx)
				setXMLInt(xmlFile, base .. "#farmlandId", mission.iaFieldFarmlandId or 0)
				setXMLInt(xmlFile, base .. "#farmId", mission.farmId or 0)
				if mission.status ~= nil then
					setXMLInt(xmlFile, base .. "#status", mission.status)
				end
				setXMLBool(xmlFile, base .. "#spawnVehicles", mission.iaFoSRestoreSpawnVehicles == true)
				setXMLBool(xmlFile, base .. "#usesBorrowedEquipment", mission.iaFoSUsesBorrowedEquipment == true)
				if mission.iaFoSMissionBorrowSessionId ~= nil and tostring(mission.iaFoSMissionBorrowSessionId) ~= "" then
					setXMLString(xmlFile, base .. "#borrowSessionId", tostring(mission.iaFoSMissionBorrowSessionId))
				end
				if mission.iaFoSNeighbourId ~= nil then
					setXMLInt(xmlFile, base .. "#neighbourId", tonumber(mission.iaFoSNeighbourId) or 0)
				end
				if mission.iaFoSSituationId ~= nil and tostring(mission.iaFoSSituationId) ~= "" then
					setXMLString(xmlFile, base .. "#situationId", tostring(mission.iaFoSSituationId))
				end
				if mission.iaFoSFieldworkJob ~= nil and tostring(mission.iaFoSFieldworkJob) ~= "" then
					setXMLString(xmlFile, base .. "#fieldworkJob", tostring(mission.iaFoSFieldworkJob))
				end
				if mission.iaFoSNeighbourFirstName ~= nil and tostring(mission.iaFoSNeighbourFirstName) ~= "" then
					setXMLString(xmlFile, base .. "#neighbourFirstName", tostring(mission.iaFoSNeighbourFirstName))
				end
				for _, attr in ipairs(IAFieldOutcomeMission.OUTCOME_KEY_ORDER) do
					local v = mission.iaExpectedFieldState ~= nil and mission.iaExpectedFieldState[attr] or nil
					if v ~= nil and type(v) == "number" then
						setXMLInt(xmlFile, base .. "#" .. attr, v)
					end
				end
				idx = idx + 1
			end
		end
	end
end

--- Re-register missions from outbound after career load (server only).
function IAFieldOutcomeMission.tryApplyOutboundRestoreAfterLoad()
	if g_server == nil or g_missionManager == nil or g_currentMission == nil or g_currentMission.missionInfo == nil then
		return
	end
	if g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer() then
		return
	end
	local dir = g_currentMission.missionInfo.savegameDirectory
	if dir == nil then
		return
	end
	local path = dir .. "/IANeighbours_outbound.xml"
	IAFieldOutcomeMission._deferredOutboundRestoreStarts = {}
	if fileExists(path) then
		local xf = loadXMLFile("IANeighboursFoSFieldOutcome", path)
		if xf ~= nil then
			IAFieldOutcomeMission.queueRestoreFromOutboundXml(xf, "IANeighboursOutbound")
			delete(xf)
		end
	end
	local queue = IAFieldOutcomeMission._restoreQueue or {}
	-- Prefer missions that were already active so MissionManager ordering matches a running session.
	table.sort(queue, function(a, b)
		local function prio(st)
			if st == MissionStatus.RUNNING or st == MissionStatus.PREPARING then
				return 0
			end
			if st == MissionStatus.CREATED then
				return 1
			end
			return 2
		end
		local pa, pb = prio(a.status), prio(b.status)
		if pa ~= pb then
			return pa < pb
		end
		return (a.farmlandId or 0) < (b.farmlandId or 0)
	end)
	local borrowRestoreByNeighbour = {}
	for _, row in ipairs(queue) do
		local nExpected = 0
		if row.expected ~= nil then
			for _ in pairs(row.expected) do
				nExpected = nExpected + 1
			end
		end
		if nExpected < 1 then
			-- initFromField needs a non-empty expected FieldState table
		elseif row.farmlandId ~= nil and row.farmlandId > 0 and row.status ~= MissionStatus.FINISHED and g_farmlandManager ~= nil then
			local farmland = g_farmlandManager:getFarmlandById(row.farmlandId)
			local field = nil
			if farmland ~= nil and farmland.getField ~= nil then
				local okF, f = pcall(farmland.getField, farmland)
				if okF then
					field = f
				end
			end
			if field ~= nil and field.currentMission == nil then
				local mission = IAFieldOutcomeMission.new(true, g_client ~= nil)
				if not mission:initFromField(field, row.expected, {
					fieldworkJob = row.fieldworkJob,
					neighbourFirstName = row.neighbourFirstName,
					neighbourId = row.neighbourId,
					situationId = row.situationId,
					usesBorrowedEquipment = row.usesBorrowedEquipment == true,
				}) then
					mission:delete()
				else
					mission.iaFieldsOfStoriesMission = true
					mission.iaFoSRestoreSpawnVehicles = row.spawnVehicles == true
					if row.neighbourId ~= nil then
						mission.iaFoSNeighbourId = row.neighbourId
					end
					if row.situationId ~= nil and tostring(row.situationId) ~= "" then
						mission.iaFoSSituationId = tostring(row.situationId)
					end
					if row.usesBorrowedEquipment == true then
						mission.iaFoSUsesBorrowedEquipment = true
						mission.iaFoSMissionBorrowSessionId = row.borrowSessionId
					end
					if row.farmId ~= nil and row.farmId > 0 then
						mission.farmId = row.farmId
					end
					local missionType = g_missionManager:getMissionType(IAFieldOutcomeMission.NAME)
					if missionType ~= nil then
						g_missionManager:registerMission(mission, missionType)
						local shouldStart = row.status == MissionStatus.RUNNING
							or row.status == MissionStatus.PREPARING
							or row.status == MissionStatus.CREATED
						if shouldStart then
							IAFieldOutcomeMission.tryStartAfterRegisterOrDefer(mission, row.farmId, false)
						end
						if g_missionManager.updateMissions ~= nil then
							g_missionManager:updateMissions(0)
						end
						if row.usesBorrowedEquipment == true and row.neighbourId ~= nil and IANeighbours ~= nil and IANeighbours.neighbours ~= nil then
							local neighbour = IANeighbours.neighbours[row.neighbourId]
							if neighbour == nil then
								for _, n in pairs(IANeighbours.neighbours) do
									if n ~= nil and n.id == row.neighbourId then
										neighbour = n
										break
									end
								end
							end
							if neighbour ~= nil then
								if borrowRestoreByNeighbour[neighbour] == nil then
									borrowRestoreByNeighbour[neighbour] = {}
								end
								table.insert(borrowRestoreByNeighbour[neighbour], mission)
							else
								-- Silently dropping this row would leave the mission permanently at 99% (usesBorrowedEquipment + probes done, no live session to clear iaFoSBorrowReturnPending).
								print(string.format("[IAFieldOutcomeMission] tryApplyOutboundRestoreAfterLoad: borrowed-equipment mission farmlandId=%s job=%s skipped from borrow session restore: neighbour id=%s not found in IANeighbours.neighbours -> mission will stay at 99%%", tostring(row.farmlandId), tostring(row.fieldworkJob), tostring(row.neighbourId)))
							end
						elseif row.usesBorrowedEquipment == true then
							-- usesBorrowedEquipment=true but cannot route to a neighbour at all -> same permanent-99% lockup.
							print(string.format("[IAFieldOutcomeMission] tryApplyOutboundRestoreAfterLoad: borrowed-equipment mission farmlandId=%s job=%s skipped from borrow session restore: neighbourId=%s IANeighbours.neighbours=%s -> mission will stay at 99%%", tostring(row.farmlandId), tostring(row.fieldworkJob), tostring(row.neighbourId), tostring(IANeighbours ~= nil and IANeighbours.neighbours ~= nil)))
						end
					else
						mission:delete()
					end
				end
			end
		end
	end
	for neighbour, missions in pairs(borrowRestoreByNeighbour) do
		if IAMissionBorrow ~= nil and type(IAMissionBorrow.tryRestoreSessionForNeighbour) == "function" then
			IAMissionBorrow.tryRestoreSessionForNeighbour(neighbour, missions)
		end
	end
	IAFieldOutcomeMission._restoreQueue = {}
end

function IAFieldOutcomeMission.registerWithMissionManager()
	IAprintDebug("--- IAFieldOutcomeMission.registerWithMissionManager")
	if g_missionManager == nil or g_missionManager.registerMissionType == nil then
		return false
	end
	if IAFieldOutcomeMission._registered then
		return true
	end
	g_missionManager:registerMissionType(IAFieldOutcomeMission, IAFieldOutcomeMission.NAME, IAFieldOutcomeMission.MAX_NUM_INSTANCES)
	local data = g_missionManager:getMissionTypeDataByName(IAFieldOutcomeMission.NAME)
	if data ~= nil and data.rewardPerHa == nil then
		data.rewardPerHa = IAFieldOutcomeMission.DEFAULT_REWARD_PER_HA
	end
	IAFieldOutcomeMission._registered = true
	if MissionManager ~= nil and MissionManager.updateMissions ~= nil and not IAFieldOutcomeMission._deferredStartUpdateMissionsHooked then
		IAFieldOutcomeMission._deferredStartUpdateMissionsHooked = true
		MissionManager.updateMissions = Utils.appendedFunction(MissionManager.updateMissions, function(...)
			IAFieldOutcomeMission.processDeferredOutboundRestoreStarts()
		end)
	end
	return true
end

function IAFieldOutcomeMission.tryGenerateMission()
	return nil
end

function IAFieldOutcomeMission.isAvailableForField(field, mission)
	return true
end

function IAFieldOutcomeMission:validate(event)
	return true
end

function IAFieldOutcomeMission.registerXMLPaths(schema, key)
	IAFieldOutcomeMission:superClass().registerXMLPaths(schema, key)
	schema:register(XMLValueType.FLOAT, key .. "#rewardPerHa", "Multiplier vs default 1800; scales job-specific worker-only $/ha")
end

function IAFieldOutcomeMission.registerSavegameXMLPaths(schema, key)
	-- Same pattern as FS25_AdditionalContracts field missions: superClass first (AbstractFieldMission / cultivateMission paths in savegame_missions.xsd), then custom root attrs (#farmlandId + OUTCOME_KEY_ORDER).
	-- Parent may be defined as static (schema, key) or method (self, schema, key); try both like AdditionalContracts superClass chains.
	local super = IAFieldOutcomeMission:superClass()
	if super ~= nil and type(super.registerSavegameXMLPaths) == "function" then
		local ok = pcall(super.registerSavegameXMLPaths, super, schema, key)
		if not ok then
			pcall(super.registerSavegameXMLPaths, schema, key)
		end
	elseif AbstractFieldMission ~= nil and type(AbstractFieldMission.registerSavegameXMLPaths) == "function" then
		local ok = pcall(AbstractFieldMission.registerSavegameXMLPaths, AbstractFieldMission, schema, key)
		if not ok then
			pcall(AbstractFieldMission.registerSavegameXMLPaths, schema, key)
		end
	end
	schema:register(XMLValueType.INT, key .. "#farmlandId", "Farmland id for field outcome mission")
	for _, attr in ipairs(IAFieldOutcomeMission.OUTCOME_KEY_ORDER) do
		schema:register(XMLValueType.INT, key .. "#" .. attr, "Expected field state " .. attr)
	end
end

function IAFieldOutcomeMission.loadMapData(xmlFile, key, baseDirectory)
	local data = g_missionManager:getMissionTypeDataByName(IAFieldOutcomeMission.NAME)
	if data ~= nil then
		-- Default 1800 = scale 1.0 on top of job-specific WORKER_ONLY_REWARD_PER_HA bases (see getRewardPerHa).
		data.rewardPerHa = xmlFile:getFloat(key .. "#rewardPerHa", IAFieldOutcomeMission.DEFAULT_REWARD_PER_HA)
	end
	return true
end

function IAFieldOutcomeMission.new(isServer, isClient, customMt)
	local typeLabel = g_i18n:getText("ia_fieldwork_label_condition")
	local who = g_i18n:getText("ia_field_outcome_neighbour_generic")
	local title = string.format(g_i18n:getText("ia_field_outcome_mission_title_for_neighbour"), typeLabel, who)
	local description = string.format(
		g_i18n:getText("ia_field_outcome_mission_desc_short"),
		g_i18n:getText("ia_fieldwork_equip_generic")
	)
	local self = AbstractFieldMission.new(isServer, isClient, title, description, customMt or IAFieldOutcomeMission_mt)
	self.workAreaTypes = {}
	self.iaFieldFarmlandId = FarmlandManager.NO_OWNER_FARM_ID
	self.iaExpectedFieldState = {}
	self.iaOutcomeCheckAccumMs = 0
	self.iaProbes = {}
	self.iaProbeDebugNodes = {}
	self.iaProbeEvalMatched = 0
	self.iaProbeEvalTotal = 1
	self.iaProbeEvalAllFinished = false
	self.jobTypName = title
	self:iaApplyWorkAreaTypesForFoSJob()
	return self
end

function IAFieldOutcomeMission:getMissionTypeName()
	return IAFieldOutcomeMission.NAME
end

--- Base $/ha for worker-only phone field outcome (before map `rewardPerHa` scale).
-- @param string|nil rawJob situation `fieldwork` string
-- @param boolean|nil usesBorrowedEquipment true when the player selected borrowed equipment
-- @return number
function IAFieldOutcomeMission.resolveWorkerOnlyRewardPerHaFromJobRaw(rawJob, usesBorrowedEquipment)
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		local fallback = IAFieldOutcomeMission.WORKER_ONLY_REWARD_FALLBACK_PER_HA
		if usesBorrowedEquipment == true then
			return math.max(1, math.floor(fallback * IAFieldOutcomeMission.BORROW_REWARD_MULT_DEFAULT + 0.5))
		end
		return fallback
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(rawJob or ""))
	local t = IAFieldOutcomeMission.WORKER_ONLY_REWARD_PER_HA
	local base = IAFieldOutcomeMission.WORKER_ONLY_REWARD_FALLBACK_PER_HA
	if jt ~= nil and t ~= nil and t[jt] ~= nil then
		base = t[jt]
	end
	if usesBorrowedEquipment == true then
		if IAFieldwork.JobType ~= nil
			and (
				jt == IAFieldwork.JobType.SEED
				or jt == IAFieldwork.JobType.SPRAY
				or (IAFieldwork.isFertilizeJobType ~= nil and IAFieldwork.isFertilizeJobType(jt))
			)
		then
			return math.max(1, math.floor(base * IAFieldOutcomeMission.BORROW_REWARD_MULT_CONSUMABLE + 0.5))
		end
		return math.max(1, math.floor(base * IAFieldOutcomeMission.BORROW_REWARD_MULT_DEFAULT + 0.5))
	end
	return base
end

--- Map `loadMapData` #rewardPerHa multiplies all job bases (default 1800 = scale 1.0).
function IAFieldOutcomeMission:getRewardPerHa()
	local base = IAFieldOutcomeMission.resolveWorkerOnlyRewardPerHaFromJobRaw(self.iaFoSFieldworkJob, self.iaFoSUsesBorrowedEquipment == true)
	local data = g_missionManager ~= nil and g_missionManager.getMissionTypeDataByName ~= nil and g_missionManager:getMissionTypeDataByName(IAFieldOutcomeMission.NAME) or nil
	local ref = IAFieldOutcomeMission.DEFAULT_REWARD_PER_HA
	if ref == nil or ref <= 0 then
		ref = 1800
	end
	local scale = ref
	if data ~= nil and data.rewardPerHa ~= nil and data.rewardPerHa > 0 then
		scale = data.rewardPerHa
	end
	return math.max(1, math.floor(base * (scale / ref) + 0.5))
end

function IAFieldOutcomeMission:getVehicleVariant()
	if self.field ~= nil and type(self.field.getAreaHa) == "function" and (self.field:getAreaHa() or 0) >= 30 then
		return "BIGLARGE"
	end
	return "GRAIN"
end

--- FoS phone field-outcome missions are player-worked and measured by sampling actual FieldState (probes).
--- Vanilla AbstractFieldMission:prepareField() (run from prepare() on every start, including savegame-restore restart)
--- enqueues a FieldUpdateTask built from the field's cached (uniform, center-sampled) FieldState across the whole
--- field polygon, which flattens the player's partial physical fieldwork back to the cached state on load.
--- Returning nil here disables that field-reset task: getIsPrepared() treats a nil fieldPreparingTask as prepared,
--- so PREPARING -> RUNNING still proceeds, but the terrain is left exactly as the engine restored it.
function IAFieldOutcomeMission:getFieldPreparingTask()
	return nil
end

function IAFieldOutcomeMission:createModifier()
	-- Density completion is unused; progress comes from getFieldCompletion / sampled FieldState.
	if g_currentMission == nil or g_currentMission.fieldGroundSystem == nil or g_currentMission.fieldGroundSystem.getDensityMapData == nil then
		return
	end
	local mapId, firstChannel, numChannels = g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.STUBBLE_SHRED_LEVEL)
	if mapId == nil then
		return
	end
	local levelState = 0
	if FieldGroundType ~= nil and FieldGroundType.getValueByType ~= nil and FieldGroundType.STUBBLE_TILLAGE ~= nil then
		levelState = FieldGroundType.getValueByType(FieldGroundType.STUBBLE_TILLAGE)
	end
	self.completionModifier = DensityMapModifier.new(mapId, firstChannel, numChannels, g_terrainNode)
	self.completionFilter = DensityMapFilter.new(self.completionModifier)
	self.completionFilter:setValueCompareParams(DensityValueCompareType.EQUAL, levelState)
end

--- Vanilla uses field:getFieldState():createFieldUpdateTask(), which can overwrite FoS contract outcomes (e.g. fertilize spray channel).
--- Match IASituation:completeFieldwork / IAFieldwork.enqueueCompleteFieldworkFieldUpdate (expected sprayType passed like seed fruit index).
function IAFieldOutcomeMission:getFieldFinishTask()
	if self.field == nil then
		return nil
	end
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return IAFieldOutcomeMission:superClass().getFieldFinishTask(self)
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(self.iaFoSFieldworkJob or ""))
	if jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
		if type(IAFieldwork.buildFieldUpdateTaskFromExpectedState) == "function" then
			return IAFieldwork.buildFieldUpdateTaskFromExpectedState(self.field, self.iaExpectedFieldState)
		end
		return nil
	end
	if jt == nil then
		return nil
	end
	local seedIdx = nil
	if jt == IAFieldwork.JobType.SEED and self.iaExpectedFieldState ~= nil then
		seedIdx = self.iaExpectedFieldState.fruitTypeIndex
	end
	local fertSpray = nil
	if IAFieldwork.isFertilizeJobType(jt) and self.iaExpectedFieldState ~= nil and self.iaExpectedFieldState.sprayType ~= nil then
		fertSpray = tonumber(self.iaExpectedFieldState.sprayType)
	end
	if type(IAFieldwork.buildFieldUpdateTaskForCompleteFieldwork) ~= "function" then
		return IAFieldOutcomeMission:superClass().getFieldFinishTask(self)
	end
	return IAFieldwork.buildFieldUpdateTaskForCompleteFieldwork(self.field, jt, seedIdx, fertSpray)
end

function IAFieldOutcomeMission:iaResolveField()
	if self.field ~= nil then
		return self.field
	end
	local f = IAHelper_getFieldForFarmlandId(self.iaFieldFarmlandId)
	if f ~= nil then
		self.field = f
	end
	return self.field
end

function IAFieldOutcomeMission.isProbeDebugDrawEnabled()
	return IANeighbours ~= nil and IANeighbours.debugFieldMissionProbes == true
end

--- Apply or clear probe markers on every active FoS field-outcome mission (console toggle).
function IAFieldOutcomeMission.syncProbeDebugMarkersForAllActive()
	if g_missionManager == nil or g_missionManager.missions == nil then
		return
	end
	local enabled = IAFieldOutcomeMission.isProbeDebugDrawEnabled()
	for _, mission in ipairs(g_missionManager.missions) do
		if mission ~= nil and mission.iaFieldsOfStoriesMission == true and mission.getMissionTypeName ~= nil then
			local okName, typeName = pcall(mission.getMissionTypeName, mission)
			if okName and typeName == IAFieldOutcomeMission.NAME and mission.status ~= MissionStatus.FINISHED then
				if enabled and type(mission.iaRefreshProbeDebugPoints) == "function" then
					mission:iaRefreshProbeDebugPoints()
				elseif type(mission.iaClearProbeDebugPoints) == "function" then
					mission:iaClearProbeDebugPoints()
				end
			end
		end
	end
end

function IAFieldOutcomeMission:iaClearProbeDebugPoints()
	if self.iaProbeDebugNodes == nil then
		return
	end
	if IANeighbours ~= nil and IANeighbours.removeDebugPointNode ~= nil then
		for _, node in ipairs(self.iaProbeDebugNodes) do
			IANeighbours:removeDebugPointNode(node)
		end
	end
	self.iaProbeDebugNodes = {}
end

function IAFieldOutcomeMission:iaRefreshProbeDebugPoints()
	self:iaClearProbeDebugPoints()
	if not IAFieldOutcomeMission.isProbeDebugDrawEnabled() then
		return
	end
	self.iaProbeDebugNodes = {}
	for _, p in ipairs(self.iaProbes or {}) do
		local y = 0
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			y = getTerrainHeightAtWorldPos(g_terrainNode, p.x, 0, p.z) + 0.2
		end
		local label
		if p.kind == "V" then
			label = string.format("FoS outcome V/%d", p.idx)
		else
			label = string.format("FoS outcome I/%d", p.idx)
		end
		local node = IANeighbours:addDebugPointAtPosition(p.x, y, p.z, label, nil)
		if node ~= nil and node ~= 0 then
			table.insert(self.iaProbeDebugNodes, node)
		end
	end
end

function IAFieldOutcomeMission:iaRebuildProbePositions(field)
	self:iaClearProbeDebugPoints()
	field = field or self.field or self:iaResolveField()
	self.iaProbes = {}
	self.iaProbeEvalMatched = 0
	self.iaProbeEvalTotal = 1
	self.iaProbeEvalAllFinished = false

	if field == nil then
		self:iaSyncProbeEvaluation()
		self:iaRefreshProbeDebugPoints()
		return
	end

	local polyCount = 0
	if field.polygonPoints ~= nil then
		polyCount = #field.polygonPoints
	end
	if polyCount < 3 then
		if IANeighbours ~= nil and IANeighbours.debug then
			print(string.format("[IAFieldOutcomeMission] iaRebuildProbePositions: polygon has %d nodes; using field center fallback", polyCount))
		end
		local cx, cz = nil, nil
		if type(field.getCenterOfFieldWorldPosition) == "function" then
			cx, cz = field:getCenterOfFieldWorldPosition()
		end
		if cx ~= nil and cz ~= nil then
			table.insert(self.iaProbes, { x = cx, z = cz, kind = "I", idx = 1 })
		end
		self:iaSyncProbeEvaluation()
		self:iaRefreshProbeDebugPoints()
		return
	end

	local MAX = IAFieldOutcomeMission.MAX_PROBES
	local minInterior = tonumber(IAFieldOutcomeMission.MIN_INTERIOR_PROBE_SLOTS)
	if minInterior == nil or minInterior < 1 then
		minInterior = 16
	end
	local interiorReserve = math.min(IAFieldOutcomeMission.NUM_INTERIOR_RANDOM, minInterior, math.max(1, MAX - 1))
	local borderCap = math.max(1, MAX - interiorReserve)
	local borderInsets = {}
	if type(IAHelper_getBorderInsetProbePoints) == "function" then
		borderInsets = IAHelper_getBorderInsetProbePoints(field, IAFieldOutcomeMission.BORDER_INSET_MIN_M, IAFieldOutcomeMission.BORDER_INSET_MAX_M, borderCap)
	end
	if borderInsets == nil then
		borderInsets = {}
	end

	local nInset = #borderInsets
	local nRandomWanted = math.min(IAFieldOutcomeMission.NUM_INTERIOR_RANDOM, math.max(0, MAX - nInset))
	local randomPts = {}
	if nRandomWanted > 0 and type(IAHelper_getRandomPointsInField) == "function" then
		randomPts = IAHelper_getRandomPointsInField(field, nRandomWanted, borderInsets)
	end
	if randomPts == nil then
		randomPts = {}
	end

	local probes = {}
	for i, p in ipairs(borderInsets) do
		if p.x ~= nil and p.z ~= nil then
			probes[#probes + 1] = { x = p.x, z = p.z, kind = "V", idx = i }
		end
	end
	for i, p in ipairs(randomPts) do
		if p.x ~= nil and p.z ~= nil then
			probes[#probes + 1] = { x = p.x, z = p.z, kind = "I", idx = i }
		end
	end

	if #probes < 1 then
		local cx, cz = nil, nil
		if type(field.getCenterOfFieldWorldPosition) == "function" then
			cx, cz = field:getCenterOfFieldWorldPosition()
		end
		if cx ~= nil and cz ~= nil then
			probes[1] = { x = cx, z = cz, kind = "I", idx = 1 }
		end
	end

	self.iaProbes = probes
	IAFieldOutcomeMission.iaLog(string.format("iaRebuildProbePositions: borderCap=%d nBorder=%d interiorWanted=%d nInterior=%d total=%d", borderCap, nInset, nRandomWanted, #randomPts, #probes))
	self:iaSyncProbeEvaluation()
	self:iaRefreshProbeDebugPoints()
end

function IAFieldOutcomeMission:iaSampleFieldStateAt(x, z)
	if x == nil or z == nil or FieldState == nil or type(FieldState.new) ~= "function" then
		return nil
	end
	local probe = FieldState.new()
	if type(probe.update) ~= "function" then
		return nil
	end
	local ok = pcall(probe.update, probe, x, z)
	if not ok then
		return nil
	end
	return probe
end

function IAFieldOutcomeMission:iaSyncProbeEvaluation()
	local plist = self.iaProbes
	if plist == nil or #plist < 1 then
		self.iaProbeEvalMatched = 0
		self.iaProbeEvalTotal = 1
		self.iaProbeEvalAllFinished = false
		self.fieldPercentageDone = 0
		return
	end
	local maxMissLogLines = 48
	local res = IAFieldOutcomeMissionProbeEvaluator.evaluateAllProbes(
		plist,
		self.iaExpectedFieldState,
		self.iaFoSFieldworkJob,
		function(x, z)
			return self:iaSampleFieldStateAt(x, z)
		end,
		{
			maxMissLogLines = maxMissLogLines,
			mismatchAnnot = IAFieldOutcomeMission.iaProbeMismatchAnnotators(),
			probeThreshold = IAFieldOutcomeMission.getProbeCompletionThreshold(),
		}
	)
	local matched = res.matched
	local total = res.total
	local missLines = res.missLines
	local missCounts = res.missCounts
	local nVertex = res.nVertex
	local nInterior = res.nInterior
	self.iaProbeEvalMatched = matched
	self.iaProbeEvalTotal = total
	self.iaProbeEvalAllFinished = res.allFinished
	self.fieldPercentageDone = res.fieldPercentageDone
	if IAMissionBorrow ~= nil and type(IAMissionBorrow.syncMissionBorrowReturnPending) == "function" then
		IAMissionBorrow.syncMissionBorrowReturnPending(self)
	end
	if IAFieldOutcomeMission.iaDbg() then
		local preamble = self:iaDebugFieldPreamble(total, nVertex, nInterior)
		IAFieldOutcomeMission.iaLog(
			string.format(
				"iaSyncProbeEvaluation %s | matched=%d/%d allFinished=%s HUD_completion=%.3f (threshold=%.0f%%; each probe must match every key in iaExpectedFieldState)",
				preamble,
				matched,
				total,
				tostring(self.iaProbeEvalAllFinished),
				(total > 0) and (matched / total) or 0,
				(IAFieldOutcomeMission.PROBE_COMPLETION_THRESHOLD or 1.0) * 100
			)
		)
		local nMissLogged = #missLines
		for mi = 1, nMissLogged do
			IAFieldOutcomeMission.iaLog("  miss: " .. missLines[mi])
		end
		if total - matched > nMissLogged then
			IAFieldOutcomeMission.iaLog(string.format("  miss: ... %d more (cap=%d)", total - matched - nMissLogged, maxMissLogLines))
		end
		local incomplete = matched < total
		if incomplete and self.iaExpectedFieldState ~= nil then
			self._iaFoSProbeDbgEvalCounter = (self._iaFoSProbeDbgEvalCounter or 0) + 1
			local prevM = self._iaFoSProbeDbgLastMatched
			self._iaFoSProbeDbgLastMatched = matched
			local force = prevM == nil or prevM ~= matched
			local periodic = (self._iaFoSProbeDbgEvalCounter % 15 == 1)
			if force or periodic then
				local expRow = IAFieldOutcomeMission.iaFormatStateForExpectedKeys(self.iaExpectedFieldState, self.iaExpectedFieldState)
				IAFieldOutcomeMission.iaLog("  contract_expected: " .. expRow)
				local field = self:iaResolveField()
				local sx, sz, sampleTag = nil, nil, "field_center"
				if field ~= nil and type(field.getCenterOfFieldWorldPosition) == "function" then
					sx, sz = field:getCenterOfFieldWorldPosition()
				end
				if sx == nil and plist[1] ~= nil then
					sx = plist[1].x
					sz = plist[1].z
					sampleTag = "first_probe_pos"
				end
				local centerState = nil
				if sx ~= nil and sz ~= nil then
					centerState = self:iaSampleFieldStateAt(sx, sz)
				end
				local centerRow = IAFieldOutcomeMission.iaFormatStateForExpectedKeys(self.iaExpectedFieldState, centerState)
				IAFieldOutcomeMission.iaLog(
					string.format("  terrain_sample(%s xz=%.2f,%.2f): %s", sampleTag, tonumber(sx) or 0, tonumber(sz) or 0, centerRow)
				)
				local hist = IAFieldOutcomeMission.iaFormatMissHistogram(missCounts)
				if hist ~= "" then
					IAFieldOutcomeMission.iaLog("  " .. hist)
				end
			end
		elseif not incomplete then
			self._iaFoSProbeDbgLastMatched = matched
		end
	end
end

function IAFieldOutcomeMission:iaExpectedOutcomeSatisfiedBy(probe)
	return IAFieldOutcomeMissionProbeEvaluator.probeSatisfiesExpected(self.iaExpectedFieldState, self.iaFoSFieldworkJob, probe)
end

function IAFieldOutcomeMission:getIsFinished()
	if self.iaFoSBorrowReturnPending == true then
		return false
	end
	return self.iaProbeEvalAllFinished == true
end

function IAFieldOutcomeMission:getFieldCompletion()
	local t = math.max(1, self.iaProbeEvalTotal or 1)
	local m = self.iaProbeEvalMatched or 0
	local comp = math.max(0, math.min(1, m / t))
	if self.iaProbeEvalAllFinished == true then
		if self.iaFoSBorrowReturnPending == true then
			return 0.99
		end
		return 1.0
	end
	return comp
end

function IAFieldOutcomeMission:getCompletion()
	return self:getFieldCompletion()
end

--- GDN vanilla: getIsRunning() and (workAreaType == nil or workAreaTypes[workAreaType]).
function IAFieldOutcomeMission:getIsWorkAllowed(farmId, x, z, workAreaType, vehicle)
	local active = false
	if self:getIsRunning() then
		active = true
	end
	if self:getIsFinished() then
		active = true
	end

	
	if not active then
		return false
	end
	if workAreaType == nil then
		return true
	end
	if self.workAreaTypes ~= nil and self.workAreaTypes[workAreaType] == true then
		return true
	end
	return false
end

function IAFieldOutcomeMission:iaApplyWorkAreaTypesForFoSJob()
	local out = {}
	local jt = nil
	if self.iaFoSFieldworkJob ~= nil
		and tostring(self.iaFoSFieldworkJob) ~= ""
		and IAFieldwork ~= nil
		and type(IAFieldwork.normalizeFieldworkJobType) == "function"
	then
		jt = IAFieldwork.normalizeFieldworkJobType(tostring(self.iaFoSFieldworkJob))
	end
	if IAFieldwork ~= nil and IAFieldwork.JobType ~= nil and jt ~= nil then
		if jt == IAFieldwork.JobType.CULTIVATE then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "CULTIVATOR" })
		elseif jt == IAFieldwork.JobType.HARROW then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "CULTIVATOR", "ROLLER" })
		elseif jt == IAFieldwork.JobType.PLOW then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "PLOW" })
		elseif jt == IAFieldwork.JobType.SLURRYSPREADING then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "SPRAYER" })
		elseif jt == IAFieldwork.JobType.MANURESPREADING then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "SPREADER", "SPRAYER", "DEFAULT" })
		elseif jt == IAFieldwork.JobType.FERTILIZEDSPREADING then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "SPREADER", "SPRAYER", "FERTILIZER" })
		elseif jt == IAFieldwork.JobType.SPRAY then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "SPRAYER", "WEEDER" })
		elseif jt == IAFieldwork.JobType.SEED then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "SOWING_MACHINE", "SOWINGMACHINE", "SOWER", "CULTIVATOR" })
		elseif jt == IAFieldwork.JobType.HARVEST then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "HARVESTER", "COMBINE", "CUTTER" })
		elseif jt == IAFieldwork.JobType.IA_FIELD_OUTCOME then
			IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, {
				"DEFAULT",
				"CULTIVATOR",
				"SPRAYER",
				"PLOW",
				"HARVESTER",
				"COMBINE",
				"ROLLER",
				"SOWING_MACHINE",
				"SOWINGMACHINE",
				"SOWER",
				"MULCHER",
				"WEEDER",
			})
		end
	end
	if next(out) == nil then
		IAFieldOutcomeMission.iaEnableWorkAreaTypesByEnumNames(out, { "DEFAULT", "CULTIVATOR", "SPRAYER", "PLOW" })
	end
	if next(out) == nil and WorkAreaType ~= nil and WorkAreaType.CULTIVATOR ~= nil then
		out[WorkAreaType.CULTIVATOR] = true
	end
	self.workAreaTypes = out
end

--- Refresh mission title / description / jobTypName (phone: job type + neighbour; short equipment blurb).
-- @param table|nil field unused; kept for call sites
-- @param table|nil context optional { fieldworkRaw, fieldworkJob, neighbourFirstName }
function IAFieldOutcomeMission:iaApplyDynamicMissionPresentation(field, context)
	if g_i18n == nil then
		return
	end
	self:iaMergeFoSContext(context)
	local exp = self.iaExpectedFieldState
	local typeLabel = self:iaJobDisplayLabel(self.iaFoSFieldworkJob, exp)
	if typeLabel == nil or typeLabel == "" then
		typeLabel = g_i18n:getText("ia_fieldwork_label_condition")
	end
	local who = self.iaFoSNeighbourFirstName
	if who == nil or who == "" then
		who = g_i18n:getText("ia_field_outcome_neighbour_generic")
	end
	self.title = string.format(
		g_i18n:getText("ia_field_outcome_mission_title_for_neighbour"),
		tostring(typeLabel),
		tostring(who)
	)
	local equip = self:iaEquipmentHint(self.iaFoSFieldworkJob, exp)
	local line1
	local jt = nil
	if IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" and self.iaFoSFieldworkJob ~= nil then
		jt = IAFieldwork.normalizeFieldworkJobType(tostring(self.iaFoSFieldworkJob))
	end
	local cropTitle = (IAFieldwork.JobType ~= nil and jt == IAFieldwork.JobType.SEED and exp ~= nil) and IAFieldOutcomeMission.iaFruitTypeDisplayTitle(exp.fruitTypeIndex) or nil
	if cropTitle ~= nil and cropTitle ~= "" then
		line1 = string.format(g_i18n:getText("ia_field_outcome_mission_desc_seed"), tostring(equip), cropTitle)
	else
		line1 = string.format(g_i18n:getText("ia_field_outcome_mission_desc_short"), tostring(equip))
	end
	local sub = self:iaTargetSubtitle()
	if sub ~= nil and sub ~= "" then
		self.description = line1 .. "\n" .. sub
	else
		self.description = line1
	end
	self.jobTypName = self.title
	self:iaSyncProgressTitle(field)
end

function IAFieldOutcomeMission:initFromField(field, expectedOutcome, context)
	if field == nil then
		return false
	end
	self:iaMergeFoSContext(context)
	self.iaExpectedFieldState = IAHelper_copyTableStringKeysOrderedFirst(expectedOutcome, IAFieldOutcomeMission.OUTCOME_KEY_ORDER)
	if field.farmland ~= nil and field.farmland.getId ~= nil then
		self.iaFieldFarmlandId = field.farmland:getId()
	elseif field.getFarmlandId ~= nil then
		self.iaFieldFarmlandId = field:getFarmlandId()
	else
		self.iaFieldFarmlandId = FarmlandManager.NO_OWNER_FARM_ID
	end
	local perHa = self:getRewardPerHa()
	local area = 1
	if type(field.getAreaHa) == "function" then
		area = field:getAreaHa() or 1
	end
	self.reward = math.max(500, math.floor(perHa * area + 0.5))
	if type(self.setMinReward) == "function" then
		self:setMinReward()
	end
	if type(self.setDefaultEndDate) == "function" then
		self:setDefaultEndDate()
	end
	self:iaPruneExpectedFieldStateForJobType()
	self:iaApplyWorkAreaTypesForFoSJob()
	local ok = IAFieldOutcomeMission:superClass().init(self, field)
	if ok then
		self:iaRebuildProbePositions(field)
		self:iaApplyDynamicMissionPresentation(field, context)
	end
	if IAFieldOutcomeMission.iaDbg() then
		local fid = self.iaFieldFarmlandId
		local nProbe = self.iaProbes ~= nil and #self.iaProbes or 0
		IAFieldOutcomeMission.iaLog(
			string.format(
				"initFromField ok=%s farmlandId=%s reward=%s probes=%d matched=%s/%s allFinished=%s expected=%s",
				tostring(ok),
				tostring(fid),
				tostring(self.reward),
				nProbe,
				tostring(self.iaProbeEvalMatched),
				tostring(self.iaProbeEvalTotal),
				tostring(self.iaProbeEvalAllFinished),
				IAFieldOutcomeMission.iaOutcomeSummary(self.iaExpectedFieldState)
			)
		)
	end
	return ok
end

function IAFieldOutcomeMission:update(dt)
	if self._iaFoSMissionPresentationPending == true then
		self:iaResolveField()
		if self.field ~= nil then
			self._iaFoSMissionPresentationPending = false
			self:iaApplyDynamicMissionPresentation(self.field, {})
		end
	end
	local statusBefore = self.status
	IAFieldOutcomeMission:superClass().update(self, dt)
	if IAFieldOutcomeMission.iaDbg() and statusBefore ~= self.status then
		IAFieldOutcomeMission.iaLog(
			string.format(
				"super.update status %s -> %s dt=%s isServer=%s (vanilla field mission logic may finish here)",
				tostring(statusBefore),
				tostring(self.status),
				tostring(dt),
				tostring(self.isServer)
			)
		)
	end
	if self.status ~= MissionStatus.RUNNING then
		return
	end
	self.iaOutcomeCheckAccumMs = (self.iaOutcomeCheckAccumMs or 0) + (dt or 0)
	if self.iaOutcomeCheckAccumMs < IAFieldOutcomeMission.PROBE_CHECK_INTERVAL_MS then
		return
	end
	self.iaOutcomeCheckAccumMs = 0
	self:iaSyncProbeEvaluation()
	if self.isServer and self:getIsFinished() then
		if self.iaFoSUsesBorrowedEquipment == true then
			return
		end
		if IAFieldOutcomeMission.iaDbg() then
			IAFieldOutcomeMission.iaLog(
				string.format(
					"finish SUCCESS via probe path matched=%s/%s getFieldCompletion=%.3f",
					tostring(self.iaProbeEvalMatched),
					tostring(self.iaProbeEvalTotal),
					self:getFieldCompletion()
				)
			)
		end
		self:finish(MissionFinishState.SUCCESS)
	end
end

function IAFieldOutcomeMission:getFarmlandId()
	if self.field ~= nil and self.field.farmland ~= nil and self.field.farmland.getId ~= nil then
		local ok, id = pcall(self.field.farmland.getId, self.field.farmland)
		if ok and id ~= nil then
			return id
		end
	end
	return self.iaFieldFarmlandId or FarmlandManager.NO_OWNER_FARM_ID
end

--- Apply relationship score change on mission end. Server-only; the mission carries
-- the owning neighbour's id (iaFoSNeighbourId), set at mission creation. The magnitude
-- is 2% of the money reward floor-rounded, with a floor of 100 points (so a tiny 500€
-- contract still moves the relationship by ±100, while a 10000€ contract moves it ±200).
-- SUCCESS adds points; FAILED / CANCELED / TIMED_OUT subtracts. Engine-driven deletes
-- without a finish() (savegame unload) intentionally do NOT trigger this — only here.
function IAFieldOutcomeMission:iaApplyMissionEndRelationshipDelta(success)
	if self.iaFoSRelationshipDeltaApplied == true then
		return
	end
	if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
		return
	end
	if IANeighbours == nil or IANeighbours.neighbours == nil then
		return
	end
	local nid = tonumber(self.iaFoSNeighbourId)
	if nid == nil or nid <= 0 then
		return
	end
	local neighbour = IANeighbours.neighbours[nid]
	if neighbour == nil or tonumber(neighbour.id) ~= nid then
		for _, n in pairs(IANeighbours.neighbours) do
			if n ~= nil and tonumber(n.id) == nid then
				neighbour = n
				break
			end
		end
	end
	if neighbour == nil or type(neighbour.addScore) ~= "function" then
		return
	end
	local reward = tonumber(self.reward) or 0
	if reward <= 0 then
		return
	end
	local magnitude = math.max(100, math.floor(reward * 0.02 + 0.5))
	local delta
	if success == MissionFinishState.SUCCESS then
		delta = magnitude
	elseif success == MissionFinishState.FAILED
		or success == MissionFinishState.CANCELED
		or success == MissionFinishState.TIMED_OUT
	then
		delta = -magnitude
	else
		return
	end
	self.iaFoSRelationshipDeltaApplied = true
	neighbour:addScore(delta)
	if IAFieldOutcomeMission.iaDbg() then
		IAFieldOutcomeMission.iaLog(string.format(
			"iaApplyMissionEndRelationshipDelta neighbour=%s id=%s success=%s reward=%s delta=%s",
			tostring(neighbour.name), tostring(nid), tostring(success), tostring(reward), tostring(delta)
		))
	end
end

-- Tell the source neighbour's daily fieldwork schedule that this player-accepted contract
-- mission has ended. SUCCESS removes the row (work done), any failure variant clears the
-- acceptedByPlayer flag so the neighbour's AI loop picks the work back up. Guarded so it
-- runs once per mission instance and only on the server (schedule lives on the server).
function IAFieldOutcomeMission:iaApplyMissionEndToNeighbourSchedule(success)
	if self.iaFoSScheduleEndApplied == true then
		return
	end
	if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
		return
	end
	if IANeighbours == nil or IANeighbours.gameLoopHelper == nil
		or type(IANeighbours.gameLoopHelper.applyAcceptedContractMissionEndToSchedule) ~= "function"
	then
		return
	end
	local sid = self.iaFoSSituationId
	if sid == nil or tostring(sid) == "" then
		return
	end
	local fid = tonumber(self.iaFieldFarmlandId)
	if fid == nil or fid <= 0 then
		return
	end
	local nid = tonumber(self.iaFoSNeighbourId)
	if nid == nil or nid <= 0 then
		return
	end
	local neighbour = nil
	if IANeighbours.neighbours ~= nil then
		neighbour = IANeighbours.neighbours[nid]
		if neighbour == nil or tonumber(neighbour.id) ~= nid then
			for _, n in pairs(IANeighbours.neighbours) do
				if n ~= nil and tonumber(n.id) == nid then
					neighbour = n
					break
				end
			end
		end
	end
	if neighbour == nil then
		return
	end
	self.iaFoSScheduleEndApplied = true
	IANeighbours.gameLoopHelper:applyAcceptedContractMissionEndToSchedule(neighbour, sid, fid, success)
end

function IAFieldOutcomeMission:finish(success)
	if IAFieldOutcomeMission.iaDbg() then
		local uid = rawget(self, "uniqueId")
		IAFieldOutcomeMission.iaLog(
			string.format(
				"finish() entry success=%s status=%s uniqueId=%s probeAllFinished=%s matched=%s/%s (if status already FINISHED before probe log, likely superClass.finish/density)",
				tostring(success),
				tostring(self.status),
				tostring(uid),
				tostring(self.iaProbeEvalAllFinished),
				tostring(self.iaProbeEvalMatched),
				tostring(self.iaProbeEvalTotal)
			)
		)
	end
	IAprintDebug("IAFieldOutcomeMission:finish()", string.format(
		"[BORROW-CANCEL] entry success=%s status=%s missionUid=%s usesBorrowed=%s sessionId=%s",
		tostring(success), tostring(self.status), tostring(rawget(self, "uniqueId")),
		tostring(self.iaFoSUsesBorrowedEquipment), tostring(self.iaFoSMissionBorrowSessionId)
	), nil, nil, nil)
	IAFieldOutcomeMission:superClass().finish(self, success)
	IAprintDebug("IAFieldOutcomeMission:finish()", string.format(
		"[BORROW-CANCEL] post-superClass.finish status=%s missionUid=%s",
		tostring(self.status), tostring(rawget(self, "uniqueId"))
	), nil, nil, nil)
	if IAMissionBorrow ~= nil and type(IAMissionBorrow.onMissionEnded) == "function" then
		IAprintDebug("IAFieldOutcomeMission:finish()", "[BORROW-CANCEL] calling IAMissionBorrow.onMissionEnded", nil, nil, nil)
		IAMissionBorrow.onMissionEnded(self, success)
		IAprintDebug("IAFieldOutcomeMission:finish()", "[BORROW-CANCEL] returned from IAMissionBorrow.onMissionEnded", nil, nil, nil)
	else
		IAprintDebug("IAFieldOutcomeMission:finish()", "[BORROW-CANCEL] IAMissionBorrow.onMissionEnded NOT available - skipping unborrow chain", nil, nil, nil)
	end
	self:iaApplyMissionEndRelationshipDelta(success)
	if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer() then
		if success == MissionFinishState.SUCCESS and self.farmId ~= nil and g_farmManager ~= nil then
			local farm = g_farmManager:getFarmById(self.farmId)
			if farm ~= nil and farm.stats ~= nil and farm.stats.updateMissionDone ~= nil then
				farm.stats:updateMissionDone()
			end
		end
		self:iaApplyMissionEndToNeighbourSchedule(success)
	end
	if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() == self.farmId then
		if success == MissionFinishState.SUCCESS then
			g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, g_i18n:getText("ia_field_outcome_mission_finished"))
		elseif success == MissionFinishState.FAILED or success == MissionFinishState.CANCELED or success == MissionFinishState.TIMED_OUT then
			g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("ia_field_outcome_mission_failed"))
		end
	end
end

function IAFieldOutcomeMission:delete()
	IAprintDebug("IAFieldOutcomeMission:delete()", string.format(
		"[BORROW-CANCEL] entry status=%s missionUid=%s usesBorrowed=%s sessionId=%s",
		tostring(self.status), tostring(rawget(self, "uniqueId")),
		tostring(self.iaFoSUsesBorrowedEquipment), tostring(self.iaFoSMissionBorrowSessionId)
	), nil, nil, nil)
	if self.status ~= nil and MissionStatus ~= nil and self.status ~= MissionStatus.FINISHED then
		IAprintDebug("IAFieldOutcomeMission:delete()", "[BORROW-CANCEL] status != FINISHED -> calling onMissionEnded(CANCELED)", nil, nil, nil)
		if IAMissionBorrow ~= nil and type(IAMissionBorrow.onMissionEnded) == "function" then
			IAMissionBorrow.onMissionEnded(self, MissionFinishState.CANCELED)
		end
	else
		IAprintDebug("IAFieldOutcomeMission:delete()", string.format(
			"[BORROW-CANCEL] status=%s already FINISHED (or nil) -> skipping onMissionEnded (cleanup expected to have happened in finish())",
			tostring(self.status)
		), nil, nil, nil)
	end
	self:iaClearProbeDebugPoints()
	self.iaExpectedFieldState = {}
	self.iaProbes = {}
	IAFieldOutcomeMission:superClass().delete(self)
end

function IAFieldOutcomeMission:saveToXMLFile(xmlFile, key)
	-- Phone field-outcome state lives in IANeighbours_outbound.xml; strip this slot from missions.xml if the engine created it.
	if xmlFile ~= nil and key ~= nil and type(xmlFile.removeProperty) == "function" then
		pcall(function()
			xmlFile:removeProperty(key)
		end)
	end
end

function IAFieldOutcomeMission:loadFromXMLFile(xmlFile, key)
	-- Legacy: older saves stored this mission in missions.xml; new saves use outbound only.
	if xmlFile == nil or key == nil then
		return false
	end
	local hasLegacy = false
	if xmlFile.hasProperty ~= nil then
		hasLegacy = xmlFile:hasProperty(key .. ".field#id") or xmlFile:hasProperty(key .. "#uniqueId")
	end
	if not hasLegacy then
		return true
	end
	IAFieldOutcomeMission.ensureSavegameSchemaRegistered(xmlFile)
	if not IAFieldOutcomeMission:superClass().loadFromXMLFile(self, xmlFile, key) then
		return false
	end
	self.iaExpectedFieldState = self.iaExpectedFieldState or {}
	local legacy = string.format("%s.iaFieldOutcome", key)
	local function readFarmlandId()
		if xmlFile:hasProperty(key .. "#farmlandId") then
			self.iaFieldFarmlandId = xmlFile:getValue(key .. "#farmlandId", self.iaFieldFarmlandId or FarmlandManager.NO_OWNER_FARM_ID)
		elseif xmlFile:hasProperty(legacy .. "#farmlandId") then
			self.iaFieldFarmlandId = xmlFile:getValue(legacy .. "#farmlandId", self.iaFieldFarmlandId or FarmlandManager.NO_OWNER_FARM_ID)
		end
	end
	readFarmlandId()
	for _, attr in ipairs(IAFieldOutcomeMission.OUTCOME_KEY_ORDER) do
		local flatPath = key .. "#" .. attr
		local legPath = legacy .. "#" .. attr
		if xmlFile:hasProperty(flatPath) then
			self.iaExpectedFieldState[attr] = xmlFile:getValue(flatPath, 0)
		elseif xmlFile:hasProperty(legPath) then
			self.iaExpectedFieldState[attr] = xmlFile:getValue(legPath, 0)
		end
	end
	return true
end

function IAFieldOutcomeMission:onSavegameLoaded()
	if self.iaFieldFarmlandId == nil and self.field ~= nil and self.field.farmland ~= nil and self.field.farmland.getId ~= nil then
		local ok, id = pcall(self.field.farmland.getId, self.field.farmland)
		if ok and id ~= nil then
			self.iaFieldFarmlandId = id
		end
	end
	IAFieldOutcomeMission:superClass().onSavegameLoaded(self)
	self:iaResolveField()
	self:iaPruneExpectedFieldStateForJobType()
	self:iaApplyWorkAreaTypesForFoSJob()
	if self.field ~= nil then
		self:iaRebuildProbePositions(self.field)
		self:iaApplyDynamicMissionPresentation(self.field, {})
	end
end

function IAFieldOutcomeMission:writeStream(streamId, connection)
	IAFieldOutcomeMission:superClass().writeStream(self, streamId, connection)
	streamWriteUInt32(streamId, self.iaFieldFarmlandId or 0)
	local keys = IAHelper_sortedMapKeys(self.iaExpectedFieldState or {})
	streamWriteUInt8(streamId, math.min(#keys, 255))
	for i = 1, math.min(#keys, 255) do
		local k = keys[i]
		streamWriteString(streamId, k)
		streamWriteInt32(streamId, self.iaExpectedFieldState[k] or 0)
	end
	streamWriteString(streamId, self.iaFoSFieldworkJob or "")
	streamWriteString(streamId, self.iaFoSNeighbourFirstName or "")
	streamWriteString(streamId, self.iaFoSSituationId or "")
end

function IAFieldOutcomeMission:readStream(streamId, connection)
	IAFieldOutcomeMission:superClass().readStream(self, streamId, connection)
	self.iaFieldFarmlandId = streamReadUInt32(streamId)
	local n = streamReadUInt8(streamId)
	self.iaExpectedFieldState = {}
	for _ = 1, n do
		local k = streamReadString(streamId)
		local v = streamReadInt32(streamId)
		if k ~= nil and k ~= "" then
			self.iaExpectedFieldState[k] = v
		end
	end
	self.iaFoSFieldworkJob = streamReadString(streamId)
	if self.iaFoSFieldworkJob == nil or self.iaFoSFieldworkJob == "" then
		self.iaFoSFieldworkJob = nil
	end
	self.iaFoSNeighbourFirstName = streamReadString(streamId)
	if self.iaFoSNeighbourFirstName == nil or self.iaFoSNeighbourFirstName == "" then
		self.iaFoSNeighbourFirstName = nil
	end
	self.iaFoSSituationId = streamReadString(streamId)
	if self.iaFoSSituationId == nil or self.iaFoSSituationId == "" then
		self.iaFoSSituationId = nil
	end
	self:iaPruneExpectedFieldStateForJobType()
	self:iaApplyWorkAreaTypesForFoSJob()
	self._iaFoSMissionPresentationPending = true
end
