-- ConstructionFoSGUI.lua
-- Fields of Stories construction menu extension
-- Adds a "Fields of Stories" category with tool placeables to the FS25 construction screen.

ConstructionFoSGUI = {}

-- Category name constant — must match the name passed to g_storeManager:addConstructionCategory()
ConstructionFoSGUI.CATEGORY_NAME = "fieldsOfStories"

-- Set by IAMapInitDialogGUI before opening the construction screen from Shift+F3;
-- cleared after auto-selecting the FoS category on the next rebuildData.
ConstructionFoSGUI._pendingAutoSelect = false

-- Prefixes (lowercase) that identify FoS tool placeable store items (tab 1)
ConstructionFoSGUI.FOS_PLACEABLE_PATH_PREFIXES = {
    "placeables/place_character/",
}

-- Prefix for character homebase placeables (tab 2 — grouped by character)
ConstructionFoSGUI.FOS_CHARACTER_HOMEBASE_PATH_PREFIX = "placeables/character_homebase/"

--------------------------------------------------------------------------------
-- Store item collection
--------------------------------------------------------------------------------

--- Collect Fields of Stories store items from the ConstructionScreen's item grid.
--- Walks self.items (all categories × tabs), matching storeItem.xmlFilename against
--- FOS_PLACEABLE_PATH_PREFIXES. Deduplicates by lowercased xmlFilename.
--- Clones each matching item so it can be placed into our custom category tab.
--- @param screenSelf ConstructionScreen instance
--- @return table[] items array of cloned item entries (each has .storeItem etc.)
function ConstructionFoSGUI.collectFoSStoreItems(screenSelf)
    local items = {}
    local seenXml = {}

    if screenSelf == nil or screenSelf.items == nil then
        return items
    end

    -- Walk all categories and their tabs, skipping our own FoS category
    local fosCat = ConstructionFoSGUI.getFoSCategory()
    for categoryIndex, tabs in ipairs(screenSelf.items) do
        -- Skip our own category so we don't double-collect
        if fosCat == nil or categoryIndex ~= fosCat.index then
            if tabs ~= nil then
                for _, tabItems in ipairs(tabs) do
                    if tabItems ~= nil then
                        for _, item in ipairs(tabItems) do
                            if item ~= nil and item.storeItem ~= nil and item.storeItem.xmlFilename ~= nil then
                                local path = string.lower(tostring(item.storeItem.xmlFilename))
                                local isFoS = false
                                local fosTab = 1
                                for _, prefix in ipairs(ConstructionFoSGUI.FOS_PLACEABLE_PATH_PREFIXES) do
                                    if string.find(path, prefix, 1, true) ~= nil then
                                        isFoS = true
                                        fosTab = 1
                                        break
                                    end
                                end
                                if not isFoS then
                                    local chPrefix = ConstructionFoSGUI.FOS_CHARACTER_HOMEBASE_PATH_PREFIX
                                    if chPrefix ~= nil and string.find(path, chPrefix, 1, true) ~= nil then
                                        isFoS = true
                                        fosTab = 2
                                    end
                                end
                                if isFoS and not seenXml[path] then
                                    seenXml[path] = true
                                    -- Shallow-clone the item so it can live in our custom tab
                                    local clone = {}
                                    for k, v in pairs(item) do
                                        clone[k] = v
                                    end
                                    clone.uniqueIndex = #items + 1
                                    clone.fosTab = fosTab
                                    table.insert(items, clone)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return items
end

--------------------------------------------------------------------------------
-- Category registration (delegated to g_storeManager)
--------------------------------------------------------------------------------

--- Register the Fields of Stories construction category and its tabs.
--- Called from ConstructionScreen.rebuildData appended hook. Idempotent — does nothing
--- if the category already exists.
--- @return table|nil category
function ConstructionFoSGUI.registerFoSCategory()
    local category = ConstructionFoSGUI.getFoSCategory()

    if category == nil then
        local title = (g_i18n ~= nil and g_i18n:getText("construction_foS_category")) or "Fields of Stories"
        g_storeManager:addConstructionCategory(
            ConstructionFoSGUI.CATEGORY_NAME,   -- unique name
            title,                               -- display title
            nil, nil,                            -- icon filename / UVs
            "",                                  -- icon slice id (empty = no icon from item, category icon uses registered atlas below)
            "iaConstructionFoS.icon_category"    -- category icon slice ID (from textures/iaConstructionFoS.xml)
        )
        category = ConstructionFoSGUI.getFoSCategory()
    end

    if category == nil then
        return nil
    end

    -- Two tabs: General Places (tab 1), Character Home (tab 2)
    local tab1Title = (g_i18n ~= nil and g_i18n:getText("construction_foS_tab_placeables")) or "General Places"
    local tab2Title = (g_i18n ~= nil and g_i18n:getText("construction_foS_tab_character_homebase")) or "Character Home"
    category.tabs = {
        {
            name = "FOS_PLACEABLES",
            title = tab1Title,
            iconFilename = nil,
            iconUVs = nil,
            iconSliceId = nil,
            index = 1,
        },
        {
            name = "FOS_CHARACTER_HOMEBASE",
            title = tab2Title,
            iconFilename = nil,
            iconUVs = nil,
            iconSliceId = nil,
            index = 2,
        }
    }

    return category
