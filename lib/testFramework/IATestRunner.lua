--
-- IATestRunner.lua — AI-assisted test runner for Fields of Stories
--
-- Captures structured diagnostic logs during controlled test scenarios.
-- Results are saved to modSettings/FoS_tests/ as .jsonl files for
-- external AI evaluation or PowerShell capture.
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo / Copilot
-- @Date: 28.06.2026

IATestRunner = {}
IATestRunner._mt = Class(IATestRunner)

-- ============================================================================
-- Configuration
-- ============================================================================

--- Prefix for all structured log lines emitted to the game console.
IATestRunner.CONSOLE_PREFIX = "[FOS_TEST]"

--- Maximum wall-clock seconds a test may run before auto-aborting.
--- Long schedule tests at timeScale=499 need ~3 min for a full day advance.
IATestRunner.TEST_TIMEOUT_SEC = 360

--- Directory under modSettings for test output.
IATestRunner.TEST_OUTPUT_SUBDIR = "FoS_tests"

-- ============================================================================
-- State
-- ============================================================================

--- true while a test scenario is actively running.
IATestRunner._testActive = false

--- Buffered structured log entries for the current test.
IATestRunner._logLines = {}

--- Wall-clock timestamp when the current test began.
IATestRunner._wallClockStart = 0

--- Name of the currently running test (or nil).
IATestRunner._testName = nil

--- Human-readable description of the current test scenario.
IATestRunner._testDescription = nil

--- Reference to the currently running scenario table (for cleanup access).
IATestRunner._currentScenario = nil

--- Queue of pending actions for the current scenario.
IATestRunner._pendingActions = {}

--- 1-based index of the next action to execute.
IATestRunner._actionIndex = 0

--- Frames remaining for a waitFrames action.
IATestRunner._waitFramesRemaining = 0

--- Wall-clock deadline for a waitWallClock action.
IATestRunner._waitWallClockUntil = nil

--- Polling deadline for a waitForLogEvent action.
IATestRunner._waitLogEventUntil = nil
--- Category to poll for in waitForLogEvent.
IATestRunner._waitLogEventCategory = nil
--- Event to poll for in waitForLogEvent.
IATestRunner._waitLogEventEvent = nil

--- Game-time target for waitGameMinutes / waitGameHours / waitGameDays.
IATestRunner._waitGameTimeTarget = nil

--- Condition function for waitFor* actions (called each frame until truthy).
IATestRunner._waitConditionFn = nil

--- Label for the current wait condition (for logging).
IATestRunner._waitConditionLabel = nil

--- true when any assert/fail has been emitted during this test.
IATestRunner._anyAssertionFailed = false

--- Optional override for the outsourced fieldwork type (contract type) chosen during
--- rebuildDailyFieldworkSchedule. Set to e.g. "harvest" to force harvest contracts.
--- Reset to nil in cleanupTestState between batch tests.
IATestRunner.forceOutsourceType = nil

--- Phase tracking for waitForNaturalContractCall: nil | "advancing" | "waiting".
IATestRunner._natCallPhase = nil
--- Neighbour name stored during natural contract call wait.
IATestRunner._natCallNeighbourName = nil
--- Wall-clock deadline (seconds) for the ring-wait phase of waitForNaturalContractCall.
IATestRunner._natCallTimeoutSec = nil
--- Wall-clock timestamp when the ring-wait phase began.
IATestRunner._natCallWaitStart = nil

--- Hook installed in IANeighbours:update when a test runs.
IATestRunner._updateHookInstalled = false

--- All registered test scenarios (indexed by name).
IATestRunner._scenarios = {}

-- ============================================================================
-- Auto-Run State (driven by IATestRegistry)
-- ============================================================================

--- true after the auto-run sequence has been started (prevents double-trigger).
IATestRunner._autoRunStarted = false

--- true while the auto-run sequence is actively running tests.
IATestRunner._autoRunActive = false

--- Wall-clock seconds when outbound XML was loaded (set by tryAutoRun on first call).
IATestRunner._autoRunLoadTimeSec = nil

--- Queue of test names remaining in the current auto-run batch.
IATestRunner._autoRunQueue = {}

--- Current test index in the auto-run batch (1-based, for logging).
IATestRunner._autoRunIndex = 0

--- Total test count in the auto-run batch.
IATestRunner._autoRunTotal = 0

-- ============================================================================
-- Structured Log Emission
-- ============================================================================

