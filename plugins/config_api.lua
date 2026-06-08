-- Config API Plugin v1
-- patch plugin: injects global "configAPI" for other plugins to register settings
-- Place at: plugins/config_api.lua

local plugin = {}
plugin.name  = "config_api"
plugin.label = "config_api"
plugin.patch = true
plugin.priority = 0

function plugin.run()

-- ── Persistent storage ────────────────────────────────────────────────────────
-- Saves to config.db (simple key=value lines)
local DB_PATH = "config.db"

local function loadDB()
    local db = {}
    if not fs.exists(DB_PATH) then return db end
    local f = fs.open(DB_PATH, "r")
    while true do
        local line = f.readLine()
        if not line then break end
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then db[k] = v end
    end
    f.close()
    return db
end

local function saveDB(db)
    local f = fs.open(DB_PATH, "w")
    for k, v in pairs(db) do f.writeLine(k .. "=" .. tostring(v)) end
    f.close()
end

local DB = loadDB()

local function dbGet(key, default)
    local v = DB[key]
    if v == nil then return default end
    if v == "true" then return true end
    if v == "false" then return false end
    local n = tonumber(v)
    if n then return n end
    return v
end

local function dbSet(key, value)
    DB[key] = tostring(value)
    saveDB(DB)
end

-- ── Registry ──────────────────────────────────────────────────────────────────
-- plugins register their settings here
-- entry: { plugin=name, key=str, label=str, type="slider"|"checkbox"|"text"|"color",
--          min=n, max=n, step=n, default=val, value=val, onChange=fn }

local registry = {}  -- list of setting entries
local byKey    = {}  -- byKey[key] = entry

local function register(entry)
    -- entry.key must be unique (use "pluginname.settingname")
    if byKey[entry.key] then return end  -- already registered
    entry.value = dbGet(entry.key, entry.default)
    entry.onChange = entry.onChange or function() end
    table.insert(registry, entry)
    byKey[entry.key] = entry
    -- apply initial value
    entry.onChange(entry.value)
end

local function get(key)
    local e = byKey[key]
    return e and e.value or nil
end

local function set(key, value)
    local e = byKey[key]
    if not e then return end
    e.value = value
    dbSet(key, value)
    e.onChange(value)
end

-- ── Color list for color-type settings ───────────────────────────────────────
local COLOR_LIST = {
    {name="Blue",        c=colors.blue       },
    {name="Red",         c=colors.red        },
    {name="Green",       c=colors.green      },
    {name="Purple",      c=colors.purple     },
    {name="Cyan",        c=colors.cyan       },
    {name="Orange",      c=colors.orange     },
    {name="Magenta",     c=colors.magenta    },
    {name="Gray",        c=colors.gray       },
    {name="LightBlue",   c=colors.lightBlue  },
    {name="Yellow",      c=colors.yellow     },
    {name="Lime",        c=colors.lime       },
    {name="Brown",       c=colors.brown      },
}

local function colorIdx(c)
    for i,col in ipairs(COLOR_LIST) do if col.c==c then return i end end
    return 1
end

-- ── Widgets ───────────────────────────────────────────────────────────────────
-- Each widget draws itself at (x,y) with given width and returns updated value.
-- Returns: newValue, dirty (bool)

-- Slider: [◄ ████░░░░ ►]  value label
local function drawSlider(x, y, w, value, minV, maxV, step, color)
    local W2,_ = term.getSize()
    local trackW = w - 6  -- space for [◄  ►] and padding
    if trackW < 2 then trackW = 2 end
    local range = maxV - minV
    local filled = range > 0 and math.floor((value - minV) / range * trackW) or 0
    filled = math.max(0, math.min(filled, trackW))

    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("[")
    term.setTextColor(colors.white) term.write("<")
    -- filled
    term.setBackgroundColor(color or colors.blue)
    term.setTextColor(color or colors.blue)
    term.write(string.rep(" ", filled))
    -- empty
    term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
    term.write(string.rep(" ", trackW - filled))
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.write(">")
    term.setTextColor(colors.gray) term.write("]")
    -- value label
    local lbl = " " .. tostring(value)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.yellow)
    term.write(lbl)

    -- return click zones: x+1=dec, x+2..x+1+trackW=track, x+2+trackW=inc
    return {
        decX = x+1,
        incX = x+2+trackW,
        trackX1 = x+2,
        trackX2 = x+1+trackW,
        trackW = trackW,
        row = y,
    }
