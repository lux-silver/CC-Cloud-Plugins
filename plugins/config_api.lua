-- Config API Plugin v2 (CORRIGIDO)
-- patch plugin: injects global "configAPI"
-- Saves per-plugin configs in config/pluginname.cfg
-- Applies all onChange callbacks on boot automatically

local plugin  = {}
plugin.name   = "config_api"
plugin.label  = "config_api"
plugin.patch  = true
plugin.priority = 1

-- A função run fica vazia porque este é um plugin de Patch (roda no boot automaticamente)
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

local function drawTextbox(x, y, w, value, focused, label)
    term.setCursorPos(x, y) term.setBackgroundColor(colors.black)
    if label then
        term.setTextColor(colors.white) term.write(label..": ")
        x = x + #label + 2  w = w - #label - 2
    end
    term.setCursorPos(x, y)
    term.setBackgroundColor(focused and colors.gray or colors.black)
    term.setTextColor(colors.white)
    local disp = (value or ""):sub(-(w-3))
    term.write("["..disp..(focused and "_" or " ")..string.rep(" ", math.max(0,w-#disp-3)).."]")
    return {row=y, x1=x, x2=x+w-1}
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

-- ── Settings screen — one page per plugin ─────────────────────────────────────
local function settingsScreen()
    local W,H = term.getSize()
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
        term.setCursorPos(1,3) term.setTextColor(colors.gray)
        term.write("No settings registered.")
        os.pullEvent("key")
        return
    end

    local tabIdx = 1
    term.setBackgroundColor(colors.black) term.clear()
    term.setCursorPos(1,2) term.setTextColor(colors.yellow)
    term.write("=== Settings: " .. plugNames[tabIdx] .. " ===")
    
    local y = 4
    for _, entry in ipairs(plugMap[plugNames[tabIdx]] or {}) do
        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        term.write(entry.label .. ": " .. tostring(entry.value))
        y = y + 1
    end
    term.setCursorPos(2, H-1) term.setTextColor(colors.gray)
    term.write("Press any key to return...")
    os.pullEvent("key")
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