--- Emit a structured log entry. If no test is active, this is a no-op.
--- @param category string  e.g. "schedule", "situation", "time", "phone"
--- @param event   string  e.g. "rebuild_begin", "generated", "ring_start"
--- @param data    table|nil  arbitrary key-value pairs to include
function IATestRunner.emit(category, event, data)
	if not IATestRunner._testActive then
		return
	end
	local elapsed = (IANeighbours._wallClockSec or 0) - IATestRunner._wallClockStart
	local entry = {
		ts = string.format("%.3f", elapsed),
		cat = category,
		evt = event,
	}
	if data ~= nil then
		for k, v in pairs(data) do
			entry[k] = v
		end
	end
	table.insert(IATestRunner._logLines, entry)

	-- Human-readable console line for the game log
	local dataStr = ""
	if data ~= nil then
		local parts = {}
		for k, v in pairs(data) do
			if type(v) == "boolean" then
				table.insert(parts, k .. "=" .. tostring(v))
			elseif type(v) == "number" then
				table.insert(parts, k .. "=" .. tostring(v))
			elseif type(v) == "string" then
				table.insert(parts, k .. "=" .. v)
			elseif type(v) == "table" then
				table.insert(parts, k .. "=[" .. tostring(#v) .. " items]")
			else
				table.insert(parts, k .. "=" .. tostring(v))
			end
		end
		dataStr = " " .. table.concat(parts, " ")
	end
	IAprintDebug("IATestRunner", string.format("[%s] %s/%s%s",
		entry.ts, category, event, dataStr))
end

--- Shortcut: emit a test-lifecycle event (begin, end, action, error, verdict).
function IATestRunner.emitTest(event, data)
	IATestRunner.emit("test", event, data)
end

--- Bridge from IAprintDebug: feed all mod debug output into the structured log.
--- Called by IAHelper.lua:IAprintDebug when a test is active.
--- @param methodName string  e.g. "IAConversation:playNextLine"
--- @param message    string  the debug message (conversation text, state info, etc.)
--- @param neighbour  table|nil
--- @param vehicle    table|nil
--- @param situation  table|nil
function IATestRunner.emitDebug(methodName, message, neighbour, vehicle, situation)
	if not IATestRunner._testActive then
		return
	end
	-- Skip noisy per-frame/mod-init debug to keep test logs lean.
	-- Also skip IATestRunner/IATestRegistry self-calls to prevent infinite
	-- recursion: emit() → IAprintDebug → emitDebug → emit() → …
	if methodName == "iaAddMapHotspotToMission"
		or methodName == "IANeighbour:ensureMapHotspotCreated"
		or methodName == "IATestRunner"
		or methodName == "IATestRegistry"
		or (methodName and methodName:match("updateFarmlands"))
		or (methodName and methodName:match("updateNeighbours"))
		or (methodName and methodName:match("getRandomVehicleByType"))
		or (methodName and methodName:match("GetVehiclesForSituation"))
		or (methodName and methodName:match("selectNewFieldwork"))
		or (methodName and methodName:match("collectOpenFieldwork"))
		or (methodName and methodName:match("validateScheduleEntry"))
		or (methodName and methodName:match("rebuildDailyFieldwork"))
		then
		return
	end
	local data = {}
	if message ~= nil and tostring(message) ~= "" then
		data.msg = tostring(message)
	end
	if neighbour ~= nil and type(neighbour) == "table" then
		data.neighbour = neighbour.name or tostring(neighbour.id or "?")
	end
	if vehicle ~= nil and type(vehicle) == "table" then
		data.vehicle = vehicle.uniqueId or vehicle.name or "?"
	end
	if situation ~= nil and type(situation) == "table" then
		data.situation = tostring(situation.id or "?")
	end
	IATestRunner.emit("debug", methodName, data)
end

-- ============================================================================
-- Test Lifecycle
-- ============================================================================

--- Queue of scenario names for iaTestRunAll (runs sequentially).
IATestRunner._runAllQueue = {}
--- Name of the current scenario in a run-all batch (nil when running standalone).
IATestRunner._runAllBatchId = nil
--- When true, buffering is active even without a named test (pre-capture mode).
IATestRunner._preCaptureActive = false

--- Start a new test run. Clears the log buffer and begins capturing.
--- @param name string  scenario name (must match a registered scenario)
--- @param keepBuffer boolean  when true, keep existing log lines (for pre-capture reuse)
function IATestRunner.beginTest(name, keepBuffer)
	if IATestRunner._testActive then
		IAprintDebug("IATestRunner", "WARNING: test '" .. IATestRunner._testName .. "' is already running; aborting it")
		IATestRunner.abortTest("replaced by new test")
	end

	IATestRunner._testActive = true
	IATestRunner._testName = name
	if not keepBuffer then
		IATestRunner._logLines = {}
	end
	IATestRunner._wallClockStart = IANeighbours._wallClockSec or 0
	IATestRunner._pendingActions = {}
	IATestRunner._actionIndex = 0
	IATestRunner._waitFramesRemaining = 0
	IATestRunner._waitWallClockUntil = nil
	IATestRunner._waitLogEventUntil = nil
	IATestRunner._waitLogEventCategory = nil
	IATestRunner._waitLogEventEvent = nil
	IATestRunner._waitGameTimeTarget = nil
	IATestRunner._waitConditionFn = nil
	IATestRunner._waitConditionLabel = nil
	IATestRunner._anyAssertionFailed = false
	IATestRunner._situationCompleteObserved = false

	if not IATestRunner._updateHookInstalled then
		IATestRunner._updateHookInstalled = true
	end

	IATestRunner.emitTest("begin", { name = name })
end

--- End the current test normally. Saves the log to modSettings.
--- @param verdict string  "PASS" or "FAIL" (for the saved report)
--- @param reason  string|nil  brief explanation
function IATestRunner.endTest(verdict, reason)
	if not IATestRunner._testActive then
		return
	end
	IATestRunner.emitTest("end", {
		verdict = verdict or "UNKNOWN",
		reason = reason,
		logLineCount = #IATestRunner._logLines,
	})
	local ok, err = pcall(function() IATestRunner.saveLogToFile() end)
    if not ok then
        IAprintDebug("IATestRunner", "saveLogToFile ERROR: " .. tostring(err))
        -- Fallback: inline console logging
        IAprintDebug("IATestRunner", "LOG_BEGIN " .. (IATestRunner._testName or "unknown"))
        for _, entry in ipairs(IATestRunner._logLines) do
            IAprintDebug("IATestRunner", " LOG_LINE " .. IAHelper_tableToJson(entry))
        end
        IAprintDebug("IATestRunner", "LOG_END")
    end

	-- Safety: always restore timeScale even if the normal delta-wait path was skipped
	if IATestRunner._waitGameTimeOriginalScale ~= nil and g_currentMission and g_currentMission.missionInfo then
		g_currentMission.missionInfo.timeScale = IATestRunner._waitGameTimeOriginalScale
		IATestRunner.emit("time", "scale_restored", { timeScale = IATestRunner._waitGameTimeOriginalScale })
	end

	IATestRunner._testActive = false
	IATestRunner._testName = nil
	IATestRunner._testDescription = nil
	IATestRunner._currentScenario = nil
	IATestRunner._pendingActions = {}
	IATestRunner._actionIndex = 0
	IATestRunner._waitFramesRemaining = 0
	IATestRunner._waitWallClockUntil = nil
	IATestRunner._waitGameTimeTarget = nil
	IATestRunner._waitGameTimeDeltaMinutes = nil
	IATestRunner._waitGameTimeOriginalScale = nil
	IATestRunner._waitConditionFn = nil
	IATestRunner._waitConditionLabel = nil
	IATestRunner._anyAssertionFailed = false
	IATestRunner._situationCompleteObserved = false

	-- If running a batch (iaTestRunAll), run cleanup then start the next scenario
	if IATestRunner._runAllQueue ~= nil and #IATestRunner._runAllQueue > 0 then
		IATestRunner._runScenarioCleanup()
		IATestRunner.cleanupTestState()
		local nextName = table.remove(IATestRunner._runAllQueue, 1)
		IAprintDebug("IATestRunner", "RUN-ALL next: " .. nextName .. " (" .. tostring(#IATestRunner._runAllQueue) .. " remaining)")
		IATestRunner._runScenarioInternal(nextName, false)
	-- If auto-run is active, chain to the next test (with inter-test delay)
	elseif IATestRunner._autoRunActive then
		IATestRunner._runScenarioCleanup()
		IATestRunner.cleanupTestState()
		IATestRunner._onAutoRunTestEnded()
	end
end

--- Run the current scenario's cleanup block (if defined).
--- Actions are executed directly via _executeAction, best-effort.
function IATestRunner._runScenarioCleanup()
	local scenario = IATestRunner._currentScenario
	if scenario == nil or scenario.cleanup == nil then
		return
	end
	IATestRunner.emit("test", "cleanup_begin", { scenario = scenario.name })
	for _, action in ipairs(scenario.cleanup) do
		if action ~= nil and action.type ~= nil then
			pcall(function() IATestRunner._executeAction(action) end)
		end
	end
	IATestRunner.emit("test", "cleanup_end", { scenario = scenario.name })
end

--- Reset mod/game state between batch tests (dialogs, phone, timeScale, etc.).
function IATestRunner.cleanupTestState()
	-- Close any open GUI dialog (phone, conversation, etc.)
	if g_gui ~= nil and g_gui.currentDialog ~= nil then
		pcall(function() g_gui:closeDialog(g_gui.currentDialog) end)
	end

	-- Clear phone state
	if IANeighbours ~= nil then
		if IANeighbours._incomingPhonePayload ~= nil then
			pcall(function() IANeighbours.stopIncomingCallRingSound() end)
			pcall(function() IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.PHONE_DIALOG_CLOSED) end)
		end
		IANeighbours.incomingPhoneRingDialogOpen = false
		IANeighbours._activeConversationKind = nil
		if IANeighbours.activeStandalonePhoneConversation ~= nil then
			pcall(function() IANeighbours.onStandalonePhoneConversationClosed(IANeighbours.activeStandalonePhoneConversation) end)
		end
		IANeighbours._globalInboundPhoneCooldownUntilWallClockSec = 0
		pcall(function() IANeighbours:disableConversationKeybind() end)
	end

	-- Restore default timeScale
	if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
		g_currentMission.missionInfo.timeScale = 5
	end

	IATestRunner._situationCompleteObserved = false

	-- Reset mission offer mode to default (realistic) so phone tests are not blocked
	if IASettings ~= nil then
		IASettings.missionOfferModeIndex = IASettings.MISSION_OFFER_MODE_DEFAULT_INDEX  -- 2 = realistic
	end

	-- Reset forced outsource type override so subsequent tests use normal random selection
	IATestRunner.forceOutsourceType = nil

	IATestRunner.emit("test", "cleanup", {})
end

--- Abort the test due to error or timeout.
function IATestRunner.abortTest(reason)
	if not IATestRunner._testActive then
		return
	end
	IATestRunner.emitTest("abort", { reason = reason or "unknown" })
	IATestRunner.endTest("ABORT", reason)
end

-- ============================================================================
-- Log Persistence
-- ============================================================================

--- Build the modSettings/FoS_tests directory path.
function IATestRunner.getTestOutputDirectory()
	local base = (g_modSettingsDirectory or "") .. IATestRunner.TEST_OUTPUT_SUBDIR .. "/"
	return base
end

--- Write the current structured log as an XML file to modSettings/FoS_tests/.
--- Uses FS25's createXMLFile/saveXMLFile/delete API (same pattern as IASettings.save).
function IATestRunner.saveLogToFile()
    if #IATestRunner._logLines == 0 then
        IAprintDebug("IATestRunner", "saveLogToFile: no log lines to save")
        return nil
    end

    local name = IATestRunner._testName or "unnamed"
    local safeName = string.gsub(name, "[^%w_%-]", "_")
    local wallSec = math.floor(IANeighbours._wallClockSec or 0)
    local ts = string.format("%d", wallSec)
    local filename = string.format("FoS_test_%s_%s.xml", safeName, ts)

    -- Build modSettings/FoS_tests/ path (ensure folder exists)
    local dir = IATestRunner.getTestOutputDirectory()
    if folderExists ~= nil and not folderExists(dir) and createFolder ~= nil then
        createFolder(dir)
    end
    local fullPath = dir .. filename

    -- Create XML file at the target path (matching IASettings.save pattern)
    local xmlFile = createXMLFile("FoS_test_log", fullPath, "testLog")
    if xmlFile == nil or xmlFile == 0 then
        -- Fallback: inline console logging
        IAprintDebug("IATestRunner", "LOG_BEGIN " .. filename)
        for _, entry in ipairs(IATestRunner._logLines) do
            IAprintDebug("IATestRunner", "LOG_LINE " .. IAHelper_tableToJson(entry))
        end
        IAprintDebug("IATestRunner", "LOG_END " .. filename)
        return nil
    end

    -- Root attributes: name, description, verdict, timestamp — glanceable summary
    setXMLString(xmlFile, "testLog#name", IATestRunner._testName or "unnamed")
    if IATestRunner._testDescription ~= nil then
        setXMLString(xmlFile, "testLog#description", IATestRunner._testDescription)
    end
    -- Pull verdict from the last log entry (test/end or test/abort)
    local lastEntry = IATestRunner._logLines[#IATestRunner._logLines]
    if lastEntry ~= nil and lastEntry.cat == "test" and (lastEntry.evt == "end" or lastEntry.evt == "abort") then
        setXMLString(xmlFile, "testLog#verdict", lastEntry.verdict or "UNKNOWN")
        if lastEntry.reason ~= nil then
            setXMLString(xmlFile, "testLog#reason", lastEntry.reason)
        end
    end
    setXMLString(xmlFile, "testLog#timestamp", ts)
    setXMLInt(xmlFile, "testLog#entryCount", #IATestRunner._logLines)

    for i, entry in ipairs(IATestRunner._logLines) do
        local idx = i - 1  -- FS25 XML is 0-indexed
        local base = "testLog.entry(" .. idx .. ")"
        setXMLString(xmlFile, base .. "#ts", entry.ts or "")
        setXMLString(xmlFile, base .. "#cat", entry.cat or "")
        setXMLString(xmlFile, base .. "#evt", entry.evt or "")

        for k, v in pairs(entry) do
            if k ~= "ts" and k ~= "cat" and k ~= "evt" then
                if type(v) == "boolean" then
                    setXMLBool(xmlFile, base .. "#" .. k, v)
                elseif type(v) == "number" then
                    if v == math.floor(v) and v > -2147483648 and v < 2147483647 then
                        setXMLInt(xmlFile, base .. "#" .. k, v)
                    else
                        setXMLFloat(xmlFile, base .. "#" .. k, v)
                    end
                else
                    setXMLString(xmlFile, base .. "#" .. k, tostring(v))
                end
            end
        end
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)

    print("[FOS_TEST_XML_PATH] " .. fullPath)
    IAprintDebug("IATestRunner", "XML_SAVED " .. fullPath .. " (" .. tostring(#IATestRunner._logLines) .. " entries)")
    return fullPath
end

-- ============================================================================
-- Time Helpers
-- ============================================================================

--- Resolve current in-game time components.
function IATestRunner.getCurrentGameTime()
	local h = g_currentMission and g_currentMission.environment and g_currentMission.environment.currentHour or 0
	local m = g_currentMission and g_currentMission.environment and g_currentMission.environment.currentMinute or 0
	local month, dayIn = 1, 1
	if type(getEnvironmentMonth1to12) == "function" then
		month = getEnvironmentMonth1to12()
	end
	if type(getEnvironmentDayOfPeriod) == "function" then
		dayIn = getEnvironmentDayOfPeriod()
	end
	return h, m, month, dayIn
end

--- Set the in-game time (hour, minute, month, dayInPeriod) directly.
function IATestRunner.setGameTime(hour, minute, month, dayInPeriod)
	if g_currentMission == nil or g_currentMission.environment == nil then
		return false
	end
	local env = g_currentMission.environment

	if month ~= nil and dayInPeriod ~= nil then
		-- Use day/time setter if available; fall back to direct field writes
		if type(env.setDayTime) == "function" then
			env:setDayTime(dayInPeriod or 1, hour or 0, minute or 0)
		else
			if env.currentDay ~= nil then
				-- currentDay is zero-based day-of-period
				env.currentDay = (dayInPeriod or 1) - 1
			end
			env.currentHour = hour or 0
			env.currentMinute = minute or 0
		end

		-- Month: try setMonth if available
		if type(env.setMonth) == "function" then
			env:setMonth(month)
		elseif env.currentMonotonicDay ~= nil and type(getDaysPerPeriod) == "function" then
			-- Approximate: compute monotonic day offset. This is imprecise but works
			-- for advancing within the same period.
			local daysPerPeriod = getDaysPerPeriod()
			if daysPerPeriod ~= nil and daysPerPeriod > 0 then
				-- We don't set the month directly here; this is a best-effort path
			end
		end
	else
		if hour ~= nil then
			env.currentHour = hour
		end
		if minute ~= nil then
			env.currentMinute = minute
		end
	end

	-- Force the environment to recalculate daytime string etc.
	if type(env.onTimeChanged) == "function" then
		pcall(function() env:onTimeChanged() end)
	end

	IATestRunner.emit("time", "set", {
		hour = hour,
		minute = minute,
		month = month,
		dayInPeriod = dayInPeriod,
	})
	return true
end

--- Set the game time scale directly.
function IATestRunner.setTimeScale(scale)
	if g_currentMission == nil or g_currentMission.missionInfo == nil then
		return false
	end
	g_currentMission.missionInfo.timeScale = (scale or 1)
	IATestRunner.emit("time", "scale_set", { timeScale = scale })
	return true
end

--- Compute total in-game minutes from hour/minute.
local function gameMinutesFromHM(h, m)
	return (h or 0) * 60 + (m or 0)
end

--- Compute total in-game minutes between two times, handling day wraparound.
local function gameMinutesBetween(h1, m1, h2, m2)
	local a = gameMinutesFromHM(h1, m1)
	local b = gameMinutesFromHM(h2, m2)
	if b >= a then
		return b - a
	end
	return (24 * 60 - a) + b
end

-- ============================================================================
-- Per-Frame Update (called from IANeighbours:update)
-- ============================================================================

--- Called every frame when a test is active. Advances the action queue.
--- @param dt number  frame delta in milliseconds
function IATestRunner.update(dt)
	-- Auto-run inter-test delay: when a test finished and we're waiting to start
	-- the next one, count down the delay here. This runs even when _testActive is false.
	if IATestRunner._autoRunPendingNext then
		if IATestRunner._autoRunInterTestDelaySec == nil then
			IATestRunner._autoRunInterTestDelaySec = (IANeighbours._wallClockSec or 0) + 2
		end
		if (IANeighbours._wallClockSec or 0) >= IATestRunner._autoRunInterTestDelaySec then
			IATestRunner._autoRunPendingNext = false
			IATestRunner._autoRunInterTestDelaySec = nil
			IATestRunner._runNextAutoTest()
		end
		-- Don't process normal update while waiting between auto-run tests
		return
	end

	if not IATestRunner._testActive then
		return
	end

	-- Timeout guard
	local elapsed = (IANeighbours._wallClockSec or 0) - IATestRunner._wallClockStart
	if elapsed > IATestRunner.TEST_TIMEOUT_SEC then
		IATestRunner.abortTest("timeout after " .. string.format("%.1f", elapsed) .. "s")
		return
	end

	-- Process frame-based waits
	if IATestRunner._waitFramesRemaining > 0 then
		IATestRunner._waitFramesRemaining = IATestRunner._waitFramesRemaining - 1
		return
	end

	-- Process log-event polling
	if IATestRunner._waitLogEventUntil ~= nil then
		local found = false
		for _, entry in ipairs(IATestRunner._logLines) do
			if entry.cat == IATestRunner._waitLogEventCategory and entry.evt == IATestRunner._waitLogEventEvent then
				found = true
				break
			end
		end
		if found then
			IATestRunner.emit("time", "log_event_found", {
				category = IATestRunner._waitLogEventCategory,
				event = IATestRunner._waitLogEventEvent,
			})
			IATestRunner._waitLogEventUntil = nil
			IATestRunner._waitLogEventCategory = nil
			IATestRunner._waitLogEventEvent = nil
			IATestRunner._advanceActionQueue()
			return
		end
		if (IANeighbours._wallClockSec or 0) >= IATestRunner._waitLogEventUntil then
			IATestRunner.emit("time", "log_event_timeout", {
				category = IATestRunner._waitLogEventCategory,
				event = IATestRunner._waitLogEventEvent,
			})
			IATestRunner._waitLogEventUntil = nil
			IATestRunner._waitLogEventCategory = nil
			IATestRunner._waitLogEventEvent = nil
			IATestRunner._advanceActionQueue()
			return
		end
		return  -- still waiting
	end

	-- Process wall-clock waits
	if IATestRunner._waitWallClockUntil ~= nil then
		if (IANeighbours._wallClockSec or 0) < IATestRunner._waitWallClockUntil then
			return
		end
		IATestRunner._waitWallClockUntil = nil
		IATestRunner._advanceActionQueue()
		return
	end

	-- Process game-time delta waits (advanceGameTimeTo: advance at high speed, count down minutes)
	if IATestRunner._waitGameTimeDeltaMinutes ~= nil then
		local scale = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale) or 1
		local gameDtMinutes = (dt / 1000) * scale / 3600 * 60
		IATestRunner._waitGameTimeDeltaMinutes = IATestRunner._waitGameTimeDeltaMinutes - gameDtMinutes
		if IATestRunner._waitGameTimeDeltaMinutes <= 0 then
			if IATestRunner._waitGameTimeOriginalScale ~= nil and g_currentMission and g_currentMission.missionInfo then
				g_currentMission.missionInfo.timeScale = IATestRunner._waitGameTimeOriginalScale
			end
			IATestRunner._waitGameTimeDeltaMinutes = nil
			IATestRunner._waitGameTimeOriginalScale = nil
			-- Check if transitioning from natural-contract-call advance to ring-wait phase
			if IATestRunner._natCallPhase == "advancing" then
				IATestRunner._natCallPhase = "waiting"
				IATestRunner._natCallWaitStart = IANeighbours._wallClockSec or 0
				IATestRunner._waitConditionFn = function()
					return IANeighbours._incomingPhonePayload ~= nil
				end
				IATestRunner._waitConditionLabel = "natural contract phone ring"
			else
				IATestRunner._advanceActionQueue()
			end
		end
		return
	end

	-- Process game-time waits (advance time each frame by dt)
	if IATestRunner._waitGameTimeTarget ~= nil then
		local h, m = IATestRunner.getCurrentGameTime()
		local nowMin = gameMinutesFromHM(h, m)
		local targetMin = IATestRunner._waitGameTimeTarget
		if nowMin < targetMin then
			-- Advance game time proportionally to timeScale
			local scale = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale) or 1
			local gameDt = (dt / 1000) * scale / 3600 -- fraction of game-hour per frame
			local advMin = gameDt * 60
			if g_currentMission and g_currentMission.environment then
				local env = g_currentMission.environment
				env.currentMinute = (env.currentMinute or m) + advMin
				while env.currentMinute >= 60 do
					env.currentMinute = env.currentMinute - 60
					env.currentHour = (env.currentHour or h) + 1
					if env.currentHour >= 24 then
						env.currentHour = env.currentHour - 24
					end
				end
			end
			return
		end
		IATestRunner._waitGameTimeTarget = nil
		IATestRunner._advanceActionQueue()
		return
	end

	-- Process condition-based waits
	if IATestRunner._waitConditionFn ~= nil then
		local ok, result = pcall(IATestRunner._waitConditionFn)
		if ok and result then
			IATestRunner.emit("wait", "condition_met", { label = IATestRunner._waitConditionLabel })
			IATestRunner._waitConditionFn = nil
			IATestRunner._waitConditionLabel = nil
			-- If this was a natural contract call ring wait, emit the success event and clean up
			if IATestRunner._natCallPhase == "waiting" then
				IATestRunner.emit("phone", "natural_ring_happened", { neighbour = IATestRunner._natCallNeighbourName })
				IATestRunner._natCallPhase = nil
				IATestRunner._natCallNeighbourName = nil
				IATestRunner._natCallTimeoutSec = nil
				IATestRunner._natCallWaitStart = nil
				-- Clear payload so it doesn't interfere with subsequent actions
				if IANeighbours ~= nil and type(IANeighbours.clearPendingIncomingPhoneOffer) == "function" then
					IANeighbours.clearPendingIncomingPhoneOffer("test_cleanup")
				end
			end
			IATestRunner._advanceActionQueue()
		else
			-- Check timeout for natural contract call ring wait
			if IATestRunner._natCallPhase == "waiting" and IATestRunner._natCallTimeoutSec ~= nil then
				local elapsed = (IANeighbours._wallClockSec or 0) - (IATestRunner._natCallWaitStart or 0)
				if elapsed >= IATestRunner._natCallTimeoutSec then
					IATestRunner.emit("phone", "natural_ring_blocked", {
						neighbour = IATestRunner._natCallNeighbourName,
						reason = "timeout after " .. string.format("%.1f", elapsed) .. "s",
					})
					IATestRunner._natCallPhase = nil
					IATestRunner._natCallNeighbourName = nil
					IATestRunner._natCallTimeoutSec = nil
					IATestRunner._natCallWaitStart = nil
					IATestRunner._waitConditionFn = nil
					IATestRunner._waitConditionLabel = nil
					IATestRunner._advanceActionQueue()
				end
			end
		end
		return
	end

	-- If no wait is active, try advancing
	if IATestRunner._waitFramesRemaining <= 0
		and IATestRunner._waitWallClockUntil == nil
		and IATestRunner._waitGameTimeTarget == nil
		and IATestRunner._waitConditionFn == nil then
		IATestRunner._advanceActionQueue()
	end
end

--- Execute the next action in the queue.
function IATestRunner._advanceActionQueue()
	local actions = IATestRunner._pendingActions
	if actions == nil or IATestRunner._actionIndex >= #actions then
		-- All actions consumed — test ends naturally
		local finalVerdict = IATestRunner._anyAssertionFailed and "FAIL" or "PASS"
	local finalReason = IATestRunner._anyAssertionFailed and "assertion(s) failed" or "all actions completed"
	IATestRunner.endTest(finalVerdict, finalReason)
		return
	end

	IATestRunner._actionIndex = IATestRunner._actionIndex + 1
	local action = actions[IATestRunner._actionIndex]

	if action == nil then
	local finalVerdict = IATestRunner._anyAssertionFailed and "FAIL" or "PASS"
	local finalReason = IATestRunner._anyAssertionFailed and "assertion(s) failed" or "all actions completed"
	IATestRunner.endTest(finalVerdict, finalReason)
		return
	end

	IATestRunner.emit("test", "action_begin", {
		index = IATestRunner._actionIndex,
		total = #actions,
		type = action.type,
	})

	local ok, err = pcall(function()
		IATestRunner._executeAction(action)
	end)

	if not ok then
		IATestRunner.emit("test", "action_error", {
			index = IATestRunner._actionIndex,
			type = action.type,
			error = tostring(err),
		})
		IATestRunner.abortTest("action error at index " .. tostring(IATestRunner._actionIndex) .. ": " .. tostring(err))
	end
end

-- ============================================================================
-- Action Execution
-- ============================================================================

function IATestRunner._executeAction(action)
	local atype = action.type

	-- ── Time Control ──────────────────────────────────────────────

	if atype == "setTime" then
		-- Direct writes to env.currentHour are ignored by the engine.
		-- Treat like advanceGameTimeTo with forward wrap-around.
		local th, tm = action.hour, action.minute
		if th == nil then return end
		local h, m = IATestRunner.getCurrentGameTime()
		local nowMin = gameMinutesFromHM(h, m)
		local targetMin = gameMinutesFromHM(th, tm or 0)
		local deltaMin = targetMin - nowMin
		if deltaMin < 0 then deltaMin = deltaMin + 24 * 60 end
		if deltaMin <= 0 then
			IATestRunner.emit("time", "already_at", { hour = th, minute = tm })
			return
		end
		local scale = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale) or 5
		local boost = action.timeScale or 499
		IATestRunner._waitGameTimeOriginalScale = scale
		IATestRunner.setTimeScale(boost)
		IATestRunner._waitGameTimeDeltaMinutes = deltaMin
		IATestRunner.emit("time", "advancing_to", { targetHour = th, targetMinute = tm, currentHour = h, currentMinute = m, deltaGameMinutes = math.floor(deltaMin + 0.5), timeScale = boost })

	elseif atype == "setTimeScale" then
		IATestRunner.setTimeScale(action.scale or 1)

	elseif atype == "advanceGameTimeTo" then
		-- Advance to target hour/minute, wrapping to next day if already past.
		-- Uses action.timeScale (default 499, just below the 500 anti-sleep guard) so
		-- handleActiveSituation & schedule rebuilds remain active during the approach.
		local th, tm = action.hour, action.minute
		if th == nil then return end
		local h, m = IATestRunner.getCurrentGameTime()
		local nowMin = gameMinutesFromHM(h, m)
		local targetMin = gameMinutesFromHM(th, tm or 0)
		local deltaMin = targetMin - nowMin
		if deltaMin < 0 then deltaMin = deltaMin + 24 * 60 end
		if deltaMin <= 0 then
			IATestRunner.emit("time", "already_at", { hour = th, minute = tm })
			return
		end
		local scale = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale) or 5
		local boost = action.timeScale or 499
		IATestRunner._waitGameTimeOriginalScale = scale
		IATestRunner.setTimeScale(boost)
		IATestRunner._waitGameTimeDeltaMinutes = deltaMin
		IATestRunner.emit("time", "advancing_to", { targetHour = th, targetMinute = tm, currentHour = h, currentMinute = m, deltaGameMinutes = math.floor(deltaMin + 0.5) })

	elseif atype == "waitGameMinutes" then
		local h, m = IATestRunner.getCurrentGameTime()
		local targetMin = gameMinutesFromHM(h, m) + (action.minutes or 1)
		-- Normalize to 0..1439
		targetMin = targetMin % (24 * 60)
		IATestRunner._waitGameTimeTarget = targetMin
		IATestRunner.emit("time", "wait_game_minutes", { minutes = action.minutes })

	elseif atype == "waitGameHours" then
		local h, m = IATestRunner.getCurrentGameTime()
		local targetMin = gameMinutesFromHM(h, m) + ((action.hours or 1) * 60)
		targetMin = targetMin % (24 * 60)
		IATestRunner._waitGameTimeTarget = targetMin
		IATestRunner.emit("time", "wait_game_hours", { hours = action.hours })

	elseif atype == "waitWallClock" then
		IATestRunner._waitWallClockUntil = (IANeighbours._wallClockSec or 0) + (action.seconds or 1)
		IATestRunner.emit("time", "wait_wall_clock", { seconds = action.seconds })

	elseif atype == "waitFrames" then
		IATestRunner._waitFramesRemaining = action.frames or 1
		IATestRunner.emit("time", "wait_frames", { frames = action.frames })

	elseif atype == "waitForLogEvent" then
		-- Poll the log buffer for a matching category+event within a timeout.
		-- Uses wall-clock seconds; falls back to 15s if no timeout given.
		local timeout = action.timeout or 15
		IATestRunner._waitLogEventUntil = (IANeighbours._wallClockSec or 0) + timeout
		IATestRunner._waitLogEventCategory = action.category
		IATestRunner._waitLogEventEvent = action.event
		IATestRunner.emit("time", "wait_log_event", {
			category = action.category,
			event = action.event,
			timeout = timeout,
		})

	-- ── Condition Waits ──────────────────────────────────────────

	elseif atype == "waitForNeighbourSituation" then
		IATestRunner._waitConditionFn = function()
			for _, n in pairs(IANeighbours.neighbours or {}) do
				if n ~= nil and n.initialized and n.activeSituation ~= nil then
					return true
				end
			end
			return false
		end
		IATestRunner._waitConditionLabel = "any neighbour gets active situation"

	elseif atype == "waitForScheduleRebuild" then
		if IATestRunner._scheduleRebuildObserved then
			-- Rebuild already observed (e.g., during a preceding advanceGameTimeTo action).
			-- Don't reset the flag - just pass through immediately.
			IATestRunner.emit("schedule", "rebuild_already_observed", {})
			ok = true
		else
			-- Set a flag that gets checked in the emission hook
			IATestRunner._scheduleRebuildObserved = false
			IATestRunner._waitConditionFn = function()
				return IATestRunner._scheduleRebuildObserved == true
			end
			IATestRunner._waitConditionLabel = "schedule rebuild observed"
		end

	elseif atype == "waitForSituationComplete" then
		-- If a completion already happened before this action started
		-- (e.g. during a preceding waitWallClock or advanceGameTimeTo),
		-- skip the wait and proceed immediately.
		if IATestRunner._situationCompleteObserved then
			IATestRunner.emit("wait", "condition_already_met", { label = "situation complete (already observed)" })
			return
		end
		local targetNeighbourId = action.neighbourId or action.neighbourName
		IATestRunner._situationCompleteObserved = false
		-- Snapshot the currently-active situation ID so we detect when it changes.
		-- This handles the race where handleActiveSituation deletes the old
		-- situation and creates a new one in the same game5Seconds tick, leaving
		-- activeSituation never nil across frames.
		local initialSituationId = nil
		if targetNeighbourId ~= nil then
			local n = IANeighbours:resolveNeighbourForConsoleToken(targetNeighbourId)
			if n ~= nil and n.activeSituation ~= nil then
				initialSituationId = n.activeSituation.id
			end
		end
		-- Baseline of _iaSituationJustCompleted per neighbour for the "any" branch,
		-- so we only fire on new completions, not stale flags from prior tests.
		local initialCompletedFlags = {}
		if targetNeighbourId == nil then
			for _, n in pairs(IANeighbours.neighbours or {}) do
				if n ~= nil and n.initialized then
					initialCompletedFlags[n.id or n.name] = n._iaSituationJustCompleted or false
				end
			end
		end
		IATestRunner._waitConditionFn = function()
			if IATestRunner._situationCompleteObserved then
				return true
			end
			if targetNeighbourId ~= nil then
				local n = IANeighbours:resolveNeighbourForConsoleToken(targetNeighbourId)
				if n ~= nil then
					local currentId = (n.activeSituation ~= nil and n.activeSituation.id) or nil
					if currentId ~= initialSituationId then
						IATestRunner._situationCompleteObserved = true
						return true
					end
				end
			else
				-- Any neighbour whose _iaSituationJustCompleted just transitioned to true.
				for _, n in pairs(IANeighbours.neighbours or {}) do
					if n ~= nil and n.initialized then
						local wasCompleted = initialCompletedFlags[n.id or n.name] or false
						local isCompleted = n._iaSituationJustCompleted or false
						if isCompleted and not wasCompleted then
							IATestRunner._situationCompleteObserved = true
							return true
						end
					end
				end
			end
			return false
		end
		IATestRunner._waitConditionLabel = "situation complete (neighbour=" .. tostring(targetNeighbourId or "any") .. ")"

	elseif atype == "waitForNearbySituation" then
		IATestRunner._waitConditionFn = function()
			return IANeighbours.nearbySituation ~= nil
		end
		IATestRunner._waitConditionLabel = "nearby situation detected (player close enough to talk)"

	elseif atype == "waitForPhoneRing" then
		IATestRunner._waitConditionFn = function()
			return IANeighbours._incomingPhonePayload ~= nil
		end
		IATestRunner._waitConditionLabel = "incoming phone ring pending"

	elseif atype == "waitForNaturalContractCall" then
		-- Find a farmer neighbour with contract-enabled schedule tasks
		-- and advance time to their callPlayerHour/Minute, then wait for the ring.
		local targetN = nil
		local callHour, callMinute = nil, nil
		local nid = action.neighbourId or action.neighbourName
		if nid ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nid)
			if targetN ~= nil and targetN.callPlayerHour ~= nil then
				callHour = targetN.callPlayerHour
				callMinute = targetN.callPlayerMinute or 0
			end
		else
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.fieldworkScheduleTasks ~= nil and nb.callPlayerHour ~= nil then
					local hasContract = false
					for _, row in ipairs(nb.fieldworkScheduleTasks) do
						if row ~= nil and row.contractEnabled == true then
							hasContract = true
							break
						end
					end
					if hasContract then
						targetN = nb
						callHour = nb.callPlayerHour
						callMinute = nb.callPlayerMinute or 0
						break
					end
				end
			end
		end
		if targetN == nil or callHour == nil then
			IATestRunner.emit("phone", "natural_ring_blocked", { reason = "no neighbour with contract tasks found" })
			return
		end
		-- Compute game-time delta to the neighbour's call hour/minute
		local h, m = IATestRunner.getCurrentGameTime()
		local nowMin = gameMinutesFromHM(h, m)
		local targetMin = gameMinutesFromHM(callHour, callMinute)
		local deltaMin = targetMin - nowMin
		if deltaMin < 0 then deltaMin = deltaMin + 24 * 60 end
		IATestRunner.emit("phone", "waiting_for_natural_call", {
			neighbour = targetN.name,
			callHour = callHour,
			callMinute = callMinute,
			currentHour = h,
			currentMinute = m,
			deltaGameMinutes = math.floor(deltaMin + 0.5),
		})
		-- Store phase info for the transition after time advance
		IATestRunner._natCallNeighbourName = targetN.name
		IATestRunner._natCallPhase = "advancing"
		IATestRunner._natCallTimeoutSec = action.timeoutSec or 60
		-- Advance to call time at 60x (allows game loop to process contract triggers naturally)
		local scale = (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale) or 5
		local boost = action.timeScale or 60
		IATestRunner._waitGameTimeOriginalScale = scale
		IATestRunner.setTimeScale(boost)
		IATestRunner._waitGameTimeDeltaMinutes = deltaMin

	elseif atype == "waitForPhoneSessionEnd" then
		IATestRunner._waitConditionFn = function()
			return not IANeighbours.isIncomingPhoneSessionActive()
				and IANeighbours._incomingPhonePayload == nil
		end
		IATestRunner._waitConditionLabel = "phone session ended"

	-- ── State Manipulation ────────────────────────────────────────

	elseif atype == "forceSituation" then
		local nToken = action.neighbourId or action.neighbourName or "1"
		local sitId = action.situationId or "4"
		local n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		if n == nil then
			IATestRunner.emit("test", "action_error", { error = "neighbour not found: " .. tostring(nToken) })
		else
			local ok, err = n:forceNewSituation(sitId)
			IATestRunner.emit("situation", "force", {
				neighbour = n.name,
				situationId = sitId,
				ok = ok,
				error = err,
			})
		end

	elseif atype == "forceAllNeighboursSituation" then
		local sitId = action.situationId or "4"
		local successCount = 0
		local failCount = 0
		local errors = {}
		local totalCount = 0
		for _, n in pairs(IANeighbours.neighbours or {}) do
			if n ~= nil and n.enabled and n.initialized then
				totalCount = totalCount + 1
				local ok, err = n:forceNewSituation(sitId, true)
				if ok then
					successCount = successCount + 1
					IATestRunner.emit("test", "force_neighbour_situation", {
						neighbour = n.name,
						neighbourId = n.id,
						situationId = sitId,
						result = "success",
					})
				else
					failCount = failCount + 1
					table.insert(errors, tostring(n.name) .. ": " .. tostring(err))
					IATestRunner.emit("test", "force_neighbour_situation", {
						neighbour = n.name,
						neighbourId = n.id,
						situationId = sitId,
						result = "failed",
						error = tostring(err),
					})
				end
			end
		end
		IATestRunner.emit("test", "force_all_situations_result", {
			total = totalCount,
			success = successCount,
			failed = failCount,
			errors = #errors > 0 and table.concat(errors, "; ") or nil,
		})

	elseif atype == "waitForAllNpcsReady" then
		local timeout = action.timeoutSeconds or 60
		local startWallClock = IANeighbours._wallClockSec or 0
		IATestRunner._waitConditionFn = function()
			local now = IANeighbours._wallClockSec or 0
			if (now - startWallClock) > timeout then
				IATestRunner.emit("wait", "npcs_ready_timeout", {
					timeoutSeconds = timeout,
					elapsed = now - startWallClock,
				})
				return true
			end
			local neighbours = IANeighbours.neighbours or {}
			local allReady = true
			local readyCount = 0
			local waitCount = 0
			for _, n in ipairs(neighbours) do
				if n ~= nil and n.enabled and n.initialized and n.activeSituation ~= nil then
					local vis = n.activeSituation.characterVisibility
					local shouldBeVisible = (vis == "yes" or n.activeSituation.npcVisibleWhilePaused == true)
					if shouldBeVisible then
						local isActive = n.npcInstance ~= nil and n.npcInstance.isActive
						local styleReady = n.humanModelStyleReady or false
						if isActive and styleReady then
							readyCount = readyCount + 1
						else
							waitCount = waitCount + 1
							allReady = false
						end
					end
				end
			end
			if not allReady then
				IATestRunner.emit("wait", "npcs_not_ready", {
					ready = readyCount,
					waiting = waitCount,
				})
			end
			return allReady
		end
		IATestRunner._waitConditionLabel = "all neighbours NPCs visible and style-ready"

	elseif atype == "forceFieldwork" then
		local nToken = action.neighbourId or action.neighbourName or "1"
		local fieldworkType = action.fieldworkType  -- optional: e.g. "grass_mowing", "seed", "lime"
		local n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		if n == nil then
			IATestRunner.emit("test", "action_error", { error = "neighbour not found: " .. tostring(nToken) })
		elseif fieldworkType ~= nil then
			-- Inject a specific fieldwork type as a contract-enabled row into the schedule
			-- This bypasses the random schedule selection to force a specific contract type
			local helper = IANeighbours.gameLoopHelper
			if helper == nil then
				IATestRunner.emit("test", "action_error", { error = "no gameLoopHelper" })
			else
				-- Ensure schedule is initialized first
				if n.fieldworkScheduleTasks == nil then
					n.fieldworkScheduleTasks = {}
				end
				if n.fieldworkScheduleYear == nil or n.fieldworkScheduleMonth == nil then
					-- Set schedule date to current game time
					if g_currentMission ~= nil and g_currentMission.environment ~= nil then
						local dayTime = g_currentMission.environment:getDayTime()
						if g_currentMission.environment:getDayTime() ~= nil then
							-- Just use some reasonable defaults
							n.fieldworkScheduleYear = 2026
							n.fieldworkScheduleMonth = 4
							n.fieldworkScheduleDayInPeriod = 1
						end
					end
				end
				
				-- Find the matching situation config
				local config = nil
				local configId = nil
				local configs = helper.situationConfigs or helper.iaFieldworkSituationConfigs or {}
				if #configs == 0 and IANeighbours.situationConfigs ~= nil then
					configs = IANeighbours.situationConfigs
				end
				-- Also try helper.iaSituationConfigs
				if #configs == 0 and helper.iaSituationConfigs ~= nil then
					configs = helper.iaSituationConfigs
				end
				local fwLower = string.lower(tostring(fieldworkType))
				for _, cfg in ipairs(configs) do
					if cfg ~= nil and cfg.fieldwork ~= nil and string.lower(tostring(cfg.fieldwork)) == fwLower then
						config = cfg
						configId = cfg.id
						break
					end
				end
				
				if config == nil then
					-- Try searching in IANeighbours.allSituationConfigs
					if IANeighbours.allSituationConfigs ~= nil then
						for _, cfg in ipairs(IANeighbours.allSituationConfigs) do
							if cfg ~= nil and cfg.fieldwork ~= nil and string.lower(tostring(cfg.fieldwork)) == fwLower then
								config = cfg
								configId = cfg.id
								break
							end
						end
					end
				end
				
				if config == nil then
					IATestRunner.emit("test", "action_error", { error = "No situation config found for fieldwork type: " .. tostring(fieldworkType) })
				else
					-- Find a matching farmland from this neighbour's assigned farmlands
					local farmlandId = nil
					if n.assignedFarmlands ~= nil and #n.assignedFarmlands > 0 then
						if config.triggerFruitTypeIndex ~= nil and #config.triggerFruitTypeIndex > 0 then
							-- Try to find a field that matches the fruit type requirement
							if g_farmlandManager ~= nil and type(g_farmlandManager.getFarmlands) == "function" then
								local allFarmlands = g_farmlandManager:getFarmlands()
								for _, fl in ipairs(allFarmlands or {}) do
									if fl ~= nil and fl.field ~= nil and fl.field.fieldState ~= nil then
										-- Check if this farmland belongs to the neighbour
										local isAssigned = false
										for _, aid in ipairs(n.assignedFarmlands) do
											if aid == fl.id then
												isAssigned = true
												break
											end
										end
										if isAssigned then
											local fruitIdx = fl.field.fieldState.fruitTypeIndex or 0
											for _, triggerFruit in ipairs(config.triggerFruitTypeIndex) do
												local resolvedTrigger = triggerFruit
												if type(resolvedTrigger) == "string" then
													if IAFieldwork ~= nil and type(IAFieldwork.resolveFruitTypeNameOrIndex) == "function" then
														resolvedTrigger = IAFieldwork.resolveFruitTypeNameOrIndex(resolvedTrigger)
													end
												end
												if tonumber(resolvedTrigger) == tonumber(fruitIdx) then
													farmlandId = fl.id
													break
												end
											end
											if farmlandId ~= nil then break end
										end
									end
								end
							end
						end
						-- Fallback: just use the first assigned farmland
						if farmlandId == nil then
							farmlandId = n.assignedFarmlands[1]
						end
					end
					
					if farmlandId == nil then
						IATestRunner.emit("test", "action_error", { error = "Neighbour has no assigned farmlands" })
					else
						-- Inject a contract-enabled row into the schedule
						local newRow = {
							situationId = tostring(configId),
							farmlandId = farmlandId,
							contractEnabled = true,
						}
						table.insert(n.fieldworkScheduleTasks, newRow)
						
						IATestRunner.emit("fieldwork", "force_type", {
							neighbour = n.name,
							fieldworkType = fieldworkType,
							configId = tostring(configId),
							farmlandId = farmlandId,
						})
						
						print(string.format("[IATestRunner] forceFieldwork: neighbour=%s, type=%s, configId=%s, farmlandId=%d",
							n.name, fieldworkType, tostring(configId), farmlandId))
					end
				end
			end
		else
			-- Original behavior: force a random fieldwork situation
			local ok, err = n:forceNewFieldworkSituation()
			IATestRunner.emit("situation", "force_fieldwork", {
				neighbour = n.name, ok = ok, error = err,
			})
		end

	elseif atype == "forceFieldState" then
		-- Force a specific field to a given fruit type and growth state for testing
		-- Parameters: neighbourId/neighbourName (optional), farmlandId (optional), 
		--              fruitTypeIndex (string or number), growthState (string or number),
		--              updateVisuals (boolean, default true)
		local farmlandId = action.farmlandId

		-- Resolve the field
		if farmlandId == nil then
			-- Find from neighbour
			local nToken = action.neighbourId or action.neighbourName
			local n = nil
			if nToken ~= nil then
				n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
			else
				-- Auto-discover first farmer neighbour
				for _, nb in pairs(IANeighbours.neighbours or {}) do
					if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour"
						and nb.assignedFarmlands ~= nil and #nb.assignedFarmlands > 0 then
						n = nb
						break
					end
				end
			end
			if n == nil or n.assignedFarmlands == nil or #n.assignedFarmlands == 0 then
				IATestRunner.emit("field", "force_state_error", { error = "No neighbour with assigned farmlands found" })
				return
			end
			farmlandId = n.assignedFarmlands[1]
		end

		-- Get the field from farmland
		local farmland = nil
		if g_farmlandManager ~= nil and type(g_farmlandManager.getFarmlands) == "function" then
			local farmlands = g_farmlandManager:getFarmlands()
			for _, fl in ipairs(farmlands or {}) do
				if fl ~= nil and fl.id == farmlandId then
					farmland = fl
					break
				end
			end
		end

		if farmland == nil or farmland.field == nil or farmland.field.fieldState == nil then
			IATestRunner.emit("field", "force_state_error", { error = "Farmland " .. tostring(farmlandId) .. " not found or has no field/fieldState" })
			return
		end

		local field = farmland.field

		-- Resolve fruit type index
		local fruitTypeIndex = action.fruitTypeIndex
		if type(fruitTypeIndex) == "string" then
			if IAFieldwork ~= nil and type(IAFieldwork.resolveFruitTypeNameOrIndex) == "function" then
				local resolved = IAFieldwork.resolveFruitTypeNameOrIndex(fruitTypeIndex)
				if resolved ~= nil then
					fruitTypeIndex = resolved
				end
			end
			-- Fallback: try game's fruitTypeManager
			if type(fruitTypeIndex) == "string" and g_fruitTypeManager ~= nil then
				local fruitTypes = g_fruitTypeManager:getFruitTypes()
				for _, ft in ipairs(fruitTypes or {}) do
					if ft ~= nil and ft.name ~= nil and string.upper(tostring(ft.name)) == string.upper(tostring(fruitTypeIndex)) then
						fruitTypeIndex = ft.index
						break
					end
				end
			end
		end
		fruitTypeIndex = tonumber(fruitTypeIndex) or 0

		-- Resolve growth state
		local growthState = action.growthState
		if type(growthState) == "string" then
			-- Try to resolve via IAFieldwork helper
			local resolvedGrowth = nil
			if IAFieldwork ~= nil and type(IAFieldwork.getHarvestReadyGrowthStateForFruit) == "function" then
				resolvedGrowth = IAFieldwork.getHarvestReadyGrowthStateForFruit(fruitTypeIndex)
			end
			if resolvedGrowth ~= nil then
				growthState = resolvedGrowth
			else
				-- Fallback: try to look up from fruitType growthStateToName
				if IAFieldwork ~= nil and type(IAFieldwork.getFruitGrowthStateNameToIndex) == "function" then
					-- Use the growth state name lookup if available
					local gsMap = IAFieldwork.getFruitGrowthStateNameToIndex(fruitTypeIndex)
					if gsMap ~= nil then
						local gsLower = string.lower(tostring(action.growthState))
						for gsName, gsIndex in pairs(gsMap) do
							if string.lower(tostring(gsName)) == gsLower then
								growthState = gsIndex
								break
							end
						end
					end
				end
			end
		end
		growthState = tonumber(growthState) or 1

		-- Apply the state to the field
		field.fieldState.fruitTypeIndex = fruitTypeIndex
		field.fieldState.growthState = growthState

		-- Optionally update visuals (density maps)
		local updateVisuals = action.updateVisuals
		if updateVisuals == nil then
			updateVisuals = true
		end

		if updateVisuals and IAFieldwork ~= nil and type(IAFieldwork.enqueueSetFieldToCropHarvestReady) == "function" then
			IAFieldwork.enqueueSetFieldToCropHarvestReady(field, fruitTypeIndex)
		end

		IATestRunner.emit("field", "force_state", {
			farmlandId = farmlandId,
			fruitTypeIndex = fruitTypeIndex,
			growthState = growthState,
			updateVisuals = updateVisuals,
		})

		print(string.format("[IATestRunner] forceFieldState: farmland=%d, fruitTypeIndex=%d, growthState=%d", farmlandId, fruitTypeIndex, growthState))

	elseif atype == "forceScheduleRebuild" then
		local nToken = action.neighbourId or action.neighbourName
		local n = nil
		if nToken ~= nil then
			n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		end
		if n == nil then
			-- Rebuild for all farmer neighbours
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour"
					and IANeighbours.gameLoopHelper ~= nil then
					pcall(function()
						IANeighbours.gameLoopHelper:rebuildDailyFieldworkSchedule(nb)
					end)
				end
			end
		elseif IANeighbours.gameLoopHelper ~= nil then
			IANeighbours.gameLoopHelper:rebuildDailyFieldworkSchedule(n)
		end
		IATestRunner.emit("schedule", "force_rebuild", { neighbour = nToken })

	elseif atype == "prepareFieldForWork" then
		-- Find the first farmer neighbour with assigned farmlands and set their
		-- first field to a plowable state (groundType=2, no crop) so that at
		-- least one "Plow" fieldwork config matches after a schedule rebuild.
		local targetN = nil
		local targetFarmlandId = nil
		local nToken = action.neighbourId or action.neighbourName
		if nToken ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		end
		if targetN == nil then
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.assignedFarmlands ~= nil and #nb.assignedFarmlands > 0 then
					targetN = nb
					break
				end
			end
		end
		if targetN ~= nil and targetN.assignedFarmlands ~= nil and #targetN.assignedFarmlands > 0 then
			targetFarmlandId = targetN.assignedFarmlands[1]
		end

		if targetFarmlandId == nil then
			IATestRunner.emit("test", "action_error", { error = "no farmer with farmlands found for prepareFieldForWork" })
			return
		end

		local farmlands = g_farmlandManager:getFarmlands()
		local farmland = nil
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == targetFarmlandId then
				farmland = f
				break
			end
		end
		if farmland == nil or farmland.field == nil then
			IATestRunner.emit("test", "action_error", { error = "farmland " .. tostring(targetFarmlandId) .. " has no field" })
			return
		end

		local field = farmland.field
		local state = { groundType = FieldGroundType.PLOWED or 2, fruitTypeIndex = 0 }
		local ok, task = pcall(IAFieldwork.buildFieldUpdateTaskFromExpectedState, field, state)
		if ok and task ~= nil then
			task:enqueue(true)
			IATestRunner.emit("field", "prepare_for_work", {
				neighbour = targetN.name,
				farmlandId = targetFarmlandId,
				groundType = state.groundType,
			})
		else
			IATestRunner.emit("test", "action_error", { error = "prepareFieldForWork failed: " .. tostring(task) })
		end

	elseif atype == "prepareFieldForHarvest" then
		-- Find the first farmer neighbour with assigned farmlands and set their
		-- first field to a harvest-ready state so that harvest contract tasks
		-- exist after a schedule rebuild. Uses fruitType from action config,
		-- defaulting to MAIZE (which triggers harvest_deliver_corn configs).
		local targetN = nil
		local targetFarmlandId = nil
		local nToken = action.neighbourId or action.neighbourName
		if nToken ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		end
		if targetN == nil then
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.assignedFarmlands ~= nil and #nb.assignedFarmlands > 0 then
					targetN = nb
					break
				end
			end
		end
		if targetN ~= nil and targetN.assignedFarmlands ~= nil and #targetN.assignedFarmlands > 0 then
			targetFarmlandId = targetN.assignedFarmlands[1]
		end

		if targetFarmlandId == nil then
			IATestRunner.emit("test", "action_error", { error = "no farmer with farmlands found for prepareFieldForHarvest" })
			return
		end

		local farmlands = g_farmlandManager:getFarmlands()
		local farmland = nil
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == targetFarmlandId then
				farmland = f
				break
			end
		end
		if farmland == nil or farmland.field == nil then
			IATestRunner.emit("test", "action_error", { error = "farmland " .. tostring(targetFarmlandId) .. " has no field" })
			return
		end

		local field = farmland.field

		-- Use fruitType from action config, default to MAIZE
		local fruitName = action.fruitType or "MAIZE"
		local fruitTypeIndex = IAFieldwork.resolveFruitTypeNameOrIndex(fruitName)
		if fruitTypeIndex == nil then
			IATestRunner.emit("test", "action_error", {
				action = "prepareFieldForHarvest",
				error = "Could not resolve fruit type: " .. tostring(fruitName)
			})
			return
		end
		local growthState = IAFieldwork.getHarvestReadyGrowthStateForFruit(fruitTypeIndex)
		if growthState == nil then
			IATestRunner.emit("test", "action_error", {
				action = "prepareFieldForHarvest",
				error = "Could not get harvest-ready growth state for fruit type: " .. tostring(fruitName)
			})
			return
		end
		local state = {
			fruitTypeIndex = fruitTypeIndex,
			growthState = growthState,
			weedState = 0,
		}
		local ok, task = pcall(IAFieldwork.buildFieldUpdateTaskFromExpectedState, field, state)
		if ok and task ~= nil then
			task:enqueue(true)
			IATestRunner.emit("field", "prepare_for_harvest", {
				neighbour = targetN.name,
				farmlandId = targetFarmlandId,
				fruitType = fruitName,
			})
		else
			IATestRunner.emit("test", "action_error", { error = "prepareFieldForHarvest failed: " .. tostring(task) })
		end

	elseif atype == "triggerIncomingPhoneRing" then
		-- Respect mission offer mode: classic mode blocks phone calls
		if IASettings ~= nil and type(IASettings.isMissionOfferModeClassic) == "function" then
			if IASettings.isMissionOfferModeClassic() then
				IATestRunner.emit("phone", "ring_triggered", {
					neighbour = "(blocked by classic mode)",
					ok = false,
				})
				return
			end
		end
		-- Find a suitable farmer neighbour with contract-enabled tasks
		local targetN = nil
		local ringNid = action.neighbourId or action.neighbourName
		if ringNid ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(ringNid)
		else
			-- Pick the first farmer neighbour with contract-enabled tasks (same logic as console command)
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.role == "Neighbour" and nb.job == "Farmer" then
					local tasks = nb.fieldworkScheduleTasks
					if tasks ~= nil then
						for _, row in ipairs(tasks) do
							if row ~= nil and row.contractEnabled == true then
								targetN = nb
								break
							end
						end
					end
				end
				if targetN ~= nil then
					break
				end
			end
			-- Fallback: any farmer neighbour
			if targetN == nil then
				for _, nb in pairs(IANeighbours.neighbours or {}) do
					if nb ~= nil and nb.initialized and nb.role == "Neighbour" and nb.job == "Farmer" then
						targetN = nb
						break
					end
				end
			end
		end
		if targetN == nil then
			IATestRunner.emit("phone", "ring_fail", { reason = "no eligible neighbour" })
		else
			-- Reset per-neighbour daily state so onContractCallTimeTriggered isn't blocked
			-- (same as consoleCommandIaTriggerNextCall)
			targetN.contractCallRingAnsweredToday = false
			targetN.contractCallRingOpensCount = 0
			targetN.contractCallLastRingScheduleKey = nil
			targetN.contractCallLastRingTotalMinutes = nil
			targetN.contractCallTriggerFiredForScheduleKey = nil

			-- Clear any pending ring and global cooldown (same as console command)
			if IANeighbours._incomingPhonePayload ~= nil then
				IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.DECLINED)
			end
			IANeighbours._globalInboundPhoneCooldownUntilWallClockSec = 0

			-- Use the natural contract call flow (same as iaTriggerNextCall)
			local ok, err = pcall(function()
				targetN:onContractCallTimeTriggered()
			end)
			IATestRunner.emit("phone", "ring_triggered", {
				neighbour = targetN.name,
				ok = ok and not err,
				error = (not ok) and tostring(err) or nil,
			})
		end

	elseif atype == "answerPhone" then
		local p = IANeighbours._incomingPhonePayload
		if p ~= nil then
			-- First stop the ring sound and clear the pending state
			IANeighbours.stopIncomingCallRingSound()
			IATestRunner.emit("phone", "answer", { neighbour = p.neighbourName })
			-- Then actually answer
			IANeighbours.answerIncomingPhoneFromPayload(p)
			IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.ANSWERED)
			IANeighbours.incomingPhoneRingDialogOpen = false
		else
			IATestRunner.emit("phone", "answer_fail", { reason = "no pending payload" })
		end

	elseif atype == "declinePhone" then
		if IANeighbours._incomingPhonePayload ~= nil then
			IATestRunner.emit("phone", "decline", { neighbour = IANeighbours._incomingPhonePayload.neighbourName })
			IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.DECLINED)
		end

	elseif atype == "closeDialog" then
		if g_gui ~= nil and g_gui.currentDialog ~= nil then
			g_gui:closeDialog(g_gui.currentDialog)
			IATestRunner.emit("ui", "dialog_closed", {})
			-- Also clean up any active standalone phone conversation state
			if IANeighbours ~= nil and type(IANeighbours.activeStandalonePhoneConversation) == "table" then
				local conv = IANeighbours.activeStandalonePhoneConversation
				if type(conv.stop) == "function" then
					conv:stop(true)
				end
				IANeighbours.activeStandalonePhoneConversation = nil
				IANeighbours.activeStandalonePhoneNeighbourId = nil
			end
		end

	elseif atype == "triggerGameSave" then
		IATestRunner.emit("game", "save_begin", {})
		local ok = false
		if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
			and type(g_currentMission.missionInfo.saveToXMLFile) == "function" then
			pcall(function()
				g_currentMission.missionInfo:saveToXMLFile()
			end)
			ok = true
		elseif g_currentMission ~= nil and type(g_currentMission.saveSavegame) == "function" then
			pcall(function()
				g_currentMission:saveSavegame()
			end)
			ok = true
		end
		IATestRunner.emit("game", "save_end", { ok = ok, savegameDir = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory })

	elseif atype == "startConversation" then
		-- Find the nearest approachable neighbour directly (same rules as the mod's
		-- updateNeighbours: distance < 5m, characterVisibility yes/in_car, or
		-- npcVisibleWhilePaused fieldwork). Does NOT depend on nearbySituation being
		-- pre-set by the mod's per-frame scan.
		IATestRunner.emit("conversation", "attempt", {})
		local bestDist, bestSit = nil, nil
		local playerInVehicle = g_localPlayer ~= nil
			and g_localPlayer.getIsInVehicle ~= nil
			and g_localPlayer:getIsInVehicle()
		if not playerInVehicle then
			for _, n in pairs(IANeighbours.neighbours or {}) do
				if n ~= nil and n.initialized and n.activeSituation ~= nil
					and n.distanceToPlayer ~= nil and n.distanceToPlayer < 5 then
					local sit = n.activeSituation
					local visOk = sit.characterVisibility == "yes"
						or sit.characterVisibility == "in_car"
					local fwOnFoot = sit.jobType ~= nil
						and sit.npcVisibleWhilePaused == true
					if visOk or fwOnFoot then
						if bestDist == nil or n.distanceToPlayer < bestDist then
							bestDist = n.distanceToPlayer
							bestSit = sit
						end
					end
				end
			end
		end
		if bestSit ~= nil then
			bestSit:startConversation()
			IATestRunner.emit("conversation", "started", {
				neighbour = bestSit.neighbour and bestSit.neighbour.name or "?",
				distance = bestDist,
			})
		else
			-- Report exactly WHY no neighbour is approachable
			local closestDist, closestName, closestVis, closestHasSit = nil, nil, nil, nil
			for _, n in pairs(IANeighbours.neighbours or {}) do
				if n ~= nil and n.initialized and n.distanceToPlayer ~= nil then
					if closestDist == nil or n.distanceToPlayer < closestDist then
						closestDist = n.distanceToPlayer
						closestName = n.name
						if n.activeSituation ~= nil then
							closestHasSit = true
							closestVis = n.activeSituation.characterVisibility
						else
							closestHasSit = false
						end
					end
				end
			end
			IATestRunner.emit("conversation", "neighbour_unavailable", {
				closest = closestName,
				distance = closestDist,
				hasSituation = closestHasSit,
				visibility = closestVis,
				playerInVehicle = playerInVehicle,
			})
			IANeighbours:onUsePhone()
			IATestRunner.emit("conversation", "phone_opened", {})
		end

	-- ── Player Teleport ─────────────────────────────────────────

	elseif atype == "teleportPlayerTo" then
		if g_localPlayer == nil then return end
		local x, y, z = action.x, action.y, action.z
		if x == nil or z == nil then return end
		local vy = y or 0
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local th = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
			if th ~= nil then vy = th + 1.0 end
		end

		-- Eject from vehicle if player is in one (character controller blocks teleport)
		if g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
			if g_localPlayer.vehicle ~= nil and g_localPlayer.vehicle.getCharacterOut ~= nil then
				pcall(function() g_localPlayer.vehicle:getCharacterOut(g_localPlayer) end)
			end
		end

		-- Always try the API (may help with game-logic state), then force position via rootNode
		if g_localPlayer.teleportTo ~= nil then
			pcall(g_localPlayer.teleportTo, g_localPlayer, x, vy, z, true, true)
			print(string.format("[IATestRunner] teleportPlayerTo: API teleport to (%.1f, %.1f, %.1f)", x, vy, z))
		end

		-- Always force position via setWorldTranslation (this is what actually works in FS25)
		if g_localPlayer.rootNode ~= nil then
			setWorldTranslation(g_localPlayer.rootNode, x, vy + 0.1, z)
		end

		-- Verify using getPosition() (game-logic character position, not node transform)
		local px, py, pz = 0, 0, 0
		if g_localPlayer.getPosition ~= nil then
			px, py, pz = g_localPlayer:getPosition()
		else
			px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
		end
		local dx = math.abs(px - x)
		local dz = math.abs(pz - z)
		if dx > 10.0 or dz > 10.0 then
			print(string.format("[IATestRunner] teleportPlayerTo: FAILED - player at (%.1f, %.1f) but target was (%.1f, %.1f)", px, pz, x, z))
			IATestRunner.emit("player", "teleport_fail", { reason = "player did not move to target position", targetX = x, targetZ = z, actualX = px, actualZ = pz })
		else
			print(string.format("[IATestRunner] teleportPlayerTo: SUCCESS - player at (%.1f, %.1f)", px, pz))
			IATestRunner.emit("player", "teleport", { x = x, y = vy, z = z })
		end

	elseif atype == "teleportPlayerToNeighbour" then
		local nToken = action.neighbourId or action.neighbourName or "1"
		local n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		if n == nil or g_localPlayer == nil then return end
		local nx, ny, nz = nil, nil, nil
		local sit = n.activeSituation
		if sit ~= nil and sit.positionX ~= nil and sit.positionZ ~= nil then
			nx, nz = sit.positionX, sit.positionZ
			ny = sit.positionY or 0
		end
		-- Fallback: use the neighbour's assigned homebase place
		if nx == nil and n.assignedHomebasePlaceIds ~= nil then
			for _, pid in ipairs(n.assignedHomebasePlaceIds) do
				if IANeighbours.places ~= nil then
					for _, p in ipairs(IANeighbours.places) do
						if p ~= nil and p.id == pid and p.x ~= nil and p.z ~= nil then
							nx, nz = p.x, p.z
							ny = p.y or 0
							break
						end
					end
				end
				if nx ~= nil then break end
			end
		end
		if nx == nil or nz == nil then
			IATestRunner.emit("player", "teleport_fail", { neighbour = n.name, reason = "no position resolved" })
			return
		end
		local ty = ny or 0
		if ty == 0 and g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local th = getTerrainHeightAtWorldPos(g_terrainNode, nx, 0, nz)
			if th ~= nil then ty = th + 1.0 end
		end
		local targetX = nx + 3
		local targetZ = nz + 3

		-- Eject from vehicle if player is in one (character controller blocks teleport)
		if g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
			if g_localPlayer.vehicle ~= nil and g_localPlayer.vehicle.getCharacterOut ~= nil then
				pcall(function() g_localPlayer.vehicle:getCharacterOut(g_localPlayer) end)
			end
		end

		-- Always try the API (may help with game-logic state), then force position via rootNode
		if g_localPlayer.teleportTo ~= nil then
			pcall(g_localPlayer.teleportTo, g_localPlayer, targetX, ty, targetZ, true, true)
			print(string.format("[IATestRunner] teleportPlayerToNeighbour: API teleport to (%.1f, %.1f, %.1f)", targetX, ty, targetZ))
		end

		-- Always force position via setWorldTranslation (this is what actually works in FS25)
		if g_localPlayer.rootNode ~= nil then
			setWorldTranslation(g_localPlayer.rootNode, targetX, ty + 0.1, targetZ)
		end

		-- Verify using getPosition() (game-logic character position, not node transform)
		local px, py, pz = 0, 0, 0
		if g_localPlayer.getPosition ~= nil then
			px, py, pz = g_localPlayer:getPosition()
		else
			px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
		end
		local dx = math.abs(px - targetX)
		local dz = math.abs(pz - targetZ)
		if dx > 10.0 or dz > 10.0 then
			print(string.format("[IATestRunner] teleportPlayerToNeighbour: FAILED - player at (%.1f, %.1f) but target was (%.1f, %.1f)", px, pz, targetX, targetZ))
			IATestRunner.emit("player", "teleport_fail", { neighbour = n.name, reason = "player did not move to target position", targetX = targetX, targetZ = targetZ, actualX = px, actualZ = pz })
		else
			print(string.format("[IATestRunner] teleportPlayerToNeighbour: SUCCESS - %s at (%.1f, %.1f)", n.name or "?", px, pz))
			IATestRunner.emit("player", "teleport_to_neighbour", { neighbour = n.name, x = targetX, z = targetZ })
		end

	elseif atype == "teleportToField" then
		-- Teleport player to the center of a neighbour's assigned farmland field.
		-- Uses the same neighbour resolution as prepareFieldForHarvest.
		-- Parameters:
		--   neighbourId    (string, optional) → specific neighbour
		--   neighbourName  (string, optional) → specific neighbour by name
		--   farmlandIndex  (number, default 1) → 1-based index into assignedFarmlands
		local targetN = nil
		local targetFarmlandId = nil
		local nToken = action.neighbourId or action.neighbourName
		if nToken ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		end
		if targetN == nil then
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.assignedFarmlands ~= nil and #nb.assignedFarmlands > 0 then
					targetN = nb
					break
				end
			end
		end
		if targetN ~= nil and targetN.assignedFarmlands ~= nil and #targetN.assignedFarmlands > 0 then
			local idx = action.farmlandIndex or 1
			targetFarmlandId = targetN.assignedFarmlands[idx]
		end

		if targetFarmlandId == nil then
			IATestRunner.emit("test", "action_error", { error = "no farmer with farmlands found for teleportToField" })
			return
		end

		local farmlands = g_farmlandManager:getFarmlands()
		local farmland = nil
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == targetFarmlandId then
				farmland = f
				break
			end
		end
		if farmland == nil or farmland.field == nil then
			IATestRunner.emit("test", "action_error", { error = "farmland " .. tostring(targetFarmlandId) .. " has no field" })
			return
		end

		local field = farmland.field
		local cx, cz = nil, nil

		-- Primary: vanilla FS25 API
		if type(field.getCenterOfFieldWorldPosition) == "function" then
			cx, cz = field:getCenterOfFieldWorldPosition()
		end
		-- Fallback: direct properties
		if (cx == nil or cz == nil) and field.posX ~= nil and field.posZ ~= nil then
			cx, cz = field.posX, field.posZ
		end

		if cx == nil or cz == nil then
			IATestRunner.emit("test", "action_error", { error = "could not resolve field center for farmland " .. tostring(targetFarmlandId) })
			return
		end

		-- Get terrain height for Y
		local ty = 0
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local th = getTerrainHeightAtWorldPos(g_terrainNode, cx, 0, cz)
			if th ~= nil then ty = th + 1.0 end
		end

		if g_localPlayer == nil then return end

		-- Eject from vehicle if player is in one (character controller blocks teleport)
		if g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
			if g_localPlayer.vehicle ~= nil and g_localPlayer.vehicle.getCharacterOut ~= nil then
				pcall(function() g_localPlayer.vehicle:getCharacterOut(g_localPlayer) end)
			end
		end

		-- Always try the API (may help with game-logic state), then force position via rootNode
		if g_localPlayer.teleportTo ~= nil then
			pcall(g_localPlayer.teleportTo, g_localPlayer, cx, ty, cz, true, true)
			print(string.format("[IATestRunner] teleportToField: API teleport to (%.1f, %.1f, %.1f)", cx, ty, cz))
		end

		-- Always force position via setWorldTranslation (this is what actually works in FS25)
		if g_localPlayer.rootNode ~= nil then
			setWorldTranslation(g_localPlayer.rootNode, cx, ty + 0.1, cz)
		end

		-- Verify using getPosition() (game-logic character position, not node transform)
		local px, py, pz = 0, 0, 0
		if g_localPlayer.getPosition ~= nil then
			px, py, pz = g_localPlayer:getPosition()
		else
			px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
		end
		local dx = math.abs(px - cx)
		local dz = math.abs(pz - cz)
		if dx > 10.0 or dz > 10.0 then
			print(string.format("[IATestRunner] teleportToField: FAILED - player at (%.1f, %.1f) but target was (%.1f, %.1f)", px, pz, cx, cz))
			IATestRunner.emit("player", "teleport_fail", { reason = "player did not move to field center", targetX = cx, targetZ = cz, actualX = px, actualZ = pz, farmlandId = targetFarmlandId })
		else
			print(string.format("[IATestRunner] teleportToField: SUCCESS - field %d at (%.1f, %.1f)", targetFarmlandId, px, pz))
			IATestRunner.emit("player", "teleport_to_field", { farmlandId = targetFarmlandId, neighbour = targetN.name, x = cx, z = cz })
		end

	elseif atype == "teleportPlayerHarvesterToField" then
			-- Teleport the player's harvester (combine) + attached cutter/header to a field.
			-- Uses the same field resolution as teleportToField.
			-- Parameters:
			--   neighbourId    (string, optional) → whose farmland to use
			--   neighbourName  (string, optional) → whose farmland to use by name
			--   farmlandIndex  (number, default 1) → 1-based index into assignedFarmlands
			--   rotation       (number, default 0) → vehicle yaw on field

			-- 1. Resolve field (identical to teleportToField)
			local targetN = nil
			local targetFarmlandId = nil
			local nToken = action.neighbourId or action.neighbourName
			if nToken ~= nil then
				targetN = IANeighbours:resolveNeighbourForConsoleToken(nToken)
			end
			if targetN == nil then
				for _, nb in pairs(IANeighbours.neighbours or {}) do
					if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour"
						and nb.assignedFarmlands ~= nil and #nb.assignedFarmlands > 0 then
						targetN = nb
						break
					end
				end
			end
			if targetN ~= nil and targetN.assignedFarmlands ~= nil and #targetN.assignedFarmlands > 0 then
				local idx = action.farmlandIndex or 1
				targetFarmlandId = targetN.assignedFarmlands[idx]
			end

			if targetFarmlandId == nil then
				IATestRunner.emit("test", "action_error", { error = "no farmer with farmlands found for teleportPlayerHarvesterToField" })
				return
			end

			local farmlands = g_farmlandManager:getFarmlands()
			local farmland = nil
			for _, f in pairs(farmlands) do
				if f ~= nil and f.id == targetFarmlandId then
					farmland = f
					break
				end
			end
			if farmland == nil or farmland.field == nil then
				IATestRunner.emit("test", "action_error", { error = "farmland " .. tostring(targetFarmlandId) .. " has no field" })
				return
			end

			local field = farmland.field
			local cx, cz = nil, nil
			if type(field.getCenterOfFieldWorldPosition) == "function" then
				cx, cz = field:getCenterOfFieldWorldPosition()
			end
			if (cx == nil or cz == nil) and field.posX ~= nil and field.posZ ~= nil then
				cx, cz = field.posX, field.posZ
			end
			if cx == nil or cz == nil then
				IATestRunner.emit("test", "action_error", { error = "could not resolve field center for farmland " .. tostring(targetFarmlandId) })
				return
			end

			local targetRot = action.rotation or 0

			-- 2. Find player-owned harvester / combine
			local playerFarmId = nil
			if g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" then
				playerFarmId = g_currentMission:getFarmId()
			end
			if playerFarmId == nil and g_currentMission ~= nil and g_currentMission.playerSystem ~= nil
				and g_currentMission.playerSystem.localPlayer ~= nil then
				local lp = g_currentMission.playerSystem.localPlayer
				if lp.farmId ~= nil then
					playerFarmId = lp.farmId
				end
			end
			if playerFarmId == nil then
				playerFarmId = 1
			end

			local harvester = nil
			local harvesterTypeName = nil
			if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil then
				for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
					if v ~= nil then
						local ownerFarmId = nil
						if type(v.getOwnerFarmId) == "function" then
							ownerFarmId = v:getOwnerFarmId()
						end
						if ownerFarmId == playerFarmId then
							-- Check via spec_combine first (most reliable)
							if v.spec_combine ~= nil then
								harvester = v
								harvesterTypeName = "combine"
								break
							end
							-- Fallback: typeName string match
							local tn = v.typeName and string.lower(tostring(v.typeName)) or ""
							if tn == "combine" or tn == "harvester" or tn == "forageharvesters" then
								harvester = v
								harvesterTypeName = tn
								break
							end
						end
					end
				end
			end

			if harvester == nil then
				IATestRunner.emit("vehicle", "harvester_not_found", {
					reason = "no player-owned harvester/combine found",
					playerFarmId = playerFarmId,
				})
				print(string.format("[IATestRunner] teleportPlayerHarvesterToField: FAILED - no player harvester found (farmId=%d)", playerFarmId))
				return
			end

			-- 3. Teleport harvester to field with offset from player position
			-- The player is teleported to field center by teleportToField.
			-- Place the harvester at an offset so they don't overlap.
			local playerOffset = action.playerOffset or 25  -- meters to the right of field center
			local hx = cx + playerOffset
			local hz = cz

			local ty = 0
			if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
				local th = getTerrainHeightAtWorldPos(g_terrainNode, hx, 0, hz)
				if th ~= nil then ty = th + 0.2 end
			end

			-- Eject player if sitting in the harvester (teleport may fail otherwise)
			if g_localPlayer ~= nil and g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
				if g_localPlayer.vehicle == harvester then
					if harvester.getCharacterOut ~= nil then
						pcall(function() harvester:getCharacterOut(g_localPlayer) end)
					end
				end
			end

			-- Stop AI if active (teleport while AI running can cause issues)
			if harvester.getIsAIActive ~= nil and harvester:getIsAIActive() then
				pcall(function()
					harvester:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
				end)
			end

			-- Teleport following the Reconcile pattern from IAEquipmentPresence.Reconcile.executeDiff:
			-- detach → hide → prepareForTeleport → teleport parent → teleport child → show parent → attach → show child
			local okTeleport = false
			local attachedImplements = {}
			local headerObj = nil
			local headerAttachJoint = nil
			local headerAttachIndex = nil
			local headerAttacherNode = nil  -- node on harvester side
			local headerHookNode = nil      -- node on header side
			pcall(function()
				-- ── Reconcile Step 1: Detach — identify the real header (cutter), not the trailer ──
				-- Collect all directly-attached implements from the harvester.
				if harvester.getAttachedImplements ~= nil and type(harvester.getAttachedImplements) == "function" then
					local okAtt, list = pcall(function() return harvester:getAttachedImplements() end)
					if okAtt and list ~= nil then
						for _, entry in pairs(list) do
							local obj = entry
							if type(entry) == "table" and entry.object ~= nil then
								obj = entry.object
							end
							if obj ~= nil then
								table.insert(attachedImplements, obj)
							end
						end
					end
				end

				-- Identify the header: it has spec_combineCutter or spec_cutter.
				-- The header trailer does NOT have these specs.
				for _, obj in ipairs(attachedImplements) do
					if obj ~= nil and (obj.spec_combineCutter ~= nil or obj.spec_cutter ~= nil) then
						headerObj = obj
						break
					end
				end

				-- If header not found directly, it may be sitting on the header trailer.
				-- Search each implement's own attached implements for the cutter.
				if headerObj == nil then
					for _, obj in ipairs(attachedImplements) do
						if obj ~= nil and obj.getAttachedImplements ~= nil
							and type(obj.getAttachedImplements) == "function" then
							local okSub, subList = pcall(function() return obj:getAttachedImplements() end)
							if okSub and subList ~= nil then
								for _, subEntry in pairs(subList) do
									local subObj = subEntry
									if type(subEntry) == "table" and subEntry.object ~= nil then
										subObj = subEntry.object
									end
									if subObj ~= nil and (subObj.spec_combineCutter ~= nil or subObj.spec_cutter ~= nil) then
										headerObj = subObj
										-- Detach header from trailer first
										if obj.getImplementIndexByObject ~= nil then
											local okIdx, impIdx = pcall(function()
												return obj:getImplementIndexByObject(subObj)
											end)
											if okIdx and impIdx ~= nil then
												pcall(function() obj:detachImplement(impIdx, true) end)
											end
										end
										break
									end
								end
							end
						end
						if headerObj ~= nil then break end
					end
				end

				-- Remember front-attachment joint info for the header (for reattach later).
				if headerObj ~= nil then
					local joint, idx, aNode, hNode = identifyAttachmentJointFront(headerObj, harvester)
					if joint ~= nil and idx ~= nil then
						headerAttachJoint = joint
						headerAttachIndex = idx
						headerAttacherNode = aNode
						headerHookNode = hNode
					end
					-- If header is still directly attached to harvester, detach it now.
					if harvester.getImplementIndexByObject ~= nil then
						local okIdx, impIdx = pcall(function()
							return harvester:getImplementIndexByObject(headerObj)
						end)
						if okIdx and impIdx ~= nil then
							pcall(function() harvester:detachImplement(impIdx, true) end)
						end
					end
				end

				-- Detach remaining implements (trailers etc.) from harvester.
				for _, obj in ipairs(attachedImplements) do
					if obj ~= nil and obj ~= headerObj then
						if harvester.getImplementIndexByObject ~= nil then
							local okIdx, impIdx = pcall(function()
								return harvester:getImplementIndexByObject(obj)
							end)
							if okIdx and impIdx ~= nil then
								pcall(function() harvester:detachImplement(impIdx, true) end)
							end
						end
					end
				end

				-- ── Reconcile Step 2: Hide both (removePhysics + setVisibility false) ──
				-- Match mech_hide(): removeFromPhysics first, then setVisibility(false)
				harvester:removeFromPhysics()
				harvester:setVisibility(false)
				for _, obj in ipairs(attachedImplements) do
					pcall(function() obj:removeFromPhysics() end)
					pcall(function() obj:setVisibility(false) end)
				end

				-- ── Reconcile Step 3: prepareForTeleport ──
				-- Match mech_prepareForTeleport(): fold combine pipe, unfold header if needed
				if type(IAHelper_foldCombinePipeIn) == "function" then
					pcall(function() IAHelper_foldCombinePipeIn(harvester) end)
				end
				-- Unfold header/cutter when unattached (same as shouldBeUnfoldedWhenUnattached)
				for _, obj in ipairs(attachedImplements) do
					if obj ~= nil and obj.spec_combineCutter ~= nil then
						pcall(function()
							if obj.setFoldState ~= nil then
								obj:setFoldState(0, false)  -- unfold
							end
						end)
					end
				end
				-- Also unfold headerObj if it was found on a trailer (not in attachedImplements)
				if headerObj ~= nil and headerObj.spec_combineCutter ~= nil then
					pcall(function()
						if headerObj.setFoldState ~= nil then
							headerObj:setFoldState(0, false)  -- unfold
						end
					end)
				end

				-- ── Reconcile Step 4: Teleport harvester (parent) ──
				-- Match mech_teleportToPose(): removeFromPhysics (already done), set position,
				-- only addToPhysics if visible (which is false, so skip — show will do it).
				local terrainY = (g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil)
					and getTerrainHeightAtWorldPos(g_terrainNode, hx, 0, hz) or ty
				local isNearTerrain = (math.abs(ty - terrainY) <= 1.0)
				if isNearTerrain and harvester.setWorldPosition ~= nil then
					harvester:setRelativePosition(hx, 0.5, hz, targetRot, true)
				else
					setTranslation(harvester.rootNode, hx, ty, hz)
					setRotation(harvester.rootNode, 0, targetRot, 0)
				end

				-- ── Reconcile Step 5: Teleport header (child) ──
				-- Position header at calculated attachment-aligned world coords.
				-- Do NOT add physics / show yet — attach + show will handle that.
				for _, obj in ipairs(attachedImplements) do
					if obj ~= nil and obj ~= headerObj then
						local impX = hx + 5
						local impZ = hz
						local impY = ty
						pcall(function()
							setTranslation(obj.rootNode, impX, impY, impZ)
							setRotation(obj.rootNode, 0, targetRot, 0)
						end)
					end
				end
				if headerObj ~= nil and headerAttacherNode ~= nil and headerHookNode ~= nil then
					local headerX, headerY, headerZ = calculateAttachmentRootPosition2(
						harvester.rootNode, headerObj.rootNode,
						headerAttacherNode, headerHookNode
					)
					if headerX ~= nil and headerZ ~= nil then
						if headerY == nil or headerY < ty then
							headerY = ty
						end
						pcall(function()
							setTranslation(headerObj.rootNode, headerX, headerY, headerZ)
							setRotation(headerObj.rootNode, 0, targetRot, 0)
						end)
					end
				end

				-- ── Reconcile Step 6: Show harvester (parent) ──
				-- Match mech_show(): addToPhysics first, then setVisibility(true)
				harvester:addToPhysics()
				harvester:setVisibility(true)

				-- ── Reconcile Step 7: Reattach header (child) ──
				if headerObj ~= nil and headerAttachJoint ~= nil and headerAttachIndex ~= nil then
					-- [COMPAT] ManualAttach: prevent auto-detach of PTO/hoses
					pcall(function()
						if headerObj.spec_manualAttachPowerTakeOff then
							headerObj.spec_manualAttachPowerTakeOff.isBlockingInitialPtoDetach = true
						end
					end)
					pcall(function()
						if headerObj.spec_manualAttachConnectionHoses then
							headerObj.spec_manualAttachConnectionHoses.isBlockingInitialHoseDetach = true
						end
					end)
					pcall(function()
						harvester:attachImplement(headerObj, headerAttachJoint, headerAttachIndex, true, nil, nil, false)
					end)
				end

				-- ── Reconcile Step 8: Show child implements ──
				-- Now that the header is attached, show all implements.
				for _, obj in ipairs(attachedImplements) do
					pcall(function() obj:addToPhysics() end)
					pcall(function() obj:setVisibility(true) end)
				end

				okTeleport = true
			end)

			-- Start motor
			if okTeleport then
				pcall(function() harvester:startMotor(true) end)
			end

			-- Verify teleport against offset position (not field center)
			local vx, _, vz = getWorldTranslation(harvester.rootNode)
			local dx = math.abs(vx - hx)
			local dz = math.abs(vz - hz)
			if dx > 10.0 or dz > 10.0 then
				print(string.format("[IATestRunner] teleportPlayerHarvesterToField: FAILED - harvester at (%.1f, %.1f) but target was (%.1f, %.1f)", vx, vz, hx, hz))
				IATestRunner.emit("vehicle", "harvester_teleport_fail", {
					reason = "harvester did not move to target position",
					targetX = hx, targetZ = hz, actualX = vx, actualZ = vz,
					farmlandId = targetFarmlandId,
					harvesterTypeName = harvesterTypeName,
				})
			else
				print(string.format("[IATestRunner] teleportPlayerHarvesterToField: SUCCESS - %s on field %d at (%.1f, %.1f) offset=%.0fm", harvesterTypeName or "harvester", targetFarmlandId, vx, vz, playerOffset))
				IATestRunner.emit("vehicle", "harvester_teleported", {
					farmlandId = targetFarmlandId,
					neighbour = targetN.name,
					harvesterTypeName = harvesterTypeName,
					x = hx, y = ty, z = hz,
					rotation = targetRot,
					playerOffset = playerOffset,
				})
			end

	elseif atype == "positionCameraForScreenshot" then
		-- Position the player (camera) at a controlled offset relative to a target vehicle.
		-- Parameters:
		--   targetExternalId (string, required) → vehicle's externalId
		--   offsetForward    (number, default -15) → meters in vehicle's forward direction (negative = behind)
		--   offsetRight      (number, default 0)   → meters to vehicle's right
		--   offsetUp         (number, default 4)    → meters above vehicle position
		--   lookAtForward    (number, default 0)    → look-at point offset forward from vehicle center
		-- This action only positions the player; add a separate takeScreenshot action afterwards.
		if g_localPlayer == nil then return end
		if g_localPlayer.teleportTo == nil then return end
		local targetExternalId = action.targetExternalId
		if targetExternalId == nil then
			IATestRunner.emit("camera", "position_fail", { reason = "missing targetExternalId" })
			return
		end
		local offsetForward = action.offsetForward or -15
		local offsetRight = action.offsetRight or 0
		local offsetUp = action.offsetUp or 4
		local lookAtForward = action.lookAtForward or 0

		-- Find vehicle by externalId across all neighbours
		local foundIA = nil
		local foundNeighbourName = nil
		if IANeighbours ~= nil and IANeighbours.neighbours ~= nil then
			for _, n in pairs(IANeighbours.neighbours) do
				if n ~= nil and n.getVehicleByExternalId ~= nil then
					local ia = n:getVehicleByExternalId(targetExternalId)
					if ia ~= nil then
						foundIA = ia
						foundNeighbourName = n.name
						break
					end
				end
			end
		end
		if foundIA == nil then
			IATestRunner.emit("camera", "position_fail", { reason = "vehicle_not_found", externalId = targetExternalId })
			return
		end

		-- Check vehicle has a rootNode
		local rootNode = foundIA.vehicle ~= nil and foundIA.vehicle.rootNode or nil
		if rootNode == nil or not entityExists(rootNode) then
			IATestRunner.emit("camera", "position_fail", { reason = "vehicle_not_loaded", externalId = targetExternalId })
			return
		end

		-- Get vehicle world position
		local vx, vy, vz = getWorldTranslation(rootNode)

		-- Get vehicle forward direction and yaw
		local canComputeYaw = (localDirectionToWorld ~= nil and MathUtil ~= nil and MathUtil.getYRotationFromDirection ~= nil)
		local vehicleYaw = 0
		if canComputeYaw then
			local fwdX, _, fwdZ = localDirectionToWorld(rootNode, 0, 0, 1)
			vehicleYaw = MathUtil.getYRotationFromDirection(fwdX, fwdZ)
		end

		-- Compute camera world position using getWorldPositionFromYawLocalOffset
		local cameraX, cameraY, cameraZ
		if getWorldPositionFromYawLocalOffset ~= nil then
			cameraX, cameraY, cameraZ = getWorldPositionFromYawLocalOffset(
				vx, vy, vz, vehicleYaw,
				offsetRight, offsetUp, offsetForward
			)
		else
			-- Fallback: simple offset without rotation
			cameraX = vx + offsetRight
			cameraY = vy + offsetUp
			cameraZ = vz + offsetForward
		end

		-- Clamp Y to terrain height to prevent underground placement
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local th = getTerrainHeightAtWorldPos(g_terrainNode, cameraX, 0, cameraZ)
			if th ~= nil then
				cameraY = math.max(cameraY, th + 0.5)
			end
		end

		-- Teleport player to camera position
		if g_localPlayer.teleportTo ~= nil then
			-- Try FS25 API first (may silently fail)
			pcall(function() g_localPlayer:teleportTo(cameraX, cameraY, cameraZ, true, true) end)
		end
		-- Force via setWorldTranslation (this ACTUALLY works in FS25)
		if g_localPlayer.rootNode ~= nil then
			setWorldTranslation(g_localPlayer.rootNode, cameraX, cameraY + 0.1, cameraZ)
		end

		-- Compute look-at yaw/pitch to face vehicle
		local lookYaw = vehicleYaw
		local lookPitch = 0
		if canComputeYaw and getWorldPositionFromYawLocalOffset ~= nil then
			local lookX, lookY, lookZ = getWorldPositionFromYawLocalOffset(
				vx, vy, vz, vehicleYaw,
				0, 0, lookAtForward
			)
			local dx = lookX - cameraX
			local dy = lookY - cameraY
			local dz = lookZ - cameraZ
			if dx ~= 0 or dz ~= 0 then
				-- Get pitch/yaw to face the target
				local rawPitch, rawYaw = MathUtil.directionToPitchYaw(dx, dy, dz)

				-- Guard against NaN (can happen if vehicle world position is invalid)
				lookPitch = rawPitch
				lookYaw = rawYaw
				if lookPitch ~= lookPitch then
					lookPitch = -0.3 -- safe default: slight downward angle
				end
				if lookYaw ~= lookYaw then
						-- NaN guard: compute direction from camera to vehicle center
						lookYaw = MathUtil.getYRotationFromDirection(vx - cameraX, vz - cameraZ)
				end

				-- Use camera API to set the camera rotation (this actually works!)
				if g_localPlayer.camera ~= nil and g_localPlayer.camera.setRotation ~= nil then
					g_localPlayer.camera:setRotation(lookPitch, lookYaw, 0)
				else
					-- Fallback: rotate player model (less effective but better than nothing)
					if setWorldRotation ~= nil and g_localPlayer.rootNode ~= nil and entityExists(g_localPlayer.rootNode) then
						local flatYaw = MathUtil.getYRotationFromDirection(dx, dz)
						setWorldRotation(g_localPlayer.rootNode, 0, flatYaw, 0)
					else
						IATestRunner.emit("camera", "rotation_skipped", {
							reason = "no camera API and no player root node available"
						})
					end
				end
			end
		end

		IATestRunner.emit("camera", "positioned", {
			externalId = targetExternalId,
			neighbour = foundNeighbourName,
			x = cameraX,
			y = cameraY,
			z = cameraZ,
			pitch = lookPitch,
			yaw = lookYaw,
			vehicleX = vx,
			vehicleZ = vz
		})

	-- ── State Snapshots ──────────────────────────────────────────

	elseif atype == "snapshotState" then
		IATestRunner.emitStateSnapshot()

	-- ── Debug Flags ──────────────────────────────────────────────

	elseif atype == "setDebug" then
		-- Debug is always on per IANeighbours.lua line 12; this action is a no-op
		-- kept for backward compatibility with existing test scenarios.
		IATestRunner.emit("debug", "set", { debug = IANeighbours.debug })

	elseif atype == "setTimeScale" then
		IATestRunner.setTimeScale(action.scale or 1)

	-- ── Debug: Dump Neighbour Fleet ─────────────────────────────

	elseif atype == "debugDumpNeighbourFleet" then
		local nToken = action.neighbourId or action.neighbourName
		local n = nil
		if nToken ~= nil then
			n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		end
		if n == nil then
			-- Fallback to first farmer neighbour
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.job == "Farmer" and nb.role == "Neighbour" then
					n = nb
					nToken = nToken or tostring(nb.id)
					break
				end
			end
		end
		if n ~= nil then
			local vehicleCount = 0
			for _, v in pairs(n.vehicles or {}) do
				if v ~= nil then
					vehicleCount = vehicleCount + 1
					IATestRunner.emit("debug", "fleet_vehicle", {
						type = v.type,
						category = v.category,
						uniqueId = v.uniqueId,
						isBorrowedByPlayer = v.isBorrowedByPlayer,
						activeSituationId = v.activeSituationId,
					})
				end
			end
			IATestRunner.emit("debug", "fleet_summary", {
				neighbour = nToken,
				vehicleCount = vehicleCount,
			})
		else
			IATestRunner.emit("debug", "fleet_summary", {
				neighbour = "none",
				vehicleCount = 0,
			})
		end

	-- ── Assertions ──────────────────────────────────────────────

	elseif atype == "assertLogContains" then
		local cat = action.category
		local evt = action.event
		local found = false
		for _, entry in ipairs(IATestRunner._logLines) do
			if entry.cat == cat and entry.evt == evt then
				found = true
				break
			end
		end
		if not found then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", found and "pass" or "fail", {
			condition = "logContains",
			category = cat,
			event = evt,
		})

	elseif atype == "assertNeighbourState" then
		local nToken = action.neighbourId or action.neighbourName
		local n = nToken and IANeighbours:resolveNeighbourForConsoleToken(nToken) or nil
		-- Fallback: if the token-based lookup failed, scan all neighbours by name directly.
		-- This guards against state changes (e.g., schedule rebuilds) that may affect
		-- the resolver without affecting the underlying neighbour list.
		if n == nil and action.neighbourName ~= nil then
			local nameLower = string.lower(action.neighbourName)
			local neighbours = IANeighbours.neighbours or {}
			for _, nb in pairs(neighbours) do
				if nb ~= nil and nb.name ~= nil and string.lower(tostring(nb.name)) == nameLower then
					n = nb
					break
				end
			end
		end
		local field = action.field
		-- Alias-Mapping: die Snapshot-Funktion nennt das Attribut "farmlands",
		-- aber das interne Feld des neighbour-Objekts hei?t "assignedFarmlands".
		if field == "farmlands" then
			field = "assignedFarmlands"
		end
		-- Alias-Mapping: Snapshot-Funktion nennt es "scheduleTasks",
		-- das interne Feld heißt "fieldworkScheduleTasks".
		if field == "scheduleTasks" then
			field = "fieldworkScheduleTasks"
		end
		local expected = action.expected
		local ok = n ~= nil
		local actual = nil
		if ok and field ~= nil then
			-- Computed fields (not direct properties of the neighbour object)
			if field == "npcIsActive" then
				actual = (n.npcInstance ~= nil and n.npcInstance.isActive) or false
			else
				actual = n[field]
			end
			if action.condition == "nonEmpty" then
				ok = actual ~= nil and ((type(actual) == "table" and next(actual) ~= nil) or (type(actual) ~= "table" and actual ~= false and actual ~= ""))
			elseif action.condition == "equals" then
				ok = tostring(actual) == tostring(expected)
			elseif action.condition == "notNil" then
				ok = actual ~= nil
			end
		end
		if not ok then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", ok and "pass" or "fail", {
			condition = action.condition,
			field = field,
			expected = expected,
			actual = tostring(actual),
		})

	elseif atype == "assertState" then
		-- Assert on a runtime field of IANeighbours (e.g. _activeConversationKind).
		-- Supported conditions: isNil, notNil, equals, notEquals.
		local field = action.field
		local condition = action.condition or "notNil"
		local expected = action.value
		local actual = IANeighbours[field]

		local ok = true
		if condition == "isNil" then
			ok = (actual == nil)
		elseif condition == "notNil" then
			ok = (actual ~= nil)
		elseif condition == "equals" then
			ok = (tostring(actual) == tostring(expected))
		elseif condition == "notEquals" then
			ok = (tostring(actual) ~= tostring(expected))
		end

		if not ok then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", ok and "pass" or "fail", {
			condition = condition,
			field = field,
			expected = tostring(expected),
			actual = tostring(actual),
		})

	elseif atype == "assertHomebaseParking" then
		-- Validate homebase parking rules for all neighbours
		local neighbourTarget = action.neighbourId or action.neighbourName
		local checkedNeighbours = 0
		local checkedVehicles = 0
		local errors = {}

		local function check(ok, msg)
			if not ok then
				table.insert(errors, msg)
				IATestRunner._anyAssertionFailed = true
				IATestRunner.emit("test", "assert/fail", { condition = "homebaseParking", detail = msg })
			else
				IATestRunner.emit("test", "assert/pass", { condition = "homebaseParking", detail = msg })
			end
		end

		-- Determine oversize vehicle types (same as IAHomebaseParking:isOversizeVehicleType / classifyIASlotKind)
		local oversizeTypes = {
			combine = true,
			greenbeanharvesters = true,
			peaharvesters = true,
			spinachharvesters = true,
			beetharvesters = true,
			beetloading = true,
			forageharvesters = true,
		}

		local vehicleTypes = {
			car = true,
			tractor = true,
			["tractor large"] = true,
		}

		-- Try to get the parking instance for place lookup
		local parking = IANeighbours and IANeighbours.gameLoopHelper and IANeighbours.gameLoopHelper.homebaseParking
		local places = IANeighbours and IANeighbours.places or {}

		-- Iterate all neighbours
