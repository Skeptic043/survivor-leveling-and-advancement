local key = "__SLA_AdminSkillUi_42_20_v1"
local evidence = rawget(_G, "__C78_ADMIN_SKILL_BOOTSTRAP")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { checks = 0, phase = 1, creates = 0, installs = 0, requires = {}, reports = {} }
    rawset(_G, "__C78_ADMIN_SKILL_BOOTSTRAP", evidence)
    evidence.stats = {
        onOptionMouseDown = function() end,
        setVisible = function() end,
    }
    evidence.owner = {
        requestAdmin = function() return { ok = false, code = "unavailable" } end,
        adminStatus = function() return { ok = true, pending = false } end,
        setAdminResultListener = function() return { ok = true } end,
    }
    evidence.integration = {
        install = function() evidence.installs = evidence.installs + 1; return { ok = true } end,
        status = function() return { ok = true, installed = true } end,
    }
    evidence.module = {
        create = function(dependencies)
            evidence.creates = evidence.creates + 1
            evidence.dependencies = dependencies
            return { ok = true, integration = evidence.integration }
        end,
    }
    require = function(path)
        evidence.requires[path] = (evidence.requires[path] or 0) + 1
        if path == "ISUI/PlayerStats/ISPlayerStatsUI" then return true end
        if path == "SurvivorLevelingAdvancement/UI/Build42AdminSkillUi" then return evidence.module end
        if path == "SurvivorLevelingAdvancement/Bootstrap" then return evidence.owner end
        return nil
    end
    ISPlayerStatsUI = evidence.stats
    getSpecificPlayer = function(slot) return { slot = slot } end
    isClient = function() return true end
    print = function(message) evidence.reports[#evidence.reports + 1] = message end
    rawset(_G, key, nil)
elseif evidence.phase == 1 then
    check(evidence.creates == 1 and evidence.installs == 1, "first load creates and installs once")
    check(evidence.dependencies.PlayerStats == evidence.stats and evidence.dependencies.owner == evidence.owner,
        "bootstrap injects exact native and lifecycle owners")
    check(evidence.dependencies.getSpecificPlayer(2).slot == 2 and evidence.dependencies.isClient() == true,
        "bootstrap injects bounded engine functions")
    evidence.dependencies.report("example")
    check(evidence.reports[1] == "SLA Player Stats: example", "bootstrap reports with player stats prefix")
    check(rawget(_G, key).signature == "sla.admin-skill-ui/42.20/v1"
        and rawget(_G, key).integration == evidence.integration, "bootstrap stores exact sentinel")
    evidence.phase = 2
elseif evidence.phase == 2 then
    check(evidence.creates == 1 and evidence.installs == 2, "reload reuses sentinel integration")
    check(evidence.requires["ISUI/PlayerStats/ISPlayerStatsUI"] == 2
        and evidence.requires["SurvivorLevelingAdvancement/UI/Build42AdminSkillUi"] == 1
        and evidence.requires["SurvivorLevelingAdvancement/Bootstrap"] == 1, "reload only requires native player stats")
    rawset(_G, key, { signature = "other", integration = evidence.integration })
    evidence.phase = 3
elseif evidence.phase == 3 then
    check(rawget(_G, "C78AdminSkillBootstrapCollision").code == "admin_skill_ui_sentinel_collision",
        "invalid sentinel fails closed")
end

return evidence.checks
