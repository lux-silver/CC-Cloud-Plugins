-- Config API Plugin v2
-- patch plugin: injects global "configAPI"
-- Saves per-plugin configs in config/pluginname.cfg
-- Applies all onChange callbacks on boot automatically

local plugin  = {}
plugin.name   = "config_api"
plugin.label  = "config_api"
plugin.patch  = true
plugin.priority = 1

function plugin.run()

local CFG_DIR = "config"

-- ── Storage ───────────────────────────────────────────────────────────────────
local function cfgPath(pluginName)
    local safe = pluginName:lower():gsub("[^a-z0-9_]","_")
    return CFG_DIR .. "/" .. safe .. ".cfg"
end

local function loadCfg(pluginName)
    local db = {}
    local path = cfgPath(pluginName)
    if not fs.exists(path) then return db end
    local f = fs.open(path, "r")
    while true do
        local line = f.readLine()
        if not line then break end
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then db[k] = v end
    end
    f.close()
    return db
end

local function saveCfg(pluginName, db)
    if not fs.isDir(CFG_DIR) then fs.makeDir(CFG_DIR) end
    local f = fs.open(cfgPath(pluginName), "w")
    for k, v in pairs(db) do f.writeLine(k .. "=" .. tostring(v)) end
    f.close()
end

local function parseVal(v)
    if v == "true"  then return true  end
    if v == "false" then return false end
    local n = tonumber(v)
    if n then return n end
    return v
end

-- ── Registry ──────────────────────────────────────────────────────────────────
local registry  = {}   -- ordered list of entries
local byKey     = {}   -- byKey[key] = entry
local cfgCache  = {}   -- cfgCache[pluginName] = {key=val,...}

local function getCache(pluginName)
    if not cfgCache[pluginName] then
        cfgCache[pluginName] = loadCfg(pluginName)
    end
    return cfgCache[pluginName]
end

local function register(entry)
    if byKey[entry.key] then return end
    local cache = getCache(entry.plugin)
    local raw   = cache[entry.key]
    entry.value = raw ~= nil and parseVal(raw) or entry.default
    if entry.onChange then
        pcall(entry.onChange, entry.value)  -- apply on boot
    else
        entry.onChange = function() end
    end
    table.insert(registry, entry)
    byKey[entry.key] = entry
end

local function get(key)
    local e = byKey[key]
    return e and e.value or nil
end

local function set(key, value)
    local e = byKey[key]
    if not e then return end
    e.value = value
    local cache = getCache(e.plugin)
    cache[e.key] = tostring(value)
    saveCfg(e.plugin, cache)
    pcall(e.onChange, value)
end

-- ── Color list ────────────────────────────────────────────────────────────────
local COLOR_LIST = {
    {name="Blue",      c=colors.blue     },
    {name="Red",       c=colors.red      },
    {name="Green",     c=colors.green    },
    {name="Purple",    c=colors.purple   },
    {name="Cyan",      c=colors.cyan     },
    {name="Orange",    c=colors.orange   },
    {name="Magenta",   c=colors.magenta  },
    {name="Gray",      c=colors.gray     },
    {name="LightBlue", c=colors.lightBlue},
    {name="Yellow",    c=colors.yellow   },
    {name="Lime",      c=colors.lime     },
    {name="Brown",     c=colors.brown    },
}
local function colorByVal(c)
    for _,col in ipairs(COLOR_LIST) do if col.c==c then return col end end
    return COLOR_LIST[1]
end

-- ── Widgets ───────────────────────────────────────────────────────────────────
local function drawSlider(x, y, w, value, minV, maxV, step, col)
    local trackW = math.max(2, w - 8)
    local range  = maxV - minV
    local filled = range>0 and math.floor((value-minV)/range*trackW) or 0
    filled = math.max(0, math.min(filled, trackW))
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white) term.write("[")
    term.setTextColor(colors.lightGray) term.write("<")
    term.setBackgroundColor(col or colors.blue) term.setTextColor(col or colors.blue)
    term.write(string.rep(" ", filled))
    term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
    term.write(string.rep(" ", trackW-filled))
    term.setBackgroundColor(colors.black) term.setTextColor(colors.lightGray) term.write(">")
    term.setTextColor(colors.gray) term.write("]")
    term.setTextColor(colors.yellow) term.write(" "..tostring(value))
    return {row=y, decX=x+1, incX=x+2+trackW, trackX1=x+2, trackX2=x+1+trackW, trackW=trackW}
end

