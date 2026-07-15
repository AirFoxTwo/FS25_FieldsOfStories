--
-- IATestRegistry.lua — Auto-run test configuration for Fields of Stories
--
-- Reads the active test name from iaTestActive.xml (written by trigger_gamestart.ps1).
-- When no test is configured, auto-run is effectively disabled.
-- The XML file is excluded from the release build zip.
--
-- @Interface: 1.0.0.0
-- @Author: AirFoxTwo / Copilot
-- @Date: 30.06.2026

IATestRegistry = {
    -- Master switch: when false, no tests auto-run regardless of the XML file.
    enabled = true,
    verbose = false,            -- Enables extra debug logging throughout the auto-run system

    -- Delay in wall-clock seconds after outbound XML loads before auto-running
    -- tests. This gives neighbours, vehicles, and placables time to fully
    -- initialize so tests run against a stable world state.
    startDelaySeconds = 5,

    -- Loaded from iaTestActive.xml at mod init; nil when no test configured.
    -- Only one test runs at a time.
    _testName = nil,
}

-- ============================================================================
-- XML Loading
-- ============================================================================

--- Load the active test name from iaTestActive.xml.
--- Called once at source time (mod load). Gracefully handles missing/empty file.
function IATestRegistry.loadFromXML()
    local filePath = IANeighbours.dir .. "lib/testFramework/iaTestActive.xml"
    local xmlFile = loadXMLFile("IATestActive", filePath)

    if xmlFile == nil or xmlFile == 0 then
        if IATestRegistry.verbose then
            IAprintDebug("IATestRegistry", "iaTestActive.xml not found or failed to load — no test active")
        end
        IATestRegistry._testName = nil
        return
    end

    local testName = getXMLString(xmlFile, "iaTestActive.test#name")
    delete(xmlFile)

    if testName == nil or testName == "" then
        if IATestRegistry.verbose then
            IAprintDebug("IATestRegistry", "iaTestActive.xml loaded — no test name set (empty)")
        end
        IATestRegistry._testName = nil
        return
    end

    IATestRegistry._testName = testName
    if IATestRegistry.verbose then
        IAprintDebug("IATestRegistry", "loaded active test '" .. testName .. "' from iaTestActive.xml")
    end
end

-- Call on mod load
IATestRegistry.loadFromXML()

-- ============================================================================
-- Helpers
-- ============================================================================

--- Get the single active test name, or nil if none configured.
function IATestRegistry.getActiveTestName()
    return IATestRegistry._testName
end

--- Get a normalized list of test names from the registry (always 0 or 1 entry).
--- Maintains backward compatibility with code that expects an array.
function IATestRegistry.getActiveTestNames()
    local names = {}
    if IATestRegistry._testName ~= nil and IATestRegistry._testName ~= "" then
        table.insert(names, IATestRegistry._testName)
    end
    return names
end

--- Check whether a test is configured.
function IATestRegistry.hasActiveTests()
    return IATestRegistry._testName ~= nil and IATestRegistry._testName ~= ""
end

--- Get the active test name as a string (for display/logging).
function IATestRegistry.getActiveTestNameString()
    if IATestRegistry._testName ~= nil and IATestRegistry._testName ~= "" then
        return IATestRegistry._testName
    end
    return "(none)"
end

--- Log helper: dump the registry state to the console.
function IATestRegistry.logState()
    IAprintDebug("IATestRegistry", "enabled=" .. tostring(IATestRegistry.enabled) ..
        ", delay=" .. tostring(IATestRegistry.startDelaySeconds) .. "s" ..
        ", test=" .. IATestRegistry.getActiveTestNameString())
end
