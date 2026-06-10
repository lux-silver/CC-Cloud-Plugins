-- Theme Plugin v1
-- patch plugin: applies header color and nickname
-- priority 3: runs after config_api (1) and autologin (2)

local plugin    = {}
plugin.name     = "theme"
plugin.label    = "theme"
plugin.patch    = true
plugin.priority = 3

function plugin.run()
    if not configAPI then return end

    configAPI.register({
        plugin   = "Theme",
        key      = "theme.headerColor",
        label    = "Header Color",
        type     = "color",
        default  = colors.blue,
        onChange = function(v)
            -- store as global — config_api and cloud.lua read _G.cloudThemeColor
            _G.cloudThemeColor = (v ~= colors.blue) and v or nil
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
