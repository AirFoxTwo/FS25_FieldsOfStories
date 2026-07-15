--
-- IAConversation: loads conversation data from a directory (XML + sound files),
-- builds tree by id/previousId, plays voice via createAndPlayVoiceSample (2D or 3D from NPC), cleans up via deleteVoiceSample.
-- The dialog is the subtitle display: it must stay visible for the entire conversation so the player can read each line.
-- Uses the mod's IAConversationDialog (gui/IAConversationDialog.xml) to avoid conflict with the game's ConversationDialog.
--
IAConversation = {}
IAConversation._mt = Class(IAConversation)

IAConversation.CONVERSATION_DIALOG_NAME = "IAConversationDialog"
--- Pause (ms) after a voice line finishes before the next clip starts (sequential lines in the same conversation).
IAConversation.VOICE_LINE_GAP_MILLISECONDS = 500
--- When audio fails to start (missing file, load error, no modSettings), wait this long before the next queue item / advance (player can still skip via click).
IAConversation.VOICE_MISSING_HOLD_MILLISECONDS = 15000
IAConversation.DEBUG_UI_SOUND = IANeighbours.debug
--- Log ESC/dialog close path: `IAConversationDialog:onClose` and `onExternalDialogClose` (set true to trace).
IAConversation.DEBUG_DIALOG_ON_CLOSE = false
--- Looping ambient noise played for a standalone phone call: starts when the call is answered and stops when it ends (hang_up.ogg). One file is picked at random per call.
IAConversation.PHONE_BACKGROUND_SOUNDS = { "sound/phone_background_1.ogg", "sound/phone_background_2.ogg" }
--- Volume for the looping phone background noise. Kept low so NPC voice lines stay clearly audible over it.
IAConversation.PHONE_BACKGROUND_VOLUME = 1
--- Shipped conversation.xml trees live here under the mod directory (`g_currentModDirectory`). Not the dev-only `conversation_generation/` source folder.
IAConversation.MOD_CONVERSATIONS_ROOT = "conversations"
--- Per-character shared folder for dynamic voice variable clips (field numbers, hectares, job types).
-- Lives at `conversations/dynamic/<characterId>/<DYNAMIC_SHARED_FOLDER>/` so the same clips can be reused
-- across all dynamic topics for that character without duplicating files per topic folder.
IAConversation.DYNAMIC_SHARED_FOLDER = "shared"
--- Global folder for player-speaker dynamic variable clips: the player voice is the same across all
-- characters (male / voiceId 0), so we store these clips exactly once instead of duplicating them
-- per character. Lives at `conversations/dynamic/<DYNAMIC_PLAYER_FOLDER>/<DYNAMIC_SHARED_FOLDER>/`
-- (e.g. `conversations/dynamic/player/shared/`). The generator helper writes here too; see
-- helper/generate_dynamic_conversation_voices.ps1.
IAConversation.DYNAMIC_PLAYER_FOLDER = "player"
--- [character#index][situationId] = { variantFolderId, ... } — filled by IAXMLHelper:loadConversationsStructureRegistry (character uses XML `index`, not `id`).
IAConversation.situationVariantIds = {}
--- conversation folder name (neighbour.id) → character `index` from conversations-structure.xml (for path lookup).
IAConversation.structureCharacterIndexByFolderId = {}

function IAConversation.new()
	local self = setmetatable({}, IAConversation._mt)
	self.currentSample = nil
	self.uiSample = nil
	self.phoneBackgroundSample = nil  -- looping ambient noise during a standalone phone call
	self.hasGrantedConversationScore = false
	self.entriesById = {}
	self.entriesByPreviousId = {}
	self.conversationDir = nil  -- mod-relative path, e.g. MOD_CONVERSATIONS_ROOT .. "/27"
	self.playbackQueue = {}     -- ordered list of mod-relative paths to play (sample by sample)
	self.currentId = nil       -- id of current node (single-NPC flow); nil at choice points
	self.nextOptions = nil     -- list of entries when at choice point (player must select)
	self.isChoicePoint = false -- true when nextOptions is set and option view should be shown
	self.pendingAutoAdvance = false -- set when 1:1 playback just finished so situation can advance once
	self.advanceDelay = 0           -- countdown after a line ends; at least VOICE_LINE_GAP_MILLISECONDS before the next voice
	self.dialogController = nil -- set when conversation is active (addMessage)
	self.npcName = "Neighbour" -- sender name for NPC lines
	self.dialog = nil         -- the dialog window (for closing)
	self.situation = nil     -- reference for cleanup (situation.activeDialog/dialogController)
	self.mainMenuOptions = nil  -- pre-loaded at init: { id, text, conversationDir } for smalltalks + Goodbye
	self._mainMenuOptions = nil -- snapshot when main menu is shown (for selectOption lookup)
	--- Optional function(entry) -> boolean; false hides player choice lines at choice points.
	self.entryAvailabilityFilter = nil
	-- Optional runtime callbacks: keyed by string entry id (from dynamic / runtime-built trees)
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	self._activePlaybackQueueItem = nil
	--- "plus" | "minus" | nil — relationship attribute of the last NPC line shown (goodbye outcome).
	self._lastNpcRelationship = nil
	--- True when started from contract phone (no IASituation); IANeighbours clears active ref on close/stop.
	self.isStandalonePhoneCall = false
	--- True once any phone-style line plays (standalone call or "phone" voice effect); used to play the hang-up sound when the call is force-closed (ESC).
	self.isPhoneCallConversation = false
	return self
end

--- Play a short 2D UI sound from the mod folder (best-effort).
function IAConversation:playUiSound(relativePath, volume)
	if IANeighbours == nil or IANeighbours.dir == nil or relativePath == nil or relativePath == "" then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playUiSound() - abort (missing baseDir/relativePath): baseDir=" .. tostring(IANeighbours and IANeighbours.dir) .. " path=" .. tostring(relativePath))
		end
		return
	end
	local fileName = Utils.getFilename(relativePath, IANeighbours.dir)
	if fileName == nil or fileName == "" or not fileExists(fileName) then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playUiSound() - file missing: " .. tostring(fileName) .. " (rel=" .. tostring(relativePath) .. ")")
		end
		return
	end
	if self.uiSample ~= nil then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playUiSound() - deleting previous uiSample=" .. tostring(self.uiSample))
		end
		delete(self.uiSample)
		self.uiSample = nil
	end
	local sample = createSample("IAConversation_ui")
	if sample == nil or sample == 0 then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playUiSound() - createSample failed")
		end
		return
	end
	if not loadSample(sample, fileName, false) then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playUiSound() - loadSample failed: sample=" .. tostring(sample) .. " file=" .. tostring(fileName))
		end
		delete(sample)
		return
	end
	playSample(sample, 1, volume or 1, 0, 0, 0)
	self.uiSample = sample
	if IAConversation.DEBUG_UI_SOUND then
		print("--- IAConversation:playUiSound() - playing: sample=" .. tostring(sample) .. " file=" .. tostring(fileName) .. " vol=" .. tostring(volume or 1))
	end
end

--- Start the looping background noise for a standalone phone call (one random file from PHONE_BACKGROUND_SOUNDS).
--- No-op if already playing or if no valid file is found. Stopped by stopPhoneBackgroundSound() when the call ends.
function IAConversation:playPhoneBackgroundSound()
	if self.phoneBackgroundSample ~= nil then
		return
	end
	if IANeighbours == nil or IANeighbours.dir == nil then
		return
	end
	local choices = IAConversation.PHONE_BACKGROUND_SOUNDS
	if choices == nil or #choices == 0 then
		return
	end
	local relativePath = choices[math.random(1, #choices)]
	local fileName = Utils.getFilename(relativePath, IANeighbours.dir)
	if fileName == nil or fileName == "" or not fileExists(fileName) then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:playPhoneBackgroundSound() - file missing: " .. tostring(fileName) .. " (rel=" .. tostring(relativePath) .. ")")
		end
		return
	end
	local sample = createSample("IAConversation_phone_background")
	if sample == nil or sample == 0 then
		return
	end
	if not loadSample(sample, fileName, false) then
		delete(sample)
		return
	end
	-- 0 loops = repeat the clip until stopPhoneBackgroundSound() deletes it.
	playSample(sample, 0, IAConversation.PHONE_BACKGROUND_VOLUME, 0, 0, 0)
	self.phoneBackgroundSample = sample
	if IAConversation.DEBUG_UI_SOUND then
		print("--- IAConversation:playPhoneBackgroundSound() - playing: sample=" .. tostring(sample) .. " file=" .. tostring(fileName))
	end
end

--- Stop and release the looping phone-call background noise (best-effort, safe to call when not playing).
function IAConversation:stopPhoneBackgroundSound()
	if self.phoneBackgroundSample ~= nil then
		delete(self.phoneBackgroundSample)
		self.phoneBackgroundSample = nil
	end
end

--- Get opening NPC line from a conversation directory (first root NPC: previousId=0, duplicate root NPCs skipped). Used at init to build main menu labels.
-- @param conversationDir string Mod-relative path, e.g. "conversations/smalltalk/job/farmer/1"
-- @return table|nil { id, text, filename } or nil if not found
function IAConversation.getFirstEntryFromDirectory(conversationDir)
	if IANeighbours.dir == nil or conversationDir == nil or conversationDir == "" then
		return nil
	end
	local xmlPath = Utils.getFilename(conversationDir .. "/conversation.xml", IANeighbours.dir)
	if not fileExists(xmlPath) then
		return nil
	end
	local xmlFile = loadXMLFile("IAConversationFirstEntry", xmlPath)
	if xmlFile == nil then
		return nil
	end
	local rootKey = "conversation"
	local entryIndex = 0
	local firstRootNpcIdStr = nil
	while true do
		local entryKey = rootKey .. ".entry(" .. entryIndex .. ")"
		local id = getXMLString(xmlFile, entryKey .. "#id", nil)
		if id == nil then
			break
		end
		local previousId = getXMLString(xmlFile, entryKey .. "#previousId", "0")
		local speaker = getXMLString(xmlFile, entryKey .. "#speaker", "npc")
		local prevIdNum = tonumber(previousId)
		if prevIdNum == nil then
			prevIdNum = 0
		end
		if prevIdNum == 0 then
			local role = IAConversation._speakerRole(speaker)
			if role == "npc" then
				if firstRootNpcIdStr == nil then
					firstRootNpcIdStr = id
					local text = IAConversation._resolveEntryText(xmlFile, entryKey, nil)
					local filename = getXMLString(xmlFile, entryKey .. "#filename", nil)
					delete(xmlFile)
					return { id = id, text = text or "", filename = filename }
				end
			end
		end
		entryIndex = entryIndex + 1
	end
	delete(xmlFile)
	return nil
end

--- Build main menu options (smalltalks by role/job + Goodbye) for a given roleKey and jobKey.
-- Used for both regular situations (from config) and standalone phone calls (from neighbour).
-- @param roleKey string|nil the role key; defaults to "default" if nil or empty
-- @param jobKey string|nil the job key; defaults to "default" if nil or empty
-- @return table { { id, text, conversationDir }, ... } with all role smalltalks, job smalltalks, and goodbye
function IAConversation.buildMainMenuOptionsFromRoleAndJob(roleKey, jobKey)
	roleKey = (roleKey ~= nil and roleKey ~= "") and string.lower(tostring(roleKey)) or "default"
	jobKey = (jobKey ~= nil and jobKey ~= "") and string.lower(tostring(jobKey)) or "default"
	local options = {}
	local maxSmalltalks = 20
	for n = 1, maxSmalltalks do
		local dir = IAConversation.MOD_CONVERSATIONS_ROOT .. "/smalltalk/role/" .. roleKey .. "/" .. tostring(n)
		local first = IAConversation.getFirstEntryFromDirectory(dir)
		if first then
			table.insert(options, {
				id = "smalltalk:role/" .. roleKey .. "/" .. tostring(n),
				text = first.text or "",
				conversationDir = dir
			})
		end
	end
	for n = 1, maxSmalltalks do
		local dir = IAConversation.MOD_CONVERSATIONS_ROOT .. "/smalltalk/job/" .. jobKey .. "/" .. tostring(n)
		local first = IAConversation.getFirstEntryFromDirectory(dir)
		if first then
			table.insert(options, {
				id = "smalltalk:job/" .. jobKey .. "/" .. tostring(n),
				text = first.text or "",
				conversationDir = dir
			})
		end
	end
	table.insert(options, { id = "goodbye", text = "Goodbye", conversationDir = nil })
	return options
end

--- Map languageIndex (from g_currentMission.userManager.masterUsers[1].languageIndex) to "de" or "en".
-- FS25 typical mapping: 0 = English, 1 = German, 2 = French, etc.
-- @param languageIndex number
-- @return string "de" or "en"
function IAConversation._languageIndexToCode(languageIndex)
	if languageIndex == nil then
		return "en"
	end
	local idx = tonumber(languageIndex)
	if idx == nil then
		return "en"
	end
	-- 1 = German in FS language list, 0 = English
	if idx == 1 then
		return "de"
	end
	return "en"
end

--- Normalize voice_pack_version.xml#language to "de" or "en"; nil if attribute missing/empty (then game language is used).
-- @param raw string|nil
-- @return string|nil
function IAConversation._normalizeVoicePackLanguage(raw)
	if raw == nil or raw == "" then
		return nil
	end
	local l = string.lower(tostring(raw))
	l = string.match(l, "^%s*(.-)%s*$") or l
	if l == "" then
		return nil
	end
	if string.sub(l, 1, 2) == "de" then
		return "de"
	end
	return "en"
end

--- Get current voice language for file pattern: "de" or "en". Voice pack XML overrides game when loaded.
--- Delegates to `getDisplayLanguageCode` (in IAHelper.lua) so audio paths follow the same
--- game UI language as text and `g_i18n:getText()`-driven variable substitution.
-- @return string
function IAConversation._getVoicePackLanguage()
	if IANeighbours ~= nil and IANeighbours.voicePackLanguage ~= nil and IANeighbours.voicePackLanguage ~= "" and IANeighbours.voicePackLoaded == true then
		return IANeighbours.voicePackLanguage
	end
	return getDisplayLanguageCode()
end

--- Get voice gender for speaker for file pattern: "male" or "female". NPC uses neighbour gender; player is forced to "male" for now.
-- @param string speaker "npc" or "player"
-- @param IANeighbour|nil neighbour neighbour for NPC gender (ignored for player)
-- @return string
function IAConversation._getVoiceGender(speaker, neighbour)
	speaker = speaker and string.lower(tostring(speaker)) or "npc"
	if speaker == "player" then
		-- Player gender detection disabled for now: always use "male" until female player voice files exist.
		-- Re-enable by inspecting g_localPlayer.graphicsComponent.baseStyle.xmlFilename
		-- (contains "playerm" → male, "playerf" → female).
		return "male"
	end
	if neighbour ~= nil and neighbour.gender ~= nil then
		return string.lower(tostring(neighbour.gender))
	end
	return "male"
end

--- Build mod-relative voice file path from conversation dir: {language}_{gender}_{voiceId}_{entryId}.ogg.
-- Player lines use voice id 0. NPC lines use neighbour:getVoiceId().
-- @param self table
-- @param entry table { id, speaker, ... } — entry.id is the conversation XML entry id (last segment of filename).
-- @return string|nil mod-relative path or nil if conversationDir missing
function IAConversation:_getVoicePath(entry)
	if self.conversationDir == nil or entry == nil or entry.id == nil then
		return nil
	end
	local speaker = entry.speaker and string.lower(tostring(entry.speaker)) or "npc"
	local lang = IAConversation._getVoicePackLanguage()
	local neighbour = self.situation ~= nil and self.situation.neighbour or nil
	local gender = IAConversation._getVoiceGender(speaker, neighbour)
	local voiceId = 1
	if speaker == "player" then
		voiceId = 0
	elseif neighbour ~= nil and neighbour.getVoiceId ~= nil then
		voiceId = neighbour:getVoiceId()
	end
	local filename = string.format("%s_%s_%d_%s.ogg", lang, gender, voiceId, tostring(entry.id))
	return self.conversationDir .. "/" .. filename
end

--- Resolve text_de / text_en / text for on-screen UI; always follows the active `g_i18n` game language.
--- Dynamic conversations substitute their {placeholders} per language via
--- `applyVariablePlaceholdersToString` (sourcing text from data/IANeighbourDynamicConversationVoices.xml,
--- not from l10n).
--- Voice pack language affects audio filenames only (`_getVoicePackLanguage`), not which text_de vs text_en is shown.
-- @return string
function IAConversation.resolveLocalizedModText(textDe, textEn, textFallback)
	textDe = textDe ~= nil and tostring(textDe) or ""
	textEn = textEn ~= nil and tostring(textEn) or ""
	textFallback = textFallback ~= nil and tostring(textFallback) or ""
	IAprintDebug("resolveLocalizedModText", "textDe: "..textDe, nil, nil, nil)
	IAprintDebug("resolveLocalizedModText", "textEn: "..textEn, nil, nil, nil)
	IAprintDebug("resolveLocalizedModText", "textFallback: "..textFallback, nil, nil, nil)
	IAprintDebug("resolveLocalizedModText", "getDisplayLanguageCode: "..getDisplayLanguageCode(), nil, nil, nil)
	local result
	if getDisplayLanguageCode() == "de" then
		result = (textDe ~= "") and textDe or textFallback
	else
		result = (textEn ~= "") and textEn or textFallback
	end
	return IAConversation._sanitizeDisplayText(result)
end

--- Decode the Unicode codepoint from the first byte of a UTF-8 sequence in s.
-- Returns codepoint (decimal number), byteLength. Returns nil, 1 on invalid lead byte.
local function _iaUtf8CodepointAt(s, start)
	local b = string.byte(s, start)
	if b == nil then return nil, 0 end
	if b < 0x80 then return b, 1 end
	if b < 0xC0 then return nil, 1 end
	if b < 0xE0 then
		local b2 = string.byte(s, start + 1)
		if b2 == nil then return nil, 1 end
		return ((b - 0xC0) * 64) + (b2 - 0x80), 2
	end
	if b < 0xF0 then
		local b2 = string.byte(s, start + 1)
		local b3 = string.byte(s, start + 2)
		if b2 == nil or b3 == nil then return nil, 1 end
		return ((b - 0xE0) * 4096) + ((b2 - 0x80) * 64) + (b3 - 0x80), 3
	end
	if b < 0xF8 then
		local b2 = string.byte(s, start + 1)
		local b3 = string.byte(s, start + 2)
		local b4 = string.byte(s, start + 3)
		if b2 == nil or b3 == nil or b4 == nil then return nil, 1 end
		return ((b - 0xF0) * 262144) + ((b2 - 0x80) * 4096) + ((b3 - 0x80) * 64) + (b4 - 0x80), 4
	end
	return nil, 1
end

--- Table of { utf8Bytes, asciiReplacement, label } — ordered so longer patterns match first.
local IA_CONVERSATION_SANITIZE_RULES = {
	{ "\226\128\152", "'",  "U+2018 LEFT SINGLE QUOTATION MARK" },
	{ "\226\128\153", "'",  "U+2019 RIGHT SINGLE QUOTATION MARK" },
	{ "\226\128\156", "\"", "U+201C LEFT DOUBLE QUOTATION MARK" },
	{ "\226\128\157", "\"", "U+201D RIGHT DOUBLE QUOTATION MARK" },
	{ "\226\128\148", "--", "U+2014 EM DASH" },
	{ "\226\128\147", "-",  "U+2013 EN DASH" },
	{ "\226\128\166", "...","U+2026 HORIZONTAL ELLIPSIS" },
	{ "\226\128\145", "-",  "U+2011 NON-BREAKING HYPHEN" },
}

--- Replace Unicode typographic characters with ASCII equivalents for font compatibility.
-- The game's bitmap texture fonts only support a limited character set (ASCII + Latin-1).
-- Smart quotes, em dashes, ellipses, and other typographic characters from AI-generated
-- conversation text cause "Character 'XXXX' not found in texture font" warnings and
-- display as missing glyphs. This normalizes them to safe ASCII at the last step before
-- the engine renders the text.
-- When IANeighbours.debug is true, each substitution is logged with the codepoint,
-- hex representation, replacement, and surrounding text context.
-- @param text string
-- @return string
function IAConversation._sanitizeDisplayText(text)
	if text == nil or text == "" then
		return text or ""
	end

	-- Debug pass: scan for non-ASCII characters and report what will be replaced
	if IANeighbours ~= nil and IANeighbours.debug then
		local i = 1
		local len = #text
		while i <= len do
			local cp, clen = _iaUtf8CodepointAt(text, i)
			if cp == nil then
				i = i + 1
			elseif cp < 128 then
				i = i + 1
			else
				-- Look up whether this is a known typographic character
				local matchedLabel = nil
				local matchedReplacement = nil
				for _, rule in ipairs(IA_CONVERSATION_SANITIZE_RULES) do
					if string.sub(text, i, i + #rule[1] - 1) == rule[1] then
						matchedLabel = rule[3]
						matchedReplacement = rule[2]
						clen = #rule[1]
						break
					end
				end
				if matchedLabel ~= nil then
					local hex = string.format("U+%04X", cp)
					local ctxStart = math.max(1, i - 12)
					local ctxEnd = math.min(len, i + clen + 12)
					local context = string.sub(text, ctxStart, ctxEnd)
					print("--- IAConversation._sanitizeDisplayText: replacing codepoint " .. tostring(cp) .. " (" .. hex .. " / " .. matchedLabel .. ") → '" .. matchedReplacement .. "'  near: \"" .. context .. "\"")
				end
				i = i + math.max(clen, 1)
			end
		end
	end

	-- Apply all replacements
	for _, rule in ipairs(IA_CONVERSATION_SANITIZE_RULES) do
		text = string.gsub(text, rule[1], rule[2])
	end

	-- Catch-all: strip any remaining multi-byte UTF-8 sequences beyond Latin-1 (U+0080–U+00FF).
	-- These are 3+ byte sequences (codepoints > U+00FF) that the bitmap font cannot render.
	-- Latin-1 characters (2-byte sequences C2 80 – C3 BF) are preserved.
	text = string.gsub(text, "[\224-\244][\128-\191][\128-\191]+", " ")

	return text
end

--- Resolve display text for an entry: prefer text_de/text_en by game UI language, fallback to #text.
-- @param xmlFile number
-- @param entryKey string e.g. "conversation.entry(0)"
-- @param _conversationInstance table|nil unused, for future use
-- @return string
function IAConversation._resolveEntryText(xmlFile, entryKey, _conversationInstance)
	local textDe = getXMLString(xmlFile, entryKey .. "#text_de", "")
	local textEn = getXMLString(xmlFile, entryKey .. "#text_en", "")
	local textFallback = getXMLString(xmlFile, entryKey .. "#text", "")
	return IAConversation.resolveLocalizedModText(textDe, textEn, textFallback)
end

--- Resolve the displayable text for one variable placeholder.
--- Symbolic variables (jobType, vehicleNameWithArticle, extraRefillNote) take their text from
--- the voice catalog `text` / `textDe` attributes; raw-string variables (fieldNumber,
--- fieldNumbers, totalHectares, situationId) substitute their value verbatim.
--- @param string varName placeholder name (case-sensitive, matches variableMap key)
--- @param any value variableMap[varName]
--- @param table|nil voiceCatalog merged catalog (see IANeighbourDynamicConversationData)
--- @param string textField "text" (English / fallback) or "textDe" (German)
local function resolveVariablePlaceholderText(varName, value, voiceCatalog, textField)
	if value == nil then
		return ""
	end
	local rawValue = tostring(value)
	if voiceCatalog == nil or voiceCatalog.variables == nil then
		return rawValue
	end
	local entries = voiceCatalog.variables[string.lower(tostring(varName))]
	if entries == nil then
		return rawValue
	end
	local lookupKey = string.lower(rawValue)
	local entry = entries[lookupKey]
	if entry == nil then
		local n = tonumber(rawValue)
		if n ~= nil then
			entry = entries[n]
		end
	end
	if entry == nil then
		return rawValue
	end
	local catText = entry[textField]
	if catText == nil or catText == "" then
		return rawValue
	end
	return catText
end

--- Replace {key} placeholders in a string. Catalog-backed placeholders pull their text from
--- the voice catalog (per language); raw placeholders substitute their variableMap value.
--- Placeholders whose variableMap value is nil/empty are stripped (replaced with ""), so an
--- optional fragment like " {extraRefillNote}" disappears cleanly when the variable is unset.
--- @param text string|nil source text
--- @param variableMap table|nil map of placeholder name -> value
--- @param voiceCatalog table|nil merged voice catalog
--- @param textField string "text" (English / fallback) or "textDe" (German)
--- @return string
function IAConversation.applyVariablePlaceholdersToString(text, variableMap, voiceCatalog, textField)
	if text == nil then
		return ""
	end
	textField = textField or "text"
	local s = tostring(text)
	return (s:gsub("%{([%w_]+)%}", function(placeholderName)
		local value = variableMap and variableMap[placeholderName] or nil
		if value == nil or value == "" then
			return ""
		end
		return resolveVariablePlaceholderText(placeholderName, value, voiceCatalog, textField)
	end))
end

--- Mod-relative shared folder for dynamic variable clips of a given character
-- (e.g. `conversations/dynamic/21/shared`). Returns nil when neighbour/id is missing.
-- @param IANeighbour|nil neighbour
-- @return string|nil
function IAConversation.getDynamicSharedDirForNeighbour(neighbour)
	if neighbour == nil or neighbour.id == nil then
		return nil
	end
	return IAConversation.MOD_CONVERSATIONS_ROOT
		.. "/dynamic/" .. tostring(neighbour.id)
		.. "/" .. IAConversation.DYNAMIC_SHARED_FOLDER
end

--- Mod-relative shared folder for dynamic variable clips spoken by the player.
-- Lives at `conversations/dynamic/player/shared/` (independent of neighbour id) because the
-- player voice is the same across all characters (male / voiceId 0), so a single copy on disk
-- is reused by every dynamic conversation.
-- @return string
function IAConversation.getDynamicPlayerSharedDir()
	return IAConversation.MOD_CONVERSATIONS_ROOT
		.. "/dynamic/" .. IAConversation.DYNAMIC_PLAYER_FOLDER
		.. "/" .. IAConversation.DYNAMIC_SHARED_FOLDER
end

--- Mod-relative per-topic folder for dynamic named/static clips spoken by the player.
-- Derived from the resolved character topic dir by replacing the `<characterId>` segment with
-- `<DYNAMIC_PLAYER_FOLDER>` and dropping any trailing variant subdir, so the same player audio
-- is reused across every neighbour (and every variant) of the same topic.
--   conversations/dynamic/18/field_mission_offer            -> conversations/dynamic/player/field_mission_offer
--   conversations/dynamic/18/field_mission_offer/2          -> conversations/dynamic/player/field_mission_offer
-- The generator helper writes the corresponding `<lang>_male_0_<suffix>.ogg` files here too;
-- see helper/generate_dynamic_conversation_voices.ps1.
-- @param string|nil resolvedRelDir mod-relative path to the topic folder (or variant subdir)
-- @return string|nil
function IAConversation.getDynamicPlayerTopicDirFromResolvedDir(resolvedRelDir)
	if resolvedRelDir == nil or resolvedRelDir == "" then
		return nil
	end
	-- Expected layout: conversations/dynamic/<charId>/<topic>[/<variant>]. Capture the topic
	-- segment (first path component after `dynamic/<charId>/`).
	local topic = string.match(resolvedRelDir, "/dynamic/[^/\\]+/([^/\\]+)")
	if topic == nil or topic == "" then
		return nil
	end
	return IAConversation.MOD_CONVERSATIONS_ROOT
		.. "/dynamic/" .. IAConversation.DYNAMIC_PLAYER_FOLDER
		.. "/" .. topic
end

--- Mod-relative path for one voice segment clip (same pattern as _getVoicePath but custom suffix stem).
-- @param IANeighbour|nil neighbour
-- @param string conversationDir mod-relative folder containing the ogg
-- @param string suffix filename stem before .ogg (no extension)
-- @param string|nil speaker "player" uses player voice id 0; otherwise neighbour voice id
function IAConversation.buildModRelativeVoiceSegmentPath(neighbour, conversationDir, suffix, speaker)
	if IANeighbours == nil or IANeighbours.dir == nil or conversationDir == nil or suffix == nil or suffix == "" then
		return nil
	end
	speaker = speaker and string.lower(tostring(speaker)) or "npc"
	local lang = IAConversation._getVoicePackLanguage()
	local gender = IAConversation._getVoiceGender(speaker, neighbour)
	local voiceId = 1
	if speaker == "player" then
		voiceId = 0
	elseif neighbour ~= nil and neighbour.getVoiceId ~= nil then
		voiceId = neighbour:getVoiceId()
	end
	-- Suffix is lowercased so paths match files written by helper/generate_dynamic_conversation_voices.ps1
	-- which always saves filenames as <lang>_<gender>_<voiceId>_<suffix>.ogg in lowercase. Without this,
	-- mixed-case segment ids like "dm_jobType" would build "..._dm_jobType.ogg" while disk has "..._dm_jobtype.ogg".
	local suffixLower = string.lower(tostring(suffix))
	local rel = string.format("%s_%s_%d_%s.ogg", lang, gender, voiceId, suffixLower)
	if string.sub(conversationDir, -1) == "/" or string.sub(conversationDir, -1) == "\\" then
		return conversationDir .. rel
	end
	return conversationDir .. "/" .. rel
end

--- Build the voice clip suffix list for one numeric value using the merged FieldNumber catalog.
--- Returns an array (often 1 element) so the conversation engine can queue several clips
--- back-to-back for one logical line. When the value has its own catalog entry the result is
--- the single matching suffix (e.g. 100 -> { "fld_100" }, 50 -> { "fld_50" }). Otherwise the
--- value is decomposed into thousands + hundreds + 1..99 pieces matching the catalog grid
--- (e.g. 245 -> { "fld_200", "fld_45" }, 1234 -> { "fld_1000", "fld_200", "fld_34" }).
--- Values outside [numericMin, numericMax] are clamped first, which keeps the previous behaviour
--- for very large hectare/field numbers that go beyond the catalog (still produce something
--- speakable instead of silence).
local function lookupNumericFieldSuffixes(voiceCatalog, n)
	if voiceCatalog == nil or voiceCatalog.variables == nil then
		return {}
	end
	local entries = voiceCatalog.variables[IANeighbourDynamicConversationData.NUMERIC_CATALOG_KEY]
	if entries == nil then
		return {}
	end
	if n == nil then
		n = voiceCatalog.numericMin
	end
	if n == nil then
		return {}
	end
	if voiceCatalog.numericMin ~= nil and n < voiceCatalog.numericMin then n = voiceCatalog.numericMin end
	if voiceCatalog.numericMax ~= nil and n > voiceCatalog.numericMax then n = voiceCatalog.numericMax end

	local function appendSuffixIfPresent(list, key)
		local entry = entries[key]
		if entry ~= nil and entry.suffix ~= nil and entry.suffix ~= "" then
			table.insert(list, entry.suffix)
			return true
		end
		return false
	end

	-- Exact catalog entry: play a single dedicated clip (1..99, 100, 200, ..., 1000).
	local exact = entries[n]
	if exact ~= nil and exact.suffix ~= nil and exact.suffix ~= "" then
		return { exact.suffix }
	end

	-- No exact entry (e.g. 145, 245, ..., 1234): combine the hundred (and thousand) voice line
	-- with the 1..99 voice line so the playback queue gets one clip per piece, played
	-- back-to-back (multi-segment lines skip the inter-line pause in IAConversation:update).
	local suffixes = {}
	if n >= 1000 then
		local thousands = math.floor(n / 1000) * 1000
		appendSuffixIfPresent(suffixes, thousands)
		n = n - thousands
	end
	if n >= 100 then
		local hundreds = math.floor(n / 100) * 100
		appendSuffixIfPresent(suffixes, hundreds)
		n = n - hundreds
	end
	if n > 0 then
		appendSuffixIfPresent(suffixes, n)
	end
	return suffixes
end

--- Resolve one segment definition into the list of voice clip suffixes to play, in order.
--- Uses a per-character voice catalog (see data/IANeighbourDynamicConversationVoices.xml).
--- segmentDef: { type="static"|"named"|"variable", suffix?, id?, name? }
--- voiceCatalog: { named={}, variables={ [varNameLower]={ [valueKey]={ suffix, text, textDe } } }, numericMin, numericMax }
--- "named" segments use #id directly as the suffix by default (no catalog entry required);
--- a catalog `<named id=".." suffix=".."/>` entry only acts as an optional override.
--- "variable" segments look up the catalog table whose name matches the segment's `name`
--- attribute (case-insensitive). Numeric variables (fieldNumber / fieldNumbers / totalHectares)
--- share the single `<FieldNumber>` table and are clamped into its [numericMin, numericMax] range.
--- Returns an array; the typical static / named / symbolic-variable case is one element, but
--- numeric variables can split into multiple pieces (e.g. 245 -> { "fld_200", "fld_45" }) so
--- the engine plays "two hundred" followed by "forty five" back-to-back as two queued clips
--- of the same logical entry.
function IAConversation.resolveVoiceCatalogSuffixes(segmentDef, variableMap, voiceCatalog)
	if segmentDef == nil then
		return {}
	end
	local typ = string.lower(tostring(segmentDef.type or ""))
	if typ == "static" then
		local suf = segmentDef.suffix
		if suf ~= nil and suf ~= "" then
			return { tostring(suf) }
		end
		return {}
	end
	if typ == "named" then
		local id = segmentDef.id and tostring(segmentDef.id) or ""
		if id == "" then
			return {}
		end
		if voiceCatalog ~= nil and voiceCatalog.named ~= nil then
			local suf = voiceCatalog.named[id]
			if suf ~= nil and suf ~= "" then
				return { tostring(suf) }
			end
		end
		return { id }
	end
	if typ ~= "variable" or voiceCatalog == nil then
		return {}
	end
	local rawName = IAtrim(segmentDef.name)
	if rawName == "" then
		return {}
	end
	local lookupName = string.lower(rawName)
	if IANeighbourDynamicConversationData.NUMERIC_VARIABLE_NAMES[lookupName] then
		local value = variableMap and (variableMap[rawName] or variableMap[lookupName])
		local n = tonumber(value)
		if n ~= nil then
			n = math.floor(n + 0.5)
		end
		return lookupNumericFieldSuffixes(voiceCatalog, n)
	end
	local entries = voiceCatalog.variables and voiceCatalog.variables[lookupName]
	if entries == nil then
		return {}
	end
	local value = variableMap and (variableMap[rawName] or variableMap[lookupName])
	if value == nil or value == "" then
		return {}
	end
	local entry = entries[string.lower(tostring(value))]
	if entry == nil or entry.suffix == nil or entry.suffix == "" then
		return {}
	end
	return { tostring(entry.suffix) }
end

--- Read optional voice segment definitions from conversation.xml under an entry.
function IAConversation.readVoiceSegmentDefsFromXml(xmlFile, entryKey)
	local defs = {}
	local sIndex = 0
	while true do
		local sKey = entryKey .. ".voiceSegments.segment(" .. sIndex .. ")"
		local typ = getXMLString(xmlFile, sKey .. "#type", nil)
		if typ == nil or typ == "" then
			break
		end
		typ = string.lower(IAtrim(typ))
		if typ == "static" then
			table.insert(defs, { type = "static", suffix = getXMLString(xmlFile, sKey .. "#suffix", "") })
		elseif typ == "named" then
			-- Accept #id (canonical) and #name (typo-tolerant: some dynamic conversation XMLs write
			-- `<segment type="named" name="dm_outro"/>` instead of `id="dm_outro"`; both mean the same).
			local namedId = getXMLString(xmlFile, sKey .. "#id", "")
			if namedId == nil or namedId == "" then
				namedId = getXMLString(xmlFile, sKey .. "#name", "")
			end
			table.insert(defs, { type = "named", id = namedId or "" })
		elseif typ == "variable" then
			table.insert(defs, { type = "variable", name = getXMLString(xmlFile, sKey .. "#name", "") })
		end
		sIndex = sIndex + 1
	end
	return defs
end

--- Parse conversation.xml into entry maps (same rules as loadFromDirectory for root NPC / player remap).
-- @param xmlFile number loadXMLFile handle
-- @param string resolvedRelDir mod-relative path to folder containing conversation.xml (used for voice paths)
-- @param table|nil dynamicOpts if set: { variableMap, neighbour, voiceCatalog, callbacksByAction }
-- @return entriesById, entriesByPreviousId, playbackEndCallbacks|nil, selectImmediateCallbacks|nil
function IAConversation.parseConversationXmlToEntryTables(xmlFile, resolvedRelDir, dynamicOpts)
	local entriesById = {}
	local entriesByPreviousId = {}
	local playbackEndCallbacks = nil
	local selectImmediateCallbacks = nil
	if dynamicOpts ~= nil and dynamicOpts.callbacksByAction ~= nil then
		playbackEndCallbacks = {}
		selectImmediateCallbacks = {}
	end

	local rootKey = "conversation"
	local entryIndex = 0
	local firstRootNpcIdStr = nil
	while true do
		local entryKey = rootKey .. ".entry(" .. entryIndex .. ")"
		local id = getXMLString(xmlFile, entryKey .. "#id", nil)
		if id == nil then
			break
		end
		local previousId = getXMLString(xmlFile, entryKey .. "#previousId", "0")
		local speaker = getXMLString(xmlFile, entryKey .. "#speaker", "npc")
		local textResolved
		if dynamicOpts ~= nil and dynamicOpts.variableMap ~= nil then
			local varMap = dynamicOpts.variableMap
			local catalog = dynamicOpts.voiceCatalog
			local textDe = IAConversation.applyVariablePlaceholdersToString(getXMLString(xmlFile, entryKey .. "#text_de", ""), varMap, catalog, "textDe")
			local textEn = IAConversation.applyVariablePlaceholdersToString(getXMLString(xmlFile, entryKey .. "#text_en", ""), varMap, catalog, "text")
			local textFb = IAConversation.applyVariablePlaceholdersToString(getXMLString(xmlFile, entryKey .. "#text", ""), varMap, catalog, "text")
			textResolved = IAConversation.resolveLocalizedModText(textDe, textEn, textFb)
		else
			textResolved = IAConversation._resolveEntryText(xmlFile, entryKey, nil)
		end
		local filename = getXMLString(xmlFile, entryKey .. "#filename", nil)
		local voiceEffect = getXMLString(xmlFile, entryKey .. "#voiceEffect", nil)
		local relationship = getXMLString(xmlFile, entryKey .. "#relationship", nil)
		if relationship ~= nil then
			relationship = string.lower(tostring(relationship))
			if relationship == "" then
				relationship = nil
			end
		end
		local prevIdNum = tonumber(previousId)
		if prevIdNum == nil then
			prevIdNum = 0
		end
		local skipEntry = false
		if prevIdNum == 0 then
			local role = IAConversation._speakerRole(speaker)
			if role == "npc" then
				if firstRootNpcIdStr ~= nil then
					skipEntry = true
				else
					firstRootNpcIdStr = id
				end
			elseif role == "player" then
				local newPrev = tonumber(firstRootNpcIdStr) or 1
				prevIdNum = newPrev
			end
		end
		if not skipEntry then
			local entry = {
				id = id,
				previousId = prevIdNum,
				speaker = speaker and string.lower(speaker) or "npc",
				text = textResolved or "",
				filename = filename,
				voiceEffect = voiceEffect,
				relationship = relationship
			}
			if dynamicOpts ~= nil and dynamicOpts.neighbour ~= nil and dynamicOpts.voiceCatalog ~= nil then
				local segDefs = IAConversation.readVoiceSegmentDefsFromXml(xmlFile, entryKey)
				if #segDefs > 0 then
					local sharedDir = IAConversation.getDynamicSharedDirForNeighbour(dynamicOpts.neighbour)
					local playerSharedDir = IAConversation.getDynamicPlayerSharedDir()
					local playerTopicDir = IAConversation.getDynamicPlayerTopicDirFromResolvedDir(resolvedRelDir)
					local isPlayerEntry = entry.speaker == "player"
					local voiceSegments = {}
					for _, segDef in ipairs(segDefs) do
						local suffixes = IAConversation.resolveVoiceCatalogSuffixes(segDef, dynamicOpts.variableMap, dynamicOpts.voiceCatalog)
						if suffixes ~= nil and #suffixes > 0 then
							-- Variable clips (field numbers, hectares, job types, ...) are reused across topics.
							-- NPC variable clips are kept per-character (different voice / gender / id per neighbour).
							-- Player variable clips are global (same male / voiceId 0 voice for every character)
							-- so they live under a single `conversations/dynamic/player/shared/` folder.
							-- NPC named/static clips stay in the topic folder (per-character voice).
							-- Player named/static clips are identical across all characters that share the
							-- same topic, so they live once under `conversations/dynamic/player/<topic>/`
							-- and are reused by every neighbour at runtime.
							local segDir = resolvedRelDir
							local segType = segDef.type and string.lower(tostring(segDef.type)) or ""
							if segType == "variable" then
								if isPlayerEntry and playerSharedDir ~= nil then
									segDir = playerSharedDir
								elseif sharedDir ~= nil then
									segDir = sharedDir
								end
							elseif isPlayerEntry and playerTopicDir ~= nil and (segType == "named" or segType == "static") then
								segDir = playerTopicDir
							end
							-- One XML <segment> may resolve to several clips (numeric variables above 100
							-- decompose into hundred + 1..99 sub-segments). Push each as its own voice
							-- segment so they queue and play back-to-back as part of the same logical line.
							for _, suf in ipairs(suffixes) do
								local p = IAConversation.buildModRelativeVoiceSegmentPath(dynamicOpts.neighbour, segDir, suf, entry.speaker)
								if p ~= nil then
									IAprintDebug("buildModRelativeVoiceSegmentPath", "p: "..p, nil, nil, nil)
									table.insert(voiceSegments, { path = p })
								end
							end
						end
					end
					if #voiceSegments > 0 then
						entry.voiceSegments = voiceSegments
					end
				end
				local cbEnd = IAtrim(getXMLString(xmlFile, entryKey .. "#callbackOnPlaybackEnd", ""))
				local cbSel = IAtrim(getXMLString(xmlFile, entryKey .. "#callbackOnSelectImmediate", ""))
				-- Expose action names on the entry so entryAvailabilityFilter (e.g. IAMissionBorrow)
				-- can decide per option whether it should be hidden at choice points.
				if cbEnd ~= "" then
					entry.callbackOnPlaybackEnd = cbEnd
				end
				if cbSel ~= "" then
					entry.callbackOnSelectImmediate = cbSel
				end
				if cbEnd ~= "" and dynamicOpts.callbacksByAction ~= nil and dynamicOpts.callbacksByAction[cbEnd] ~= nil then
					playbackEndCallbacks[tostring(id)] = dynamicOpts.callbacksByAction[cbEnd]
				end
				if cbSel ~= "" and dynamicOpts.callbacksByAction ~= nil and dynamicOpts.callbacksByAction[cbSel] ~= nil then
					selectImmediateCallbacks[tostring(id)] = dynamicOpts.callbacksByAction[cbSel]
				end
			end
			entriesById[id] = entry
			if entriesByPreviousId[prevIdNum] == nil then
				entriesByPreviousId[prevIdNum] = {}
			end
			table.insert(entriesByPreviousId[prevIdNum], entry)
		end
		entryIndex = entryIndex + 1
	end

	if playbackEndCallbacks ~= nil and next(playbackEndCallbacks) == nil then
		playbackEndCallbacks = nil
	end
	if selectImmediateCallbacks ~= nil and next(selectImmediateCallbacks) == nil then
		selectImmediateCallbacks = nil
	end
	return entriesById, entriesByPreviousId, playbackEndCallbacks, selectImmediateCallbacks
end

--- Check if a dialog is registered (game Gui uses .guis table, not hasGui).
local function hasGui(gui, name)
	return gui ~= nil and gui.guis ~= nil and gui.guis[name] ~= nil
end

--- Ensure the mod's IAConversationDialog is available (load from mod gui so layout and click work).
-- @return boolean true if the dialog can be shown
function IAConversation.ensureConversationDialogLoaded()
	if hasGui(g_gui, IAConversation.CONVERSATION_DIALOG_NAME) then
		return true
	end
	local baseDir = IANeighbours.dir
	if baseDir == nil then
		if IANeighbours.debug then
			print("--- IAConversation:ensureConversationDialogLoaded() - IANeighbours.dir is nil")
		end
		return false
	end
	local path = baseDir.."gui/IAConversationDialog.xml"
	-- loadGui expects a controller *instance* (it calls controller:addElement(gui)); passing the class causes nil .elements
	local controller = IAConversationDialog.new(g_gui)
	g_gui:loadGui(path, IAConversation.CONVERSATION_DIALOG_NAME, controller, false)
	return hasGui(g_gui, IAConversation.CONVERSATION_DIALOG_NAME)
end

--- Start conversation; show subtitle dialog immediately and keep it visible for the whole conversation.
-- @param previousId number e.g. 0 for start
-- @param npcName string name for NPC lines
-- @param situation IASituation (for setSituation and for clearing activeDialog/dialogController on stop)
function IAConversation:start(previousId, npcName, situation)
	if not IAConversation.ensureConversationDialogLoaded() then
		if IANeighbours.debug then
				print("--- IAConversation:start() - IAConversationDialog not available")
			end
		return
	end
	self.dialogController = nil
	self.dialog = nil
	self.npcName = npcName and npcName or "Neighbour"
	self.situation = situation
	-- A standalone call is always a phone call; non-standalone conversations become phone calls once a "phone" voice line is queued/played.
	self.isPhoneCallConversation = self.isStandalonePhoneCall == true
	-- Standalone phone call: loop ambient background noise from answer until the call ends (hang_up.ogg).
	if self.isStandalonePhoneCall == true then
		--self:playPhoneBackgroundSound() --disabled for now
	end
	self:startFrom(previousId)
	--print("--- IAConversation:start() - previousId=" .. tostring(previousId) .. " npcName=" .. tostring(npcName) .. " situation=" .. tostring(situation))
	if self._lastState then
		--print("--- IAConversation:start() - _lastState=" .. tostring(self._lastState))
		self:_showDialog(self._lastState)
		-- Start first line playback after dialog is visible so first line appears in UI
		self:_playNextInQueue()
	end
end

--- Show or update the subtitle dialog. Opens at first call, then updates state.messages (current line). Never hidden until stop().
 -- So the dialog does not freeze player controls, we set needInput=false on the dialog target before showDialog (Gui only enters menu context when needInput is nil or true).
-- @param state table with .messages (from _buildStateFromEntries)
function IAConversation:_showDialog(state)
	--print("--- IAConversation:_showDialog() - state=" .. tostring(state))
	if not IAConversation.ensureConversationDialogLoaded() then
		return
	end
	--print("--- IAConversation:_showDialog() - self.dialog=" .. tostring(self.dialog))
	if self.dialog == nil then
		--print("--- IAConversation:_showDialog() - self.dialog is nil")
		local gui = g_gui.guis and g_gui.guis[IAConversation.CONVERSATION_DIALOG_NAME]
		if gui and gui.target then
			gui.target.needInput = false  -- keep player movable while dialog is open
		end
		self.dialog = g_gui:showDialog(IAConversation.CONVERSATION_DIALOG_NAME)
		if self.dialog == nil then
			return
		end
		-- Show mouse cursor and center it so player can click Skip/options while still moving
		if g_inputBinding then
			self._cursorVisibleBeforeDialog = g_inputBinding.getShowMouseCursor and g_inputBinding:getShowMouseCursor()
			--print("--- IAConversation:_showDialog() - _cursorVisibleBeforeDialog=" .. tostring(self._cursorVisibleBeforeDialog))
			if g_inputBinding.setShowMouseCursor then
				g_inputBinding:setShowMouseCursor(true)
				--print("--- IAConversation:_showDialog() - setShowMouseCursor true")
			end
		end
		if wrapMousePosition then
			wrapMousePosition(0.5, 0)
		end
		if self.dialog.target ~= nil then
			self.dialogController = self.dialog.target
			if self.dialogController.setSituation and self.situation ~= nil then
				self.dialogController:setSituation(self.situation)
			end
			if self.dialogController.setNpcName then
				self.dialogController:setNpcName(self.npcName)
			end
			if self.dialogController.setDialog then
				self.dialogController:setDialog(self.dialog)
			end
			-- Wire advance: button overlay and conversation box (RoundCorner) so click anywhere on text area advances
			local conversation = self
			local function wireAdvance(element)
				if element then
					element.onClickCallback = function()
						conversation:requestAdvanceToNextLine()
					end
				end
			end
			wireAdvance(self.dialogController.clickToAdvanceButton or (self.dialog.getDescendantByName and self.dialog:getDescendantByName("clickToAdvanceButton")))
		end
		if self.situation ~= nil then
			self.situation.activeDialog = self.dialog
			self.situation.dialogController = self.dialogController
		end
	end
	if state and state.messages then
		self:_applyState(state)
	end
	if state ~= nil then
		self:_updateOptionButtons(state)
		-- Keep self in sync with the dialog state (selectOption passes a partial state without re-running _buildStateFromEntries).
		-- Otherwise self.isChoicePoint stays true after picking an option and requestAdvanceToNextLine() ignores clicks.
		if state.isChoicePoint == true then
			self.isChoicePoint = true
			if state.nextOptions ~= nil then
				self.nextOptions = state.nextOptions
			end
			self.currentId = nil
		elseif state.isChoicePoint == false then
			self.isChoicePoint = false
			self.nextOptions = nil
			if state.currentId ~= nil then
				self.currentId = state.currentId
			else
				self.currentId = nil
			end
		end
	end
end

--- After subtitle dialog closes: we always forced cursor visible for Skip/options — hide for on-foot gameplay.
function IAConversation._hideMouseCursorAfterConversation()
	if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor then
		--print("--- IAConversation._hideMouseCursorAfterConversation() - setShowMouseCursor false")
		g_inputBinding:setShowMouseCursor(false)
	end
end

--- Hide the dialog. Only used from stop(); we do not hide between lines (dialog is the subtitle display).
function IAConversation:_hideDialog()
	if self.dialog == nil then
		return
	end
	--print("--- IAConversation:_hideDialog() - _cursorVisibleBeforeDialog=" .. tostring(self._cursorVisibleBeforeDialog))
	IAConversation._hideMouseCursorAfterConversation()
	self._cursorVisibleBeforeDialog = nil
	g_gui:closeDialog(self.dialog)
	self.dialog = nil
	self.dialogController = nil
	if self.situation ~= nil then
		self.situation.activeDialog = nil
		self.situation.dialogController = nil
	end
end

--- True while IAConversationDialog is shown (in-world or phone); used by IANeighbours.refreshActiveConversationState.
function IAConversation:hasSubtitleDialogOpen()
	return self.dialog ~= nil
end

--- Set the current subtitle line in the dialog (id="textElement"). Tries dialogController.textElement then dialog:getDescendantByName.
function IAConversation:setCurrentSubtitle(text)
	local t = text and tostring(text) or ""
	local textEl = nil
	if self.dialogController ~= nil and self.dialogController.textElement ~= nil then
		textEl = self.dialogController.textElement
	end
	if (textEl == nil or not textEl.setText) and self.dialog ~= nil and self.dialog.getDescendantByName then
		textEl = self.dialog:getDescendantByName("textElement")
	end
	if textEl ~= nil and textEl.setText then
		textEl:setText(t)
	end
	if self.dialogController and self.dialogController.updateTextBoxHeight then
		local choiceFromSituation = self.situation ~= nil and self.situation.isChoicePoint == true and self.situation.nextOptions ~= nil and #self.situation.nextOptions > 0
		local choiceFromSelf = self.isChoicePoint == true and self.nextOptions ~= nil and #self.nextOptions > 0
		self.dialogController:updateTextBoxHeight(choiceFromSituation or choiceFromSelf)
	end
end

--- Set speaker name label (NPC name or "Player") and subtitle text. Call when switching who is speaking.
-- @param speaker string "npc" or "player"
-- @param text string subtitle text
function IAConversation:setCurrentSpeakerAndSubtitle(speaker, text)
	local displayName = self.npcName or "Neighbour"
	if speaker == "player" then
		displayName = "You"
	end
	if self.dialogController ~= nil and self.dialogController.setNpcName then
		self.dialogController:setNpcName(displayName)
	end
	self:setCurrentSubtitle(text)
end

--- Apply state to dialog: set speaker and current subtitle from last message (used when opening/updating dialog state).
function IAConversation:_applyState(state)
	if state == nil then
		return
	end
	if state.messages == nil or #state.messages == 0 then
		-- Player-only choice points leave messages empty; last NPC line was already shown by playback — do not clear.
		if state.isChoicePoint == true then
			return
		end
		self:setCurrentSpeakerAndSubtitle("npc", "")
		return
	end
	local lastMsg = state.messages[#state.messages]
	local speaker = (lastMsg.speaker and string.lower(tostring(lastMsg.speaker))) or "npc"
	self:setCurrentSpeakerAndSubtitle(speaker, lastMsg.text)
end

--- Update option buttons from state: same procedure as IADialogGUI addMessage – clone template into ScrollingLayout, set text, wire click; clear like clearChatHistory.
function IAConversation:_updateOptionButtons(state)
	if self.dialog == nil or self.dialogController == nil then
		return
	end
	local scrollingLayout = self.dialogController.optionsScrollingLayout
	local optionButtonTemplate = self.dialogController.optionButtonTemplate
	local optionBoxBackground = self.dialogController.optionBoxBackground
	if scrollingLayout == nil or optionButtonTemplate == nil then
		return
	end
	-- Clear all option clones (keep only the template), same as IADialogGUI clearChatHistory
	local elementsToRemove = {}
	if scrollingLayout.elements then
		for i = 1, #scrollingLayout.elements do
			local el = scrollingLayout.elements[i]
			if el ~= optionButtonTemplate and (el.id == nil or el.id ~= "optionButtonTemplate") then
				table.insert(elementsToRemove, el)
			end
		end
	end
	for _, el in ipairs(elementsToRemove) do
		if scrollingLayout.removeElement then
			scrollingLayout:removeElement(el)
		else
			el:unlinkElement()
		end
		el:delete()
	end
	if optionButtonTemplate.setVisible then
		optionButtonTemplate:setVisible(false)
	end
	local showOptions = state.isChoicePoint and state.nextOptions and #state.nextOptions > 0
	if optionBoxBackground and optionBoxBackground.setVisible then
		optionBoxBackground:setVisible(showOptions)
	end
	if scrollingLayout.setVisible then
		scrollingLayout:setVisible(showOptions)
	end
	-- Hide Skip button when choices are visible
	local skipBtn = self.dialogController.clickToAdvanceButton
	if skipBtn and skipBtn.setVisible then
		skipBtn:setVisible(not showOptions)
	end
	if showOptions then
		for _, entry in ipairs(state.nextOptions) do
			-- Same procedure as IADialogGUI addMessage: clone template into scrolling layout
			local clone = optionButtonTemplate:clone(scrollingLayout, false, false)
			if clone == nil then
				break
			end
			local entryId = entry.id
			local textEl = clone:getDescendantByName("text")
			if textEl and textEl.setText then
				local optionText = entry.text or ""
				if #optionText > 70 then
					optionText = optionText:sub(1, 70) .. "..."
				end
				textEl:setText(optionText)
			end
			local rowBg = clone.elements and clone.elements[1]
			local guiButton = rowBg and rowBg.elements and rowBg.elements[1]
			if guiButton then
				guiButton.optionEntryId = entryId
				if textEl then
					textEl.optionEntryId = entryId
				end
				guiButton.onClickCallback = function(_, index)
					local id = type(index) == "table" and index.optionEntryId or nil
					if id and self.situation and self.situation.selectConversationOption then
						self.situation:selectConversationOption(id)
					elseif id then
						self:selectOption(id)
					end
				end
			end

			clone:setVisible(true)
			if clone.invalidateLayout then
				clone:invalidateLayout()
			end
		end
		if scrollingLayout.invalidateLayout then
			scrollingLayout:invalidateLayout()
		end
		-- Scroll to top so first options are visible (IADialogGUI scrolls to bottom for chat; here we want top)
		if scrollingLayout.scrollTo then
			scrollingLayout:scrollTo(0, true, false)
		end

		self.dialogController:updateTextBoxHeight(showOptions)
	end
end

--- Resolve mod-relative conversation directory: either `.../situation/conversation.xml` (no variant subfolder),
-- or `.../situation/<variant>/` using variant ids from conversations-structure.xml (random pick if several).
-- @param situationBaseDir string Mod-relative path without variant, e.g. "conversations/17/6"
-- @return string|nil resolved mod-relative path, or nil if nothing loadable
function IAConversation.resolveRandomSituationVariantDirectory(situationBaseDir)
	local baseDir = IANeighbours.dir
	if baseDir == nil or situationBaseDir == nil or situationBaseDir == "" then
		return nil
	end
	local legacyPath = Utils.getFilename(situationBaseDir .. "/conversation.xml", baseDir)
	if fileExists(legacyPath) then
		return situationBaseDir
	end
	local norm = string.gsub(situationBaseDir, "\\", "/")
	local root = string.gsub(IAConversation.MOD_CONVERSATIONS_ROOT, "\\", "/")
	local folderCharId, sitId = string.match(norm, "^" .. root .. "/([^/]+)/([^/]+)$")
	if folderCharId ~= nil and sitId ~= nil then
		local structIndex = IAConversation.structureCharacterIndexByFolderId[folderCharId]
		local byChar = structIndex ~= nil and IAConversation.situationVariantIds[structIndex] or nil
		local variantList = byChar ~= nil and byChar[sitId] or nil
		if variantList ~= nil and #variantList > 0 then
			local pick = variantList[math.random(1, #variantList)]
			return situationBaseDir .. "/" .. tostring(pick)
		end
	end
	return nil
end

--- Pick a random variant under conversations/dynamic/<character>/<topic>/ when subfolders 1..N each contain conversation.xml.
-- If conversation.xml exists directly under baseRelDir, returns baseRelDir.
-- @param string baseRelDir mod-relative e.g. conversations/dynamic/1/field_mission_offer
-- @return string|nil
function IAConversation.resolveDynamicConversationVariantDirectory(baseRelDir)
	local baseDir = IANeighbours.dir
	if baseDir == nil or baseRelDir == nil or baseRelDir == "" then
		return nil
	end
	local legacyPath = Utils.getFilename(baseRelDir .. "/conversation.xml", baseDir)
	if fileExists(legacyPath) then
		return baseRelDir
	end
	local variants = {}
	for i = 1, 40 do
		local sub = baseRelDir .. "/" .. tostring(i)
		local xp = Utils.getFilename(sub .. "/conversation.xml", baseDir)
		if fileExists(xp) then
			table.insert(variants, sub)
		end
	end
	if #variants == 0 then
		return nil
	end
	return variants[math.random(1, #variants)]
end

--- Load conversation from a directory: read conversation.xml, fill entriesById and entriesByPreviousId.
-- @param conversationDir string Mod-relative path, e.g. "conversations/27" or situation base "conversations/1/5" when pickRandomSituationVariant is true
-- @param pickRandomSituationVariant boolean|nil if true, resolve conversations/<neighbour>/<situation>/<variant>/ randomly
-- @return boolean success
function IAConversation:loadFromDirectory(conversationDir, pickRandomSituationVariant)
	local resolvedDir = conversationDir
	if pickRandomSituationVariant then
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - [situation] random variant mode, base path: " .. tostring(conversationDir))
		end
		resolvedDir = IAConversation.resolveRandomSituationVariantDirectory(conversationDir)
		if resolvedDir == nil then
			if IANeighbours.debug then
				print("--- IAConversation:loadFromDirectory() - [situation] FAILED: no flat conversation.xml and no structure entry for: " .. tostring(conversationDir))
			end
			return false
		end
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - [situation] resolved conversation dir: " .. tostring(resolvedDir))
		end
	else
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - loading: " .. tostring(conversationDir))
		end
	end

	self.conversationDir = resolvedDir
	self.entriesById = {}
	self.entriesByPreviousId = {}
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	self._lastNpcRelationship = nil

	local baseDir = IANeighbours.dir
	if baseDir == nil then
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - FAILED: IANeighbours.dir is nil")
		end
		return false
	end
	local xmlPath = Utils.getFilename(resolvedDir .. "/conversation.xml", baseDir)
	if not fileExists(xmlPath) then
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - FAILED: file not found: " .. tostring(xmlPath))
		end
		return false
	end
	if IANeighbours.debug then
		print("--- IAConversation:loadFromDirectory() - reading XML: " .. tostring(xmlPath))
	end

	local xmlFile = loadXMLFile("IAConversation", xmlPath)
	if xmlFile == nil then
		if IANeighbours.debug then
			print("--- IAConversation:loadFromDirectory() - FAILED: loadXMLFile returned nil for: " .. tostring(xmlPath))
		end
		return false
	end

	local byId, byPrev = IAConversation.parseConversationXmlToEntryTables(xmlFile, resolvedDir, nil)
	self.entriesById = byId
	self.entriesByPreviousId = byPrev
	delete(xmlFile)
	if IANeighbours.debug then
		local tag = pickRandomSituationVariant and "[situation] " or ""
		local cnt = 0
		for _ in pairs(byId) do
			cnt = cnt + 1
		end
		print("--- IAConversation:loadFromDirectory() - " .. tag .. "OK: " .. tostring(cnt) .. " entries | mod-relative dir: " .. tostring(resolvedDir) .. " | xml: " .. tostring(xmlPath))
	end
	return true
end

--- Per-character dynamic tree: same conversation.xml + branching as loadFromDirectory, with {placeholders} in text
-- and optional voiceSegments resolved via voiceCatalog (see data/IANeighbourDynamicConversationVoices.xml).
-- Audio files live under the resolved variant folder; filenames use this neighbour's voice id (character-specific).
-- @param conversationBaseDir string e.g. conversations/dynamic/17/field_mission_offer
-- @param pickRandomSituationVariant boolean|nil if true, pick random subfolder with conversation.xml (same as situations)
-- @param IANeighbour neighbour
-- @param table variableMap keys like fieldNumber, jobType, situationId for {placeholder} substitution
-- @param table voiceCatalog merged catalog for this character: { named={}, variables={ [varNameLower]={ [valueKey]={ suffix, text, textDe } } }, numericMin, numericMax }
-- @param table|nil callbacksByAction maps XML callbackOn* action strings to functions(conversation, situation, entryIdStr)
-- @return boolean success
function IAConversation:loadDynamicConversationFromDirectory(conversationBaseDir, pickRandomSituationVariant, neighbour, variableMap, voiceCatalog, callbacksByAction)
	local resolvedDir = conversationBaseDir
	if pickRandomSituationVariant then
		resolvedDir = IAConversation.resolveDynamicConversationVariantDirectory(conversationBaseDir)
		if resolvedDir == nil then
			if IANeighbours.debug then
				print("--- IAConversation:loadDynamicConversationFromDirectory() FAILED resolve variant for " .. tostring(conversationBaseDir))
			end
			return false
		end
	end
	self.conversationDir = resolvedDir
	self.entriesById = {}
	self.entriesByPreviousId = {}
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	self._lastNpcRelationship = nil

	local baseDir = IANeighbours.dir
	if baseDir == nil then
		return false
	end
	local xmlPath = Utils.getFilename(resolvedDir .. "/conversation.xml", baseDir)
	if not fileExists(xmlPath) then
		if IANeighbours.debug then
			print("--- IAConversation:loadDynamicConversationFromDirectory() missing " .. tostring(xmlPath))
		end
		return false
	end
	local xmlFile = loadXMLFile("IAConversationDyn", xmlPath)
	if xmlFile == nil then
		return false
	end
	local byId, byPrev, pb, sel = IAConversation.parseConversationXmlToEntryTables(xmlFile, resolvedDir, {
		variableMap = variableMap or {},
		neighbour = neighbour,
		voiceCatalog = voiceCatalog or {},
		callbacksByAction = callbacksByAction
	})
	delete(xmlFile)
	self.entriesById = byId
	self.entriesByPreviousId = byPrev
	self.entryPlaybackEndCallbacks = pb
	self.entrySelectImmediateCallbacks = sel
	if IANeighbours.debug then
		local cnt = 0
		for _ in pairs(byId) do
			cnt = cnt + 1
		end
		print("--- IAConversation:loadDynamicConversationFromDirectory() OK entries=" .. tostring(cnt) .. " dir=" .. tostring(resolvedDir))
	end
	return true
end

--- Load conversation graph from pre-built entry maps (no conversation.xml on disk). Same entry shape as loadFromDirectory.
-- @param conversationDir string mod-relative base path for voice files, e.g. conversations/dynamic/field_mission
-- @param entriesById table id string -> entry
-- @param entriesByPreviousId table number previousId -> array of entries
function IAConversation:loadFromRuntimeEntries(conversationDir, entriesById, entriesByPreviousId)
	self.conversationDir = conversationDir
	self.entriesById = entriesById or {}
	self.entriesByPreviousId = entriesByPreviousId or {}
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	self._lastNpcRelationship = nil
	if IANeighbours.debug then
		local n = 0
		for _ in pairs(self.entriesById) do
			n = n + 1
		end
		print("--- IAConversation:loadFromRuntimeEntries() dir=" .. tostring(conversationDir) .. " entries=" .. tostring(n))
	end
end

--- @param callbackMap table|nil maps string entry id -> function(conversation, situation, entryId)
function IAConversation:setEntryPlaybackEndCallbacks(callbackMap)
	self.entryPlaybackEndCallbacks = callbackMap
end

--- Invoked when the player selects this option (before follow-up playback). Same signature as playback-end callbacks.
-- @param callbackMap table|nil maps string entry id -> function(conversation, situation, entryId)
function IAConversation:setEntrySelectImmediateCallbacks(callbackMap)
	self.entrySelectImmediateCallbacks = callbackMap
end

function IAConversation:_invokeEntryPlaybackEndCallback(entryIdStr)
	if entryIdStr == nil or self.entryPlaybackEndCallbacks == nil then
		return
	end
	local cb = self.entryPlaybackEndCallbacks[tostring(entryIdStr)]
	if cb ~= nil then
		local ok, err = pcall(cb, self, self.situation, entryIdStr)
		if not ok and IANeighbours ~= nil and IANeighbours.debug then
			print("--- IAConversation:_invokeEntryPlaybackEndCallback() ERROR entryId=" .. tostring(entryIdStr) .. " err=" .. tostring(err))
		end
	end
end

function IAConversation:_invokeEntrySelectImmediateCallback(entryIdStr)
	if entryIdStr == nil or self.entrySelectImmediateCallbacks == nil then
		return
	end
	local cb = self.entrySelectImmediateCallbacks[tostring(entryIdStr)]
	if cb ~= nil then
		local ok, err = pcall(cb, self, self.situation, entryIdStr)
		if not ok and IANeighbours ~= nil and IANeighbours.debug then
			print("--- IAConversation:_invokeEntrySelectImmediateCallback() ERROR entryId=" .. tostring(entryIdStr) .. " err=" .. tostring(err))
		end
	end
end

--- Remove queued clips for the same logical line (multi-segment voice) from the front of the queue.
function IAConversation:_flushPlaybackQueueForLogicalEntryId(logicalEntryId)
	if logicalEntryId == nil or self.playbackQueue == nil then
		return
	end
	local idStr = tostring(logicalEntryId)
	while #self.playbackQueue > 0 do
		local first = self.playbackQueue[1]
		if first ~= nil and first.logicalEntryId ~= nil and tostring(first.logicalEntryId) == idStr then
			table.remove(self.playbackQueue, 1)
		else
			break
		end
	end
end

function IAConversation:getEntriesByPreviousId(previousId)
	local list = self.entriesByPreviousId[previousId]
	if list == nil then
		return {}
	end
	return list
end

function IAConversation:getEntryById(id)
	return self.entriesById[id]
end

--- "npc" or "player" for alternation rules (anything non-npc counts as player).
function IAConversation._speakerRole(speaker)
	if speaker == nil then
		return nil
	end
	if string.lower(tostring(speaker)) == "npc" then
		return "npc"
	end
	return "player"
end

--- When several branches share the same previousId, keep only lines for the expected next speaker
-- (npc after player, player after npc). Single-branch flows are unchanged.
function IAConversation:_filterEntriesForAlternation(entries, parentSpeaker)
	if entries == nil or #entries <= 1 then
		return entries
	end
	local parentRole = IAConversation._speakerRole(parentSpeaker)
	if parentRole == nil then
		return entries
	end
	local want = (parentRole == "npc") and "player" or "npc"
	local filtered = {}
	for _, e in ipairs(entries) do
		if IAConversation._speakerRole(e.speaker) == want then
			table.insert(filtered, e)
		end
	end
	if #filtered == 0 then
		return entries
	end
	return filtered
end

--- Build state from entries and fill playback queue. One NPC = 1:1 flow; multiple player lines = choice point;
-- multiple NPC lines = pick one at random (variant lines), no option UI.
-- @param entries array of entry tables
-- @param parentSpeaker string|nil speaker of the entry these rows hang off (for multi-option alternation)
-- @return state { messages = {{ speaker, text }}, currentId, nextOptions, isChoicePoint }
function IAConversation:_filterEntriesByAvailability(entries)
	if entries == nil or self.entryAvailabilityFilter == nil then
		return entries
	end
	local filtered = {}
	for _, e in ipairs(entries) do
		local ok = true
		local okCall, res = pcall(self.entryAvailabilityFilter, e)
		if okCall then
			ok = res ~= false
		end
		if ok then
			table.insert(filtered, e)
		end
	end
	if #filtered == 0 then
		return entries
	end
	return filtered
end

function IAConversation:_buildStateFromEntries(entries, parentSpeaker)
	entries = self:_filterEntriesForAlternation(entries, parentSpeaker)
	entries = self:_filterEntriesByAvailability(entries)
	local state = { messages = {}, currentId = nil, nextOptions = nil, isChoicePoint = false }
	if entries == nil or #entries == 0 then
		self.currentId = nil
		self.nextOptions = nil
		self.isChoicePoint = false
		self.playbackQueue = {}
		return state
	end
	-- Several NPC branches after a player line: random variant, same as a single NPC node (no choices for the player).
	if #entries > 1 then
		local allNpc = true
		for _, e in ipairs(entries) do
			if IAConversation._speakerRole(e.speaker) ~= "npc" then
				allNpc = false
				break
			end
		end
		if allNpc then
			return self:_buildStateFromEntries({ entries[math.random(1, #entries)] }, parentSpeaker)
		end
	end
	-- Single entry: never a choice point (only one path). NPC = queue and play; player = just advance to next node.
	if #entries == 1 then
		local e = entries[1]
		state.currentId = e.id
		state.nextOptions = nil
		state.isChoicePoint = false
		self.currentId = e.id
		self.nextOptions = nil
		self.isChoicePoint = false
		if e.speaker == "npc" or e.speaker == "NPC" then
			state.messages = { { speaker = "npc", text = e.text or "" } }
			self:_queueNpcEntriesForPlayback({ e })
		else
			-- Single player entry: play player voice (path by pattern), then advance to next node when done
			self:_queueNpcEntriesForPlayback({ e })
			if self.currentSample == nil and #(self.playbackQueue or {}) == 0 then
				self.pendingAutoAdvance = true
			end
		end
		return state
	end
	-- Multiple player entries: choice point; optional NPC preview lines (same previousId) play first, then options
	local npcEntries = {}
	for _, e in ipairs(entries) do
		if e and (e.speaker == "npc" or e.speaker == "NPC") and e.text and e.text ~= "" then
			table.insert(state.messages, { speaker = "npc", text = e.text })
			table.insert(npcEntries, e)
		end
	end
	state.currentId = nil
	state.nextOptions = entries
	state.isChoicePoint = true
	self.currentId = nil
	self.nextOptions = entries
	self.isChoicePoint = true
	self:_queueNpcEntriesForPlayback(npcEntries)
	return state
end

--- Internal: fill playback queue from entries (path, effect, speaker, text). Voice path: {lang}_{gender}_{voiceId}_{entryId}.ogg.
-- Entries may set voiceSegments: array of { path, effect?, speaker? } for one subtitle line split into sequential clips.
-- Does not start playing the first line (caller should call _playNextInQueue after dialog is visible for first line to appear).
function IAConversation:_queueNpcEntriesForPlayback(entries)
	self.playbackQueue = {}
	if self.conversationDir == nil or entries == nil then
		return
	end
	for _, e in ipairs(entries) do
		if e then
			local text = e.text and tostring(e.text) or ""
			local logicalId = e.id ~= nil and tostring(e.id) or nil
			local speaker = e.speaker
			if e.voiceEffect ~= nil and string.lower(tostring(e.voiceEffect)) == "phone" then
				self.isPhoneCallConversation = true
			end
			if e.speaker == "npc" or e.speaker == "NPC" then
				self._lastNpcRelationship = e.relationship
			end
			if e.voiceSegments ~= nil and #e.voiceSegments > 0 then
				local n = #e.voiceSegments
				for i, seg in ipairs(e.voiceSegments) do
					if seg ~= nil and seg.path ~= nil and seg.path ~= "" then
						table.insert(self.playbackQueue, {
							path = seg.path,
							effect = seg.effect or e.voiceEffect,
							speaker = seg.speaker or speaker,
							text = text,
							logicalEntryId = logicalId,
							isLastSegment = (i == n)
						})
					end
				end
			else
				local path = self:_getVoicePath(e)
				if path then
					table.insert(self.playbackQueue, {
						path = path,
						effect = e.voiceEffect,
						speaker = speaker,
						text = text,
						logicalEntryId = logicalId,
						isLastSegment = true
					})
				end
			end
		end
	end
end

--- Play the next item in the playback queue (subtitle + voice). Call after dialog is shown so first line appears in UI.
function IAConversation:_playNextInQueue()
	if self.playbackQueue == nil or #self.playbackQueue == 0 then
		return
	end
	local item = self.playbackQueue[1]
	IAprintDebug("_playNextInQueue", "item: "..tostring(item.path), nil, nil, nil)
	table.remove(self.playbackQueue, 1)
	self:_playCurrentLine(item)
end

--- Start conversation from a node (e.g. previousId 0 for root). Queues playback; dialog shown only at choice points.
-- @param previousId number e.g. 0 for start
function IAConversation:startFrom(previousId)
	local prevNum = tonumber(previousId)
	if prevNum == nil then
		prevNum = 0
	end
	local entries = self:getEntriesByPreviousId(prevNum)
	local parentSpeaker = nil
	if prevNum ~= 0 then
		local pe = self:getEntryById(tostring(previousId)) or self:getEntryById(previousId)
		if pe ~= nil then
			parentSpeaker = pe.speaker
		end
	end
	local state = self:_buildStateFromEntries(entries, parentSpeaker)
	self._lastState = state
end

--- Advance after player chose an option; play chosen option's voice if present, then show follow-up state. Handles main menu: Goodbye and smalltalk selection.
-- @param chosenEntryId string|number id of the chosen entry (from nextOptions[i].id or main menu)
function IAConversation:selectOption(chosenEntryId)
	local idStr = tostring(chosenEntryId)
	if idStr == "goodbye" then
		self._mainMenuOptions = nil
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:selectOption() - goodbye clicked, playing success UI sound")
		end
		local neighbour = (self.situation ~= nil) and self.situation.neighbour or nil
		self:stop(true)
		if (not self.hasGrantedConversationScore) and neighbour ~= nil and neighbour.addScore ~= nil then
			local delta
			if self._lastNpcRelationship == "minus" then
				delta = -10
			else
				delta = math.random(20, 120)
			end
			neighbour:addScore(delta)
			self.hasGrantedConversationScore = true
		end
		return
	end
	if self._mainMenuOptions then
		for _, opt in ipairs(self._mainMenuOptions) do
			if tostring(opt.id) == idStr and opt.conversationDir then
				self._mainMenuOptions = nil
				self:loadFromDirectory(opt.conversationDir)
				self:startFrom(0)
				if self._lastState then
					self:_showDialog(self._lastState)
				end
				return
			end
		end
		self._mainMenuOptions = nil
	end
	local idNum = tonumber(chosenEntryId)
	if idNum == nil then
		return
	end
	local chosenEntry = self:getEntryById(tostring(chosenEntryId)) or self:getEntryById(chosenEntryId)
	local nextEntries = self:getEntriesByPreviousId(idNum)
	if chosenEntry then
		self:_invokeEntrySelectImmediateCallback(tostring(chosenEntryId))
		self.currentId = idNum
		self:_showDialog({ messages = { { speaker = chosenEntry.speaker or "player", text = chosenEntry.text or "" } }, currentId = idNum, nextOptions = nil, isChoicePoint = false })
		self:_queueNpcEntriesForPlayback({ chosenEntry })
		-- If no voice path was found, advance to next node immediately
		if self.currentSample == nil and #(self.playbackQueue or {}) == 0 then
			self.pendingAutoAdvance = true
		end
	else
		local parentEntry = self:getEntryById(tostring(idNum)) or self:getEntryById(idNum)
		local parentSp = parentEntry ~= nil and parentEntry.speaker or nil
		local state = self:_buildStateFromEntries(nextEntries, parentSp)
		self._lastState = state
		self:_showDialog(state)
	end
end

--- Advance to next node when in 1:1 flow (playback finished). Queues next line and adds its subtitle to the dialog. When no entries (end of path), show main menu instead.
function IAConversation:advanceNext()
	self.pendingAutoAdvance = false
	if self.currentId == nil then
		return
	end
	local idNum = tonumber(self.currentId)
	local entries = self:getEntriesByPreviousId(idNum)
	if entries == nil or #entries == 0 then
		self:showMainMenu()
		return
	end
	local parentEntry = self:getEntryById(tostring(self.currentId)) or self:getEntryById(self.currentId)
	local parentSp = parentEntry ~= nil and parentEntry.speaker or nil
	local state = self:_buildStateFromEntries(entries, parentSp)
	self._lastState = state
	self:_showDialog(state)
end

--- Show main menu (smalltalks + Goodbye) using pre-loaded mainMenuOptions. Called when conversation path ends.
function IAConversation:showMainMenu()
	local options = self.mainMenuOptions
	if options == nil or #options == 0 then
		local state = { messages = {}, currentId = nil, nextOptions = nil, isChoicePoint = false }
		self._lastState = state
		self:_showDialog(state)
		return
	end
	self._mainMenuOptions = options
	local state = {
		messages = {},
		currentId = nil,
		nextOptions = options,
		isChoicePoint = true
	}
	self._lastState = state
	self:_showDialog(state)
end

--- Process one voice line: set speaker name, subtitle, then play sound. Single path for all voice playback.
-- @param item table { path, effect, speaker, text, logicalEntryId?, isLastSegment? } from playback queue
function IAConversation:_playCurrentLine(item)
	if item == nil or item.path == nil then
		return
	end
	self._activePlaybackQueueItem = item
	self:setCurrentSpeakerAndSubtitle(item.speaker, item.text)
	self:playVoice(item.path, item.effect, item.speaker)
end

--- Play a voice sample from mod-relative path. 3D: from NPC node when speaker is NPC, from player position when speaker is player.
-- During phone calls the player line is forced to 2D (direct, non-positional): the third-person camera
-- sits behind/above the player so a 3D source at the player position would be attenuated by distance and
-- could even become inaudible. NPC phone lines stay 2D as well via the band-limited "phone" effect path
-- (no real-world emitter for the remote speaker).
-- @param relativePath string Mod-relative path, e.g. "conversations/27/001_greeting.wav"
-- @param effectPreset string|nil Optional effect, e.g. "phone" for band-limited phone sound
-- @param speaker string|nil "player" or "npc" (or nil) to choose 3D source; nil treated as npc
function IAConversation:playVoice(relativePath, effectPreset, speaker)
	local function holdBeforeNextBecauseNoVoice()
		self.advanceDelay = math.max(self.advanceDelay or 0, IAConversation.VOICE_MISSING_HOLD_MILLISECONDS)
	end
	if IANeighbours.dir == nil or relativePath == nil or relativePath == "" then
		holdBeforeNextBecauseNoVoice()
		return
	end
	if self.currentSample ~= nil then
		deleteVoiceSample(self.currentSample)
		self.currentSample = nil
	end
	-- No valid voice pack (version XML): do not touch the audio engine; hold for subtitle read time only.
	if IANeighbours.voicePackLoaded ~= true then
		holdBeforeNextBecauseNoVoice()
		return
	end
	local isPhoneCall = self.isStandalonePhoneCall == true or (effectPreset ~= nil and string.lower(tostring(effectPreset)) == "phone")
	if isPhoneCall then
		self.isPhoneCallConversation = true
	end
	local sourceNode = nil
	if speaker == "player" then
		-- Phone call: keep the player's own voice 2D so the third-person camera distance does not attenuate it.
		if not isPhoneCall then
			sourceNode = "player"
		end
	else
		local nb = self.situation ~= nil and self.situation.neighbour or nil
		local wnode = nb ~= nil and nb.getCharacterWorldNode ~= nil and nb:getCharacterWorldNode() or nil
		if wnode ~= nil then
			sourceNode = wnode
		end
	end
	-- Voice audio is expected under the mod's settings directory (persistent + writable):
	-- <modSettings>/FS25_FIELDS_OF_STORIES/conversations/x/y/z/file.ogg
	if IANeighbours.xmlHelper == nil or IANeighbours.xmlHelper.getModSettingsDirectory == nil then
		holdBeforeNextBecauseNoVoice()
		return
	end
	local baseDir = IANeighbours.xmlHelper:getModSettingsDirectory()
	if baseDir == nil or baseDir == "" then
		holdBeforeNextBecauseNoVoice()
		return
	end
	local handle = createAndPlayVoiceSample(baseDir, relativePath, sourceNode, effectPreset)
	if handle ~= nil and (type(handle) ~= "number" or handle ~= 0) then
		self.currentSample = handle
		return
	end
	holdBeforeNextBecauseNoVoice()
end

--- Called when user clicks to continue (e.g. left click on dialog). Stops current voice playback and advances to next line only when not at option menu.
function IAConversation:requestAdvanceToNextLine()
	if self.isChoicePoint then
		return
	end
	if self.currentSample ~= nil then
		deleteVoiceSample(self.currentSample)
		self.currentSample = nil
	end
	local logicalId = self._activePlaybackQueueItem ~= nil and self._activePlaybackQueueItem.logicalEntryId or nil
	if logicalId ~= nil then
		self:_flushPlaybackQueueForLogicalEntryId(logicalId)
		self:_invokeEntryPlaybackEndCallback(tostring(logicalId))
	end
	self._activePlaybackQueueItem = nil
	self.advanceDelay = 0
	self.pendingAutoAdvance = true
end

--- Call once per frame: sample cleanup, short pause between voice lines, then advance / play next or show selection.
function IAConversation:update(dt)
	if self.uiSample ~= nil and not isSamplePlaying(self.uiSample) then
		if IAConversation.DEBUG_UI_SOUND then
			print("--- IAConversation:update() - uiSample finished, deleting: " .. tostring(self.uiSample))
		end
		delete(self.uiSample)
		self.uiSample = nil
	end
	if self.currentSample ~= nil and not isVoiceSamplePlaying(self.currentSample) then
		deleteVoiceSample(self.currentSample)
		self.currentSample = nil
		-- Pause before the next voice clip so lines do not run together.
		-- Skip the pause between segments of the same logical entry (multi-segment dynamic conversation lines)
		-- so the segments play back-to-back without an audible gap.
		local justFinished = self._activePlaybackQueueItem
		local wasIntermediateSegment = justFinished ~= nil and justFinished.isLastSegment == false
		if not wasIntermediateSegment then
			self.advanceDelay = math.max(IAConversation.VOICE_LINE_GAP_MILLISECONDS, self.advanceDelay)
		end
	end
	if self.advanceDelay > 0 then
		self.advanceDelay = self.advanceDelay - dt
		if self.advanceDelay <= 0 then
			self.advanceDelay = 0
			self.pendingAutoAdvance = true
		end
	end
	-- Drain multi-segment queue before advancing the conversation graph (pendingAutoAdvance + non-empty queue).
	if self.pendingAutoAdvance then
		local q = self.playbackQueue
		if q ~= nil and #q > 0 and self.currentSample == nil then
			self.pendingAutoAdvance = false
		else
			local meta = self._activePlaybackQueueItem
			if meta ~= nil and meta.isLastSegment == true and meta.logicalEntryId ~= nil then
				self:_invokeEntryPlaybackEndCallback(tostring(meta.logicalEntryId))
			end
			self._activePlaybackQueueItem = nil
			self:advanceNext()
		end
	end
	if self.currentSample == nil and self.playbackQueue and #self.playbackQueue > 0 and self.advanceDelay <= 0 then
		self:_playNextInQueue()
	end
end

--- Called when the GUI was closed by the engine (e.g. ESC) so the dialog is already gone: stop audio, restore cursor, clear refs. Do not call closeDialog.
function IAConversation:onExternalDialogClose()
	if IAConversation.DEBUG_DIALOG_ON_CLOSE then
		local hasBinding = g_inputBinding ~= nil
		local canGet = hasBinding and g_inputBinding.getShowMouseCursor ~= nil
		local canSet = hasBinding and g_inputBinding.setShowMouseCursor ~= nil
		print(string.format(
			"--- IAConversation:onExternalDialogClose() cursorBefore=%s hasInputBinding=%s getCursor=%s setCursor=%s situation=%s",
			tostring(self._cursorVisibleBeforeDialog),
			tostring(hasBinding),
			tostring(canGet),
			tostring(canSet),
			tostring(self.situation ~= nil)
		))
	end
	if self.currentSample ~= nil then
		deleteVoiceSample(self.currentSample)
		self.currentSample = nil
	end
	self.playbackQueue = {}
	self._activePlaybackQueueItem = nil
	self.currentId = nil
	self.nextOptions = nil
	self.isChoicePoint = false
	self.pendingAutoAdvance = false
	self.advanceDelay = 0
	self.dialogController = nil
	self.npcName = "Neighbour"
	self._lastState = nil
	self._mainMenuOptions = nil
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	--print("--- IAConversation:onExternalDialogClose() - _cursorVisibleBeforeDialog=" .. tostring(self._cursorVisibleBeforeDialog))
	IAConversation._hideMouseCursorAfterConversation()
	if IAConversation.DEBUG_DIALOG_ON_CLOSE then
		print("--- IAConversation:onExternalDialogClose() setShowMouseCursor(false) (after conversation)")
	end
	self._cursorVisibleBeforeDialog = nil
	self.dialog = nil
	local wasStandalonePhone = self.isStandalonePhoneCall == true
	local wasPhoneCall = wasStandalonePhone or self.isPhoneCallConversation == true
	self.isStandalonePhoneCall = false
	self.isPhoneCallConversation = false
	if wasStandalonePhone then
		self:stopPhoneBackgroundSound()
	end
	-- Force-closing a phone call (e.g. ESC): the speaking voice was already stopped above; play the hang-up sound.
	if wasPhoneCall then
		self:playUiSound("sound/hang_up.ogg")
	end
	if self.situation ~= nil then
		self.situation.activeDialog = nil
		self.situation.dialogController = nil
		self.situation.conversationCurrentId = 0
		self.situation.conversationNextOptions = nil
		self.situation = nil
	end
	if wasStandalonePhone and IANeighbours ~= nil and type(IANeighbours.onStandalonePhoneConversationClosed) == "function" then
		IANeighbours.onStandalonePhoneConversationClosed(self)
	end
end

--- Stop and release current voice sample; close dialog; clear playback queue, choice state, and references.
-- @param resumeFieldworkAfterGoodbye boolean|nil if true, fieldwork resumes (only for explicit Goodbye); ESC/menu close uses onExternalDialogClose and must not pass this.
function IAConversation:stop(resumeFieldworkAfterGoodbye)
	local wasStandalonePhone = self.isStandalonePhoneCall == true
	local wasPhoneCall = wasStandalonePhone or self.isPhoneCallConversation == true
	self.isStandalonePhoneCall = false
	self.isPhoneCallConversation = false
	if wasStandalonePhone then
		self:stopPhoneBackgroundSound()
	end
	-- Do NOT delete uiSample here: goodbye triggers stop() immediately after starting the sound.
	-- Let update() delete it once playback has finished.
	-- Stop the speaking character/player voice before playing the hang-up sound.
	if self.currentSample ~= nil then
		deleteVoiceSample(self.currentSample)
		self.currentSample = nil
	end
	if wasPhoneCall then
		self:playUiSound("sound/hang_up.ogg")
	end
	self.playbackQueue = {}
	self._activePlaybackQueueItem = nil
	self.currentId = nil
	self.nextOptions = nil
	self.isChoicePoint = false
	self.pendingAutoAdvance = false
	self.advanceDelay = 0
	self.dialogController = nil
	self.npcName = "Neighbour"
	self._lastState = nil
	self._mainMenuOptions = nil
	self.entryPlaybackEndCallbacks = nil
	self.entrySelectImmediateCallbacks = nil
	if self.situation ~= nil then
		self.situation.activeDialog = nil
		self.situation.dialogController = nil
		local sit = self.situation
		self.situation = nil
		if resumeFieldworkAfterGoodbye == true and sit.resumeFieldworkAfterConversation ~= nil then
			sit:resumeFieldworkAfterConversation()
		end
	end
	self:_hideDialog()
	if wasStandalonePhone and IANeighbours ~= nil and type(IANeighbours.onStandalonePhoneConversationClosed) == "function" then
		IANeighbours.onStandalonePhoneConversationClosed(self)
	end
end