for _, n in pairs(IANeighbours.neighbours or {}) do
			if n ~= nil and n.enabled and n.initialized then
				if neighbourTarget == nil or n.name == neighbourTarget or tostring(n.id) == tostring(neighbourTarget) then
					checkedNeighbours = checkedNeighbours + 1

					for _, ia in pairs(n.vehicles or {}) do
						-- Skip vehicles in active situations
						if ia.activeSituationId == nil or ia.activeSituationId == "" then
							-- Skip hidden vehicles (couldn't get a parking spot)
							local presenceState = ia.presenceState
							if not (presenceState and presenceState.mode == "hidden") then
								checkedVehicles = checkedVehicles + 1
								local typeName = ia.typeName or "unknown"
								local typeNameLower = typeName and string.lower(tostring(typeName))
								local placeId = ia.parkingPlaceId
								local semantic = ia.parkingPlaceSemantic
								local extId = ia.externalId or ia.uniqueId

								-- Check 1: Must have a parking place assigned
								check(placeId ~= nil and placeId ~= "",
									string.format("[%s] vehicle=%s(%s) missing parkingPlaceId (semantic=%s)", n.name, extId, typeName, tostring(semantic)))

								if placeId and placeId ~= "" then
									-- Determine the kind of place by looking it up
									local placeKind = "unknown"
									for _, p in ipairs(places) do
										if p ~= nil and p.id == placeId then
											if p.sizeType ~= nil and string.lower(tostring(p.sizeType)) == "oversize_vehicle" then
												placeKind = "oversize"
											elseif p.withVehicle and not p.withAttachment then
												placeKind = "vehicle"
											elseif p.withAttachment then
												placeKind = "attachment"
											end
											break
										end
									end

									-- Check 2: Oversize vehicles must be on oversize places
									if typeNameLower and oversizeTypes[typeNameLower] then
										check(placeKind == "oversize",
											string.format("[%s] vehicle=%s(%s) OVERSIZE should be on oversize place but got kind=%s (placeId=%s)", n.name, extId, typeName, placeKind, tostring(placeId)))
									end

									-- Check 3: Regular vehicles must be on vehicle places (not oversize)
									if typeNameLower and vehicleTypes[typeNameLower] then
										check(placeKind == "vehicle",
											string.format("[%s] vehicle=%s(%s) VEHICLE should be on vehicle place but got kind=%s (placeId=%s)", n.name, extId, typeName, placeKind, tostring(placeId)))
									end

									-- Check 4: Headers must be on same place as their trailer
									local headerTrailerId = ia.headerTrailerExternalId
									if headerTrailerId and headerTrailerId ~= "" then
										local trailerIa = nil
										for _, via in pairs(n.vehicles or {}) do
											if tostring(via.externalId) == tostring(headerTrailerId) then
												trailerIa = via
												break
											end
										end
										if trailerIa then
											check(trailerIa.parkingPlaceId == ia.parkingPlaceId,
												string.format("[%s] HEADER %s(%s) on placeId=%s but TRAILER %s(%s) on placeId=%s - NOT SAME SPOT!", n.name, extId, typeName, tostring(ia.parkingPlaceId), tostring(trailerIa.externalId or trailerIa.uniqueId), tostring(trailerIa.typeName or "unknown"), tostring(trailerIa.parkingPlaceId)))
										else
											IATestRunner.emit("test", "assert/skip", { condition = "homebaseParking", detail = string.format("[%s] HEADER %s has headerTrailer=%s but trailer not found in vehicles", n.name, extId, headerTrailerId) })
										end
									end
								end
							end  -- not hidden
						end  -- activeSituationId nil/empty
					end  -- for ia in pairs(n.vehicles)
				end  -- neighbourTarget match
			end  -- n ~= nil, enabled, initialized
		end  -- for n in ipairs(neighbours)

		if #errors == 0 then
			IATestRunner.emit("test", "action", { action = "assertHomebaseParking", result = "pass", neighboursChecked = checkedNeighbours, vehiclesChecked = checkedVehicles })
		else
			IATestRunner.emit("test", "action", { action = "assertHomebaseParking", result = "fail", neighboursChecked = checkedNeighbours, vehiclesChecked = checkedVehicles, errorCount = #errors })
		end

	elseif atype == "assertAllNeighboursField" then
		local field = action.field
		-- Alias-Mappings (identisch zu assertNeighbourState)
		if field == "farmlands" then
			field = "assignedFarmlands"
		end
		if field == "scheduleTasks" then
			field = "fieldworkScheduleTasks"
		end
		local expected = action.expected
		local cond = action.condition or "notNil"
		local failedList = {}
		for _, n in pairs(IANeighbours.neighbours or {}) do
			if n ~= nil and n.initialized then
				local actual = nil
				-- Computed fields
				if field == "npcIsActive" then
					actual = (n.npcInstance ~= nil and n.npcInstance.isActive) or false
				else
					actual = n[field]
				end
				-- Condition check
				local pass = true
				if cond == "nonEmpty" then
					pass = actual ~= nil and ((type(actual) == "table" and next(actual) ~= nil) or (type(actual) ~= "table" and actual ~= false and actual ~= ""))
				elseif cond == "equals" then
					pass = tostring(actual) == tostring(expected)
				elseif cond == "notNil" then
					pass = actual ~= nil
				end
				if not pass then
					table.insert(failedList, tostring(n.name))
				end
			end
		end
		local allOk = (#failedList == 0)
		if not allOk then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", allOk and "pass" or "fail", {
			condition = cond,
			field = field,
			expected = expected,
			failedNeighbours = #failedList > 0 and table.concat(failedList, ", ") or nil,
		})

	elseif atype == "assertFarmlandNPCs" then
		-- Base-game NPC names that we want to ensure are NOT assigned to farmlands
		local BASE_GAME_NPC_NAMES = {
			["GRANDPA"] = true,
			["FORESTER"] = true,
			["FARMER"] = true,
			["HELPER"] = true,
			["ANIMAL_DEALER"] = true,
		}

		-- We only check farmlands where (isOwned == false or farmId == 99), which
		-- matches the condition used in IANeighbours:updateFarmlands(). Farmlands
		-- where isOwned == true and farmId ~= 99 are player-owned or base-game NPC
		-- farms (GRANDPA, FARMER, HELPER) and are not managed by this mod.

		local farmlands = g_farmlandManager:getFarmlands()
		local totalFarmlands = 0
		local farmlandsWithField = 0
		local skippedBaseOwnedFarmlands = 0
		local farmlandsChecked = 0
		local farmlandsWithNpc = 0
		local invalidNpcIndexCount = 0
		local baseGameNpcCount = 0
		local nilNpcCount = 0
		local noNameCount = 0
		local noImageCount = 0
		local failedFarmlandIds = {}

		for _, farmland in ipairs(farmlands or {}) do
			totalFarmlands = totalFarmlands + 1
			if farmland.field ~= nil then
				farmlandsWithField = farmlandsWithField + 1

				-- Skip farmlands owned by player or base-game NPCs (isOwned == true, farmId ~= 99)
					if farmland.isOwned == true and farmland.farmId ~= 99 then
						skippedBaseOwnedFarmlands = skippedBaseOwnedFarmlands + 1
					else
						farmlandsChecked = farmlandsChecked + 1
					local npcIndex = farmland.npcIndex

					-- Check 1: npcIndex must not be 0 or 99
					if npcIndex == nil or npcIndex == 0 or npcIndex == 99 then
						invalidNpcIndexCount = invalidNpcIndexCount + 1
						table.insert(failedFarmlandIds, tostring(farmland.id) .. "(npcIndex=" .. tostring(npcIndex) .. ")")
					else
						-- Check 2: getNPCByIndex must return a valid object
						local npc = nil
						if g_npcManager ~= nil and g_npcManager.getNPCByIndex ~= nil then
							npc = g_npcManager:getNPCByIndex(npcIndex)
						end

						if npc == nil then
							nilNpcCount = nilNpcCount + 1
							table.insert(failedFarmlandIds, tostring(farmland.id) .. "(npc=nil for index=" .. tostring(npcIndex) .. ")")
						else
							farmlandsWithNpc = farmlandsWithNpc + 1

							-- Check 3: NPC must have a name
							if npc.name == nil or npc.name == "" then
								noNameCount = noNameCount + 1
								table.insert(failedFarmlandIds, tostring(farmland.id) .. "(npc.name=nil)")
							end

							-- Check 4: NPC must have an imageFilename
							if npc.imageFilename == nil or npc.imageFilename == "" then
								noImageCount = noImageCount + 1
								table.insert(failedFarmlandIds, tostring(farmland.id) .. "(npc.imageFilename=nil)")
							end

							-- Check 5: NPC name must NOT be a base-game NPC
							if BASE_GAME_NPC_NAMES[npc.name] then
								baseGameNpcCount = baseGameNpcCount + 1
								table.insert(failedFarmlandIds, tostring(farmland.id) .. "(baseGameNPC=" .. tostring(npc.name) .. ")")
							end
						end
					end
				end
			end
		end

		local allOk = (#failedFarmlandIds == 0)
		if not allOk then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", allOk and "pass" or "fail", {
			totalFarmlands = totalFarmlands,
			farmlandsWithField = farmlandsWithField,
			skippedBaseOwnedFarmlands = skippedBaseOwnedFarmlands,
			farmlandsChecked = farmlandsChecked,
			farmlandsWithValidNpc = farmlandsWithNpc,
			invalidNpcIndexCount = invalidNpcIndexCount,
			baseGameNpcCount = baseGameNpcCount,
			nilNpcCount = nilNpcCount,
			noNameCount = noNameCount,
			noImageCount = noImageCount,
			failedFarmlandIds = #failedFarmlandIds > 0 and table.concat(failedFarmlandIds, ", ") or nil,
		})

	elseif atype == "assertNoErrors" then
		local hasError = false
		for _, entry in ipairs(IATestRunner._logLines) do
			if entry.cat == "test" and (entry.evt == "action_error" or entry.evt == "abort") then
				hasError = true
				break
			end
		end
		if hasError then
			IATestRunner._anyAssertionFailed = true
		end
		IATestRunner.emit("assert", hasError and "fail" or "pass", { condition = "noErrors" })

	elseif atype == "setSetting" then
		local key = action.key
		local val = action.value
		local valStr = tostring(val)
		if key == "missionOfferModeIndex" then
			IASettings.missionOfferModeIndex = tonumber(val) or 1
			valStr = tostring(IASettings.missionOfferModeIndex)
		elseif key == "contractCallsPerDayIndex" then
			IASettings.contractCallsPerDayIndex = tonumber(val) or 3
			valStr = tostring(IASettings.contractCallsPerDayIndex)
		elseif key == "forceOutsourceType" then
			if val ~= nil and val ~= "" then
				IATestRunner.forceOutsourceType = tostring(val)
			else
				IATestRunner.forceOutsourceType = nil
			end
			valStr = tostring(IATestRunner.forceOutsourceType or "nil")
		else
			IATestRunner.emit("action_error", "unknown_key", { key = key })
			return
		end
		IATestRunner.emit("setting", "changed", { key = key, value = valStr })
		ok = true

	-- ── Mission & Borrow Actions ─────────────────────────────────

	elseif atype == "acceptMissionWithBorrow" then
		-- Find a farmer neighbour with contract-enabled schedule tasks and accept a
		-- field-outcome mission with borrowed equipment. Uses the game loop helper
		-- to create missions and start a borrow session.
		local h = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
		if h == nil then
			IATestRunner.emit("mission", "accept_fail", { reason = "no gameLoopHelper" })
			return
		end
		local fieldworkFilter = action.fieldwork  -- optional, e.g. "grass_mowing"
		local targetN = nil
		local targetOpenList = nil
		local nid = action.neighbourId or action.neighbourName
		if nid ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nid)
		end
		if targetN == nil then
			-- First try the active phone conversation's neighbour
			local phoneNid = IANeighbours.activeStandalonePhoneNeighbourId
			if phoneNid ~= nil then
				targetN = IANeighbours:resolveNeighbourForConsoleToken(phoneNid)
			end
		end
		if targetN == nil then
			-- Find first farmer neighbour with contract-enabled schedule tasks
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.fieldworkScheduleTasks ~= nil then
					for _, row in ipairs(nb.fieldworkScheduleTasks) do
						if row ~= nil and row.contractEnabled == true then
							local matchesFilter = true
							if fieldworkFilter ~= nil then
								local rowConfig = h:findSituationConfigById(row.situationId)
								local rowFieldwork = rowConfig ~= nil and rowConfig.fieldwork ~= nil
									and string.lower(tostring(rowConfig.fieldwork)) or ""
								matchesFilter = (rowFieldwork == string.lower(tostring(fieldworkFilter)))
							end
							if matchesFilter then
								targetN = nb
								break
							end
						end
					end
					if targetN ~= nil then
						break
					end
				end
			end
		end
		if targetN == nil then
			local diagParts = {}
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour" then
					local schedLen = nb.fieldworkScheduleTasks ~= nil and #nb.fieldworkScheduleTasks or 0
					local contractCount = 0
					if nb.fieldworkScheduleTasks ~= nil then
						for _, row in ipairs(nb.fieldworkScheduleTasks) do
							if row ~= nil and row.contractEnabled == true then
								contractCount = contractCount + 1
							end
						end
					end
					local farmlandCount = nb.assignedFarmlands ~= nil and #nb.assignedFarmlands or 0
					table.insert(diagParts, string.format("%s(sch=%d,ctr=%d,fld=%d)", tostring(nb.name or "?"), schedLen, contractCount, farmlandCount))
				end
			end
			local failReason = "no neighbour with contract tasks"
			if fieldworkFilter ~= nil then
				failReason = "no neighbour with contract tasks matching fieldwork filter '" .. tostring(fieldworkFilter) .. "'"
			end
			IATestRunner.emit("mission", "accept_fail", { reason = failReason, diag = table.concat(diagParts, " ") })
			return
		end

		-- Build open fieldwork list from contract-enabled schedule rows,
		-- optionally filtered by fieldwork type
		local openList = {}
		for _, row in ipairs(targetN.fieldworkScheduleTasks) do
			if row ~= nil and row.contractEnabled == true then
				local config = h:findSituationConfigById(row.situationId)
				if config ~= nil then
					local matchesFilter = true
					if fieldworkFilter ~= nil then
						local rowFieldwork = config.fieldwork ~= nil
							and string.lower(tostring(config.fieldwork)) or ""
						matchesFilter = (rowFieldwork == string.lower(tostring(fieldworkFilter)))
					end
					if matchesFilter then
						local entry = {
							farmlandId = row.farmlandId,
							config = config,
							nextCropFruitTypeIndex = row.seedFruitTypeIndex,
							neighbourFirstName = targetN.name,
							neighbourId = targetN.id,
						}
						table.insert(openList, entry)
					end
				end
			end
		end
		if #openList == 0 then
			local failReason = "no open fieldwork rows resolved"
			if fieldworkFilter ~= nil then
				failReason = "no open fieldwork rows resolved matching fieldwork filter '" .. tostring(fieldworkFilter) .. "'"
			end
			IATestRunner.emit("mission", "accept_fail", { reason = failReason })
			return
		end

		local farmId = IABorrowAccess ~= nil and IABorrowAccess.getPlayerFarmId ~= nil
			and IABorrowAccess.getPlayerFarmId() or 1

		local maxCount = action.maxCount
		local added, started, sessionId = h:createAndRegisterFieldMissionsWithBorrow(
			targetN, openList, farmId, maxCount)

		if added == nil or added <= 0 or sessionId == nil then
			IATestRunner.emit("mission", "accept_fail", {
				reason = "createAndRegisterFieldMissionsWithBorrow returned zero missions",
				added = added or 0,
				started = started or 0,
				sessionId = tostring(sessionId or "nil"),
			})
			return
		end

		IATestRunner.emit("mission", "borrow_accepted", {
			neighbour = targetN.name,
			added = added,
			started = started,
			sessionId = tostring(sessionId),
			unitsCount = IAMissionBorrow ~= nil
				and IAMissionBorrow.getSession(sessionId) ~= nil
				and IAMissionBorrow.getSession(sessionId).borrowedUnits ~= nil
				and #IAMissionBorrow.getSession(sessionId).borrowedUnits or 0,
		})

		-- Emit borrow_session_started log event
		local session = IAMissionBorrow ~= nil and IAMissionBorrow.getSession(sessionId) or nil
		IATestRunner.emit("mission", "borrow_session_started", {
			sessionId = tostring(sessionId),
			neighbour = targetN.name,
			unitsCount = session ~= nil and session.borrowedUnits ~= nil and #session.borrowedUnits or 0,
			missionsCount = started or 0,
		})

		-- Emit borrow_unit_accepted log event for each borrowed unit
		if session ~= nil and session.borrowedUnits ~= nil then
			for _, unit in ipairs(session.borrowedUnits) do
				IATestRunner.emit("mission", "borrow_unit_accepted", {
					sessionId = tostring(sessionId),
					uniqueId = tostring(unit.uniqueId or "?"),
					vehiclePresent = tostring(unit.vehicle ~= nil),
					parkingPlaceId = tostring(unit.parkingPlaceId or "nil"),
				})
			end
		end

	elseif atype == "acceptMission" then
		-- Find a farmer neighbour with contract-enabled schedule tasks and accept a
		-- field-outcome mission without borrowed equipment. Uses the game loop helper
		-- to create missions via createAndRegisterFieldMissionsForOpenFieldworkList.
		local h = IANeighbours ~= nil and IANeighbours.gameLoopHelper or nil
		if h == nil then
			IATestRunner.emit("mission", "accept_fail", { reason = "no gameLoopHelper" })
			return
		end
		local fieldworkFilter = action.fieldwork  -- optional, e.g. "grass_mowing"
		local targetN = nil
		local targetOpenList = nil
		local nid = action.neighbourId or action.neighbourName
		if nid ~= nil then
			targetN = IANeighbours:resolveNeighbourForConsoleToken(nid)
		end
		if targetN == nil then
			-- First try the active phone conversation's neighbour
			local phoneNid = IANeighbours.activeStandalonePhoneNeighbourId
			if phoneNid ~= nil then
				targetN = IANeighbours:resolveNeighbourForConsoleToken(phoneNid)
			end
		end
		if targetN == nil then
			-- Find first farmer neighbour with contract-enabled schedule tasks
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour"
					and nb.fieldworkScheduleTasks ~= nil then
					for _, row in ipairs(nb.fieldworkScheduleTasks) do
						if row ~= nil and row.contractEnabled == true then
							local matchesFilter = true
							if fieldworkFilter ~= nil then
								local rowConfig = h:findSituationConfigById(row.situationId)
								local rowFieldwork = rowConfig ~= nil and rowConfig.fieldwork ~= nil
									and string.lower(tostring(rowConfig.fieldwork)) or ""
								matchesFilter = (rowFieldwork == string.lower(tostring(fieldworkFilter)))
							end
							if matchesFilter then
								targetN = nb
								break
							end
						end
					end
					if targetN ~= nil then
						break
					end
				end
			end
		end
		if targetN == nil then
			local diagParts = {}
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour" then
					local schedLen = nb.fieldworkScheduleTasks ~= nil and #nb.fieldworkScheduleTasks or 0
					local contractCount = 0
					if nb.fieldworkScheduleTasks ~= nil then
						for _, row in ipairs(nb.fieldworkScheduleTasks) do
							if row ~= nil and row.contractEnabled == true then
								contractCount = contractCount + 1
							end
						end
					end
					local farmlandCount = nb.assignedFarmlands ~= nil and #nb.assignedFarmlands or 0
					table.insert(diagParts, string.format("%s(sch=%d,ctr=%d,fld=%d)", tostring(nb.name or "?"), schedLen, contractCount, farmlandCount))
				end
			end
			local failReason = "no neighbour with contract tasks"
			if fieldworkFilter ~= nil then
				failReason = "no neighbour with contract tasks matching fieldwork filter '" .. tostring(fieldworkFilter) .. "'"
			end
			IATestRunner.emit("mission", "accept_fail", { reason = failReason, diag = table.concat(diagParts, " ") })
			return
		end

		-- Build open fieldwork list from contract-enabled schedule rows,
		-- optionally filtered by fieldwork type
		local openList = {}
		for _, row in ipairs(targetN.fieldworkScheduleTasks) do
			if row ~= nil and row.contractEnabled == true then
				local config = h:findSituationConfigById(row.situationId)
				if config ~= nil then
					local matchesFilter = true
					if fieldworkFilter ~= nil then
						local rowFieldwork = config.fieldwork ~= nil
							and string.lower(tostring(config.fieldwork)) or ""
						matchesFilter = (rowFieldwork == string.lower(tostring(fieldworkFilter)))
					end
					if matchesFilter then
						local entry = {
							farmlandId = row.farmlandId,
							config = config,
							nextCropFruitTypeIndex = row.seedFruitTypeIndex,
							neighbourFirstName = targetN.name,
							neighbourId = targetN.id,
						}
						table.insert(openList, entry)
					end
				end
			end
		end
		if #openList == 0 then
			local failReason = "no open fieldwork rows resolved"
			if fieldworkFilter ~= nil then
				failReason = "no open fieldwork rows resolved matching fieldwork filter '" .. tostring(fieldworkFilter) .. "'"
			end
			IATestRunner.emit("mission", "accept_fail", { reason = failReason })
			return
		end

		local farmId = IABorrowAccess ~= nil and IABorrowAccess.getPlayerFarmId ~= nil
			and IABorrowAccess.getPlayerFarmId() or 1

		local maxCount = action.maxCount

		IATestRunner.emit("mission", "accept_started", {
			neighbour = targetN.name,
			openListCount = #openList,
		})

		local added, started = h:createAndRegisterFieldMissionsForOpenFieldworkList(openList, farmId, true, maxCount)

		if added == nil or added <= 0 then
			IATestRunner.emit("mission", "accept_fail", {
				reason = "createAndRegisterFieldMissionsForOpenFieldworkList returned zero missions",
				added = added or 0,
				started = started or 0,
			})
			return
		end

		IATestRunner.emit("mission", "accept_success", {
			neighbour = targetN.name,
			added = added,
			started = started,
		})

	elseif atype == "cancelMissionBorrowSession" then
		-- Cancel/end all active borrow sessions, unborrowing vehicles back to homebase.
		if IAMissionBorrow == nil or IAMissionBorrow.sessions == nil then
			IATestRunner.emit("mission", "cancel_fail", { reason = "no borrow system" })
			return
		end
		local sessionIds = {}
		for sid, session in pairs(IAMissionBorrow.sessions) do
			if session ~= nil then
				table.insert(sessionIds, sid)
			end
		end
		if #sessionIds == 0 then
			IATestRunner.emit("mission", "cancel_none", { reason = "no active sessions" })
			return
		end

		for _, sid in ipairs(sessionIds) do
			local session = IAMissionBorrow.getSession(sid)
			if session ~= nil then
				local neighbourName = session.neighbourName or (session.neighbour ~= nil and session.neighbour.name) or "?"
				local unitsCount = session.borrowedUnits ~= nil and #session.borrowedUnits or 0
				local missionsCount = session.missions ~= nil and #session.missions or 0
				IATestRunner.emit("mission", "cancel_begin", {
					sessionId = tostring(sid),
					neighbour = neighbourName,
					unitsCount = unitsCount,
					missionsCount = missionsCount,
				})

				-- Record pre-cancel borrow state for assertions
				if session.borrowedUnits ~= nil then
					for _, ia in ipairs(session.borrowedUnits) do
						if ia ~= nil then
							IATestRunner.emit("mission", "borrow_unit_pre_cancel", {
								sessionId = tostring(sid),
								uniqueId = tostring(ia.uniqueId or "?"),
								isBorrowedByPlayer = tostring(ia.isBorrowedByPlayer),
								vehiclePresent = tostring(ia.vehicle ~= nil),
								parkingPlaceId = tostring(ia.parkingPlaceId or "nil"),
								borrowReturnParkingPlaceId = tostring(ia.borrowReturnParkingPlaceId or "nil"),
								homebaseParkingPlaceId = tostring(ia.parkingPlaceSemantic == "homebase" and ia.parkingPlaceId or "nil"),
							})
						end
					end
				end

				-- Copy missions reference before ending session (endSession clears it)
				local missions = {}
				if session.missions ~= nil then
					for _, m in ipairs(session.missions) do
						if m ~= nil then
							table.insert(missions, m)
						end
					end
				end

				-- Copy borrowed units reference before ending session
				local borrowedUnits = {}
				if session.borrowedUnits ~= nil then
					for _, ia in ipairs(session.borrowedUnits) do
						table.insert(borrowedUnits, ia)
					end
				end

				-- End the borrow session first (unborrow vehicles back to homebase)
				-- This calls unborrowSessionUnits which sets isBorrowedByPlayer = false
				IAMissionBorrow.endSession(sid, true)

				-- Record post-cancel borrow state for assertions
				for _, ia in ipairs(borrowedUnits) do
					if ia ~= nil then
						IATestRunner.emit("mission", "borrow_unit_post_cancel", {
							sessionId = tostring(sid),
							uniqueId = tostring(ia.uniqueId or "?"),
							isBorrowedByPlayer = tostring(ia.isBorrowedByPlayer),
							vehiclePresent = tostring(ia.vehicle ~= nil),
							parkingPlaceId = tostring(ia.parkingPlaceId or "nil"),
							borrowReturnParkingPlaceId = tostring(ia.borrowReturnParkingPlaceId or "nil"),
							homebaseParkingPlaceId = tostring(ia.parkingPlaceSemantic == "homebase" and ia.parkingPlaceId or "nil"),
						})
					end
				end

				-- Now stop/cancel each mission (clean game state)
				-- End session already ran, so onMissionEnded won't double-clean
				for _, mission in ipairs(missions) do
					if mission ~= nil then
						if type(mission.stop) == "function" then
							pcall(function() mission:stop() end)
						elseif type(mission.cancel) == "function" then
							pcall(function() mission:cancel() end)
						elseif type(mission.finish) == "function" and MissionFinishState ~= nil then
							pcall(function() mission:finish(MissionFinishState.CANCELED) end)
						end
					end
				end

				IATestRunner.emit("mission", "cancel_end", {
					sessionId = tostring(sid),
					neighbour = neighbourName,
				})
			end
		end

	elseif atype == "forceDeliverySpawn" then
		-- Directly test silo spawning at a neighbour's delivery point, bypassing mission pipeline
		local nToken = action.neighbourId or action.neighbourName or "1"
		local n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		if n == nil then
			-- Auto-discover first farmer neighbour
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour" then
					n = nb
					break
				end
			end
		end
		if n == nil then
			IATestRunner.emit("test", "action_error", { error = "No farmer neighbour found" })
			return
		end

		-- Find the delivery position using the delivery helper
		local fx, fy, fz, place = nil, nil, nil, nil
		if IAPlaceableHelper ~= nil and type(IAPlaceableHelper.findLargeAreaFarmPlace) == "function" then
			place = IAPlaceableHelper.findLargeAreaFarmPlace(n)
			if place ~= nil then
				fx = place.x or 0
				fy = (place.y or 0) + 1.0
				fz = place.z or 0
			end
		end

		if fx == nil then
			IATestRunner.emit("test", "action_error", { error = "No delivery farm place found for neighbour: " .. tostring(n.name) })
			return
		end

		print(string.format("[IATestRunner] forceDeliverySpawn: neighbour=%s, pos=(%.1f, %.1f, %.1f), placeId=%s",
			n.name, fx, fy, fz, tostring(place.id)))

		-- Spawn the silo
		if IAPlaceableHelper ~= nil and type(IAPlaceableHelper.spawnPlaceable) == "function" then
			local farmId = g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" and g_currentMission:getFarmId() or 1
			local rotationY = 0
			if place ~= nil and place.rotation ~= nil then
				rotationY = place.rotation
			end

			-- Store delivery position for teleportToDeliveryPoint to use later
			local helperStore = IATestRunner._deliverySpawnData or {}
			helperStore.x = fx
			helperStore.y = fy
			helperStore.z = fz
			IATestRunner._deliverySpawnData = helperStore

			IAPlaceableHelper.spawnPlaceable(
				IAFieldOutcomeDeliveryHelper.DELIVERY_SILO_XML or "data/placeables/mapUS/storage/storage.xml",
				fx, fy, fz, rotationY, farmId,
				function(placeable, errorMsg, args)
					if placeable ~= nil then
						IATestRunner.emit("delivery", "silo_spawned", {
							neighbour = n.name,
							x = fx, y = fy, z = fz,
						})
						print("[IATestRunner] Silo spawned successfully at delivery point")
					else
						IATestRunner.emit("test", "action_error", { error = "Failed to spawn silo: " .. tostring(errorMsg) })
						print("[IATestRunner] Failed to spawn silo: " .. tostring(errorMsg))
					end
				end
			)
		else
			IATestRunner.emit("test", "action_error", { error = "IAPlaceableHelper not available" })
		end

	-- ── Teleport ─────────────────────────────────────────────────

	elseif atype == "teleportPlayer" then
		-- Teleport the player to (x, y, z) for test verification
		local x = a.x or 0
		local y = a.y or 0
		local z = a.z or 0
		if g_currentMission ~= nil and g_currentMission.player ~= nil then
			local playerNode = g_currentMission.player.rootNode or g_currentMission.player.node
			if playerNode ~= nil then
				setWorldTranslation(playerNode, x, y, z)
				print(string.format("[IATestRunner] Teleported player to (%.1f, %.1f, %.1f)", x, y, z))
			else
				print("[IATestRunner] teleportPlayer: player node is nil")
			end
		else
			print("[IATestRunner] teleportPlayer: g_currentMission or player is nil")
		end

	elseif atype == "teleportToDeliveryPoint" then
		-- Teleport the player to the delivery spawn point stored by forceDeliverySpawn / spawnSiloAtCharacterLargeArea
		if IATestRunner._deliverySpawnData ~= nil then
			local spawnData = IATestRunner._deliverySpawnData
			if g_localPlayer ~= nil and g_localPlayer.teleportTo ~= nil then
				g_localPlayer:teleportTo(spawnData.x, spawnData.y, spawnData.z)
				print(string.format("[IATestRunner] Teleported to delivery point (from spawnData) (%.1f, %.1f, %.1f)", spawnData.x, spawnData.y, spawnData.z))
			elseif g_currentMission.player ~= nil then
				local playerNode = g_currentMission.player.rootNode or g_currentMission.player.node
				if playerNode ~= nil then
					setWorldTranslation(playerNode, spawnData.x, spawnData.y, spawnData.z)
					print(string.format("[IATestRunner] Teleported (fallback setWorldTranslation) to delivery point (from spawnData) (%.1f, %.1f, %.1f)", spawnData.x, spawnData.y, spawnData.z))
				end
			end
		else
			print("[IATestRunner] teleportToDeliveryPoint: no spawn data available (run forceDeliverySpawn or spawnSiloAtCharacterLargeArea first)")
		end

	elseif atype == "spawnSiloAtCharacterLargeArea" then
		-- Standalone test: spawn a silo at a character's large area farm place
		-- Parameters:
		--   neighbourId (optional) → neighbour id string
		--   neighbourName (optional) → neighbour name
		--   xmlFilename (optional) → store item XML path
		-- This bypasses the mission pipeline entirely.
		local nToken = action.neighbourId or action.neighbourName or "1"
		local n = IANeighbours:resolveNeighbourForConsoleToken(nToken)
		if n == nil then
			-- Auto-discover first farmer neighbour
			for _, nb in pairs(IANeighbours.neighbours or {}) do
				if nb ~= nil and nb.initialized and nb.job == "Farmer" and nb.role == "Neighbour" then
					n = nb; break
				end
			end
		end
		if n == nil then
			IATestRunner.emit("test", "action_error", { error = "No farmer neighbour found" })
			return
		end
		
		-- Check delivery helper is available
		if IAFieldOutcomeDeliveryHelper == nil or type(IAFieldOutcomeDeliveryHelper.spawnSiloAtCharacterLargeArea) ~= "function" then
			IATestRunner.emit("test", "action_error", { error = "IAFieldOutcomeDeliveryHelper.spawnSiloAtCharacterLargeArea not available" })
			return
		end
		
		local xmlFilename = action.xmlFilename
		
		-- Store the callback reference so teleportToDeliveryPoint can use the position
		IAFieldOutcomeDeliveryHelper.spawnSiloAtCharacterLargeArea(n, xmlFilename,
			function(placeable, errorMsg)
				if placeable ~= nil then
					-- Get position from placeable
					local px, py, pz = 0, 0, 0
					if placeable.getWorldPosition ~= nil then
						px, py, pz = placeable:getWorldPosition()
					end
					-- Store spawn data for teleportToDeliveryPoint fallback
					local helperStore = IATestRunner._deliverySpawnData or {}
					helperStore.x = px
					helperStore.y = py + 3.0  -- above terrain for player teleport
					helperStore.z = pz
					helperStore.placeable = placeable
					IATestRunner._deliverySpawnData = helperStore
					
					IATestRunner.emit("delivery", "silo_spawned", { neighbour = n.name, x = px, y = py, z = pz })
					print(string.format("[IATestRunner] silo_spawned at character '%s' large area (%.1f, %.1f, %.1f)", n.name or "?", px, py, pz))
				else
					IATestRunner.emit("test", "action_error", { error = "Failed to spawn silo: " .. tostring(errorMsg) })
					print("[IATestRunner] Failed to spawn silo: " .. tostring(errorMsg))
				end
			end
		)

	elseif atype == "cleanupDeliverySpawn" then
		-- Clean up the placeable that was spawned by spawnSiloAtCharacterLargeArea
		local spawnData = IATestRunner._deliverySpawnData
		if spawnData ~= nil and spawnData.placeable ~= nil then
			if IAPlaceableHelper ~= nil and type(IAPlaceableHelper.removePlaceable) == "function" then
				IAPlaceableHelper.removePlaceable(spawnData.placeable)
				print("[IATestRunner] Cleaned up spawned silo placeable")
			else
				print("[IATestRunner] IAPlaceableHelper.removePlaceable not available for cleanup")
			end
			IATestRunner._deliverySpawnData = nil
			IATestRunner.emit("test", "cleanupDeliverySpawn", {})
		else
			print("[IATestRunner] No delivery spawn data to clean up")
		end

	-- ── Farmer Placeables Detailed Assert ─────────────────────────

	elseif atype == "assertFarmerPlaceablesDetailed" then
		-- 1. Check FARMER_PLACEABLES exists and has 4 entries
		local placeablesTableCount = 0
		if IANeighbours.FARMER_PLACEABLES ~= nil then
			for _, _ in pairs(IANeighbours.FARMER_PLACEABLES) do
				placeablesTableCount = placeablesTableCount + 1
			end
		end
		if placeablesTableCount == 4 then
			IATestRunner.emit("assert", "pass", { field = "FARMER_PLACEABLES", expected = "4 entries", actual = tostring(placeablesTableCount) })
		else
			IATestRunner.emit("assert", "fail", { field = "FARMER_PLACEABLES", expected = "4 entries", actual = tostring(placeablesTableCount) })
			IATestRunner._anyAssertionFailed = true
		end

		-- 2. For each farmer: check placeables
		local farmerIds = { "18", "19", "20", "21" }
		for _, fid in ipairs(farmerIds) do
			local n = IANeighbours:resolveNeighbourForConsoleToken(fid)
			if n == nil then
				IATestRunner.emit("assert", "fail", { farmer = fid, field = "neighbour", expected = "exists", actual = "nil" })
				IATestRunner._anyAssertionFailed = true
			else
				-- Check neighbour.placeables exists
				local hasPlaceables = n.placeables ~= nil and next(n.placeables) ~= nil
				if hasPlaceables then
					IATestRunner.emit("assert", "pass", { farmer = n.name, field = "placeables", expected = "nonEmpty", actual = tostring(#n.placeables or "hash") })
					-- Check each placeable for uniqueId + positions
					for _, iaPl in pairs(n.placeables) do
						if iaPl ~= nil then
							local name = tostring(iaPl.xmlFilename or "unknown")
							-- uniqueId
							if iaPl.uniqueId ~= nil then
								IATestRunner.emit("placeable", "check", { farmer = n.name, placeable = name, field = "uniqueId", status = "ok", value = tostring(iaPl.uniqueId) })
							else
								IATestRunner.emit("assert", "fail", { farmer = n.name, placeable = name, field = "uniqueId", expected = "notNil", actual = "nil" })
								IATestRunner._anyAssertionFailed = true
							end
							-- positionX
							if iaPl.positionX ~= nil then
								IATestRunner.emit("placeable", "check", { farmer = n.name, placeable = name, field = "positionX", status = "ok", value = tostring(iaPl.positionX) })
							else
								IATestRunner.emit("assert", "fail", { farmer = n.name, placeable = name, field = "positionX", expected = "notNil", actual = "nil" })
								IATestRunner._anyAssertionFailed = true
							end
							-- positionY
							if iaPl.positionY ~= nil then
								IATestRunner.emit("placeable", "check", { farmer = n.name, placeable = name, field = "positionY", status = "ok", value = tostring(iaPl.positionY) })
							else
								IATestRunner.emit("assert", "fail", { farmer = n.name, placeable = name, field = "positionY", expected = "notNil", actual = "nil" })
								IATestRunner._anyAssertionFailed = true
							end
							-- positionZ
							if iaPl.positionZ ~= nil then
								IATestRunner.emit("placeable", "check", { farmer = n.name, placeable = name, field = "positionZ", status = "ok", value = tostring(iaPl.positionZ) })
							else
								IATestRunner.emit("assert", "fail", { farmer = n.name, placeable = name, field = "positionZ", expected = "notNil", actual = "nil" })
								IATestRunner._anyAssertionFailed = true
							end
						end
					end
				else
					IATestRunner.emit("assert", "fail", { farmer = n.name, field = "placeables", expected = "nonEmpty", actual = "nil or empty" })
					IATestRunner._anyAssertionFailed = true
				end
			end
		end

	-- ── Teleport To Placeable ────────────────────────────────────

	elseif atype == "teleportToPlaceable" then
		local neighbourId = action.neighbourId
		if neighbourId == nil then
			IATestRunner.emit("camera", "position_fail", { reason = "missing neighbourId" })
			return
		end
		if g_localPlayer == nil then return end

		local n = IANeighbours:resolveNeighbourForConsoleToken(neighbourId)
		if n == nil then
			IATestRunner.emit("camera", "position_fail", { reason = "neighbour_not_found", neighbourId = neighbourId })
			return
		end

		-- Find the first placeable of the neighbour
		local iaPl = nil
		if n.placeables ~= nil then
			for _, pl in pairs(n.placeables) do
				if pl ~= nil then
					iaPl = pl
					break
				end
			end
		end
		if iaPl == nil then
			IATestRunner.emit("camera", "position_fail", { reason = "no_placeables", neighbour = n.name })
			return
		end

		-- Determine placeable position: live game object or stored coordinates
		local px, py, pz, pRot
		if iaPl.placeable ~= nil and iaPl.placeable.rootNode ~= nil and entityExists(iaPl.placeable.rootNode) then
			px, py, pz = getWorldTranslation(iaPl.placeable.rootNode)
			pRot = (getNodeYawFromForward ~= nil) and getNodeYawFromForward(iaPl.placeable.rootNode) or (iaPl.rotation or 0)
		else
			px, py, pz = iaPl.positionX or 0, iaPl.positionY or 0, iaPl.positionZ or 0
			pRot = iaPl.rotation or 0
		end

		local offsetForward = action.offsetForward or -12
		local offsetRight = action.offsetRight or 5
		local offsetUp = action.offsetUp or 4

		-- Camera position calculation
		local cameraX, cameraY, cameraZ
		if getWorldPositionFromYawLocalOffset ~= nil then
			cameraX, cameraY, cameraZ = getWorldPositionFromYawLocalOffset(px, py, pz, pRot, offsetRight, offsetUp, offsetForward)
		else
			cameraX = px + offsetRight
			cameraY = py + offsetUp
			cameraZ = pz + offsetForward
		end

		-- Terrain clamping
		if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
			local th = getTerrainHeightAtWorldPos(g_terrainNode, cameraX, 0, cameraZ)
			if th ~= nil then
				cameraY = math.max(cameraY, th + 0.5)
			end
		end

		-- Teleport
		if g_localPlayer.teleportTo ~= nil then
			pcall(function() g_localPlayer:teleportTo(cameraX, cameraY, cameraZ, true, true) end)
		end
		if g_localPlayer.rootNode ~= nil then
			setWorldTranslation(g_localPlayer.rootNode, cameraX, cameraY + 0.1, cameraZ)
		end

		-- Point camera at placeable
		local lookYaw = pRot
		local lookPitch = -0.3
		if MathUtil ~= nil and MathUtil.getYRotationFromDirection ~= nil then
			local dx = px - cameraX
			local dz = pz - cameraZ
			if dx ~= 0 or dz ~= 0 then
				lookYaw = MathUtil.getYRotationFromDirection(dx, dz)
			end
		end
		if g_localPlayer.camera ~= nil and g_localPlayer.camera.setRotation ~= nil then
			pcall(function() g_localPlayer.camera:setRotation(lookPitch, lookYaw, 0) end)
		end

		IATestRunner.emit("camera", "positioned", {
			neighbour = n.name,
			neighbourId = neighbourId,
			x = cameraX, y = cameraY, z = cameraZ,
			pitch = lookPitch, yaw = lookYaw,
			placeableX = px, placeableZ = pz
		})

	-- ── Screenshot ────────────────────────────────────────────────

	elseif atype == "takeScreenshot" then
		IATestRunner.takeScreenshot()

	-- ── Advance conversation to choice point ────────────────────

	elseif atype == "advanceConversationToChoice" then
		local timeoutMs = action.timeoutMs or 60000
		local startTime = IANeighbours._wallClockSec or 0
		local maxWait = timeoutMs / 1000
		IATestRunner._waitConditionFn = function()
			local elapsed = (IANeighbours._wallClockSec or 0) - startTime
			if elapsed > maxWait then
				IATestRunner.emit("conversation", "advance_to_choice_fail", { reason = "timeout after " .. string.format("%.1f", elapsed) .. "s", timeoutMs = timeoutMs })
				return true
			end
			local conv = IANeighbours.activeStandalonePhoneConversation
			if conv == nil then
				return false
			end
			if conv.isChoicePoint then
				IATestRunner.emit("conversation", "choice_reached", { wallClockSec = IANeighbours._wallClockSec })
				return true
			end
			conv:requestAdvanceToNextLine()
			return false
		end
		IATestRunner._waitConditionLabel = "advanceConversationToChoice"

	elseif atype == "advanceConversationToEnd" then
		local timeoutMs = action.timeoutMs or 60000
		local startTime = IANeighbours._wallClockSec or 0
		local maxWait = timeoutMs / 1000
		IATestRunner._waitConditionFn = function()
			local elapsed = (IANeighbours._wallClockSec or 0) - startTime
			if elapsed > maxWait then
				IATestRunner.emit("conversation", "advance_to_end_fail", { reason = "timeout after " .. string.format("%.1f", elapsed) .. "s", timeoutMs = timeoutMs })
				return true
			end
			local conv = IANeighbours.activeStandalonePhoneConversation
			if conv == nil then
				IATestRunner.emit("conversation", "conversation_ended", { wallClockSec = IANeighbours._wallClockSec })
				return true
			end
			conv:requestAdvanceToNextLine()
			return false
		end
		IATestRunner._waitConditionLabel = "advanceConversationToEnd"

	-- ── Conversation option selection ───────────────────────────

	elseif atype == "selectOption" then
		-- Wählt eine Conversation-Option aus (für Phone- und Face-to-Face-Gespräche).
		-- Nutzt das framework-eigene _waitConditionFn-Polling statt coroutine.yield(),
		-- da coroutine in der FS25-Lua-Sandbox nicht verfügbar ist.
		local optionIndex = action.optionIndex or 1
		local conv = IANeighbours.activeStandalonePhoneConversation
		
		-- Fallback: in-world situation conversation suchen
		if conv == nil then
			for _, n in pairs(IANeighbours.neighbours or {}) do
				if n ~= nil and n.activeSituation ~= nil 
				   and n.activeSituation.conversation ~= nil then
					conv = n.activeSituation.conversation
					break
				end
			end
		end
		
		if conv == nil then
			IATestRunner.emit("conversation", "select_option_fail", { reason = "no active conversation found" })
			return
		end
		
		-- Helper: versuche eine Option auszuwählen, falls verfügbar.
		-- Returns true wenn eine Selektion stattfand (erfolgreich oder Fehler),
		-- false wenn noch keine Optionen verfügbar sind.
		local function trySelect()
			-- Check: nextOptions
			if conv.nextOptions ~= nil and #conv.nextOptions > 0 then
				if optionIndex <= #conv.nextOptions then
					local opt = conv.nextOptions[optionIndex]
					conv:selectOption(opt.id)
					IATestRunner.emit("conversation", "option_selected", {
						optionIndex = optionIndex,
						optionId = opt.id,
						optionText = opt.text,
					})
				else
					IATestRunner.emit("conversation", "select_option_fail", {
						reason = "optionIndex out of range",
						optionIndex = optionIndex,
						nextOptionsCount = #conv.nextOptions,
						mainMenuOptionsCount = conv._mainMenuOptions ~= nil and #conv._mainMenuOptions or 0,
					})
					IATestRunner._anyAssertionFailed = true
				end
				return true  -- options were available, action is done
			end
			-- Check: _mainMenuOptions
			if conv._mainMenuOptions ~= nil and #conv._mainMenuOptions > 0 then
				if optionIndex <= #conv._mainMenuOptions then
					local opt = conv._mainMenuOptions[optionIndex]
					conv:selectOption(opt.id)
					IATestRunner.emit("conversation", "option_selected", {
						optionIndex = optionIndex,
						optionId = opt.id,
						optionText = opt.text,
					})
				else
					IATestRunner.emit("conversation", "select_option_fail", {
						reason = "optionIndex out of range",
						optionIndex = optionIndex,
						nextOptionsCount = conv.nextOptions ~= nil and #conv.nextOptions or 0,
						mainMenuOptionsCount = #conv._mainMenuOptions,
					})
					IATestRunner._anyAssertionFailed = true
				end
				return true  -- options were available, action is done
			end
			return false  -- noch keine Optionen verfügbar → weiter pollen
		end
		
		-- Quick-Path: Optionen sind bereits verfügbar
		if trySelect() then
			return
		end
		
		-- Slow-Path: Setze _waitConditionFn für Frame-basiertes Polling.
		-- Der Update-Loop (onUpdate) ruft die Condition jede Frame auf.
		-- Sobald sie true zurückgibt, wird _advanceActionQueue() getriggert.
		local maxWaitSec = (action.timeoutMs or 30000) / 1000
		local deadline = (IANeighbours._wallClockSec or 0) + maxWaitSec
		IATestRunner.emit("conversation", "select_option_waiting", {
			optionIndex = optionIndex,
			timeoutSec = maxWaitSec,
		})
		
		IATestRunner._waitConditionFn = function()
			-- Timeout-Check
			if (IANeighbours._wallClockSec or 0) >= deadline then
				IATestRunner.emit("conversation", "select_option_fail", { 
					reason = "timeout waiting for options",
					timeoutSec = maxWaitSec,
					nextOptions = conv.nextOptions,
					hasMainMenu = conv._mainMenuOptions ~= nil,
				})
				IATestRunner._anyAssertionFailed = true
				return true  -- Abbruch: advance zur nächsten Action
			end
			-- Versuche Selektion
			return trySelect()
		end
		IATestRunner._waitConditionLabel = "selectOption index=" .. tostring(optionIndex)

	-- ── Unknown action ──────────────────────────────────────────

	else
		IATestRunner.emit("test", "unknown_action", { type = atype })
	end
end

-- ============================================================================
-- State Snapshot
-- ============================================================================

--- Emit a comprehensive snapshot of the current mod state.
function IATestRunner.emitStateSnapshot()
	local h, m, month, dayIn = IATestRunner.getCurrentGameTime()
	IATestRunner.emit("state", "snapshot", {
		gameHour = h,
		gameMinute = m,
		gameMonth = month,
		gameDayInPeriod = dayIn,
		timeScale = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.timeScale or nil,
		wallClockSec = IANeighbours._wallClockSec,
		outboundLoaded = IANeighbours.outboundXMLLoaded,
		blockMod = IANeighbours.BlockMod,
		neighbourCount = #(IANeighbours.neighbours or {}),
		placeCount = #(IANeighbours.places or {}),
		activeConversationKind = IANeighbours._activeConversationKind,
		hasPhonePayload = IANeighbours._incomingPhonePayload ~= nil,
	})

	-- Per-neighbour detail
	for _, n in pairs(IANeighbours.neighbours or {}) do
		if n ~= nil and n.initialized then
			local taskCount = (n.fieldworkScheduleTasks ~= nil) and #n.fieldworkScheduleTasks or 0
			local farmlandCount = (n.assignedFarmlands ~= nil) and #n.assignedFarmlands or 0
			local vehicleCount = 0
			if n.vehicles ~= nil then
				for _ in pairs(n.vehicles) do vehicleCount = vehicleCount + 1 end
			end
			IATestRunner.emit("state", "neighbour", {
				id = n.id,
				name = n.name,
				role = n.role,
				job = n.job,
				hasActiveSituation = n.activeSituation ~= nil,
				activeSituationId = n.activeSituationId,
				scheduleTasks = taskCount,
				farmlands = farmlandCount,
				vehicles = vehicleCount,
				distanceToPlayer = n.distanceToPlayer,
				callPlayerHour = n.callPlayerHour,
				callPlayerMinute = n.callPlayerMinute,
				characterVisibility = (n.activeSituation ~= nil and n.activeSituation.characterVisibility) or "none",
				npcIsActive = (n.npcInstance ~= nil and n.npcInstance.isActive) or false,
				humanModelStyleReady = n.humanModelStyleReady or false,
			})
		end
	end
end

-- ============================================================================
-- Screenshot
-- ============================================================================

--- Take a screenshot using the native FS25 engine function.
--- Emits the current game time and screenshots directory path via emit().
--- The screenshot is saved asynchronously by the engine with an auto-generated
--- filename (e.g., Screenshot_YYYY-MM-DD_HH-MM-SS.png).
function IATestRunner.takeScreenshot()
	local h, m = IATestRunner.getCurrentGameTime()
	IATestRunner.emit("screenshot", "taken", {
		gameHour = h,
		gameMinute = m,
		screenshotsDir = g_screenshotsDirectory,
		wallClockSec = IANeighbours._wallClockSec,
	})
	if takeScreenshot ~= nil then
		takeScreenshot()
	end
end

-- ============================================================================
-- Scenario Registration & Execution
-- ============================================================================

--- Register a test scenario.
--- @param table scenario  { name, description, setup, actions }
function IATestRunner.registerScenario(scenario)
	if scenario == nil or scenario.name == nil then
		return false
	end
	IATestRunner._scenarios[scenario.name] = scenario
	return true
end

--- Run a named scenario. Starts the test lifecycle and enqueues setup + actions.
--- If pre-capture is active (iaTestBeginCapture was called), reuses the existing buffer.
--- @param string name
function IATestRunner.runScenario(name)
	IATestRunner._runAllQueue = {}  -- clear any batch queue when running standalone
	local reuseBuffer = IATestRunner._preCaptureActive == true
	if reuseBuffer then
		IATestRunner._preCaptureActive = false
		IATestRunner.emit("test", "pre_capture_end", { scenario = name })
	end
	IATestRunner._runScenarioInternal(name, reuseBuffer)
end

--- Internal: run a scenario, optionally keeping the existing log buffer.
--- @param name       string
--- @param keepBuffer boolean  when true, prepend to existing log (pre-capture mode)
function IATestRunner._runScenarioInternal(name, keepBuffer)
	local scenario = IATestRunner._scenarios[name]
	if scenario == nil then
		IAprintDebug("IATestRunner", "ERROR: scenario not found: " .. tostring(name))
		IAprintDebug("IATestRunner", "Available: " .. table.concat(IATestRunner.listScenarioNames(), ", "))
		return
	end

	IATestRunner._testDescription = scenario.description
	IATestRunner._currentScenario = scenario
	--print("[FOS_TEST_DIAG] _runScenarioInternal: running '" .. tostring(name) .. "'")
	IATestRunner.beginTest(name, keepBuffer)

	-- Build the action queue: setup actions first, then main actions
	local queue = {}

	-- Debug is always on per IANeighbours.lua line 12; no toggle needed.

	-- Add snapshot at start
	table.insert(queue, { type = "snapshotState" })

	-- Add setup actions
	if scenario.setup ~= nil then
		IATestRunner._inflateSetupActions(scenario.setup, queue)
	end

	-- Add main actions
	if scenario.actions ~= nil then
		for _, act in ipairs(scenario.actions) do
			table.insert(queue, act)
		end
	end

	-- Add final snapshot
	table.insert(queue, { type = "snapshotState" })
	table.insert(queue, { type = "assertNoErrors" })

	IATestRunner._pendingActions = queue
	IATestRunner._actionIndex = 0

	IAprintDebug("IATestRunner", "RUN " .. name .. " (" .. tostring(#queue) .. " actions)")
end

--- Convert a setup block into action queue entries.
function IATestRunner._inflateSetupActions(setup, queue)
	-- Debug is always on per IANeighbours.lua line 12; no toggle needed.

	if setup.setTime ~= nil then
		table.insert(queue, {
			type = "setTime",
			hour = setup.setTime.hour,
			minute = setup.setTime.minute,
			month = setup.setTime.month,
			dayInPeriod = setup.setTime.dayInPeriod,
		})
	end

	if setup.setTimeScale ~= nil then
		table.insert(queue, { type = "setTimeScale", scale = setup.setTimeScale })
	end

	if setup.ensureOutboundLoaded then
		table.insert(queue, {
			type = "waitWallClock",
			seconds = 5,
		})
	end

	if setup.waitFrames ~= nil then
		table.insert(queue, { type = "waitFrames", frames = setup.waitFrames })
	end

	-- ensureNeighbourInitialized: wait until a specific neighbour exists and is initialized
	if setup.ensureNeighbourInitialized ~= nil then
		local targetName = setup.ensureNeighbourInitialized
		table.insert(queue, {
			type = "waitWallClock",
			seconds = 3,
			_label = "wait for neighbour init: " .. tostring(targetName),
		})
	end

	-- ensureNoActiveConversation: abort any pending phone ring
	if setup.ensureNoActiveConversation then
		if IANeighbours._incomingPhonePayload ~= nil then
			IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.PHONE_DIALOG_CLOSED)
		end
		if IANeighbours.activeStandalonePhoneConversation ~= nil then
			IANeighbours.onStandalonePhoneConversationClosed(IANeighbours.activeStandalonePhoneConversation)
		end
	end

	-- setGlobalCooldownExpired
	if setup.setGlobalCooldownExpired then
		IANeighbours._globalInboundPhoneCooldownUntilWallClockSec = 0
	end

	-- setMissionOfferMode
	if setup.setMissionOfferMode ~= nil then
		IASettings.missionOfferModeIndex = tonumber(setup.setMissionOfferMode) or 1
		IATestRunner.emit("setting", "changed", { key = "missionOfferModeIndex", value = tostring(IASettings.missionOfferModeIndex) })
	end

	-- Per-scenario timeout override (seconds)
	if setup.timeoutSeconds ~= nil then
		IATestRunner.TEST_TIMEOUT_SEC = setup.timeoutSeconds
	else
		IATestRunner.TEST_TIMEOUT_SEC = 360
	end

	-- Clear a neighbour's situation history (for first-situation tests)
	if setup.ensureNeighbourHistoryCleared ~= nil then
		local n = IANeighbours:resolveNeighbourForConsoleToken(setup.ensureNeighbourHistoryCleared)
		if n ~= nil then
			n.situationHistory = {}
			if n.activeSituation ~= nil then
				pcall(function() n.activeSituation:delete() end)
			end
			n.activeSituation = nil
			n.activeSituationId = nil
		end
	end
end

--- Run all registered scenarios in sequence. Each completes before the next starts.
function IATestRunner.runAllScenarios()
	local names = IATestRunner.listScenarioNames()
	if #names == 0 then
		IAprintDebug("IATestRunner", "No scenarios registered")
		return
	end
	IATestRunner._runAllQueue = {}
	for _, name in ipairs(names) do
		table.insert(IATestRunner._runAllQueue, name)
	end
	IAprintDebug("IATestRunner", "RUN-ALL starting " .. tostring(#names) .. " scenario(s)")
	-- Start the first one; subsequent ones auto-start in endTest()
	local firstName = table.remove(IATestRunner._runAllQueue, 1)
	IATestRunner._runScenarioInternal(firstName, false)
end

--- Begin pre-capture: start buffering logs before a specific test begins.
--- Useful for capturing mod initialization events. Call iaTestRun afterwards
--- to attach a scenario to the existing buffer.
function IATestRunner.beginPreCapture()
	if IATestRunner._testActive then
		IAprintDebug("IATestRunner", "pre-capture skipped: test already running")
		return
	end
	IATestRunner._testActive = true
	IATestRunner._testName = "(pre-capture)"
	IATestRunner._logLines = {}
	IATestRunner._wallClockStart = IANeighbours._wallClockSec or 0
	IATestRunner._preCaptureActive = true
	IATestRunner.emit("test", "pre_capture_begin", { wallClockSec = IANeighbours._wallClockSec })
	IAprintDebug("IATestRunner", "PRE-CAPTURE started — call iaTestRun <name> to attach a scenario")
end

--- List all registered scenario names.
function IATestRunner.listScenarioNames()
	local names = {}
	for name, _ in pairs(IATestRunner._scenarios) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- ============================================================================
-- Instrumentation Hooks (called by subsystems)
-- ============================================================================

--- Called by IAGameLoopHelper:rebuildDailyFieldworkSchedule when it begins.
function IATestRunner.onScheduleRebuildBegin(neighbour)
	local taskCount = 0
	if neighbour.assignedFarmlands ~= nil then
		taskCount = #neighbour.assignedFarmlands
	end
	IATestRunner.emit("schedule", "rebuild_begin", {
		neighbour = neighbour.name,
		year = neighbour.fieldworkScheduleYear,
		month = neighbour.fieldworkScheduleMonth,
		dayInPeriod = neighbour.fieldworkScheduleDayInPeriod,
		assignedFarmlands = taskCount,
	})
	IATestRunner._scheduleRebuildObserved = true
end

--- Called by IAGameLoopHelper:rebuildDailyFieldworkSchedule when it finishes.
function IATestRunner.onScheduleRebuildEnd(neighbour, outsourcedJobType)
	local taskCount = (neighbour.fieldworkScheduleTasks ~= nil) and #neighbour.fieldworkScheduleTasks or 0
	local contractCount = 0
	local aiCount = 0
	if neighbour.fieldworkScheduleTasks ~= nil then
		for _, t in ipairs(neighbour.fieldworkScheduleTasks) do
			if t.contractEnabled then
				contractCount = contractCount + 1
			else
				aiCount = aiCount + 1
			end
		end
	end
	IATestRunner.emit("schedule", "rebuild_end", {
		neighbour = neighbour.name,
		totalTasks = taskCount,
		aiTasks = aiCount,
		contractTasks = contractCount,
		outsourcedType = outsourcedJobType or "none",
		callHour = neighbour.callPlayerHour,
		callMinute = neighbour.callPlayerMinute,
	})
end

--- Called by IAGameLoopHelper:generateNewSituation when it returns a result.
function IATestRunner.onSituationGenerated(neighbour, scenarioData, source)
	if scenarioData == nil then
		IATestRunner.emit("situation", "generation_failed", {
			neighbour = neighbour and neighbour.name or "?",
			source = source or "unknown",
		})
		return
	end
	IATestRunner.emit("situation", "generated", {
		neighbour = neighbour.name,
		situationId = scenarioData.config and scenarioData.config.id or "?",
		fieldwork = scenarioData.jobType or "none",
		farmlandId = scenarioData.farmlandId,
		source = source or "unknown",
	})
end

--- Called by IASituation when loadStep changes.
function IATestRunner.onSituationLoadStepChanged(situation, newStep)
	if situation == nil then return end
	IATestRunner.emit("situation", "loadstep", {
		id = situation.id,
		step = newStep,
		jobType = situation.jobType,
		farmlandId = situation.farmlandId,
		hasVehicle = situation.vehicle ~= nil and situation.vehicle.vehicle ~= nil,
	})
end

--- Called by IASituation when it completes/expires.
function IATestRunner.onSituationComplete(situation, reason)
	if situation == nil then return end
	local neighbourName = situation.neighbour and situation.neighbour.name or "?"
	IATestRunner.emit("situation", "complete", {
		id = situation.id,
		neighbour = neighbourName,
		reason = reason or "normal",
		jobType = situation.jobType,
	})
	-- Signal completion to any waiting condition
	IATestRunner._situationCompleteObserved = true
	if situation.neighbour ~= nil then
		situation.neighbour._iaSituationJustCompleted = true
	end
end

--- Called by IANeighbours:tryShowIncomingPhoneRing when ring starts.
function IATestRunner.onPhoneRingStart(neighbour)
	IATestRunner.emit("phone", "ring_start", {
		neighbour = neighbour and neighbour.name or "?",
		wallClockSec = IANeighbours._wallClockSec,
	})
end

--- Called by IANeighbours:clearPendingIncomingPhoneOffer when ring ends.
function IATestRunner.onPhoneRingEnd(reason)
	IATestRunner.emit("phone", "ring_end", { reason = reason or "unknown" })
end

--- Called when any AI job is started for a neighbour's vehicle.
function IATestRunner.onAIJobStart(neighbour, vehicle)
	if neighbour == nil or vehicle == nil then return end
	IATestRunner.emit("ai", "job_start", {
		neighbour = neighbour.name,
		vehicleType = vehicle.type or "?",
	})
end

--- Called when any AI job stops for a neighbour's vehicle.
function IATestRunner.onAIJobStop(neighbour, vehicle, reason)
	if neighbour == nil then return end
	IATestRunner.emit("ai", "job_stop", {
		neighbour = neighbour.name,
		vehicleType = vehicle and vehicle.type or "?",
		reason = reason or "normal",
	})
end

-- ============================================================================
-- Console Command Registration
-- ============================================================================

function IATestRunner.registerConsoleCommands()
	if addConsoleCommand == nil then return end

	addConsoleCommand("iaTestRun", "Fields of Stories: run a named test scenario", "consoleCommandIaTestRun", IATestRunner, "[scenarioName]")
	addConsoleCommand("iaTestRunAll", "Fields of Stories: run all registered test scenarios in sequence", "consoleCommandIaTestRunAll", IATestRunner)
	addConsoleCommand("iaTestBeginCapture", "Fields of Stories: start buffering logs now (call iaTestRun later to attach scenario)", "consoleCommandIaTestBeginCapture", IATestRunner)
	addConsoleCommand("iaTestList", "Fields of Stories: list all registered test scenarios", "consoleCommandIaTestList", IATestRunner)
	addConsoleCommand("iaTestSnapshot", "Fields of Stories: emit a full state snapshot to the test log", "consoleCommandIaTestSnapshot", IATestRunner)
	addConsoleCommand("iaTestSaveLog", "Fields of Stories: save the last test log to modSettings", "consoleCommandIaTestSaveLog", IATestRunner)
	addConsoleCommand("iaTestAutoRun", "Fields of Stories: start the auto-run test sequence now (ignores delay)", "consoleCommandIaTestAutoRun", IATestRunner)

	IAprintDebug("IATestRunner", " Console commands: iaTestRun, iaTestRunAll, iaTestBeginCapture, iaTestList, iaTestSnapshot, iaTestSaveLog, iaTestAutoRun")
end

function IATestRunner:consoleCommandIaTestRun(scenarioName)
	if scenarioName == nil or scenarioName == "" then
		IAprintDebug("IATestRunner", " Usage: iaTestRun <scenarioName>")
		IAprintDebug("IATestRunner", " Available: " .. table.concat(IATestRunner.listScenarioNames(), ", "))
		return
	end
	IATestRunner.runScenario(scenarioName)
end

function IATestRunner:consoleCommandIaTestRunAll()
	IATestRunner.runAllScenarios()
end

function IATestRunner:consoleCommandIaTestBeginCapture()
	IATestRunner.beginPreCapture()
end

function IATestRunner:consoleCommandIaTestList()
	local names = IATestRunner.listScenarioNames()
	if #names == 0 then
		IAprintDebug("IATestRunner", " No scenarios registered.")
		return
	end
	IAprintDebug("IATestRunner", " Registered test scenarios (" .. tostring(#names) .. "):")
	for _, name in ipairs(names) do
		local s = IATestRunner._scenarios[name]
		local desc = (s.description and string.sub(s.description, 1, 80)) or "(no description)"
		IAprintDebug("IATestRunner", "  " .. name .. " — " .. desc)
	end
end

function IATestRunner:consoleCommandIaTestSnapshot()
	if not IATestRunner._testActive then
		IAprintDebug("IATestRunner", " No test active; emitting snapshot anyway.")
	end
	IATestRunner.emitStateSnapshot()
	IAprintDebug("IATestRunner", " Snapshot emitted (" .. tostring(#IATestRunner._logLines) .. " total entries)")
end

function IATestRunner:consoleCommandIaTestSaveLog()
	IATestRunner.saveLogToFile()
end

function IATestRunner:consoleCommandIaTestAutoRun()
	if IATestRegistry == nil then
		IAprintDebug("IATestRunner", " AUTO-RUN: IATestRegistry not loaded")
		return
	end
	if not IATestRegistry.hasActiveTests() then
		IAprintDebug("IATestRunner", " AUTO-RUN: no active tests in registry")
		IATestRegistry.logState()
		return
	end
	if IATestRunner._testActive then
		IAprintDebug("IATestRunner", " AUTO-RUN: waiting for active test '" .. tostring(IATestRunner._testName) .. "' to finish...")
		-- Wait: the auto-run will pick up after the current test ends via endTest
		IATestRunner._autoRunStarted = true
		IATestRunner._autoRunActive = true
		-- Build queue without running immediately
		local names = IATestRegistry.getActiveTestNames()
		IATestRunner._autoRunQueue = {}
		for _, name in ipairs(names) do
			table.insert(IATestRunner._autoRunQueue, name)
		end
		IATestRunner._autoRunIndex = 0
		IATestRunner._autoRunTotal = #names
		IAprintDebug("IATestRunner", " AUTO-RUN queued " .. tostring(#names) .. " test(s) — will start after current test ends")
		return
	end
	IATestRunner._autoRunStarted = true
	IATestRegistry.logState()
	IATestRunner._startAutoRunSequence()
end

-- ============================================================================
-- Auto-Run System (reads IATestRegistry and runs tests on game load)
-- ============================================================================

--- Called every frame from IANeighbours:update(). Checks whether it's time to
--- start the auto-run sequence based on IATestRegistry.
--- Does nothing if auto-run is already started, disabled, or no tests configured.
function IATestRunner.tryAutoRun()
	-- Guard: run only once per session — prevents per-frame re-entry and log spam
	if IATestRunner._autoRunStarted then
		--print("[FOS_TEST_DIAG] tryAutoRun: _autoRunStarted = true, skipping")
		return
	end

	-- Verbose logging (only on the very first call before the load-time is recorded)
	if IATestRegistry.verbose and IATestRunner._autoRunLoadTimeSec == nil then
		IAprintDebug("IATestRunner", "tryAutoRun() called, outboundXMLLoaded = " .. tostring(IANeighbours.outboundXMLLoaded))
		IAprintDebug("IATestRunner", "IATestRegistry.enabled = " .. tostring(IATestRegistry.enabled))
		IAprintDebug("IATestRunner", "IATestRegistry active test = " .. IATestRegistry.getActiveTestNameString())
	end
	print("[FOS_TEST_DIAG] tryAutoRun: outboundXMLLoaded=" .. tostring(IANeighbours.outboundXMLLoaded) .. ", enabled=" .. tostring(IATestRegistry and IATestRegistry.enabled) .. ", activeTest=" .. (IATestRegistry and IATestRegistry.getActiveTestNameString() or "nil"))

	-- Registry may not be loaded yet (source ordering)
	if IATestRegistry == nil then
		print("[FOS_TEST_DIAG] tryAutoRun: IATestRegistry is nil, skipping")
		return
	end

	-- Master switch off
	if not IATestRegistry.enabled then
		IATestRunner._autoRunStarted = true
		print("[FOS_TEST_DIAG] tryAutoRun: IATestRegistry.enabled = false, AUTO-RUN DISABLED")
		IAprintDebug("IATestRunner", " AUTO-RUN disabled (IATestRegistry.enabled = false)")
		return
	end

	-- No tests configured
	if not IATestRegistry.hasActiveTests() then
		IATestRunner._autoRunStarted = true
		print("[FOS_TEST_DIAG] tryAutoRun: hasActiveTests() = false, no active tests - test name='" .. tostring(IATestRegistry.getActiveTestNameString()) .. "'")
		IAprintDebug("IATestRunner", " AUTO-RUN skipped: no active tests in registry")
		return
	end

	-- Record load time on first call
	if IATestRunner._autoRunLoadTimeSec == nil then
		IATestRunner._autoRunLoadTimeSec = IANeighbours._wallClockSec or 0
		print("[FOS_TEST_DIAG] tryAutoRun: loadTimeSec=" .. tostring(IATestRunner._autoRunLoadTimeSec) .. ", will schedule in " .. tostring(IATestRegistry.startDelaySeconds) .. "s")
		IAprintDebug("IATestRunner", " AUTO-RUN scheduled in " .. tostring(IATestRegistry.startDelaySeconds) .. "s...")
		if IATestRegistry.verbose then
			IAprintDebug("IATestRunner", "Auto-run will start in " .. tostring(IATestRegistry.startDelaySeconds) .. " seconds...")
		end
		return
	end

	-- Wait for the configured delay
	local elapsed = (IANeighbours._wallClockSec or 0) - IATestRunner._autoRunLoadTimeSec
	if elapsed < (IATestRegistry.startDelaySeconds or 15) then
		print("[FOS_TEST_DIAG] tryAutoRun: elapsed=" .. tostring(elapsed) .. "s, need " .. tostring(IATestRegistry.startDelaySeconds) .. "s, waiting...")
		return
	end

	-- Don't start if a manual test is already running
	if IATestRunner._testActive then
		print("[FOS_TEST_DIAG] tryAutoRun: manual test active, deferring")
		IAprintDebug("IATestRunner", " AUTO-RUN waiting: manual test '" .. tostring(IATestRunner._testName) .. "' still active")
		return
	end

	-- Don't start if a run-all batch is in progress
	if IATestRunner._runAllQueue ~= nil and #IATestRunner._runAllQueue > 0 then
		print("[FOS_TEST_DIAG] tryAutoRun: run-all in progress, deferring")
		IAprintDebug("IATestRunner", " AUTO-RUN waiting: manual run-all in progress")
		return
	end

	print("[FOS_TEST_DIAG] tryAutoRun: ALL CHECKS PASSED, starting auto-run!")
	IATestRunner._autoRunStarted = true
	IATestRunner._startAutoRunSequence()
end

--- Build the auto-run queue and begin executing tests sequentially.
function IATestRunner._startAutoRunSequence()
	local names = IATestRegistry.getActiveTestNames()
	print("[FOS_TEST_DIAG] _startAutoRunSequence: starting " .. tostring(#names) .. " tests")
	if #names == 0 then
		IAprintDebug("IATestRunner", " AUTO-RUN: no valid test names resolved")
		IATestRunner._autoRunActive = false
		return
	end

	IATestRunner._autoRunQueue = {}
	for _, name in ipairs(names) do
		table.insert(IATestRunner._autoRunQueue, name)
	end

	IATestRunner._autoRunIndex = 0
	IATestRunner._autoRunTotal = #names
	IATestRunner._autoRunActive = true

	IAprintDebug("IATestRunner", " ========================================")
	IAprintDebug("IATestRunner", " AUTO-RUN starting " .. tostring(#names) .. " test(s)")
	IAprintDebug("IATestRunner", " Tests: " .. table.concat(names, " -> "))
	IAprintDebug("IATestRunner", " ========================================")

	if IATestRegistry.verbose then
		IAprintDebug("IATestRunner", "Starting auto-run sequence with " .. tostring(#names) .. " tests")
		for i, name in ipairs(names) do
			IAprintDebug("IATestRunner", "  Test #" .. tostring(i) .. ": " .. name)
		end
	end

	IATestRunner._runNextAutoTest()
end

--- Start the next test in the auto-run queue. Called after each test completes.
function IATestRunner._runNextAutoTest()
	if not IATestRunner._autoRunActive then
		return
	end

	--print("[FOS_TEST_DIAG] _runNextAutoTest: queue has " .. tostring(IATestRunner._autoRunQueue and #IATestRunner._autoRunQueue or 0) .. " tests remaining")
	if IATestRunner._autoRunQueue == nil or #IATestRunner._autoRunQueue == 0 then
		-- All tests completed
		IATestRunner._autoRunActive = false
		IAprintDebug("IATestRunner", " ========================================")
		IAprintDebug("IATestRunner", " AUTO-RUN complete: " .. tostring(IATestRunner._autoRunIndex) .. "/" .. tostring(IATestRunner._autoRunTotal) .. " tests finished")
		IAprintDebug("IATestRunner", " ========================================")

		-- Emit a sentinel console marker so trigger_gamestart.ps1 can detect
		-- test completion by polling log.txt, avoiding the hardcoded 600s wait.
		print("[FOS_TEST_ALL_COMPLETE]")

		return
	end

	local name = table.remove(IATestRunner._autoRunQueue, 1)
	IATestRunner._autoRunIndex = IATestRunner._autoRunIndex + 1

	IAprintDebug("IATestRunner", " AUTO-RUN [" .. tostring(IATestRunner._autoRunIndex) .. "/" .. tostring(IATestRunner._autoRunTotal) .. "] " .. name)

	if IATestRegistry.verbose then
		IAprintDebug("IATestRunner", "Now running test #" .. tostring(IATestRunner._autoRunIndex) .. ": " .. name)
	end

	-- Check that the scenario is registered
	if IATestRunner._scenarios[name] == nil then
		IAprintDebug("IATestRunner", " AUTO-RUN ERROR: scenario '" .. tostring(name) .. "' not found — skipping")
		-- Continue to next test immediately
		IATestRunner._runNextAutoTest()
		return
	end

	-- Run the scenario using the existing runner. Wrap in pcall so a crash in
	-- one test doesn't kill the entire auto-run sequence.
	local ok, err = pcall(function()
		-- Clear any batch queue and run standalone
		IATestRunner._runAllQueue = {}
		IATestRunner._runScenarioInternal(name, false)
	end)

	if not ok then
		IAprintDebug("IATestRunner", " AUTO-RUN CRASH in '" .. tostring(name) .. "': " .. tostring(err))
		-- The test didn't even start; continue with next
		IATestRunner._runNextAutoTest()
	end
end

--- Called by endTest when a test finishes during auto-run. Overrides the normal
--- endTest behavior to chain to the next auto-run test instead of letting the
--- test framework sit idle.
function IATestRunner._onAutoRunTestEnded()
	if not IATestRunner._autoRunActive then
		return
	end
	if IATestRegistry.verbose then
		-- The last test that ran is at _autoRunIndex (already incremented in _runNextAutoTest)
		local lastName = "unknown"
		if IATestRunner._autoRunTotal > 0 and IATestRunner._autoRunIndex <= IATestRunner._autoRunTotal then
			lastName = IATestRunner._testName or "unknown"
		end
		IAprintDebug("IATestRunner", "Test " .. tostring(lastName) .. " finished, advancing to next in queue")
	end
	-- Small delay between tests to let the game state settle
	IATestRunner._autoRunInterTestDelaySec = (IANeighbours._wallClockSec or 0) + 2
	IATestRunner._autoRunPendingNext = true
end

-- ============================================================================
-- JSON Helper (minimal, no external dependencies)
-- ============================================================================

--- Convert a Lua table to a compact JSON string. Handles nil, boolean,
--- number, string, and simple flat tables. No nested tables or arrays.
function IAHelper_tableToJson(tbl)
	if tbl == nil then return "null" end
	if type(tbl) == "boolean" then return tbl and "true" or "false" end
	if type(tbl) == "number" then
		if tbl == math.huge or tbl ~= tbl then return "null" end
		return string.format("%.17g", tbl):gsub("%.?0+$", "")
	end
	if type(tbl) == "string" then
		return string.format("%q", tbl)
	end
	if type(tbl) ~= "table" then return "null" end

	local parts = {}
	local first = true
	local keys = {}
	local keyMap = {}  -- tostring(k) -> original k (numeric keys survive)
	for k in pairs(tbl) do
		local ks = tostring(k)
		table.insert(keys, ks)
		keyMap[ks] = k
	end
	table.sort(keys)
	for _, ks in ipairs(keys) do
		local origKey = keyMap[ks]
		local v = tbl[origKey]
		if not first then table.insert(parts, ",") end
		first = false
		table.insert(parts, string.format("%q", ks))
		table.insert(parts, ":")
		if v == nil then
			table.insert(parts, "null")
		elseif type(v) == "boolean" then
			table.insert(parts, v and "true" or "false")
		elseif type(v) == "number" then
			if v == math.huge or v ~= v then
				table.insert(parts, "null")
			else
				local numStr = string.format("%.17g", v)
				if numStr ~= nil then
					numStr = numStr:gsub("%.?0+$", "")
					table.insert(parts, numStr)
				else
					table.insert(parts, "null")
				end
			end
		elseif type(v) == "string" then
			table.insert(parts, string.format("%q", v))
		elseif type(v) == "table" then
			table.insert(parts, string.format("%q", "[table:" .. tostring(#v) .. "]"))
		else
			table.insert(parts, "null")
		end
	end
	return "{" .. table.concat(parts, "") .. "}"
end
