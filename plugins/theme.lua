-- Theme Plugin v2
-- patch plugin: changes the header color palette and nickname
-- Uses term.setPaletteColor to redefine colors.orange globally
-- priority 3: runs after config_api (1) and autologin (2)

local plugin    = {}
plugin.name     = "theme"
plugin.label    = "theme"
plugin.patch    = true
plugin.priority = 3

-- Palette hex values matching CC color constants
local COLOR_HEX = {
    [colors.blue]      = 0x3366CC,
    [colors.red]       = 0xCC4444,
    [colors.green]     = 0x57A64E,
    [colors.purple]    = 0xB357BD,
    [colors.cyan]      = 0x4AC8AC,
    [colors.orange]    = 0xCC6600,
    [colors.magenta]   = 0xE57FD8,
    [colors.gray]      = 0x4C4C4C,
    [colors.lightBlue] = 0x7099D4,
    [colors.yellow]    = 0xDEDE6C,
    [colors.lime]      = 0x7FCC19,
    [colors.brown]     = 0x7F664C,
}

local DEFAULT_ORANGE_HEX = 0xCC6600

local function applyColor(c)
    local hex = COLOR_HEX[c] or DEFAULT_ORANGE_HEX
    -- redefine colors.orange palette to match chosen color
    pcall(term.setPaletteColor, colors.orange, hex)
end

function plugin.run()
    if not configAPI then return end

    configAPI.register({
        plugin   = "Theme",
        key      = "theme.headerColor",
        label    = "Header Color",
        type     = "color",
        default  = colors.orange,
        onChange = function(v)
            _G.cloudThemeColor = v
            applyColor(v)
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

-- @installed:1781121142