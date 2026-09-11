--
-- FS25 Fields of Stories — probe vs expected FieldState comparison for phone field-outcome missions.
-- Pure helpers (no Class): keeps fertilize spray equivalence and key iteration out of IAFieldOutcomeMission update flow.
--

IAFieldOutcomeMissionProbeEvaluator = IAFieldOutcomeMissionProbeEvaluator or {}

--- FS25: mineral fertilizer may read as MANURE on the field while the contract stores FERTILIZER.
-- @param string|nil fieldworkJobRaw situation / mission raw job string (before normalize)
-- @param number|nil expectedIdx expected FieldState.sprayType
-- @param number|nil actualIdx sampled FieldState.sprayType
-- @return boolean
function IAFieldOutcomeMissionProbeEvaluator.fertilizeSprayTypeKeyMatches(fieldworkJobRaw, expectedIdx, actualIdx)
	local e = tonumber(expectedIdx)
	local a = tonumber(actualIdx)
	if e ~= nil and a ~= nil and e == a then
		return true
	end
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" or type(IAFieldwork.getFieldSprayTypeIndexForEnumName) ~= "function" then
		return false
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(fieldworkJobRaw or ""))
	if not IAFieldwork.isFertilizeJobType(jt) then
		return false
	end
	local fert = tonumber(IAFieldwork.getFieldSprayTypeIndexForEnumName("FERTILIZER"))
	local man = tonumber(IAFieldwork.getFieldSprayTypeIndexForEnumName("MANURE"))
	if fert ~= nil and man ~= nil and e == fert and a == man then
		return true
	end
	return false
end

--- Spray contracts: any post-herbicide "withered" weedState (7/8/9, incl. PF target 9) counts as sprayed.
--- weedState 0 also passes: tramlines / Precision Farming spots with no crop have no weeds to spray either.
function IAFieldOutcomeMissionProbeEvaluator.sprayWeedStateKeyMatches(fieldworkJobRaw, expectedIdx, actualIdx)
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return false
	end
	if IAFieldwork.normalizeFieldworkJobType(tostring(fieldworkJobRaw or "")) ~= IAFieldwork.JobType.SPRAY then
		return false
	end
	local e, a = tonumber(expectedIdx), tonumber(actualIdx)
	if e ~= nil and a ~= nil and e == a then
		return true
	end
	-- Precision Farming / tramlines: a bare spot with no crop also has no weeds (weedState 0).
	-- It is already "clean", so treat it as sprayed instead of failing the probe.
	if a ~= nil and a == 0 then
		return true
	end
	if type(IAFieldwork.isPostHerbicideWeedState) == "function" then
		return IAFieldwork.isPostHerbicideWeedState(e) and IAFieldwork.isPostHerbicideWeedState(a)
	end
	return (e == 7 or e == 8) and (a == 7 or a == 8)
end

--- Cultivate contracts: a finished cultivation reads as CULTIVATED, but a field worked further into a
--- SEEDBED (e.g. power harrow / seeder pass) has also clearly been cultivated, so accept it too.
-- @param string|nil fieldworkJobRaw situation / mission raw job string (before normalize)
-- @param number|nil expectedIdx expected FieldState.groundType (CULTIVATED for cultivate)
-- @param number|nil actualIdx sampled FieldState.groundType
-- @return boolean
function IAFieldOutcomeMissionProbeEvaluator.cultivateGroundTypeKeyMatches(fieldworkJobRaw, expectedIdx, actualIdx)
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return false
	end
	if IAFieldwork.normalizeFieldworkJobType(tostring(fieldworkJobRaw or "")) ~= IAFieldwork.JobType.CULTIVATE then
		return false
	end
	local e, a = tonumber(expectedIdx), tonumber(actualIdx)
	if e == nil or a == nil then
		return false
	end
	local cultivated = (FieldGroundType ~= nil and tonumber(FieldGroundType.CULTIVATED)) or 3
	local seedbed = (FieldGroundType ~= nil and tonumber(FieldGroundType.SEEDBED)) or 4
	if e ~= cultivated then
		return false
	end
	return a == cultivated or a == seedbed
end

--- Seed contracts: a finished seeding reads as SOWN, but seeding over stubble (no prior cultivation pass)
--- can leave the ground reading as SEEDED instead. Both mean the field has been sown, so accept either.
--- The real proof of a completed seeding is the growthState / fruitTypeIndex keys, not the exact groundType.
-- @param string|nil fieldworkJobRaw situation / mission raw job string (before normalize)
-- @param number|nil expectedIdx expected FieldState.groundType (SOWN for seed)
-- @param number|nil actualIdx sampled FieldState.groundType
-- @return boolean
function IAFieldOutcomeMissionProbeEvaluator.seedGroundTypeKeyMatches(fieldworkJobRaw, expectedIdx, actualIdx)
	if IAFieldwork == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return false
	end
	if IAFieldwork.normalizeFieldworkJobType(tostring(fieldworkJobRaw or "")) ~= IAFieldwork.JobType.SEED then
		return false
	end
	local e, a = tonumber(expectedIdx), tonumber(actualIdx)
	if e == nil or a == nil then
		return false
	end
	local sown = (FieldGroundType ~= nil and tonumber(FieldGroundType.SOWN)) or 8
	local seeded = (FieldGroundType ~= nil and tonumber(FieldGroundType.SEEDED)) or 9
	if e ~= sown then
		return false
	end
	return a == sown or a == seeded