end

-- Checkbox: [x] Label  or  [ ] Label
local function drawCheckbox(x, y, value, label)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    if value then
        term.setTextColor(colors.lime) term.write("[x] ")
    else
        term.setTextColor(colors.gray) term.write("[ ] ")
    end
    term.setTextColor(colors.white) term.write(label or "")
    return {row=y, x1=x, x2=x+3}
end

-- Textbox: [_text_cursor_________]
local function drawTextbox(x, y, w, value, focused, label)
    if label then
        term.setCursorPos(x, y)
        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
        term.write(label .. ": ")
        x = x + #label + 2
        w = w - #label - 2
    end
    term.setCursorPos(x, y)
    term.setBackgroundColor(focused and colors.gray or colors.black)
    term.setTextColor(colors.white)
    local display = value or ""
    if #display > w-2 then display = display:sub(#display-w+3) end
    term.write("[" .. display .. (focused and "_" or " "))
    local pad = w - #display - 2
    if pad > 0 then term.write(string.rep(" ", pad)) end
    term.write("]")
    return {row=y, x1=x, x2=x+w-1}
end

-- Color picker: row of colored blocks
local function drawColorPicker(x, y, currentColor)
    term.setCursorPos(x, y)
    local cx = x
    for i, col in ipairs(COLOR_LIST) do
        term.setCursorPos(cx, y)
        if col.c == currentColor then
            term.setBackgroundColor(col.c) term.setTextColor(colors.white)
            term.write("*")
        else
            term.setBackgroundColor(col.c) term.setTextColor(col.c)
            term.write(" ")
        end
        cx = cx + 1
    end
    term.setBackgroundColor(colors.black)
    -- name of current
    local name = ""
    for _,col in ipairs(COLOR_LIST) do if col.c==currentColor then name=col.name break end end
    term.setCursorPos(cx+1, y) term.setTextColor(colors.yellow) term.write(name)
    return {row=y, x1=x, x2=cx-1}
end

