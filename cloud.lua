-- Cloud Launcher v4 (CORRIGIDO: Tela azul apenas quando há atualizações)
-- Copies cloud_user.lua to a sandbox instance, injects plugins, runs it
-- cloud_user.lua is NEVER modified

local CLOUD_USER = "cloud_user.lua"
local INSTANCE   = ".cloud_instance.lua"
local PLUGIN_DIR = "plugins"

if not fs.exists(CLOUD_USER) then
    error("cloud_user.lua not found", 0)
end

-- ── Load plugin metadata (without executing) ──────────────────────────────────
local function loadPluginMeta(path)
    local pf = fs.open(path, "r")
    local psrc = pf.readAll()
    pf.close()
    
    -- Força o instalador a ler apenas os metadados em silêncio absoluto aqui
    _G._cloudPluginLoad = true
    local ok, p = pcall(loadstring(psrc, "@"..path))
    _G._cloudPluginLoad = nil
    
    if not ok or type(p) ~= "table" or not p.name then return nil, psrc end
    return p, psrc
end

local allPlugins = {}

if fs.isDir(PLUGIN_DIR) then
    for _, file in ipairs(fs.list(PLUGIN_DIR)) do
        if file:match("%.lua$") then
            local path = PLUGIN_DIR .. "/" .. file
            local meta, src = loadPluginMeta(path)
            if src then
                table.insert(allPlugins, { meta = meta, src = src, path = path })
            end
        end
    end
end

-- sort plugins by priority
table.sort(allPlugins, function(a, b)
    local pa = a.meta and a.meta.priority or (a.meta and a.meta.patch and 1 or 10)
    local pb = b.meta and b.meta.priority or (b.meta and b.meta.patch and 1 or 10)
    return pa < pb
end)

-- ── Handle Priority 0 Plugins (Pre-Boot) ──────────────────────────────────────
local context = {
    restartRequested = false,
    reason = "",
    requestRestart = function(msg)
        context.restartRequested = true
        context.reason = msg or "Plugin requested restart"
    end
}

-- Executa os plugins de pre-boot
for _, p in ipairs(allPlugins) do
    local prio = p.meta and p.meta.priority or (p.meta and p.meta.patch and 1 or 10)
    if prio == 0 and p.meta.preBoot then
        
        -- !!! TRUQUE MÁGICO !!!
        -- Definimos como FALSE para que o install.lua saiba que PODE rodar e mostrar a tela.
        -- Mas o install.lua original só vai abrir a interface gráfica se ele REALMENTE 
        -- detetar um arquivo modificado na internet. Se estiver tudo igual, ele sai em silêncio.
        _G._cloudPluginLoad = false 
        
        pcall(p.meta.preBoot, context)
        
        if context.restartRequested then
            print(context.reason)
            os.sleep(1)
            -- Re-executa o launcher para aplicar as mudanças (Segundo Boot)
            os.queueEvent("timer", 0)
            os.pullEvent("timer")
            return shell.run(shell.getRunningProgram())
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

-- Remove linhas vazias e assinaturas do instalador no final
while #lines > 0 do
    local lastLine = lines[#lines]:gsub("%s+$", "")
    if lastLine == "" or lastLine:match("%-%-%-? ?@installed:%d+") then
        table.remove(lines)
    else
        break
    end
end

-- Corta o loop final original de 4 linhas
for _ = 1, 4 do 
    if #lines > 0 then table.remove(lines) end 
end
local stripped = table.concat(lines, "\n")

-- ── Build injected code ───────────────────────────────────────────────────────
local inject = {}

table.insert(inject, "\n-- === Cloud Launcher injection ===")
table.insert(inject, "local _plugins = {}")
for _, p in ipairs(allPlugins) do
    local prio = p.meta and p.meta.priority or (p.meta and p.meta.patch and 1 or 10)
    if prio > 0 then
        table.insert(inject, "do")
        table.insert(inject, "  local _p = (function()")
        table.insert(inject, p.src)
        table.insert(inject, "  end)()")
        table.insert(inject, "  if type(_p) == 'table' and _p.run and _p.name then table.insert(_plugins, _p) end")
        table.insert(inject, "end")
    end
end

-- Injeção do menu do utilizador e plugins patch
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

-- Executa os patches imediatamente
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

-- Restaura o loop principal
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
