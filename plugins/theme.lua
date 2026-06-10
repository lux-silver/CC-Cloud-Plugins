-- Theme Plugin v1
-- patch plugin: applies header color and nickname globally
-- priority 3: runs after config_api (1) and autologin (2)

local plugin    = {}
plugin.name     = "theme"
plugin.label    = "theme"
plugin.patch    = true
plugin.priority = 3

function plugin.run()
    if not configAPI then return end

    -- patch term.setBackgroundColor ONCE so every colors.blue call
    -- anywhere (cloud_user, plugins, settings) uses the theme color
    local _origSetBg = term.setBackgroundColor
    local _patched   = false

    local function applyPatch(c)
        if c == colors.blue then
            -- no patch needed, restore original
            if _patched then
                term.setBackgroundColor = _origSetBg
                _patched = false
            end
            return
        end
        if not _patched then
            term.setBackgroundColor = function(col)
                _origSetBg(col == colors.blue and c or col)
            end
            _patched = true
        else
            -- update the closure color by re-patching
            term.setBackgroundColor = function(col)
                _origSetBg(col == colors.blue and c or col)
            end
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
            applyPatch(v)
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
end

return plugin
