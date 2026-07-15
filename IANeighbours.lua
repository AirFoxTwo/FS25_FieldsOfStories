--
-- FS25 - InteractiveNeighbours
--
-- @Interface: 1.0.0.1
-- @Author: AirFoxTwo
-- @Date: 27.06.2026
-- @Version: 1.0.0.1

IANeighbours = {}
IANeighbours.dir = g_currentModDirectory
IANeighbours.modName = g_currentModName
IANeighbours.debug = false
--- When true, the frame/function profiling (inline IANeighbours:update timer + wrapped "main" functions)
--- is active. When false, none of it is installed: no getTimeSec calls, no function wrapping, no logging.
IANeighbours.debugPerformance = false
IANeighbours.inboundXML = nil
IANeighbours.neighbours = {}
IANeighbours.places = {}
IANeighbours.situationConfigs = {}
IANeighbours.autoDrive = nil
IANeighbours.activeDialog = nil
IANeighbours.activeDialogText = ""
--- Combined on-foot SHIFT+R action event (InputAction.IAStartConversation). The displayed HUD label is
--- refreshed between "Start Conversation" and "Use Phone"; the Controls/keybind menu label stays combined.
IANeighbours.conversationKeybind = nil
IANeighbours.conversationActionEventTarget = nil
--- Optional in-vehicle SHIFT+R action event registered from the vehicle action-event context, for opening the phone while seated.
IANeighbours.vehiclePhoneKeybind = nil
--- Deprecated: the phone no longer has its own separate InputAction binding.
IANeighbours.usePhoneKeybind = nil
--- "conv"|"phone" — last computed availability hint. See refreshConversationActionEvents.
IANeighbours._conversationActionEventsState = nil
--- Previous frame isIncomingPhoneSessionActive(); used to force a SHIFT+R prompt re-register when a call ends.
IANeighbours._prevPhoneSessionActiveForPrompt = false
IANeighbours.canStartConversation = false
--- Previous frame g_inGameMenu.isOpen; used to run conversation GUI cleanup when the menu closes.
IANeighbours._prevInGameMenuOpen = false
IANeighbours.vehicleIdMapping = {} -- Maps externalId -> uniqueId
IANeighbours.debugPoints = {}
IANeighbours.savegameEventsBound = false
IANeighbours.outboundXMLLoaded = false  -- Flag to track if outbound XML has been loaded once
IANeighbours.BlockMod = false
--- Reset in loadMap(SP). First updateFarmlands with a resolvable field list strips vanilla NPC field missions (ownerFarmId 0); FoS missions kept.
IANeighbours.didStripVanillaFieldMissionsOnLoad = false
--- First-time-only: after farmlands are assigned to Farmer neighbours on a brand-new save, foreign crops
--- (not in IAFieldwork.CHARACTER_HARVEST_FRUIT_NAMES) on those fields are normalized to wheat (harvest-ready).
--- DISABLED: set to true to leave field state unchanged on initial farmland assignment.
IANeighbours.didNormalizeAssignedFieldCropsOnFirstLoad = true
IANeighbours.mapInitJobRun = false  -- When true, map-init mode is active for missing map config (no vehicle spawn)
IANeighbours.pendingMapPlacesBootstrap = false  -- No map config: wait for user OK in IAMapPlacesGenDialogGUI before heavy place generation
IANeighbours.mapPlacesBootstrapDialogShown = false  -- true after showDialog queued successfully (retry if show failed)
IANeighbours.firstLoadTutorialDialogShown = false -- true after showDialog queued successfully
-- Voice pack: expected version in modSettings/.../conversations/voice_pack_version.xml (see loadData check in IAXMLHelper)
IANeighbours.requiredVoicePackVersion = "1.1.0"
IANeighbours.pendingVoicePackWarning = false
IANeighbours.voicePackWarningNotificationShown = false
--- True after voice_pack_version.xml matches requiredVoicePackVersion; false until check runs or on mismatch/missing. IAConversation skips audio when false.
IANeighbours.voicePackLoaded = false
--- "de" or "en" from voice_pack_version.xml#language when voicePackLoaded; nil = use game language for mod text/voice file prefix.
IANeighbours.voicePackLanguage = nil
--- True while map-init place markers (all places) are shown on the world; toggled from the Map Init dialog.
IANeighbours.mapInitPlaceMarkersVisible = false
--- When true, draw debug markers every frame at each mod neighbour vehicle/attachment world position (any visibility/state). Toggle: `iaToggleVehiclePresenceDebug`.
IANeighbours.debugVehiclePresencePositions = false
--- When true, draw field-border / spawn-alignment debug points for every active fieldwork situation (map-wide, no range limit). Toggle: `iaToggleFieldworkBorderDebug`.
IANeighbours.debugFieldworkBorderGeometry = false
--- When true, draw FoS phone field-outcome mission probe markers (V/I samples). Toggle: `iaToggleFieldMissionProbeDebug`.
IANeighbours.debugFieldMissionProbes = false
--- Per-frame profiling: when IANeighbours:update wall-clock time exceeds this many ms, the elapsed time is printed.
--- Set to nil to always print, or to a large value to effectively disable.
IANeighbours.frameTimeLogThresholdMs = 2
-- Map-init debug: wireframe sphere radius (visual only; overlapSphere for blocking still uses PLACE_COLLISION_CHECK_RADIUS).
IANeighbours.collisionProbeSpheres = {}
IANeighbours.DebugAiFarmId = nil
-- On-foot situation: public_place parking slots reserved this frame (see isPlaceBlocked forPublicPlaceParkingSelection + reserveRoadsideParkingSlot) to avoid multiple NPCs at same map place
IANeighbours.roadsideParkingReservedKeys = {}

-- Cached PlayerStyle configs for HumanModel neighbours (copyConfigurationFrom per spawn; cleared on remove-mod).
IANeighbours.maleStyleTemplate = nil
IANeighbours.femaleStyleTemplate = nil

-- Overlay atlases for neighbour PlaceableHotspot icons (registered once in loadMap).
IANeighbours._iaNpcMapHotspotMainRegistered = false
IANeighbours._iaNpcMapHotspotSmallRegistered = false

-- When true, user requested "Remove Mod" from the UI. We disable the mod loop and remove runtime objects.
IANeighbours.removeModRequested = false

-- Subsystems and input: set in loadMap / registerActionEvent (nil until then).
IANeighbours.xmlHelper = nil
IANeighbours.placesLoader = nil
IANeighbours.gameLoopHelper = nil
--- Set when an incoming phone ring is scheduled (cleared on Answer/Decline or dialog close).
IANeighbours.pendingIncomingPhoneNeighbourId = nil
--- While IAPhoneDialogGUI is open (incoming UI or idle phone opened by keybind).
IANeighbours.incomingPhoneRingDialogOpen = false
--- True after gui/IAPhoneTexture.xml was registered with g_overlayManager (imageSliceId iaPhone.*).
IANeighbours._phoneGuiTextureRegistered = false
--- { neighbourId, neighbourName?, conversation } while an incoming call is pending or the phone UI is open; built before the ring sound / Answer flow.
IANeighbours._incomingPhonePayload = nil
--- Standalone phone IAConversation (no IASituation); updated in IANeighbours:update after Answer.
IANeighbours.activeStandalonePhoneConversation = nil
IANeighbours._incomingCallRingSample = nil
--- Wall-clock (`IANeighbours._wallClockSec`) when unanswered `_incomingPhonePayload` was set in `tryShowIncomingPhoneRing`.
IANeighbours._pendingIncomingPhoneStartedWallClockSec = nil
--- Real-time cap for an unanswered pending offer; after this, payload clears (ring stopped by `clearPendingIncomingPhoneOffer`).
IANeighbours.PENDING_INCOMING_PHONE_MAX_SEC = 20
--- `playSample` loop count for `sound/incoming_call.ogg`. **0** = repeat the clip until `stopIncomingCallRingSound()` (ring runs for the full `PENDING_INCOMING_PHONE_MAX_SEC` window). Set to **1** for a single play-through only. Per-loop duration = length of the `.ogg` in your DAW.
IANeighbours.INCOMING_CALL_RING_SAMPLE_LOOPS = 2
--- Passed to `clearPendingIncomingPhoneOffer` (missed = not answered; others = explicit player / UI actions).
IANeighbours.IncomingCallEndReason = {
	MISSED_RING_FINISHED = "missed_ring_finished",
	MISSED_TIMEOUT = "missed_timeout",
	ANSWERED = "answered",
	DECLINED = "declined",
	PHONE_DIALOG_CLOSED = "phone_dialog_closed",
}
--- Refreshed by refreshActiveConversationState(): nil | "phone_ring" | "phone" | "personal"
IANeighbours._activeConversationKind = nil
--- When _activeConversationKind is "personal", "phone" or "phone_ring", which neighbour the player is engaged with.
IANeighbours._activeConversationNeighbourId = nil
--- Set in answerIncomingPhoneFromPayload, cleared in onStandalonePhoneConversationClosed.
IANeighbours.activeStandalonePhoneNeighbourId = nil
--- Monotonic seconds from `dt` in update() (`dt` is milliseconds per frame here, same as gameMs / IAConversation; not game time).
IANeighbours._wallClockSec = 0
--- Minimum real seconds between inbound phone rings (any character).
IANeighbours.GLOBAL_INBOUND_PHONE_COOLDOWN_SEC = 180
--- Inbound phone may open again once `_wallClockSec` reaches this value (any character).
IANeighbours._globalInboundPhoneCooldownUntilWallClockSec = IANeighbours.GLOBAL_INBOUND_PHONE_COOLDOWN_SEC

IANeighbours.mapInitJob = nil
IANeighbours.mapInitDialogKeybind = nil
IANeighbours.mapNodesDebugKeybind = nil
IANeighbours.mapNodeFocusKeybind = nil
IANeighbours.mapNodeFocusBackKeybind = nil
IANeighbours.mapNodeFocusNextI3dKeybind = nil
IANeighbours.nearbySituation = nil

-- Per-frame counters and XML sync timers (incremented in update).
IANeighbours.gameMs = 0
IANeighbours.gameSeconds = 0
IANeighbours.inboundLoadTimer = 30000  -- Timer for inbound XML loading
IANeighbours.inboundLoadInterval = 30000  -- Load inbound XML every 30 seconds (or when trigger file found)
IANeighbours.outboundSaveTimer = 0  -- Timer for outbound XML saving
IANeighbours.outboundSaveInterval = 30000  -- Save outbound XML every 30 seconds
IANeighbours.inboundCheckTimer = 0
IANeighbours.inboundCheckInterval = 1000  -- Check outbound XML trigger file every 1 second
IANeighbours.lastInboundFileTime = nil  -- Track last known file modification time
IANeighbours.lastInboundFileHash = nil  -- Track last known file content hash (fallback)
IANeighbours.lastOutboundFileTime = nil  -- Track last known outbound file modification time

-- Place corner rectangle: 2m front, variable back (box length = front + back). FS convention: rotation 0 = forward is -Z.
IANeighbours.PLACE_DEBUG_FRONT_M = 3
IANeighbours.PLACE_DEBUG_SIDE_M = 1.5
IANeighbours.PLACE_DEBUG_BOX_LENGTH_VEHICLE = 6   -- box length when withVehicle true, withAttachment false
IANeighbours.PLACE_DEBUG_BOX_LENGTH_ATTACH = 15  -- box length when withAttachment true
IANeighbours.PLACE_DEBUG_BOX_LENGTH_OVERSIZE = 10  -- box length when sizeType == "oversize_vehicle" (bigger than vehicle+attachment)
IANeighbours.PLACE_DEBUG_BOX_LENGTH_LARGE_AREA = 22.5  -- box length when sizeType == "large_area" (vehicle+attachment length + 50%)
IANeighbours.PLACE_DEBUG_SIDE_LARGE_AREA = 4.5    -- box half-width when sizeType == "large_area" (3x PLACE_DEBUG_SIDE_M)
--- For vehicle+attachment places: two extra collision probes along local −Z (rear of debug box), at this fraction of the back segment length (center→rear edge). Matches IAHelper_computePlaceDebugBoxCorners back = boxLength − PLACE_DEBUG_FRONT_M.
IANeighbours.PLACE_ATTACH_BACK_PROBE_FRACTIONS = { 1 / 4, 2 / 4, 3 / 4 }
IANeighbours.mapInitPlaceDebugParents = {}  -- legacy: { parentNode } per place (corner boxes now drawn as lines, not scene nodes)
IANeighbours.mapInitPlaceDebugBoxes = {}    -- { corners = {{x,y,z} x4}, centerX, centerY, centerZ } drawn per-frame as connected lines (borrow-return box style)

--- Default radius (m) for place collision check - small sphere at place position.
IANeighbours.PLACE_COLLISION_CHECK_RADIUS = 0.5

--- Radius (m) for character-only places (withVehicle==false and withAttachment==false): smaller probe + smaller displayed sphere.
IANeighbours.PLACE_COLLISION_CHECK_RADIUS_CHARACTER_ONLY = 0.4

--- Wireframe debug sphere radius (m) at map-init place centers when IANeighbours.debug; visual only, not used for overlapSphere blocking.
IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_M = 2.5

--- Wireframe debug sphere radius (m) for character-only places (withVehicle==false and withAttachment==false).
IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_CHARACTER_ONLY_M = 0.4

--- Wider sphere (m) for on-foot public_place parking selection only (isPlaceBlocked with forPublicPlaceParkingSelection); detects parked vehicles better than PLACE_COLLISION_CHECK_RADIUS.
IANeighbours.ROADSIDE_PARKING_OCCUPANCY_RADIUS_M = 3.5

--- Collision filter groups (from i3d collisionFilterGroup via getCollisionFilterGroup) to exclude from place blocking after overlap - e.g. sidewalks (0x601c). Add water plane's group here once you log it on a hit node (same idea as sidewalks, not name-based).
IANeighbours.PLACE_BLOCKING_EXCLUDE_COLLISION_FILTER_GROUPS = { 0x601c, 0x80000000 }

--- Optional overlapSphere collisionMask (FS25 GDN: integer, default all bits). When set, only layers matching this mask are queried - use if you know the bitmask that omits water/static decorative layers (discover via map / GDN); leave nil for full query + post-filters above.
IANeighbours.PLACE_OVERLAP_SPHERE_COLLISION_MASK = nil

--- Node names (case insensitive) excluded from place blocking: exact "collision", "tipCollision"; or name containing listed substrings (e.g. "trigger", "boundary", "mapboundaries", "waterplane"). IAHelper also checks getNodeIdFullName and parent chain so hits under mapBoundaries still match.
IANeighbours.PLACE_BLOCKING_EXCLUDE_NODE_NAMES = { "collision", "tipcollision", "trigger", "boundary", "mapboundaries", "waterplane" }

source(IANeighbours.dir .. "IAHelper.lua")
source(IANeighbours.dir .. "IAHumanCharacter.lua")
source(IANeighbours.dir .. "gui/IAConversationDialog.lua")
source(IANeighbours.dir .. "gui/IAMapInitDialogGUI.lua")
source(IANeighbours.dir .. "gui/IAMapPlacesGenDialogGUI.lua")
source(IANeighbours.dir .. "gui/IAMapFirstLoadTutorialDialogGUI.lua")
source(IANeighbours.dir .. "gui/IAPhoneDialogGUI.lua")
source(IANeighbours.dir .. "IAConversation.lua")
source(IANeighbours.dir .. "IANeighbourDynamicConversationData.lua")
source(IANeighbours.dir .. "XMLHelper.lua")
source(IANeighbours.dir .. "IANeighbour.lua")
source(IANeighbours.dir .. "IANeighbourVehicle.lua")
source(IANeighbours.dir .. "IAEquipmentPresence.lua")
source(IANeighbours.dir .. "IAAIJob.lua")
source(IANeighbours.dir .. "IAFieldwork.lua")
source(IANeighbours.dir .. "IAFieldOutcomeMissionProbeEvaluator.lua")
source(IANeighbours.dir .. "IASituation.lua")
source(IANeighbours.dir .. "IASituationConfig.lua")
source(IANeighbours.dir .. "IAMapPlace.lua")
source(IANeighbours.dir .. "IAPlacesLoader.lua")
source(IANeighbours.dir .. "IAMapInitJob.lua")
source(IANeighbours.dir .. "IAHomebaseParking.lua")
source(IANeighbours.dir .. "IAGameLoopHelper.lua")
source(IANeighbours.dir .. "IAFieldOutcomeMission.lua")
source(IANeighbours.dir .. "IAMissionBorrow.lua")
source(IANeighbours.dir .. "IASettings.lua")
if IANeighbours.debug then
	source(IANeighbours.dir .. "lib/testFramework/IATestRunner.lua")
	source(IANeighbours.dir .. "lib/testFramework/IATestScenarios.lua")
	source(IANeighbours.dir .. "lib/testFramework/IATestRegistry.lua")
end

-- Vehicle borrow-access spec: register at mod load (before loadMap / validateTypes), not via source().
if g_specializationManager ~= nil then
	local borrowSpecName = string.format("%s.borrowAccess", g_currentModName)
	if g_specializationManager:getSpecializationObjectByName(borrowSpecName) == nil then
		g_specializationManager:addSpecialization(
			"borrowAccess",
			"IABorrowAccess",
			IANeighbours.dir .. "IABorrowAccess.lua",
			nil
		)
	end
end

