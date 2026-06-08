-- Cloud Launcher v3
-- Copies cloud_user.lua to a sandbox instance, injects plugins, runs it
-- cloud_user.lua is NEVER modified

local CLOUD_USER = "cloud_user.lua"
local INSTANCE   = ".cloud_instance.lua"
local PLUGIN_DIR = "plugins"

if not fs.exists(CLOUD_USER) then
    error("cloud_user.lua not found", 0)
end

-- ── Collect plugin file paths ─────────────────────────────────────────────────
local pluginFiles = {}
if fs.isDir(PLUGIN_DIR) then
    for _, file in ipairs(fs.list(PLUGIN_DIR)) do
        if file:match("%.lua$") then
            table.insert(pluginFiles, PLUGIN_DIR .. "/" .. file)
        end
    end
end

-- ── Read original source ──────────────────────────────────────────────────────
local f = fs.open(CLOUD_USER, "r")
local src = f.readAll()
f.close()

-- ── Strip final while loop line by line ──────────────────────────────────────
local lines = {}
for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
end
-- remove trailing blank lines then the 3-line loop + its "end"
while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
-- expect last 4 lines: "end", "    if isAdmin...", "    doLogin()", "while true do"
for _ = 1, 4 do table.remove(lines) end
local stripped = table.concat(lines, "\n")

-- ── Build injected code ───────────────────────────────────────────────────────
local inject = {}

-- load all plugin files inline so they share the same scope
table.insert(inject, "\n-- === Cloud Launcher injection ===")
table.insert(inject, "local _plugins = {}")
for _, path in ipairs(pluginFiles) do
    -- read plugin source and inline it as a function that returns the plugin table
    local pf = fs.open(path, "r")
    local psrc = pf.readAll()
    pf.close()
    table.insert(inject, "do")
    table.insert(inject, "  local _p = (function()")
    table.insert(inject, psrc)
    table.insert(inject, "  end)()")
    table.insert(inject, "  if type(_p) == 'table' and _p.run and _p.name then table.insert(_plugins, _p) end")
    table.insert(inject, "end")
end

-- separate plugins: patch plugins (no menu entry) vs menu plugins
table.insert(inject, [[
local _menuPlugins  = {}
local _patchPlugins = {}
for _, p in ipairs(_plugins) do
    if p.patch then
        table.insert(_patchPlugins, p)
    else
        table.insert(_menuPlugins, p)
    end
end

-- run patch plugins immediately (they modify globals like itemListUI)
for _, p in ipairs(_patchPlugins) do p.run() end

local _origUserMenu = userMenu
userMenu = function()
    if #_menuPlugins == 0 then _origUserMenu() return end
    local menuItems = {
        { label="Withdraw", icon=colors.green },
        { label="Deposit",  icon=colors.blue  },
        { label="Log",      icon=colors.gray  },
    }
    for _, p in ipairs(_menuPlugins) do
        table.insert(menuItems, { label = p.label or p.name, icon = colors.purple })
    end
    table.insert(menuItems, { label="Logout", icon=colors.red })
    local logoutIdx = #menuItems
    while true do
        local sel = clickMenu("Cloud - " .. username, menuItems)
        if sel == nil or sel == logoutIdx then
            token=nil username=nil isAdmin=false return
        elseif sel == 1 then
            itemListUI({ title="Withdraw", actionLabel="Withdrew",
                fetchFn=function() local r=rpc({type="list_vault",token=token}) return r or {} end,
                actionFn=function(item,amt)
                    local r=rpc({type="withdraw",token=token,name=item.name,displayName=item.displayName,count=amt},10)
                    return r and r.ok, r and r.err end })
        elseif sel == 2 then
            itemListUI({ title="Deposit", actionLabel="Deposited",
                fetchFn=function() local r=rpc({type="list_inventory",token=token}) return r or {} end,
                actionFn=function(item,amt)
                    local r=rpc({type="deposit",token=token,name=item.name,displayName=item.displayName,count=amt},10)
                    return r and r.ok, r and r.err end })
        elseif sel == 3 then
            logScreen()
        else
            local idx = sel - 3
            if _menuPlugins[idx] then _menuPlugins[idx].run() end
        end
    end
end
]])

-- restore main loop
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