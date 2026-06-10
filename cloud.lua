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

local _origUserMenu = userMenu
userMenu = function()
    if #_menuPlugins == 0 then _origUserMenu() return end
    local menuItems = {
        { label="Cloud Storage", icon=colors.cyan   },
        { label="Bank",          icon=colors.yellow },
        { label="Market",        icon=colors.orange },
    }
    for _, p in ipairs(_menuPlugins) do
        table.insert(menuItems, { label = p.label or p.name, icon = colors.purple })
    end
    table.insert(menuItems, { label="Logout", icon=colors.red })
    local logoutIdx = #menuItems
    while true do
        local displayName = _G.cloudDisplayName or username
        local sel = clickMenu("Cloud - " .. displayName, menuItems)
        if sel == nil or sel == logoutIdx then
            token=nil username=nil isAdmin=false return
        elseif sel == 1 then cloudStorageMenu()
        elseif sel == 2 then bankMenu()
        elseif sel == 3 then marketMenu()
        else
            local idx = sel - 3
            if _menuPlugins[idx] then _menuPlugins[idx].run() end
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
