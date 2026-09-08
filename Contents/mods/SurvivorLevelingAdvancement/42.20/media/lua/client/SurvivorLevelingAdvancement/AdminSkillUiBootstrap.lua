require "ISUI/PlayerStats/ISPlayerStatsUI"

local key = "__SLA_AdminSkillUi_42_20_v1"
local signature = "sla.admin-skill-ui/42.20/v1"
local existing = rawget(_G, key)
if existing ~= nil then
    if type(existing) ~= "table" or getmetatable(existing) ~= nil
        or existing.signature ~= signature or type(existing.integration) ~= "table"
        or type(existing.integration.install) ~= "function"
        or type(existing.integration.status) ~= "function" then
        return { ok = false, code = "admin_skill_ui_sentinel_collision" }
    end
    local installed = existing.integration.install()
    return installed.ok and existing.integration or installed
end

local created = require("SurvivorLevelingAdvancement/UI/Build42AdminSkillUi").create({
    PlayerStats = ISPlayerStatsUI,
    owner = require "SurvivorLevelingAdvancement/Bootstrap",
    getSpecificPlayer = function(slot) return getSpecificPlayer(slot) end,
    isClient = function() return isClient() end,
    report = function(code) print("SLA Player Stats: " .. tostring(code)) end,
})
if not created.ok then return created end
local installed = created.integration.install()
if not installed.ok then return installed end
rawset(_G, key, { signature = signature, integration = created.integration })
return created.integration