-- ── Settings screen ───────────────────────────────────────────────────────────
local function settingsScreen()
    local W,H = term.getSize()

    -- group entries by plugin name
    local plugins2 = {}
    local pluginMap = {}
    for _, e in ipairs(registry) do
        if not pluginMap[e.plugin] then
            table.insert(plugins2, e.plugin)
            pluginMap[e.plugin] = {}
        end
        table.insert(pluginMap[e.plugin], e)
    end

    if #plugins2 == 0 then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,1) term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white) term.clearLine()
        term.write(" Settings — no plugins registered")
        term.setCursorPos(1,3) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("No settings available.")
        term.setCursorPos(1,H) term.setTextColor(colors.gray) term.write("[Q]back")
        repeat local ev,p1=os.pullEvent() until (ev=="key" and p1==keys.q) or ev=="mouse_click"
        return
    end

    local tabIdx    = 1
    local focusIdx  = nil  -- focused textbox index in current tab
    local dirty     = false

    local function currentEntries() return pluginMap[plugins2[tabIdx]] or {} end

    local function draw()
        W,H = term.getSize()
        term.setBackgroundColor(colors.black) term.clear()

        -- header
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        term.write(" Settings")
        term.setCursorPos(W-2,1) term.write("[X]")

        -- tab bar (row 2)
        term.setCursorPos(1,2) term.setBackgroundColor(colors.black) term.clearLine()
        local tx = 1
        for i, pname in ipairs(plugins2) do
            local short = pname:sub(1,10)
            if i == tabIdx then
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else
                term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
            end
            term.setCursorPos(tx, 2)
            term.write(" "..short.." ")
            tx = tx + #short + 2
        end

        -- entries
        local entries = currentEntries()
        local ey = 4
        for idx, e in ipairs(entries) do
            if ey > H-2 then break end
            term.setCursorPos(1, ey)
            term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
            term.clearLine()

            if e.type == "slider" then
                term.write(e.label .. ":")
                drawSlider(1 + #e.label + 1, ey, W - #e.label - 2,
                           e.value, e.min, e.max, e.step or 1, e.sliderColor)
                ey = ey + 1

            elseif e.type == "color" then
                term.write(e.label .. ":")
                ey = ey + 1
                term.setCursorPos(3, ey) term.clearLine()
                drawColorPicker(3, ey, e.value)
                ey = ey + 1

            elseif e.type == "checkbox" then
                drawCheckbox(1, ey, e.value, e.label)
                ey = ey + 1

            elseif e.type == "text" then
                term.clearLine()
                drawTextbox(1, ey, W, e.value, focusIdx==idx, e.label)
                ey = ey + 1
            end

            ey = ey + 1  -- spacing
        end

        -- bottom hint
        term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("[Q]back  click to change")
    end

    -- ── tab hit test ──────────────────────────────────────────────────────────
    local function hitTab(mx, my)
        if my ~= 2 then return nil end
        local tx = 1
        for i, pname in ipairs(plugins2) do
            local short = pname:sub(1,10)
            local x2 = tx + #short + 1
            if mx >= tx and mx <= x2 then return i end
            tx = x2 + 1
        end
        return nil
    end

    while true do
        draw()
        local ev,p1,p2,p3 = os.pullEvent()

        if ev == "term_resize" then W,H=term.getSize()

        elseif ev == "key" then
            if p1 == keys.q or p1 == keys.escape then
                focusIdx = nil
                if dirty then saveDB(DB) end
                return
            elseif focusIdx then
                local e = currentEntries()[focusIdx]
                if e and e.type == "text" then
                    if p1 == keys.backspace then
                        e.value = e.value:sub(1,-2)
                        set(e.key, e.value)
                    elseif p1 == keys.enter then
                        focusIdx = nil
                    end
                end
            end

        elseif ev == "char" then
            if focusIdx then
                local e = currentEntries()[focusIdx]
                if e and e.type == "text" then
                    e.value = e.value .. p1
                    set(e.key, e.value)
                    dirty = true
                end
            end

        elseif ev == "mouse_click" then
            local btn,mx,my = p1,p2,p3
            -- header X
            if my==1 and mx>=W-2 then return end
            -- tab click
            local ti = hitTab(mx,my)
            if ti then tabIdx=ti focusIdx=nil end

            -- entry interaction
            local entries = currentEntries()
            local ey = 4
            for idx, e in ipairs(entries) do
                if ey > H-2 then break end
                if e.type=="slider" then
                    if my==ey then
                        local trackW = W - #e.label - 2 - 6
                        local tx1 = 1 + #e.label + 1 + 2
                        local tx2 = tx1 + trackW - 1
                        local decX = tx1 - 1
                        local incX = tx2 + 1
                        local step = e.step or 1
                        if mx==decX then
                            set(e.key, math.max(e.min, e.value - step)) dirty=true
                        elseif mx==incX then
                            set(e.key, math.min(e.max, e.value + step)) dirty=true
                        elseif mx>=tx1 and mx<=tx2 then
                            local frac=(mx-tx1)/(tx2-tx1)
                            local v=e.min+math.floor(frac*(e.max-e.min)/step+0.5)*step
                            set(e.key, math.max(e.min,math.min(e.max,v))) dirty=true
                        end
                    end
                    ey = ey + 2
                elseif e.type=="color" then
                    ey = ey + 1
                    if my==ey then
                        local ci = mx - 2  -- 3 is start
                        if ci>=1 and ci<=#COLOR_LIST then
                            set(e.key, COLOR_LIST[ci].c) dirty=true
                        end
                    end
                    ey = ey + 2
                elseif e.type=="checkbox" then
                    if my==ey then
                        set(e.key, not e.value) dirty=true
                    end
                    ey = ey + 2
                elseif e.type=="text" then
                    if my==ey then focusIdx=idx end
                    ey = ey + 2
                end
            end

        elseif ev == "mouse_scroll" then
            -- scroll through color options if on a color row
        end
    end
end

-- ── Expose global configAPI ───────────────────────────────────────────────────
configAPI = {
    register      = register,
    get           = get,
    set           = set,
    settingsScreen= settingsScreen,
    colors        = COLOR_LIST,
}

end -- plugin.run

return plugin
