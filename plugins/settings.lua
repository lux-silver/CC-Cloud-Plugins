-- Settings Plugin v2
-- Menu plugin: opens configAPI settings screen
-- Built-in settings: header color + nickname

local plugin   = {}
plugin.name    = "settings"
plugin.label   = "Settings"
plugin.patch   = false
plugin.priority = 10

-- ── Theme color patch ─────────────────────────────────────────────────────────
-- Replaces colors.blue with chosen color in ALL term calls during clickMenu
local _patched = false

local function applyThemeColor(c)
    -- c is a number (CC color value)
    -- store it so the patch below uses it
    _G.cloudThemeColor = c

    if _patched then return end
    _patched = true

    local origSetBg = term.setBackgroundColor
    term.setBackgroundColor = function(col)
        if col == colors.blue and _G.cloudThemeColor then
            origSetBg(_G.cloudThemeColor)
        else
            origSetBg(col)
        end
    end
end

-- ── Register built-ins once configAPI is available ───────────────────────────
local _registered = false
local function tryRegister()
    if _registered or not configAPI then return end
    _registered = true

    configAPI.register({
        plugin   = "Cloud Theme",
        key      = "theme.headerColor",
        label    = "Header Color",
        type     = "color",
        default  = colors.blue,
        onChange = function(v)
            -- v comes as number from parseVal — that's correct for colors.*
            applyThemeColor(v)
        end,
    })

    configAPI.register({
        plugin   = "Cloud Theme",
        key      = "theme.nickname",
        label    = "Nickname",
        type     = "text",
        default  = "",
        onChange = function(v)
            _G.cloudDisplayName = (v and v ~= "") and v or nil
        end,
    })
end

-- ── plugin.run ────────────────────────────────────────────────────────────────
function plugin.run()
    tryRegister()

    if not configAPI then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red) term.write(" config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write(" Add plugins/config_api.lua first.")
        term.setCursorPos(1,6) term.write(" Press any key...")
        os.pullEvent("key")
        return
    end

    configAPI.settingsScreen()
end

return plugin
