--
-- FS25 - InteractiveNeighbours - Game Loop Helper
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 23.01.2026
-- @Version: 1.0.0.0
-- Helper class for scenario generation logic

IAGameLoopHelper = {}
IAGameLoopHelper._mt = Class(IAGameLoopHelper)
-- Minimum distance (meters) from player to a place for a situation to be created there (avoids spawning when player is nearby)
IAGameLoopHelper.MIN_PLAYER_DISTANCE_FOR_PLACE_SITUATION = 20
-- Allowed crops for "next crop" selection (must match crops used in situations/fields_of_stories_situations.xml seed and fieldwork)
IAGameLoopHelper.NEXT_CROP_WHITELIST_NAMES = {
	"CANOLA",
	"WHEAT",
	"BARLEY",
	"OAT",
	"SOYBEAN"
}

-- Daily fieldwork ordering (lower = earlier): harvest, seed, spray, fertilize subtypes, plow, harrow, cultivate — batch similar machines.
-- Keyed by IAFieldwork.JobType.* (canonical strings) so it tracks the enum without separate string drift.
IAGameLoopHelper.FIELDWORK_TYPE_PRIORITY = {
	[IAFieldwork.JobType.HARVEST] = 1,
	[IAFieldwork.JobType.SEED] = 2,
	[IAFieldwork.JobType.SPRAY] = 3,
	[IAFieldwork.JobType.MANURESPREADING] = 4,
	[IAFieldwork.JobType.SLURRYSPREADING] = 4,
	[IAFieldwork.JobType.FERTILIZEDSPREADING] = 4,
	[IAFieldwork.JobType.PLOW] = 5,
	[IAFieldwork.JobType.HARROW] = 6,
	[IAFieldwork.JobType.CULTIVATE] = 7,
	[IAFieldwork.JobType.IA_FIELD_OUTCOME] = 8,
}

-- Phone-accepted fieldwork uses IAFieldOutcomeMission only (no vanilla FertilizeMission / tryGenerateMission).

-- Inbound contract rings per schedule day: first at callPlayerHour:Minute, then at least +1 in-game hour from the previous actual ring.
IAGameLoopHelper.CONTRACT_CALL_MAX_RING_OPENS_PER_DAY = 3
IAGameLoopHelper.CONTRACT_CALL_RETRY_MIN_INGAME_MINUTES = 60
-- Maximum number of fields/farmlands a neighbour can outsource as contracts per day
IAGameLoopHelper.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_PER_DAY = 3

-- Create a new IAGameLoopHelper instance
-- @param table ianeighboursInstance - Reference to IANeighbours instance
function IAGameLoopHelper.new(ianeighboursInstance)
	local self = setmetatable({}, IAGameLoopHelper._mt)
	self.ianeighbours = ianeighboursInstance
	self.homebaseParking = IAHomebaseParking.new(ianeighboursInstance)
	return self
end

-- True if situation placetypes match runtime place.type or semantic basePlaceType (e.g. shop on player farm is type player_farm).
local function placeMatchesPlacetypes(place, placetypes)
	if place == nil or placetypes == nil or #placetypes == 0 then
		return false
	end
	if type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(place.type, placetypes) then
		return true
	end
	local sem = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
	if sem ~= nil and sem ~= place.type and type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(sem, placetypes) then
		return true
	end
	return false
end

-- Place sizeType values that situations must explicitly opt into via <placeSizes>; never selected by default.
local IA_EXCLUSIVE_PLACE_SIZE_TYPES = {
	["large_area"] = true,
}

--- True when the place's sizeType satisfies the situation config's <placeSizes> list.
-- - Empty/missing list: allow any size EXCEPT entries in IA_EXCLUSIVE_PLACE_SIZE_TYPES (opt-in only).
-- - Non-empty list: place.sizeType (case-insensitive) must equal one of the listed values.
local function placeMatchesRequestedSize(place, situationConfig)
	if place == nil then
		return false
	end
	local requested = situationConfig and situationConfig.placeSizes
	local st = (place.sizeType ~= nil) and string.lower(tostring(place.sizeType)) or nil

	if requested ~= nil and #requested > 0 then
		if st == nil then
			return false
		end
		if type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" then
			return IAHelper_valueEqualsAnyInArrayIgnoreCase(st, requested) == true
		end
		for _, item in ipairs(requested) do
			if string.lower(tostring(item)) == st then
				return true
			end
		end
		return false
	end

	if st ~= nil and IA_EXCLUSIVE_PLACE_SIZE_TYPES[st] == true then
		return false
	end
	return true
end

--- Rebuild IAGameLoopHelper._placesByTypeBuckets when #places changed.
function IAGameLoopHelper:rebuildPlacesByTypeBucketsIfNeeded()
	local places = self.ianeighbours and self.ianeighbours.places
	if places == nil then
		self._placesByTypeBuckets = nil
		self._placesByTypeBucketsLen = nil
		return
	end
	local n = #places
	if self._placesByTypeBuckets ~= nil and self._placesByTypeBucketsLen == n then
		return
	end
	local buckets = {}
	for _, place in ipairs(places) do
		if place ~= nil and place.type ~= nil then
			local t1 = string.lower(tostring(place.type))
			if buckets[t1] == nil then
				buckets[t1] = {}
			end
			table.insert(buckets[t1], place)
			local sem = (place.getSemanticType ~= nil and place:getSemanticType()) or nil
			if sem ~= nil then
				local t2 = string.lower(tostring(sem))
				if t2 ~= t1 then
					if buckets[t2] == nil then
						buckets[t2] = {}
					end
					table.insert(buckets[t2], place)
				end
			end
		end
	end
	self._placesByTypeBuckets = buckets
	self._placesByTypeBucketsLen = n
end

function IAGameLoopHelper:invalidatePlacesTypeBucketCache()
	self._placesByTypeBuckets = nil
	self._placesByTypeBucketsLen = nil
end

--- Union of places that might match placetypes (type / semantic buckets), deduped; each entry verified with placeMatchesPlacetypes.
function IAGameLoopHelper:collectPlacesMatchingPlacetypes(placetypes)
	self:rebuildPlacesByTypeBucketsIfNeeded()
	local buckets = self._placesByTypeBuckets
	if buckets == nil or placetypes == nil then
		return {}
	end
	local seen = {}
	local out = {}
	for _, pt in ipairs(placetypes) do
		local k = string.lower(tostring(pt))
		for _, place in ipairs(buckets[k] or {}) do
			if not seen[place] and placeMatchesPlacetypes(place, placetypes) then
				seen[place] = true
				table.insert(out, place)
			end
		end
	end
	return out
end

--- Priority rank for sorting fieldwork (unknown types last).
-- @param string|nil fieldworkLower - lowercase job string from config.fieldwork
-- @return number
function IAGameLoopHelper.getFieldworkPriorityRank(fieldworkLower)
	if fieldworkLower == nil or fieldworkLower == "" then
		return 999
	end
	local p = IAGameLoopHelper.FIELDWORK_TYPE_PRIORITY[fieldworkLower]
	if p ~= nil then
		return p
	end
	if IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" then
		local jt = IAFieldwork.normalizeFieldworkJobType(fieldworkLower)
		if jt ~= nil then
			local pj = IAGameLoopHelper.FIELDWORK_TYPE_PRIORITY[jt]
			if pj ~= nil then
				return pj
			end
		end
	end
	return 998
end

local function configIdSortKey(config)
	if config == nil or config.id == nil then
		return "\255"
	end
	local n = tonumber(config.id)
	if n ~= nil then
		return string.format("%012d", n)
	end
	return tostring(config.id)
end

local function compareFieldworkScheduleTasks(a, b)
	if a == nil or b == nil then
		return false
	end
	local ja = (a.config and a.config.fieldwork) and string.lower(tostring(a.config.fieldwork)) or ""
	local jb = (b.config and b.config.fieldwork) and string.lower(tostring(b.config.fieldwork)) or ""
	local ra = IAGameLoopHelper.getFieldworkPriorityRank(ja)
	local rb = IAGameLoopHelper.getFieldworkPriorityRank(jb)
	if ra ~= rb then
		return ra < rb
	end
	-- Field order is a per-neighbour, per-day random permutation (fieldOrderKey) instead of
	-- ascending farmlandId, so neighbours don't always start at their lowest field id.
	-- Falls back to farmlandId when no random key was assigned (e.g. legacy loaded rows).
	local fa = a.fieldOrderKey or a.farmlandId or 0
	local fb = b.fieldOrderKey or b.farmlandId or 0
	if fa ~= fb then
		return fa < fb
	end
	return configIdSortKey(a.config) < configIdSortKey(b.config)
end

-- True if the planned next crop may be sown in the current period (FruitType growthDataSeasonal.plantingAllowed),
-- or when that data is missing, if current month appears on any matching SEED situation (legacy XML months).
function IAGameLoopHelper:isSowingMonthForPlannedSeed(neighbour, farmlandId)
	if neighbour == nil or farmlandId == nil or self.ianeighbours.situationConfigs == nil then
		return false
	end
	local nextCrop = (neighbour.assignedFarmlandNextCrop ~= nil and neighbour.assignedFarmlandNextCrop[farmlandId] ~= nil)
		and neighbour.assignedFarmlandNextCrop[farmlandId]
		or self:getNextCropForField(neighbour, farmlandId)
	if nextCrop == nil then
		return false
	end
	local planting = iaIsFruitTypePlantingAllowedInPeriod(nextCrop)
	if planting == true then
		return true
	end
	if planting == false then
		return false
	end
	local currentMonth = getEnvironmentMonth1to12()
	if currentMonth == nil then
		return false
	end
	for _, config in ipairs(self.ianeighbours.situationConfigs) do
		if config ~= nil and config.type ~= nil and string.lower(tostring(config.type)) == "fieldwork"
			and config.fieldwork ~= nil and string.lower(tostring(config.fieldwork)) == "seed" then
			if self:doesSituationConfigMatchNeighbour(config, neighbour) then
				local seedIdx = IAFieldwork.resolveFruitTypeNameOrIndex(config.seedFruitTypeIndex)
				if seedIdx ~= nil and seedIdx == nextCrop and config.months ~= nil and #config.months > 0 then
					for _, monthNum in ipairs(config.months) do
						if currentMonth == (tonumber(monthNum) or monthNum) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

function IAGameLoopHelper:findSituationConfigById(situationId)
	if situationId == nil or self.ianeighbours.situationConfigs == nil then
		return nil
	end
	for _, config in ipairs(self.ianeighbours.situationConfigs) do
		if config ~= nil and tostring(config.id) == tostring(situationId) then
			return config
		end
	end
	return nil
end

--- True when an IAFieldOutcomeMission (player phone contract) is currently bound to the given farmland and not yet finished.
--- Falls back to scanning g_missionManager.missions when farmland.field.currentMission has not been set yet
--- (e.g. mission registered but startMission deferred). Active situations the AI started do not count here.
-- @param number farmlandId
-- @return boolean
function IAGameLoopHelper:hasActivePlayerFieldOutcomeForFarmland(farmlandId)
	if farmlandId == nil then
		return false
	end
	farmlandId = tonumber(farmlandId)
	if farmlandId == nil then
		return false
	end
	if g_farmlandManager ~= nil and type(g_farmlandManager.getFarmlands) == "function" then
		local farmlands = g_farmlandManager:getFarmlands()
		if farmlands ~= nil then
			for _, f in pairs(farmlands) do
				if f ~= nil and tonumber(f.id) == farmlandId and f.field ~= nil then
					local mission = f.field.currentMission
					if mission ~= nil and mission.farmId ~= nil then
						return true
					end
				end
			end
		end
	end
	if g_missionManager ~= nil and g_missionManager.missions ~= nil then
		for _, m in pairs(g_missionManager.missions) do
			if m ~= nil and m.iaFieldsOfStoriesMission == true then
				local mFarmland = m.iaFieldFarmlandId
				if mFarmland == nil and m.field ~= nil and type(m.field.getFarmlandId) == "function" then
					mFarmland = m.field:getFarmlandId()
				end
				if mFarmland ~= nil and tonumber(mFarmland) == farmlandId then
					if MissionStatus == nil or m.status == nil
						or m.status == MissionStatus.RUNNING
						or m.status == MissionStatus.PREPARING
						or m.status == MissionStatus.CREATED then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Build ordered daily queue from open candidates; mutates neighbour fieldwork schedule fields.
