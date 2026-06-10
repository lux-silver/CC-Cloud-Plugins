-- Cloud Launcher v4
-- Copies cloud_user.lua to a sandbox instance, injects plugins, runs it
-- cloud_user.lua is NEVER modified
--
-- Plugin priority system:
--   plugin.priority = 0   → runs BEFORE instance is created (pre-boot)
--   plugin.priority = 1   → patch plugin (default for patch=true)
--   plugin.priority = 10  → menu plugin (default for patch=false)
--   lower number = runs first within each group

local CLOUD_USER = "cloud_user.lua"
local INSTANCE   = ".cloud_instance.lua"
local PLUGIN_DIR = "plugins"

if not fs.exists(CLOUD_USER) then
    error("cloud_user.lua not found", 0)
end

-- ── Load plugin metadata (without executing) ──────────────────────────────────
-- We read each plugin file, execute it to get the table, then sort by priority
_G._cloudPluginLoad = true  -- set BEFORE any plugin load to prevent UI execution

local function loadPluginMeta(path)
    local pf = fs.open(path, "r")
    local psrc = pf.readAll()
    pf.close()
    local ok, p = pcall(loadstring(psrc, "@"..path))
    if not ok or type(p) ~= "table" or not p.name then return nil, psrc end
    return p, psrc
end

local allPlugins = {}  -- {meta=table, src=string, path=string}

if fs.isDir(PLUGIN_DIR) then
    for _, file in ipairs(fs.list(PLUGIN_DIR)) do
        if file:match("%.lua$") then
            local path = PLUGIN_DIR .. "/" .. file
            local meta, src = loadPluginMeta(path)
            if meta then
                -- assign default priority
                if meta.priority == nil then
                    meta.priority = meta.patch and 1 or 10
                end
                table.insert(allPlugins, {meta=meta, src=src, path=path})
            end
        end
    end
end

-- sort by priority (lower = first)
table.sort(allPlugins, function(a,b)
    return (a.meta.priority or 10) < (b.meta.priority or 10)
end)

_G._cloudPluginLoad = nil  -- clear flag — metadata loading done

-- ── Pre-boot plugins (priority 0) ─────────────────────────────────────────────
-- These run before the instance is built.
-- They receive a simple pre-boot API: { requestRestart, setRestartMsg }
-- If any sets needRestart=true, launcher shows a message and re-execs after.

local needRestart   = false
local restartMsg    = "Restart required to apply updates."
local preBootCtx    = {
    requestRestart = function(msg)
        needRestart = true
        if msg then restartMsg = msg end
    end,
}

for _, entry in ipairs(allPlugins) do
    if entry.meta.priority == 0 then
        -- run in a protected call with the pre-boot context
        local chunk = loadstring(entry.src, "@"..entry.path)
        if chunk then
            local ok, p = pcall(chunk)
            if ok and type(p)=="table" and p.preBoot then
                pcall(p.preBoot, preBootCtx)
            end
        end
    end
end

-- ── If restart was requested, show prompt and relaunch ────────────────────────
if needRestart then
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.orange) term.setTextColor(colors.black)
    term.setCursorPos(1,1) term.clearLine()
    term.write(" Restart Required")
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.setCursorPos(1,3) term.write(restartMsg)
    term.setCursorPos(1,5) term.setTextColor(colors.yellow)
    term.write("[R] Restart now    [C] Continue anyway")
    while true do
        local ev,p1 = os.pullEvent("key")
        if p1 == keys.r then
            -- reboot the computer
            os.reboot()
        elseif p1 == keys.c then
            break
        end
    end
end

-- ── Read original cloud_user.lua ──────────────────────────────────────────────
local f = fs.open(CLOUD_USER, "r")
local src = f.readAll()
f.close()

-- ── Strip installer signature and final while loop ────────────────────────────
local lines = {}
for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
end

