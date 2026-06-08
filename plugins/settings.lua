-- Settings Plugin v1
-- Menu plugin: opens settings screen with all registered configs
-- Also registers built-in settings: theme color + log nickname
-- Place at: plugins/settings.lua

local plugin  = {}
plugin.name   = "settings"
plugin.label  = "Settings"
plugin.patch  = false  -- aparece na lista do menu principal

-- ── Built-in: theme color ─────────────────────────────────────────────────────
local function patchClickMenuColor()
    -- Se o clickMenu ainda não existir na memória global, sai sem dar erro!
    if not _G.clickMenu and not clickMenu then return end
    
    local orig = _G.clickMenu or clickMenu
    if _G._origClickMenu then return end -- evita aplicar o patch por cima de si mesmo
    
    _G._origClickMenu = orig
    _G.clickMenu = function(title, items, msg)
        return orig(title, items, msg)
    end
end

-- ── Main Screen ───────────────────────────────────────────────────────────────
function plugin.run()
    -- Aplica o patch apenas na hora que o plugin é aberto de verdade
    patchClickMenuColor()

    local api = _G.configAPI or configAPI
    if not api then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setTextColor(colors.red)
        term.write("config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write("Add plugins/config_api.lua")
        os.pullEvent("key")
        return
    end

    api.settingsScreen()
end

-- ── Self-register built-in settings (runs at load time) ──────────────────────
local registered = false
local _origRun = plugin.run

plugin.run = function()
    local api = _G.configAPI or configAPI
    if not registered and api then
        registered = true

        -- Theme color
        api.register({
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
        api.register({
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