local function drawCheckbox(x, y, value, label)
    term.setCursorPos(x, y) term.setBackgroundColor(colors.black)
    if value then term.setTextColor(colors.lime) term.write("[x] ")
    else          term.setTextColor(colors.gray) term.write("[ ] ") end
    term.setTextColor(colors.white) term.write(label or "")
    return {row=y, x1=x, x2=x+3}
end

local function drawTextbox(x, y, w, value, focused, label)
    term.setCursorPos(x, y) term.setBackgroundColor(colors.black)
    if label then
        term.setTextColor(colors.white) term.write(label..": ")
        x = x + #label + 2  w = w - #label - 2
    end
    term.setCursorPos(x, y)
    term.setBackgroundColor(focused and colors.gray or colors.black)
    term.setTextColor(colors.white)
    local disp = tostring(value or ""):sub(-(w-3))
    term.write("["..disp..(focused and "_" or " ")..string.rep(" ", math.max(0,w-#disp-3)).."]")
    return {row=y, x1=x, x2=x+w-1}
end

local function drawColorPicker(x, y, cur)
    term.setCursorPos(x, y)
    for i, col in ipairs(COLOR_LIST) do
        term.setCursorPos(x+i-1, y)
        term.setBackgroundColor(col.c) term.setTextColor(colors.white)
        term.write(col.c==cur and "*" or " ")
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.yellow)
    term.write("  "..colorByVal(cur).name)
    return {row=y, x1=x, x2=x+#COLOR_LIST-1}
end

-- ── Settings screen — one page per plugin, full screen each ──────────────────
local function settingsScreen()
    local W,H = term.getSize()

    -- gather plugin names
    local plugNames = {}
    local plugMap   = {}
    for _, e in ipairs(registry) do
        if not plugMap[e.plugin] then
            table.insert(plugNames, e.plugin)
            plugMap[e.plugin] = {}
        end
        table.insert(plugMap[e.plugin], e)
    end

    if #plugNames == 0 then
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Settings")
        term.setCursorPos(1,3) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("No settings registered.")
        term.setCursorPos(1,H) term.write("[Q] back")
        repeat local ev,p1=os.pullEvent()
        until (ev=="key" and (p1==keys.q or p1==keys.escape)) or ev=="mouse_click"
        return
    end

    local tabIdx   = 1
    local focusIdx = nil
    local pageScroll = 0

    local function entries() return plugMap[plugNames[tabIdx]] or {} end

    -- tab bar widths
    local function tabRanges()
        local ranges = {}
        local x = 1
        for i, name in ipairs(plugNames) do
            local short = name:sub(1,9)
            ranges[i] = {x1=x, x2=x+#short+1, name=short}
            x = x + #short + 2
        end
        return ranges
    end

    local function drawHeader()
        W,H = term.getSize()
        -- row 1: title + [X]
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        term.write(" Settings")
        term.setCursorPos(W-2,1) term.write("[X]")

        -- row 2: tabs
        term.setCursorPos(1,2) term.setBackgroundColor(colors.black) term.clearLine()
        local ranges = tabRanges()
        for i, r in ipairs(ranges) do
            term.setCursorPos(r.x1, 2)
            if i==tabIdx then
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else
                term.setBackgroundColor(colors.black) term.setTextColor(colors.lightGray)
            end
            term.write(" "..r.name.." ")
        end

        -- row 3: plugin full name subtitle
        term.setCursorPos(1,3) term.setBackgroundColor(colors.black) term.clearLine()
        term.setTextColor(colors.gray) term.write(" "..plugNames[tabIdx])

        -- divider row 4
        term.setCursorPos(1,4) term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
        term.write(string.rep("-",W))
    end

    local function drawPage()
        W,H = term.getSize()
        term.setBackgroundColor(colors.black) term.clear()
        drawHeader()

        local ents = entries()
        local startRow = 5
        local maxRow   = H - 2

        -- draw entries starting at pageScroll
        local visY = startRow
        for idx = 1+pageScroll, #ents do
            local e = ents[idx]
            if visY > maxRow then break end

            -- label row
            term.setCursorPos(1, visY) term.setBackgroundColor(colors.black) term.clearLine()
            term.setTextColor(colors.white) term.write(" "..e.label)
            visY = visY + 1
            if visY > maxRow then break end

            -- widget row
            term.setCursorPos(1, visY) term.setBackgroundColor(colors.black) term.clearLine()
            local wx = 3

            if e.type == "slider" then
                drawSlider(wx, visY, W-wx, e.value, e.min, e.max, e.step or 1, e.sliderColor)
            elseif e.type == "color" then
                drawColorPicker(wx, visY, e.value)
            elseif e.type == "checkbox" then
                drawCheckbox(wx, visY, e.value, "")
            elseif e.type == "text" then
                drawTextbox(wx, visY, W-wx, e.value, focusIdx==idx+pageScroll, "")
            end
            visY = visY + 2  -- gap between settings
        end

        -- scroll indicators
        if pageScroll > 0 then
            term.setCursorPos(W,5) term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white) term.write("^")
        end
        if 1+pageScroll+math.floor((maxRow-startRow)/3) <= #ents then
            term.setCursorPos(W,maxRow) term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white) term.write("v")
        end

        -- bottom hint
        term.setCursorPos(1,H-1) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.clearLine()
        term.write(" [Q]back  click to change")
        term.setCursorPos(1,H) term.clearLine()
        if focusIdx then
            term.setTextColor(colors.yellow) term.write(" Typing... Enter=done Bksp=delete")
        end
    end

    -- ── hit test ──────────────────────────────────────────────────────────────
    local function hitTab(mx,my)
        if my~=2 then return nil end
        for i,r in ipairs(tabRanges()) do
            if mx>=r.x1 and mx<=r.x2 then return i end
        end
        return nil
    end

    local function hitEntry(mx,my)
        -- returns entry index (in current tab) or nil
        local ents = entries()
        local visY = 5
        for idx = 1+pageScroll, #ents do
            local e = ents[idx]
            if visY+1 > H-2 then break end
            -- label on visY, widget on visY+1
            if my == visY or my == visY+1 then return idx, e, my==(visY+1) end
            visY = visY + 3
        end
        return nil
    end

    -- ── main loop ─────────────────────────────────────────────────────────────
    while true do
        drawPage()
        local ev,p1,p2,p3 = os.pullEvent()

        if ev=="term_resize" then W,H=term.getSize()

        elseif ev=="key" then
            if p1==keys.q or p1==keys.escape then
                if focusIdx then focusIdx=nil
                else return end
            elseif p1==keys.tab then
                tabIdx = tabIdx % #plugNames + 1
                focusIdx=nil pageScroll=0
            elseif p1==keys.enter then
                focusIdx=nil
            elseif p1==keys.backspace and focusIdx then
                local e = entries()[focusIdx]
                if e and e.type=="text" then
                    set(e.key, (e.value or ""):sub(1,-2))
                end
            end

        elseif ev=="char" then
            if focusIdx then
                local e = entries()[focusIdx]
                if e and e.type=="text" then
                    set(e.key, (e.value or "")..p1)
                end
            end

        elseif ev=="mouse_scroll" then
            pageScroll = math.max(0, pageScroll + p1)

        elseif ev=="mouse_click" then
            local btn,mx,my = p1,p2,p3
            -- [X] close
            if my==1 and mx>=W-2 then return end
            -- tab
            local ti = hitTab(mx,my)
            if ti then tabIdx=ti focusIdx=nil pageScroll=0 end

            local idx, e, onWidget = hitEntry(mx,my)
            if idx and e and onWidget then
                if e.type=="checkbox" then
                    set(e.key, not e.value)
                elseif e.type=="text" then
                    focusIdx = idx
                elseif e.type=="color" then
                    local ci = mx - 2  -- wx=3 → ci=mx-3+1
                    ci = mx - 3 + 1
                    if ci>=1 and ci<=#COLOR_LIST then
                        set(e.key, COLOR_LIST[ci].c)
                    end
                elseif e.type=="slider" then
                    local trackW = math.max(2, W-3-8)
                    local tx1 = 3+2  local tx2 = tx1+trackW-1
                    local decX = tx1-1  local incX = tx2+1
                    local step = e.step or 1
                    if mx==decX then
                        set(e.key, math.max(e.min, e.value-step))
                    elseif mx==incX then
                        set(e.key, math.min(e.max, e.value+step))
                    elseif mx>=tx1 and mx<=tx2 then
                        local frac = (mx-tx1)/(tx2-tx1)
                        local v = e.min + math.floor(frac*(e.max-e.min)/step+0.5)*step
                        set(e.key, math.max(e.min, math.min(e.max,v)))
                    end
                end
            end
        end
    end
end

-- ── Expose configAPI global ───────────────────────────────────────────────────
configAPI = {
    register       = register,
    get            = get,
    set            = set,
    settingsScreen = settingsScreen,
    colors         = COLOR_LIST,
}

end -- plugin.run
return plugin
