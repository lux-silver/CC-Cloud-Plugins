-- Settings Plugin v3
-- Menu plugin: opens configAPI settings screen
-- Just a menu entry — theme and other configs are handled by their own plugins

local plugin    = {}
plugin.name     = "settings"
plugin.label    = "Settings"
plugin.patch    = false
plugin.priority = 10

function plugin.run()
    if not configAPI then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setTextColor(colors.red)
        term.write(" config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write(" Add plugins/config_api.lua first.")
        term.setCursorPos(1,6) term.write(" Press any key...")
        os.pullEvent("key")
        return
    end
    configAPI.settingsScreen()
end

return plugin

-- @installed:1781121142