-- remove trailing blank lines and @installed signature
while #lines > 0 do
    local last = lines[#lines]:gsub("%s+$","")
    if last == "" or last:match("%-%-.-@installed:%d+") then
        table.remove(lines)
    else break end
end

-- remove last 4 lines (while true do / doLogin() / if isAdmin... / end)
for _ = 1, 4 do
    if #lines > 0 then table.remove(lines) end
end
local stripped = table.concat(lines, "\n")

-- ── Build injected code ───────────────────────────────────────────────────────
local inject = {}
table.insert(inject, "\n-- === Cloud Launcher v4 injection ===")
table.insert(inject, "local _plugins = {}")

-- inline all non-priority-0 plugins using dofile (saves memory vs inline)
for _, entry in ipairs(allPlugins) do
    if (entry.meta.priority or 10) > 0 then
        table.insert(inject, "do")
        table.insert(inject, "  _G._cloudPluginLoad = true")
        table.insert(inject, "  local _p = dofile(" .. string.format("%q", entry.path) .. ")")
        table.insert(inject, "  _G._cloudPluginLoad = nil")
        table.insert(inject, "  if type(_p)=='table' and _p.run and _p.name then")
        table.insert(inject, "    _p._priority = " .. tostring(entry.meta.priority or 10))
        table.insert(inject, "    table.insert(_plugins, _p)")
        table.insert(inject, "  end")
        table.insert(inject, "end")
    end
end

-- sort plugins by priority inside instance, then split patch vs menu
table.insert(inject, [[
table.sort(_plugins, function(a,b)
    return (a._priority or 10) < (b._priority or 10)
end)

local _menuPlugins  = {}
local _patchPlugins = {}
for _, p in ipairs(_plugins) do
    if p.patch then
        table.insert(_patchPlugins, p)
    else
        table.insert(_menuPlugins, p)
    end
end

-- run patch plugins in priority order
for _, p in ipairs(_patchPlugins) do p.run() end

-- Wrap userMenu to inject plugin entries without hardcoding the original menu
local _origUserMenu = userMenu
userMenu = function()
    if #_menuPlugins == 0 then _origUserMenu() return end

    -- Intercept the opts table from the original userMenu by monkey-patching
    -- the inner loop. We capture opts by running a fake iteration.
    -- Strategy: run original userMenu but override os.pullEvent to capture
    -- the opts list on first draw, then restore and rebuild with plugins.

    -- Simpler approach: shadow the original opts by re-reading the source.
    -- We detect opts by calling _origUserMenu in a sandboxed env where
    -- term writes are captured. Too complex.

    -- Best approach for CraftOS Lua 5.1:
    -- We know userMenu draws a list and waits for keys.
    -- We patch term.write to capture menu items on first clear, then abort.

    local capturedOpts = {}
    local capturing = true
    local origWrite = term.write
    local origClear = term.clearLine
    local origSetCursor = term.setCursorPos
    local origSetBg = term.setBackgroundColor
    local origSetFg = term.setTextColor
    local lastRow = 0

    -- Capture phase: intercept term to read menu items
    term.setCursorPos = function(x, y) lastRow = y origSetCursor(x, y) end
    term.write = function(s)
        -- menu items are written at col 3+ with a leading space
        if capturing and lastRow >= 3 then
            local trimmed = s:match("^ (.+)$")
            if trimmed and trimmed ~= "" then
                table.insert(capturedOpts, trimmed)
            end
        end
        origWrite(s)
    end

    -- Run one fake event cycle to capture the draw
    local origPull = os.pullEvent
    local pulled = false
    os.pullEvent = function(filter)
        if not pulled then
            pulled = true
            capturing = false
            -- restore term
            term.write = origWrite
            term.setCursorPos = origSetCursor
            -- abort original loop by erroring (caught below)
            error("__capture_done__")
        end
        return origPull(filter)
    end

    pcall(_origUserMenu)

    -- Restore everything
    term.write = origWrite
    term.clearLine = origClear
    term.setCursorPos = origSetCursor
    term.setBackgroundColor = origSetBg
    term.setTextColor = origSetFg
    os.pullEvent = origPull

    -- capturedOpts now has the original menu items (last one is "Logout")
    -- Remove "Logout" from end, we'll re-add it after plugin entries
    local baseOpts = {}
    for _, o in ipairs(capturedOpts) do
        if o:lower() ~= "logout" then table.insert(baseOpts, o) end
    end

    -- Build final opts: base + plugins + Logout
    local opts = {}
    for _, o in ipairs(baseOpts) do table.insert(opts, o) end
    for _, p in ipairs(_menuPlugins) do table.insert(opts, p.label or p.name) end
    table.insert(opts, "Logout")

    local sel = 1
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        local displayName = _G.cloudDisplayName or username
        term.write(" Cloud - " .. displayName)
        for i, opt in ipairs(opts) do
            term.setCursorPos(3, i+2)
            if i == sel then term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else term.setBackgroundColor(colors.black) term.setTextColor(colors.white) end
            term.clearLine() term.write(" " .. opt)
        end
        term.setBackgroundColor(colors.black)
        local ev, p1 = os.pullEvent("key")
        if p1 == keys.up and sel > 1 then sel=sel-1
        elseif p1 == keys.down and sel < #opts then sel=sel+1
        elseif p1 == keys.enter then
            local logoutIdx = #opts
            if sel == logoutIdx then
                token=nil username=nil isAdmin=false return
            elseif sel <= #baseOpts then
                -- call original userMenu but intercept to only run the selected option
                -- We fake the key sequence: navigate to sel, press enter
                local presses = {}
                -- reset to top first (sel-1 downs)
                for _ = 1, sel-1 do table.insert(presses, keys.down) end
                table.insert(presses, keys.enter)
                table.insert(presses, keys.q)  -- exit after action
                local origPull2 = os.pullEvent
                local pi = 0
                os.pullEvent = function(filter)
                    pi = pi + 1
                    if pi <= #presses then
                        return "key", presses[pi]
                    end
                    os.pullEvent = origPull2
                    return origPull2(filter)
                end
                _origUserMenu()
                os.pullEvent = origPull2
            else
                -- plugin
                local idx = sel - #baseOpts
                if _menuPlugins[idx] then _menuPlugins[idx].run() end
            end
        end
    end
end
]])

table.insert(inject, "\nwhile true do")
table.insert(inject, "    doLogin()")
table.insert(inject, "    if isAdmin then adminMenu() else userMenu() end")
table.insert(inject, "end")

-- ── Write and run instance ────────────────────────────────────────────────────
local out = fs.open(INSTANCE, "w")
out.write(stripped)
out.write("\n")
out.write(table.concat(inject, "\n"))
out.close()

dofile(INSTANCE)
