-- Theme Plugin v1
-- patch plugin: applies header color and nickname from config
-- priority 3: runs after config_api (1) and autologin (2)

local plugin    = {}
plugin.name     = "theme"
plugin.label    = "theme"
plugin.patch    = true
plugin.priority = 3

function plugin.run()
    if not configAPI then return end

    -- patch term.setBackgroundColor once so colors.blue → theme color everywhere
    local _origSetBg = term.setBackgroundColor
    local function applyPatch()
        local c = configAPI.get("theme.headerColor")
        if not c or c == colors.blue then
            term.setBackgroundColor = _origSetBg
            return
        end
        term.setBackgroundColor = function(col)
            _origSetBg(col == colors.blue and c or col)
        end
    end

    configAPI.register({
        plugin   = "Theme",
        key      = "theme.headerColor",
        label    = "Header Color",
        type     = "color",
        default  = colors.blue,
        onChange = function(v)
            _G.cloudThemeColor = v
            applyPatch()
        end,
    })

    configAPI.register({
        plugin   = "Theme",
        key      = "theme.nickname",
        label    = "Nickname",
        type     = "text",
        default  = "",
        onChange = function(v)
            _G.cloudDisplayName = (v and v ~= "") and v or nil
        end,
    })

    applyPatch()
end

return plugin