function IAGameLoopHelper:rebuildDailyFieldworkSchedule(neighbour)
	local year, month, dayIn = getEnvironmentYearMonthDayInPeriod()
	neighbour.fieldworkScheduleYear = year
	neighbour.fieldworkScheduleMonth = month
	neighbour.fieldworkScheduleDayInPeriod = dayIn
	neighbour.fieldworkScheduleTasks = {}
	neighbour.contractCallTriggerFiredForScheduleKey = nil
	neighbour.contractCallRingOpensCount = 0
	neighbour.contractCallRingAnsweredToday = false
	neighbour.contractFallbackToAiFiredForScheduleKey = nil
	neighbour.contractCallLastRingScheduleKey = nil
	neighbour.contractCallLastRingTotalMinutes = nil

	if IATestRunner ~= nil and type(IATestRunner.onScheduleRebuildBegin) == "function" then
		IATestRunner.onScheduleRebuildBegin(neighbour)
	end

	--- Normalized fieldwork key for daily planning (stubble_cultivation → harrow; sow → seed).
	local function fieldworkKeyForOutsource(cfg)
		local jt = (cfg ~= nil and cfg.fieldwork) and string.lower(tostring(cfg.fieldwork)) or ""
		if jt == "" then
			return ""
		end
		if jt == "harvest" then
			return "harvest"
		end
		if IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" then
			local n = IAFieldwork.normalizeFieldworkJobType(jt)
			if n ~= nil then
				return n
			end
		end
		return jt
	end

	local all = self:collectOpenFieldworkCandidates(neighbour)
	if #all == 0 then
		return
	end

	local byField = {}
	for _, c in ipairs(all) do
		local fid = c.farmlandId
		if byField[fid] == nil then
			byField[fid] = {}
		end
		table.insert(byField[fid], c)
	end

	local chosen = {}
	for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
		local matches = byField[farmlandId]
		if matches ~= nil and #matches > 0 then
			local urgent = self:isSowingMonthForPlannedSeed(neighbour, farmlandId)
			if urgent then
				local bestByJob = {}
				for _, c in ipairs(matches) do
					local jt = fieldworkKeyForOutsource(c.config)
					local prev = bestByJob[jt]
					if prev == nil or configIdSortKey(c.config) < configIdSortKey(prev.config) then
						bestByJob[jt] = c
					end
				end
				for _, c in pairs(bestByJob) do
					table.insert(chosen, c)
				end
			else
				local best = nil
				for _, c in ipairs(matches) do
					local jt = (c.config and c.config.fieldwork) and string.lower(tostring(c.config.fieldwork)) or ""
					local rank = IAGameLoopHelper.getFieldworkPriorityRank(jt)
					if best == nil then
						best = c
					else
						local bjt = string.lower(tostring(best.config.fieldwork))
						local br = IAGameLoopHelper.getFieldworkPriorityRank(bjt)
						if rank < br or (rank == br and configIdSortKey(c.config) < configIdSortKey(best.config)) then
							best = c
						end
					end
				end
				if best ~= nil then
					table.insert(chosen, best)
				end
			end
		end
	end

	-- Randomize the order fields are worked so neighbours don't always start at their lowest field id.
	-- Build a shuffled permutation of this neighbour's assigned farmlands (stable for the whole game day,
	-- since rebuild only runs on day change) and assign each task its field's position in that permutation.
	-- compareFieldworkScheduleTasks uses this fieldOrderKey instead of ascending farmlandId.
	local fieldOrderKeyByFarmland = {}
	do
		local ids = {}
		for _, fid in ipairs(neighbour.assignedFarmlands) do
			table.insert(ids, fid)
		end
		for i = #ids, 2, -1 do
			local j = math.random(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end
		for rank, fid in ipairs(ids) do
			fieldOrderKeyByFarmland[fid] = rank
		end
	end
	for _, c in ipairs(chosen) do
		c.fieldOrderKey = fieldOrderKeyByFarmland[c.farmlandId]
	end

	table.sort(chosen, compareFieldworkScheduleTasks)

	-- One outsourced fieldwork type per day (random among types present); harvest is never outsourced.
	-- Also exclude the job type the neighbour is currently performing in an active fieldwork
	-- situation: offering contracts for the same job type would race with the implements that
	-- the active AI run still needs (slurry tank, fertilizer spreader, ...).
	local activeJobTypeKey = nil
	if neighbour.activeSituation ~= nil and neighbour.activeSituation.jobType ~= nil then
		local rawActive = string.lower(tostring(neighbour.activeSituation.jobType))
		if IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" then
			local norm = IAFieldwork.normalizeFieldworkJobType(rawActive)
			if norm ~= nil and norm ~= "" then
				activeJobTypeKey = norm
			end
		end
		if activeJobTypeKey == nil and rawActive ~= "" then
			activeJobTypeKey = rawActive
		end
	end

	local distinctNonHarvestTypes = {}
	local seenType = {}
	for _, c in ipairs(chosen) do
		local key = fieldworkKeyForOutsource(c.config)
		local skip = false
		if key == "" or key == "harvest" then
			skip = true
		end
		if activeJobTypeKey ~= nil and key == activeJobTypeKey then
			skip = true
		end
		if not skip and not seenType[key] then
			seenType[key] = true
			table.insert(distinctNonHarvestTypes, key)
		end
	end
	local outsourcedJobType = nil
	if #distinctNonHarvestTypes > 0 then
		outsourcedJobType = distinctNonHarvestTypes[math.random(1, #distinctNonHarvestTypes)]
	end
	if self.ianeighbours.debug and activeJobTypeKey ~= nil then
		print("--- IAGameLoopHelper:rebuildDailyFieldworkSchedule() - excluded active jobType '" .. tostring(activeJobTypeKey) .. "' from outsource pool for " .. tostring(neighbour.name))
	end

	local function rowIsContractForOutsource(c)
		local key = fieldworkKeyForOutsource(c.config)
		if key == "harvest" then
			return false
		end
		return outsourcedJobType ~= nil and key == outsourcedJobType
	end

	local aiFirst = {}
	local contractTail = {}
	for _, c in ipairs(chosen) do
		if rowIsContractForOutsource(c) then
			table.insert(contractTail, c)
		else
			table.insert(aiFirst, c)
		end
	end
	local ordered = {}
	for _, c in ipairs(aiFirst) do
		table.insert(ordered, c)
	end
	for _, c in ipairs(contractTail) do
		table.insert(ordered, c)
	end

	local contractFieldCount = 0
	local maxContractFields = IAGameLoopHelper.CONTRACT_MAX_FIELDS_PER_NEIGHBOUR_PER_DAY
	-- Read from player setting; -1 means unlimited (no cap).
	if IASettings ~= nil and type(IASettings.getContractMaxFieldsPerNeighbour) == "function" then
		local settingCap = IASettings.getContractMaxFieldsPerNeighbour()
		if settingCap ~= nil then
			maxContractFields = settingCap
		end
	end
	for _, c in ipairs(ordered) do
		local row = {
			situationId = c.config.id,
			farmlandId = c.farmlandId,
		}
		if c.nextCropFruitTypeIndex ~= nil then
			row.seedFruitTypeIndex = c.nextCropFruitTypeIndex
		end
		if rowIsContractForOutsource(c) then
			if maxContractFields < 0 or contractFieldCount < maxContractFields then
				row.contractEnabled = true
				contractFieldCount = contractFieldCount + 1
			end
			-- Remaining contract-eligible rows become plain AI work (no contractEnabled flag)
		end
		table.insert(neighbour.fieldworkScheduleTasks, row)
	end

	-- Daily random call window (hour 8..14 inclusive, minute 0..59). Set once per game day (rebuild only runs on day change via ensureDailyFieldworkSchedule).
	neighbour.callPlayerHour = math.random(8, 14)
	neighbour.callPlayerMinute = math.random(0, 59)

	if IATestRunner ~= nil and type(IATestRunner.onScheduleRebuildEnd) == "function" then
		IATestRunner.onScheduleRebuildEnd(neighbour, outsourcedJobType)
	end

	if self.ianeighbours.debug then
		local contractCount = 0
		for _, t in ipairs(neighbour.fieldworkScheduleTasks) do
			if t.contractEnabled then contractCount = contractCount + 1 end
		end
		print("--- IAGameLoopHelper:rebuildDailyFieldworkSchedule() - "..tostring(neighbour.name).." y="..tostring(year).." m="..tostring(month).." d="..tostring(dayIn).." tasks="..tostring(#neighbour.fieldworkScheduleTasks).." outsourceType="..tostring(outsourcedJobType or "none").." contracts="..tostring(contractCount).." callAt="..string.format("%02d:%02d", neighbour.callPlayerHour, neighbour.callPlayerMinute))
	end
end

--- Apply completed field state for every still-valid row on yesterday's schedule (day rollover, before rebuild).
--- Skips accepted contracts (active mission), already-worked fields, and stale rows via validateScheduleEntry.
function IAGameLoopHelper:autoCompleteScheduledFieldworkAtDayEnd(neighbour)
	if neighbour == nil or neighbour.fieldworkScheduleTasks == nil or #neighbour.fieldworkScheduleTasks == 0 then
		return
	end
	if IAFieldwork == nil or type(IAFieldwork.enqueueCompleteFieldworkFieldUpdate) ~= "function" then
		return
	end
	if g_farmlandManager == nil or type(g_farmlandManager.getFarmlands) ~= "function" then
		return
	end
	local completed = 0
	local tasks = neighbour.fieldworkScheduleTasks
	for _, row in ipairs(tasks) do
		local ok, err = pcall(function()
			-- Resolve the job type up front: harvest needs relaxed validation at day end (see below),
			-- so we must know the job before calling validateScheduleEntry.
			local rowConfig = self:findSituationConfigById(row ~= nil and row.situationId or nil)
			if rowConfig == nil or rowConfig.fieldwork == nil or rowConfig.fieldwork == "" then
				return
			end
			local jobType = nil
			if type(IAFieldwork.normalizeFieldworkJobType) == "function" then
				jobType = IAFieldwork.normalizeFieldworkJobType(string.lower(tostring(rowConfig.fieldwork)))
			end
			if jobType == nil then
				return
			end
			-- The calendar already rolled over before this runs, so the engine applied a day of growth
			-- and withering. A harvest-ready crop left unworked yesterday is now withered and no longer
			-- matches the situation's harvest growth trigger; relax the field-state trigger check for
			-- harvest so the withered crop is still cleared (harvested) here.
			local validateOpts = (jobType == IAFieldwork.JobType.HARVEST) and { skipFieldStateTriggerMatch = true } or nil
			local valid = self:validateScheduleEntry(neighbour, row, validateOpts)
			if valid == nil then
				return
			end
			local field = nil
			local farmlands = g_farmlandManager:getFarmlands()
			if farmlands ~= nil then
				for _, f in pairs(farmlands) do
					if f ~= nil and f.id == valid.farmlandId and f.field ~= nil then
						field = f.field
						break
					end
				end
			end
			if field == nil then
				return
			end
			local seedFruitTypeIndex = valid.nextCropFruitTypeIndex
			local fertilizeSprayTypeIndex = nil
			if type(IAFieldwork.getFertilizeSprayTypeIndexForJobType) == "function" then
				fertilizeSprayTypeIndex = IAFieldwork.getFertilizeSprayTypeIndexForJobType(jobType)
			end
			-- Day-end variant compensates for the elapsed day: seeded crops advance one growth stage
			-- (they would have grown overnight). Harvest leaves the field in its harvested (cut) state
			-- even when the crop withered overnight.
			local enqueued = false
			if type(IAFieldwork.enqueueCompleteFieldworkFieldUpdateForDayEnd) == "function" then
				enqueued = IAFieldwork.enqueueCompleteFieldworkFieldUpdateForDayEnd(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
			else
				IAFieldwork.enqueueCompleteFieldworkFieldUpdate(field, jobType, seedFruitTypeIndex, fertilizeSprayTypeIndex)
				enqueued = true
			end
			if enqueued then
				completed = completed + 1
			end
		end)
		if not ok and self.ianeighbours ~= nil and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:autoCompleteScheduledFieldworkAtDayEnd() - row failed: " .. tostring(err))
		end
	end
	if self.ianeighbours ~= nil and self.ianeighbours.debug then
		print("--- IAGameLoopHelper:autoCompleteScheduledFieldworkAtDayEnd() - " .. tostring(neighbour.name)
			.. " completed " .. tostring(completed) .. " of " .. tostring(#tasks) .. " scheduled tasks at day end")
	end
end

function IAGameLoopHelper:calendarDayMatchesStoredSchedule(neighbour)
	if neighbour == nil then
		return false
	end
	local y, m, d = getEnvironmentYearMonthDayInPeriod()
	if y == nil or m == nil or d == nil then
		return false
	end
	if neighbour.fieldworkScheduleYear == nil or neighbour.fieldworkScheduleMonth == nil or neighbour.fieldworkScheduleDayInPeriod == nil then
		return false
	end
	return neighbour.fieldworkScheduleYear == y
		and neighbour.fieldworkScheduleMonth == m
		and neighbour.fieldworkScheduleDayInPeriod == d
end

function IAGameLoopHelper:ensureDailyFieldworkSchedule(neighbour)
	if neighbour == nil then
		return
	end
	if neighbour.fieldworkScheduleTasks == nil then
		neighbour.fieldworkScheduleTasks = {}
	end
	if not self:calendarDayMatchesStoredSchedule(neighbour) then
		self:autoCompleteScheduledFieldworkAtDayEnd(neighbour)
		self:rebuildDailyFieldworkSchedule(neighbour)
	end
	if self:calendarDayMatchesStoredSchedule(neighbour)
		and neighbour.fieldworkScheduleTasks ~= nil
		and #neighbour.fieldworkScheduleTasks == 0 then
		-- Rebuilding here would reset contract-call bookkeeping and pick a new random outsource type
		-- for the same calendar day, causing a second ring with missions that were not in today's plan.
		local dayKey = self:getFieldworkScheduleDayKey(neighbour)
		if dayKey ~= nil and neighbour.contractCallTriggerFiredForScheduleKey == dayKey then
			return
		end
		self:rebuildDailyFieldworkSchedule(neighbour)
	end
end

-- How many contract inbound rings can still fit from callPlayerHour today (same minute each hour), capped at CONTRACT_CALL_MAX_RING_OPENS_PER_DAY.
function IAGameLoopHelper.getContractCallRingSlotsCountForCallHour(callPlayerHour)
	local h = tonumber(callPlayerHour)
	if h == nil or h < 0 or h > 23 then
		return 0
	end
	return math.min(IAGameLoopHelper.CONTRACT_CALL_MAX_RING_OPENS_PER_DAY, math.max(0, 24 - h))
end

-- Up to three in-game hourly slots (call time, +1h, +2h same minute); answering locks the rest of the day. Plan lock key set on first successful ring (see ensureDailyFieldworkSchedule).
function IAGameLoopHelper:evaluateContractPlayerCallTrigger(neighbour)
	if neighbour == nil or not neighbour.initialized then
		return
	end
	if neighbour.job ~= "Farmer" or neighbour.role ~= "Neighbour" then
		return
	end
	if IANeighbours ~= nil and type(IANeighbours.isPlayerInAnyConversation) == "function" and IANeighbours.isPlayerInAnyConversation() then
		return
	end
	if g_currentMission == nil or g_currentMission.environment == nil then
		return
	end
	self:ensureDailyFieldworkSchedule(neighbour)
	if not self:calendarDayMatchesStoredSchedule(neighbour) then
		return
	end
	if neighbour.callPlayerHour == nil or neighbour.callPlayerMinute == nil then
		return
	end
	local tasks = neighbour.fieldworkScheduleTasks
	if tasks == nil then
		return
	end
	local hasContract = false
	for _, row in ipairs(tasks) do
		if row ~= nil and row.contractEnabled == true then
			hasContract = true
			break
		end
	end
	if not hasContract then
		return
	end

	local env = g_currentMission.environment
	local curH = env.currentHour or 0
	local curM = env.currentMinute or 0
	local curTotal = curH * 60 + curM

	if g_inGameMenu ~= nil and g_inGameMenu.isOpen == true then
		return
	end
	local mi = g_currentMission.missionInfo
	if mi == nil or mi.timeScale == nil or mi.timeScale >= 500 then
		return
	end

	local scheduleKey = tostring(neighbour.fieldworkScheduleYear) .. "_" .. tostring(neighbour.fieldworkScheduleMonth) .. "_" .. tostring(neighbour.fieldworkScheduleDayInPeriod)

	if neighbour.contractCallRingAnsweredToday == true then
		return
	end

	local maxOpens = IAGameLoopHelper.getContractCallRingSlotsCountForCallHour(neighbour.callPlayerHour)
	if maxOpens <= 0 then
		return
	end

	local opens = tonumber(neighbour.contractCallRingOpensCount) or 0
	if opens >= maxOpens then
		return
	end

	if opens > 0 then
		local lastRingTotal = tonumber(neighbour.contractCallLastRingTotalMinutes)
		if neighbour.contractCallLastRingScheduleKey == scheduleKey and lastRingTotal ~= nil then
			local retryMinMinutes = tonumber(IAGameLoopHelper.CONTRACT_CALL_RETRY_MIN_INGAME_MINUTES) or 60
			if curTotal < lastRingTotal + retryMinMinutes then
				return
			end
		end
	end

	local slotHour = neighbour.callPlayerHour + opens
	if slotHour > 23 then
		return
	end
	local slotTotal = slotHour * 60 + (neighbour.callPlayerMinute or 0)
	if curTotal < slotTotal then
		return
	end

	-- Classic mission offer mode: no phone call rings at all.
	if IASettings ~= nil and type(IASettings.isMissionOfferModeClassic) == "function" then
		if IASettings.isMissionOfferModeClassic() then
			return
		end
	end

	-- Global per-day cap (IASettings.contractCallsPerDay): blocks any further contract rings
	-- across all neighbours today once the configured cap is reached. Per-neighbour retry slots
	-- above still apply within that budget.
	if IASettings ~= nil and type(IASettings.canTriggerContractCallNow) == "function" then
		if not IASettings.canTriggerContractCallNow() then
			return
		end
	end

	if IANeighbours ~= nil and type(IANeighbours.isGlobalInboundPhoneCooldownActive) == "function" then
		if IANeighbours.isGlobalInboundPhoneCooldownActive() then
			return
		end
	end

	local showedRing = neighbour:onContractCallTimeTriggered()
	if showedRing then
		neighbour.contractCallRingOpensCount = opens + 1
		neighbour.contractCallLastRingScheduleKey = scheduleKey
		neighbour.contractCallLastRingTotalMinutes = curTotal
		if neighbour.contractCallTriggerFiredForScheduleKey ~= scheduleKey then
			neighbour.contractCallTriggerFiredForScheduleKey = scheduleKey
		end
		if IASettings ~= nil and type(IASettings.recordContractCallTriggered) == "function" then
			IASettings.recordContractCallTriggered()
		end
	elseif IATestRunner ~= nil and IATestRunner._testActive then
		-- All guards passed (game time >= call window) but ring failed to show.
		-- Emit diagnostic so we can tell why the trigger didn't produce a payload.
		IATestRunner.emit("phone", "natural_ring_blocked", {
			neighbour = neighbour.name,
			reason = "onContractCallTimeTriggered returned false (all time/state guards passed)",
			callHour = neighbour.callPlayerHour,
			callMinute = neighbour.callPlayerMinute,
			curHour = curH,
			curMinute = curM,
			opens = opens,
			maxOpens = maxOpens,
			hasActiveSituation = neighbour.activeSituation ~= nil,
		})
	end
end

-- @return string|nil schedule day key "year_month_dayInPeriod"
function IAGameLoopHelper:getFieldworkScheduleDayKey(neighbour)
	if neighbour == nil or neighbour.fieldworkScheduleYear == nil or neighbour.fieldworkScheduleMonth == nil or neighbour.fieldworkScheduleDayInPeriod == nil then
		return nil
	end
	return tostring(neighbour.fieldworkScheduleYear) .. "_" .. tostring(neighbour.fieldworkScheduleMonth) .. "_" .. tostring(neighbour.fieldworkScheduleDayInPeriod)
end

-- Player accepted the full bundled contract offer: keep all rows in the daily schedule
-- but mark every contract-enabled row as acceptedByPlayer=true (and clear contractEnabled).
-- The schedule list stays complete; AI work selection (selectNewFieldwork) skips
-- acceptedByPlayer rows, and applyAcceptedContractMissionEndToSchedule restores them to
-- AI work on cancel/fail or removes them on success.
function IAGameLoopHelper:markAllContractRowsAsAcceptedByPlayer(neighbour)
	if neighbour == nil or neighbour.fieldworkScheduleTasks == nil then
		return
	end
	for _, row in ipairs(neighbour.fieldworkScheduleTasks) do
		if row ~= nil and row.contractEnabled == true then
			row.acceptedByPlayer = true
			row.contractEnabled = nil
		end
	end
end

-- Player accepted the first `takeCount` rows of a bundled contract offer.
-- Schedule rows matching openList[1..takeCount] by (situationId, farmlandId) are marked
-- acceptedByPlayer=true (and lose contractEnabled). Any remaining contract-enabled rows
-- are demoted to plain AI work (contractEnabled=nil). No row is removed from the
-- schedule: applyAcceptedContractMissionEndToSchedule later removes accepted rows on
-- success or clears acceptedByPlayer on cancel/fail. Identity matching avoids positional
-- drift when the offer list and the schedule iterate in different orders or when some
-- rows were pruned/blocked between call time and accept time.
-- @param IANeighbour neighbour
-- @param table openList contract offer list (each entry has .config.id and .farmlandId)
-- @param number takeCount how many of the first openList rows the player accepted
function IAGameLoopHelper:markAcceptedContractRowsAndDemoteRest(neighbour, openList, takeCount)
	if neighbour == nil or neighbour.fieldworkScheduleTasks == nil then
		return
	end
	if openList == nil or #openList == 0 or takeCount == nil or takeCount <= 0 then
		return
	end

	local acceptedKeys = {}
	local limit = math.min(takeCount, #openList)
	for i = 1, limit do
		local row = openList[i]
		local sid = (row ~= nil and row.config ~= nil and row.config.id ~= nil) and tostring(row.config.id) or nil
		local fid = (row ~= nil) and tonumber(row.farmlandId) or nil
		if sid ~= nil and fid ~= nil then
			acceptedKeys[sid .. "|" .. fid] = true
		end
	end

	for _, row in ipairs(neighbour.fieldworkScheduleTasks) do
		if row ~= nil and row.contractEnabled == true then
			local sid = row.situationId ~= nil and tostring(row.situationId) or nil
			local fid = tonumber(row.farmlandId)
			if sid ~= nil and fid ~= nil and acceptedKeys[sid .. "|" .. fid] then
				row.acceptedByPlayer = true
				row.contractEnabled = nil
			else
				row.contractEnabled = nil
			end
		end
	end
end

-- Resolve a finished player-accepted contract mission against its source schedule row.
-- SUCCESS: the work is done -> remove the row from the schedule.
-- FAILED/CANCELED/TIMED_OUT: the player gave the work back -> clear acceptedByPlayer so
-- the neighbour AI can pick it up again.
-- Matches the row by (situationId, farmlandId); silently returns when the row no longer
-- exists (e.g. day rolled over, mission survived across day-rebuild).
-- @param IANeighbour neighbour owning neighbour
-- @param string situationId schedule row situation id
-- @param number farmlandId schedule row farmland id
-- @param number missionFinishState MissionFinishState.SUCCESS / FAILED / CANCELED / TIMED_OUT
function IAGameLoopHelper:applyAcceptedContractMissionEndToSchedule(neighbour, situationId, farmlandId, missionFinishState)
	if neighbour == nil or neighbour.fieldworkScheduleTasks == nil then
		return
	end
	if situationId == nil or farmlandId == nil then
		return
	end
	local sid = tostring(situationId)
	local fid = tonumber(farmlandId)
	if sid == "" or fid == nil then
		return
	end
	local tasks = neighbour.fieldworkScheduleTasks
	for i = 1, #tasks do
		local row = tasks[i]
		if row ~= nil
			and row.acceptedByPlayer == true
			and row.situationId ~= nil
			and tostring(row.situationId) == sid
			and tonumber(row.farmlandId) == fid
		then
			if MissionFinishState ~= nil and missionFinishState == MissionFinishState.SUCCESS then
				table.remove(tasks, i)
				if self.ianeighbours ~= nil and self.ianeighbours.debug then
					print("--- IAGameLoopHelper:applyAcceptedContractMissionEndToSchedule() - SUCCESS removed row sid=" .. sid .. " fid=" .. tostring(fid) .. " neighbour=" .. tostring(neighbour.name))
				end
			else
				row.acceptedByPlayer = nil
				if self.ianeighbours ~= nil and self.ianeighbours.debug then
					print("--- IAGameLoopHelper:applyAcceptedContractMissionEndToSchedule() - non-SUCCESS (" .. tostring(missionFinishState) .. ") restored row to AI work sid=" .. sid .. " fid=" .. tostring(fid) .. " neighbour=" .. tostring(neighbour.name))
				end
			end
			return
		end
	end
end

local function iaResolveSeedFruitTypeIndex(openFieldwork)
	if openFieldwork == nil then
		return nil
	end
	local idx = openFieldwork.nextCropFruitTypeIndex
	if idx ~= nil then
		return idx
	end
	-- If the situation config explicitly names a seed fruit type, prefer that.
	local cfg = openFieldwork.config
	if cfg ~= nil and cfg.seedFruitTypeIndex ~= nil and cfg.seedFruitTypeIndex ~= "" then
		local resolved = IAFieldwork.resolveFruitTypeNameOrIndex(cfg.seedFruitTypeIndex)
		if resolved ~= nil then
			return resolved
		end
	end
	-- Fallback: pick any seeding-enabled fruit type that is marked for field missions.
	if g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypes ~= nil then
		for _, ft in ipairs(g_fruitTypeManager:getFruitTypes()) do
			if ft ~= nil and ft.index ~= nil and ft.useForFieldMissions and ft.allowsSeeding then
				return ft.index
			end
		end
	end
	return nil
end

--- Build expected FieldState keys for IAFieldOutcomeMission (phone contracts).
-- Base from IAFieldwork.getExpectedFieldStateAfterJob (seed + fertilize spray from config), then situation fieldStateOutcome; fertilize sprayType from tools wins over XML.
function IAGameLoopHelper:buildPhoneFieldStateOutcome(openFieldwork, field)
	local config = openFieldwork.config
	local out = {}
	local jobStr = (config ~= nil and config.fieldwork ~= nil and config.fieldwork ~= "") and string.lower(tostring(config.fieldwork)) or ""
	local jobEnum = (IAFieldwork ~= nil and IAFieldwork.normalizeFieldworkJobType ~= nil) and IAFieldwork.normalizeFieldworkJobType(jobStr) or nil

	local seedIdx = nil
	if jobEnum == IAFieldwork.JobType.SEED then
		seedIdx = iaResolveSeedFruitTypeIndex(openFieldwork)
		if seedIdx ~= nil then
			openFieldwork.nextCropFruitTypeIndex = seedIdx
		end
	end

	local fertSpray = nil
	if IAFieldwork ~= nil and IAFieldwork.isFertilizeJobType(jobEnum) and type(IAFieldwork.getFertilizeSprayTypeIndexForJobType) == "function" then
		fertSpray = IAFieldwork.getFertilizeSprayTypeIndexForJobType(jobEnum)
	end

	if IAFieldwork ~= nil and IAFieldwork.getExpectedFieldStateAfterJob ~= nil and jobEnum ~= nil and field ~= nil then
		local base = IAFieldwork.getExpectedFieldStateAfterJob(jobEnum, field, seedIdx, fertSpray)
		for k, v in pairs(base) do
			if type(k) == "string" and type(v) == "number" then
				out[k] = v
			end
		end
	end

	if config ~= nil and config.fieldStateOutcome ~= nil then
		for k, v in pairs(config.fieldStateOutcome) do
			if type(k) == "string" and type(v) == "number" then
				out[k] = v
			end
		end
	end

	if IAFieldwork.isFertilizeJobType(jobEnum) and fertSpray ~= nil then
		out.sprayType = fertSpray
	end

	-- triggerFruitTypeIndex lists acceptable crops for *offering* the job, not a post-job outcome (spray/fertilize/etc. do not change crop).
	if jobEnum == IAFieldwork.JobType.SEED and config ~= nil and config.triggerFruitTypeIndex ~= nil and config.triggerFruitTypeIndex[1] ~= nil and out.fruitTypeIndex == nil then
		local idx = IAFieldwork.resolveFruitTypeNameOrIndex(config.triggerFruitTypeIndex[1])
		if idx ~= nil then
			out.fruitTypeIndex = idx
		end
	end

	return out
end

--- True when the field's actual state at its center already matches the expected post-job outcome built for the given openFieldwork row.
-- Used as a preflight to drop scheduled rows whose work the player (or anyone) already completed before the row could be offered.
-- @param table openFieldwork row carrying at least .config (situation config) and .farmlandId; same shape returned by validateScheduleEntry
-- @param table field live field reference (farmland.field) for the row's farmlandId
-- @return boolean true when the center probe satisfies every expected key (job already done)
function IAGameLoopHelper:isFieldActualStateMatching(openFieldwork, field)
	if openFieldwork == nil or openFieldwork.config == nil or field == nil then
		return false
	end
	if IAFieldOutcomeMissionProbeEvaluator == nil or type(IAFieldOutcomeMissionProbeEvaluator.probeSatisfiesExpected) ~= "function" then
		return false
	end
	if FieldState == nil or type(FieldState.new) ~= "function" then
		return false
	end
	if type(field.getCenterOfFieldWorldPosition) ~= "function" then
		return false
	end

	local expected = self:buildPhoneFieldStateOutcome(openFieldwork, field)
	local jobRaw = (openFieldwork.config.fieldwork ~= nil and openFieldwork.config.fieldwork ~= "") and string.lower(tostring(openFieldwork.config.fieldwork)) or nil
	local jobEnum = (IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" and jobRaw ~= nil) and IAFieldwork.normalizeFieldworkJobType(jobRaw) or nil
	if IAFieldwork ~= nil and type(IAFieldwork.pruneExpectedFieldStateForValidation) == "function" then
		IAFieldwork.pruneExpectedFieldStateForValidation(expected, jobEnum)
	end

	local nExpected = 0
	for _ in pairs(expected) do
		nExpected = nExpected + 1
	end
	if nExpected == 0 then
		return false
	end

	local cx, cz = field:getCenterOfFieldWorldPosition()
	if cx == nil or cz == nil then
		return false
	end
	local probe = FieldState.new()
	if probe == nil or type(probe.update) ~= "function" then
		return false
	end
	local ok = pcall(probe.update, probe, cx, cz)
	if not ok then
		return false
	end
	return IAFieldOutcomeMissionProbeEvaluator.probeSatisfiesExpected(expected, jobRaw, probe)
end

--- Create and register IAFieldOutcomeMission for one openFieldwork row (phone accept). No vanilla mission types.
-- Server-only: add/start must run on server in MP.
-- @param table openFieldwork { farmlandId, config, nextCropFruitTypeIndex? }
-- @param number farmId
-- @param boolean spawnVehicles
-- @param boolean startNow if true attempts g_missionManager:startMission (otherwise only addMission)
-- @return table|nil mission
-- @return any|nil startState
function IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork(openFieldwork, farmId, spawnVehicles, startNow, usesBorrowedEquipment)
	if openFieldwork == nil or openFieldwork.farmlandId == nil or openFieldwork.config == nil then
		return nil, nil
	end
	if g_server == nil or g_missionManager == nil then
		return nil, nil
	end
	if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
		return nil, nil
	end

	local jobType = (openFieldwork.config.fieldwork ~= nil and openFieldwork.config.fieldwork ~= "") and string.lower(tostring(openFieldwork.config.fieldwork)) or nil
	local field = IAHelper_getFieldForFarmlandId(openFieldwork.farmlandId)
	if field == nil then
		if self.ianeighbours and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork() - No field for farmlandId=" .. tostring(openFieldwork.farmlandId) .. " jobType=" .. tostring(jobType))
		end
		return nil, nil
	end
	if field.currentMission ~= nil and field.currentMission.farmId ~= nil then
		if self.ianeighbours and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork() - Field already has active mission farmlandId=" .. tostring(openFieldwork.farmlandId) .. " jobType=" .. tostring(jobType))
		end
		return nil, nil
	end

	if IAFieldOutcomeMission == nil or type(IAFieldOutcomeMission.new) ~= "function" then
		return nil, nil
	end
	local expected = self:buildPhoneFieldStateOutcome(openFieldwork, field)
	local nExpected = 0
	for _ in pairs(expected) do
		nExpected = nExpected + 1
	end
	if nExpected == 0 then
		if self.ianeighbours and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork() - No expected FieldState keys (add fieldStateOutcome and/or triggers) jobType=" .. tostring(jobType) .. " farmlandId=" .. tostring(openFieldwork.farmlandId))
		end
		return nil, nil
	end

	local mission = IAFieldOutcomeMission.new(true, g_client ~= nil)
	local fwRaw = openFieldwork.config.fieldwork
	if mission == nil
		or not mission:initFromField(field, expected, {
			fieldworkRaw = fwRaw,
			neighbourFirstName = openFieldwork.neighbourFirstName,
			neighbourId = openFieldwork.neighbourId,
			situationId = openFieldwork.config ~= nil and openFieldwork.config.id or nil,
			usesBorrowedEquipment = usesBorrowedEquipment == true,
		})
	then
		if mission ~= nil and type(mission.delete) == "function" then
			mission:delete()
		end
		if self.ianeighbours and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork() - IAFieldOutcomeMission init failed jobType=" .. tostring(jobType) .. " farmlandId=" .. tostring(openFieldwork.farmlandId))
		end
		return nil, nil
	end
	local missionType = g_missionManager:getMissionType(IAFieldOutcomeMission.NAME)
	if missionType == nil then
		if type(mission.delete) == "function" then
			mission:delete()
		end
		return nil, nil
	end
	mission.iaFieldsOfStoriesMission = true
	mission.iaFoSRestoreSpawnVehicles = spawnVehicles == true
	g_missionManager:registerMission(mission, missionType)
	if type(g_missionManager.updateMissions) == "function" then
		g_missionManager:updateMissions(0)
	end

	local startState = nil
	if startNow == true then
		if IAFieldOutcomeMission ~= nil and IAFieldOutcomeMission.tryStartAfterRegisterOrDefer ~= nil then
			IAFieldOutcomeMission.tryStartAfterRegisterOrDefer(mission, farmId, spawnVehicles == true)
			if MissionStartState ~= nil and MissionStartState.OK ~= nil then
				startState = mission.status ~= MissionStatus.CREATED and MissionStartState.OK or nil
			else
				startState = true
			end
		else
			local okStart, resStart = pcall(g_missionManager.startMission, g_missionManager, mission, farmId, spawnVehicles == true)
			if okStart then
				startState = resStart
			else
				startState = nil
				if self.ianeighbours and self.ianeighbours.debug then
					print("--- IAGameLoopHelper:createAndRegisterFieldMissionForOpenFieldwork() - startMission ERROR jobType=" .. tostring(jobType) .. " farmlandId=" .. tostring(openFieldwork.farmlandId) .. " err=" .. tostring(resStart))
				end
				if type(mission.delete) == "function" then
					mission:delete()
				end
				return nil, nil
			end
		end
	end
	return mission, startState
end

--- Create missions for a list of openFieldwork rows (e.g. bundled phone offer).
-- Starts every mission (startMission); if MissionManager blocks (PREPARING), IAFieldOutcomeMission defers until updateMissions allows it.
-- @param table openList array of openFieldwork rows
-- @param number farmId
-- @param boolean spawnVehicles
-- @param number|nil maxCount optional cap (take first N rows)
-- @return number addedCount
-- @return number startedCount
function IAGameLoopHelper:createAndRegisterFieldMissionsForOpenFieldworkList(openList, farmId, spawnVehicles, maxCount)
	if openList == nil or #openList == 0 then
		return 0, 0
	end
	local added = 0
	local started = 0
	local limit = maxCount ~= nil and math.max(0, tonumber(maxCount) or 0) or #openList
	for i, row in ipairs(openList) do
		if i > limit then
			break
		end
		local m = select(1, self:createAndRegisterFieldMissionForOpenFieldwork(row, farmId, spawnVehicles, true, spawnVehicles == true))
		if m ~= nil then
			added = added + 1
			-- Deferred starts stay CREATED until MissionManager.updateMissions; count only immediate transitions.
			if MissionStatus ~= nil and m.status ~= MissionStatus.CREATED then
				started = started + 1
			end
		end
	end
	return added, started
end

--- Create phone field missions and start a borrow session for neighbour fleet implements.
-- @param IANeighbour neighbour
-- @param table openList
-- @param number farmId
-- @param number|nil maxCount
-- @return number addedCount
-- @return number startedCount
-- @return string|nil sessionId
function IAGameLoopHelper:createAndRegisterFieldMissionsWithBorrow(neighbour, openList, farmId, maxCount)
	if neighbour == nil or openList == nil or #openList == 0 or IAMissionBorrow == nil then
		return 0, 0, nil
	end
	local units = self:collectMissionBorrowUnitsForOpenList(neighbour, openList, maxCount)
	if #units == 0 then
		return 0, 0, nil
	end
	local missions = {}
	local added = 0
	local started = 0
	local limit = maxCount ~= nil and math.max(0, tonumber(maxCount) or 0) or #openList
	for i, row in ipairs(openList) do
		if i > limit then
			break
		end
		local m = select(1, self:createAndRegisterFieldMissionForOpenFieldwork(row, farmId, false, true, true))
		if m ~= nil then
			added = added + 1
			table.insert(missions, m)
			if MissionStatus ~= nil and m.status ~= MissionStatus.CREATED then
				started = started + 1
			end
		end
	end
	if added == 0 then
		return 0, 0, nil
	end
	local sessionId = IAMissionBorrow.startSession(neighbour, missions, units, openList)
	return added, started, sessionId
end

-- 15:00 fallback: treat pending contract rows as normal AI work for the rest of the day.
function IAGameLoopHelper:clearContractFlagsOnSchedule(neighbour)
	if neighbour == nil or neighbour.fieldworkScheduleTasks == nil then
		return
	end
	for _, row in ipairs(neighbour.fieldworkScheduleTasks) do
		if row ~= nil and row.contractEnabled == true then
			row.contractEnabled = false
		end
	end
end

-- @param table farmlandIds number[] unique farmland ids
-- @return number total hectares rounded to whole number
function IAGameLoopHelper:sumRoundedHectaresForFarmlandIds(farmlandIds)
	if farmlandIds == nil or #farmlandIds == 0 or g_farmlandManager == nil or g_farmlandManager.getFarmlands == nil then
		return 0
	end
	local totalHa = 0
	local farmlands = g_farmlandManager:getFarmlands()
	for _, fid in ipairs(farmlandIds) do
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == fid then
				if f.areaInHa ~= nil then
					totalHa = totalHa + f.areaInHa
				end
				break
			end
		end
	end
	return math.floor(totalHa + 0.5)
end

-- Pending contract rows become normal AI work (player declined or 15:00 fallback). Returns true if flags were cleared.
-- @param string|nil reason debug label e.g. "decline", "1500"
function IAGameLoopHelper:applyContractFallbackToAi(neighbour, reason)
	if neighbour == nil or not neighbour.initialized then
		return false
	end
	if neighbour.job ~= "Farmer" or neighbour.role ~= "Neighbour" then
		return false
	end
	self:ensureDailyFieldworkSchedule(neighbour)
	if not self:calendarDayMatchesStoredSchedule(neighbour) then
		return false
	end
	local tasks = neighbour.fieldworkScheduleTasks
	if tasks == nil then
		return false
	end
	local hasPendingContract = false
	for _, row in ipairs(tasks) do
		if row ~= nil and row.contractEnabled == true then
			hasPendingContract = true
			break
		end
	end
	if not hasPendingContract then
		return false
	end
	local scheduleKey = self:getFieldworkScheduleDayKey(neighbour)
	if scheduleKey == nil then
		return false
	end
	if neighbour.contractFallbackToAiFiredForScheduleKey == scheduleKey then
		return false
	end
	neighbour.contractFallbackToAiFiredForScheduleKey = scheduleKey
	self:clearContractFlagsOnSchedule(neighbour)
	if self.ianeighbours ~= nil and self.ianeighbours.debug then
		print("--- IAGameLoopHelper:applyContractFallbackToAi() - " .. tostring(neighbour.name) .. " scheduleKey=" .. scheduleKey .. " reason=" .. tostring(reason or "?") .. " cleared pending contract flags")
	end
	return true
end

-- Once per schedule day at in-game 15:00+: pending contract rows become normal AI tasks if the player never accepted.
function IAGameLoopHelper:evaluateContractFallbackToAiAt1500(neighbour)
	if neighbour == nil or not neighbour.initialized then
		return
	end
	if neighbour.job ~= "Farmer" or neighbour.role ~= "Neighbour" then
		return
	end
	if g_currentMission == nil or g_currentMission.environment == nil then
		return
	end
	local env = g_currentMission.environment
	local curH = env.currentHour or 0
	local curM = env.currentMinute or 0
	if curH * 60 + curM < 15 * 60 then
		return
	end
	if g_inGameMenu ~= nil and g_inGameMenu.isOpen == true then
		return
	end
	local mi = g_currentMission.missionInfo
	if mi == nil or mi.timeScale == nil or mi.timeScale >= 500 then
		return
	end
	self:applyContractFallbackToAi(neighbour, "1500")
end

-- Validate a persisted schedule row against live field + config; returns same shape as getOpenFieldwork or nil.
-- @param table|nil opts { skipFieldStateTriggerMatch=bool } - when set, skips the doesFieldMatchSituationConfig
--        trigger check (used by day-end auto-completion of harvest, where the crop has already withered overnight
--        and no longer matches the harvest growth trigger but must still be cleared).
function IAGameLoopHelper:validateScheduleEntry(neighbour, entry, opts)
	-- Debug helper: logs why a (seed) contract row is being rejected. Rows can show
	-- [CONTRACT] in the Shift+F3 schedule yet never ring because they fail re-validation
	-- here at call time; seed has extra gates (planting calendar + crop match) the other
	-- job types skip, so these logs pinpoint which gate dropped the row.
	local debugOn = self.ianeighbours ~= nil and self.ianeighbours.debug == true
	local function iaResolveFruitName(idx)
		if idx == nil then
			return "nil"
		end
		if g_fruitTypeManager ~= nil and type(g_fruitTypeManager.getFruitTypeByIndex) == "function" then
			local ft = g_fruitTypeManager:getFruitTypeByIndex(idx)
			if ft ~= nil and ft.name ~= nil then
				return tostring(ft.name) .. " (" .. tostring(idx) .. ")"
			end
		end
		return tostring(idx)
	end
	local function rejectLog(reason)
		IAprintDebug("IAGameLoopHelper:validateScheduleEntry","REJECT ["
			.. tostring(reason) .. "] farmlandId=" .. tostring(entry and entry.farmlandId)
			.. " situationId=" .. tostring(entry and entry.situationId), neighbour, nil, nil)
	end

	if neighbour == nil or entry == nil or entry.farmlandId == nil or entry.situationId == nil then
		IAprintDebug("IAGameLoopHelper:validateScheduleEntry","[nil-args] neighbour=" .. tostring(neighbour and neighbour.name or "?") .. " entry=" .. tostring(entry ~= nil), neighbour, nil, nil)
		return nil
	end
	-- Prevent contract offers for a field the neighbour is already working on right now.
	if neighbour.activeSituation ~= nil and neighbour.activeSituation.jobType ~= nil and neighbour.activeSituation.farmlandId ~= nil then
		if tonumber(neighbour.activeSituation.farmlandId) == tonumber(entry.farmlandId) then
			rejectLog("active-on-farmland")
			return nil
		end
	end
	local config = self:findSituationConfigById(entry.situationId)
	if config == nil then
		rejectLog("config-not-found")
		return nil
	end
	if config.type == nil or string.lower(tostring(config.type)) ~= "fieldwork" then
		rejectLog("config-not-fieldwork type=" .. tostring(config.type))
		return nil
	end
	local nextCropFruitTypeIndex = entry.seedFruitTypeIndex
	local fwLowerForMonth = config.fieldwork ~= nil and string.lower(tostring(config.fieldwork)) or nil
	if fwLowerForMonth == "seed" then
		if nextCropFruitTypeIndex == nil then
			nextCropFruitTypeIndex = (neighbour.assignedFarmlandNextCrop ~= nil and neighbour.assignedFarmlandNextCrop[entry.farmlandId] ~= nil)
				and neighbour.assignedFarmlandNextCrop[entry.farmlandId]
				or self:getNextCropForField(neighbour, entry.farmlandId)
		end
		if not iaFieldworkSeedCalendarAllowedForFruit(config, nextCropFruitTypeIndex) then
				IAprintDebug("--- IAGameLoopHelper:validateScheduleEntry() - REJECT [seed-calendar] neighbour=" .. tostring(neighbour.name)
					.. " farmlandId=" .. tostring(entry.farmlandId) .. " situationId=" .. tostring(entry.situationId)
					.. " nextCrop=" .. iaResolveFruitName(nextCropFruitTypeIndex)
					.. " configCrop=" .. tostring(config.seedFruitTypeIndex)
					.. " period=" .. tostring(getEnvironmentCurrentPeriodOrNil and getEnvironmentCurrentPeriodOrNil() or "?")
					.. " month=" .. tostring(getEnvironmentMonth1to12 and getEnvironmentMonth1to12() or "?")
					.. " (crop not plantable now / situation months do not match)", neighbour, nil, nil)
			return nil
		end
	elseif not iaSituationConfigMonthsMatchCurrent(config) then
		rejectLog("months-no-match fieldwork=" .. tostring(fwLowerForMonth) .. " month=" .. tostring(getEnvironmentMonth1to12 and getEnvironmentMonth1to12() or "?"))
		return nil
	end
	if not self:doesSituationConfigMatchNeighbour(config, neighbour) then
		rejectLog("neighbour-role/job-mismatch")
		return nil
	end

	local fwLower = config.fieldwork ~= nil and string.lower(tostring(config.fieldwork)) or nil

	local farmlands = g_farmlandManager:getFarmlands()
	local farmland = nil
	for _, f in pairs(farmlands) do
		if f ~= nil and f.id == entry.farmlandId then
			farmland = f
			break
		end
	end
	if farmland == nil or farmland.field == nil then
		rejectLog("no-farmland-or-field")
		return nil
	end
	-- Reject farmlands owned by the player (farmId 1 = player farm / farmId from g_localPlayer.farmId).
	-- This guards against stale schedule entries that were built before the player bought the field;
	-- updateFarmlands removes the field from assignedFarmlands but schedule rebuild only happens on day change.
	if farmland.isOwned == true and farmland.farmId ~= 99 then
		rejectLog("farmland-player-owned farmId=" .. tostring(farmland.farmId))
		return nil
	end
	-- ia_field_outcome: standalone mod mission; no cached fieldState / trigger-gate checks here (custom rules later).
	if fwLower ~= "ia_field_outcome" then
		if farmland.field.fieldState == nil then
			rejectLog("nil-fieldState")
			return nil
		end
	end
	local mission = farmland.field.currentMission
	if mission ~= nil and mission.farmId ~= nil then
		rejectLog("field-has-active-mission farmId=" .. tostring(mission.farmId))
		return nil
	end
	if self:hasActivePlayerFieldOutcomeForFarmland(entry.farmlandId) then
		rejectLog("active-player-field-outcome")
		return nil
	end
	local skipFieldStateTriggerMatch = opts ~= nil and opts.skipFieldStateTriggerMatch == true
	if fwLower ~= "ia_field_outcome" and not skipFieldStateTriggerMatch then
		if not self:doesFieldMatchSituationConfig(entry.farmlandId, farmland.field.fieldState, config) then
			local fs = farmland.field.fieldState
			IAprintDebug("--- IAGameLoopHelper:validateScheduleEntry() - REJECT [field-state-mismatch] neighbour=" .. tostring(neighbour.name)
				.. " farmlandId=" .. tostring(entry.farmlandId) .. " situationId=" .. tostring(entry.situationId)
				.. " fieldwork=" .. tostring(fwLower)
				.. " field(groundType=" .. tostring(fs and fs.groundType)
				.. ", fruitTypeIndex=" .. tostring(fs and fs.fruitTypeIndex)
				.. ", growthState=" .. tostring(fs and fs.growthState)
				.. ", weedState=" .. tostring(fs and fs.weedState)
				.. ", sprayLevel=" .. tostring(fs and fs.sprayLevel) .. ")"
				.. " (field no longer matches situation triggers)", neighbour, nil, nil)
			return nil
		end
	end

	local isSeed = config.fieldwork ~= nil and string.lower(tostring(config.fieldwork)) == "seed"
	if isSeed then
		if nextCropFruitTypeIndex == nil then
			nextCropFruitTypeIndex = (neighbour.assignedFarmlandNextCrop ~= nil and neighbour.assignedFarmlandNextCrop[entry.farmlandId] ~= nil)
				and neighbour.assignedFarmlandNextCrop[entry.farmlandId]
				or self:getNextCropForField(neighbour, entry.farmlandId)
		end
		if nextCropFruitTypeIndex ~= nil and config.seedFruitTypeIndex ~= nil and config.seedFruitTypeIndex ~= "" then
			local configSeedIndex = IAFieldwork.resolveFruitTypeNameOrIndex(config.seedFruitTypeIndex)
			if configSeedIndex == nil or configSeedIndex ~= nextCropFruitTypeIndex then
				IAprintDebug("--- IAGameLoopHelper:validateScheduleEntry() - REJECT [seed-crop-mismatch] neighbour=" .. tostring(neighbour.name)
						.. " farmlandId=" .. tostring(entry.farmlandId) .. " situationId=" .. tostring(entry.situationId)
						.. " nextCrop=" .. iaResolveFruitName(nextCropFruitTypeIndex)
						.. " configCrop=" .. tostring(config.seedFruitTypeIndex) .. " (resolved " .. tostring(configSeedIndex) .. ")"
						.. " (field's planned next crop differs from this seed situation's crop)", neighbour, nil, nil)
				return nil
			end
		end
	end

	local result = { farmlandId = entry.farmlandId, config = config }
	if nextCropFruitTypeIndex ~= nil then
		result.nextCropFruitTypeIndex = nextCropFruitTypeIndex
	end
	if neighbour.name ~= nil and tostring(neighbour.name) ~= "" then
		local first = tostring(neighbour.name):match("^%s*(%S+)")
		result.neighbourFirstName = first or tostring(neighbour.name)
	end
	if neighbour.id ~= nil then
		result.neighbourId = neighbour.id
	end
	if self:isFieldActualStateMatching(result, farmland.field) then
		if self.ianeighbours ~= nil and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:validateScheduleEntry() - Dropped already-completed field outcome farmlandId=" .. tostring(entry.farmlandId) .. " situationId=" .. tostring(entry.situationId))
		end
		return nil
	end
	return result
end

-- Build scenario table from open fieldwork row (shared by schedule dequeue and legacy path).
function IAGameLoopHelper:buildFieldworkScenarioFromOpenFieldwork(neighbour, openFieldwork)
	if neighbour == nil or openFieldwork == nil or openFieldwork.config == nil then
		return nil
	end
	local farmlandId = openFieldwork.farmlandId
	local fieldworkConfig = openFieldwork.config
	local jobTypeRaw = (fieldworkConfig.fieldwork ~= nil and fieldworkConfig.fieldwork ~= "") and string.lower(tostring(fieldworkConfig.fieldwork)) or nil
	local jobType = jobTypeRaw
	if IAFieldwork ~= nil and type(IAFieldwork.normalizeFieldworkJobType) == "function" and jobTypeRaw ~= nil then
		local jt = IAFieldwork.normalizeFieldworkJobType(jobTypeRaw)
		if jt ~= nil then
			jobType = jt
		end
	end

	local farmlands = g_farmlandManager:getFarmlands()
	local farmland = nil
	for _, f in pairs(farmlands) do
		if f ~= nil and f.id == farmlandId then
			farmland = f
			break
		end
	end
	if farmland == nil then
		return nil
	end

	local placeX = farmland.xWorldPos or 0
	local placeY = getTerrainHeightAtWorldPos(g_terrainNode, placeX, 0, farmland.zWorldPos or 0) or 0
	local placeZ = farmland.zWorldPos or 0
	local fieldworkPlace = IAMapPlace.new(
		nil,
		"Field "..tostring(farmlandId),
		"fieldwork",
		placeX,
		placeY,
		placeZ,
		0,
		true,
		true,
		nil,
		nil
	)

	local vehiclesData = self:GetVehiclesForSituation(neighbour.vehicles, fieldworkConfig)
	local situationVehicle = vehiclesData.vehicle
	local attachmentBack = vehiclesData.attachmentBack
	local attachmentFront = vehiclesData.attachmentFront

	if fieldworkConfig.vehicles ~= nil and string.lower(tostring(fieldworkConfig.vehicles)) == "force" and situationVehicle == nil then
		return nil
	end
	if situationVehicle == nil then
		situationVehicle = self:getRandomVehicleByType(neighbour.vehicles, "tractor")
	end
	if situationVehicle == nil then
		return nil
	end

	local result = {
		config = fieldworkConfig,
		place = fieldworkPlace,
		vehicle = situationVehicle,
		attachmentBack = attachmentBack,
		attachmentFront = attachmentFront,
		farmlandId = farmlandId,
		jobType = jobType,
	}
	if openFieldwork.nextCropFruitTypeIndex ~= nil then
		result.seedFruitTypeIndex = openFieldwork.nextCropFruitTypeIndex
	end
	local ok, _ = self:validateScenarioFleetVehicles(result)
	if not ok then
		return nil
	end
	return result
end

-- Get a fruit type index for "next crop" that is not the neighbour's stored last crop for this farmland.
-- Uses neighbour.assignedFarmlandLastCrop[farmlandId] (persisted); fieldState.fruitTypeIndex is not reliable before seeding.
-- Only crops in NEXT_CROP_WHITELIST_NAMES (matching situations XML) are considered.
-- @param IANeighbour neighbour - Neighbour who has this farmland assigned (holds assignedFarmlandLastCrop)
-- @param number farmlandId - Farmland ID
-- @return number|nil - A fruit type index different from last crop, or nil if none available
function IAGameLoopHelper:getNextCropForField(neighbour, farmlandId)
	if neighbour == nil or farmlandId == nil or g_fruitTypeManager == nil then
		return nil
	end
	local whitelist = IAGameLoopHelper.NEXT_CROP_WHITELIST_NAMES
	if whitelist == nil or #whitelist == 0 then
		return nil
	end
	local allowedIndices = {}
	for _, name in ipairs(whitelist) do
		local idx = IAFieldwork.resolveFruitTypeNameOrIndex(name)
		if idx ~= nil then
			allowedIndices[idx] = true
		end
	end
	local lastCrop = (neighbour.assignedFarmlandLastCrop ~= nil) and neighbour.assignedFarmlandLastCrop[farmlandId] or nil
	local fruitTypes = g_fruitTypeManager:getFruitTypes()
	if fruitTypes == nil then
		return nil
	end
	local candidates = {}
	for _, fruitType in ipairs(fruitTypes) do
		if fruitType ~= nil and fruitType.index ~= nil then
			if fruitType.index ~= lastCrop and allowedIndices[fruitType.index] then
				if FruitType.UNKNOWN == nil or fruitType.index ~= FruitType.UNKNOWN then
					table.insert(candidates, fruitType.index)
				end
			end
		end
	end
	if #candidates == 0 then
		if self.ianeighbours and self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getNextCropForField() - No candidates for "..tostring(neighbour and neighbour.name or "?").." farmland "..tostring(farmlandId).." (lastCrop "..tostring(lastCrop).."), trying whitelist fallback")
		end
		for _, name in ipairs(whitelist) do
			local fb = IAFieldwork.resolveFruitTypeNameOrIndex(name)
			if fb ~= nil and fb ~= lastCrop then
				return fb
			end
		end
		return nil
	end
	local chosen = candidates[math.random(1, #candidates)]
	if self.ianeighbours and self.ianeighbours.debug then
		local ft = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(chosen)
		local nameStr = (ft and ft.name) or tostring(chosen)
		print("--- IAGameLoopHelper:getNextCropForField() - "..tostring(neighbour.name).." farmland "..tostring(farmlandId).." lastCrop "..tostring(lastCrop).." -> next "..tostring(nameStr).." ("..tostring(chosen)..")")
	end
	return chosen
end

-- Check if a fieldwork situation config matches the neighbour (characterRoles, characterJobs).
-- If config has no characterRoles/characterJobs, it matches any neighbour.
-- @param IASituationConfig config - Fieldwork situation config
-- @param IANeighbour neighbour - The neighbour
-- @return boolean - true if config is valid for this neighbour
function IAGameLoopHelper:doesSituationConfigMatchNeighbour(config, neighbour)
	if config == nil or neighbour == nil then
		return false
	end
	if config.characterRoles ~= nil and #config.characterRoles > 0 then
		if not (type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(neighbour.role, config.characterRoles)) then
			return false
		end
	end
	if config.characterJobs ~= nil and #config.characterJobs > 0 then
		if not (type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(neighbour.job, config.characterJobs)) then
			return false
		end
	end
	return true
end

-- Check if a field's state matches a fieldwork situation config criteria (triggerGroundType, triggerFruitTypeIndex, triggerGrowthState, triggerWeedState, triggerSprayLevel).
-- Empty trigger lists mean "any" (no filter). All non-empty trigger lists must match.
-- @param table fieldState - farmland.field.fieldState (groundType, fruitTypeIndex, growthState, etc.)
-- @param IASituationConfig config - Fieldwork situation config
-- @return boolean - true if field matches situation criteria
function IAGameLoopHelper:doesFieldMatchSituationConfig(id,fieldState, config)
	if fieldState == nil or config == nil then
		return false
	end

	local fieldDebug = false--(self.ianeighbours ~= nil and self.ianeighbours.debug == true)

	if fieldDebug then
		print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Config: " .. tostring(config.id).." - "..tostring(config.fieldwork))
	end
	-- triggerGroundType: field's groundType (number) must be in config's list (XML stores as string "3", "4")
	if config.triggerGroundType ~= nil and #config.triggerGroundType > 0 then
		if fieldDebug then
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Ground Types: " .. arrayToString(config.triggerGroundType))
		end
		local fieldGroundType = fieldState.groundType
		if fieldGroundType == nil then
			return false
		end
		local matchesGround = false
		for _, gt in ipairs(config.triggerGroundType) do

			local gtName = FieldGroundType.getName(fieldGroundType)
			if fieldDebug then
				print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Ground Type: " .. tostring(gt) .. " - " .. tostring(fieldGroundType))
			end
			if tostring(fieldGroundType) == tostring(gt) then
				matchesGround = true
				if fieldDebug then
					print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Matches Ground Type: " .. tostring(fieldGroundType))
				end
				break
			end
		end
		if not matchesGround then
			return false
		end
	end
	-- triggerFruitTypeIndex: for harvest etc., field's fruitTypeIndex must match one of the config's fruit types
	if config.triggerFruitTypeIndex ~= nil and #config.triggerFruitTypeIndex > 0 then
		if fieldDebug then
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Fruit Type Indexes: " .. arrayToString(config.triggerFruitTypeIndex))
		end
		local fieldFruitTypeIndex = fieldState.fruitTypeIndex
		if fieldFruitTypeIndex == nil then
			return false
		end
		local matchesFruit = false
		for _, nameOrIndex in ipairs(config.triggerFruitTypeIndex) do
			local resolvedIndex = IAFieldwork.resolveFruitTypeNameOrIndex(nameOrIndex)
			if fieldDebug then
				print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Fruit Type Index: " .. tostring(nameOrIndex) .. " - " .. tostring(resolvedIndex))
			end
			if resolvedIndex ~= nil and fieldFruitTypeIndex == resolvedIndex then
				if fieldDebug then
					print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Matches Fruit Type Index: " .. tostring(resolvedIndex))
				end
				matchesFruit = true
				break
			end
		end
		if not matchesFruit then
			return false
		end
	end
	-- triggerGrowthState: field's growthState must be in config's list (e.g. harvest-ready)
	if config.triggerGrowthState ~= nil and #config.triggerGrowthState > 0 then
		if fieldDebug then
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Growth States: " .. arrayToString(config.triggerGrowthState))
		end
		local fieldGrowthState = fieldState.growthState
		if fieldGrowthState == nil then
			return false
		end
		local gsName = getFruitTypeGrowthStateName(fieldState.fruitTypeIndex, fieldGrowthState)
		local matchesGrowth = false
		for _, gs in ipairs(config.triggerGrowthState) do
			
			if fieldDebug then
				print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Growth State: " .. tostring(gs) .. " - " .. tostring(gsName))
			end
			if gs == gsName then
				if fieldDebug then
					print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Matches Growth State: " .. tostring(gsName))
				end
				matchesGrowth = true
				break
			end
		end
		if not matchesGrowth then
			return false
		end
	end
	-- triggerWeedState: field's weedState must be in config's list (e.g. 2,3,4,5 for weed levels)
	if config.triggerWeedState ~= nil and #config.triggerWeedState > 0 then
		if fieldDebug then
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Trigger Weed State: " .. arrayToString(config.triggerWeedState))
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Weed States: " .. arrayToString(config.triggerWeedState))
		end
		local fieldWeedState = fieldState.weedState
		if fieldWeedState == nil then
			return false
		end
		local matchesWeed = false
		for _, ws in ipairs(config.triggerWeedState) do
			if fieldDebug then
				print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Weed State: " .. tostring(ws) .. " - " .. tostring(fieldWeedState))
			end
			if tonumber(fieldWeedState) == tonumber(ws) then
				if fieldDebug then
					print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Matches Weed State: " .. tostring(fieldWeedState))
				end
				matchesWeed = true
				break
			end
		end
		if not matchesWeed then
			return false
		end
	end
	-- triggerSprayLevel: field's sprayLevel must be in config's list (e.g. 0,1,2 for spray/fertilizer levels)
	if config.triggerSprayLevel ~= nil and #config.triggerSprayLevel > 0 then
		if fieldDebug then
			print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Spray Levels: " .. arrayToString(config.triggerSprayLevel))
		end
		local fieldSprayLevel = fieldState.sprayLevel
		if fieldSprayLevel == nil then
			return false
		end
		local matchesSprayLevel = false
		for _, sl in ipairs(config.triggerSprayLevel) do
			if fieldDebug then
				print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Spray Level: " .. tostring(sl) .. " - " .. tostring(fieldSprayLevel))
			end
			if tonumber(fieldSprayLevel) == tonumber(sl) then
				if fieldDebug then
					print("--- IAGameLoopHelper:doesFieldMatchSituationConfig() - "..tostring(id)..": Matches Spray Level: " .. tostring(fieldSprayLevel))
				end
				matchesSprayLevel = true
				break
			end
		end
		if not matchesSprayLevel then
			return false
		end
	end
	return true
end

-- @param string|nil configDaytime
-- @param string currentDaytime
-- @return boolean
function IAGameLoopHelper:situationConfigMatchesDaytime(configDaytime, currentDaytime)
	if configDaytime == nil or configDaytime == "anytime" then
		return true
	end
	if configDaytime == "day" then
		return currentDaytime == "morning" or currentDaytime == "day" or currentDaytime == "evening"
	end
	return configDaytime == currentDaytime
end

-- @param IASituationConfig config
-- @param IANeighbour neighbour
-- @param number|nil currentGameHours - optional; defaults to getCurrentGameHours()
-- @return boolean
function IAGameLoopHelper:situationConfigPassesMinFrequency(config, neighbour, currentGameHours)
	if config == nil or config.minFrequency == nil or neighbour == nil then
		return true
	end
	local lastOccurence = neighbour:getLastSituationOccurence(config.id)
	if lastOccurence == nil then
		return true
	end
	local hours = currentGameHours or getCurrentGameHours()
	local elapsedHours = hours - lastOccurence
	local minFrequencyHours = config.minFrequency * 24
	if elapsedHours >= minFrequencyHours then
		return true
	end
	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:situationConfigPassesMinFrequency() - Situation "..tostring(config.id).." skipped: minFrequency not met (elapsed: "..tostring(elapsedHours).."h, required: "..tostring(minFrequencyHours).."h)")
	end
	return false
end

-- Daytime, minFrequency, character role/job, and months filters for one situation config (same rules as selectNewSituation).
-- @param IASituationConfig config
-- @param IANeighbour neighbour
-- @return boolean
function IAGameLoopHelper:situationConfigPassesNeighbourFilters(config, neighbour)
	if config == nil or neighbour == nil then
		return false
	end
	local currentDaytime = getCurrentDaytime()
	local currentGameHours = getCurrentGameHours()
	return self:situationConfigMatchesDaytime(config.daytime, currentDaytime)
		and self:situationConfigPassesMinFrequency(config, neighbour, currentGameHours)
		and self:doesSituationConfigMatchNeighbour(config, neighbour)
		and iaSituationConfigMonthsMatchCurrent(config)
end

-- Collect situation configs eligible for this neighbour right now (daytime, minFrequency, role/job, months filters),
-- split by occurrence (regular vs other). The result preserves XML order; the caller is expected to shuffle
-- before iterating. Used by selectNewSituation (single random pick, regular > random) and by
-- generateNewSituation (try each candidate until one builds; falls back to random when no regular config builds).
-- @param IANeighbour neighbour
-- @return table regularConfigs, table randomConfigs
function IAGameLoopHelper:collectMatchingSituationConfigsForNeighbour(neighbour)
	local regularConfigs = {}
	local randomConfigs = {}
	if self.ianeighbours.situationConfigs == nil or #self.ianeighbours.situationConfigs == 0 then
		return regularConfigs, randomConfigs
	end

	local currentDaytime = getCurrentDaytime()
	local currentGameHours = getCurrentGameHours()
	local skippedRoleMismatchCount = 0

	for _, config in ipairs(self.ianeighbours.situationConfigs) do
		if config ~= nil then
			if self:situationConfigPassesNeighbourFilters(config, neighbour) then
				if config.occurrence ~= nil and string.lower(tostring(config.occurrence)) == "regular" then
					table.insert(regularConfigs, config)
				else
					table.insert(randomConfigs, config)
				end
			elseif neighbour ~= nil
				and self:situationConfigMatchesDaytime(config.daytime, currentDaytime)
				and self:situationConfigPassesMinFrequency(config, neighbour, currentGameHours)
				and not self:doesSituationConfigMatchNeighbour(config, neighbour) then
				skippedRoleMismatchCount = skippedRoleMismatchCount + 1
			end
		end
	end

	if self.ianeighbours.debug and skippedRoleMismatchCount > 0 and neighbour ~= nil then
		print("--- IAGameLoopHelper:collectMatchingSituationConfigsForNeighbour() - Skipped "..tostring(skippedRoleMismatchCount).." situation config(s): characterRoles/characterJobs mismatch for "..tostring(neighbour.name))
	end

	return regularConfigs, randomConfigs
end

-- Select a random situation from IANeighbours.situationConfigs that matches the current daytime and minFrequency.
-- Picks one config from the prioritized pool (regular > random); the caller is responsible for verifying that the
-- chosen config can actually build a scenario. generateNewSituation walks candidates with a proper regular→random
-- fallback to avoid stalling when a regular config (e.g. "prepare the tractor") cannot be set up right now.
-- @param IANeighbour neighbour - The neighbour to check situation history for
-- @return IASituationConfig|nil - The randomly selected situation config, or nil if no configs available
function IAGameLoopHelper:selectNewSituation(neighbour)
	local regularConfigs, randomConfigs = self:collectMatchingSituationConfigsForNeighbour(neighbour)

	-- Prioritize regular situations: if any exist, select from those only
	local matchingConfigs = {}
	if #regularConfigs > 0 then
		matchingConfigs = regularConfigs
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectNewSituation() - Prioritizing "..tostring(#regularConfigs).." regular situation(s)")
		end
	else
		matchingConfigs = randomConfigs
	end

	if #matchingConfigs == 0 then
		if self.ianeighbours.debug then
			local currentDaytime = getCurrentDaytime()
			print("--- IAGameLoopHelper:selectNewSituation() - No situation configs match current daytime: "..currentDaytime.." and minFrequency requirements")
		end
		return nil
	end

	local randomIndex = math.random(1, #matchingConfigs)
	local selectedConfig = matchingConfigs[randomIndex]

	if self.ianeighbours.debug then
		local currentDaytime = getCurrentDaytime()
		print("--- IAGameLoopHelper:selectNewSituation() - Selected situation config: "..tostring(selectedConfig.id).." (Type: "..tostring(selectedConfig.type)..", Daytime: "..tostring(selectedConfig.daytime)..", Current: "..currentDaytime..")")
	end

	return selectedConfig
end

-- Select a random place from IANeighbours.places that matches the situation config's placetypes.
-- Candidates: assigned character_homebase/job (when those types apply) union other type matches; deduped; shuffled; first passing cheap filters, occupancy, collision wins (uniform over valid places).
-- @param IASituationConfig situationConfig - The situation config to match placetypes against
-- @param IANeighbour neighbour - The neighbour to check id/defaultPlaceId against (for character_homebase places)
-- @return IAMapPlace|nil - The randomly selected place, or nil if no matching places found
function IAGameLoopHelper:selectRandomPlaceForSituation(situationConfig, neighbour)
	if situationConfig == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Situation config is nil")
		end
		return nil
	end

	if self.ianeighbours.places == nil or #self.ianeighbours.places == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - No places available")
		end
		return nil
	end

	if situationConfig.placetypes == nil or #situationConfig.placetypes == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Situation config has no placetypes")
		end
		return nil
	end

	local function placeCharacterJobMatchesNeighbour(place, n)
		if place == nil then
			return false
		end
		local pj = place.job
		if pj == nil or pj == "" then
			return true
		end
		if n == nil or n.job == nil or n.job == "" then
			return false
		end
		return string.lower(tostring(pj)) == string.lower(tostring(n.job))
	end

	local placetypes = situationConfig.placetypes
	local function placetypesInclude(nameLower)
		for _, pt in ipairs(placetypes) do
			if string.lower(tostring(pt)) == nameLower then
				return true
			end
		end
		return false
	end

	--- True if main vehicle type is combine or harvester (self-propelled harvesters need the larger map-init slot: withVehicle + withAttachment).
	local function situationUsesCombineOrHarvesterMainVehicle(config)
		if config == nil or config.vehicleTypes == nil then
			return false
		end
		for _, vType in ipairs(config.vehicleTypes) do
			if vType ~= nil then
				local vl = string.lower(tostring(vType))
				if vl ~= "attachment" and (vl == "combine" or vl == "harvester") then
					return true
				end
			end
		end
		return false
	end
	local needsCombineSizedPlace = situationUsesCombineOrHarvesterMainVehicle(situationConfig)

	--- True when the situation requires a specific attachment (has Attachment in vehicleTypes + non-empty attachmentCategories).
	local function situationRequiresAttachmentPlace(config)
		if config == nil or config.vehicleTypes == nil then
			return false
		end
		local hasAttachmentVehicleType = false
		for _, vType in ipairs(config.vehicleTypes) do
			if vType ~= nil and string.lower(tostring(vType)) == "attachment" then
				hasAttachmentVehicleType = true
				break
			end
		end
		return hasAttachmentVehicleType and (config.attachmentCategories ~= nil and #config.attachmentCategories > 0)
	end
	local needsAttachmentPlace = situationRequiresAttachmentPlace(situationConfig)

	local allPlaces = self.ianeighbours.places
	local idToPlace = {}
	for _, p in ipairs(allPlaces) do
		if p ~= nil and p.id ~= nil then
			idToPlace[p.id] = p
		end
	end

	local typeCandidates = {}
	local seenPlace = {}
	local function addCandidate(place)
		if place ~= nil and not seenPlace[place] then
			seenPlace[place] = true
			table.insert(typeCandidates, place)
		end
	end

	if placetypesInclude("character_homebase") and neighbour ~= nil and neighbour.assignedHomebasePlaceIds ~= nil then
		for _, hid in ipairs(neighbour.assignedHomebasePlaceIds) do
			local p = idToPlace[hid]
			if p ~= nil then
				local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
				if st == "character_homebase" then
					addCandidate(p)
				end
			end
		end
	end

	if placetypesInclude("character_job") and neighbour ~= nil and neighbour.assignedWorkplacePlaceIds ~= nil then
		for _, wid in ipairs(neighbour.assignedWorkplacePlaceIds) do
			local p = idToPlace[wid]
			if p ~= nil then
				local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
				if st == "character_job" and placeCharacterJobMatchesNeighbour(p, neighbour) then
					addCandidate(p)
				end
			end
		end
	end

	local fromCollect = self:collectPlacesMatchingPlacetypes(placetypes)
	if #fromCollect == 0 then
		for _, place in ipairs(allPlaces) do
			if place ~= nil and place.type ~= nil and placeMatchesPlacetypes(place, placetypes) then
				table.insert(fromCollect, place)
			end
		end
	end

	for _, place in ipairs(fromCollect) do
		local semType = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
		if semType ~= "character_homebase" and semType ~= "character_job" then
			addCandidate(place)
		end
	end

	if #typeCandidates == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - No available places match placetypes: "..table.concat(placetypes, ", "))
		end
		return nil
	end

	if type(IAHelper_shuffleArrayInPlace) == "function" then
		IAHelper_shuffleArrayInPlace(typeCandidates)
	end

	local numCandidates = #typeCandidates
	local inn = self.ianeighbours
	if inn.debug then
		print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Candidates (narrowed, shuffled): " .. tostring(numCandidates) .. " | placetypes: " .. table.concat(placetypes, ", "))
	end

	local minDist = IAGameLoopHelper.MIN_PLAYER_DISTANCE_FOR_PLACE_SITUATION or 20

	for i, place in ipairs(typeCandidates) do
		if place == nil or place.type == nil then
			-- skip
		elseif place.isPlaceableRelative and place:isPlaceableRelative() and place.x == 0 and place.z == 0 then
			-- unresolved placeable-relative
		elseif not placeMatchesPlacetypes(place, situationConfig.placetypes) then
			-- skip
		elseif not placeMatchesRequestedSize(place, situationConfig) then
			if inn.debug then
				local requested = situationConfig.placeSizes
				local reqStr = (requested ~= nil and #requested > 0) and table.concat(requested, ", ") or "(none, exclusive sizes opt-in only)"
				print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping place (id: "..tostring(place.id)..", type: "..tostring(place.type).."): sizeType="..tostring(place.sizeType).." does not match requested placeSizes ["..reqStr.."]")
			end
		else
			local distToPlayer = (place.x ~= nil and place.z ~= nil) and distanceToPlayer(place.x, place.y or 0, place.z) or nil
			if distToPlayer ~= nil and distToPlayer < minDist then
				if inn.debug then
					print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping place (player too close): "..tostring(place.name).." distance: "..tostring(math.floor(distToPlayer)).."m < "..tostring(minDist).."m")
				end
			else
				local semType = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type))
				local isCharacterHomebase = (semType == "character_homebase")
				local isCharacterJob = (semType == "character_job")
				local roleOk = true
				if isCharacterHomebase then
					roleOk = false
					if neighbour ~= nil and neighbour.assignedHomebasePlaceIds ~= nil and place.id ~= nil then
						for _, id in ipairs(neighbour.assignedHomebasePlaceIds) do
							if id == place.id then
								roleOk = true
								break
							end
						end
					end
					if not roleOk and inn.debug then
						print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping character_homebase place (id: "..tostring(place.id)..") - not in neighbour assignedHomebasePlaceIds")
					end
				elseif isCharacterJob then
					roleOk = false
					if neighbour ~= nil and neighbour.assignedWorkplacePlaceIds ~= nil and place.id ~= nil then
						for _, id in ipairs(neighbour.assignedWorkplacePlaceIds) do
							if id == place.id then
								roleOk = true
								break
							end
						end
					end
					if roleOk then
						roleOk = placeCharacterJobMatchesNeighbour(place, neighbour)
					end
					if not roleOk and inn.debug then
						print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping character_job place (id: "..tostring(place.id)..") - not assigned to neighbour or job mismatch")
					end
				end

				if roleOk and needsCombineSizedPlace and not (place.withVehicle == true and place.withAttachment == true) then
					if inn.debug then
						print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping place (id: " .. tostring(place.id) .. ", type: " .. tostring(place.type) .. "): need map place size vehicle+attachment for combine/harvester; has withVehicle=" .. tostring(place.withVehicle) .. " withAttachment=" .. tostring(place.withAttachment))
					end
				elseif roleOk and needsAttachmentPlace and not (place.withAttachment == true) then
					if inn.debug then
						print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Skipping place (id: " .. tostring(place.id) .. ", type: " .. tostring(place.type) .. "): situation requires attachment (" .. table.concat(situationConfig.attachmentCategories, ", ") .. ") but place has withAttachment=" .. tostring(place.withAttachment))
					end
				elseif roleOk then
					if inn:isPlaceBlockedByOccupancy(place, nil) then
						-- isPlaceBlockedByOccupancy logs when another neighbour holds this place (debug)
					elseif inn:isPlaceBlockedByCollision(place, nil) then
						if inn.debug then
							print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Place blocked by collision: " .. tostring(place.name) .. " (Type: " .. tostring(place.type) .. ")")
						end
					else
						if inn.debug then
							print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - Selected place: "..tostring(place.name).." (Type: "..tostring(place.type)..", ID: "..tostring(place.id)..") | candidates="..tostring(numCandidates)..", iterationIndex="..tostring(i).." (1-based order after shuffle)")
						end
						return place
					end
				end
			end
		end
	end

	if inn.debug then
		print("--- IAGameLoopHelper:selectRandomPlaceForSituation() - No valid place after full scan | candidates="..tostring(numCandidates)..", iterations="..tostring(numCandidates).." (all candidate slots checked)")
	end
	return nil
end

--- True when this fleet unit is not borrowed by the player (available for neighbour situations).
function IAGameLoopHelper:isFleetVehicleAvailableForSituation(ia_vehicle)
	if ia_vehicle == nil then
		return true
	end
	if ia_vehicle.isBorrowedByPlayer == true then
		return false
	end
	if IABorrowAccess ~= nil and IABorrowAccess.hasPlayerBorrowAccess ~= nil and ia_vehicle.vehicle ~= nil then
		if IABorrowAccess.hasPlayerBorrowAccess(ia_vehicle.vehicle) then
			return false
		end
	end
	return true
end

--- True when any fleet unit required by config is currently borrowed by the player.
function IAGameLoopHelper:isAnyFleetVehicleForConfigBorrowedByPlayer(neighbour, config)
	if neighbour == nil or neighbour.vehicles == nil or config == nil then
		return false
	end
	local vehicleTypes = config.vehicleTypes
	local attachmentCategories = config.attachmentCategories
	if vehicleTypes == nil then
		return false
	end
	for _, iv in pairs(neighbour.vehicles) do
		if iv ~= nil and iv.isBorrowedByPlayer == true then
			local isAttachment = iv.type ~= nil and string.lower(tostring(iv.type)) == "attachment"
			local typeMatches = type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function"
				and IAHelper_valueEqualsAnyInArrayIgnoreCase(iv.type, vehicleTypes)
			if typeMatches then
				if isAttachment and attachmentCategories ~= nil and #attachmentCategories > 0 then
					if type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function"
						and IAHelper_valueEqualsAnyInArrayIgnoreCase(iv.category, attachmentCategories)
					then
						return true
					end
				else
					return true
				end
			end
		end
	end
	return false
end

--- True when implement is parked at neighbour homebase (presence), not in NPC fieldwork, and not attached.
function IAGameLoopHelper:isFleetAttachmentAvailableAtHomebase(ia_vehicle)
	if ia_vehicle == nil then
		return false
	end
	if not self:isFleetVehicleAvailableForSituation(ia_vehicle) then
		return false
	end
	if ia_vehicle.activeSituationId ~= nil then
		return false
	end
	local s = ia_vehicle.presenceState
	if s == nil or s.owner ~= "homebase" or s.mode ~= "visible" then
		return false
	end
	local gv = ia_vehicle.vehicle
	if gv ~= nil and type(gv.getAttacherVehicle) == "function" then
		local ok, att = pcall(gv.getAttacherVehicle, gv)
		if ok and att ~= nil then
			return false
		end
	end
	return true
end

--- First fleet unit matching type/category (stable order by uniqueId), or nil.
function IAGameLoopHelper:findFirstFleetVehicleByType(vehicles, vehicleType, vehicleCategory)
	if vehicleType == nil or vehicles == nil then
		return nil
	end
	local vehicleTypes = type(vehicleType) == "table" and vehicleType or { vehicleType }
	local vehicleCategories = nil
	if vehicleCategory ~= nil then
		vehicleCategories = type(vehicleCategory) == "table" and vehicleCategory or { vehicleCategory }
	end
	local sorted = {}
	for _, ia_vehicle in pairs(vehicles) do
		if ia_vehicle ~= nil then
			table.insert(sorted, ia_vehicle)
		end
	end
	table.sort(sorted, function(a, b)
		return tostring(a.uniqueId or "") < tostring(b.uniqueId or "")
	end)
	for _, ia_vehicle in ipairs(sorted) do
		local typeMatches = type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function"
			and IAHelper_valueEqualsAnyInArrayIgnoreCase(ia_vehicle.type, vehicleTypes)
		if typeMatches then
			local isAttachment = ia_vehicle.type ~= nil and string.lower(tostring(ia_vehicle.type)) == "attachment"
			if isAttachment and vehicleCategories ~= nil then
				if type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function"
					and IAHelper_valueEqualsAnyInArrayIgnoreCase(ia_vehicle.category, vehicleCategories)
				then
					return ia_vehicle
				end
			else
				return ia_vehicle
			end
		end
	end
	return nil
end

--- Resolve rear/front attachments for a fieldwork config (deterministic first match per category).
-- @return table|nil { attachmentBack, attachmentFront }
function IAGameLoopHelper:resolveMissionAttachmentsForConfig(neighbour, config)
	if neighbour == nil or config == nil or neighbour.vehicles == nil then
		return nil
	end
	local usesAttachment = false
	if config.vehicleTypes ~= nil then
		for _, vType in ipairs(config.vehicleTypes) do
			if vType ~= nil and string.lower(tostring(vType)) == "attachment" then
				usesAttachment = true
				break
			end
		end
	end
	if not usesAttachment or config.attachmentCategories == nil or #config.attachmentCategories == 0 then
		return { attachmentBack = nil, attachmentFront = nil }
	end
	local vehicles = neighbour.vehicles
	local attachmentFront = nil
	local frontCategories = self:getAttachmentFrontCategoriesForConfig(config)
	if #frontCategories > 0 then
		attachmentFront = self:findFirstFleetVehicleByType(vehicles, "attachment", frontCategories)
	end
	local attachmentBack = nil
	local backCategories = self:getAttachmentBackCategoriesForConfig(config)
	if #backCategories > 0 then
		attachmentBack = self:findFirstFleetVehicleByType(vehicles, "attachment", backCategories)
	end
	return { attachmentBack = attachmentBack, attachmentFront = attachmentFront }
end

--- Collect unique fleet implements required across open fieldwork rows (rear + front per config).
--- Weight-category attachments are intentionally excluded: fieldwork contracts only borrow the
--- main implement; the player supplies their own counterweight if their tractor needs one.
function IAGameLoopHelper:collectMissionBorrowUnitsForOpenList(neighbour, openList, maxCount)
	local units = {}
	local seenUid = {}
	if openList == nil then
		return units
	end
	local limit = maxCount ~= nil and math.max(0, tonumber(maxCount) or 0) or #openList
	local configSeen = {}
	for i, row in ipairs(openList) do
		if i > limit then
			break
		end
		local cfg = row ~= nil and row.config or nil
		local cfgId = cfg ~= nil and tostring(cfg.id) or nil
		if cfg ~= nil and cfgId ~= nil and not configSeen[cfgId] then
			configSeen[cfgId] = true
			local resolved = self:resolveMissionAttachmentsForConfig(neighbour, cfg)
			if resolved ~= nil then
				for _, ia in ipairs({ resolved.attachmentBack, resolved.attachmentFront }) do
					if ia ~= nil and ia.uniqueId ~= nil and not seenUid[tostring(ia.uniqueId)]
						and not self:iaVehicleHasWeightCategory(ia)
					then
						seenUid[tostring(ia.uniqueId)] = true
						table.insert(units, ia)
					end
				end
			end
		end
	end
	return units
end

--- True when every required implement is either at homebase already, or can take a spawned sibling's slot via swap.
function IAGameLoopHelper:canOfferEquipmentBorrowForOpenList(neighbour, openList, maxCount)
	if neighbour == nil or openList == nil or #openList == 0 then
		return false
	end
	local units = self:collectMissionBorrowUnitsForOpenList(neighbour, openList, maxCount)
	if #units == 0 then
		return false
	end
	for _, ia in ipairs(units) do
		if ia == nil or ia.isBorrowedByPlayer == true or ia.activeSituationId ~= nil then
			return false
		end
	end
	if self.homebaseParking ~= nil and type(self.homebaseParking.canSatisfyAllBorrowUnitsViaHomebaseOrSwap) == "function" then
		return self.homebaseParking:canSatisfyAllBorrowUnitsViaHomebaseOrSwap(neighbour, units)
	end
	for _, ia in ipairs(units) do
		if not self:isFleetAttachmentAvailableAtHomebase(ia) then
			return false
		end
	end
	return true
end

--- @param string|nil category
function IAGameLoopHelper:isWeightAttachmentCategory(category)
	return category ~= nil and string.lower(tostring(category)) == "weight"
end

--- @param IANeighbourVehicle|nil ia_vehicle
function IAGameLoopHelper:iaVehicleHasWeightCategory(ia_vehicle)
	return ia_vehicle ~= nil and self:isWeightAttachmentCategory(ia_vehicle.category)
end

--- Situation XML lists Weight plus at least one implement category (e.g. Cultivator + Weight).
function IAGameLoopHelper:situationConfigRequiresWeightPlusImplement(config)
	if config == nil or config.attachmentCategories == nil or #config.attachmentCategories == 0 then
		return false
	end
	local hasWeight = false
	local hasImplement = false
	for _, cat in ipairs(config.attachmentCategories) do
		if cat ~= nil then
			if self:isWeightAttachmentCategory(cat) then
				hasWeight = true
			else
				hasImplement = true
			end
		end
	end
	return hasWeight and hasImplement
end

--- Front categories for attachment selection (Weight / Header on front hitch); mirrors XMLHelper loader.
function IAGameLoopHelper:getAttachmentFrontCategoriesForConfig(config)
	if config == nil or config.attachmentCategories == nil then
		return {}
	end
	if config.attachmentFrontCategories ~= nil and #config.attachmentFrontCategories > 0 then
		return config.attachmentFrontCategories
	end
	local frontCategories = {}
	for _, cat in ipairs(config.attachmentCategories) do
		if cat == "Header / Cutter" or self:isWeightAttachmentCategory(cat) then
			table.insert(frontCategories, cat)
		end
	end
	return frontCategories
end

--- Rear attachment categories (all configured categories except front categories).
function IAGameLoopHelper:getAttachmentBackCategoriesForConfig(config)
	if config == nil or config.attachmentCategories == nil then
		return {}
	end
	local frontCategories = self:getAttachmentFrontCategoriesForConfig(config)
	local backCategories = {}
	for _, cat in ipairs(config.attachmentCategories) do
		local isFront = false
		for _, frontCat in ipairs(frontCategories) do
			if cat == frontCat then
				isFront = true
				break
			end
		end
		if not isFront then
			table.insert(backCategories, cat)
		end
	end
	return backCategories
end

--- Required rear/front attachments when config uses Attachment (+ Weight+implement rules).
--- @return boolean ok, string|nil errorMessage
function IAGameLoopHelper:validateScenarioAttachmentLayout(scenarioData)
	local config = scenarioData ~= nil and scenarioData.config or nil
	if config == nil or config.attachmentCategories == nil or #config.attachmentCategories == 0 then
		return true, nil
	end
	local usesAttachment = false
	if config.vehicleTypes ~= nil then
		for _, vType in ipairs(config.vehicleTypes) do
			if vType ~= nil and string.lower(tostring(vType)) == "attachment" then
				usesAttachment = true
				break
			end
		end
	end
	if not usesAttachment then
		return true, nil
	end

	local backCategories = self:getAttachmentBackCategoriesForConfig(config)
	local frontCategories = self:getAttachmentFrontCategoriesForConfig(config)
	if #backCategories > 0 and scenarioData.attachmentBack == nil then
		return false, "required rear attachment missing (borrowed or unavailable)"
	end

	if self:situationConfigRequiresWeightPlusImplement(config) then
		if scenarioData.vehicle == nil then
			return false, "weight layout requires main vehicle"
		end
		if scenarioData.attachmentBack ~= nil and self:iaVehicleHasWeightCategory(scenarioData.attachmentBack) then
			return false, "rear attachment must be implement, not weight"
		end
		local mainVehicle = scenarioData.vehicle.vehicle
		if mainVehicle == nil or type(vehicleHasFrontAttacherJoint) ~= "function" or not vehicleHasFrontAttacherJoint(mainVehicle) then
			return false, "weight required but main vehicle has no front attacher joint"
		end
		if scenarioData.attachmentFront == nil or not self:iaVehicleHasWeightCategory(scenarioData.attachmentFront) then
			return false, "weight layout requires front weight attachment"
		end
	elseif #frontCategories > 0 and scenarioData.attachmentFront == nil then
		return false, "required front attachment missing (borrowed or unavailable)"
	end
	return true, nil
end

--- @return boolean ok, string|nil errorMessage
function IAGameLoopHelper:validateScenarioFleetVehicles(scenarioData)
	if scenarioData == nil then
		return false, "no scenario data"
	end
	local function check(ia, label)
		if ia == nil then
			return true, nil
		end
		if self:isFleetVehicleAvailableForSituation(ia) then
			return true, nil
		end
		local name = ia.vehicleName or ia.name or ia.xmlFilename or ia.uniqueId or label
		return false, tostring(label) .. " unavailable (borrowed by player): " .. tostring(name)
	end
	local ok, err
	ok, err = check(scenarioData.vehicle, "main vehicle")
	if not ok then
		return false, err
	end
	ok, err = check(scenarioData.attachmentBack, "attachment")
	if not ok then
		return false, err
	end
	ok, err = check(scenarioData.attachmentFront, "front attachment")
	if not ok then
		return false, err
	end
	ok, err = self:validateScenarioAttachmentLayout(scenarioData)
	if not ok then
		return false, err
	end
	return true, nil
end

-- Get a random vehicle from vehicles matching the specified type
-- @param table vehicles - The vehicles table to search in
-- @param string|table vehicleType - The vehicle type(s) to filter by (can be a single string or array of strings)
-- @param string|table vehicleCategory - The vehicle category(ies) to filter by (optional, a single string or array of strings, only checked if type is "attachment")
-- @return IANeighbourVehicle|nil - A randomly selected vehicle of the specified type, or nil if none found
function IAGameLoopHelper:getRandomVehicleByType(vehicles, vehicleType, vehicleCategory)
	if vehicleType == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getRandomVehicleByType() - vehicleType is nil, returning nil")
		end
		return nil
	end

	if self.ianeighbours.debug then
		local function arrStr(t)
			if t == nil or type(t) ~= "table" then return tostring(t) end
			local parts = {}
			for _, v in ipairs(t) do parts[#parts + 1] = tostring(v) end
			return "{" .. table.concat(parts, ", ") .. "}"
		end
		print("--- IAGameLoopHelper:getRandomVehicleByType() - vehicleType: " .. arrStr(type(vehicleType) == "table" and vehicleType or {vehicleType}) .. ", vehicleCategory: " .. arrStr(vehicleCategory))
	end

	-- Normalize vehicleType to an array (handle both single values and arrays)
	local vehicleTypes = {}
	if type(vehicleType) == "table" then
		vehicleTypes = vehicleType
	else
		vehicleTypes = {vehicleType}
	end

	-- Normalize vehicleCategory to an array (handle both single values and arrays)
	local vehicleCategories = nil
	if vehicleCategory ~= nil then
		vehicleCategories = {}
		if type(vehicleCategory) == "table" then
			vehicleCategories = vehicleCategory
		else
			vehicleCategories = {vehicleCategory}
		end
	end

	-- Collect all vehicles matching the type(s)
	local matchingVehicles = {}
	local totalChecked = 0
	for _, ia_vehicle in pairs(vehicles) do
		totalChecked = totalChecked + 1
		if not self:isFleetVehicleAvailableForSituation(ia_vehicle) then
			if self.ianeighbours.debug then
				print("--- IAGameLoopHelper:getRandomVehicleByType() - skipped (borrowed): " .. tostring(ia_vehicle.vehicleName or ia_vehicle.uniqueId))
			end
		else
		-- Check if vehicle type matches any of the specified types (case-insensitive)
		local typeMatches = type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(ia_vehicle.type, vehicleTypes)

		if typeMatches then
			-- If the vehicle's type is "attachment" and categories are specified, also check category
			local isAttachment = (ia_vehicle.type ~= nil and string.lower(tostring(ia_vehicle.type)) == "attachment")
			if isAttachment and vehicleCategories ~= nil then
				-- For attachments, category must match one of the specified categories
				if type(IAHelper_valueEqualsAnyInArrayIgnoreCase) == "function" and IAHelper_valueEqualsAnyInArrayIgnoreCase(ia_vehicle.category, vehicleCategories) then
					table.insert(matchingVehicles, ia_vehicle)
				elseif self.ianeighbours.debug then
					print("--- IAGameLoopHelper:getRandomVehicleByType() - skipped (type match, category no): " .. tostring(ia_vehicle.vehicleName or ia_vehicle.uniqueId) .. " type=" .. tostring(ia_vehicle.type) .. " category=" .. tostring(ia_vehicle.category))
				end
			else
				-- For non-attachment types or when category is not specified, just match by type
				table.insert(matchingVehicles, ia_vehicle)
			end
		elseif self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getRandomVehicleByType() - skipped (type no): " .. tostring(ia_vehicle.vehicleName or ia_vehicle.uniqueId) .. " type=" .. tostring(ia_vehicle.type) .. " category=" .. tostring(ia_vehicle.category))
		end
		end
	end

	if self.ianeighbours.debug then
		local matchNames = {}
		for _, v in ipairs(matchingVehicles) do
			matchNames[#matchNames + 1] = tostring(v.vehicleName or v.uniqueId) .. "(" .. tostring(v.type) .. (v.category and "/" .. tostring(v.category) or "") .. ")"
		end
		print("--- IAGameLoopHelper:getRandomVehicleByType() - checked " .. tostring(totalChecked) .. " vehicles, " .. tostring(#matchingVehicles) .. " match: " .. (matchNames[1] and table.concat(matchNames, ", ") or "none"))
	end

	-- Return nil if no matching vehicles found
	if #matchingVehicles == 0 then
		return nil
	end

	-- Randomly select one vehicle from the matching list
	local randomIndex = math.random(1, #matchingVehicles)
	local selected = matchingVehicles[randomIndex]
	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:getRandomVehicleByType() - selected: " .. tostring(selected.vehicleName or selected.uniqueId) .. " (type=" .. tostring(selected.type) .. ", category=" .. tostring(selected.category) .. ")")
	end
	return selected
end

-- Get vehicles for a situation based on the situation config's vehicleTypes and attachmentCategories
-- Attachments with category "Header / Cutter" go to attachmentFront (front attacher); others go to attachmentBack.
-- @param table vehicles - The vehicles table to search in
-- @param IASituationConfig situationConfig - The situation config with vehicleTypes and attachmentCategories
-- @return table - Table with keys: vehicle (IANeighbourVehicle|nil), attachmentBack (IANeighbourVehicle|nil), attachmentFront (IANeighbourVehicle|nil)
function IAGameLoopHelper:GetVehiclesForSituation(vehicles, situationConfig)
	local situationVehicle = nil
	local attachmentBack = nil
	local attachmentFront = nil

	if self.ianeighbours.debug then
		local vehicleCount = 0
		if vehicles ~= nil then
			for _ in pairs(vehicles) do vehicleCount = vehicleCount + 1 end
		end
		print("--- IAGameLoopHelper:GetVehiclesForSituation() - config id: " .. tostring(situationConfig and situationConfig.id) .. ", vehicles count: " .. tostring(vehicleCount))
		if situationConfig ~= nil and situationConfig.vehicleTypes ~= nil and #situationConfig.vehicleTypes > 0 then
			local vtParts = {}
			for _, v in ipairs(situationConfig.vehicleTypes) do vtParts[#vtParts + 1] = tostring(v) end
			print("--- IAGameLoopHelper:GetVehiclesForSituation() - vehicleTypes: {" .. table.concat(vtParts, ", ") .. "}")
			if situationConfig.attachmentCategories ~= nil and #situationConfig.attachmentCategories > 0 then
				local acParts = {}
				for _, v in ipairs(situationConfig.attachmentCategories) do acParts[#acParts + 1] = tostring(v) end
				print("--- IAGameLoopHelper:GetVehiclesForSituation() - attachmentCategories: {" .. table.concat(acParts, ", ") .. "}")
			end
		end
	end

	if situationConfig ~= nil and situationConfig.vehicleTypes ~= nil and #situationConfig.vehicleTypes > 0 then
		-- Filter out "Attachment" from vehicleTypes for main vehicle selection
		local vehicleTypesForMain = {}
		local hasAttachment = false
		for _, vType in ipairs(situationConfig.vehicleTypes) do
			if vType ~= nil then
				local vTypeLower = string.lower(tostring(vType))
				if vTypeLower == "attachment" then
					hasAttachment = true
				else
					table.insert(vehicleTypesForMain, vType)
				end
			end
		end

		if self.ianeighbours.debug then
			local vtMainParts = {}
			for _, v in ipairs(vehicleTypesForMain) do vtMainParts[#vtMainParts + 1] = tostring(v) end
			print("--- IAGameLoopHelper:GetVehiclesForSituation() - vehicleTypesForMain: {" .. table.concat(vtMainParts, ", ") .. "}, hasAttachment: " .. tostring(hasAttachment))
		end

		-- Select main vehicle (excluding attachments)
		if #vehicleTypesForMain > 0 then
			situationVehicle = self:getRandomVehicleByType(vehicles, vehicleTypesForMain)
			if self.ianeighbours.debug then
				print("--- IAGameLoopHelper:GetVehiclesForSituation() - situationVehicle: " .. (situationVehicle ~= nil and (tostring(situationVehicle.name or situationVehicle.vehicleName or situationVehicle.uniqueId) .. " (type=" .. tostring(situationVehicle.type) .. ")") or "nil"))
			end
		end

		-- If "Attachment" is in vehicleTypes, select attachments: front (e.g. Header / Cutter, Weight) and back (implements)
		if hasAttachment and situationConfig.attachmentCategories ~= nil and #situationConfig.attachmentCategories > 0 then
			local attachmentFrontCategories = self:getAttachmentFrontCategoriesForConfig(situationConfig)
			if #attachmentFrontCategories > 0 then
				attachmentFront = self:getRandomVehicleByType(vehicles, "attachment", attachmentFrontCategories)
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:GetVehiclesForSituation() - attachmentFront: " .. (attachmentFront ~= nil and (tostring(attachmentFront.name or attachmentFront.vehicleName) .. " (category=" .. tostring(attachmentFront.category) .. ")") or "nil"))
				end
			end
			local attachmentBackCategories = self:getAttachmentBackCategoriesForConfig(situationConfig)
			if self.ianeighbours.debug then
				local abParts = {}
				for _, v in ipairs(attachmentBackCategories) do abParts[#abParts + 1] = tostring(v) end
				print("--- IAGameLoopHelper:GetVehiclesForSituation() - attachmentBackCategories: {" .. table.concat(abParts, ", ") .. "}")
			end
			if #attachmentBackCategories > 0 then
				attachmentBack = self:getRandomVehicleByType(vehicles, "attachment", attachmentBackCategories)
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:GetVehiclesForSituation() - attachmentBack: " .. (attachmentBack ~= nil and (tostring(attachmentBack.name or attachmentBack.vehicleName) .. " (category=" .. tostring(attachmentBack.category) .. ")") or "nil"))
				end
			end
			-- No front hitch on main vehicle → do not use front attachment (e.g. weight)
			if attachmentFront ~= nil and situationVehicle ~= nil and situationVehicle.vehicle ~= nil and not vehicleHasFrontAttacherJoint(situationVehicle.vehicle) then
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:GetVehiclesForSituation() - dropping attachmentFront (main vehicle has no front attacher joint)")
				end
				attachmentFront = nil
			end
		end
	end

	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:GetVehiclesForSituation() - result: vehicle=" .. (situationVehicle ~= nil and tostring(situationVehicle.vehicleName or situationVehicle.uniqueId) or "nil") ..
			", attachmentBack=" .. (attachmentBack ~= nil and tostring(attachmentBack.vehicleName or attachmentBack.uniqueId) or "nil") ..
			", attachmentFront=" .. (attachmentFront ~= nil and tostring(attachmentFront.vehicleName or attachmentFront.uniqueId) or "nil"))
	end

	return {
		vehicle = situationVehicle,
		attachmentBack = attachmentBack,
		attachmentFront = attachmentFront
	}
end

-- Get character_homebase places and unassigned shed vehicle slots not assigned to any neighbour.
-- Order: all unassigned character_homebase first (for pairing + fallback), then sheds with withVehicle
-- (used only as the vehicle side of an on-foot + vehicle pair within selectHomebasesForNeighbour).
-- @return table - Array of IAMapPlace
function IAGameLoopHelper:getUnassignedHomebasePlaces()
	local places = self.ianeighbours.places
	if places == nil or #places == 0 then
		return {}
	end
	local assigned = IAHelper_collectNeighbourAssignedPlaceIds(self.ianeighbours, "assignedHomebasePlaceIds")
	local unassigned = {}
	for _, place in ipairs(places) do
		if place ~= nil and place.id ~= nil then
			local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			if st == "character_homebase" then
				if place.x == nil or place.z == nil then
					-- Skip unresolved placeable-relative
				elseif not assigned[place.id] then
					table.insert(unassigned, place)
				end
			end
		end
	end
	for _, place in ipairs(places) do
		if place ~= nil and place.id ~= nil then
			local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			if st == "shed" and place.withVehicle == true and place.withAttachment ~= true then
				if place.x == nil or place.z == nil then
					-- Skip unresolved
				elseif not assigned[place.id] then
					table.insert(unassigned, place)
				end
			end
		end
	end
	return unassigned
end

-- Get all character_job places not assigned to any neighbour as workplace.
-- @return table - Array of IAMapPlace
function IAGameLoopHelper:getUnassignedWorkplacePlaces()
	local places = self.ianeighbours.places
	if places == nil or #places == 0 then
		return {}
	end
	local assigned = IAHelper_collectNeighbourAssignedPlaceIds(self.ianeighbours, "assignedWorkplacePlaceIds")
	local unassigned = {}
	for _, place in ipairs(places) do
		if place ~= nil and place.id ~= nil then
			local st = string.lower(tostring((place.getSemanticType ~= nil and place:getSemanticType()) or place.type or ""))
			if st == "character_job" then
				if place.x == nil or place.z == nil then
					-- Skip unresolved
				elseif not assigned[place.id] then
					table.insert(unassigned, place)
				end
			end
		end
	end
	return unassigned
end

-- Pick workplace places for this neighbour from the unassigned pool: place.job must match neighbour.job (case-insensitive).
-- Places with no job set are skipped (manual assignment only).
-- @param IANeighbour neighbour
-- @param table unassignedPlaces - from getUnassignedWorkplacePlaces()
-- @return table - Array of IAMapPlace to assign (may be empty)
function IAGameLoopHelper:selectWorkplacesForNeighbour(neighbour, unassignedPlaces)
	if neighbour == nil or neighbour.job == nil or neighbour.job == "" or unassignedPlaces == nil or #unassignedPlaces == 0 then
		return {}
	end
	local j = string.lower(tostring(neighbour.job))
	local out = {}
	for _, p in ipairs(unassignedPlaces) do
		local pj = p.job
		if pj ~= nil and pj ~= "" and string.lower(tostring(pj)) == j then
			table.insert(out, p)
		end
	end
	return out
end

-- Horizontal distance between two places (x,z). Returns nil if either place has no x/z.
local function placeDistanceHorizontal(p1, p2)
	if p1 == nil or p2 == nil or p1.x == nil or p1.z == nil or p2.x == nil or p2.z == nil then
		return nil
	end
	local dx = p1.x - p2.x
	local dz = p1.z - p2.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Prefer a pair (on-foot character_homebase + vehicle within 50 m). Vehicle side may be character_homebase or shed (from getUnassignedHomebasePlaces).
-- @param table unassignedPlaces - Array of IAMapPlace (from getUnassignedHomebasePlaces)
-- @return table - Array of IAMapPlace to assign (on-foot first if pair), or { first character_homebase } if no pair
function IAGameLoopHelper:selectHomebasesForNeighbour(unassignedPlaces)
	local HOMEBASE_PAIR_RANGE_M = 50
	local MIN_HOMEBASE_DISTANCE_M = 30
	if unassignedPlaces == nil or #unassignedPlaces == 0 then
		return {}
	end

	-- Enforce minimum spacing between characters' primary (on-foot) homebases.
	-- We treat each neighbour's first assigned on-foot character_homebase as their "primary" homebase anchor.
	local function buildPlaceById()
		local m = {}
		local places = self.ianeighbours ~= nil and self.ianeighbours.places or nil
		if places ~= nil then
			for _, p in ipairs(places) do
				if p ~= nil and p.id ~= nil then
					m[p.id] = p
				end
			end
		end
		return m
	end

	local function isCharacterHomebasePlace(p)
		if p == nil then
			return false
		end
		local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
		return st == "character_homebase"
	end

	local function isOnFootHomebasePlace(p)
		return isCharacterHomebasePlace(p) and (p.withVehicle == false or p.withVehicle == nil)
	end

	local function getNeighbourPrimaryHomebasePlace(neighbour, placeById)
		if neighbour == nil or neighbour.assignedHomebasePlaceIds == nil then
			return nil
		end
		-- Prefer an on-foot character_homebase
		for _, id in ipairs(neighbour.assignedHomebasePlaceIds) do
			local p = placeById[id]
			if isOnFootHomebasePlace(p) then
				return p
			end
		end
		-- Fallback: any character_homebase
		for _, id in ipairs(neighbour.assignedHomebasePlaceIds) do
			local p = placeById[id]
			if isCharacterHomebasePlace(p) then
				return p
			end
		end
		return nil
	end

	local function getExistingPrimaryHomebases()
		local anchors = {}
		if self.ianeighbours == nil or self.ianeighbours.neighbours == nil then
			return anchors
		end
		local placeById = buildPlaceById()
		for _, n in pairs(self.ianeighbours.neighbours) do
			if n ~= nil and n.assignedHomebasePlaceIds ~= nil and #n.assignedHomebasePlaceIds > 0 then
				local p = getNeighbourPrimaryHomebasePlace(n, placeById)
				if p ~= nil and p.x ~= nil and p.z ~= nil then
					table.insert(anchors, p)
				end
			end
		end
		return anchors
	end

	local function respectsMinDistance(candidate, anchors)
		if candidate == nil or candidate.x == nil or candidate.z == nil then
			return false
		end
		for _, a in ipairs(anchors) do
			local dist = placeDistanceHorizontal(candidate, a)
			if dist ~= nil and dist < MIN_HOMEBASE_DISTANCE_M then
				return false
			end
		end
		return true
	end

	local existingAnchors = getExistingPrimaryHomebases()
	local onFoot = {}
	local vehicle = {}
	for _, p in ipairs(unassignedPlaces) do
		if p.withVehicle == false or p.withVehicle == nil then
			table.insert(onFoot, p)
		else
			table.insert(vehicle, p)
		end
	end
	-- Try to pick an on-foot homebase that respects spacing; if none, fall back to original list.
	local onFootSpaced = {}
	for _, of in ipairs(onFoot) do
		if respectsMinDistance(of, existingAnchors) then
			table.insert(onFootSpaced, of)
		end
	end
	local onFootCandidates = (#onFootSpaced > 0) and onFootSpaced or onFoot

	-- Find first pair within range (on-foot + vehicle <= 50 m); vehicle may include type shed
	for _, of in ipairs(onFootCandidates) do
		for _, v in ipairs(vehicle) do
			local dist = placeDistanceHorizontal(of, v)
			if dist ~= nil and dist <= HOMEBASE_PAIR_RANGE_M then
				return { of, v }
			end
		end
	end
	-- No pair: first character_homebase only (never assign a shed alone)
	for _, p in ipairs(onFootCandidates) do
		if p ~= nil and p.id ~= nil then
			local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
			if st == "character_homebase" then
				return { p }
			end
		end
	end
	return {}
end

-- Check if a neighbour has at least one homebase place they can use (place.id in neighbour.assignedHomebasePlaceIds).
-- Situations are only generated when this is true to avoid loops when no places exist.
-- @param IANeighbour neighbour - The neighbour to check
-- @return boolean - true if at least one id in assignedHomebasePlaceIds exists in IANeighbours.places
function IAGameLoopHelper:neighbourHasHomebasePlace(neighbour)
	if neighbour == nil or neighbour.assignedHomebasePlaceIds == nil or #neighbour.assignedHomebasePlaceIds == 0 then
		return false
	end
	local places = self.ianeighbours.places
	if places == nil or #places == 0 then
		return false
	end
	local placeIds = {}
	for _, p in ipairs(places) do
		if p ~= nil and p.id ~= nil then
			placeIds[p.id] = true
		end
	end
	for _, id in ipairs(neighbour.assignedHomebasePlaceIds) do
		if placeIds[id] then
			return true
		end
	end
	return false
end

-- True if neighbour has at least one assigned workplace id that exists as a resolved character_job place.
-- @param IANeighbour neighbour
-- @return boolean
function IAGameLoopHelper:neighbourHasWorkplacePlace(neighbour)
	if neighbour == nil or neighbour.assignedWorkplacePlaceIds == nil or #neighbour.assignedWorkplacePlaceIds == 0 then
		return false
	end
	local places = self.ianeighbours.places
	if places == nil or #places == 0 then
		return false
	end
	local placeIds = {}
	for _, p in ipairs(places) do
		if p ~= nil and p.id ~= nil and p.x ~= nil and p.z ~= nil then
			local st = string.lower(tostring((p.getSemanticType ~= nil and p:getSemanticType()) or p.type or ""))
			if st == "character_job" then
				placeIds[p.id] = true
			end
		end
	end
	for _, id in ipairs(neighbour.assignedWorkplacePlaceIds) do
		if placeIds[id] then
			return true
		end
	end
	return false
end

-- Homebase off-situation parking lives in IAHomebaseParking (see self.homebaseParking).

function IAGameLoopHelper:getAssignedHomebasePlacesForNeighbour(neighbour)
	return self.homebaseParking:getAssignedHomebasePlacesForNeighbour(neighbour)
end

function IAGameLoopHelper:spawnNonSituationVehiclesToHomebase(neighbour, scenario)
	self.homebaseParking:spawnNonSituationVehiclesToHomebase(neighbour, scenario)
end

function IAGameLoopHelper:reconcileNeighbourFleet(neighbour, context)
	if IAEquipmentPresence ~= nil and IAEquipmentPresence.Reconcile ~= nil then
		IAEquipmentPresence.Reconcile.reconcileNeighbourFleet(neighbour, context)
	end
end

-- @param string|number situationId - Situation config id from XML (e.g. "4")
-- @return IASituationConfig|nil
function IAGameLoopHelper:getSituationConfigById(situationId)
	if situationId == nil or self.ianeighbours.situationConfigs == nil then
		return nil
	end
	local want = tostring(situationId)
	for _, config in ipairs(self.ianeighbours.situationConfigs) do
		if config ~= nil and tostring(config.id) == want then
			return config
		end
	end
	return nil
end

-- Build scenario data for a chosen config (place + optional vehicles). Shared by generateNewSituation.
-- @return table|nil
function IAGameLoopHelper:buildScenarioDataForConfig(neighbour, selectedConfig)
	if neighbour == nil or selectedConfig == nil then
		return nil
	end
	local selectedPlace = self:selectRandomPlaceForSituation(selectedConfig, neighbour)
	if selectedPlace == nil then
		return nil
	end
	local situationVehicle = nil
	local attachmentBack = nil
	local attachmentFront = nil
	if selectedPlace.withVehicle == true then
		local vehiclesData = self:GetVehiclesForSituation(neighbour.vehicles, selectedConfig)
		situationVehicle = vehiclesData.vehicle
		attachmentBack = vehiclesData.attachmentBack
		attachmentFront = vehiclesData.attachmentFront
	end
	if selectedConfig.vehicles ~= nil and string.lower(tostring(selectedConfig.vehicles)) == "force" and situationVehicle == nil then
		return nil
	end
	local scenarioData = {
		config = selectedConfig,
		place = selectedPlace,
		vehicle = situationVehicle,
		attachmentBack = attachmentBack,
		attachmentFront = attachmentFront
	}
	local ok, _ = self:validateScenarioFleetVehicles(scenarioData)
	if not ok then
		return nil
	end
	return scenarioData
end
-- Prioritizes fieldwork for neighbours with role=Neighbour and job=Farmer
-- Situations are only generated if the neighbour has at least a homebase place defined.
-- @param IANeighbour neighbour - The neighbour to generate a situation for
-- @return table|nil - Table with keys: config (IASituationConfig), place (IAMapPlace), vehicle (IANeighbourVehicle), or nil if generation failed
function IAGameLoopHelper:generateNewSituation(neighbour)
	if neighbour == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - Neighbour is nil")
		end
		return nil
	end

	-- Only generate situations if this neighbour has a homebase place (avoids loop when no map config / no places)
	if not self:neighbourHasHomebasePlace(neighbour) then
		if self.ianeighbours.debug then
			--print("--- IAGameLoopHelper:generateNewSituation() - Neighbour "..tostring(neighbour.name).." has no homebase place, skipping situation generation")
		end
		return nil
	end

	local historyLen = (neighbour.situationHistory ~= nil) and #neighbour.situationHistory or 0

	-- First situation for every character: fixed "relax" (situation id 4), never fieldwork
	if historyLen == 0 then
		local relaxConfig = self:getSituationConfigById("4")
		if relaxConfig ~= nil then
			local firstResult = self:buildScenarioDataForConfig(neighbour, relaxConfig)
			if firstResult ~= nil then
				if IATestRunner ~= nil and type(IATestRunner.onSituationGenerated) == "function" then
					IATestRunner.onSituationGenerated(neighbour, firstResult, "first_relax")
				end
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:generateNewSituation() - First situation for "..tostring(neighbour.name)..": fixed relax (id 4)")
				end
				return firstResult
			end
			if self.ianeighbours.debug then
				print("--- IAGameLoopHelper:generateNewSituation() - First situation: could not create relax (id 4), falling back without fieldwork")
			end
		elseif self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - First situation: situation config id 4 (relax) not found")
		end
	end

	-- Prioritize fieldwork for farmer neighbours (role=Neighbour and job=Farmer) only after 6:00 — not for the very first situation
	local canGenerateFieldwork = false
	if g_currentMission and g_currentMission.environment then
		local hour = g_currentMission.environment.currentHour or 0
		-- Only generate fieldwork situations between 6:00 and 22:00 (not after 22)
		canGenerateFieldwork = hour >= 6 and hour < 22
	end

	-- Pause fieldwork starts while this neighbour is on the phone with the player (or has a pending ring):
	-- starting a new IASituation here would invalidate the contract just being negotiated and could
	-- claim implements the contract still depends on. Place-based situations remain allowed.
	if canGenerateFieldwork and IANeighbours ~= nil and type(IANeighbours.isNeighbourEngagedWithPlayer) == "function" and IANeighbours.isNeighbourEngagedWithPlayer(neighbour) then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - skipping fieldwork: " .. tostring(neighbour.name) .. " is on the phone with the player")
		end
		canGenerateFieldwork = false
	end

	if historyLen > 0 and canGenerateFieldwork and neighbour.role == "Neighbour" and neighbour.job == "Farmer" then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - Neighbour "..neighbour.name.." is a farmer, checking for fieldwork first")
		end

		self:ensureDailyFieldworkSchedule(neighbour)

		local fieldworkData = self:selectNewFieldwork(neighbour)
		if fieldworkData ~= nil then
			if IATestRunner ~= nil and type(IATestRunner.onSituationGenerated) == "function" then
				IATestRunner.onSituationGenerated(neighbour, fieldworkData, "fieldwork")
			end
			if self.ianeighbours.debug then
				print("--- IAGameLoopHelper:generateNewSituation() - Found fieldwork data for farmer neighbour "..neighbour.name)
			end
			-- Return fieldwork data with attachment, farmlandId, jobType, and optional seedFruitTypeIndex
			local result = {
				config = fieldworkData.config,
				place = fieldworkData.place,
				vehicle = fieldworkData.vehicle,
				attachmentBack = fieldworkData.attachmentBack,
				attachmentFront = fieldworkData.attachmentFront,
				farmlandId = fieldworkData.farmlandId,
				jobType = fieldworkData.jobType
			}
			if fieldworkData.seedFruitTypeIndex ~= nil then
				result.seedFruitTypeIndex = fieldworkData.seedFruitTypeIndex
			end
			return result
		else
			if self.ianeighbours.debug then
				print("--- IAGameLoopHelper:generateNewSituation() - No fieldwork found for farmer neighbour "..neighbour.name..", falling back to normal situation")
			end
		end
	end
	
	-- Place-based path: collect all eligible configs, try each in priority order until one builds.
	-- Regular configs are preferred (shuffled among themselves); when none of them can build right
	-- now (e.g. "prepare the tractor" needs a Tractor that is borrowed by the player or still loading,
	-- or a large_area homebase that this neighbour does not have), we fall back to random configs so
	-- the neighbour still gets a sensible situation (e.g. relax at home, walk the dog) instead of
	-- doing nothing at all. Without this fallback, farmers in months 3–10 would stall every morning
	-- whenever the regular morning config (id=30) cannot be set up, which is what was happening while
	-- contract-pending fieldwork blocked the fieldwork path too.
	local regularConfigs, randomConfigs = self:collectMatchingSituationConfigsForNeighbour(neighbour)
	if #regularConfigs == 0 and #randomConfigs == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - No situation config selected (none match daytime/minFrequency/role)")
		end
		return nil
	end

	if type(IAHelper_shuffleArrayInPlace) == "function" then
		IAHelper_shuffleArrayInPlace(regularConfigs)
		IAHelper_shuffleArrayInPlace(randomConfigs)
	end

	local function tryBuildFromList(list, label)
		for _, config in ipairs(list) do
			local r = self:buildScenarioDataForConfig(neighbour, config)
			if r ~= nil then
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:generateNewSituation() - Selected "..label.." situation "..tostring(config.id).." (Type: "..tostring(config.type)..", Daytime: "..tostring(config.daytime)..")")
				end
				return r
			elseif self.ianeighbours.debug then
				print("--- IAGameLoopHelper:generateNewSituation() - "..label.." situation "..tostring(config.id).." skipped: no matching place or requires vehicle (Force) but none found")
			end
		end
		return nil
	end

	if #regularConfigs > 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - Trying "..tostring(#regularConfigs).." regular situation(s) for "..tostring(neighbour.name))
		end
		local r = tryBuildFromList(regularConfigs, "regular")
		if r ~= nil then
			if IATestRunner ~= nil and type(IATestRunner.onSituationGenerated) == "function" then
				IATestRunner.onSituationGenerated(neighbour, r, "place_regular")
			end
			return r
		end
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:generateNewSituation() - No regular situation could be built for "..tostring(neighbour.name)..", falling back to "..tostring(#randomConfigs).." random situation(s)")
		end
	end

	local r = tryBuildFromList(randomConfigs, "random")
	if r ~= nil then
		if IATestRunner ~= nil and type(IATestRunner.onSituationGenerated) == "function" then
			IATestRunner.onSituationGenerated(neighbour, r, "place_random")
		end
		return r
	end

	if IATestRunner ~= nil and type(IATestRunner.onSituationGenerated) == "function" then
		IATestRunner.onSituationGenerated(neighbour, nil, "no_match")
	end

	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:generateNewSituation() - No situation could be built for "..tostring(neighbour.name).." (regular="..tostring(#regularConfigs)..", random="..tostring(#randomConfigs)..")")
	end
	return nil
end

-- Collect all open fieldwork (farmland + situation config) for a neighbour. Assumes neighbour and situationConfigs are valid.
-- @param IANeighbour neighbour
-- @return table array of { farmlandId, config, nextCropFruitTypeIndex? }
function IAGameLoopHelper:collectOpenFieldworkCandidates(neighbour)
	local candidates = {}
	if neighbour == nil or neighbour.assignedFarmlands == nil or #neighbour.assignedFarmlands == 0 then
		return candidates
	end
	if self.ianeighbours.situationConfigs == nil or #self.ianeighbours.situationConfigs == 0 then
		return candidates
	end

	local fieldworkConfigs = {}
	for _, config in ipairs(self.ianeighbours.situationConfigs) do
		if config ~= nil and config.type ~= nil and string.lower(tostring(config.type)) == "fieldwork" and config.fieldwork ~= nil and config.fieldwork ~= "" then
			if self:doesSituationConfigMatchNeighbour(config, neighbour) then
				local fwLower = string.lower(tostring(config.fieldwork))
				local calendarOk = false
				if fwLower == "seed" then
					local seedIdx = IAFieldwork.resolveFruitTypeNameOrIndex(config.seedFruitTypeIndex)
					calendarOk = iaFieldworkSeedCalendarAllowedForFruit(config, seedIdx)
				else
					calendarOk = iaSituationConfigMonthsMatchCurrent(config)
				end
				if calendarOk then
					table.insert(fieldworkConfigs, config)
				end
			end
		end
	end

	if #fieldworkConfigs == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - No fieldwork situation configs match neighbour "..tostring(neighbour.name))
		end
		return candidates
	end

	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - "..tostring(neighbour.name).." assignedFarmlands="..tostring(#neighbour.assignedFarmlands)..", fieldworkConfigs="..tostring(#fieldworkConfigs)..", month="..tostring(getEnvironmentMonth1to12()))
	end

	local farmlands = g_farmlandManager:getFarmlands()
	local seedCandidateCount = 0

	for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
		-- Skip farmland that is currently being worked by this neighbour's active fieldwork situation.
		local skipFarmland = false
		if neighbour.activeSituation ~= nil and neighbour.activeSituation.jobType ~= nil and neighbour.activeSituation.farmlandId ~= nil then
			if tonumber(neighbour.activeSituation.farmlandId) == tonumber(farmlandId) then
				skipFarmland = true
			end
		end
		if skipFarmland then
			-- (No goto in FS Lua)
		else
		local farmland = nil
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == farmlandId then
				farmland = f
				break
			end
		end

		if farmland ~= nil and farmland.field ~= nil and farmland.field.fieldState ~= nil then
			local mission = farmland.field.currentMission
			local hasPlayerContract = self:hasActivePlayerFieldOutcomeForFarmland(farmlandId)
			if (mission ~= nil and mission.farmId ~= nil) or hasPlayerContract then
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - Field "..tostring(farmlandId).." is in use by player (mission="..tostring(mission ~= nil)..", playerContract="..tostring(hasPlayerContract).."), skipping")
				end
			else
				local fieldState = farmland.field.fieldState
				for _, config in ipairs(fieldworkConfigs) do
					if self:doesFieldMatchSituationConfig(farmlandId, fieldState, config) then
						local isSeed = config.fieldwork ~= nil and string.lower(tostring(config.fieldwork)) == "seed"
						local candidate = { farmlandId = farmlandId, config = config }
						local addCandidate = true
						if isSeed then
							candidate.nextCropFruitTypeIndex = (neighbour.assignedFarmlandNextCrop ~= nil and neighbour.assignedFarmlandNextCrop[farmlandId] ~= nil) and neighbour.assignedFarmlandNextCrop[farmlandId] or self:getNextCropForField(neighbour, farmlandId)
							if candidate.nextCropFruitTypeIndex ~= nil and config.seedFruitTypeIndex ~= nil and config.seedFruitTypeIndex ~= "" then
								local configSeedIndex = IAFieldwork.resolveFruitTypeNameOrIndex(config.seedFruitTypeIndex)
								if configSeedIndex == nil or configSeedIndex ~= candidate.nextCropFruitTypeIndex then
									addCandidate = false
									if self.ianeighbours.debug then
										local ft = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(candidate.nextCropFruitTypeIndex)
										local nextName = (ft and ft.name) or tostring(candidate.nextCropFruitTypeIndex)
										print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - SEED candidate rejected: farmland "..tostring(farmlandId)..", situation "..tostring(config.id).." seedFruitTypeIndex="..tostring(config.seedFruitTypeIndex).." (index "..tostring(configSeedIndex)..") does not match nextCrop "..tostring(nextName).." ("..tostring(candidate.nextCropFruitTypeIndex)..")")
									end
								end
							end
							if addCandidate then
								seedCandidateCount = seedCandidateCount + 1
								if self.ianeighbours.debug then
									local nextIdx = candidate.nextCropFruitTypeIndex
									local nameStr = "nil"
									if nextIdx ~= nil and g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex then
										local ft = g_fruitTypeManager:getFruitTypeByIndex(nextIdx)
										nameStr = (ft and ft.name) or tostring(nextIdx)
									elseif nextIdx ~= nil then
										nameStr = tostring(nextIdx)
									end
									print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - SEED candidate: farmland "..tostring(farmlandId)..", situation "..tostring(config.id)..", nextCrop="..tostring(nameStr).." ("..tostring(nextIdx or "nil")..")")
								end
							end
						else
							if self.ianeighbours.debug then
								print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - Match: farmland "..tostring(farmlandId)..", situation "..tostring(config.id).." ("..tostring(config.fieldwork)..")")
							end
						end
						if addCandidate then
							table.insert(candidates, candidate)
						end
					end
				end
			end
		end
		end
	end

	if self.ianeighbours.debug and #candidates > 0 then
		print("--- IAGameLoopHelper:collectOpenFieldworkCandidates() - total="..tostring(#candidates).." (SEED rows="..tostring(seedCandidateCount)..")")
	end

	return candidates
end

-- Dev/console: pick the next fieldwork situation only (same rules as selectNewFieldwork: fields, XML configs, vehicles).
-- Skips the normal generator's first-relax situation, time-of-day window, and farmer-only branch — still requires a homebase.
-- @param IANeighbour neighbour
-- @return table|nil scenarioData compatible with IANeighbour:getNextSituation / IASituation.new
function IAGameLoopHelper:generateForcedFieldworkSituation(neighbour)
	if neighbour == nil then
		return nil, "neighbour is nil"
	end
	if not self:neighbourHasHomebasePlace(neighbour) then
		return nil, "no homebase place"
	end
	local fieldworkData = self:selectNewFieldwork(neighbour)
	if fieldworkData == nil then
		return nil, "no matching fieldwork (farmlands, situation XML, or vehicles)"
	end
	local result = {
		config = fieldworkData.config,
		place = fieldworkData.place,
		vehicle = fieldworkData.vehicle,
		attachmentBack = fieldworkData.attachmentBack,
		attachmentFront = fieldworkData.attachmentFront,
		farmlandId = fieldworkData.farmlandId,
		jobType = fieldworkData.jobType
	}
	if fieldworkData.seedFruitTypeIndex ~= nil then
		result.seedFruitTypeIndex = fieldworkData.seedFruitTypeIndex
	end
	local ok, err = self:validateScenarioFleetVehicles(result)
	if not ok then
		return nil, err or "required fleet vehicle borrowed by player"
	end
	return result, nil
end

-- Dev/console: build scenario data for a specific situation id.
-- Forces initialization even when natural-path filters (daytime, minFrequency, months) would block it,
-- but logs a console warning so you can see which checks would have prevented a natural spawn.
-- Still requires role/job, place, and vehicles (hard gates).
-- Fieldwork configs use open-fieldwork candidates; other configs use place-based buildScenarioDataForConfig.
-- @param IANeighbour neighbour
-- @param string|number situationId
-- @return table|nil scenarioData, string|nil errorMessage
function IAGameLoopHelper:generateForcedSituation(neighbour, situationId)
	if neighbour == nil then
		return nil, "neighbour is nil"
	end
	if situationId == nil or tostring(situationId) == "" then
		return nil, "situation id required"
	end
	if not self:neighbourHasHomebasePlace(neighbour) then
		return nil, "no homebase place"
	end
	local config = self:getSituationConfigById(situationId)
	if config == nil then
		return nil, "unknown situation id " .. tostring(situationId)
	end

	-- Collect natural-path warnings (daytime, minFrequency, months) for both paths.
	local function collectNaturalFilterWarnings(cfg)
		local warnings = {}
		local currentDaytime = getCurrentDaytime()
		local currentGameHours = getCurrentGameHours()
		if not self:situationConfigMatchesDaytime(cfg.daytime, currentDaytime) then
			table.insert(warnings, "daytime mismatch: config=" .. tostring(cfg.daytime) .. " current=" .. tostring(currentDaytime))
		end
		if not self:situationConfigPassesMinFrequency(cfg, neighbour, currentGameHours) then
			table.insert(warnings, "minFrequency not met")
		end
		if not iaSituationConfigMonthsMatchCurrent(cfg) then
			local currentMonth = getEnvironmentMonth1to12()
			local monthStrs = {}
			if cfg.months then for _, m in ipairs(cfg.months) do table.insert(monthStrs, tostring(m)) end end
			table.insert(warnings, "months mismatch: config=[" .. table.concat(monthStrs, ",") .. "] current=" .. tostring(currentMonth))
		end
		return warnings
	end

	local isFieldwork = config.type ~= nil and string.lower(tostring(config.type)) == "fieldwork"
	if isFieldwork then
		local want = tostring(situationId)
		local candidates = self:collectOpenFieldworkCandidates(neighbour)
		local matching = {}
		for _, c in ipairs(candidates) do
			if c.config ~= nil and tostring(c.config.id) == want then
				matching[#matching + 1] = c
			end
		end
		if #matching == 0 then
			local warnings = collectNaturalFilterWarnings(config)
			if #warnings > 0 then
				print("[iaForceSituation] WARNING: fieldwork situation " .. tostring(situationId) .. " would NOT be selected naturally for " .. tostring(neighbour.name) .. ":")
				for _, w in ipairs(warnings) do
					print("  - " .. w)
				end
			end
			return nil, "fieldwork conditions not met (farmlands, field state, calendar, or role/job) — natural filters logged above"
		end
		-- Log warnings even when naturally eligible (informational)
		local warnings = collectNaturalFilterWarnings(config)
		if #warnings > 0 then
			print("[iaForceSituation] INFO: fieldwork situation " .. tostring(situationId) .. " for " .. tostring(neighbour.name) .. " — natural filters would normally reject:")
			for _, w in ipairs(warnings) do
				print("  - " .. w)
			end
			print("  (forcing anyway via iaForceSituation)")
		end
		local pick = matching[math.random(1, #matching)]
		local result = self:buildFieldworkScenarioFromOpenFieldwork(neighbour, pick)
		if result == nil then
			return nil, "could not build fieldwork scenario (vehicles borrowed, missing, or terrain)"
		end
		local ok, err = self:validateScenarioFleetVehicles(result)
		if not ok then
			return nil, err or "required fleet vehicle borrowed by player"
		end
		return result
	end

	-- Place-based path: role/job is a hard gate; daytime/minFrequency/months are soft (logged, then forced).
	if not self:doesSituationConfigMatchNeighbour(config, neighbour) then
		return nil, "situation filters not met (role/job)"
	end
	local warnings = collectNaturalFilterWarnings(config)
	if #warnings > 0 then
		print("[iaForceSituation] WARNING: place-based situation " .. tostring(situationId) .. " would NOT be selected naturally for " .. tostring(neighbour.name) .. ":")
		for _, w in ipairs(warnings) do
			print("  - " .. w)
		end
		print("  (forcing anyway via iaForceSituation)")
	end
	local result = self:buildScenarioDataForConfig(neighbour, config)
	if result == nil then
		return nil, "no matching place or requires vehicle (Force) but none available (borrowed or missing)"
	end
	local ok, err = self:validateScenarioFleetVehicles(result)
	if not ok then
		return nil, err or "required fleet vehicle borrowed by player"
	end
	return result
end

-- All open fieldwork matches for the neighbour (no random pick). Same semantics as getOpenFieldwork for eligibility.
-- @param IANeighbour neighbour
-- @return table array of { farmlandId, config, nextCropFruitTypeIndex? }; empty if none
function IAGameLoopHelper:getAllOpenFieldwork(neighbour)
	if neighbour == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getAllOpenFieldwork() - Neighbour is nil")
		end
		return {}
	end
	if neighbour.assignedFarmlands == nil or #neighbour.assignedFarmlands == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getAllOpenFieldwork() - Neighbour "..neighbour.name.." has no assigned farmlands")
		end
		return {}
	end
	if self.ianeighbours.situationConfigs == nil or #self.ianeighbours.situationConfigs == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getAllOpenFieldwork() - No situation configs available")
		end
		return {}
	end
	local candidates = self:collectOpenFieldworkCandidates(neighbour)
	if #candidates == 0 and self.ianeighbours.debug then
		print("--- IAGameLoopHelper:getAllOpenFieldwork() - No open fieldwork for neighbour "..neighbour.name)
	end
	return candidates
end

-- Get open fieldwork for a neighbour's assigned farmlands.
-- Fields are checked against fieldwork situation criteria (triggerGroundType, triggerFruitTypeIndex, triggerGrowthState, triggerWeedState).
-- Returns one randomly selected match: { farmlandId, config }. Job type is config.fieldwork.
-- @param IANeighbour neighbour - The neighbour to check farmlands for
-- @return table|nil - Table with keys: farmlandId (number), config (IASituationConfig); or nil if no match
function IAGameLoopHelper:getOpenFieldwork(neighbour)
	if neighbour == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getOpenFieldwork() - Neighbour is nil")
		end
		return nil
	end

	if neighbour.assignedFarmlands == nil or #neighbour.assignedFarmlands == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getOpenFieldwork() - Neighbour "..neighbour.name.." has no assigned farmlands")
		end
		return nil
	end

	if self.ianeighbours.situationConfigs == nil or #self.ianeighbours.situationConfigs == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getOpenFieldwork() - No situation configs available")
		end
		return nil
	end

	local candidates = self:collectOpenFieldworkCandidates(neighbour)
	if #candidates == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:getOpenFieldwork() - No fieldwork situation configs match neighbour "..neighbour.name.." or no open fieldwork found")
		end
		return nil
	end

	local selectedIndex = math.random(1, #candidates)
	local selected = candidates[selectedIndex]

	if self.ianeighbours.debug then
		local nextStr = (selected.nextCropFruitTypeIndex ~= nil) and tostring(selected.nextCropFruitTypeIndex) or "nil"
		local nameStr = nextStr
		if selected.nextCropFruitTypeIndex ~= nil and g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex then
			local ft = g_fruitTypeManager:getFruitTypeByIndex(selected.nextCropFruitTypeIndex)
			nameStr = (ft and ft.name) or nextStr
		end
		print("--- IAGameLoopHelper:getOpenFieldwork() - Candidates total="..tostring(#candidates)..", selected #"..tostring(selectedIndex)..": farmland "..tostring(selected.farmlandId)..", situation "..tostring(selected.config.id).." ("..tostring(selected.config.fieldwork).."), nextCropFruitTypeIndex="..tostring(nameStr).." ("..tostring(nextStr)..")")
	end

	local result = {
		farmlandId = selected.farmlandId,
		config = selected.config
	}
	if selected.nextCropFruitTypeIndex ~= nil then
		result.nextCropFruitTypeIndex = selected.nextCropFruitTypeIndex
	end
	return result
end

-- Select and return data for a new fieldwork situation.
-- Uses getOpenFieldwork to find (farmland, situation) matches by situation criteria; job type comes from the situation config.
-- @param IANeighbour neighbour - The neighbour to get fieldwork data for
-- @return table|nil - Table with keys: config (IASituationConfig), place (IAMapPlace), vehicle (IANeighbourVehicle), attachmentBack (IANeighbourVehicle|nil), farmlandId (number), jobType (string), or nil if no fieldwork
function IAGameLoopHelper:selectNewFieldwork(neighbour)
	if neighbour == nil then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectNewFieldwork() - Neighbour is nil")
		end
		return nil
	end

	self:ensureDailyFieldworkSchedule(neighbour)
	local tasks = neighbour.fieldworkScheduleTasks
	if tasks == nil or #tasks == 0 then
		if self.ianeighbours.debug then
			print("--- IAGameLoopHelper:selectNewFieldwork() - No scheduled fieldwork for neighbour "..tostring(neighbour.name))
		end
		return nil
	end

	-- Walk the schedule but only consume (table.remove) rows that this AI run is taking on
	-- or that we positively know are stale. Rows the player is actively handling
	-- (acceptedByPlayer=true) must stay in place so a later cancel can restore them to AI
	-- work via applyAcceptedContractMissionEndToSchedule.
	local idx = 1
	while idx <= #tasks do
		local entry = tasks[idx]
		if entry == nil then
			table.remove(tasks, idx)
		elseif entry.acceptedByPlayer == true then
			-- Player took this slot; do not work it, do not drop it, just look past.
			idx = idx + 1
		else
			local openFieldwork = self:validateScheduleEntry(neighbour, entry)
			if openFieldwork == nil then
				table.remove(tasks, idx)
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:selectNewFieldwork() - Dropped invalid/stale schedule entry at idx "..tostring(idx).." for "..tostring(neighbour.name))
				end
			elseif entry.contractEnabled == true
				and not (IASettings ~= nil and type(IASettings.isMissionOfferModeClassic) == "function" and IASettings.isMissionOfferModeClassic())
			then
				-- Contract row still pending player decision: block AI until accept/decline/15:00 fallback resolves it.
				-- In classic mode this branch is skipped (no phone calls exist), so the row falls through to normal AI work.
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:selectNewFieldwork() - Task at idx "..tostring(idx).." is contract-pending for " .. tostring(neighbour.name) .. ", waiting for accept/decline/15:00 fallback")
				end
				return nil
			elseif self:isAnyFleetVehicleForConfigBorrowedByPlayer(neighbour, openFieldwork.config) then
				-- Equipment required for this row is currently borrowed by the player
				-- (typical case: player accepted only part of a bundled contract).
				-- Keep the row in the schedule and step over it so the AI retries
				-- once the gear is returned. Do NOT table.remove.
				if self.ianeighbours.debug then
					print("--- IAGameLoopHelper:selectNewFieldwork() - Task at idx "..tostring(idx).." skipped (required equipment borrowed by player) for "..tostring(neighbour.name))
				end
				idx = idx + 1
			else
				local fieldworkConfig = openFieldwork.config
				if self.ianeighbours.debug then
					local seedIdx = openFieldwork.nextCropFruitTypeIndex
					local seedName = tostring(seedIdx or "nil")
					if seedIdx ~= nil and g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex then
						local ft = g_fruitTypeManager:getFruitTypeByIndex(seedIdx)
						seedName = (ft and ft.name) or tostring(seedIdx)
					end
					local rawFw = (fieldworkConfig.fieldwork ~= nil and fieldworkConfig.fieldwork ~= "") and string.lower(tostring(fieldworkConfig.fieldwork)) or "nil"
					print("--- IAGameLoopHelper:selectNewFieldwork() - schedule pick at idx "..tostring(idx)..": neighbour="..tostring(neighbour.name)..", farmlandId="..tostring(openFieldwork.farmlandId)..", config.id="..tostring(fieldworkConfig.id)..", fieldwork="..tostring(rawFw)..", nextCropFruitTypeIndex="..tostring(seedName))
				end

				local result = self:buildFieldworkScenarioFromOpenFieldwork(neighbour, openFieldwork)
				if result == nil then
					table.remove(tasks, idx)
					if self.ianeighbours.debug then
						print("--- IAGameLoopHelper:selectNewFieldwork() - Could not build scenario (vehicles/terrain), dropping entry at idx "..tostring(idx).." for "..tostring(neighbour.name))
					end
				else
					table.remove(tasks, idx)
					if self.ianeighbours.debug then
						local seedInfo = (result.seedFruitTypeIndex ~= nil) and (" seedFruitTypeIndex="..tostring(result.seedFruitTypeIndex)) or ""
						print("--- IAGameLoopHelper:selectNewFieldwork() - Returning scheduled fieldwork: "..tostring(neighbour.name).." farmland "..tostring(result.farmlandId)..", situation "..tostring(fieldworkConfig.id)..", jobType "..tostring(result.jobType)..seedInfo)
					end
					return result
				end
			end
		end
	end

	if self.ianeighbours.debug then
		print("--- IAGameLoopHelper:selectNewFieldwork() - Schedule exhausted for neighbour "..tostring(neighbour.name))
	end
	return nil
end
