--
-- IATestScenarios.lua — Registered test scenarios for Fields of Stories
--
-- Each scenario defines setup, actions, and a natural-language description
-- for AI-assisted evaluation of the captured structured log.
--
-- Scenarios are registered via IATestRunner.registerScenario() and
-- run via the iaTestRun <name> console command.
--
-- IMPORTANT: When adding/removing/renaming a test scenario here, you MUST
-- also update iaTestList.xml with the corresponding <test name="..."/> entry.
-- The XML is the source of truth for the n8n "list_tests" queue endpoint.
--

-- ============================================================================
-- Category: Schedule & Timing (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "schedule_rebuilt_at_dawn",
	description = [[
Verifies that a Farmer neighbour rebuilds their daily fieldwork schedule at 6:00.
Expected: rebuildDailyFieldworkSchedule fires, candidates collected, tasks sorted
by FIELDWORK_TYPE_PRIORITY (harvest > seed > spray > fertilize > plow > harrow > cultivate),
first tasks kept for AI, contractEnabled tasks marked, callPlayerHour/callPlayerMinute set.

All advances use the default timeScale=499 (below the 500 anti-sleep guard) so
handleActiveSituation stays active and detects the day boundary crossing at 6:00.
	]],
	setup = {
		setTime = { hour = 5, minute = 55, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "advanceGameTimeTo", hour = 6, minute = 1 },
		{ type = "waitWallClock", seconds = 10 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
		{ type = "assertLogContains", category = "schedule", event = "rebuild_begin" },
		{ type = "assertLogContains", category = "schedule", event = "rebuild_end" },
	},
})

IATestRunner.registerScenario({
	name = "schedule_respects_fieldwork_priority",
	description = [[
Verifies that FIELDWORK_TYPE_PRIORITY ordering is respected when multiple fieldwork
types are available. Harvest (priority 1) should be scheduled before seed (2) before spray (3).
Check the structured log for task ordering in the rebuild_end event.
	]],
	setup = {
		setTime = { hour = 6, minute = 0, month = 7, dayInPeriod = 1 },
		waitFrames = 30,
	},
	actions = {
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
		{ type = "assertLogContains", category = "schedule", event = "rebuild_end" },
		{ type = "assertNeighbourState", neighbourName = "Jacob Miller", field = "scheduleTasks", condition = "nonEmpty" },
	},
})