end

local function keyMatchesExpected(fieldworkJobRaw, k, expected, actual)
	if k == "sprayType" then
		return IAFieldOutcomeMissionProbeEvaluator.fertilizeSprayTypeKeyMatches(fieldworkJobRaw, expected, actual)
	end
	if k == "weedState" then
		if IAFieldOutcomeMissionProbeEvaluator.sprayWeedStateKeyMatches(fieldworkJobRaw, expected, actual) then
			return true
		end
	end
	if k == "groundType" then
		if IAFieldOutcomeMissionProbeEvaluator.cultivateGroundTypeKeyMatches(fieldworkJobRaw, expected, actual) then
			return true
		end
		if IAFieldOutcomeMissionProbeEvaluator.seedGroundTypeKeyMatches(fieldworkJobRaw, expected, actual) then
			return true
		end
	end
	-- Outbound XML / streams may store numbers as strings; FieldState samples are numeric.
	if k == "sprayLevel" or k == "limeLevel" or k == "weedState" or k == "weedFactor" or k == "growthState" or k == "fruitTypeIndex" or k == "groundType" or k == "plowLevel" or k == "rollerLevel" or k == "stubbleShredLevel" or k == "stoneLevel" or k == "waterLevel" then
		local ev, av = tonumber(expected), tonumber(actual)
		return av ~= nil and ev ~= nil and ev == av
	end
	return actual ~= nil and actual == expected
end

--- True when the raw fieldwork string normalizes to a job where a bare tramline spot (no seed,
-- so no crop) has nothing left to do: harvest (nothing to harvest) or harrow (no stubble to work).
function IAFieldOutcomeMissionProbeEvaluator.isTramlineJob(fieldworkJobRaw)
	if IAFieldwork == nil or IAFieldwork.JobType == nil or type(IAFieldwork.normalizeFieldworkJobType) ~= "function" then
		return false
	end
	local jt = IAFieldwork.normalizeFieldworkJobType(tostring(fieldworkJobRaw or ""))
	return jt == IAFieldwork.JobType.HARVEST or jt == IAFieldwork.JobType.HARROW
end

--- True when a sampled FieldState has no fruit at all (fruitTypeIndex UNKNOWN and growthState 0),
-- e.g. a tramline where the seeder skipped the row so there is no crop to harvest or cultivate.
function IAFieldOutcomeMissionProbeEvaluator.probeHasNoFruit(probe)
	if probe == nil then
		return false
	end
	local unknown = (FruitType ~= nil and FruitType.UNKNOWN ~= nil) and tonumber(FruitType.UNKNOWN) or 0
	local fti = tonumber(probe.fruitTypeIndex)
	local gs = tonumber(probe.growthState)
	return (fti == nil or fti == 0 or fti == unknown) and (gs == nil or gs == 0)
end

--- True when every key in `expected` is satisfied by `probe` (same FieldState key names).
-- @param table|nil expected contract subset (numeric FieldState keys)
-- @param string|nil fieldworkJobRaw for fertilize-only sprayType equivalence
-- @param table|nil probe sampled FieldState
-- @return boolean
function IAFieldOutcomeMissionProbeEvaluator.probeSatisfiesExpected(expected, fieldworkJobRaw, probe)
	if probe == nil or expected == nil or type(expected) ~= "table" then
		return false
	end
	local hasAny = false
	for _ in pairs(expected) do
		hasAny = true
		break
	end
	if not hasAny then
		return false
	end
	-- Tramline / Precision Farming: a spot with no crop has nothing to harvest or work, so it
	-- already satisfies the outcome instead of failing the fruitTypeIndex/growthState/groundType keys.
	if IAFieldOutcomeMissionProbeEvaluator.isTramlineJob(fieldworkJobRaw)
		and IAFieldOutcomeMissionProbeEvaluator.probeHasNoFruit(probe) then
		return true
	end
	for k, exp in pairs(expected) do
		if not keyMatchesExpected(fieldworkJobRaw, k, exp, probe[k]) then
			return false
		end
	end
	return true
end

--- First key where `probe` disagrees with `expected`, or sentinels for nil probe/expected.
-- @return string|nil diffKey use missHistogramBucket() for log buckets; nil means all keys match
-- @return any expected value at that key
-- @return any actual value at that key
function IAFieldOutcomeMissionProbeEvaluator.probeFirstKeyDifference(expected, fieldworkJobRaw, probe)
	if probe == nil then
		return "_probe_nil", nil, nil
	end
	if expected == nil then
		return "_expected_nil", nil, nil
	end
	for k, exp in pairs(expected) do
		if not keyMatchesExpected(fieldworkJobRaw, k, exp, probe[k]) then
			return k, exp, probe[k]
		end
	end
	return nil, nil, nil
