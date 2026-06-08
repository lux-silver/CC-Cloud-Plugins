-- Settings Plugin v1
-- Menu plugin: opens settings screen with all registered configs
-- Also registers built-in settings: theme color + log nickname
-- Place at: plugins/settings.lua

local plugin  = {}
plugin.name   = "settings"
plugin.label  = "Settings"
plugin.patch  = false  -- appears as menu entry

-- ── Built-in: theme color ─────────────────────────────────────────────────────
-- Patches clickMenu to use the chosen header color

local function applyTheme(c)
    if not clickMenu then return end
    local orig = _G._origClickMenu or clickMenu
    _G._origClickMenu = orig
    clickMenu = function(title, items, msg)
        -- wrap: swap header color before drawing
        -- We patch term.setBackgroundColor calls during clickMenu
        -- Simpler: just re-set after the fact is not possible from outside.
        -- Instead we store the color and patch drawPanel / header inline.
        -- Since clickMenu is native to cloud_user, we expose a global
        -- that cloud_user's clickMenu checks.
        _G.cloudThemeColor = c
        return orig(title, items, msg)
    end
end

-- Patch: intercept clickMenu header draw to use cloudThemeColor
-- We override term.setBackgroundColor only during clickMenu calls.
-- Cleanest approach: monkey-patch clickMenu to swap colors.blue→cloudThemeColor.
local function patchClickMenuColor()
    if not clickMenu then return end
    local orig = clickMenu
    _G._origClickMenu = orig
    clickMenu = function(title, items, msg)
        -- temporarily redirect colors.blue draws to theme color
        local themeC = _G.cloudThemeColor or colors.blue
        if themeC == colors.blue then return orig(title, items, msg) end

        local origSetBg = term.setBackgroundColor
        term.setBackgroundColor = function(c)
            if c == colors.blue then origSetBg(themeC)
            else origSetBg(c) end
        end
        local result = orig(title, items, msg)
        term.setBackgroundColor = origSetBg
        return result
    end
end

-- ── Built-in: log nickname ────────────────────────────────────────────────────
local function applyNickname(nick)
    _G.cloudNickname = (nick and nick ~= "") and nick or nil
end

-- ── Plugin run ────────────────────────────────────────────────────────────────
function plugin.run()
    if not configAPI then
        -- configAPI not loaded (config_api.lua missing)
        local W,H = term.getSize()
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,3) term.setTextColor(colors.red)
        term.write("config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write("Add plugins/config_api.lua")
        os.pullEvent("key")
        return
    end

    configAPI.settingsScreen()
end

-- ── Self-register built-in settings (runs at load time) ──────────────────────
-- These register when the plugin file is loaded, before plugin.run() is called.
-- We use a small trick: check configAPI in a deferred way since other
-- patch plugins may run after us. We register in plugin.run() instead,
-- but only once.

local registered = false
local _origRun = plugin.run
plugin.run = function()
    if not registered and configAPI then
        registered = true

        -- Theme color
        configAPI.register({
            plugin   = "Cloud Theme",
            key      = "theme.headerColor",
            label    = "Header Color",
            type     = "color",
            default  = colors.blue,
            onChange = function(v)
                _G.cloudThemeColor = v
                patchClickMenuColor()
            end,
        })

        -- Log nickname
        configAPI.register({
            plugin   = "Cloud Theme",
            key      = "theme.nickname",
            label    = "Log Nickname",
            type     = "text",
            default  = "",
            onChange = function(v)
                applyNickname(v)
                -- patch username display if possible
                if v and v ~= "" then
                    _G.cloudDisplayName = v
                else
                    _G.cloudDisplayName = nil
                end
            end,
        })
    end
    _origRun()
end

return plugin