IATestRunner.registerScenario({
	name = "schedule_contract_split",
	description = [[
Verifies that the daily schedule splits tasks: AI-kept tasks (not contractEnabled) vs
contract-offered tasks (contractEnabled=true). The outsourced job type should be one
non-harvest type from the candidate set, and harvest should never be outsourced.
	]],
	setup = {
		setTime = { hour = 6, minute = 0, month = 4, dayInPeriod = 1 },
		waitFrames = 30,
	},
	actions = {
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

IATestRunner.registerScenario({
	name = "schedule_call_time_set",
	description = [[
Verifies that callPlayerHour is between 8-14 and callPlayerMinute is between 0-59
after a schedule rebuild. These are set once per game day.
	]],
	setup = {
		setTime = { hour = 6, minute = 0, month = 5, dayInPeriod = 3 },
		waitFrames = 30,
	},
	actions = {
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

IATestRunner.registerScenario({
	name = "schedule_sowing_month_keeps_all_seed_tasks",
	description = [[
When the current month is a sowing month for the planned next crop, the sowing-month
exception should keep ALL fieldwork matches on that field (deduped by job type),
rather than picking only the best one. Verify that the schedule contains multiple
task rows for the same farmland when in a sowing window.
	]],
	setup = {
		setTime = { hour = 6, minute = 0, month = 4, dayInPeriod = 1 },
		waitFrames = 30,
	},
	actions = {
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

-- ============================================================================
-- Category: Situation Generation (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "first_situation_is_relax",
	description = [[
The very first situation for any character (historyLen == 0) must be situation id 4
("relax at home"). This is a fixed rule, not random. Verify the structured log
shows source="first_relax" and situationId="4".
	]],
	setup = {
		setTime = { hour = 8, minute = 0, month = 1, dayInPeriod = 1 },
		waitFrames = 30,
		ensureNeighbourHistoryCleared = "18",
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
		{ type = "assertLogContains", category = "situation", event = "generated" },
	},
})

IATestRunner.registerScenario({
	name = "situation_fieldwork_prioritized_for_farmer",
	description = [[
A Farmer neighbour (role=Neighbour, job=Farmer) should attempt fieldwork first when
it's between 6:00 and 22:00 and historyLen > 0. The structured log should show
source="fieldwork" for the generated situation.
	]],
	setup = {
		setTime = { hour = 8, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

IATestRunner.registerScenario({
	name = "situation_fieldwork_blocked_at_night",
	description = [[
Fieldwork generation should be blocked when the hour is outside [6, 22). At 3:00 AM,
a farmer should fall back to place-based situations. Verify the generated situation
has source="place_regular" or "place_random", not "fieldwork".
	]],
	setup = {
		setTime = { hour = 3, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

IATestRunner.registerScenario({
	name = "situation_fieldwork_blocked_during_phone_ring",
	description = [[
Fieldwork generation should be paused while the neighbour is engaged with the player
(phone ring or active phone conversation). Trigger a phone ring from a farmer, then
verify that no fieldwork situation is generated for that neighbour until the call ends.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "declinePhone" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

IATestRunner.registerScenario({
	name = "situation_config_daytime_filter",
	description = [[
Situation configs with daytime=="night" should be skipped during day hours.
Configs with daytime=="day" should be skipped at night. Configs with daytime==nil
or "anytime" should match any time. The generated situation should have a config
whose daytime matches the current game time.
	]],
	setup = {
		setTime = { hour = 14, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

-- ============================================================================
-- Category: AI Job Lifecycle (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "ai_fieldwork_starts_and_runs",
	description = [[
When a fieldwork situation is generated, the AI job should start (loadStep reaches 5).
The structured log should show the situation/loadstep event with step=5.
The AI vehicle should become active.
	]],
	setup = {
		setTime = { hour = 8, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 60,
		timeoutSeconds = 3600,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 10 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

IATestRunner.registerScenario({
	name = "ai_fieldwork_completes",
	description = [[
When a fieldwork AI job finishes (field reaches target state), the situation should
complete and the structured log should show situation/complete event.

The test forces a schedule rebuild, waits for a farmer neighbour to start fieldwork,
then advances game time to 23:35. At 23:30+ the managePositioning end-of-day check
stops the AI and transitions through loadStep 6 -> 99, causing isExpired() to return
true. The handleActiveSituation 5s tick then calls delete(), which emits the
situation/complete log event via IATestRunner.onSituationComplete.
	]],
	setup = {
		setTime = { hour = 8, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 60,
		timeoutSeconds = 3600,
	},
	actions = {
		-- Rebuild schedule so farmer neighbours have fieldwork tasks.
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },

		-- Wait for a farmer neighbour to get an active fieldwork situation.
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 10 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },

		-- Advance to end of working day. At 23:30, managePositioning triggers
		-- _fieldworkCompleteFieldworkAndGoToStep6, which sets loadStep=6->99.
		-- timeScale=499 stays below the 500 anti-sleep guard so handleActiveSituation
		-- remains active.
		{ type = "advanceGameTimeTo", hour = 23, minute = 35, timeScale = 499 },
		{ type = "waitWallClock", seconds = 15 },

		-- Wait for any neighbour's completed situation to be detected.
		{ type = "waitForSituationComplete" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
		{ type = "assertLogContains", category = "situation", event = "complete" },
	},
})

-- ============================================================================
-- Category: Time Skip / Sleep (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "time_skip_pauses_generation",
	description = [[
When timeScale > 500 (sleeping), handleActiveSituation returns early and does not
generate new situations. After sleep ends (timeScale restored), generation resumes.
	]],
	setup = {
		setTime = { hour = 8, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "setTimeScale", scale = 600 },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "setTimeScale", scale = 1 },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

-- ============================================================================
-- Category: Phone System (Priority 2)
-- ============================================================================

IATestRunner.registerScenario({
	name = "phone_ring_starts_and_payload_set",
	description = [[
When tryShowIncomingPhoneRing succeeds, the structured log should show phone/ring_start.
The _incomingPhonePayload should be non-nil, ring sound should play, and an ingame
notification should be added.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		setMissionOfferMode = 2,  -- EXPLICIT: realistic mode, ensures ring is not blocked
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "declinePhone" },
	},
})

IATestRunner.registerScenario({
	name = "phone_ring_timeout_clears_payload",
	description = [[
When PENDING_INCOMING_PHONE_MAX_SEC (20s) elapses without the player answering,
the payload should be cleared with reason MISSED_TIMEOUT. Verify phone/ring_end
event appears with reason=missed_timeout.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		setMissionOfferMode = 2,  -- EXPLICIT: realistic mode, ensures ring is not blocked
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 22 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertLogContains", category = "phone", event = "ring_end" },
	},
})

IATestRunner.registerScenario({
	name = "phone_answer_starts_conversation",
	description = [[
When the player answers an incoming call, the phone conversation should start.
Verify that activeStandalonePhoneConversation is set and the conversation begins.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		setMissionOfferMode = 2,  -- EXPLICIT: realistic mode, ensures ring is not blocked
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 1 },
		{ type = "answerPhone" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

IATestRunner.registerScenario({
	name = "phone_global_cooldown_blocks_rapid_rings",
	description = [[
After an inbound phone ring is presented, GLOBAL_INBOUND_PHONE_COOLDOWN_SEC (180s)
should prevent another ring from any character. Verify that a second triggerIncomingPhoneRing
within the cooldown window fails.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		setMissionOfferMode = 2,  -- EXPLICIT: realistic mode, ensures ring is not blocked
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing", skipGlobalInboundWallClock = false },
		{ type = "waitWallClock", seconds = 1 },
		{ type = "declinePhone" },
		{ type = "triggerIncomingPhoneRing", skipGlobalInboundWallClock = false },
		{ type = "waitWallClock", seconds = 1 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

-- ============================================================================
-- Category: User Actions & Combinations (Priority 2)
-- ============================================================================

IATestRunner.registerScenario({
	name = "conversation_keybind_enables_in_range",
	description = [[
When the player is on foot within 5m of a neighbour whose characterVisibility is "yes"
or "in_car" (or npcVisibleWhilePaused), the conversation keybind should be enabled.
The refreshConversationActionEvents should switch from "phone" to "conv" state.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 60,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

IATestRunner.registerScenario({
	name = "menu_close_recovers_conversation",
	description = [[
Opening the in-game menu (ESC) during a conversation dismisses the dialog without
IAConversationDialog:onClose(). When the menu closes, onInGameMenuJustClosed should
run cleanup: close the dialog if still open, stop audio, clear active references.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 1 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "declinePhone" },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

-- ============================================================================
-- Category: Persistence (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "persistence_schedule_survives_rebuild",
	description = [[
After a schedule rebuild, the schedule fields on the neighbour should be set:
fieldworkScheduleYear, fieldworkScheduleMonth, fieldworkScheduleDayInPeriod,
fieldworkScheduleTasks, callPlayerHour, callPlayerMinute.
The task list should be non-empty if there are eligible farmlands with work.
	]],
	setup = {
		setTime = { hour = 6, minute = 5, month = 4, dayInPeriod = 1 },
		waitFrames = 30,
	},
	actions = {
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "takeScreenshot" },
		{ type = "snapshotState" },
	},
})

-- ============================================================================
-- Category: Smoke Tests (Quick)
-- ============================================================================

IATestRunner.registerScenario({
	name = "smoke_mod_loads_without_errors",
	description = [[
Basic smoke test: after outbound XML loads and neighbours initialize, there should
be no errors in the structured log. Neighbours should exist and be initialized.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 60,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertNoErrors" },
	},
})

IATestRunner.registerScenario({
	name = "smoke_update_loop_runs",
	description = [[
The mod update loop should run without errors. After waiting several frames, the
wallClockSec should be advancing and the outbound XML should be loaded.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 30,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertNoErrors" },
	},
})

-- ============================================================================
-- Category: State Snapshots (Debug)
-- ============================================================================

IATestRunner.registerScenario({
	name = "debug_full_state_snapshot",
	description = [[
Emits a full state snapshot of all neighbours, situations, farmlands, and global
state. Useful as a baseline for AI evaluation of any other test.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 60,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertNoErrors" },
	},
})

-- ============================================================================
-- Category: Persistence & Save (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "persistence_game_save_triggers_outbound",
	description = [[
Verifies that triggering a game save writes the outbound XML. The structured log
should show game/save_begin and game/save_end events. If savegameDirectory is set,
the outbound file should be written. All debug output during save is captured.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "triggerGameSave" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertLogContains", category = "game", event = "save_begin" },
		{ type = "assertLogContains", category = "game", event = "save_end" },
	},
})

-- ============================================================================
-- Category: Conversation & User Interaction (Priority 2)
-- ============================================================================

IATestRunner.registerScenario({
	name = "conversation_start_near_neighbour",
	description = [[
Teleports the player near a neighbour with an active situation (characterVisibility
"yes" or npcVisibleWhilePaused), waits for the mod to detect the nearby situation,
then triggers startConversation. Asserts that conversation/started (not phone_opened)
appears in the log. All IAprintDebug output (including conversation text) is captured
via the emitDebug bridge.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 60,
	},
	actions = {
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "forceSituation", neighbourId = "18", situationId = "46" },
		{ type = "waitWallClock", seconds = 8 },
		{ type = "teleportPlayerToNeighbour", neighbourId = "18" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "startConversation" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "takeScreenshot" },
		{ type = "assertLogContains", category = "conversation", event = "started" },
		{ type = "snapshotState" },
	},
	cleanup = {
		{ type = "closeDialog" },
		{ type = "setTimeScale", scale = 5 },
	},
})

IATestRunner.registerScenario({
	name = "phone_opens_when_no_neighbour",
	description = [[
When startConversation is triggered with no neighbour in range, the phone should
open instead. Verify conversation/phone_opened event appears.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 30,
	},
	actions = {
		{ type = "startConversation" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

IATestRunner.registerScenario({
	name = "full_phone_ring_answer_conversation",
	description = [[
End-to-end phone flow: ring starts, player answers, conversation begins. The
structured log should capture the full sequence: phone/ring_start, phone/answer,
conversation text via emitDebug (IAprintDebug bridge). Verify all events appear
in correct order.
	]],
	setup = {
		setTime = { hour = 10, minute = 0, month = 4, dayInPeriod = 2 },
		setGlobalCooldownExpired = true,
		ensureNoActiveConversation = true,
		waitFrames = 30,
	},
	actions = {
		{ type = "triggerIncomingPhoneRing" },
		{ type = "waitWallClock", seconds = 1 },
		{ type = "answerPhone" },
		{ type = "waitWallClock", seconds = 5 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
	},
})

-- ============================================================================
-- Category: Pre-Capture (Mod Load to Test)
-- ============================================================================

IATestRunner.registerScenario({
	name = "precapture_mod_initialization",
	description = [[
This scenario is designed to be used with iaTestBeginCapture called right after
the mod loads. Call iaTestBeginCapture first, then iaTestRun precapture_mod_initialization.
The combined log will contain all mod initialization events (outbound load, neighbour
creation, first situations) plus the test actions. This gives the AI full visibility
into the complete mod lifecycle from load to first situation.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 120,
	},
	actions = {
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "waitForNeighbourSituation" },
		{ type = "waitWallClock", seconds = 10 },
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		{ type = "assertNoErrors" },
	},
})

-- ============================================================================
-- Category: Mission Offer Mode
-- ============================================================================

IATestRunner.registerScenario({
	name = "mission_offer_classic_skips_calls_keeps_missions",
	description = [[
Classic mission offer mode: sets mode to classic, verifies that phone calls are NOT
initiated and that standard vanilla missions remain on farmlands when a new game day arrives.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 60,
		setMissionOfferMode = 1,   -- classic mode
	},
	actions = {
		-- Snapshot initial state (classic mode already set in setup)
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },
		
		-- Advance to next game day (6:00 AM) at high speed to trigger natural rebuild
		{ type = "advanceGameTimeTo", hour = 6, minute = 0, timeScale = 499 },
		
		-- Wait for the dawn schedule rebuild to fire naturally
		{ type = "waitForScheduleRebuild" },
		
		-- Snapshot after rebuild (missions should still be on farmlands)
		{ type = "snapshotState" },
		
		-- Try to trigger a phone ring - should be BLOCKED in classic mode
		{ type = "triggerIncomingPhoneRing" },
		
		-- Take snapshot - ring should have been BLOCKED (no payload)
		{ type = "snapshotState" },
		{ type = "assertLogContains", category = "phone", event = "ring_triggered" },
		{ type = "takeScreenshot" },
		
		-- Assert the ring was blocked (ring_triggered with ok=false)
		{ type = "assertNoErrors" },
		
		-- Advance to NEXT day (to trigger another rebuild cycle)
		{ type = "advanceGameTimeTo", hour = 6, minute = 0, timeScale = 499 },
		
		-- Wait for rebuild
		{ type = "waitForScheduleRebuild" },
		
		-- Final snapshot - should show farmlands with missions intact
		{ type = "snapshotState" },
		{ type = "assertNeighbourState", neighbourName = "Brian Winter", field = "farmlands", condition = "nonEmpty" },
		{ type = "takeScreenshot" },
		
		-- Assert no errors throughout
		{ type = "assertNoErrors" },
	},
})

IATestRunner.registerScenario({
	name = "mission_offer_realistic_allows_calls_removes_missions",
	description = [[
Realistic mission offer mode: sets mode to realistic, verifies that natural contract phone
calls ARE initiated and that standard vanilla missions are removed from farmlands.
	]],
	setup = {
		ensureOutboundLoaded = true,
		waitFrames = 60,
		setMissionOfferMode = 2,   -- realistic mode
	},
	actions = {
		-- Snapshot initial state (realistic mode already set)
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Advance to next game day (6:00 AM) at high speed to trigger natural rebuild
		{ type = "advanceGameTimeTo", hour = 6, minute = 0, timeScale = 499 },

		-- Wait for the dawn schedule rebuild to fire naturally
		{ type = "waitForScheduleRebuild" },

		-- Snapshot after rebuild (missions should be removed from farmlands)
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Try to trigger a phone ring - should WORK in realistic mode
		{ type = "triggerIncomingPhoneRing" },
		
		-- Take snapshot - ring should have payload
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Advance to NEXT day (to trigger another rebuild cycle)
		{ type = "advanceGameTimeTo", hour = 6, minute = 0, timeScale = 499 },

		-- Wait for rebuild
		{ type = "waitForScheduleRebuild" },

		-- Final snapshot
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Assert no errors throughout
		{ type = "assertNoErrors" },
	},
})

-- ============================================================================
-- Category: Mission Borrow Lifecycle (Priority 1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "cancel_mission_returns_borrowed_vehicle_to_homebase",
	description = [[
Verifies the full borrow lifecycle (accept → cancel) for a field-outcome mission
with borrowed equipment. The borrowed vehicle is acquired when the mission is accepted
and unborrowed (returned to the neighbour's homebase parking spot) when cancelled.

The test:
  1. Uses forceScheduleRebuild in realistic mission offer mode to ensure
     contract-enabled schedule tasks exist.
  2. Accepts a field-outcome mission with borrowed equipment.
  3. Asserts borrow_accepted, borrow_session_started, and borrow_unit_accepted
     (vehicle is now borrowed by player, isBorrowedByPlayer=true).
  4. Takes a state snapshot to capture the borrow state.
  5. Cancels the mission borrow session (simulating player cancelling the contract).
  6. Asserts borrow_unit_pre_cancel (vehicle was borrowed before cancel),
     cancel_begin, cancel_end, and borrow_unit_post_cancel (vehicle no longer
     borrowed, returned to homebase).
  7. Takes a final state snapshot and asserts no errors throughout.
	]],
	setup = {
		setTime = { hour = 6, minute = 0, month = 4, dayInPeriod = 1 },
		setMissionOfferMode = 2,   -- realistic mode (contract calls enabled)
		waitFrames = 60,
	},
	actions = {
		-- Rebuild schedule to generate contract-enabled tasks
		{ type = "forceScheduleRebuild" },
		{ type = "waitWallClock", seconds = 3 },

		-- Snapshot before accepting
		{ type = "snapshotState" },

		-- Accept a mission with borrowed equipment
		{ type = "acceptMissionWithBorrow" },
		{ type = "waitWallClock", seconds = 3 },

		-- Assert that borrow acceptance events occurred
		{ type = "assertLogContains", category = "mission", event = "borrow_accepted" },
		{ type = "assertLogContains", category = "mission", event = "borrow_session_started" },
		{ type = "assertLogContains", category = "mission", event = "borrow_unit_accepted" },

		-- Snapshot after borrow (vehicle should be borrowed now)
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Cancel the mission borrow session (simulates player cancelling the contract)
		{ type = "cancelMissionBorrowSession" },
		{ type = "waitWallClock", seconds = 3 },

		-- Assert that borrow cancel events occurred
		{ type = "assertLogContains", category = "mission", event = "cancel_begin" },
		{ type = "assertLogContains", category = "mission", event = "borrow_unit_pre_cancel" },
		{ type = "assertLogContains", category = "mission", event = "cancel_end" },
		{ type = "assertLogContains", category = "mission", event = "borrow_unit_post_cancel" },

		-- Snapshot after cancel (vehicle should be unborrowed, back at homebase)
		{ type = "snapshotState" },
		{ type = "takeScreenshot" },

		-- Assert no errors during the entire flow
		{ type = "assertNoErrors" },
	},
})

-- ============================================================================
-- Category: Conversation Window Tests (Priority 2)
-- ============================================================================

IATestRunner.registerScenario({
	name = "conversation_window_general",
	description = [[
Tests the general conversation window flow: teleport to a neighbour, start a
conversation, verify it opens, let dialog play out to the main menu, then select
an option and verify the conversation state changes accordingly. Captures state
snapshots before and after option selection for AI evaluation.
	]],
	setup = {
		ensureDebug = true,
		ensureOutboundLoaded = true,
		ensureNeighbourInitialized = true,
		setTime = { hour = 16, minute = 0 },
		setGlobalCooldownExpired = true,
		timeoutSeconds = 600,
	},
	actions = {
		{ type = "waitWallClock", seconds = 10 },
		{ type = "forceSituation", neighbourId = "18", situationId = "4" },
		{ type = "waitWallClock", seconds = 15 },
		{ type = "teleportPlayerToNeighbour", neighbourId = "18" },
		{ type = "waitWallClock", seconds = 3 },
		{ type = "startConversation" },
		{ type = "waitWallClock", seconds = 2 },
		{ type = "takeScreenshot" },                  -- capture dialog open state
		{ type = "assertLogContains", category = "conversation", event = "started" },
		{ type = "waitWallClock", seconds = 12 },  -- let conversation progress to main menu
		{ type = "snapshotState" },
		{ type = "selectOption", optionIndex = 1 },  -- select first option (usually a smalltalk)
		{ type = "waitWallClock", seconds = 5 },     -- let option play out
		{ type = "takeScreenshot" },                  -- capture after option selection
		{ type = "snapshotState" },                  -- capture post-option state
	},
	cleanup = {
		{ type = "closeDialog" },
		{ type = "setTimeScale", scale = 5 },
	},
})

-- ============================================================================
-- Category: NPC Visibility & Deferred Spawn (P1)
-- ============================================================================

IATestRunner.registerScenario({
	name = "all_neighbours_visible_after_relax",
	description = [[
Forces ALL neighbours into situation 4 (relax at home) with characterVisibility="yes",
then waits for every neighbour's NPC to actually become visible (npcInstance.isActive=true
AND humanModelStyleReady=true). This verifies that the bidirectional visibility enforcer
correctly retries showNPC() when models load asynchronously, rather than silently failing
and leaving characters invisible forever.

The state snapshot at the end contains npcIsActive and humanModelStyleReady per neighbour,
which can be asserted against to confirm all characters are visibly spawned.
	]],
	setup = {
		--setTime = { hour = 12, minute = 0, month = 4, dayInPeriod = 2 },
		waitFrames = 60,
		timeoutSeconds = 300,
	},
	actions = {
		{ type = "forceAllNeighboursSituation", situationId = "4" },
		{ type = "waitWallClock", seconds = 20 },
		{ type = "assertAllNeighboursField", field = "npcIsActive", condition = "equals", expected = "true" },
		{ type = "snapshotState" },
		{ type = "assertNoErrors" },
	},
})

IATestRunner.registerScenario({
	name = "farmland_npcs_registered",
	description = [[
Prüft dass jedes NPC-owned farmland mit Feldern einen korrekten NPC zugewiesen hat
(Indices 6-9 oder höher). Player-Farmlands und Farmlands ohne Felder werden nicht
geprüft, da diese Base-Game-NPCs (GRANDPA, FARMER, HELPER) verwenden.
	]],
	setup = {
		waitFrames = 60,
	},
	actions = {
		{ type = "waitWallClock", seconds = 10 },
		{ type = "assertNoErrors" },
		{ type = "assertFarmlandNPCs" },
		{ type = "assertNoErrors" },
	},
	expectedResults = {
		{ description = "Jedes NPC-owned farmland mit Feldern hat npcIndex im gültigen Bereich (nicht 0 oder 99)" },
		{ description = "g_npcManager:getNPCByIndex(npcIndex) liefert gültiges Objekt" },
		{ description = "NPC hat name und imageFilename gesetzt" },
		{ description = "NPC-Name ist KEIN Base-Game-NPC (GRANDPA, FARMER, FORESTER, HELPER, ANIMAL_DEALER)" },
		{ description = "Player-Farmlands und Farmlands ohne Felder werden nicht geprüft" },
	},
})