function IANeighbours:loadMap()
	-- Multiplayer: do not register GUI, hooks, or helpers. On host/dedicated this matches
	-- g_server ~= nil and g_currentMission.missionDynamicInfo.isMultiplayer; MP clients skip the same way via isMultiplayer.
	if g_currentMission ~= nil and g_currentMission.missionDynamicInfo ~= nil and g_currentMission.missionDynamicInfo.isMultiplayer then
		IANeighbours.BlockMod = true
		return
	end

	IANeighbours.didStripVanillaFieldMissionsOnLoad = false
	IANeighbours.didNormalizeAssignedFieldCropsOnFirstLoad = true -- DISABLED: leave field state unchanged on initial farmland assignment

	local ui = g_currentMission.inGameMenu

	-- if IANeighbours.debug then
	-- 	print("--- IANeighbours "..g_currentMission.missionInfo.savegameDirectory.."/guiProfiles.xml")
	-- 	local xmlFile = loadXMLFile("Temp", "dataS/guiProfiles.xml")
	-- 	saveXMLFileTo(xmlFile, g_currentMission.missionInfo.savegameDirectory.."/guiProfiles.xml")
	-- 	delete(xmlFile);
	-- end
	--IANeighbours:loadInboundXML()

	-- Initialize IAXMLHelper
	IANeighbours.xmlHelper = IAXMLHelper.new(IANeighbours)
	
	-- Initialize IAPlacesLoader (loads all places into IANeighbours.places from XML + init + placeables)
	IANeighbours.placesLoader = IAPlacesLoader.new(IANeighbours)
	
	-- Initialize IAGameLoopHelper
	IANeighbours.gameLoopHelper = IAGameLoopHelper.new(IANeighbours)

	if IAFieldOutcomeMission ~= nil and type(IAFieldOutcomeMission.registerWithMissionManager) == "function" then
		IAFieldOutcomeMission.registerWithMissionManager()
	end

	-- Lift active mission cap (vanilla uses hasFarmReachedMissionLimit and MAX_MISSIONS for generation/UI).
	-- Set MAX_MISSIONS on the CLASS table (not g_missionManager instance) so getFreeActiveMissionId
	-- and getCanStartNewMissionGeneration both see the raised limit (1000).
	if MissionManager ~= nil and MissionManager.hasFarmReachedMissionLimit ~= nil then
		MissionManager.MAX_MISSIONS = 1000

		-- Per-farm limit: always return false (unlimited).
		MissionManager.hasFarmReachedMissionLimit = Utils.overwrittenFunction(
			MissionManager.hasFarmReachedMissionLimit,
			IANeighbours.hasFarmReachedMissionLimit)
	end

	-- Map init job (used for map init spawn and for update-driven debug, e.g. map nodes debug)
	IANeighbours.mapInitJob = IAMapInitJob.new(self)
	IAMapInitJob.getMapReferenceData() --initialize the map reference data by triggering the map async data loading
	
	--g_currentMission.aiSystem:consoleCommandAIEnableDebug()

	if addConsoleCommand ~= nil then
		addConsoleCommand("iaForceFieldwork", "Fields of Stories: force a neighbour into a fieldwork situation", "consoleCommandIaForceFieldwork", IANeighbours, "[index|id|name]")
		addConsoleCommand("iaForceSituation", "Fields of Stories: force a neighbour into a specific situation (if eligible)", "consoleCommandIaForceSituation", IANeighbours, "[index|id|name]; [situationId]")
		addConsoleCommand("iaToggleVehiclePresenceDebug", "Fields of Stories: toggle map-wide vehicle/attachment presence debug markers", "consoleCommandIaToggleVehiclePresenceDebug", IANeighbours)
		addConsoleCommand("iaToggleFieldworkBorderDebug", "Fields of Stories: toggle fieldwork border/alignment debug markers (all active fieldworks)", "consoleCommandIaToggleFieldworkBorderDebug", IANeighbours)
		addConsoleCommand("iaToggleFieldMissionProbeDebug", "Fields of Stories: toggle field-outcome mission probe debug markers (active phone contracts)", "consoleCommandIaToggleFieldMissionProbeDebug", IANeighbours)
		addConsoleCommand("iaDumpGrowthStates", "Fields of Stories: dump all growth state names via getFruitTypeGrowthStateName (optional fruit name filter)", "consoleCommandIaDumpGrowthStates", IANeighbours, "[fruitName]")
		-- Performance debugging console commands
		addConsoleCommand("iaPerfToggleNeighbours", "Fields of Stories: toggle skipNeighbourUpdate (disable all neighbour per-frame updates)", "consoleCommandIaPerfToggleNeighbours", IANeighbours)
		addConsoleCommand("iaPerfToggleDebugDrawing", "Fields of Stories: toggle skipDebugDrawing (disable all per-frame debug visual overlays)", "consoleCommandIaPerfToggleDebugDrawing", IANeighbours)
		addConsoleCommand("iaPerfToggleBorrowUpdate", "Fields of Stories: toggle skipBorrowUpdate (disable per-frame IAMissionBorrow.update)", "consoleCommandIaPerfToggleBorrowUpdate", IANeighbours)
		addConsoleCommand("iaPerfStatus", "Fields of Stories: print current performance debugging toggle states", "consoleCommandIaPerfStatus", IANeighbours)
		addConsoleCommand("iaPerfEnableAll", "Fields of Stories: enable debugPerformance + set threshold to 0 (always log)", "consoleCommandIaPerfEnableAll", IANeighbours)
		addConsoleCommand("iaPerfDisableAll", "Fields of Stories: disable all performance debugging toggles and guards", "consoleCommandIaPerfDisableAll", IANeighbours)
		-- TEMP: combine auger pipe fold verification (remove once spawn/parking wiring is confirmed)
		addConsoleCommand("iaCombinePipeInfo", "Fields of Stories (TEMP): print nearest combine pipe (auger) state fields", "consoleCommandIaCombinePipeInfo", IANeighbours)
		addConsoleCommand("iaFoldCombinePipe", "Fields of Stories (TEMP): fold the nearest combine's auger pipe in", "consoleCommandIaFoldCombinePipe", IANeighbours)
		addConsoleCommand("iaUnfoldCombinePipe", "Fields of Stories (TEMP): unfold the nearest combine's auger pipe out", "consoleCommandIaUnfoldCombinePipe", IANeighbours)
	end

	-- Mod settings: load persisted values and register the in-game settings page UI
	-- (Pause menu -> General settings). UI registration is deferred to the first
	-- InGameMenu open so the settings page is fully built.
	if IASettings ~= nil then
		IASettings.initialize()
		InGameMenu.onMenuOpened = Utils.appendedFunction(InGameMenu.onMenuOpened, IASettings.registerInGameMenuSettings)
	end

	if IABorrowAccess ~= nil then
		IABorrowAccess.registerConsoleCommands()
	end

	if IANeighbours.debug then
		IATestRunner.registerConsoleCommands()
	end

	IANeighbours.registerNpcMapHotspotTexture()
	IANeighbours.registerCharacterPortraitTextures()
	g_gui:loadProfiles(Utils.getFilename("gui/guiProfiles.xml", IANeighbours.dir))
	-- Bitmap GUI elements do not get modEnvironment; register phone atlas
	if not IANeighbours._phoneGuiTextureRegistered and g_overlayManager ~= nil and g_overlayManager.addTextureConfigFile ~= nil then
		local texPath = Utils.getFilename("gui/IAPhoneTexture.xml", IANeighbours.dir)
		if texPath ~= nil and texPath ~= "" and fileExists(texPath) then
			g_overlayManager:addTextureConfigFile(texPath, "iaPhone")
			IANeighbours._phoneGuiTextureRegistered = true
		end
	end

	-- Preload mod conversation dialog so it is registered before first use (avoids path/timing issues)
	IAConversation.ensureConversationDialogLoaded()
	-- Preload Map Init dialog (opened with Shift+F3 when no map config)
	IANeighbours.ensureMapInitDialogLoaded()
	IANeighbours.ensureMapPlacesGenDialogLoaded()
	IANeighbours.ensureFirstLoadTutorialDialogLoaded()
	IANeighbours.ensurePhoneDialogLoaded()

	-- Dump ConversationDialog.xml to log (for debugging layout / element names)
	--IANeighbours.xmlHelper:dumpXML("dataS/gui/dialogs/ConversationDialog.xml", "ConversationDialog.xml")

	
	-- Remove and re-register the on-foot SHIFT+R action event so the FS HUD rebuilds the prompt with the new
	-- label ("Start Conversation" vs "Use Phone"); changing text on an existing visible event does not refresh it.
	local function registerConversationActionEvent(showConversation)
		if g_inputBinding == nil or InputAction == nil or InputAction.IAStartConversation == nil or IANeighbours.conversationActionEventTarget == nil then
			return false
		end
		local oldEventId = IANeighbours.conversationKeybind
		if oldEventId ~= nil and oldEventId ~= "" and g_inputBinding.removeActionEvent ~= nil then
			IAsafePcall("IANeighbours.registerConversationActionEvent removeActionEvent", function()
				g_inputBinding:removeActionEvent(oldEventId)
			end)
		end
		local textKey = showConversation == true and "gui_hud_start_conversation" or "input_IAUsePhone"
		local fallbackText = showConversation == true and "Start Conversation" or "Use Phone"
		local actionText = (g_i18n ~= nil and g_i18n.getText ~= nil) and g_i18n:getText(textKey) or fallbackText
		local convSuccess
		local eventId
		convSuccess, eventId = g_inputBinding:registerActionEvent(InputAction.IAStartConversation, IANeighbours.conversationActionEventTarget, function ()
			IANeighbours:onStartConversation()
		end, false, true, false, true)
		IANeighbours.conversationKeybind = eventId
		if IANeighbours.conversationKeybind ~= nil then
			g_inputBinding:setActionEventText(IANeighbours.conversationKeybind, actionText)
			g_inputBinding:setActionEventTextPriority(IANeighbours.conversationKeybind, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(IANeighbours.conversationKeybind, true)
			g_inputBinding:setActionEventActive(IANeighbours.conversationKeybind, true)
		end
		return convSuccess == true and IANeighbours.conversationKeybind ~= nil
	end
	IANeighbours.registerConversationActionEvent = registerConversationActionEvent

	local function addPlayerActionEvents(selfx, parentFunc, ...)
		parentFunc(selfx, ...)
		-- One on-foot SHIFT+R action event. The Controls/keybind menu uses input_IAStartConversation
		-- ("Conversation / Phone"), while the HUD prompt event is re-registered when its label changes.
		IANeighbours.conversationActionEventTarget = selfx
		IANeighbours.registerConversationActionEvent(false)
		IANeighbours.usePhoneKeybind = nil
		IANeighbours._conversationActionEventsState = "phone"

		-- Map Init dialog (Shift+F3): always registered active; no conditional deactivation in update()
		_, IANeighbours.mapInitDialogKeybind = g_inputBinding:registerActionEvent(InputAction.IAMapInitDialog, selfx, function ()
			IANeighbours.openMapInitDialog()
		end, false, true, false, true)
		g_inputBinding:setActionEventTextPriority(IANeighbours.mapInitDialogKeybind, GS_PRIO_MEDIUM)
		g_inputBinding:setActionEventTextVisibility(IANeighbours.mapInitDialogKeybind, false)
		g_inputBinding:setActionEventActive(IANeighbours.mapInitDialogKeybind, true)

		if IANeighbours.debug then
			-- Relative targets debug (Shift+F6): request run in IAMapInitJob:update -> IAPlacesLoader:setDisplayedRelativeTargets (nodes + placeables)
			_, IANeighbours.mapNodesDebugKeybind = g_inputBinding:registerActionEvent(InputAction.IAMapNodesDebug, selfx, function ()
				if IANeighbours.mapInitJob == nil then
					IANeighbours.mapInitJob = IAMapInitJob.new(IANeighbours)
				end
				IANeighbours.mapInitJob.mapNodesDebugRequested = true
			end, false, true, false, true)
			g_inputBinding:setActionEventTextPriority(IANeighbours.mapNodesDebugKeybind, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(IANeighbours.mapNodesDebugKeybind, false)
			g_inputBinding:setActionEventActive(IANeighbours.mapNodesDebugKeybind, true)

			-- Relative target focus (Ctrl+Y): cycle through displayed relative targets (nodes + placeables); focused one labeled "focused"
			_, IANeighbours.mapNodeFocusKeybind = g_inputBinding:registerActionEvent(InputAction.IAMapNodeFocus, selfx, function ()
				if IANeighbours.placesLoader then
					IANeighbours.placesLoader:cycleFocusedRelativeTargetAndRebuild()
				end
			end, false, true, false, true)
			g_inputBinding:setActionEventTextPriority(IANeighbours.mapNodeFocusKeybind, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(IANeighbours.mapNodeFocusKeybind, false)
			g_inputBinding:setActionEventActive(IANeighbours.mapNodeFocusKeybind, true)

			-- Relative target focus back (Ctrl+Shift+Z): cycle backwards through displayed relative targets
			_, IANeighbours.mapNodeFocusBackKeybind = g_inputBinding:registerActionEvent(InputAction.IAMapNodeFocusBack, selfx, function ()
				if IANeighbours.placesLoader then
					IANeighbours.placesLoader:cycleFocusedRelativeTargetBackAndRebuild()
				end
			end, false, true, false, true)
			g_inputBinding:setActionEventTextPriority(IANeighbours.mapNodeFocusBackKeybind, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(IANeighbours.mapNodeFocusBackKeybind, false)
			g_inputBinding:setActionEventActive(IANeighbours.mapNodeFocusBackKeybind, true)

			-- Jump to next i3d entry (Ctrl+I): cycles focus to next target whose name/reference contains ".i3d"
			_, IANeighbours.mapNodeFocusNextI3dKeybind = g_inputBinding:registerActionEvent(InputAction.IAMapNodeFocusNextI3D, selfx, function ()
				if IANeighbours.placesLoader then
					IANeighbours.placesLoader:cycleFocusedRelativeTargetToNextI3dAndRebuild()
				end
			end, false, true, false, true)
			g_inputBinding:setActionEventTextPriority(IANeighbours.mapNodeFocusNextI3dKeybind, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(IANeighbours.mapNodeFocusNextI3dKeybind, false)
			g_inputBinding:setActionEventActive(IANeighbours.mapNodeFocusNextI3dKeybind, true)
		end
	end
	PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
		PlayerInputComponent.registerGlobalPlayerActionEvents, addPlayerActionEvents)

	local function addVehicleActionEvents(selfx, parentFunc, ...)
		parentFunc(selfx, ...)
		if g_inputBinding == nil or InputAction == nil or InputAction.IAStartConversation == nil then
			return
		end
		local success, eventId = g_inputBinding:registerActionEvent(InputAction.IAStartConversation, selfx, function ()
			IANeighbours:onUsePhone()
		end, false, true, false, true)
		if success and eventId ~= nil then
			IANeighbours.vehiclePhoneKeybind = eventId
			g_inputBinding:setActionEventText(eventId, (g_i18n ~= nil and g_i18n.getText ~= nil) and g_i18n:getText("input_IAUsePhone") or "Use Phone")
			g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_MEDIUM)
			g_inputBinding:setActionEventTextVisibility(eventId, true)
			g_inputBinding:setActionEventActive(eventId, true)
		end
	end
	if Vehicle ~= nil and Vehicle.registerActionEvents ~= nil then
		Vehicle.registerActionEvents = Utils.overwrittenFunction(Vehicle.registerActionEvents, addVehicleActionEvents)
	elseif Enterable ~= nil and Enterable.registerActionEvents ~= nil then
		Enterable.registerActionEvents = Utils.overwrittenFunction(Enterable.registerActionEvents, addVehicleActionEvents)
	end


	if g_currentMission.maxNumHirables == 10 then
		g_currentMission.maxNumHirables = g_currentMission.maxNumHirables + 20
	end

	IANeighbours.initPlayerStyleTemplates()

	--IANeighbours:loadInitialNpcs()


--	IANeighbours.fixInGameMenu(guiIANeighbours,"ingameMenuFieldsOfStories", {0,0,1024,1024}, 2, IANeighbours:makeIANeighboursEnabledPredicate())

--	guiIANeighbours:initialize()	
end

--- Register overlay atlases: `iaFosNpc.npc` (map) and `iaFosNpcSm.npc` (small map list).
function IANeighbours.registerNpcMapHotspotTexture()
	if g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil then
		return
	end
	if not IANeighbours._iaNpcMapHotspotMainRegistered then
		local path = IANeighbours.dir .. "textures/iaNpcMapHotspot.xml"
		if fileExists(path) then
			g_overlayManager:addTextureConfigFile(path, "iaFosNpc")
		end
		IANeighbours._iaNpcMapHotspotMainRegistered = true
	end
	if not IANeighbours._iaNpcMapHotspotSmallRegistered then
		local pathSm = IANeighbours.dir .. "textures/iaNpcMapHotspotSmall.xml"
		if fileExists(pathSm) then
			g_overlayManager:addTextureConfigFile(pathSm, "iaFosNpcSm")
		end
		IANeighbours._iaNpcMapHotspotSmallRegistered = true
	end
end

--- Highest character portrait id (images/<id>.dds) to look for when registering slices.
IANeighbours.CHARACTER_PORTRAIT_MAX_ID = 21

--- Overlay-manager prefix for a character portrait texture config (slice id is `<prefix>.portrait`).
function IANeighbours.getCharacterPortraitSlicePrefix(id)
	return "iaFosChar" .. tostring(id)
end

--- Full slice id (e.g. `iaFosChar3.portrait`) used by GUI bitmaps via setImageSlice.
function IANeighbours.getCharacterPortraitSliceId(id)
	return IANeighbours.getCharacterPortraitSlicePrefix(id) .. ".portrait"
end

--- Register one overlay atlas per character portrait (images/<id>.dds) so GUI bitmaps can use slices.
function IANeighbours.registerCharacterPortraitTextures()
	if g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil then
		return
	end
	if IANeighbours._characterPortraitTexturesRegistered == nil then
		IANeighbours._characterPortraitTexturesRegistered = {}
	end
	for id = 1, IANeighbours.CHARACTER_PORTRAIT_MAX_ID do
		if not IANeighbours._characterPortraitTexturesRegistered[id] then
			local cfgPath = IANeighbours.dir .. "textures/characters/char_" .. tostring(id) .. ".xml"
			if fileExists(cfgPath) then
				g_overlayManager:addTextureConfigFile(cfgPath, IANeighbours.getCharacterPortraitSlicePrefix(id))
				IANeighbours._characterPortraitTexturesRegistered[id] = true
			end
		end
	end
end

--- Load once per career session (PlayerStyle XML configs for HumanModel neighbours).
function IANeighbours.initPlayerStyleTemplates()
	if IANeighbours.maleStyleTemplate ~= nil then
		return
	end
	local m = PlayerStyle.new()
	m:loadConfigurationXML("dataS/character/playerM/playerM.xml")
	IANeighbours.maleStyleTemplate = m
	local f = PlayerStyle.new()
	f:loadConfigurationXML("dataS/character/playerF/playerF.xml")
	IANeighbours.femaleStyleTemplate = f
end

function IANeighbours:registerFarmerNPCs()
	-- Find existing max NPC index in g_npcManager
	local nextIndex = 0
	if g_npcManager ~= nil and g_npcManager.npcs ~= nil then
		for i = 1, #g_npcManager.npcs do
			if g_npcManager.npcs[i] ~= nil then
				nextIndex = i
			end
		end
		nextIndex = nextIndex + 1
	else
		nextIndex = 1
	end
	
	-- Dynamically find all farmer neighbours
	local farmerNeighbours = {}
	for _, neighbour in ipairs(self.neighbours or {}) do
		if neighbour ~= nil and neighbour.job == "Farmer" and neighbour.role == "Neighbour" then
			table.insert(farmerNeighbours, neighbour)
		end
	end
	
	IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: Gestartet. nextIndex=" .. nextIndex .. ", anzahlFarmer=" .. #farmerNeighbours, nil, nil, nil)
	
	-- Sort by id for deterministic index assignment
	table.sort(farmerNeighbours, function(a, b) return a.id < b.id end)
	
	-- Create REAL NPC engine objects for each farmer neighbour
	for i, neighbour in ipairs(farmerNeighbours) do
		local npcIndex = nextIndex + i - 1
		local npcKey = "FARMER_NPC_" .. tostring(neighbour.id)
		local npcName = neighbour.name or "Farmer"
		local npcImage = neighbour:_characterPortraitImagePathForMap()
		
		IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: npcIndex=" .. npcIndex .. " npcKey=" .. npcKey .. " npcName=" .. npcName, nil, nil, nil)
		
		-- Ensure existing registered NPC also has its index set (from a previous registration, e.g. save reload)
		if neighbour.registeredNpc ~= nil then
			neighbour.registeredNpc.index = npcIndex
			IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: NPC fuer " .. neighbour.name .. " existiert bereits, update Index auf " .. npcIndex, nil, nil, nil)
			IAHelper_registerNpcInManager(neighbour.registeredNpc, npcIndex)
		end
		
		IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: Erstelle NPC " .. npcIndex .. " fuer " .. neighbour.name .. " (key=" .. npcKey .. ")", nil, nil, nil)
		
		-- Create and load a REAL engine NPC object
		local success, npc = pcall(function()
			local npcObj = NPC.new()
			npcObj:load("dataS2/npc/farmer/farmer.xml", npcKey, npcName)
			npcObj.index = npcIndex  -- Important for farmland.npcIndex assignment in updateFarmlands()
			npcObj.title = npcName
			npcObj.imageFilename = npcImage
			return npcObj
		end)
		
		if success and npc ~= nil then
			IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: NPC geladen fuer " .. neighbour.name .. " mit Index " .. npcIndex, nil, nil, nil)
			
			-- Register in g_npcManager via helper (encapsulates direct g_npcManager access)
			IAHelper_registerNpcInManager(npc, npcIndex)
			if g_npcManager ~= nil and g_npcManager.nameToNPC ~= nil then
				g_npcManager.nameToNPC[npcKey] = npc
			end
			IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: NPC-Index " .. npcIndex .. " = " .. tostring(npc) .. " registriert in g_npcManager fuer " .. neighbour.name, nil, nil, nil)
			
			-- Store reference on the neighbour object
			neighbour.registeredNpc = npc
		else
			local errMsg = tostring(npc)
			IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: FEHLGESCHLAGEN fuer " .. npcName .. ": " .. errMsg, nil, nil, nil)
		end
	end
	
	IAprintDebug("IANeighbours:registerFarmerNPCs()", "- registerFarmerNPCs: Fertig", nil, nil, nil)
end

function IANeighbours:getCharacterPortraitPath(characterId, gender)
	if characterId == nil then
		return nil
	end
	
	local basePath = Utils.getFilename("dataS2/character/npc/portraits/", self.dir)
	
	-- Try specific character portrait
	local filename = string.format("%snpc_%d.dds", basePath, characterId)
	if fileExists(filename) then
		return filename
	end
	
	-- Try PNG fallback
	filename = string.format("%snpc_%d.png", basePath, characterId)
	if fileExists(filename) then
		return filename
	end
	
	return nil
end

function IANeighbours:getDefaultCharacterPortraitPath(gender)
	local basePath = Utils.getFilename("dataS2/character/npc/portraits/", self.dir)
	if gender ~= nil and string.lower(gender) == "female" then
		return string.format("%snpc_default_female.dds", basePath)
	end
	return string.format("%snpc_default_male.dds", basePath)
end

function IANeighbours.clearPlayerStyleTemplates()
	IANeighbours.maleStyleTemplate = nil
	IANeighbours.femaleStyleTemplate = nil
end

--- Open the Map Init dialog if conditions are met (map init run or mod loaded with config; dialog loaded). Can be opened on foot or in a vehicle.
-- @return boolean true if the dialog was opened
function IANeighbours.openMapInitDialog()
	-- Allow opening on foot or in a vehicle. We only block when the mod is explicitly blocked.
	-- (The dialog itself can still guide the user even before outbound XML finished loading.)
	local canOpen = (not IANeighbours.BlockMod) and IANeighbours.ensureMapInitDialogLoaded()
	if not canOpen then
		return false
	end
	-- Places are already loaded from fields_of_stories_<mapId>.xml in loadData/loadMapConfiguration
	local dialog = g_gui:showDialog("IAMapInitDialogGUI")
	if dialog and dialog.target and dialog.target.setDialog then
		dialog.target:setDialog(dialog)
	end
	return dialog ~= nil
end

--- Remove mod runtime objects (situations, vehicles, neighbours, NPCs) and block further updates.
-- Intended for the Map Init dialog "Remove Mod" button.
function IANeighbours:requestRemoveMod()
	if self.removeModRequested == true then
		return
	end
	self.removeModRequested = true
	-- Immediately stop running logic after cleanup
	self:performRemoveModCleanup()
	self.BlockMod = true
	-- Outbound minimal XML is written on the next career save (savegame folder is not writable outside saveToXMLFile on FS25/UWP).
end

--- Always allow more missions for this farm (disables per-farm limit).
function IANeighbours:hasFarmReachedMissionLimit(superFunc, farmId)
	return false
end

--- Resolve neighbour from developer-console token: 1-based list index, character id, or case-insensitive name.
function IANeighbours:resolveNeighbourForConsoleToken(token)
	if token == nil then
		return nil
	end
	token = tostring(token):match("^%s*(.-)%s*$") or ""
	if token == "" then
		return nil
	end
	local list = self.neighbours or {}
	local num = tonumber(token)
	if num ~= nil then
		local i = math.floor(num + 1e-9)
		if i >= 1 and i <= #list then
			return list[i]
		end
	end
	local tokenLower = string.lower(token)
	for _, n in ipairs(list) do
		if n ~= nil then
			if tostring(n.id) == token then
				return n
			end
			if n.name ~= nil and string.lower(tostring(n.name)) == tokenLower then
				return n
			end
		end
	end
	return nil
end

--- Developer console: iaToggleVehiclePresenceDebug
function IANeighbours:consoleCommandIaToggleVehiclePresenceDebug()
	IANeighbours.debugVehiclePresencePositions = not IANeighbours.debugVehiclePresencePositions
	print("[iaToggleVehiclePresenceDebug] debugVehiclePresencePositions=" .. tostring(IANeighbours.debugVehiclePresencePositions))
end

--- Developer console: iaToggleFieldworkBorderDebug
function IANeighbours:consoleCommandIaToggleFieldworkBorderDebug()
	IANeighbours.debugFieldworkBorderGeometry = not IANeighbours.debugFieldworkBorderGeometry
	print("[iaToggleFieldworkBorderDebug] debugFieldworkBorderGeometry=" .. tostring(IANeighbours.debugFieldworkBorderGeometry))
end

--- Developer console: iaToggleFieldMissionProbeDebug
function IANeighbours:consoleCommandIaToggleFieldMissionProbeDebug()
	IANeighbours.debugFieldMissionProbes = not IANeighbours.debugFieldMissionProbes
	print("[iaToggleFieldMissionProbeDebug] debugFieldMissionProbes=" .. tostring(IANeighbours.debugFieldMissionProbes))
	if IAFieldOutcomeMission ~= nil and type(IAFieldOutcomeMission.syncProbeDebugMarkersForAllActive) == "function" then
		IAFieldOutcomeMission.syncProbeDebugMarkersForAllActive()
	end
end

--- TEMP developer console: iaCombinePipeInfo
-- Find the nearest combine with a movable pipe (auger spout) and print its
-- spec_pipe state fields so we can verify the fold-in mapping before wiring it
-- into spawn/parking. Remove together with iaFoldCombinePipe.
function IANeighbours:consoleCommandIaCombinePipeInfo()
	local refX, refY, refZ = self:resolvePlayerRefPosition()
	if refX == nil then
		print("[iaCombinePipeInfo] could not resolve player position")
		return
	end
	local vehicle, distSq = IAHelper_findNearestVehicleWithPipe(refX, refY, refZ)
	if vehicle == nil then
		print("[iaCombinePipeInfo] no combine with a movable pipe found")
		return
	end
	local spec = vehicle.spec_pipe
	local name = (vehicle.getFullName ~= nil) and vehicle:getFullName() or tostring(vehicle)
	print(string.format("[iaCombinePipeInfo] %s (dist=%.1fm)", tostring(name), math.sqrt(distSq or 0)))
	print(string.format("  currentState=%s targetState=%s foldMinState=%s foldMaxState=%s",
		tostring(spec.currentState), tostring(spec.targetState),
		tostring(spec.foldMinState), tostring(spec.foldMaxState)))
	print(string.format("  hasMovablePipe=%s anim=%s foldMinTime=%s foldMaxTime=%s",
		tostring(spec.hasMovablePipe), tostring(spec.animation and spec.animation.name),
		tostring(spec.foldMinTime), tostring(spec.foldMaxTime)))
end

--- TEMP developer console: iaFoldCombinePipe
-- Find the nearest combine with a movable pipe and fold its auger spout in via
-- IAHelper_foldCombinePipeIn (the production logic). Remove this command once the
-- spawn/parking wiring is verified.
function IANeighbours:consoleCommandIaFoldCombinePipe()
	local refX, refY, refZ = self:resolvePlayerRefPosition()
	if refX == nil then
		print("[iaFoldCombinePipe] could not resolve player position")
		return
	end
	local vehicle, distSq = IAHelper_findNearestVehicleWithPipe(refX, refY, refZ)
	if vehicle == nil then
		print("[iaFoldCombinePipe] no combine with a movable pipe found")
		return
	end
	local ok, msg = IAHelper_foldCombinePipeIn(vehicle)
	local name = (vehicle.getFullName ~= nil) and vehicle:getFullName() or tostring(vehicle)
	print(string.format("[iaFoldCombinePipe] %s (dist=%.1fm) -> ok=%s %s",
		tostring(name), math.sqrt(distSq or 0), tostring(ok), tostring(msg)))
end

--- TEMP developer console: iaUnfoldCombinePipe
-- Find the nearest combine with a movable pipe and unfold its auger spout out via
-- IAHelper_unfoldCombinePipeOut. Counterpart of iaFoldCombinePipe.
function IANeighbours:consoleCommandIaUnfoldCombinePipe()
	local refX, refY, refZ = self:resolvePlayerRefPosition()
	if refX == nil then
		print("[iaUnfoldCombinePipe] could not resolve player position")
		return
	end
	local vehicle, distSq = IAHelper_findNearestVehicleWithPipe(refX, refY, refZ)
	if vehicle == nil then
		print("[iaUnfoldCombinePipe] no combine with a movable pipe found")
		return
	end
	local ok, msg = IAHelper_unfoldCombinePipeOut(vehicle)
	local name = (vehicle.getFullName ~= nil) and vehicle:getFullName() or tostring(vehicle)
	print(string.format("[iaUnfoldCombinePipe] %s (dist=%.1fm) -> ok=%s %s",
		tostring(name), math.sqrt(distSq or 0), tostring(ok), tostring(msg)))
end

--- TEMP helper for the pipe console commands: resolve a world reference position
-- (current vehicle root if seated, otherwise the player position).
-- @return number|nil x, number|nil y, number|nil z
function IANeighbours:resolvePlayerRefPosition()
	if g_localPlayer == nil then
		return nil, nil, nil
	end
	local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if v ~= nil and v.rootNode ~= nil then
		return getWorldTranslation(v.rootNode)
	end
	if g_localPlayer.getPosition ~= nil then
		return g_localPlayer:getPosition()
	end
	return nil, nil, nil
end

--- Developer console: iaDumpGrowthStates
-- Dumps every fruit type and all of its growth state names, resolved via the
-- global getFruitTypeGrowthStateName(fruitTypeIndex, growthState) helper.
-- Optional argument: a (case-insensitive, partial-match) fruit name filter.
function IANeighbours:consoleCommandIaDumpGrowthStates(fruitNameFilter)
	if g_fruitTypeManager == nil then
		print("[iaDumpGrowthStates] g_fruitTypeManager is not available")
		return "g_fruitTypeManager is not available"
	end

	local fruitTypes = g_fruitTypeManager:getFruitTypes()
	if fruitTypes == nil then
		print("[iaDumpGrowthStates] no fruit types registered")
		return "no fruit types registered"
	end

	local filter = nil
	if fruitNameFilter ~= nil and fruitNameFilter ~= "" then
		filter = string.lower(tostring(fruitNameFilter))
	end

	local fruitCount = 0
	local stateCount = 0
	print("[iaDumpGrowthStates] dumping growth state names via getFruitTypeGrowthStateName" .. (filter ~= nil and (" (filter='" .. filter .. "')") or ""))

	for _, fruitType in ipairs(fruitTypes) do
		local fruitName = fruitType.name or "?"
		if filter == nil or string.find(string.lower(tostring(fruitName)), filter, 1, true) ~= nil then
			fruitCount = fruitCount + 1
			local maxState = 0
			if fruitType.growthStateToName ~= nil then
				for i, _ in ipairs(fruitType.growthStateToName) do
					if i > maxState then
						maxState = i
					end
				end
			end
			print(string.format("[iaDumpGrowthStates] fruit '%s' (index=%s, growthStates=%d)", tostring(fruitName), tostring(fruitType.index), maxState))
			for growthState = 1, maxState do
				local name = getFruitTypeGrowthStateName(fruitType.index, growthState)
				if name ~= nil then
					stateCount = stateCount + 1
					print(string.format("    [%d] %s", growthState, tostring(name)))
				end
			end
		end
	end

	local summary = string.format("[iaDumpGrowthStates] done: %d fruit type(s), %d growth state name(s)", fruitCount, stateCount)
	print(summary)
	return summary
end

--- Build a short label for map-wide vehicle presence debug markers.
function IANeighbours:buildVehiclePresenceDebugLabel(neighbour, ia)
	local parts = {}
	if neighbour ~= nil and neighbour.name ~= nil then
		table.insert(parts, tostring(neighbour.name))
	end
	if ia.type ~= nil and ia.type ~= "" then
		table.insert(parts, tostring(ia.type))
	end
	if ia.category ~= nil and ia.category ~= "" then
		table.insert(parts, "(" .. tostring(ia.category) .. ")")
	end
	if ia.uniqueId ~= nil then
		table.insert(parts, "uid=" .. tostring(ia.uniqueId))
	end
	local ps = ia.presenceState
	if ps ~= nil then
		table.insert(parts, tostring(ps.owner or "?") .. "/" .. tostring(ps.mode or "?"))
	end
	if ia.vehicleIsVisible ~= true then
		table.insert(parts, "engineHidden")
	end
	if ia.isBorrowedByPlayer == true then
		table.insert(parts, "borrowed")
	end
	if #parts == 0 then
		return "vehicle"
	end
	return table.concat(parts, " ")
end

--- Pick drawDebugPoint RGBA from desired presence / visibility (engineHidden = red).
function IANeighbours:vehiclePresenceDebugMarkerColor(ia)
	if ia == nil or ia.vehicleIsVisible ~= true then
		return 255, 40, 40, 200
	end
	local ps = ia.presenceState
	local owner = ps ~= nil and ps.owner or "none"
	if owner == "situation" then
		return 40, 255, 80, 200
	end
	if owner == "homebase" then
		return 80, 180, 255, 200
	end
	if owner == "borrowed" then
		return 220, 120, 255, 200
	end
	return 255, 220, 60, 200
end

--- Every frame: draw markers at actual game vehicle world positions (no range limit; ignores hide state).
function IANeighbours:drawVehiclePresenceDebugMarkers()
	if g_currentMission == nil then
		return
	end
	local neighbours = IANeighbours.neighbours
	if neighbours == nil then
		return
	end
	for _, neighbour in pairs(neighbours) do
		if neighbour ~= nil and not neighbour.isDeleted and neighbour.vehicles ~= nil then
			for _, ia in pairs(neighbour.vehicles) do
				if ia ~= nil then
					local x, y, z = nil, nil, nil
					local gv = ia.vehicle
					if gv ~= nil and gv.rootNode ~= nil and entityExists(gv.rootNode) then
						x, y, z = getWorldTranslation(gv.rootNode)
						ia.realPositionX = x
						ia.realPositionY = y
						ia.realPositionZ = z
					elseif ia.realPositionX ~= nil and ia.realPositionZ ~= nil then
						x, y, z = ia.realPositionX, ia.realPositionY, ia.realPositionZ
					end
					if x ~= nil and y ~= nil and z ~= nil then
						local r, g, b, a = IANeighbours:vehiclePresenceDebugMarkerColor(ia)
						drawDebugPoint(x, y, z, r, g, b, a, false)
						if Utils.renderTextAtWorldPosition and getCorrectTextSize then
							local label = IANeighbours:buildVehiclePresenceDebugLabel(neighbour, ia)
							Utils.renderTextAtWorldPosition(x, y + 0.5, z, label, getCorrectTextSize(0.011), 0)
						end
					end
				end
			end
		end
	end
end

--- Draw one fieldwork border debug point: tier = pillar height (1–4 dots); labels use text size not color.
function IANeighbours:drawFieldworkBorderDebugPoint(x, z, label, tier, sitTag)
	if x == nil or z == nil then
		return
	end
	local y = 0
	if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.25
	end
	local t = math.max(1, math.min(4, math.floor(tonumber(tier) or 1)))
	local step = 0.4
	for i = 0, t - 1 do
		drawDebugPoint(x, y + i * step, z, 50, 50, 50, 100, false)
	end
	if Utils.renderTextAtWorldPosition and getCorrectTextSize and label ~= nil and label ~= "" then
		local textSize = 0.008
		if t >= 4 then
			textSize = 0.016
		elseif t >= 3 then
			textSize = 0.013
		elseif t >= 2 then
			textSize = 0.011
		end
		local prefix = sitTag ~= nil and (tostring(sitTag) .. " ") or ""
		Utils.renderTextAtWorldPosition(x, y + t * step + 0.15, z, prefix .. tostring(label), getCorrectTextSize(textSize), 0)
	end
end

--- Draw a debug line between two XZ points (same neutral color as points).
function IANeighbours:drawFieldworkBorderDebugSegment(x1, z1, x2, z2, yBase)
	if drawDebugLine == nil or x1 == nil or z1 == nil or x2 == nil or z2 == nil then
		return
	end
	local y1, y2 = yBase or 0, yBase or 0
	if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
		y1 = getTerrainHeightAtWorldPos(g_terrainNode, x1, 0, z1) + 0.35
		y2 = getTerrainHeightAtWorldPos(g_terrainNode, x2, 0, z2) + 0.35
	end
	drawDebugLine(x1, y1, z1, 50, 50, 50, x2, y2, z2, 50, 50, 50)
end

--- Every frame: field polygon + longest-edge spawn geometry for all active fieldwork situations (no draw range limit).
function IANeighbours:drawFieldworkBorderDebugMarkers()
	if g_currentMission == nil or type(IAHelper_collectFieldBorderSpawnDebugPoints) ~= "function" then
		return
	end
	local situations = self:getAllActiveSituations()
	for _, situation in ipairs(situations) do
		if situation ~= nil and situation.jobType ~= nil and situation.farmland ~= nil and situation.farmland.field ~= nil then
			local field = situation.farmland.field
			local combined = 0
			if type(situation.iaResolveCombinedFieldworkWidth) == "function" then
				combined = situation:iaResolveCombinedFieldworkWidth()
			end
			local sitTag = tostring(situation.id or situation.farmlandId or "?")
			local points = IAHelper_collectFieldBorderSpawnDebugPoints(field, combined, nil)
			for _, p in ipairs(points) do
				if p.segment == true then
					IANeighbours:drawFieldworkBorderDebugSegment(p.x1, p.z1, p.x2, p.z2, nil)
				elseif p.x ~= nil and p.z ~= nil then
					IANeighbours:drawFieldworkBorderDebugPoint(p.x, p.z, p.label, p.tier, sitTag)
				end
			end
			if situation.positionX ~= nil and situation.positionZ ~= nil then
				IANeighbours:drawFieldworkBorderDebugPoint(situation.positionX, situation.positionZ, "[SIT] stored pose", 3, sitTag)
				if situation.rotation ~= nil and MathUtil ~= nil and type(MathUtil.getDirectionFromYRotation) == "function" then
					local fwdX, fwdZ = MathUtil.getDirectionFromYRotation(situation.rotation)
					local tx, tz = situation.positionX + fwdX * 4, situation.positionZ + fwdZ * 4
					IANeighbours:drawFieldworkBorderDebugPoint(tx, tz, "[SIT-YAW] heading", 2, sitTag)
					IANeighbours:drawFieldworkBorderDebugSegment(situation.positionX, situation.positionZ, tx, tz, nil)
				end
			end
		end
	end
end

--- Performance debugging: iaPerfToggleNeighbours
function IANeighbours:consoleCommandIaPerfToggleNeighbours()
	IANeighbours.skipNeighbourUpdate = not IANeighbours.skipNeighbourUpdate
	print("[iaPerf] skipNeighbourUpdate = " .. tostring(IANeighbours.skipNeighbourUpdate))
end

--- Performance debugging: iaPerfToggleDebugDrawing
function IANeighbours:consoleCommandIaPerfToggleDebugDrawing()
	IANeighbours.skipDebugDrawing = not IANeighbours.skipDebugDrawing
	print("[iaPerf] skipDebugDrawing = " .. tostring(IANeighbours.skipDebugDrawing))
end

--- Performance debugging: iaPerfToggleBorrowUpdate
function IANeighbours:consoleCommandIaPerfToggleBorrowUpdate()
	IANeighbours.skipBorrowUpdate = not IANeighbours.skipBorrowUpdate
	print("[iaPerf] skipBorrowUpdate = " .. tostring(IANeighbours.skipBorrowUpdate))
end

--- Performance debugging: iaPerfStatus — print all toggle states
function IANeighbours:consoleCommandIaPerfStatus()
	print("=== [iaPerf] Performance Debug State ===")
	print("  debugPerformance       = " .. tostring(IANeighbours.debugPerformance))
	print("  frameTimeLogThresholdMs = " .. tostring(IANeighbours.frameTimeLogThresholdMs))
	print("  skipNeighbourUpdate     = " .. tostring(IANeighbours.skipNeighbourUpdate))
	print("  skipDebugDrawing        = " .. tostring(IANeighbours.skipDebugDrawing))
	print("  skipBorrowUpdate        = " .. tostring(IANeighbours.skipBorrowUpdate))
	print("=======================================")
end

--- Performance debugging: iaPerfEnableAll — enable profiling and set threshold to 0 (always log)
function IANeighbours:consoleCommandIaPerfEnableAll()
	IANeighbours.debugPerformance = true
	IANeighbours.frameTimeLogThresholdMs = 0
	print("[iaPerf] debugPerformance = true, frameTimeLogThresholdMs = 0 (always log)")
end

--- Performance debugging: iaPerfDisableAll — disable profiling and reset all skip guards
function IANeighbours:consoleCommandIaPerfDisableAll()
	IANeighbours.debugPerformance = false
	IANeighbours.frameTimeLogThresholdMs = 2
	IANeighbours.skipNeighbourUpdate = false
	IANeighbours.skipDebugDrawing = false
	IANeighbours.skipBorrowUpdate = false
	print("[iaPerf] All performance debugging reset: profiling OFF, all skip guards cleared")
end

--- Developer console: iaForceSituation [index|id|name]; [situationId]
function IANeighbours:consoleCommandIaForceSituation(neighbourToken, situationToken)
	if self.BlockMod == true or self.removeModRequested == true then
		print("[iaForceSituation] Mod inactive (multiplayer or removed).")
		return
	end
	local function trimToken(v)
		if v == nil then
			return nil
		end
		local s = tostring(v):match("^%s*(.-)%s*$") or ""
		if s == "" then
			return nil
		end
		return s
	end
	neighbourToken = trimToken(neighbourToken)
	situationToken = trimToken(situationToken)
	if neighbourToken == nil or situationToken == nil then
		print("[iaForceSituation] Usage: iaForceSituation <1-based index | characterId | name> <situationId>  (two separate args)")
		local list = self.neighbours or {}
		for i = 1, #list do
			local n = list[i]
			if n ~= nil then
				print(string.format("  [%d] id=%s name=%s", i, tostring(n.id), tostring(n.name)))
			end
		end
		return
	end
	local neighbour = self:resolveNeighbourForConsoleToken(neighbourToken)
	if neighbour == nil then
		print("[iaForceSituation] No neighbour matches: " .. tostring(neighbourToken))
		return
	end
	local ok, err = neighbour:forceNewSituation(situationToken)
	if ok then
		print("[iaForceSituation] OK: " .. tostring(neighbour.name) .. " -> situation " .. tostring(neighbour.activeSituationId))
	else
		print("[iaForceSituation] Failed for " .. tostring(neighbour.name) .. " (situation " .. tostring(situationToken) .. "): " .. tostring(err))
	end
end

--- Developer console: iaForceFieldwork [index|id|name]
function IANeighbours:consoleCommandIaForceFieldwork(argStr)
	if self.BlockMod == true or self.removeModRequested == true then
		print("[iaForceFieldwork] Mod inactive (multiplayer or removed).")
		return
	end
	local token
	if type(argStr) == "string" then
		token = argStr:match("^%s*(.-)%s*$") or ""
	else
		token = tostring(argStr or ""):match("^%s*(.-)%s*$") or ""
	end
	if token == "" then
		print("[iaForceFieldwork] Usage: iaForceFieldwork <1-based index | characterId | name>")
		local list = self.neighbours or {}
		for i = 1, #list do
			local n = list[i]
			if n ~= nil then
				print(string.format("  [%d] id=%s name=%s", i, tostring(n.id), tostring(n.name)))
			end
		end
		return
	end
	local neighbour = self:resolveNeighbourForConsoleToken(token)
	if neighbour == nil then
		print("[iaForceFieldwork] No neighbour matches: " .. token)
		return
	end
	local ok, err = neighbour:forceNewFieldworkSituation()
	if ok then
		print("[iaForceFieldwork] OK: " .. tostring(neighbour.name) .. " -> situation " .. tostring(neighbour.activeSituationId))
	else
		print("[iaForceFieldwork] Failed for " .. tostring(neighbour.name) .. ": " .. tostring(err))
	end
end

--- Best-effort cleanup: each neighbour's :delete() (situations, vehicles, NPCs, hotspots), then clear mod runtime tables.
function IANeighbours:performRemoveModCleanup()
	pcall(function() IANeighbours:clearAllDebugPoints() end)
	self.mapInitPlaceMarkersVisible = false

	local nbs = self.neighbours or {}
	local copy = {}
	for i = 1, #nbs do
		copy[#copy + 1] = nbs[i]
	end
	self.neighbours = {}
	for _, neighbour in ipairs(copy) do
		if neighbour ~= nil and neighbour.delete ~= nil then
			pcall(function() neighbour:delete() end)
		end
	end

	self.activeDialog = nil
	self.activeDialogText = ""
	self.situationConfigs = {}
	self.vehicleIdMapping = {}
	IANeighbours.clearPlayerStyleTemplates()
	-- Clean up orphaned farm 99 vehicles that are no longer tracked by any neighbour
	if self.xmlHelper ~= nil and self.xmlHelper.removeOrphanedFarm99Vehicles ~= nil then
		self.xmlHelper:removeOrphanedFarm99Vehicles()
	end
end

--- Remove one neighbour from the list and run full :delete() (same teardown as remove-mod per character).
function IANeighbours:deleteNeighbour(neighbour)
	if neighbour == nil then
		return
	end
	for i = #self.neighbours, 1, -1 do
		if self.neighbours[i] == neighbour then
			table.remove(self.neighbours, i)
			break
		end
	end
	if neighbour.delete ~= nil then
		pcall(function() neighbour:delete() end)
	end
end

--- Ensure the Map Init dialog is loaded (for Shift+F3 when no map config).
-- @return boolean true if the dialog can be shown
function IANeighbours.ensureMapInitDialogLoaded()
	if g_gui == nil then
		return false
	end
	if g_gui.guis ~= nil and g_gui.guis["IAMapInitDialogGUI"] ~= nil then
		return true
	end
	local baseDir = IANeighbours.dir
	if baseDir == nil then
		return false
	end
	local path = baseDir .. "gui/IAMapInitDialogGUI.xml"
	local controller = IAMapInitDialogGUI.new(g_gui)
	g_gui:loadGui(path, "IAMapInitDialogGUI", controller, false)
	return g_gui.guis ~= nil and g_gui.guis["IAMapInitDialogGUI"] ~= nil
end

--- Ensure the first-run map places warning dialog is registered.
-- @return boolean true if the GUI is available to show
function IANeighbours.ensureMapPlacesGenDialogLoaded()
	if g_gui == nil then
		return false
	end
	if g_gui.guis ~= nil and g_gui.guis["IAMapPlacesGenDialogGUI"] ~= nil then
		return true
	end
	local baseDir = IANeighbours.dir
	if baseDir == nil then
		return false
	end
	local path = baseDir .. "gui/IAMapPlacesGenDialogGUI.xml"
	local controller = IAMapPlacesGenDialogGUI.new(g_gui)
	g_gui:loadGui(path, "IAMapPlacesGenDialogGUI", controller, false)
	return g_gui.guis ~= nil and g_gui.guis["IAMapPlacesGenDialogGUI"] ~= nil
end

--- First two dot-separated parts of requiredVoicePackVersion for UI (matches major.minor check; patch hidden).
function IANeighbours.requiredVoicePackVersionLabel()
	local full = IANeighbours.requiredVoicePackVersion or ""
	if full == nil or full == "" then
		return ""
	end
	local s = tostring(full):gsub("^%s+", ""):gsub("%s+$", "")
	local parts = {}
	for p in string.gmatch(s, "[^.]+") do
		parts[#parts + 1] = p
		if #parts >= 2 then
			break
		end
	end
	if #parts == 0 then
		return s
	end
	if #parts == 1 then
		return parts[1]
	end
	return parts[1] .. "." .. parts[2]
end

--- Ensure the first-load tutorial dialog is registered (shown when savegame isn't saved yet).
-- @return boolean true if the dialog can be shown
function IANeighbours.ensureFirstLoadTutorialDialogLoaded()
	if g_gui == nil then
		return false
	end
	if g_gui.guis ~= nil and g_gui.guis["IAMapFirstLoadTutorialDialogGUI"] ~= nil then
		return true
	end
	local baseDir = IANeighbours.dir
	if baseDir == nil then
		return false
	end
	local path = baseDir .. "gui/IAMapFirstLoadTutorialDialogGUI.xml"
	local controller = IAMapFirstLoadTutorialDialogGUI.new(g_gui)
	g_gui:loadGui(path, "IAMapFirstLoadTutorialDialogGUI", controller, false)
	return g_gui.guis ~= nil and g_gui.guis["IAMapFirstLoadTutorialDialogGUI"] ~= nil
end

--- Show intro/tutorial dialog once when `savegameDirectory` is nil.
function IANeighbours:maybeShowFirstLoadTutorialDialog()
	if self.firstLoadTutorialDialogShown == true then
		return false
	end
	if g_currentMission == nil or g_currentMission.missionInfo == nil then
		return false
	end
	if g_currentMission.missionInfo.savegameDirectory ~= nil then
		return false
	end
	if g_gui == nil then
		return false
	end
	if g_inGameMenu ~= nil and g_inGameMenu.isOpen == true then
		return false
	end

	if not self.ensureFirstLoadTutorialDialogLoaded() then
		return false
	end

	local dialog = g_gui:showDialog("IAMapFirstLoadTutorialDialogGUI")
	if dialog ~= nil then
		self.firstLoadTutorialDialogShown = true
		if dialog.target and dialog.target.setDialog then
			dialog.target:setDialog(dialog)
		end
		return true
	end
	return false
end

--- Register shared phone dialog (tutorial-style shell; reuse for any phone-related UI).
function IANeighbours.ensurePhoneDialogLoaded()
	if g_gui == nil then
		return false
	end
	if g_gui.guis ~= nil and g_gui.guis["IAPhoneDialogGUI"] ~= nil then
		return true
	end
	local baseDir = IANeighbours.dir
	if baseDir == nil then
		return false
	end

	local path = baseDir .. "gui/IAPhoneDialogGUI.xml"
	local controller = IAPhoneDialogGUI.new(g_gui)
	g_gui:loadGui(path, "IAPhoneDialogGUI", controller, false)
	return g_gui.guis ~= nil and g_gui.guis["IAPhoneDialogGUI"] ~= nil
end

function IANeighbours.stopIncomingCallRingSound()
	if IANeighbours._incomingCallRingSample ~= nil then
		delete(IANeighbours._incomingCallRingSample)
		IANeighbours._incomingCallRingSample = nil
	end
end

--- Single exit path for pending contract/phone offer (payload + ring). See `IncomingCallEndReason` for why it ended.
--- Does not close IAPhoneDialogGUI; refreshes its widgets if it is the current dialog (idle layout when missed).
--- @param reason string `IncomingCallEndReason.*`
function IANeighbours.clearPendingIncomingPhoneOffer(reason)
	if IATestRunner ~= nil and IATestRunner.onPhoneRingEnd ~= nil then
		IATestRunner.onPhoneRingEnd(reason)
	end
	if IANeighbours._incomingPhonePayload == nil then
		return
	end
	local shouldStopNotAnsweredConversation = reason == IANeighbours.IncomingCallEndReason.DECLINED
		or reason == IANeighbours.IncomingCallEndReason.PHONE_DIALOG_CLOSED
	local p = IANeighbours._incomingPhonePayload
	if shouldStopNotAnsweredConversation and p ~= nil and p.conversation ~= nil and type(p.conversation.stop) == "function" then
		p.conversation:stop()
	end
	IANeighbours._incomingPhonePayload = nil
	IANeighbours.pendingIncomingPhoneNeighbourId = nil
	IANeighbours._pendingIncomingPhoneStartedWallClockSec = nil
	IANeighbours.stopIncomingCallRingSound()
	if IANeighbours.debug and reason ~= nil then
		local missed = reason == IANeighbours.IncomingCallEndReason.MISSED_RING_FINISHED or reason == IANeighbours.IncomingCallEndReason.MISSED_TIMEOUT
		if missed then
			print("--- IANeighbours.clearPendingIncomingPhoneOffer() MISSED / not answered — reason=" .. tostring(reason))
		end
	end
	if IAPhoneDialogGUI ~= nil and type(IAPhoneDialogGUI.refreshPhoneScreenFromNeighboursStateIfOpen) == "function" then
		IAPhoneDialogGUI.refreshPhoneScreenFromNeighboursStateIfOpen()
	end
end

--- While `_incomingPhonePayload` is set: enforce `PENDING_INCOMING_PHONE_MAX_SEC`. `MISSED_RING_FINISHED` only if the sample stops without us deleting it (non-loop / engine edge case); looping ring normally ends via timeout or `clearPendingIncomingPhoneOffer`.
function IANeighbours.updatePendingIncomingPhoneLifecycle()
	if IANeighbours._incomingPhonePayload == nil then
		return
	end
	local now = IANeighbours._wallClockSec or 0
	local started = IANeighbours._pendingIncomingPhoneStartedWallClockSec
	if started ~= nil and IANeighbours.PENDING_INCOMING_PHONE_MAX_SEC ~= nil and IANeighbours.PENDING_INCOMING_PHONE_MAX_SEC > 0 then
		if now - started >= IANeighbours.PENDING_INCOMING_PHONE_MAX_SEC then
			IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.MISSED_TIMEOUT)
			return
		end
	end
	local sample = IANeighbours._incomingCallRingSample
	if sample ~= nil and isSamplePlaying ~= nil and not isSamplePlaying(sample) then
		IANeighbours.clearPendingIncomingPhoneOffer(IANeighbours.IncomingCallEndReason.MISSED_RING_FINISHED)
	end
end

function IANeighbours.playIncomingCallRingSound()
	IANeighbours.stopIncomingCallRingSound()
	if IANeighbours.dir == nil then
		return
	end
	local fileName = Utils.getFilename("sound/incoming_call.ogg", IANeighbours.dir)
	if fileName == nil or fileName == "" or not fileExists(fileName) then
		return
	end
	local sample = createSample("IANeighbours_incoming_call")
	if sample == nil or sample == 0 then
		return
	end
	if not loadSample(sample, fileName, false) then
		delete(sample)
		return
	end
	local loops = IANeighbours.INCOMING_CALL_RING_SAMPLE_LOOPS
	if loops == nil then
		loops = 0
	end
	playSample(sample, loops, 0.6, 0, 0, 0)
	IANeighbours._incomingCallRingSample = sample
end

--- Active standalone phone conversation or phone GUI open (blocks stacking rings / duplicate opens). Pending audio-only incoming does not set this.
function IANeighbours.isIncomingPhoneSessionActive()
	if IANeighbours.activeStandalonePhoneConversation ~= nil then
		return true
	end
	if IANeighbours.incomingPhoneRingDialogOpen == true then
		return true
	end
	return false
end

--- Recomputes _activeConversationKind / _activeConversationNeighbourId (phone ring, phone talk, or in-world IAConversationDialog).
function IANeighbours.refreshActiveConversationState()
	IANeighbours._activeConversationKind = nil
	IANeighbours._activeConversationNeighbourId = nil
	if IANeighbours.incomingPhoneRingDialogOpen == true then
		IANeighbours._activeConversationKind = "phone_ring"
		IANeighbours._activeConversationNeighbourId = IANeighbours.pendingIncomingPhoneNeighbourId
			or (IANeighbours._incomingPhonePayload ~= nil and IANeighbours._incomingPhonePayload.neighbourId or nil)
		return
	end
	if IANeighbours.activeStandalonePhoneConversation ~= nil then
		IANeighbours._activeConversationKind = "phone"
		IANeighbours._activeConversationNeighbourId = IANeighbours.activeStandalonePhoneNeighbourId
		return
	end
	-- A pending ring (audio + payload) without the dialog yet open still counts as "engaged"
	-- with that neighbour, so fieldwork won't start mid-ring.
	if IANeighbours._incomingPhonePayload ~= nil then
		IANeighbours._activeConversationKind = "phone_ring"
		IANeighbours._activeConversationNeighbourId = IANeighbours._incomingPhonePayload.neighbourId
			or IANeighbours.pendingIncomingPhoneNeighbourId
		return
	end
	for _, n in pairs(IANeighbours.neighbours or {}) do
		if n ~= nil and n.initialized and n.activeSituation ~= nil then
			local conv = n.activeSituation.conversation
			if conv ~= nil and type(conv.hasSubtitleDialogOpen) == "function" and conv:hasSubtitleDialogOpen() then
				IANeighbours._activeConversationKind = "personal"
				IANeighbours._activeConversationNeighbourId = n.id
				return
			end
		end
	end
end

--- True while phone ring/phone call or any neighbour's situation conversation subtitle dialog is open.
function IANeighbours.isPlayerInAnyConversation()
	IANeighbours.refreshActiveConversationState()
	return IANeighbours._activeConversationKind ~= nil
end

--- @return string|nil kind "phone_ring"|"phone"|"personal"|nil ; number|nil neighbourId for personal
function IANeighbours.getActiveConversationState()
	IANeighbours.refreshActiveConversationState()
	return IANeighbours._activeConversationKind, IANeighbours._activeConversationNeighbourId
end

--- True until `_wallClockSec` reaches the deadline set when any inbound phone ring was presented (audio notification).
function IANeighbours.isGlobalInboundPhoneCooldownActive()
	local untilSec = IANeighbours._globalInboundPhoneCooldownUntilWallClockSec
	if IANeighbours.debug then
		--print("--- IANeighbours.isGlobalInboundPhoneCooldownActive() - untilSec=" .. tostring(untilSec))
		--print("--- IANeighbours.isGlobalInboundPhoneCooldownActive() - wallClockSec=" .. tostring(IANeighbours._wallClockSec))
	end
	if untilSec == nil then
		return false
	end
	return (IANeighbours._wallClockSec or 0) < untilSec
end

--- Call when an inbound phone ring is presented to the player (audio notification and/or phone UI).
function IANeighbours.noteGlobalInboundPhoneCallOpened()
	local w = IANeighbours._wallClockSec or 0
	if IANeighbours.debug then
		print("--- IANeighbours.noteGlobalInboundPhoneCallOpened() - Set Cooldown to inbound call w=" .. tostring(w))
	end
	IANeighbours._globalInboundPhoneCooldownUntilWallClockSec = w + IANeighbours.GLOBAL_INBOUND_PHONE_COOLDOWN_SEC
end

function IANeighbours.onStandalonePhoneConversationClosed(conv)
	if IANeighbours.activeStandalonePhoneConversation == conv then
		IANeighbours.activeStandalonePhoneConversation = nil
		IANeighbours.activeStandalonePhoneNeighbourId = nil
	end
end

--- True when this neighbour is currently engaged with the player via phone ring, phone call, or in-world subtitle dialog.
--- Used to pause new fieldwork situation generation while the character is still talking to the player.
function IANeighbours.isNeighbourEngagedWithPlayer(neighbour)
	if neighbour == nil or neighbour.id == nil then
		return false
	end
	IANeighbours.refreshActiveConversationState()
	if IANeighbours._activeConversationNeighbourId == neighbour.id then
		return true
	end
	return false
end

--- @param table p { neighbourId, neighbourName?, conversation, isContractFieldMissionOffer? } — `conversation` must be a ready IAConversation (caller-built, e.g. via dynamicConversationData).
function IANeighbours.answerIncomingPhoneFromPayload(p)
	if p == nil or p.conversation == nil then
		if IANeighbours.debug then
			print("--- IANeighbours.answerIncomingPhoneFromPayload() - missing payload or conversation")
		end
		return
	end
	local neighbour = nil
	for _, n in pairs(IANeighbours.neighbours or {}) do
		if n ~= nil and n.id == p.neighbourId then
			neighbour = n
			break
		end
	end
	if neighbour == nil then
		if IANeighbours.debug then
			print("--- IANeighbours.answerIncomingPhoneFromPayload() - neighbour not found id=" .. tostring(p.neighbourId))
		end
		return
	end
	if p.isContractFieldMissionOffer == true then
		neighbour.contractCallRingAnsweredToday = true
	end
	local conv = p.conversation
	conv.isStandalonePhoneCall = true
	if conv.mainMenuOptions == nil and neighbour.role ~= nil and neighbour.job ~= nil then
		conv.mainMenuOptions = IAConversation.buildMainMenuOptionsFromRoleAndJob(neighbour.role, neighbour.job)
	end
	IANeighbours.activeStandalonePhoneConversation = conv
	IANeighbours.activeStandalonePhoneNeighbourId = neighbour.id
	local npcName = p.neighbourName or neighbour.name or "Neighbour"
	conv:start(0, npcName, nil)
	if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor then
		g_inputBinding:setShowMouseCursor(true)
	end
end

--- Ingame notification (same style as mission-complete OK) telling the player to open the phone for an incoming call.
--- @param string|nil callerName display name of the caller (falls back to l10n gui_phone_caller_unknown)
function IANeighbours.addIncomingPhoneIngameNotification(callerName)
	if g_currentMission == nil or g_currentMission.addIngameNotification == nil then
		return
	end
	if FSBaseMission == nil or FSBaseMission.INGAME_NOTIFICATION_OK == nil then
		return
	end
	if g_i18n == nil or g_i18n.getText == nil then
		return
	end
	local name = callerName
	if name == nil or tostring(name) == "" then
		name = g_i18n:getText("gui_phone_caller_unknown")
	end
	local msg = string.format(g_i18n:getText("gui_phone_incoming_notification"), tostring(name))
	g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
end

--- Schedule incoming ring for any topic: ring sound + payload only (no GUI). Player opens IAPhoneDialogGUI with IAStartConversation when ready.
--- Caller supplies a fully prepared IAConversation (not started yet).
--- @param IANeighbour neighbour caller (must match ringPayload.neighbourId when set)
--- @param table ringPayload { neighbourId, neighbourName?, conversation, isContractFieldMissionOffer?, skipGlobalInboundWallClock? }
--- @return boolean true if ring sound + payload were applied
function IANeighbours.tryShowIncomingPhoneRing(neighbour, ringPayload)
	if neighbour == nil or ringPayload == nil or ringPayload.conversation == nil then
		return false
	end
	local nid = ringPayload.neighbourId or neighbour.id
	if neighbour.id ~= nid then
		if IANeighbours.debug then
			print("--- IANeighbours.tryShowIncomingPhoneRing() - neighbourId mismatch")
		end
		return false
	end
	if IANeighbours._incomingPhonePayload ~= nil then
		if IANeighbours.debug then
			print("--- IANeighbours.tryShowIncomingPhoneRing() - blocked (incoming already pending or UI holds payload)")
		end
		return false
	end
	if not ringPayload.skipGlobalInboundWallClock and IANeighbours.isGlobalInboundPhoneCooldownActive() then
		return false
	end
	if IANeighbours.isPlayerInAnyConversation() then
		return false
	end
	if g_gui == nil then
		return false
	end
	if g_inGameMenu ~= nil and g_inGameMenu.isOpen == true then
		return false
	end
	IANeighbours._incomingPhonePayload = {
		neighbourId = nid,
		neighbourName = ringPayload.neighbourName or neighbour.name,
		conversation = ringPayload.conversation,
		isContractFieldMissionOffer = ringPayload.isContractFieldMissionOffer == true,
	}
	IANeighbours._pendingIncomingPhoneStartedWallClockSec = IANeighbours._wallClockSec or 0
	IANeighbours.playIncomingCallRingSound()
	if not ringPayload.skipGlobalInboundWallClock then
		IANeighbours.noteGlobalInboundPhoneCallOpened()
	end
	IANeighbours.addIncomingPhoneIngameNotification(ringPayload.neighbourName or neighbour.name)
	if IATestRunner ~= nil and IATestRunner.onPhoneRingStart ~= nil then
		IATestRunner.onPhoneRingStart(neighbour)
	end
	return true
end

--- Open phone shell from IAStartConversation when no NPC conversation is active.
--- @return boolean true if dialog was shown
function IANeighbours.tryOpenPhoneDialogFromPlayerKeybind()
	if g_gui == nil then
		return false
	end
	if not IANeighbours.ensurePhoneDialogLoaded() then
		return false
	end
	local dialog = g_gui:showDialog("IAPhoneDialogGUI")
	if dialog == nil or dialog.target == nil then
		return false
	end
	if dialog.target.setDialog then
		dialog.target:setDialog(dialog)
	end
	return true
end

--- Re-run auto-assignment for homebase and workplace now that IANeighbours.places exists (map XML / bootstrap finished after initialize()).
function IANeighbours.refreshHomebaseAssignmentsAfterPlacesBootstrap()
	for _, neighbour in pairs(IANeighbours.neighbours or {}) do
		if neighbour ~= nil and type(neighbour.tryAutoAssignHomebasePlacesIfNeeded) == "function" then
			neighbour:tryAutoAssignHomebasePlacesIfNeeded()
		end
		if neighbour ~= nil and type(neighbour.tryAutoAssignWorkplacePlacesIfNeeded) == "function" then
			neighbour:tryAutoAssignWorkplacePlacesIfNeeded()
		end
	end
	local mapId = g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId
	if mapId ~= nil and IANeighbours.xmlHelper and IANeighbours.xmlHelper.saveMapConfigToFile then
		if IANeighbours.debug then
			print("--- saveMapConfigToFile caller: IANeighbours.refreshHomebaseAssignmentsAfterPlacesBootstrap mapId=" .. tostring(mapId))
		end
		IANeighbours.xmlHelper:saveMapConfigToFile(mapId)
	end
end

--- Run after user confirms IAMapPlacesGenDialogGUI: heavy bootstrap + roadside splines, then map-init mode.
function IANeighbours.onMapPlacesBootstrapConfirmed()
	if IANeighbours.xmlHelper then
		IANeighbours.xmlHelper:bootstrapFirstRunMapPlaces()
	end
	if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
		IAMapInitJob.saveAutoPlaces(IANeighbours)
	end
	IANeighbours.refreshHomebaseAssignmentsAfterPlacesBootstrap()
	IANeighbours:reclassifyPlacesByPlayerFarmland()
	IANeighbours.mapInitJobRun = true
	IANeighbours.pendingMapPlacesBootstrap = false
	IANeighbours.mapPlacesBootstrapDialogShown = false
	if IANeighbours.debug then
		print("--- IANeighbours.onMapPlacesBootstrapConfirmed() - First-run map places generation finished")
	end
end

function IANeighbours:getModDirectory()
	return IANeighbours.dir
end

--- executed per frame
-- @param number dt delta time in milliseconds (same convention as gameMs / inbound timers in this class)
function IANeighbours:update(dt)

	-- Per-frame profiling: measure wall-clock time spent in this update (reported below if over threshold).
	-- Gated by debugPerformance so nothing is computed when profiling is off.
	local frameTimer = IANeighbours.debugPerformance and IAHelper_frameTimerStart() or nil

	if g_currentMission == nil or g_currentMission.missionInfo == nil then
		return
	end

	if g_currentMission.missionDynamicInfo ~= nil and g_currentMission.missionDynamicInfo.isMultiplayer then
		self.BlockMod = true
		return
	end

	-- First run: savegame isn't persisted yet -> show tutorial once (savegameDirectory == nil).
	-- Initialization no longer waits for the first save: persistence is gated on FSCareerMissionInfo.saveToXMLFile
	-- and every writer guards savegameDirectory == nil, so we only show the tutorial here and let update() proceed.
	if g_currentMission.missionInfo.savegameDirectory == nil and IANeighbours.firstLoadTutorialDialogShown ~= true then
		IANeighbours:maybeShowFirstLoadTutorialDialog()
	end
	if g_localPlayer == nil then
		return
	end

	-- Real-time accumulator for inbound-phone cooldown (dt is ms per frame; not in-game clock).
	IANeighbours._wallClockSec = (IANeighbours._wallClockSec or 0) + ((dt or 0) / 1000)
	IANeighbours.updatePendingIncomingPhoneLifecycle()

	-- Opening the in-game menu (ESC) can dismiss the conversation dialog without IAConversationDialog:onClose();
	-- when the menu closes, sync so onExternalDialogClose runs (cursor + situation refs) and controls work again.
	local menuOpen = g_inGameMenu ~= nil and g_inGameMenu.isOpen == true
	if IANeighbours._prevInGameMenuOpen and not menuOpen then
		IANeighbours.onInGameMenuJustClosed()
	end
	IANeighbours._prevInGameMenuOpen = menuOpen

	-- Reset roadside parking reservations each frame before neighbours run (on-foot vehicle spawn uses same-frame exclusivity)
	self.roadsideParkingReservedKeys = {}

	-- Map init job update (e.g. pending map nodes debug when requested via keybind)
	if IANeighbours.mapInitJob ~= nil and IANeighbours.mapInitJob.update ~= nil then
		IANeighbours.mapInitJob:update(dt)
	end

	if self.BlockMod == true then
		return
	end

	local activePhoneConversation = IANeighbours.activeStandalonePhoneConversation
	if activePhoneConversation ~= nil and type(activePhoneConversation.update) == "function" then
		activePhoneConversation:update(dt)
	end

	if self.savegameEventsBound == false then
		self:bindSavegameEvents()
		self.savegameEventsBound = true
	end

	-- Increment timers
	local game5Seconds = false
	self.inboundLoadTimer = self.inboundLoadTimer + dt
	self.outboundSaveTimer = self.outboundSaveTimer + dt
	self.inboundCheckTimer = self.inboundCheckTimer + dt
	self.gameMs = self.gameMs + dt
	

	if self.gameSeconds >= 5 then
		getCurrentGameHours()
		self:updateFarmlands()
		self:resetFarmlandsToDefault()
		self.gameSeconds = 0
		game5Seconds = true
	end
	if IANeighbours.gameMs >= 1000 then
		self.gameSeconds = self.gameSeconds + 1
		self.gameMs = self.gameMs - 1000
	end
		


	--drawDebugPoint(-634.0900268554688, 47.20000076293945, 100.95999908447266,50,50,50,100,false)

	-- Load outbound XML once as soon as the map is known (no longer waits for the first save / savegameDirectory).
	-- On a fresh game the outbound file doesn't exist yet; loadData() cleanly falls back to the scenario preset seed.
	if not self.outboundXMLLoaded and g_currentMission.missionInfo.mapId ~= nil then
		if IANeighbours.debug then
			print("--- IANeighbours:update() - Loading outbound XML once")
		end
		-- Check configuration before loading (succeeds even when map config is missing; neighbours/vehicles still load)
		if not self.xmlHelper:checkConfiguration() then
			if IANeighbours.debug then
				print("--- IANeighbours:update() - Configuration check failed, skipping XML load")
			end
			self.BlockMod = true
			return false
		end

		self.xmlHelper:loadData()
		self.outboundXMLLoaded = true

		-- Register NPC objects for farmer neighbours in g_npcManager
		-- This must happen AFTER neighbours are loaded from XML
		if not self._farmerNPCsRegistered then
			self:registerFarmerNPCs()
			self._farmerNPCsRegistered = true
		end

		-- Rebuild borrow-access O(1) lookup set after fleet load (may have persisted borrows)
		if IABorrowAccess ~= nil and IABorrowAccess.rebuildBorrowedIdSet ~= nil then
			IABorrowAccess.rebuildBorrowedIdSet()
		end

		if IANeighbours.debug then
			if IATestRegistry.verbose then
				print("[FOS_TEST] IATestRunner: outboundXMLLoaded = true, will call tryAutoRun()")
			end

			-- Auto-run test system: start the auto-run sequence once the mod is fully loaded
			IATestRunner.tryAutoRun()
		end

		-- When map config was missing and bootstrap was not deferred to the dialog: enable map init + roadside splines (headless path)
		if self.xmlHelper.mapConfigFileNotFound and not self.mapInitJobRun and not IANeighbours.pendingMapPlacesBootstrap then
			self.mapInitJobRun = true
			if IANeighbours.debug then
				print("--- IANeighbours:update() - Map init mode enabled (no map config for active map)")
			end
			local mapId = g_currentMission.missionInfo.mapId
			if mapId then
				local added = IAMapInitJob.saveAutoPlaces(self)
				if IANeighbours.debug and added > 0 then
					print("--- IANeighbours:update() - saveAutoPlaces added " .. tostring(added) .. " roadside places")
				end
			end
		end
	end

	-- Voice pack missing or wrong version (set in IAXMLHelper:loadData): show a one-time fail-style in-game notification
	if self.outboundXMLLoaded and IANeighbours.pendingVoicePackWarning
		and not IANeighbours.voicePackWarningNotificationShown
		and g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
		and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL ~= nil
		and g_i18n ~= nil and g_i18n.getText ~= nil then
		local tmpl = g_i18n:getText("gui_voice_pack_warn_message")
		local msg = tmpl
		if tmpl ~= nil and tmpl ~= "" then
			msg = string.format(tmpl, IANeighbours.requiredVoicePackVersionLabel())
		end
		if msg ~= nil and msg ~= "" then
			g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msg)
			IANeighbours.voicePackWarningNotificationShown = true
		end
	end

	-- Deferred first-run places: show warning dialog once (after outbound load), OK runs bootstrap + saveAutoPlaces
	if self.outboundXMLLoaded and IANeighbours.pendingMapPlacesBootstrap
		and not IANeighbours.mapPlacesBootstrapDialogShown
		and g_gui ~= nil and g_inGameMenu ~= nil and g_inGameMenu.isOpen == false then
		if IANeighbours.ensureMapPlacesGenDialogLoaded() then
			local dialog = g_gui:showDialog("IAMapPlacesGenDialogGUI")
			if dialog ~= nil then
				IANeighbours.mapPlacesBootstrapDialogShown = true
				if dialog.target and dialog.target.setDialog then
					dialog.target:setDialog(dialog)
				end
			end
		end
	end

	-- Check if it's time to save outbound XML (separate timer)
	--if self.outboundSaveTimer >= self.outboundSaveInterval then
	--	if IANeighbours.debug then
	--		print("--- IANeighbours:update() - Saving outbound XML")
	--	end
	--	IANeighbours.xmlHelper:saveOutboundXMLToXMLFile()
	--	self.outboundSaveTimer = 0  -- Reset timer
		

		--print("--- IANeighbours:update() - Player count: "..tostring(g_currentMission.playerSystem:getPlayerCount()))
		--printObj(g_currentMission.playerSystem:getPlayers(),2,"g_currentMission.playerSystem:getPlayers")
		--printObj(g_currentMission.playerSystem:getPlayerByIndex(1),2,"Player1")
		--printObj(g_currentMission.playerSystem:getPlayerByIndex(2),2,"Player2")
		

	--	if IANeighbours.debug then
	--		print("--- IANeighbours: Auto-saved outbound XML")
	--	end
	--end


	IANeighbours:updateNeighbours(dt,self.gameSeconds,game5Seconds)

	if not IANeighbours.skipBorrowUpdate and IAMissionBorrow ~= nil and type(IAMissionBorrow.update) == "function" then
		IAMissionBorrow.update(dt)
	end

	-- AI-assisted test runner: process action queue when a test is active
	if IANeighbours.debug then
		IATestRunner.update(dt)

		-- Auto-run system: count down the startup delay and launch tests when ready.
		-- Only active after outbound XML is loaded (safe to call every frame).
		if self.outboundXMLLoaded then
			IATestRunner.tryAutoRun()
		end
	end

	-- Debug drawing block: skipped entirely when skipDebugDrawing is true
	if not IANeighbours.skipDebugDrawing then
	if IANeighbours.debugVehiclePresencePositions == true then
		IANeighbours:drawVehiclePresenceDebugMarkers()
	end

	if IANeighbours.debugFieldworkBorderGeometry == true then
		IANeighbours:drawFieldworkBorderDebugMarkers()
	end

	local hasDebugPoints = next(IANeighbours.debugPoints) ~= nil
	local hasProbeSpheres = IANeighbours.collisionProbeSpheres ~= nil and #IANeighbours.collisionProbeSpheres > 0
	local hasPlaceBoxes = IANeighbours.mapInitPlaceDebugBoxes ~= nil and #IANeighbours.mapInitPlaceDebugBoxes > 0
	if hasDebugPoints or hasProbeSpheres or hasPlaceBoxes then
		-- Only draw debug markers within this distance (m) from player / current vehicle
		local debugPointDrawRangeSq = 50 * 50
		local refX, refY, refZ = nil, nil, nil
		if g_localPlayer then
			local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
			if v ~= nil and v.rootNode ~= nil and entityExists(v.rootNode) then
				refX, refY, refZ = getWorldTranslation(v.rootNode)
			end
			if refX == nil and g_localPlayer.getPosition then
				refX, refY, refZ = g_localPlayer:getPosition()
			end
		end

		if hasProbeSpheres then
			for _, sp in ipairs(IANeighbours.collisionProbeSpheres) do
				if sp ~= nil and sp.x ~= nil and sp.z ~= nil and sp.radius ~= nil and sp.radius > 0 then
					local inRange = true
					if refX ~= nil and refY ~= nil and refZ ~= nil then
						local sy = sp.y or 0
						local dx, dy, dz = sp.x - refX, sy - refY, sp.z - refZ
						inRange = (dx * dx + dy * dy + dz * dz) <= debugPointDrawRangeSq
					end
					if inRange then
						IANeighbours.drawCollisionProbeSphereWireframe(sp.x, sp.y or 0, sp.z, sp.radius, sp.r, sp.g, sp.b)
					end
				end
			end
		end

		for _, debugPoint in pairs(IANeighbours.debugPoints) do
			if debugPoint ~= nil then
				local node = type(debugPoint) == "table" and debugPoint.node or debugPoint
				local label = type(debugPoint) == "table" and debugPoint.text or nil
				if node ~= nil and entityExists(node) then
					local x, y, z = getWorldTranslation(node)
					if x ~= nil and y ~= nil and z ~= nil then
						local inRange = true
						if refX ~= nil and refY ~= nil and refZ ~= nil then
							local dx, dy, dz = x - refX, y - refY, z - refZ
							inRange = (dx * dx + dy * dy + dz * dz) <= debugPointDrawRangeSq
						end
						if inRange then
							drawDebugPoint(x, y, z, 50, 50, 50, 100, false)
							if label ~= nil and label ~= "" and Utils.renderTextAtWorldPosition and getCorrectTextSize then
								Utils.renderTextAtWorldPosition(x, y, z, label, getCorrectTextSize(0.012), 0)
							end
						end
					end
				end
			end
		end

		if hasPlaceBoxes then
			IAHelper_drawMapInitPlaceDebugBoxes(IANeighbours, refX, refY, refZ, debugPointDrawRangeSq)
		end
	end
	end -- IANeighbours.skipDebugDrawing guard

	if frameTimer ~= nil then
		IAHelper_frameTimerEnd(frameTimer, IANeighbours.frameTimeLogThresholdMs, "IANeighbours:update")
	end

end
function IANeighbours:bindSavegameEvents()

	FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
		if IANeighbours.xmlHelper ~= nil then
			pcall(function() IANeighbours.xmlHelper:saveOutboundXMLToXMLFile() end)
			pcall(function() IANeighbours.xmlHelper:saveInboundXMLToXMLFile() end)
		end
	end)

end

function IANeighbours:hideDialog()
	if IANeighbours.nearbySituation ~= nil then
		IANeighbours.nearbySituation:hideConversation()
	end
end

--- Keep the single on-foot SHIFT+R action event active and update its HUD label. The Controls/keybind menu
--- still uses input_IAStartConversation ("Conversation / Phone"); this event text is only the in-game prompt.
--- When the prompt mode changes, the action event is removed and re-registered so the FS HUD rebuilds text.
--- @param useConversationHint boolean true when a conversation can currently be started
function IANeighbours.refreshConversationActionEvents(useConversationHint)
	if g_inputBinding == nil or g_inputBinding.setActionEventActive == nil then
		return
	end
	local showConversation = useConversationHint == true
	local newState = showConversation and "conv" or "phone"
	local prevState = IANeighbours._conversationActionEventsState

	-- Falling edge of a phone session (standalone call or incoming ring just closed): the player input context
	-- can be rebuilt while the dialog is up, which may leave the SHIFT+R prompt showing a stale label that the
	-- change-only path below would never correct. Force a clean re-register from the current in-range truth so
	-- the prompt can never get stuck on "Start Conversation" (or "Use Phone") after a call. Also self-heal if the
	-- event id was lost (e.g. an engine rebuild dropped it).
	local phoneSessionActive = IANeighbours.isIncomingPhoneSessionActive()
	local phoneSessionJustEnded = IANeighbours._prevPhoneSessionActiveForPrompt == true and not phoneSessionActive
	IANeighbours._prevPhoneSessionActiveForPrompt = phoneSessionActive

	IANeighbours._conversationActionEventsState = newState
	local mustReregister = (prevState ~= newState) or phoneSessionJustEnded or IANeighbours.conversationKeybind == nil
	if mustReregister and IANeighbours.registerConversationActionEvent ~= nil then
		IANeighbours.registerConversationActionEvent(showConversation)
	elseif IANeighbours.conversationKeybind ~= nil then
		g_inputBinding:setActionEventActive(IANeighbours.conversationKeybind, true)
		g_inputBinding:setActionEventTextVisibility(IANeighbours.conversationKeybind, true)
	end
end

--- After the in-game menu closes: end (do NOT recover) any conversation whose subtitle dialog was open when the menu opened.
--- Opening the in-game menu dismisses the dialog without firing IAConversationDialog:onClose, so we tear the call down here:
--- close the dialog if the engine left/restored it, then run external-close cleanup (stops audio, plays the hang-up sound,
--- and clears the standalone-phone reference) so the player can immediately start a new conversation.
function IANeighbours.onInGameMenuJustClosed()
	if g_gui == nil then
		return
	end
	local function endConversation(conv)
		if conv == nil or conv.dialog == nil then
			return
		end
		if g_gui.currentDialog == conv.dialog or g_gui.currentDialog == "IAConversationDialog" then
			g_gui:closeDialog(conv.dialog)
		end
		if type(conv.onExternalDialogClose) == "function" then
			conv:onExternalDialogClose()
		end
	end
	IAsafePcall("IANeighbours.onInGameMenuJustClosed:endPhoneCall", function()
		endConversation(IANeighbours.activeStandalonePhoneConversation)
	end)
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.initialized and neighbour.activeSituation ~= nil then
			endConversation(neighbour.activeSituation.conversation)
		end
	end
end
function IANeighbours:sendDialogAnswer(text)
	IANeighbours.activeDialogText = text
end

function IANeighbours:enableConversationKeybind(nearbySituation)
	if nearbySituation == nil then
		return
	end
	if not IANeighbours.canStartConversation then
		if IANeighbours.debug then
			print("--- IANeighbours:enableConversationKeybind()")
		end
		IANeighbours.canStartConversation = true
		IANeighbours.nearbySituation = nearbySituation
		--g_inputBinding:setActionEventTextVisibility(self.conversationKeybind, true)
		--g_inputBinding:setActionEventActive(self.conversationKeybind, true)
		return
	end
	-- Already in range: closest neighbour can change while keybind stays on — keep pointer fresh and drop stale dialog.
	if IANeighbours.nearbySituation ~= nearbySituation then
		if IANeighbours.nearbySituation ~= nil and IANeighbours.nearbySituation.hideConversation ~= nil then
			IANeighbours.nearbySituation:hideConversation()
		end
		IANeighbours.nearbySituation = nearbySituation
	end
end
function IANeighbours:disableConversationKeybind()
	if not IANeighbours.canStartConversation then
		return
	end
	IANeighbours:hideDialog()
	IANeighbours.nearbySituation = nil
	IANeighbours.canStartConversation = false
	if IANeighbours.debug then
		print("--- IANeighbours:disableConversationKeybind()")
	end
	--g_inputBinding:setActionEventTextVisibility(self.conversationKeybind, false)
	--g_inputBinding:setActionEventActive(self.conversationKeybind, false)
end
function IANeighbours:onStartConversation(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)
	if g_localPlayer == nil then
		return
	end
	if IANeighbours.activeStandalonePhoneConversation ~= nil then
		IAprintDebug("IANeighbours:onStartConversation","blocked (active phone call)", nil, nil, nil)
		return
	end
	if IANeighbours.incomingPhoneRingDialogOpen == true then
		IAprintDebug("IANeighbours:onStartConversation","blocked (incoming phone ring dialog open)", nil, nil, nil)
		return
	end
	if IANeighbours.canStartConversation and IANeighbours.nearbySituation ~= nil then
		IANeighbours.nearbySituation:startConversation()
		IAprintDebug("IANeighbours:onStartConversation","starting conversation", nil, nil, IANeighbours.nearbySituation)
		return
	end
	-- No character in range: fall back to the phone.
	IANeighbours:onUsePhone()
end

--- Handler for InputAction.IAUsePhone: opens the standalone phone dialog. Active whenever no character is
--- in conversation range (see refreshConversationActionEvents).
function IANeighbours:onUsePhone(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)
	if g_localPlayer == nil then
		return
	end
	if IANeighbours.activeStandalonePhoneConversation ~= nil then
		IAprintDebug("IANeighbours:onUsePhone","blocked (active phone call)", nil, nil, nil)
		return
	end
	if IANeighbours.incomingPhoneRingDialogOpen == true then
		IAprintDebug("IANeighbours:onUsePhone","blocked (incoming phone ring dialog open)", nil, nil, nil)
		return
	end
	if g_inGameMenu ~= nil and g_inGameMenu.isOpen == true then
		IAprintDebug("IANeighbours:onUsePhone","blocked (in game menu open)", nil, nil, nil)
		return
	end
	IANeighbours.tryOpenPhoneDialogFromPlayerKeybind()
end

function IANeighbours:makeIANeighboursEnabledPredicate()
	return function () return true end
end

--- Set place.type to player_farm when on player-owned farmland, else restore basePlaceType (semantic type).
function IANeighbours:reclassifyPlacesByPlayerFarmland()
	-- DISABLED for now — the override causes misleading "waiting at your farm"
    -- notifications for places that aren't semantically farms (e.g. public_place,
    -- workshop, shop) but happen to sit on player-owned farmland.
    
	--return

	--if self.places == nil or g_farmlandManager == nil or g_farmlandManager.getFarmlandAtWorldPosition == nil then
	--	return
	--end
	--for _, place in ipairs(self.places) do
	--	if place == nil or place.id == nil then
	--		-- Skip ephemeral places (e.g. fieldwork with nil id)
	--	elseif place.hasWorldPosition == nil or not place:hasWorldPosition() then
	--		-- No world position yet
	--	elseif place.isPlaceableRelative and place:isPlaceableRelative() and place.x == 0 and place.z == 0 then
	--		-- Unresolved placeable-relative
	--	else
	--		if place.basePlaceType == nil then
	--			place.basePlaceType = place.type
	--		end
	--		local farmland = g_farmlandManager:getFarmlandAtWorldPosition(place.x, place.z)
	--		local playerOwned = farmland ~= nil and farmland.isOwned == true and farmland.farmId ~= 99
	--		if playerOwned then
	--			place.type = "player_farm"
	--		else
	--			place.type = place.basePlaceType
	--		end
	--	end
	--end
end

function IANeighbours:updateFarmlands()
	self:reclassifyPlacesByPlayerFarmland()
	if IANeighbours.debug then
		--print("--- IANeighbours:updateFarmlands() - Starting farmland update")
	end

	-- Only strip vanilla missions in realistic mode; classic mode leaves them intact.
	if IASettings == nil or type(IASettings.isMissionOfferModeClassic) ~= "function" or not IASettings.isMissionOfferModeClassic() then
		-- Whole map: vanilla contract / mission generation skips fields when isMissionAllowed is false (see e.g. missionTypeContractGenerator).
		if g_fieldManager ~= nil then
			local fieldsList = nil
			if type(g_fieldManager.getFields) == "function" then
				local ok, list = pcall(function()
					return g_fieldManager:getFields()
				end)
				if ok and list ~= nil then
					fieldsList = list
				end
			end
			if fieldsList == nil and type(g_fieldManager.fields) == "table" then
				fieldsList = g_fieldManager.fields
			end
			if fieldsList ~= nil then
				local stripNow = not IANeighbours.didStripVanillaFieldMissionsOnLoad
				if stripNow then
					IANeighbours.didStripVanillaFieldMissionsOnLoad = true
				end
				for _, field in pairs(fieldsList) do
					if field ~= nil then
						field.isMissionAllowed = false
						if stripNow and field.currentMission ~= nil then
							local m = field.currentMission
							local skip = m.iaFieldsOfStoriesMission == true
							if not skip and IAFieldOutcomeMission ~= nil and type(m.getMissionTypeName) == "function" then
								local okT, typeName = pcall(m.getMissionTypeName, m)
								if okT and typeName == IAFieldOutcomeMission.NAME then
									skip = true
								end
							end
							if not skip and m.ownerFarmId == 0 and type(m.delete) == "function" then
								if IANeighbours.debug then
									print("--- IANeighbours:updateFarmlands() - First-load strip vanilla field mission id=" .. tostring(m.id))
								end
								m:delete()
							end
						end
					end
				end
			end
		end
	else
		-- Classic mode: restore isMissionAllowed so vanilla contracts can exist and aren't removed by the engine.
		if g_fieldManager ~= nil then
			local fieldsList = nil
			if type(g_fieldManager.getFields) == "function" then
				local ok, list = pcall(function()
					return g_fieldManager:getFields()
				end)
				if ok and list ~= nil then
					fieldsList = list
				end
			end
			if fieldsList == nil and type(g_fieldManager.fields) == "table" then
				fieldsList = g_fieldManager.fields
			end
			if fieldsList ~= nil then
				for _, field in pairs(fieldsList) do
					if field ~= nil then
						field.isMissionAllowed = true
					end
				end
			end
		end
	end
	
	local farmlands = g_farmlandManager:getFarmlands()

	-- Live density sample vs Field cache: FieldState:update(worldX, worldZ) (engine; see FieldManager debug / GDN).
	local IA_DEBUG_FIELDSTATE_FARMLAND_ID = nil--110
	if IANeighbours.debug then
		local dbgFarmland = nil
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == IA_DEBUG_FIELDSTATE_FARMLAND_ID then
				dbgFarmland = f
				break
			end
		end
		if dbgFarmland ~= nil and dbgFarmland.field ~= nil then
			local field = dbgFarmland.field
			local cx, cz = nil, nil
			if type(field.getCenterOfFieldWorldPosition) == "function" then
				cx, cz = field:getCenterOfFieldWorldPosition()
			end
			local function fieldStateToStr(label, fs)
				if fs == nil then
					return label .. "=nil"
				end
				return string.format(
					"%s valid=%s fruit=%s growth=%s ground=%s spray=%s/%s lime=%s plow=%s weed=%s roller=%s stones=%s",
					label,
					tostring(fs.isValid),
					tostring(fs.fruitTypeIndex),
					tostring(fs.growthState),
					tostring(fs.groundType),
					tostring(fs.sprayType),
					tostring(fs.sprayLevel),
					tostring(fs.limeLevel),
					tostring(fs.plowLevel),
					tostring(fs.weedState),
					tostring(fs.rollerLevel),
					tostring(fs.stoneLevel)
				)
			end
			local cachedStr = "cached=n/a"
			if type(field.getFieldState) == "function" then
				local okC, fsCached = pcall(field.getFieldState, field)
				if okC and fsCached ~= nil then
					cachedStr = fieldStateToStr("cached", fsCached)
				elseif not okC then
					cachedStr = "cached pcall error: " .. tostring(fsCached)
				end
			end
			local sampledStr = "sampled=n/a"
			if cx ~= nil and cz ~= nil and FieldState ~= nil and type(FieldState.new) == "function" then
				local probe = FieldState.new()
				if type(probe.update) == "function" then
					local okU, errU = pcall(probe.update, probe, cx, cz)
					if okU then
						sampledStr = fieldStateToStr("sampled(FieldState:update)", probe)
					else
						sampledStr = "sampled FieldState:update error: " .. tostring(errU)
					end
				else
					sampledStr = "sampled: FieldState instance has no update()"
				end
			elseif cx == nil or cz == nil then
				sampledStr = "sampled: no field center (getCenterOfFieldWorldPosition)"
			end
			print(string.format(
				"--- IANeighbours:updateFarmlands() - fieldState debug farmlandId=%s center=(%.2f, %.2f) | %s | %s",
				tostring(IA_DEBUG_FIELDSTATE_FARMLAND_ID),
				cx or 0,
				cz or 0,
				cachedStr,
				sampledStr
			))
		else
			print("--- IANeighbours:updateFarmlands() - fieldState debug: no farmland or field for id " .. tostring(IA_DEBUG_FIELDSTATE_FARMLAND_ID))
		end
	end

	local totalFarmlands = 0
	local ownedFarmlands = 0
	local unownedFarmlandsCount = 0
	for _, farmland in pairs(farmlands) do
		if farmland ~= nil then
			totalFarmlands = totalFarmlands + 1
			if farmland.isOwned == true and farmland.farmId ~= 99 then
				ownedFarmlands = ownedFarmlands + 1
			else
				unownedFarmlandsCount = unownedFarmlandsCount + 1
				if farmland.farmId == 0 then
					--farmland:setOwnerFarmId(99)
					--farmland.npcIndex = 0
				end
				--farmland.showOnFarmlandsScreen = false
			end
		end
	end
	if IANeighbours.debug then
		--print("--- IANeighbours:updateFarmlands() - Total farmlands: "..tostring(totalFarmlands)..", Owned: "..tostring(ownedFarmlands)..", Unowned: "..tostring(unownedFarmlandsCount))
	end
	
	-- First, remove farmlands from assignedFarmlands if they are now owned by player
	local removedCount = 0
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.assignedFarmlands ~= nil then
			local toRemove = {}
			for i, farmlandId in ipairs(neighbour.assignedFarmlands) do
				-- Find farmland by ID
				local farmland = nil
				for _, f in pairs(farmlands) do
					if f ~= nil and f.id == farmlandId then
						farmland = f
						break
					end
				end
				if farmland ~= nil and farmland.isOwned == true and farmland.farmId ~= 99 then
					table.insert(toRemove, i)
					if IANeighbours.debug then
						print("--- IANeighbours:updateFarmlands() - Removing farmland "..tostring(farmlandId).." from "..neighbour.name.." (now owned by player)")
					end
				end
			end
			-- Remove in reverse order to maintain indices; clear lastCrop for unassigned farmlands
			for i = #toRemove, 1, -1 do
				local farmlandId = neighbour.assignedFarmlands[toRemove[i]]
				table.remove(neighbour.assignedFarmlands, toRemove[i])
				if farmlandId ~= nil then
					if neighbour.assignedFarmlandLastCrop ~= nil then
						neighbour.assignedFarmlandLastCrop[farmlandId] = nil
					end
					if neighbour.assignedFarmlandNextCrop ~= nil then
						neighbour.assignedFarmlandNextCrop[farmlandId] = nil
					end
				end
				removedCount = removedCount + 1
			end
		end
	end
	if IANeighbours.debug and removedCount > 0 then
		--print("--- IANeighbours:updateFarmlands() - Removed "..tostring(removedCount).." farmlands from neighbours (now owned)")
	end
	
	-- Get all farmer neighbours (job=Farmer and role=Neighbour)
	local farmerNeighbours = {}
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil then
			if IANeighbours.debug then
				--print("--- IANeighbours:updateFarmlands() - Checking neighbour: "..neighbour.name..", job: "..tostring(neighbour.job)..", role: "..tostring(neighbour.role))
			end
			if neighbour.job == "Farmer" and neighbour.role == "Neighbour" then
				table.insert(farmerNeighbours, neighbour)
				if IANeighbours.debug then
					--print("--- IANeighbours:updateFarmlands() - Added farmer neighbour: "..neighbour.name)
				end
			end
		end
	end
	
	if IANeighbours.debug then
		--print("--- IANeighbours:updateFarmlands() - Found "..tostring(#farmerNeighbours).." farmer neighbours")
	end
	
	-- If no farmer neighbours exist, return early
	if #farmerNeighbours == 0 then
		if IANeighbours.debug then
			--print("--- IANeighbours:updateFarmlands() - No farmer neighbours found, returning early")
		end
		return
	end
	
	-- Track which farmlands are already assigned
	local assignedFarmlandIds = {}
	for _, neighbour in pairs(farmerNeighbours) do
		if neighbour.assignedFarmlands ~= nil then
			if IANeighbours.debug then
				--print("--- IANeighbours:updateFarmlands() - "..neighbour.name.." has "..tostring(#neighbour.assignedFarmlands).." assigned farmlands")
			end
			for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
				assignedFarmlandIds[farmlandId] = true
			end
		end
	end
	
	-- Assign unowned farmlands to farmer neighbours (only farmlands that actually have fields)
	local unownedFarmlands = {}
	for _, farmland in pairs(farmlands) do
		if farmland ~= nil and farmland.field ~= nil and (farmland.isOwned == false or farmland.farmId == 99) and not assignedFarmlandIds[farmland.id] then
			table.insert(unownedFarmlands, farmland.id)
		end
	end
	
	if IANeighbours.debug then
		--print("--- IANeighbours:updateFarmlands() - Found "..tostring(#unownedFarmlands).." unowned farmlands to assign")
	end
	
	-- Distribute unowned farmlands evenly among farmer neighbours
	if #unownedFarmlands > 0 then
		local currentNeighbourIndex = 1
		local assignedCount = 0
		for _, farmlandId in ipairs(unownedFarmlands) do
			local neighbour = farmerNeighbours[currentNeighbourIndex]
			if neighbour ~= nil then
				if neighbour.assignedFarmlands == nil then
					neighbour.assignedFarmlands = {}
				end
				table.insert(neighbour.assignedFarmlands, farmlandId)
				assignedCount = assignedCount + 1
				if IANeighbours.debug then
					print("--- IANeighbours:updateFarmlands() - Assigned farmland "..tostring(farmlandId).." to "..neighbour.name)
				end
				currentNeighbourIndex = currentNeighbourIndex + 1
				if currentNeighbourIndex > #farmerNeighbours then
					currentNeighbourIndex = 1
				end
			end
		end
		if IANeighbours.debug then
			--print("--- IANeighbours:updateFarmlands() - Assigned "..tostring(assignedCount).." farmlands to farmer neighbours")
		end
	end
	
	-- Sync last crop from field state only when the field has a valid fruit type (e.g. growing or harvested).
	-- When the field has no fruitTypeIndex (plowed/cultivated) we do not overwrite – keep the last known value.
	for _, neighbour in pairs(farmerNeighbours) do
		if neighbour ~= nil and neighbour.assignedFarmlands ~= nil then
			if neighbour.assignedFarmlandLastCrop == nil then
				neighbour.assignedFarmlandLastCrop = {}
			end
			for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
				local farmland = nil
				for _, f in pairs(farmlands) do
					if f ~= nil and f.id == farmlandId then
						farmland = f
						break
					end
				end
				local fieldState = (farmland and farmland.field and farmland.field.fieldState) and farmland.field.fieldState or nil
				local idx = (fieldState and fieldState.fruitTypeIndex ~= nil) and fieldState.fruitTypeIndex or nil
				-- Only update when field has a valid crop index; do not overwrite with nil/0/UNKNOWN (keeps last known value)
				if idx ~= nil and (FruitType.UNKNOWN == nil or idx ~= FruitType.UNKNOWN) and idx ~= 0 then
					local prevLast = neighbour.assignedFarmlandLastCrop ~= nil and neighbour.assignedFarmlandLastCrop[farmlandId] or nil
					neighbour.assignedFarmlandLastCrop[farmlandId] = idx
					-- Update stored next crop only when lastCrop changed or we have none (avoid re-rolling every frame)
					if neighbour.assignedFarmlandNextCrop == nil then
						neighbour.assignedFarmlandNextCrop = {}
					end
					if prevLast ~= idx or neighbour.assignedFarmlandNextCrop[farmlandId] == nil then
						if IANeighbours.gameLoopHelper ~= nil then
							local nextCrop = IANeighbours.gameLoopHelper:getNextCropForField(neighbour, farmlandId)
							neighbour.assignedFarmlandNextCrop[farmlandId] = nextCrop
						end
					end
					if IANeighbours.debug then
						local ft = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(idx)
						local nameStr = (ft and ft.name) or tostring(idx)
						--print("--- IANeighbours:updateFarmlands() - Sync lastCrop "..tostring(neighbour.name).." farmland "..tostring(farmlandId).." -> "..tostring(nameStr).." ("..tostring(idx)..")")
					end
				elseif idx == nil or idx == 0 or (FruitType.UNKNOWN ~= nil and idx == FruitType.UNKNOWN) then
					-- Bare / fallow: no fruitTypeIndex sync, but still assign planned next crop once (SEED / schedule / outbound XML).
					if neighbour.assignedFarmlandNextCrop == nil then
						neighbour.assignedFarmlandNextCrop = {}
					end
					if neighbour.assignedFarmlandNextCrop[farmlandId] == nil and IANeighbours.gameLoopHelper ~= nil then
						neighbour.assignedFarmlandNextCrop[farmlandId] = IANeighbours.gameLoopHelper:getNextCropForField(neighbour, farmlandId)
					end
				end


				-- Set NPC index for this farmland to the neighbour's registered NPC
				if neighbour.registeredNpc ~= nil then
					farmland.npcIndex = neighbour.registeredNpc.index
				end
			end
		end
	end

	-- First-time only (brand-new save): normalize foreign crops on character-assigned fields to wheat (harvest-ready).
	self:normalizeAssignedFieldCropsOnFirstLoad(farmlands, farmerNeighbours)
	
	if IANeighbours.debug then
		for _, neighbour in pairs(farmerNeighbours) do
			local count = neighbour.assignedFarmlands ~= nil and #neighbour.assignedFarmlands or 0
			print("--- IANeighbours:updateFarmlands() - "..tostring(neighbour.name).." has "..tostring(count).." assigned farmlands")
		end
		print("--- IANeighbours:updateFarmlands() - Finished farmland update")
	end
end

--- First-time-only pass (runs once on a brand-new save, savegameDirectory == nil): for every farmland just
--- assigned to a Farmer neighbour, read the field's current crop. If a crop is seeded that is NOT in the
--- character's allowed harvest list (IAFieldwork.CHARACTER_HARVEST_FRUIT_NAMES), switch that field to wheat
--- in a harvest-ready state. Empty/fallow fields are left untouched.
-- @param table farmlands g_farmlandManager:getFarmlands() result (kept in sync with caller)
-- @param table farmerNeighbours list of Farmer/Neighbour entries with assignedFarmlands
function IANeighbours:normalizeAssignedFieldCropsOnFirstLoad(farmlands, farmerNeighbours)
	if IANeighbours.didNormalizeAssignedFieldCropsOnFirstLoad == true then
		return
	end
	-- Only on a fresh game start (no persisted savegame yet).
	if g_currentMission == nil or g_currentMission.missionInfo == nil or g_currentMission.missionInfo.savegameDirectory ~= nil then
		return
	end
	if IAFieldwork == nil or type(IAFieldwork.isFruitTypeInCharacterHarvestList) ~= "function" then
		return
	end
	if farmerNeighbours == nil or #farmerNeighbours == 0 then
		return
	end

	-- Wait until assignment actually produced farmlands (field density maps are loaded by the time the mission runs).
	local anyAssigned = false
	for _, neighbour in pairs(farmerNeighbours) do
		if neighbour ~= nil and neighbour.assignedFarmlands ~= nil and #neighbour.assignedFarmlands > 0 then
			anyAssigned = true
			break
		end
	end
	if not anyAssigned then
		return
	end

	local function findFarmland(farmlandId)
		for _, f in pairs(farmlands) do
			if f ~= nil and f.id == farmlandId then
				return f
			end
		end
		return nil
	end

	local convertedCount = 0
	local processedFarmlands = {}

	for _, neighbour in pairs(farmerNeighbours) do
		if neighbour ~= nil and neighbour.assignedFarmlands ~= nil then
			for _, farmlandId in ipairs(neighbour.assignedFarmlands) do
				if not processedFarmlands[farmlandId] then
					processedFarmlands[farmlandId] = true
					local farmland = findFarmland(farmlandId)
					local field = (farmland ~= nil) and farmland.field or nil
					local fieldState = (field ~= nil) and field.fieldState or nil
					local fruitIndex = (fieldState ~= nil) and fieldState.fruitTypeIndex or nil
					-- Only act on fields that actually have a (valid, non-empty) crop seeded.
					local hasCrop = fruitIndex ~= nil and fruitIndex ~= 0
						and (FruitType.UNKNOWN == nil or fruitIndex ~= FruitType.UNKNOWN)
					if hasCrop and not IAFieldwork.isFruitTypeInCharacterHarvestList(fruitIndex) then
						-- Pick a random allowed crop for this field instead of always wheat.
						local newCrop = IAFieldwork.getRandomCharacterHarvestFruitIndex(fruitIndex)
						if newCrop ~= nil and IAFieldwork.enqueueSetFieldToCropHarvestReady(field, newCrop) then
							convertedCount = convertedCount + 1
							-- Keep the neighbour's crop bookkeeping consistent with the new crop.
							if neighbour.assignedFarmlandLastCrop == nil then
								neighbour.assignedFarmlandLastCrop = {}
							end
							neighbour.assignedFarmlandLastCrop[farmlandId] = newCrop
							if IANeighbours.debug then
								local fromFt = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
								local fromName = (fromFt and fromFt.name) or tostring(fruitIndex)
								local toFt = (g_fruitTypeManager and g_fruitTypeManager.getFruitTypeByIndex) and g_fruitTypeManager:getFruitTypeByIndex(newCrop)
								local toName = (toFt and toFt.name) or tostring(newCrop)
								print("--- IANeighbours:normalizeAssignedFieldCropsOnFirstLoad() - "..tostring(neighbour.name).." farmland "..tostring(farmlandId)..": foreign crop "..tostring(fromName).." -> "..tostring(toName).." (harvest-ready)")
							end
						end
					end
				end
			end
		end
	end

	IANeighbours.didNormalizeAssignedFieldCropsOnFirstLoad = true
	if IANeighbours.debug then
		print("--- IANeighbours:normalizeAssignedFieldCropsOnFirstLoad() - Converted "..tostring(convertedCount).." foreign-crop field(s) to wheat (harvest-ready)")
	end
end
function IANeighbours:updateNeighbours(dt,gameSeconds,game5Seconds)
	-- Performance guard: skip entire neighbour update loop when toggled via iaPerfToggleNeighbours
	if IANeighbours.skipNeighbourUpdate then
		return
	end
	local _timer = IANeighbours.debugPerformance and IAHelper_frameTimerStart() or nil
	local neighbourInRange = false
	local nearbySituation = nil
	local bestDistance = nil
	-- Update all initialized neighbours and check if any is in conversation range
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and type(neighbour.update) == "function" then
			neighbour:update(dt,gameSeconds,game5Seconds)
			-- Check if this neighbour is in conversation range
			--print("--- IANeighbours:updateNeighbours() - "..neighbour.name.." distance to player: "..tostring(neighbour.distanceToPlayer))
			if g_localPlayer ~= nil and IANeighbours.conversationKeybind ~= nil then
				if neighbour.initialized and neighbour.distanceToPlayer ~= nil then
					-- Check if neighbour is in conversation range (distance < 20)
					local sit = neighbour.activeSituation
					--print("--- IANeighbours:updateNeighbours() - "..neighbour.name.." distance to player: "..tostring(neighbour.distanceToPlayer))
					--print("--- IANeighbours:updateNeighbours() - "..neighbour.name.." activeSituation: "..tostring(sit))
					--print("--- IANeighbours:updateNeighbours() - "..neighbour.name.." characterVisibility: "..tostring(sit ~= nil and sit.characterVisibility or nil))
					-- Fieldwork forces characterVisibility to "no" in IASituation; when AI is paused and NPC is shown on foot (npcVisibleWhilePaused), allow conversation range like "yes"/"in_car".
					local visibilityOk = sit ~= nil and (sit.characterVisibility == "yes" or sit.characterVisibility == "in_car")
					local fieldworkOnFoot = sit ~= nil and sit.jobType ~= nil and sit.npcVisibleWhilePaused == true
					if neighbour.distanceToPlayer < 5 and sit ~= nil and (visibilityOk or fieldworkOnFoot)
						and neighbour.npcInstance ~= nil and neighbour.npcInstance.isActive then
						if bestDistance == nil or neighbour.distanceToPlayer < bestDistance then
							bestDistance = neighbour.distanceToPlayer
							neighbourInRange = true
							nearbySituation = sit
						end
						if IANeighbours.debug then
							--print("--- IANeighbours:updateNeighbours() - "..neighbour.name.." is in range: "..tostring(neighbour.distanceToPlayer))
						end
					end
				end
			end
		end
	end
	
	-- Enable or disable conversation keybind based on whether any neighbour is in range
	--print("--- IANeighbours:updateNeighbours() - neighbourInRange: "..tostring(neighbourInRange)..", g_localPlayer:getIsInVehicle(): "..tostring(g_localPlayer:getIsInVehicle()))
	local playerIsInVehicle = g_localPlayer ~= nil and g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle()
	local conversationAvailable = neighbourInRange and not playerIsInVehicle and not IANeighbours.isIncomingPhoneSessionActive()
	if conversationAvailable then
		IANeighbours:enableConversationKeybind(nearbySituation)
	else
		IANeighbours:disableConversationKeybind()
	end
	IANeighbours.refreshConversationActionEvents(conversationAvailable)
	if _timer ~= nil then
		IAHelper_frameTimerEnd(_timer, IANeighbours.frameTimeLogThresholdMs, "updateNeighbours")
	end
end



function IANeighbours:loadVehicleIdMapping()
	if g_currentMission.missionInfo.savegameDirectory == nil then
		return
	end
	local filePath = g_currentMission.missionInfo.savegameDirectory.."/IANeighbours_outbound.xml"
	
	if not fileExists(filePath) then
		if IANeighbours.debug then
			print("--- IANeighbours:loadVehicleIdMapping() - Outbound file does not exist: "..filePath)
		end
		IANeighbours.vehicleIdMapping = {}
		return
	end
	
	local xmlFile = loadXMLFile("IANeighboursOutbound", filePath)
	
	if xmlFile == nil then
		if IANeighbours.debug then
			print("--- IANeighbours:loadVehicleIdMapping() - Failed to load outbound XML file: "..filePath)
		end
		IANeighbours.vehicleIdMapping = {}
		return
	end
	
	-- Clear existing mapping
	IANeighbours.vehicleIdMapping = {}
	
	-- Read vehicle mappings
	local rootKey = "IANeighboursOutbound"
	local vehicleIndex = 0
	while true do
		local vehicleKey = rootKey..".vehicles.vehicle("..vehicleIndex..")"
		local externalId = getXMLString(xmlFile, vehicleKey.."#externalId", nil)
		
		if externalId == nil then
			break
		end
		
		local uniqueId = getXMLString(xmlFile, vehicleKey.."#uniqueId", nil)
		if uniqueId ~= nil then
			IANeighbours.vehicleIdMapping[externalId] = uniqueId
			if IANeighbours.debug then
				--print("--- IANeighbours:loadVehicleIdMapping() - Loaded mapping: "..externalId.." -> "..uniqueId)
			end
		end
		
		vehicleIndex = vehicleIndex + 1
	end
	
	delete(xmlFile)
	
	if IANeighbours.debug then
		--print("--- IANeighbours:loadVehicleIdMapping() - Loaded "..tostring(vehicleIndex).." vehicle mappings")
	end
end
-- Get IANeighbourVehicle and its neighbour by game vehicle uniqueId
-- @param number|string uniqueId - Game vehicle uniqueId
-- @return IANeighbourVehicle|nil, IANeighbour|nil
function IANeighbours:getIANeighbourVehicleByUniqueId(uniqueId)
	if uniqueId == nil or self.neighbours == nil then
		return nil, nil
	end
	local uid = tostring(uniqueId)
	for _, neighbour in pairs(self.neighbours) do
		if neighbour ~= nil and neighbour.vehicles ~= nil then
			for _, ia_vehicle in pairs(neighbour.vehicles) do
				if ia_vehicle ~= nil and ia_vehicle.uniqueId ~= nil and tostring(ia_vehicle.uniqueId) == uid then
					return ia_vehicle, neighbour
				end
			end
		end
	end
	return nil, nil
end

function IANeighbours:addDebugPoint(node)
	table.insert(IANeighbours.debugPoints, node)
end

--- Add a debug point at world position (x, y, z). Drawn every frame in update. Optional label and rotation (yaw radians).
-- @param number x world X
-- @param number y world Y
-- @param number z world Z
-- @param string|nil text optional label (e.g. place type) to render at position
-- @param number|nil rotationY optional yaw in radians (so the "2 units behind" tick uses correct direction)
function IANeighbours:addDebugPointAtPosition(x, y, z, text, rotationY)
	if x == nil or y == nil or z == nil then
		return
	end
	if g_currentMission == nil or g_currentMission.terrainRootNode == nil then
		return
	end
	local node = createTransformGroup("IAMapInitPlaceDebug")
	if node == nil or node == 0 then
		return
	end
	setTranslation(node, x, y, z)
	if rotationY ~= nil then
		setRotation(node, 0, rotationY, 0)
	end
	link(g_currentMission.terrainRootNode, node)
	if text ~= nil and text ~= "" then
		table.insert(IANeighbours.debugPoints, { node = node, text = text })
	else
		table.insert(IANeighbours.debugPoints, node)
	end
	return node
end

--- Remove one debug point created by addDebugPointAtPosition (or raw node entry). Does not clear map-init parents or probe spheres.
function IANeighbours:removeDebugPointNode(node)
	if node == nil or node == 0 or IANeighbours.debugPoints == nil then
		return
	end
	for i = #IANeighbours.debugPoints, 1, -1 do
		local debugPoint = IANeighbours.debugPoints[i]
		local n = type(debugPoint) == "table" and debugPoint.node or debugPoint
		if n == node then
			if entityExists(node) then
				unlink(node)
				delete(node)
			end
			table.remove(IANeighbours.debugPoints, i)
			return
		end
	end
end

--- Overlap callback used by isPositionBlockedByCollision: collects transform IDs of overlapping collision shapes.
function IANeighbours:overlapCollectorCallback(transformId)
	if transformId ~= nil then
		-- Use instance storage so helpers don't depend on the global singleton name.
		table.insert(self._overlapCollectorIds or {}, transformId)
	end
	return true
end

--- Raw world-position overlap (overlapSphere + filters). For map places, use IAMapPlace:isBlockedByCollision(options).
-- Uses physics overlapSphere; terrain is excluded so only buildings, vehicles, placeables, etc. count as blocking.
-- For map places, callers (IAMapPlace:isBlockedByCollision) pass y = surfaceY + radius so the probe does not extend below ground.
-- @param number x world X
-- @param number y world Y
-- @param number z world Z
-- @param number radiusM optional radius in meters (default PLACE_COLLISION_CHECK_RADIUS)
-- @param number|table excludeNodeId optional: single node id, or table of node ids to exclude (node and all nested children not counted as blocking)
-- @return boolean blocked, table blockingInfos (array of "name (id=N)" strings), table blockingNodeIds (array of node ids for debug points)
-- [deprecated] isPositionBlockedByCollision moved to getPositionBlockedByCollision(neighbours, ...) in IAHelper.lua

--- Draw a wireframe “sphere” as three great circles at (px,py,pz) with radius radiusM. Uses DebugUtil.drawDebugCircle (XZ) + drawDebugLine (XY and YZ). RGB 0–255 converted to 0–1 for DebugUtil.
function IANeighbours.drawCollisionProbeSphereWireframe(px, py, pz, radiusM, r255, g255, b255)
	if radiusM == nil or radiusM <= 0 or px == nil or pz == nil then
		return
	end
	local pyv = py or 0
	local r = math.max(0, math.min(1, (r255 or 80) / 255))
	local g = math.max(0, math.min(1, (g255 or 200) / 255))
	local bcol = math.max(0, math.min(1, (b255 or 255) / 255))
	local col = { r, g, bcol }
	local steps = math.max(18, math.min(40, math.floor(radiusM * 12 + 18)))
	if DebugUtil ~= nil and DebugUtil.drawDebugCircle ~= nil then
		DebugUtil.drawDebugCircle(px, pyv, pz, radiusM, steps, col, false, false, false)
	end
	if drawDebugLine == nil then
		return
	end
	local function seg(x1, y1, z1, x2, y2, z2)
		drawDebugLine(x1, y1, z1, r, g, bcol, x2, y2, z2, r, g, bcol)
	end
	for i = 1, steps do
		local a1 = ((i - 1) / steps) * 2 * math.pi
		local a2 = (i / steps) * 2 * math.pi
		-- XY plane at world Z = pz
		local xa1, ya1 = px + math.cos(a1) * radiusM, pyv + math.sin(a1) * radiusM
		local xa2, ya2 = px + math.cos(a2) * radiusM, pyv + math.sin(a2) * radiusM
		seg(xa1, ya1, pz, xa2, ya2, pz)
		-- YZ plane at world X = px
		local yb1, zb1 = pyv + math.cos(a1) * radiusM, pz + math.sin(a1) * radiusM
		local yb2, zb2 = pyv + math.cos(a2) * radiusM, pz + math.sin(a2) * radiusM
		seg(px, yb1, zb1, px, yb2, zb2)
	end
end

--- Get debug box length in meters for a place. Single source of truth for all place debug display.
-- @param boolean withVehicle legacy size flag
-- @param boolean withAttachment legacy size flag
-- @param string sizeType optional (character/vehicle/vehicle_attachment/oversize_vehicle/large_area)
function IANeighbours.getPlaceDebugBoxLength(withVehicle, withAttachment, sizeType)
	local st = sizeType ~= nil and string.lower(tostring(sizeType)) or nil
	if st == "large_area" then
		return IANeighbours.PLACE_DEBUG_BOX_LENGTH_LARGE_AREA
	end
	if st == "oversize_vehicle" then
		return IANeighbours.PLACE_DEBUG_BOX_LENGTH_OVERSIZE
	end
	if withAttachment == true then
		return IANeighbours.PLACE_DEBUG_BOX_LENGTH_ATTACH
	end
	if withVehicle == true then
		return IANeighbours.PLACE_DEBUG_BOX_LENGTH_VEHICLE
	end
	return nil
end

--- Get debug box half-width (side extent) in meters for a place. Default PLACE_DEBUG_SIDE_M; "large_area" widens it.
-- @param boolean withVehicle legacy size flag (currently unused; kept for symmetry with getPlaceDebugBoxLength)
-- @param boolean withAttachment legacy size flag (currently unused; kept for symmetry)
-- @param string sizeType optional (character/vehicle/vehicle_attachment/oversize_vehicle/large_area)
function IANeighbours.getPlaceDebugBoxSide(withVehicle, withAttachment, sizeType)
	local st = sizeType ~= nil and string.lower(tostring(sizeType)) or nil
	if st == "large_area" then
		return IANeighbours.PLACE_DEBUG_SIDE_LARGE_AREA
	end
	return IANeighbours.PLACE_DEBUG_SIDE_M
end

--- For long attach debug box: world positions of rear collision probes (excluding center). Empty if not withAttachment or no back span.
-- Uses getWorldPositionFromYawLocalOffset — same frame as IAHelper_computePlaceDebugBoxCorners (local offset (off[1], 0, off[2]); back at local Z = −back).
function IANeighbours.getAttachBackProbeWorldPositions(centerX, centerY, centerZ, rotationY, withVehicle, withAttachment, sizeType)
	if withAttachment ~= true or centerX == nil or centerZ == nil then
		return {}
	end
	local boxLen = IANeighbours.getPlaceDebugBoxLength(withVehicle, withAttachment, sizeType)
	if boxLen == nil or boxLen <= 0 then
		return {}
	end
	local front = IANeighbours.PLACE_DEBUG_FRONT_M or 3
	local back = math.max(0, boxLen - front)
	if back <= 0 then
		return {}
	end
	local fracs = IANeighbours.PLACE_ATTACH_BACK_PROBE_FRACTIONS
	if fracs == nil or #fracs == 0 then
		fracs = { 1 / 3, 2 / 3 }
	end
	local ry = rotationY or 0
	local cy = centerY or 0
	local out = {}
	for _, frac in ipairs(fracs) do
		if frac ~= nil and frac > 0 then
			local localZ = -back * frac
			local wx, _, wz = getWorldPositionFromYawLocalOffset(centerX, cy, centerZ, ry, 0, 0, localZ)
			if wx ~= nil and wz ~= nil then
				table.insert(out, { wx, wz })
			end
		end
	end
	return out
end

--- Merge two isPositionBlockedByCollision results; dedupes blockingNodeIds while keeping parallel blockingInfos.
function IANeighbours.mergeBlockingCollisionResults(blocked1, infos1, ids1, blocked2, infos2, ids2)
	if blocked2 ~= true then
		return blocked1, infos1, ids1
	end
	if blocked1 ~= true then
		return blocked2, infos2, ids2
	end
	infos1, ids1 = infos1 or {}, ids1 or {}
	infos2, ids2 = infos2 or {}, ids2 or {}
	local infos, ids = {}, {}
	local seen = {}
	for i, nid in ipairs(ids1) do
		if nid ~= nil and not seen[nid] then
			seen[nid] = true
			table.insert(ids, nid)
			table.insert(infos, infos1[i] or ("id=" .. tostring(nid)))
		end
	end
	for i, nid in ipairs(ids2) do
		if nid ~= nil and not seen[nid] then
			seen[nid] = true
			table.insert(ids, nid)
			table.insert(infos, infos2[i] or ("id=" .. tostring(nid)))
		end
	end
	return true, infos, ids
end

--- Add center debug point and optional corner box for one place. Use this from rebuildMapInitDebugPoints and Map Init dialog to avoid duplicating logic.
-- When IANeighbours.debug is true: appends collision status " [blocked: ...]" / " [OK]" / " [ignoreCollision]" and may add points at blocking nodes; draws a 2.5 m wireframe sphere (visual only).
-- When debug is false: no collision queries (fast path when many place markers are rebuilt at once).
-- @param number excludeNodeId optional extra exclude root (merged in IAMapPlace:isBlockedByCollision when placeRef set)
-- @param boolean ignoreCollision optional when true: do not run overlap check; label shows collision check off (debug only)
-- @param table placeRef optional IAMapPlace — when set, collision matches situation selection / isPlaceBlockedByCollision (Y from terrain, full collision excludes)
function IANeighbours:addPlaceDebugPointsAt(x, y, z, rotation, label, withVehicle, withAttachment, excludeNodeId, ignoreCollision, placeRef, sizeType)
	if x == nil or z == nil or label == nil then
		return
	end
	local rot = rotation or 0
	local yVal = (y ~= nil) and y or 0
	local blocked, blockingInfos, blockingNodeIds = false, {}, {}
	local statusSuffix = ""
	if IANeighbours.debug == true then
		if ignoreCollision == true then
			statusSuffix = " [ignoreCollision]"
		else
			if placeRef ~= nil and placeRef.isBlockedByCollision ~= nil then
				blocked, blockingInfos, blockingNodeIds = placeRef:isBlockedByCollision({ excludeNodeIds = excludeNodeId })
			else
				local physR = IANeighbours.PLACE_COLLISION_CHECK_RADIUS or 0.5
				if withVehicle ~= true and withAttachment ~= true then
					physR = IANeighbours.PLACE_COLLISION_CHECK_RADIUS_CHARACTER_ONLY or 0.25
				end
				blocked, blockingInfos, blockingNodeIds = getPositionBlockedByCollision(self, x, yVal + physR, z, nil, excludeNodeId)
				if withAttachment == true then
					local probes = IANeighbours.getAttachBackProbeWorldPositions(x, yVal, z, rot, withVehicle, withAttachment, sizeType)
					for _, p in ipairs(probes) do
						local wx, wz = p[1], p[2]
						if wx ~= nil and wz ~= nil then
							local surf = yVal
							if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
								local ty = getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz)
								if ty ~= nil then
									surf = ty
								end
							end
							local b2, inf2, id2 = getPositionBlockedByCollision(self, wx, surf + physR, wz, nil, excludeNodeId)
							blocked, blockingInfos, blockingNodeIds = IANeighbours.mergeBlockingCollisionResults(blocked, blockingInfos, blockingNodeIds, b2, inf2, id2)
						end
					end
				end
			end
			if blocked and blockingInfos and #blockingInfos > 0 then
				statusSuffix = " [blocked: " .. table.concat(blockingInfos, ", ") .. "]"
			else
				statusSuffix = blocked and " [blocked]" or " [OK]"
			end
		end
	end
	if IANeighbours.debug == true and ignoreCollision ~= true then
		local rSphere = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_M or 2.5
		if withVehicle ~= true and withAttachment ~= true then
			rSphere = IANeighbours.PLACE_COLLISION_DEBUG_SPHERE_RADIUS_CHARACTER_ONLY_M or 0.25
		end
		if IANeighbours.collisionProbeSpheres == nil then
			IANeighbours.collisionProbeSpheres = {}
		end
		local function pushProbeSphere(sx, sz, syCenter, cr, cg, cb)
			table.insert(IANeighbours.collisionProbeSpheres, { x = sx, y = syCenter, z = sz, radius = rSphere, r = cr, g = cg, b = cb })
		end
		local sphereY = (placeRef ~= nil and placeRef.getCollisionDebugSphereCenterWorldY ~= nil)
			and placeRef:getCollisionDebugSphereCenterWorldY()
			or (yVal + rSphere)
		pushProbeSphere(x, z, sphereY, 80, 200, 255)
		if withAttachment == true then
			local probes = IANeighbours.getAttachBackProbeWorldPositions(x, yVal, z, rot, withVehicle, withAttachment, sizeType)
			for _, p in ipairs(probes) do
				local wx, wz = p[1], p[2]
				if wx ~= nil and wz ~= nil then
					local rearY = yVal + rSphere
					if placeRef ~= nil and placeRef.getCollisionDebugSphereCenterWorldYAt ~= nil then
						rearY = placeRef:getCollisionDebugSphereCenterWorldYAt(wx, wz)
					elseif g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
						local ty = getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz)
						if ty ~= nil then
							rearY = ty + rSphere
						end
					end
					pushProbeSphere(wx, wz, rearY, 220, 160, 80)
				end
			end
		end
	end
	IANeighbours:addDebugPointAtPosition(x, yVal, z, label .. statusSuffix, rot)
	if blocked and blockingNodeIds and #blockingNodeIds > 0 then
		for i, nodeId in ipairs(blockingNodeIds) do
			if nodeId ~= nil and entityExists(nodeId) then
				local bx, by, bz = getWorldTranslation(nodeId)
				if bx ~= nil and bz ~= nil then
					local nodeLabel = (blockingInfos and blockingInfos[i]) or ("id=" .. tostring(nodeId))
					self:addDebugPointAtPosition(bx, by or 0, bz, "block: " .. nodeLabel, nil)
				end
			end
		end
	end
	IAHelper_addPlaceDebugBox(IANeighbours, x, yVal, z, rot, withVehicle, withAttachment, sizeType)
end

--- Clear all debug points (unlink and delete nodes). Also deletes place corner parents.
function IANeighbours:clearAllDebugPoints()
	if IANeighbours.debugPoints ~= nil then
		for _, debugPoint in pairs(IANeighbours.debugPoints) do
			if debugPoint ~= nil then
				local node = type(debugPoint) == "table" and debugPoint.node or debugPoint
				if node ~= nil and entityExists(node) then
					unlink(node)
					delete(node)
				end
			end
		end
		IANeighbours.debugPoints = {}
	end
	IANeighbours.collisionProbeSpheres = {}
	IANeighbours.mapInitPlaceDebugBoxes = {}
	if IANeighbours.mapInitPlaceDebugParents ~= nil then
		for _, parent in ipairs(IANeighbours.mapInitPlaceDebugParents) do
			if parent ~= nil and entityExists(parent) then
				unlink(parent)
				delete(parent)
			end
		end
		IANeighbours.mapInitPlaceDebugParents = {}
	end
end

--- Get traffic system root node or "splineNodes" if mission has direct spline list. Used by getTrafficSplineShapeIds / addPlacesFromTrafficSplines.
-- @return number|string|nil - trafficRoot node id, "splineNodes", or nil
function IANeighbours:getTrafficSystemRoot()
	if g_currentMission == nil or g_currentMission.terrainRootNode == nil then
		return nil
	end
	local trafficRoot = nil
	if g_currentMission.trafficSystem ~= nil then
		if g_currentMission.trafficSystem.node ~= nil and entityExists(g_currentMission.trafficSystem.node) then
			trafficRoot = g_currentMission.trafficSystem.node
		elseif g_currentMission.trafficSystem.rootNode ~= nil and entityExists(g_currentMission.trafficSystem.rootNode) then
			trafficRoot = g_currentMission.trafficSystem.rootNode
		elseif g_currentMission.trafficSystem.rootNodeId ~= nil and entityExists(g_currentMission.trafficSystem.rootNodeId) then
			trafficRoot = g_currentMission.trafficSystem.rootNodeId
		elseif g_currentMission.trafficSystem.splineNodes ~= nil and #g_currentMission.trafficSystem.splineNodes > 0 then
			trafficRoot = "splineNodes"
		end
	end
	if trafficRoot == nil then
		trafficRoot = findNodeByUserAttribute(g_currentMission.terrainRootNode, "onCreate", "TrafficSystem.onCreate")
	end
	return trafficRoot
end

--- Collect valid traffic spline shape IDs (node IDs that respond to getSplineLength >= 0.01). Used for debug points and for adding places from splines.
-- @return table - array of shapeId (number)
function IANeighbours:getTrafficSplineShapeIds()
	local out = {}
	local trafficRoot = self:getTrafficSystemRoot()
	if trafficRoot == nil then
		return out
	end
	local splineNodes = {}
	if trafficRoot == "splineNodes" then
		for _, sn in ipairs(g_currentMission.trafficSystem.splineNodes) do
			if sn ~= nil and ((type(sn) == "number" and entityExists(sn)) or (type(sn) == "table" and sn.node and entityExists(sn.node))) then
				table.insert(splineNodes, type(sn) == "table" and sn.node or sn)
			end
		end
	else
		local n = getNumOfChildren(trafficRoot)
		for i = 0, n - 1 do
			local child = getChildAt(trafficRoot, i)
			if child ~= nil and entityExists(child) then
				table.insert(splineNodes, child)
			end
		end
	end
	for _, candidate in ipairs(splineNodes) do
		if candidate ~= nil and entityExists(candidate) then
			local shapeId = findSplineShapeInSubtree(candidate, MAX_TRAFFIC_SPLINE_SEARCH_DEPTH)
			if shapeId ~= nil then
				table.insert(out, shapeId)
			end
		end
	end
	return out
end

--- Map-init debug: mark vehicle shop spawn rectangle from `g_currentMission.storeSpawnPlaces` (same L/W and max caps as IAPlacesLoader workshop grid).
-- Start = spawn origin (s=0,t=0); end = world corner at (s=L,t=W), opposite the origin along both axes.
function IANeighbours:addStoreSpawnAreaDebugPoints()
	local m = g_currentMission
	local list = m and m.storeSpawnPlaces
	if list == nil or type(list) ~= "table" then
		return
	end
	local terrainYOffset = 0.15
	for si, spawn in ipairs(list) do
		if spawn ~= nil and type(spawn) == "table" then
			local sx = tonumber(spawn.startX)
			local sy = tonumber(spawn.startY)
			local sz = tonumber(spawn.startZ)
			local L = tonumber(spawn.width)
			local W = tonumber(spawn.length)
			if sx ~= nil and sz ~= nil and L ~= nil and W ~= nil and L > 0 and W > 0 then
				local maxL = tonumber(spawn.maxWidth)
				local maxW = tonumber(spawn.maxLength)
				if maxL ~= nil and maxL > 0 and maxL < math.huge and maxL < L then
					L = maxL
				end
				if maxW ~= nil and maxW > 0 and maxW < math.huge and maxW < W then
					W = maxW
				end
				local ux, uy, uz = normalizeVec3(spawn.dirX, spawn.dirY, spawn.dirZ)
				local vx, vy, vz = normalizeVec3(spawn.dirPerpX, spawn.dirPerpY, spawn.dirPerpZ)
				if ux ~= nil and vx ~= nil then
					local yOff = tonumber(spawn.yOffset) or 0
					local function worldYAt(wx, wz)
						local yy = (sy or 0) + yOff
						if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
							local th = getTerrainHeightAtWorldPos(g_terrainNode, wx, 0, wz)
							if th ~= nil and th == th then
								yy = th + terrainYOffset
							end
						end
						return yy
					end
					local xEnd = sx + ux * L + vx * W
					local zEnd = sz + uz * L + vz * W
					self:addDebugPointAtPosition(sx, worldYAt(sx, sz), sz, string.format("Vehicle shop area start (#%d)", si), nil)
					self:addDebugPointAtPosition(xEnd, worldYAt(xEnd, zEnd), zEnd, string.format("Vehicle shop area end (#%d)", si), nil)
				end
			end
		end
	end
end

--- Rebuild debug points from IANeighbours.places (all places with absolute coords). When both withVehicle and withAttachment are false: one center point only. sizeType may override legacy vehicle/attachment box dimensions.
function IANeighbours:rebuildMapInitDebugPoints()
	IANeighbours:clearAllDebugPoints()
	local places = self.places
	if places ~= nil then
		for _, place in ipairs(places) do
			if place and place.x ~= nil and place.z ~= nil
				and not (IAMapInitDialogGUI and IAMapInitDialogGUI.shouldExcludePlaceFromMapInitDebug and IAMapInitDialogGUI.shouldExcludePlaceFromMapInitDebug(place)) then
				local label = IAMapInitDialogGUI and IAMapInitDialogGUI.getLabelForMapInitPlaceEntry and IAMapInitDialogGUI.getLabelForMapInitPlaceEntry(place) or place.type
				local excl = (IANeighbours.debug == true) and self:getPrimaryPlaceDebugCollisionExcludeNodeId(place) or nil
				self:addPlaceDebugPointsAt(place.x, place.y or 0, place.z, place.rotation or 0, label, place.withVehicle, place.withAttachment, excl, place.ignoreCollision == true, place, place.sizeType)
			end
		end
	end
	self:addStoreSpawnAreaDebugPoints()
end

--- Remove the place nearest to the current player/vehicle position from IANeighbours.places, save, and rebuild debug points.
-- @return boolean true if a place was removed
function IANeighbours:removeNearestPlace()
	local px, py, pz = nil, nil, nil
	if g_localPlayer then
		local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
		if v and v.rootNode and entityExists(v.rootNode) then
			px, py, pz = getWorldTranslation(v.rootNode)
		else
			px, py, pz = g_localPlayer:getPosition()
		end
	end
	local places = self.places
	if px == nil or pz == nil or places == nil or #places == 0 then
		return false
	end
	local bestIdx = nil
	local bestDistSq = math.huge
	for i, place in ipairs(places) do
		if place and place.x ~= nil and place.z ~= nil then
			local dx = (place.x or 0) - px
			local dz = (place.z or 0) - pz
			local distSq = dx * dx + dz * dz
			if distSq < bestDistSq then
				bestDistSq = distSq
				bestIdx = i
			end
		end
	end
	if bestIdx == nil then
		return false
	end
	table.remove(places, bestIdx)
	if IANeighbours.xmlHelper and g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
		if IANeighbours.debug then
			print("--- saveMapConfigToFile caller: IANeighbours:removeNearestPlace mapId=" .. tostring(g_currentMission.missionInfo.mapId))
		end
		IANeighbours.xmlHelper:saveMapConfigToFile(g_currentMission.missionInfo.mapId)
	end
	if IANeighbours.mapInitPlaceMarkersVisible == true then
		IANeighbours:rebuildMapInitDebugPoints()
	end
	return true
end

--- End the map init phase: remove init vehicle (eject player and delete), clear all debug points, close dialog.
function IANeighbours:endInitPhase()
	local vehicle = g_localPlayer and g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
	if vehicle ~= nil and IAMapInitJob.isInitVehicle(vehicle) then
		if vehicle.requestToLeave then
			vehicle:requestToLeave(g_localPlayer)
		elseif g_currentMission and g_currentMission.requestToLeaveVehicle and g_localPlayer and g_localPlayer.connection then
			g_currentMission:requestToLeaveVehicle(g_localPlayer.connection, vehicle)
		end
		vehicle:delete(true)
	end
	IANeighbours:clearAllDebugPoints()
	IANeighbours.mapInitPlaceMarkersVisible = false
	if g_gui and g_gui.currentDialog and g_gui.currentDialog.target and g_gui.currentDialog.target.dialog then
		local d = g_gui.currentDialog
		if d.target and d.target.dialog == d and d.target.className and string.find(tostring(d.target.className), "IAMapInitDialogGUI") then
			g_gui:closeDialog(d)
		end
	end
end

-- Tolerance (metres) when re-locating a saved hidden object by name + world position on load.
IANeighbours.HIDDEN_OBJECT_MATCH_EPS = 0.5
-- Max distance (metres, 2D) from the player to consider a "gate" object for removal.
IANeighbours.HIDE_GATE_MAX_DISTANCE = 20

--- Collect map nodes whose (lowercased) name contains `substr`, with world position and an index-path
--- hint. Reuses the same map-node traversal used elsewhere (IAMapInitJob.getMapRootNode +
--- collectRuntimeMapNodes), so it walks g_currentMission.maps[1] like the rest of map init.
-- @param string substr - case-insensitive substring to match against node names (e.g. "gate")
-- @return table[] - array of { nodeId, name, x, y, z, index }
function IANeighbours.collectMapNodesByNameSubstring(substr)
	local out = {}
	if substr == nil or substr == "" then
		return out
	end
	local needle = string.lower(tostring(substr))
	local root = IAMapInitJob and IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
	if root == nil then
		return out
	end
	local nodes = IAMapInitJob.collectRuntimeMapNodes(root)
	for _, n in ipairs(nodes) do
		if n ~= nil and n.nodeId ~= nil and entityExists(n.nodeId) and n.name ~= nil and n.name ~= "" then
			if string.find(string.lower(n.name), needle, 1, true) then
				local x, y, z = getWorldTranslation(n.nodeId)
				if x ~= nil and z ~= nil then
					out[#out + 1] = {
						nodeId = n.nodeId,
						name = n.name,
						x = x,
						y = y or 0,
						z = z,
						index = (n.hierarchyPath ~= nil) and table.concat(n.hierarchyPath, "|") or ""
					}
				end
			end
		end
	end
	return out
end

--- Find the map object nearest to the player/vehicle whose node name contains "gate", remove it from
--- the scene entirely (delete, not just setVisibility) and persist it in the map config so it stays
--- gone after a reload.
-- @return boolean removed
-- @return string|nil removedName
function IANeighbours:hideNearestGateObject()
	local px, _, pz
	if g_localPlayer then
		local v = g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()
		if v and v.rootNode and entityExists(v.rootNode) then
			px, _, pz = getWorldTranslation(v.rootNode)
		else
			px, _, pz = g_localPlayer:getPosition()
		end
	end
	if px == nil or pz == nil then
		return false, nil
	end

	local candidates = IANeighbours.collectMapNodesByNameSubstring("gate")
	local maxDist = IANeighbours.HIDE_GATE_MAX_DISTANCE or 20
	local maxDistSq = maxDist * maxDist
	local best = nil
	local bestDistSq = math.huge
	for _, c in ipairs(candidates) do
		local dx = c.x - px
		local dz = c.z - pz
		local distSq = dx * dx + dz * dz
		if distSq < bestDistSq and distSq <= maxDistSq then
			bestDistSq = distSq
			best = c
		end
	end
	if best == nil then
		return false, nil
	end

	-- Persist before deletion: world position + index path must reflect the live scene.
	if self.hiddenMapObjects == nil then
		self.hiddenMapObjects = {}
	end
	table.insert(self.hiddenMapObjects, {
		name = best.name,
		index = best.index,
		x = best.x,
		y = best.y,
		z = best.z
	})

	-- Remove the whole node subtree (visual + collision) so the gate is gone, not just hidden.
	-- unlink + delete is the same removal pattern used elsewhere in the mod for map-linked nodes.
	if entityExists(best.nodeId) then
		pcall(function()
			unlink(best.nodeId)
			delete(best.nodeId)
		end)
	end

	if IANeighbours.xmlHelper and g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.mapId then
		if IANeighbours.debug then
			print("--- saveMapConfigToFile caller: IANeighbours:hideNearestGateObject mapId=" .. tostring(g_currentMission.missionInfo.mapId))
		end
		IANeighbours.xmlHelper:saveMapConfigToFile(g_currentMission.missionInfo.mapId)
	end
	return true, best.name
end

--- Re-locate and delete all persisted hidden map objects (called once after the map config loads).
--- Each entry is matched by node name + saved world position (within HIDDEN_OBJECT_MATCH_EPS), which is
--- robust to scene child-index shifts caused by earlier deletions. All targets are resolved first and
--- only then deleted, so multiple hidden siblings still resolve to the correct nodes.
-- @return number - count of objects removed
function IANeighbours:applyHiddenMapObjects()
	local list = self.hiddenMapObjects
	if list == nil or #list == 0 then
		return 0
	end
	local root = IAMapInitJob and IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
	if root == nil then
		return 0
	end
	local nodes = IAMapInitJob.collectRuntimeMapNodes(root)
	local eps = IANeighbours.HIDDEN_OBJECT_MATCH_EPS or 0.5
	local eps2 = eps * eps
	local used = {}
	local toDelete = {}
	for _, h in ipairs(list) do
		if h ~= nil and h.name ~= nil and h.x ~= nil and h.z ~= nil then
			local best = nil
			local bestDistSq = math.huge
			for _, n in ipairs(nodes) do
				if n ~= nil and n.nodeId ~= nil and not used[n.nodeId] and entityExists(n.nodeId) and n.name == h.name then
					local x, y, z = getWorldTranslation(n.nodeId)
					if x ~= nil and z ~= nil then
						local dx = x - h.x
						local dy = (y or 0) - (h.y or 0)
						local dz = z - h.z
						local distSq = dx * dx + dy * dy + dz * dz
						if distSq < bestDistSq then
							bestDistSq = distSq
							best = n.nodeId
						end
					end
				end
			end
			if best ~= nil and bestDistSq <= eps2 then
				used[best] = true
				toDelete[#toDelete + 1] = best
			end
		end
	end
	local removed = 0
	for _, nodeId in ipairs(toDelete) do
		if entityExists(nodeId) then
			local ok = pcall(function()
				unlink(nodeId)
				delete(nodeId)
			end)
			if ok then
				removed = removed + 1
			end
		end
	end
	return removed
end

-- Get uniqueId from externalId mapping
-- @param string externalId - External ID
-- @return string|nil - Unique ID if found, nil otherwise
function IANeighbours:getVehicleUniqueIdByExternalId(externalId)
	if externalId == nil or IANeighbours.vehicleIdMapping == nil then
		return nil
	end
	return IANeighbours.vehicleIdMapping[externalId]
end

-- Set vehicle ID mapping (externalId -> uniqueId)
-- @param string externalId - External ID
-- @param string uniqueId - Unique ID
function IANeighbours:setVehicleIdMapping(externalId, uniqueId)
	if externalId == nil or uniqueId == nil then
		return
	end
	if IANeighbours.vehicleIdMapping == nil then
		IANeighbours.vehicleIdMapping = {}
	end
	IANeighbours.vehicleIdMapping[externalId] = uniqueId
end

--- Add a single map-init entry to IANeighbours.places (via IAPlacesLoader so it is available for situation spawning).
-- @param table entry - Map-init entry with type, x, y, z, rotation, optional id, optional characterNumber, optional withVehicle, optional withAttachment
function IANeighbours:addPlaceFromMapInitEntry(entry)
	if self.placesLoader == nil or self.placesLoader.addPlaceFromMapInitEntry == nil then
		return
	end
	self.placesLoader:addPlaceFromMapInitEntry(entry)
end

--- Roadside places from traffic splines (see IAPlacesLoader:addPlacesFromTrafficSplines).
function IANeighbours:addPlacesFromTrafficSplines(options)
	if self.placesLoader == nil or self.placesLoader.addPlacesFromTrafficSplines == nil then
		return 0
	end
	return self.placesLoader:addPlacesFromTrafficSplines(options)
end

--- Add places from g_currentMission.economyManager.sellingStations unload trigger aiNodes (see IAPlacesLoader:addPlacesFromSellingStations).
function IANeighbours:addPlacesFromSellingStations(options)
	if self.placesLoader == nil or self.placesLoader.addPlacesFromSellingStations == nil then
		return 0
	end
	return self.placesLoader:addPlacesFromSellingStations(options)
end

--- Merge optional single/table exclude ids with runtime node ids from a place (each valid id and descendants ignored by overlap).
-- @param number|table|nil optionExclude - from options.excludeNodeIds
-- @param table|nil placeRuntimeList - array of engine node ids
-- @return number|table|nil - argument to isPositionBlockedByCollision
function IANeighbours:mergeCollisionExcludeNodeIds(optionExclude, placeRuntimeList)
	if placeRuntimeList == nil or #placeRuntimeList == 0 then
		return optionExclude
	end
	local merged = {}
	local seen = {}
	local function add(nid)
		if nid ~= nil and entityExists(nid) and not seen[nid] then
			seen[nid] = true
			merged[#merged + 1] = nid
		end
	end
	if type(optionExclude) == "number" then
		add(optionExclude)
	elseif type(optionExclude) == "table" then
		for _, n in ipairs(optionExclude) do
			add(n)
		end
	end
	for _, n in ipairs(placeRuntimeList) do
		add(n)
	end
	if #merged == 0 then
		return nil
	end
	if #merged == 1 then
		return merged[1]
	end
	return merged
end

--- Resolve place.collisionExcludeRefIds (or mapRefNodeId fallback) + resolvedMapNodeId to engine node ids. Caches scene walk and ref→runtime per session.
-- @param IAMapPlace place
function IANeighbours:ensurePlaceCollisionExcludeRuntimeNodes(place)
	if place == nil or place.ignoreCollision == true then
		return
	end
	local refKeys = {}
	if place.collisionExcludeRefIds ~= nil then
		for _, rid in ipairs(place.collisionExcludeRefIds) do
			if rid ~= nil and tostring(rid) ~= "" then
				refKeys[#refKeys + 1] = tostring(rid)
			end
		end
	end
	if #refKeys == 0 and place.mapRefNodeId ~= nil and tostring(place.mapRefNodeId) ~= "" then
		refKeys[1] = tostring(place.mapRefNodeId)
	end
	local out = {}
	local seen = {}
	local function add(id)
		if id ~= nil and entityExists(id) and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	add(place.resolvedMapNodeId)
	IAprintDebug("IANeighbours:ensurePlaceCollisionExcludeRuntimeNodes()","getMapReferenceData()",nil,nil,nil)
	local refData = IAMapInitJob and IAMapInitJob.getMapReferenceData and IAMapInitJob.getMapReferenceData()
	IAprintDebug("IANeighbours:ensurePlaceCollisionExcludeRuntimeNodes()","refData: " .. tostring(refData and #refData or 0),nil,nil,nil)
	if refData ~= nil and next(refData) ~= nil and #refKeys > 0 and IAMapInitJob.collectRuntimeMapNodes ~= nil then
		local mapRoot = IAMapInitJob.getMapRootNode and IAMapInitJob.getMapRootNode()
		if self._collisionRuntimeNodesList == nil or self._collisionRuntimeNodesRoot ~= mapRoot then
			self._collisionRuntimeNodesRoot = mapRoot
			self._collisionRuntimeNodesList = (mapRoot and IAMapInitJob.collectRuntimeMapNodes(mapRoot)) or {}
		end
		if self._collisionRefKeyToRuntime == nil then
			self._collisionRefKeyToRuntime = {}
		end
		local rlist = self._collisionRuntimeNodesList
		for _, key in ipairs(refKeys) do
			local nidNum = tonumber(key)
			if nidNum ~= nil then
				local rt = self._collisionRefKeyToRuntime[key]
				if rt ~= nil and entityExists(rt) then
					add(rt)
				else
					local ref = refData[nidNum]
					if ref ~= nil and IAMapInitJob.buildXmlEntryFromMapRef ~= nil then
						local xmlEntry = IAMapInitJob.buildXmlEntryFromMapRef(nidNum, ref)
						if xmlEntry ~= nil and IAMapInitJob.findRuntimeNodeForXmlEntry ~= nil then
							rt = IAMapInitJob.findRuntimeNodeForXmlEntry(xmlEntry, rlist, {})
							if rt ~= nil and entityExists(rt) then
								self._collisionRefKeyToRuntime[key] = rt
								add(rt)
							end
						end
					end
				end
			end
		end
	end
	place.collisionExcludeRuntimeNodeIds = out
end

--- First runtime exclude node for debug overlap display (single id API).
function IANeighbours:getPrimaryPlaceDebugCollisionExcludeNodeId(place)
	if place == nil then
		return nil
	end
	self:ensurePlaceCollisionExcludeRuntimeNodes(place)
	if place.collisionExcludeRuntimeNodeIds ~= nil and #place.collisionExcludeRuntimeNodeIds > 0 then
		return place.collisionExcludeRuntimeNodeIds[1]
	end
	return place.resolvedMapNodeId
end

--- Reserved public_place slot (on-foot parking) and/or another neighbour's active situation at this logical place. No physics query.
-- @param table options optional - same as isPlaceBlocked (forPublicPlaceParkingSelection)
-- @return boolean
function IANeighbours:isPlaceBlockedByOccupancy(place, options)
	if place == nil then
		if IANeighbours.debug then
			print("--- IANeighbours:isPlaceBlockedByOccupancy() - Place is nil")
		end
		return false
	end
	if IANeighbours.neighbours == nil then
		return false
	end

	local publicPlaceParkingSelect = options ~= nil and options.forPublicPlaceParkingSelection == true
	local sem = (place.getSemanticType ~= nil and place:getSemanticType()) or place.type
	local ptype = string.lower(tostring(sem or ""))
	local allowsVehicle = (place.withVehicle ~= false)
	local isPublicPlaceParkingCandidate = (ptype == "public_place") and allowsVehicle
	if publicPlaceParkingSelect and isPublicPlaceParkingCandidate and self:isRoadsideParkingSlotReserved(place) then
		return true
	end

	if place.id ~= nil and IAEquipmentPresence ~= nil and IAEquipmentPresence.State.isPlaceBlockedByFleetPresenceState ~= nil then
		local excludeUid = options ~= nil and options.excludePresenceUniqueId or nil
		if IAEquipmentPresence.State.isPlaceBlockedByFleetPresenceState(place.id, excludeUid) then
			if IANeighbours.debug then
				print("--- IANeighbours:isPlaceBlockedByOccupancy() - Place blocked by fleet presenceState placeId=" .. tostring(place.id))
			end
			return true
		end
	end

	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.activeSituation ~= nil then
			local situation = neighbour.activeSituation
			if situation.place ~= nil and placesMatchForSituationBlocking(place, situation.place) then
				if IANeighbours.debug then
					print("--- IANeighbours:isPlaceBlockedByOccupancy() - Place is blocked by neighbour: "..tostring(neighbour.name))
				end
				return true
			end
		end
	end

	return false
end

--- Physics overlap at place position (collision excludes applied). Does not check active situations or parking reservation.
-- Delegates to IAMapPlace:isBlockedByCollision(options).
-- @param table options optional - excludeNodeIds, forPublicPlaceParkingSelection (wider radius for public_place), collisionRadiusM
-- @return boolean
function IANeighbours:isPlaceBlockedByCollision(place, options)
	if place == nil or place.ignoreCollision == true or place.x == nil or place.z == nil then
		return false
	end
	if place.isBlockedByCollision == nil then
		return false
	end
	return select(1, place:isBlockedByCollision(options))
end

-- Check if a specific place is blocked (has a situation from any neighbour, reserved parking slot, or physics at the position).
-- Physics branch: IAMapPlace:isBlockedByCollision(options).
-- Used for situation selection and homebase vehicle placement so occupied positions are respected.
-- @param IAMapPlace place - The place to check
-- @param table options optional - { excludeNodeIds = { nodeId, ... } } nodes to exclude from collision check (e.g. neighbour's vehicles when placing at homebase);
--   excludePresenceUniqueId = string — skip this vehicle when checking presenceState.parkingPlaceId occupancy;
--   forPublicPlaceParkingSelection = true — for type public_place with withVehicle ~= false: treat reserved slots (roadsideParkingReservedKeys) as blocked and use ROADSIDE_PARKING_OCCUPANCY_RADIUS_M for collision instead of PLACE_COLLISION_CHECK_RADIUS.
-- @return boolean - true if the place is blocked, false if available
function IANeighbours:isPlaceBlocked(place, options)
	if place == nil then
		if IANeighbours.debug then
			print("--- IANeighbours:isPlaceBlocked() - Place is nil")
		end
		return false
	end

	if IANeighbours.neighbours == nil then
		return false
	end

	return self:isPlaceBlockedByOccupancy(place, options) or self:isPlaceBlockedByCollision(place, options)
end

--- Stable key for exclusive use of a public_place slot when parking on-foot vehicles (see IAGameLoopHelper).
function IANeighbours:roadsideParkingReservationKeyForPlace(place)
	if place == nil then
		return nil
	end
	if place.id ~= nil then
		return "id:" .. tostring(place.id)
	end
	if place.x ~= nil and place.z ~= nil then
		-- 0.5 m grid groups duplicate spline samples at the same world spot
		local gx = math.floor((place.x or 0) * 2 + 0.5)
		local gz = math.floor((place.z or 0) * 2 + 0.5)
		return "xz:" .. tostring(gx) .. ":" .. tostring(gz)
	end
	return nil
end

function IANeighbours:isRoadsideParkingSlotReserved(place)
	local k = self:roadsideParkingReservationKeyForPlace(place)
	return k ~= nil and self.roadsideParkingReservedKeys[k] == true
end

function IANeighbours:reserveRoadsideParkingSlot(place)
	local k = self:roadsideParkingReservationKeyForPlace(place)
	if k ~= nil then
		self.roadsideParkingReservedKeys[k] = true
	end
end

-- Get all active situations from all neighbours
-- @return table - Array of all active IASituation objects
function IANeighbours:getAllActiveSituations()
	local activeSituations = {}
	
	if IANeighbours.neighbours == nil then
		return activeSituations
	end
	
	for _, neighbour in pairs(IANeighbours.neighbours) do
		if neighbour ~= nil and neighbour.activeSituation ~= nil then
			table.insert(activeSituations, neighbour.activeSituation)
		end
	end
	
	if IANeighbours.debug then
		--print("--- IANeighbours:getAllActiveSituations() - Found "..tostring(#activeSituations).." active situations")
	end
	
	return activeSituations
end

-- Reset farmlands to default when there is no active situation on the farmland
-- Rules:
-- - If isOwned=true and farmId is 1, do nothing (player's farmland)
-- - If isOwned=true and farmId is 99, reset it to farmId 0
function IANeighbours:resetFarmlandsToDefault()
	if IANeighbours.debug then
		--print("--- IANeighbours:resetFarmlandsToDefault() - Starting farmland reset check")
	end
	
	-- Get all active situations
	local activeSituations = self:getAllActiveSituations()
	
	-- Create a set of farmland IDs that have active situations
	local farmlandsWithActiveSituations = {}
	for _, situation in ipairs(activeSituations) do
		if situation ~= nil and situation.farmlandId ~= nil then
			farmlandsWithActiveSituations[situation.farmlandId] = true
		end
	end
	
	-- Get all farmlands
	local farmlands = g_farmlandManager:getFarmlands()
	local resetCount = 0
	
	for _, farmland in pairs(farmlands) do
		if farmland ~= nil then
			-- Check if this farmland has an active situation
			local hasActiveSituation = farmlandsWithActiveSituations[farmland.id] == true
			
			-- Only process if there's no active situation on this farmland
			if not hasActiveSituation then
				-- If isOwned=true and farmId is 1, do nothing (player's farmland)
				if farmland.isOwned == true and farmland.farmId == 1 then
					-- Do nothing, this is the player's farmland
					if IANeighbours.debug then
						--print("--- IANeighbours:resetFarmlandsToDefault() - Skipping player farmland: "..tostring(farmland.id))
					end
				-- If isOwned=true and farmId is 99, reset it to farmId 0
				elseif farmland.isOwned == true and (farmland.farmId == 99 or farmland.farmId == 2) then
					if IANeighbours.debug then
						print("--- IANeighbours:resetFarmlandsToDefault() - Resetting farmland "..tostring(farmland.id).." from farmId 99 to 0")
					end
					
					-- Reset farmland to default (farmId 0)
					g_farmlandManager:setLandOwnership(farmland.id, 0)
					farmland:setOwnerFarmId(0)
					-- NPC index is managed by IANeighbours:updateFarmlands() on the 5-second cycle.
					farmland.showOnFarmlandsScreen = true
					if farmland.field ~= nil and farmland.field.fieldState ~= nil then
						farmland.field.fieldState.ownerFarmId = 0
					end
					
					resetCount = resetCount + 1
				end
			end
		end
	end
	
	if IANeighbours.debug then
		--print("--- IANeighbours:resetFarmlandsToDefault() - Reset "..tostring(resetCount).." farmlands to default")
	end
	
	return resetCount
end



-- Insert a custom tab into the in-game menu paging bar (page name must match the GUI root name).
function IANeighbours.fixInGameMenu(frame,pageName,uvs,position,predicateFunc)
	local inGameMenu = g_gui.screenControllers[InGameMenu]
	local abovePrices = 0;

	if IANeighbours.debug then
		print("--- IANeighbours.fixInGameMenu")
		DebugUtil.printTableRecursively(inGameMenu.pagingElement)
	end

	-- remove all to avoid warnings
	for k, v in pairs({pageName}) do
		inGameMenu.controlIDs[v] = nil
	end

	for i = 1, #inGameMenu.pagingElement.elements do
		local child = inGameMenu.pagingElement.elements[i]
		if child == inGameMenu["pageStatistics"] then
			abovePrices = i;
			if IANeighbours.debug then
				print("--- found Statistics position - "..tostring(abovePrices))
			end
		end
	end

	if abovePrices == 0 then
		abovePrices = position
	end
	
	inGameMenu[pageName] = frame
	inGameMenu.pagingElement:addElement(inGameMenu[pageName])

	inGameMenu:exposeControlsAsFields(pageName)

	for i = 1, #inGameMenu.pagingElement.elements do
		local child = inGameMenu.pagingElement.elements[i]
		if child == inGameMenu[pageName] then
			table.remove(inGameMenu.pagingElement.elements, i)
			table.insert(inGameMenu.pagingElement.elements, abovePrices, child)
			break
		end
	end

	for i = 1, #inGameMenu.pagingElement.pages do
		local child = inGameMenu.pagingElement.pages[i]
		if child.element == inGameMenu[pageName] then
			table.remove(inGameMenu.pagingElement.pages, i)
			table.insert(inGameMenu.pagingElement.pages, abovePrices, child)
			break
		end
	end

	inGameMenu.pagingElement:updateAbsolutePosition()
	inGameMenu.pagingElement:updatePageMapping()
	
	inGameMenu:registerPage(inGameMenu[pageName], position, predicateFunc)
	local iconFileName = Utils.getFilename('images/menuIcon.dds', IANeighbours.dir)
	inGameMenu:addPageTab(inGameMenu[pageName],iconFileName, GuiUtils.getUVs(uvs))
--	inGameMenu[pageName]:applyScreenAlignment()
--	inGameMenu[pageName]:updateAbsolutePosition()

	for i = 1, #inGameMenu.pageFrames do
		local child = inGameMenu.pageFrames[i]
		if child == inGameMenu[pageName] then
			table.remove(inGameMenu.pageFrames, i)
			table.insert(inGameMenu.pageFrames, abovePrices, child)
			break
		end
	end

	inGameMenu:rebuildTabList()

end




-- Per-frame / per-cycle profiling: wrap the heaviest recurring "main" functions so each call is
-- wall-clock timed and printed (with its function name) when it exceeds IANeighbours.frameTimeLogThresholdMs.
-- IANeighbours:update is already instrumented inline, so it is intentionally not wrapped here.
if IANeighbours.debugPerformance and IAHelper_profileWrap ~= nil and not IANeighbours._mainFunctionsProfiled then
	IANeighbours._mainFunctionsProfiled = true

	-- IANeighbours per-frame hot paths
	IANeighbours.updateNeighbours = IAHelper_profileWrap("IANeighbours:updateNeighbours", IANeighbours.updateNeighbours)
	IANeighbours.updateFarmlands  = IAHelper_profileWrap("IANeighbours:updateFarmlands", IANeighbours.updateFarmlands)

	-- Per-entity update functions (run every frame, once per neighbour / situation / conversation / mission)
	if IANeighbour ~= nil then
		IANeighbour.update = IAHelper_profileWrap("IANeighbour:update", IANeighbour.update)
	end
	if IASituation ~= nil then
		IASituation.update = IAHelper_profileWrap("IASituation:update", IASituation.update)
	end
	if IAConversation ~= nil then
		IAConversation.update = IAHelper_profileWrap("IAConversation:update", IAConversation.update)
	end
	if IAFieldOutcomeMission ~= nil then
		IAFieldOutcomeMission.update = IAHelper_profileWrap("IAFieldOutcomeMission:update", IAFieldOutcomeMission.update)
	end

	-- IAGameLoopHelper: the most complex on-demand orchestrators (situation/fieldwork generation & scheduling)
	if IAGameLoopHelper ~= nil then
		IAGameLoopHelper.selectNewSituation             = IAHelper_profileWrap("IAGameLoopHelper:selectNewSituation", IAGameLoopHelper.selectNewSituation)
		IAGameLoopHelper.generateNewSituation           = IAHelper_profileWrap("IAGameLoopHelper:generateNewSituation", IAGameLoopHelper.generateNewSituation)
		IAGameLoopHelper.selectRandomPlaceForSituation  = IAHelper_profileWrap("IAGameLoopHelper:selectRandomPlaceForSituation", IAGameLoopHelper.selectRandomPlaceForSituation)
		IAGameLoopHelper.rebuildDailyFieldworkSchedule  = IAHelper_profileWrap("IAGameLoopHelper:rebuildDailyFieldworkSchedule", IAGameLoopHelper.rebuildDailyFieldworkSchedule)
		IAGameLoopHelper.collectOpenFieldworkCandidates = IAHelper_profileWrap("IAGameLoopHelper:collectOpenFieldworkCandidates", IAGameLoopHelper.collectOpenFieldworkCandidates)
		IAGameLoopHelper.validateScheduleEntry          = IAHelper_profileWrap("IAGameLoopHelper:validateScheduleEntry", IAGameLoopHelper.validateScheduleEntry)
	end
end

addModEventListener(IANeighbours)
