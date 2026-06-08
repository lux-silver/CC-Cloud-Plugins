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
        _G.cloudThemeColor = c
        return orig(title, items, msg)
    end
end

-- Patch: intercept clickMenu header draw to use cloudThemeColor
local function patchClickMenuColor()
    -- CORREÇÃO: Se o clickMenu ainda não existir (tempo de boot), sai sem dar erro!
    if not clickMenu then return end
    
    -- Evita duplicar o proxy se já foi aplicado antes
    if _G._patchedClickMenu then return end
    _G._patchedClickMenu = true

    local orig = clickMenu
    _G._origClickMenu = orig
    clickMenu = function(title, items, msg)
        return orig(title, items, msg)
    end
end

-- ── Main Screen ───────────────────────────────────────────────────────────────
function plugin.run()
    -- Tenta aplicar o patch de cor agora que o utilizador abriu o menu e a sandbox está pronta
    patchClickMenuColor()

    if not configAPI then
        configAPI = _G.configAPI
    end

    if not configAPI then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setTextColor(colors.red)
        term.write("config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write("Add plugins/config_api.lua")
        os.pullEvent("key")
        return
    end

    configAPI.settingsScreen()
end

-- ── Self-register built-in settings (runs at load time) ──────────────────────
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
                -- Só chama o patch se o ambiente já estiver pronto
                if clickMenu then patchClickMenuColor() end
            end,
        })

        -- Log nickname
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
    _origRun()
end

return plugin
