-- Config API Plugin v2
-- patch plugin: injects global "configAPI"
-- Saves per-plugin configs in config/pluginname.cfg
-- Applies all onChange callbacks on boot automatically

local plugin  = {}
plugin.name   = "config_api"
plugin.label  = "config_api"
plugin.patch  = true
plugin.priority = 1

-- Deixamos a estrutura global do plugin idêntica à original
function plugin.run()
end

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

-- ── Sua Função drawTextbox Nova (Protegida contra números/booleanos/nil) ──────
local function drawTextbox(x, y, w, value, focused, label)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)

    if label then
        term.setTextColor(colors.white)
        term.write(label .. ": ")
        x = x + #label + 2
        w = w - #label - 2
    end

    term.setCursorPos(x, y)
    term.setBackgroundColor(focused and colors.gray or colors.black)
    term.setTextColor(colors.white)

    local text = tostring(value or "")

    local disp
    if #text > (w - 3) then
        disp = text:sub(-(w - 3))
    else
        disp = text
    end

    term.write(
        "[" ..
        disp ..
        (focused and "_" or " ") ..
        string.rep(" ", math.max(0, w - #disp - 3)) ..
        "]"
    )

    return {
        row = y,
        x1 = x,
        x2 = x + w - 1
    }
end

local function drawColorPicker(x, y, cur)
    term.setCursorPos(x, y)
    for i, col in ipairs(COLOR_LIST) do
        term.setCursorPos(x+i-1, y)
        pcall(term.setBackgroundColor, col.c) term.setTextColor(colors.white)
        term.write(col.c==cur and "*" or " ")
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.yellow)
    term.write("  "..colorByVal(cur).name)
    return {row=y, x1=x, x2=x+#COLOR_LIST-1}
end

-- ── Settings screen — COMPLETA com toda a interatividade original ─────────────
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
        -- Mantemos o cabeçalho respeitando a cor customizada se ela existir
        local headerCol = _G.cloudThemeColor or colors.blue
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(headerCol) term.setTextColor(colors.white)
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
        
        -- Aqui está o segredo: usa a cor customizada dinâmica para pintar a barra superior!
        local headerCol = _G.cloudThemeColor or colors.blue
        term.setBackgroundColor(headerCol) term.setTextColor(colors.white)
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
        local startY = 5
        local maxRows = H - startY - 1
        local widgets = {}

        for i = 1, maxRows do
            local idx = i + pageScroll
            local e = ents[idx]
            if not e then break end

            local rowY = startY + i - 1
            term.setCursorPos(2, rowY)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.write(e.label)

            local wX = 20
            local wW = W - wX - 1

            if e.type == "bool" then
                widgets[idx] = drawCheckbox(wX, rowY, e.value, "")
            elseif e.type == "text" then
                widgets[idx] = drawTextbox(wX, rowY, wW, e.value, (focusIdx == idx), nil)
            elseif e.type == "color" then
                widgets[idx] = drawColorPicker(wX, rowY, e.value)
            elseif e.type == "slider" then
                widgets[idx] = drawSlider(wX, rowY, wW, e.value, e.min or 0, e.max or 100, e.step or 1, _G.cloudThemeColor)
            end
        end

        -- Footer instructions
        term.setCursorPos(2, H) term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
        term.write("[Tab/Arrows] Navigate | [Q/Esc] Save & Exit")
        if focusIdx then
            term.setCursorPos(W - 12, H) term.setTextColor(colors.yellow) term.write("[Editing...]")
        end
        return widgets
    end

    -- ── Main event loop da tela de configurações original ─────────────────────
    while true do
        local widgets = drawPage()
        local ev, p1, p2, p3 = os.pullEvent()

        if ev == "term_resize" then
            W,H = term.getSize()
        elseif ev == "key" then
            if focusIdx then
                local e = entries()[focusIdx]
                if p1 == keys.enter or p1 == keys.escape then
                    focusIdx = nil
                elseif p1 == keys.backspace then
                    local s = tostring(e.value or "")
                    set(e.key, s:sub(1, #s-1))
                end
            else
                if p1 == keys.q or p1 == keys.escape then
                    break
                elseif p1 == keys.tab or p1 == keys.down then
                    local ents = entries()
                    if #ents > 0 then
                        focusIdx = nil
                        pageScroll = math.min(pageScroll + 1, math.max(0, #ents - (H - 6)))
                    end
                elseif p1 == keys.up then
                    pageScroll = math.max(0, pageScroll - 1)
                end
            end
        elseif ev == "char" and focusIdx then
            local e = entries()[focusIdx]
            set(e.key, tostring(e.value or "") .. p1)
        elseif ev == "mouse_click" and p1 == 1 then
            local mx, my = p2, p3
            
            -- Clique no botão [X] para fechar
            if my == 1 and mx >= W-3 then
                break
            end

            -- Clique nas abas (Tabs)
            if my == 2 then
                local ranges = tabRanges()
                for i, r in ipairs(ranges) do
                    if mx >= r.x1 and mx <= r.x2 then
                        tabIdx = i
                        focusIdx = nil
                        pageScroll = 0
                        break
                    end
                end
            end

            -- Clique nos Elementos da Página (Widgets)
            local ents = entries()
            local startY = 5
            local idx = my - startY + 1 + pageScroll

            if ents[idx] and widgets[idx] then
                local e = ents[idx]
                if e.type == "bool" then
                    set(e.key, not e.value)
                elseif e.type == "text" then
                    focusIdx = idx
                elseif e.type == "color" then
                    local ci = mx - 20 + 1
                    if ci >= 1 and ci <= #COLOR_LIST then
                        set(e.key, COLOR_LIST[ci].c)
                    end
                elseif e.type == "slider" then
                    local wX = 20
                    local trackW = math.max(2, W - wX - 8)
                    local tx1 = wX + 2
                    local tx2 = tx1 + trackW - 1
                    local decX = tx1 - 1
                    local incX = tx2 + 1
                    local step = e.step or 1
                    if mx == decX then
                        set(e.key, math.max(e.min or 0, e.value - step))
                    elseif mx == incX then
                        set(e.key, math.min(e.max or 100, e.value + step))
                    elseif mx >= tx1 and mx <= tx2 then
                        local frac = (mx - tx1) / (tx2 - tx1)
                        local minV = e.min or 0
                        local maxV = e.max or 100
                        local v = minV + math.floor(frac * (maxV - minV) / step + 0.5) * step
                        set(e.key, math.max(minV, math.min(maxV, v)))
                    end
                end
            else
                -- Clicou fora, remove o foco do textbox
                focusIdx = nil
            end
        end
    end
end

-- ── Expose configAPI global ───────────────────────────────────────────────────
_G.configAPI = {
    register       = register,
    get            = get,
    set            = set,
    settingsScreen = settingsScreen
}
configAPI = _G.configAPI

return plugin
