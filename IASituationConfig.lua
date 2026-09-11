--
-- FS25 - InteractiveNeighbours - Situation Config
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo
-- @Date: 25.10.2022
-- @Version: 1.0.0.1
-- Configuration class for situations loaded from XML

IASituationConfig = {}
IASituationConfig._mt = Class(IASituationConfig)

-- Create a new IASituationConfig instance
-- @param table data - Table containing all situation configuration data from XML
function IASituationConfig.new(data)
	local self = setmetatable({}, IASituationConfig._mt)
	
	-- Store all data from XML
	self.id = data.id
	self.type = data.type
	self.intent = data.intent
	self.occurrence = data.occurrence
	self.trigger = data.trigger
	self.createdAt = data.createdAt
	self.updatedAt = data.updatedAt
	self.minFrequency = data.minFrequency
	self.vehicles = data.vehicles
	self.ignorePlayerDistance = data.ignorePlayerDistance
	self.daytime = data.daytime
	self.maxDuration = data.maxDuration
	self.characterVisibility = data.characterVisibility
	self.fieldwork = data.fieldwork
	-- Optional overrides for ia_field_outcome phone missions (situations XML fieldStateOutcome); base targets come from IAFieldwork.getExpectedFieldStateAfterJob (fertilize sprayType from attachmentCategories).
	self.fieldStateOutcome = data.fieldStateOutcome or {}
	-- seedFruitTypeIndex is a single value (string or number), NOT an array
	self.seedFruitTypeIndex = data.seedFruitTypeIndex
	-- Arrays from XML
	self.triggerFruitTypeIndex = data.triggerFruitTypeIndex or {}
	self.triggerGrowthState = data.triggerGrowthState or {}
	self.triggerWeedState = data.triggerWeedState or {}
	self.triggerSprayLevel = data.triggerSprayLevel or {}
	self.triggerStoneLevel = data.triggerStoneLevel or {}
	self.triggerLimeLevel = data.triggerLimeLevel or {}
	self.placetypes = data.placetypes or {}
	-- Optional list of allowed place sizeType values for this situation.
	-- - Empty/absent: any place size is accepted EXCEPT exclusive sizes (currently "large_area"), which are opt-in only.
	-- - Non-empty: only places whose sizeType matches one of the listed values are eligible.
	self.placeSizes = data.placeSizes or {}
	self.vehicleTypes = data.vehicleTypes or {}
	self.attachmentCategories = data.attachmentCategories or {}
	self.attachmentFrontCategories = data.attachmentFrontCategories or {}
	self.season = data.season or {}
	self.triggerGroundType = data.triggerGroundType or {}
	self.characterRoles = data.characterRoles or {}
	self.characterJobs = data.characterJobs or {}
	self.months = data.months or {}
	
	return self
end