end

--- Map diffKey from probeFirstKeyDifference to stable histogram bucket names.
function IAFieldOutcomeMissionProbeEvaluator.missHistogramBucket(diffKey)
	if diffKey == "_probe_nil" then
		return "FieldState_nil"
	end
	if diffKey == "_expected_nil" then
		return "expected_nil"
	end
	return diffKey
end

--- Run probe list against expected FieldState: sample at each point, count matches, collect miss lines and histogram buckets.
--- @param table plist array of probes { x, z, kind, ... }
--- @param table|nil expState expected keys
--- @param string|nil jobRaw raw fieldwork string (fertilize spray equivalence)
--- @param function sampleAt function(x, z) -> FieldState|nil
--- @param table|nil opts maxMissLogLines (default 48), mismatchAnnot (sprayType / fruitTypeIndex formatters), probeThreshold (default 1.0 — fraction of probes that must match for allFinished=true)
--- @return table matched, total, nVertex, nInterior, missLines, missCounts, allFinished, fieldPercentageDone
function IAFieldOutcomeMissionProbeEvaluator.evaluateAllProbes(plist, expState, jobRaw, sampleAt, opts)
	opts = opts or {}
	local maxMissLogLines = opts.maxMissLogLines or 48
	local mismatchAnnot = opts.mismatchAnnot
	local matched, total = 0, 0
	local missLines = {}
	local missCounts = {}
	local nVertex, nInterior = 0, 0
	if plist == nil or sampleAt == nil or type(sampleAt) ~= "function" then
		return {
			matched = 0,
			total = 0,
			nVertex = 0,
			nInterior = 0,
			missLines = missLines,
			missCounts = missCounts,
			allFinished = false,
			fieldPercentageDone = 0,
		}
	end
	total = #plist
	if total < 1 then
		return {
			matched = 0,
			total = 0,
			nVertex = 0,
			nInterior = 0,
			missLines = missLines,
			missCounts = missCounts,
			allFinished = false,
			fieldPercentageDone = 0,
		}
	end
	for _, p in ipairs(plist) do
		if p.kind == "V" then
			nVertex = nVertex + 1
		else
			nInterior = nInterior + 1
		end
	end
	local eval = IAFieldOutcomeMissionProbeEvaluator
	for i, p in ipairs(plist) do
		local state = sampleAt(p.x, p.z)
		if eval.probeSatisfiesExpected(expState, jobRaw, state) then
			matched = matched + 1
		else
			local dk, ev, ac = eval.probeFirstKeyDifference(expState, jobRaw, state)
			if #missLines < maxMissLogLines then
				table.insert(
					missLines,
					string.format(
						"probe[%d] kind=%s xz=%.2f,%.2f -> %s",
						i,
						tostring(p.kind),
						tonumber(p.x) or -1,
						tonumber(p.z) or -1,
						eval.formatFirstMismatchOneLine(dk, ev, ac, mismatchAnnot)
					)
				)
			end
			if dk ~= nil then
				local bucket = eval.missHistogramBucket(dk)
				missCounts[bucket] = (missCounts[bucket] or 0) + 1
			end
		end
	end
	local threshold = opts.probeThreshold or 1.0
	local allFinished = (total > 0 and (matched / total) >= threshold)
	local fp = 0
	if total > 0 then
		fp = math.max(0, math.min(1, matched / total))
	end
	return {
		matched = matched,
		total = total,
		nVertex = nVertex,
		nInterior = nInterior,
		missLines = missLines,
		missCounts = missCounts,
		allFinished = allFinished,
		fieldPercentageDone = fp,
	}
end

--- One-line debug reason for a mismatch (or sentinels / "ok").
-- @param table|nil annotateFns optional .sprayType(idx) and .fruitTypeIndex(idx) for readable logs
function IAFieldOutcomeMissionProbeEvaluator.formatFirstMismatchOneLine(key, expected, actual, annotateFns)
	if key == "_probe_nil" then
		return "FieldState_nil"
	end
	if key == "_expected_nil" then
		return "expected_nil"
	end
	if key == nil then
		return "ok"
	end
	annotateFns = annotateFns or {}
	local expS, actS = tostring(expected), tostring(actual)
	if key == "sprayType" and type(annotateFns.sprayType) == "function" then
		expS = annotateFns.sprayType(expected)
		actS = annotateFns.sprayType(actual)
	elseif key == "fruitTypeIndex" and type(annotateFns.fruitTypeIndex) == "function" then
		expS = annotateFns.fruitTypeIndex(expected)
		actS = annotateFns.fruitTypeIndex(actual)
	end
	return string.format("%s expected=%s actual=%s", tostring(key), expS, actS)
end

return IAFieldOutcomeMissionProbeEvaluator