end

--- Get the FoS construction category from g_storeManager.
--- @return table|nil category
function ConstructionFoSGUI.getFoSCategory()
    if g_storeManager == nil or g_storeManager.getConstructionCategoryByName == nil then
        return nil
    end
    return g_storeManager:getConstructionCategoryByName(ConstructionFoSGUI.CATEGORY_NAME)
end

--- Check if the given category index is the FoS category.
--- @param categoryIndex integer|nil
--- @return boolean
function ConstructionFoSGUI.isFoSCategory(categoryIndex)
    local cat = ConstructionFoSGUI.getFoSCategory()
    return cat ~= nil and categoryIndex == cat.index
end

--- Refresh the items shown inside the FoS category.
--- Populates self.items[cat.index][1] with collected FoS store items.
--- @param self ConstructionScreen instance
function ConstructionFoSGUI.refreshFoSItems(self)
    local cat = ConstructionFoSGUI.getFoSCategory()
    if cat == nil then
        return
    end

    if self.items == nil then
        self.items = {}
    end

    self.items[cat.index] = {}
    local allItems = ConstructionFoSGUI.collectFoSStoreItems(self)
    -- Tab 1: Tool Placeables (fosTab == 1 or no tag)
    local tab1 = {}
    -- Tab 2: Character Homebase (fosTab == 2)
    local tab2 = {}
    local removeItem = nil

    for _, item in ipairs(allItems) do
        if item.fosTab == 2 then
            table.insert(tab2, item)
        else
            -- Check if this is the "remove place" tool
            if removeItem == nil and item.storeItem ~= nil and item.storeItem.xmlFilename ~= nil then
                local path = string.lower(tostring(item.storeItem.xmlFilename))
                if string.find(path, "place_character_remove", 1, true) ~= nil then
                    removeItem = item
                else
                    table.insert(tab1, item)
                end
            else
                table.insert(tab1, item)
            end
        end
    end

    -- Move the "remove place" tool to the front of tab1
    if removeItem ~= nil then
        table.insert(tab1, 1, removeItem)
    end

    -- Also add the "remove place" tool to tab2 (Character Home / Homebase),
    -- so it is accessible from both tabs
    if removeItem ~= nil then
        local removeClone = {}
        for k, v in pairs(removeItem) do
            removeClone[k] = v
        end
        removeClone.fosTab = 2
        table.insert(tab2, 1, removeClone)
    end

    self.items[cat.index][1] = tab1
    self.items[cat.index][2] = tab2
end

--------------------------------------------------------------------------------
-- Hooks (installed once from IANeighbours.loadMap)
--------------------------------------------------------------------------------

--- After vanilla rebuildData: register our category and populate items.
local function _rebuildDataAppended(self)
    ConstructionFoSGUI.registerFoSCategory()
    self.categories = g_storeManager:getConstructionCategories()
    ConstructionFoSGUI.refreshFoSItems(self)
    self.categorySelector:reloadData()

    -- Auto-select FoS category if requested (from Shift+F3 "Open Construction Menu")
    if ConstructionFoSGUI._pendingAutoSelect then
        ConstructionFoSGUI._pendingAutoSelect = false
        local fosCat = ConstructionFoSGUI.getFoSCategory()
        if fosCat ~= nil and self.setCurrentCategory ~= nil then
            self:setCurrentCategory(fosCat.index)
        end
    end
end

--- When switching to the FoS category, ensure tab state defaults to 1.
local function _setCurrentCategoryAppended(self, categoryIndex, ...)
    if ConstructionFoSGUI.isFoSCategory(categoryIndex) then
        self.currentTab = 1
    end
end

--- Install hooks on ConstructionScreen. Safe to call multiple times (idempotent —
--- Utils.appendedFunction only appends once per unique function reference).
function ConstructionFoSGUI.installHooks()
    if ConstructionFoSGUI._hooksInstalled then
        return
    end
    if ConstructionScreen == nil then
        print("[ConstructionFoSGUI] WARNING: ConstructionScreen not available — hooks not installed")
        return
    end

    -- Rebuild data: register category + populate items after vanilla
    ConstructionScreen.rebuildData = Utils.appendedFunction(
        ConstructionScreen.rebuildData, _rebuildDataAppended)

    -- Category switch: ensure tab defaults to 1 for our category
    ConstructionScreen.setCurrentCategory = Utils.appendedFunction(
        ConstructionScreen.setCurrentCategory, _setCurrentCategoryAppended)

    ConstructionFoSGUI._hooksInstalled = true
    IAprintDebug("ConstructionFoSGUI", "Hooks installed on ConstructionScreen")
end
