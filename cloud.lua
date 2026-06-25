-- Cloud Launcher v5
-- Carrega cloud_user.lua sem modificá-lo, injeta um sistema de plugin limpo.
-- Plugins recebem uma API completa: rpc, token, username, isAdmin, cores, etc.

local CLOUD_USER = "cloud_user.lua"
local INSTANCE   = ".cloud_instance.lua"
local PLUGIN_DIR = "plugins"

-- ── Bootstrap: garante que install.lua é v4 (auto-atualiza uma vez) ──────────
do
    local RAW = "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/install.lua"
    local f = fs.exists("install.lua") and fs.open("install.lua","r")
    local src = f and f.readAll()
    if f then f.close() end
    -- Se é v3 (não tem "RULES_FILE" que é exclusivo do v4), baixa v4
    if not src or not src:find("RULES_FILE") then
        local ok, res = pcall(http.get, RAW)
        if ok and res then
            local fresh = res.readAll(); res.close()
            if fresh and fresh:find("RULES_FILE") then
                local out = fs.open("install.lua","w")
                out.write(fresh); out.close()
            end
        end
    end
end

if not fs.exists(CLOUD_USER) then error("cloud_user.lua not found", 0) end

-- ─── 1. Carrega metadados dos plugins (sem executar o run()) ──────────────────
_G._cloudPluginLoad = true

local allPlugins = {}

local function loadPlugin(path)
    local f = fs.open(path, "r"); local src = f.readAll(); f.close()
    local chunk, err = load(src, "@"..path, "t", _G)
    if not chunk then print("[plugin] "..path..": "..tostring(err)); return nil, src end
    local ok, p = pcall(chunk)
    if not ok or type(p) ~= "table" or not p.name then return nil, src end
    return p, src
end

if fs.isDir(PLUGIN_DIR) then
    for _, file in ipairs(fs.list(PLUGIN_DIR)) do
        if file:match("%.lua$") then
            local path = PLUGIN_DIR.."/"..file
            local meta, src = loadPlugin(path)
            if meta then
                if meta.priority == nil then
                    meta.priority = meta.patch and 1 or 10
                end
                table.insert(allPlugins, {meta=meta, src=src, path=path})
            end
        end
    end
end

table.sort(allPlugins, function(a,b)
    return (a.meta.priority or 10) < (b.meta.priority or 10)
end)

_G._cloudPluginLoad = nil

-- ─── 2. Pre-boot plugins (priority 0) ─────────────────────────────────────────
local needRestart, restartMsg = false, "Restart required to apply updates."
local preBootCtx = {
    requestRestart = function(msg)
        needRestart = true
        if msg then restartMsg = msg end
    end,
}
for _, e in ipairs(allPlugins) do
    if e.meta.priority == 0 then
        local chunk = load(e.src, "@"..e.path, "t", _G)
        if chunk then
            local ok, p = pcall(chunk)
            if ok and type(p)=="table" and p.preBoot then pcall(p.preBoot, preBootCtx) end
        end
    end
end

if needRestart then
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.orange) term.setTextColor(colors.black)
    term.setCursorPos(1,1) term.clearLine() term.write(" Restart Required")
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.setCursorPos(1,3) term.write(restartMsg)
    term.setCursorPos(1,5) term.setTextColor(colors.yellow)
    term.write("[R] Restart now    [C] Continue")
    while true do
        local _,p1 = os.pullEvent("key")
        if p1==keys.r then os.reboot()
        elseif p1==keys.c then break end
    end
end

-- ─── 3. Lê e processa cloud_user.lua ─────────────────────────────────────────
local f = fs.open(CLOUD_USER, "r"); local src = f.readAll(); f.close()

-- Remove linhas finais até o while true do + doLogin() / adminMenu() / end
local lines = {}
for line in (src.."\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end

while #lines > 0 do
    local last = lines[#lines]:gsub("%s+$","")
    if last=="" or last:match("%-%-.-@installed:%d+") then
        table.remove(lines)
    else break end
end
-- Remove o loop principal (parallel.waitForAny ou while true do)
-- Corta a partir da PRIMEIRA linha que começa o loop de execução:
--   "parallel.waitForAny(" ou "while true do" no nível raiz (sem indentação)
local cutAt = #lines
for i = #lines, 1, -1 do
    local l = lines[i]:gsub("%s+$","")
    if l == "parallel.waitForAny(" or l:match("^while true do") then
        cutAt = i - 1
        break
    end
end
while cutAt > 0 and lines[cutAt]:gsub("%s+$","") == "" do cutAt = cutAt - 1 end

local stripped = table.concat(lines, "\n", 1, cutAt)

-- ─── 4. Constrói injeção ──────────────────────────────────────────────────────
--
-- O que é injetado depois do stripped:
--
--   a) _cloudAPI: tabela com referências a token, rpc, colors, etc.
--      Plugins usam isso — sem ficar caçando globals frágeis.
--
--   b) _registerPlugin / _runPlugins: sistema limpo para registrar e chamar.
--
--   c) Wrap de userMenu: adiciona entradas de plugin ao menu principal
--      de forma estável, sem hack de interceptar clickMenu.
--
--   d) Loop principal com doLogin() / userMenu() / adminMenu()

local inject = {}

table.insert(inject, [[

-- ═══════════════════════════════════════════════════════════════════════════════
-- Cloud Launcher v5 — Plugin System
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── API pública para plugins ────────────────────────────────────────────────
-- Plugins recebem esta tabela como argumento de p.run(api).
-- A tabela é reconstruída a cada chamada para garantir token atual.
local function buildApi()
    return {
        -- Identidade
        token     = token,
        username  = username,
        isAdmin   = isAdmin,
        -- Comunicação
        rpc       = rpc,
        httpRpc   = httpRpc,
        httpPost  = httpPost,
        -- UI helpers expostos pelo cloud_user
        clickMenu      = clickMenu,
        numInput       = numInput,
        amountPicker   = amountPicker,
        pickItem       = pickItem,
        -- Utilitários
        itemColor   = itemColor,
        prettyName  = prettyName,
        colors      = colors,
        term        = term,
        keys        = keys,
        W           = W, H = H,
        -- Marcar que precisa relogin
        requestRelogin = function() needsRelogin = true end,
    }
end

-- ── Registro de plugins ─────────────────────────────────────────────────────
local _menuPlugins  = {}   -- aparecem no menu principal
local _patchPlugins = {}   -- rodam no boot (modificam comportamento)

local function _registerPlugin(p)
    if not p or not p.name then return end
    p._priority = p.priority or (p.patch and 1 or 10)
    if p.patch then
        table.insert(_patchPlugins, p)
    else
        table.insert(_menuPlugins, p)
    end
end

-- ── Carrega plugins (priority > 0) ─────────────────────────────────────────
]])

for _, entry in ipairs(allPlugins) do
    if (entry.meta.priority or 10) > 0 then
        table.insert(inject, "do")
        table.insert(inject, "  _G._cloudPluginLoad = true")
        table.insert(inject, "  local _p = dofile("..string.format("%q", entry.path)..")")
        table.insert(inject, "  _G._cloudPluginLoad = nil")
        table.insert(inject, "  _registerPlugin(_p)")
        table.insert(inject, "end")
    end
end

-- Sort patch plugins by priority
table.insert(inject, [[

table.sort(_patchPlugins, function(a,b) return a._priority < b._priority end)
table.sort(_menuPlugins,  function(a,b) return a._priority < b._priority end)

-- Roda patch plugins logo após o boot (antes do primeiro menu)
for _, p in ipairs(_patchPlugins) do
    if p.run then pcall(p.run, buildApi()) end
end

-- ── Wrap userMenu para injetar entradas de plugins ────────────────────────────
if #_menuPlugins > 0 then
    local _origUserMenu = userMenu
    userMenu = function()
        while true do
            if needsRelogin then needsRelogin = false doLogin() end

            -- Monta itens do menu incluindo plugins
            local ncRes = rpc({type="get_notif_count", token=token}, 5)
            local unreadCount = (ncRes and ncRes.count) or unreadNotifs
            local hasUnread = unreadCount > 0
            local notifLabel = hasUnread and ("Notifications ("..unreadCount..")") or "Notifications"
            local hasFoodSub = foodSubCache and foodSubCache.food_sub

            local baseItems = {
                {label="Cloud Storage", icon=colors.cyan  },
                {label="Bank",          icon=colors.yellow},
                {label="Market",        icon=colors.orange},
                {label="Gambling",      icon=colors.pink  },
                {label="Subscriptions", icon=hasFoodSub and colors.lime or colors.purple},
                {label=notifLabel,      icon=colors.purple, flash=hasUnread},
                {label="Leaderboard",   icon=colors.gray  },
            }

            -- Insere plugins antes do Logout
            for _, p in ipairs(_menuPlugins) do
                table.insert(baseItems, {
                    label = p.label or p.name,
                    icon  = p.icon  or colors.purple,
                })
            end

            table.insert(baseItems, {label="Logout", icon=colors.red})

            local logoutIdx = #baseItems
            local sel = clickMenu("Cloud - "..username, baseItems, nil, 15)

            if sel == nil or sel == logoutIdx then
                token=nil username=nil isAdmin=false foodSubCache=nil return
            elseif sel==1 then cloudStorageMenu()
            elseif sel==2 then bankMenu()
            elseif sel==3 then marketMenu()
            elseif sel==4 then gamblingMenu()
            elseif sel==5 then subscriptionsMenu()
            elseif sel==6 then
                notificationsScreen()
                unreadCount=0 unreadNotifs=0
            elseif sel==7 then leaderboardScreen()
            else
                -- Plugin slot
                local pluginIdx = sel - 7   -- 7 base items before plugins
                local p = _menuPlugins[pluginIdx]
                if p and p.run then
                    local ok, err = pcall(p.run, buildApi())
                    if not ok then
                        term.setBackgroundColor(colors.black) term.clear()
                        term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                        term.setCursorPos(1,1) term.clearLine()
                        term.write(" Plugin error: "..p.name)
                        term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
                        term.setCursorPos(2,3) term.write(tostring(err):sub(1,W-2))
                        term.setCursorPos(2,5) term.setTextColor(colors.yellow)
                        term.write("Press any key...")
                        os.pullEvent()
                    end
                end
            end
        end
    end
end

-- ── Loop principal (preserva parallel + food delivery do original) ───────────
parallel.waitForAny(
    function()
        while true do
            if not tryRestoreSession() then doLogin() end
            if isAdmin then adminMenu() else userMenu() end
            if needsRelogin then
                local chk = httpPost("/session_check", {token=token or ""})
                if chk == nil then
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                    term.setCursorPos(1,1) term.clearLine() term.write(" Server Offline")
                    term.setBackgroundColor(colors.black)
                    term.setCursorPos(2,3) term.setTextColor(colors.yellow) term.write("Tunnel unreachable.")
                    term.setCursorPos(2,4) term.setTextColor(colors.gray)  term.write("Sessão mantida.")
                    term.setCursorPos(2,5) term.write("Pressione qualquer tecla para reconectar...")
                    os.pullEvent()
                    needsRelogin = false
                else
                    clearSession()
                    needsRelogin = false
                    token=nil username=nil isAdmin=false
                end
            end
        end
    end,
    function()
        while true do
            sleep(60)
            checkAndDeliverFood()
        end
    end
)
]])

-- ─── 5. Escreve e executa instância ───────────────────────────────────────────
local out = fs.open(INSTANCE, "w")
out.write(stripped)
out.write("\n")
out.write(table.concat(inject, "\n"))
out.close()

shell.run(INSTANCE)-- Cloud Launcher v5
-- Carrega cloud_user.lua sem modificá-lo, injeta um sistema de plugin limpo.
-- Plugins recebem uma API completa: rpc, token, username, isAdmin, cores, etc.

local CLOUD_USER = "cloud_user.lua"
local INSTANCE   = ".cloud_instance.lua"
local PLUGIN_DIR = "plugins"

-- ── Bootstrap: garante que install.lua é v4 (auto-atualiza uma vez) ──────────
do
    local RAW = "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/install.lua"
    local f = fs.exists("install.lua") and fs.open("install.lua","r")
    local src = f and f.readAll()
    if f then f.close() end
    -- Se é v3 (não tem "RULES_FILE" que é exclusivo do v4), baixa v4
    if not src or not src:find("RULES_FILE") then
        local ok, res = pcall(http.get, RAW)
        if ok and res then
            local fresh = res.readAll(); res.close()
            if fresh and fresh:find("RULES_FILE") then
                local out = fs.open("install.lua","w")
                out.write(fresh); out.close()
            end
        end
    end
end

if not fs.exists(CLOUD_USER) then error("cloud_user.lua not found", 0) end

-- ─── 1. Carrega metadados dos plugins (sem executar o run()) ──────────────────
_G._cloudPluginLoad = true

local allPlugins = {}

local function loadPlugin(path)
    local f = fs.open(path, "r"); local src = f.readAll(); f.close()
    local chunk, err = load(src, "@"..path, "t", _G)
    if not chunk then print("[plugin] "..path..": "..tostring(err)); return nil, src end
    local ok, p = pcall(chunk)
    if not ok or type(p) ~= "table" or not p.name then return nil, src end
    return p, src
end

if fs.isDir(PLUGIN_DIR) then
    for _, file in ipairs(fs.list(PLUGIN_DIR)) do
        if file:match("%.lua$") then
            local path = PLUGIN_DIR.."/"..file
            local meta, src = loadPlugin(path)
            if meta then
                if meta.priority == nil then
                    meta.priority = meta.patch and 1 or 10
                end
                table.insert(allPlugins, {meta=meta, src=src, path=path})
            end
        end
    end
end

table.sort(allPlugins, function(a,b)
    return (a.meta.priority or 10) < (b.meta.priority or 10)
end)

_G._cloudPluginLoad = nil

-- ─── 2. Pre-boot plugins (priority 0) ─────────────────────────────────────────
local needRestart, restartMsg = false, "Restart required to apply updates."
local preBootCtx = {
    requestRestart = function(msg)
        needRestart = true
        if msg then restartMsg = msg end
    end,
}
for _, e in ipairs(allPlugins) do
    if e.meta.priority == 0 then
        local chunk = load(e.src, "@"..e.path, "t", _G)
        if chunk then
            local ok, p = pcall(chunk)
            if ok and type(p)=="table" and p.preBoot then pcall(p.preBoot, preBootCtx) end
        end
    end
end

if needRestart then
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.orange) term.setTextColor(colors.black)
    term.setCursorPos(1,1) term.clearLine() term.write(" Restart Required")
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.setCursorPos(1,3) term.write(restartMsg)
    term.setCursorPos(1,5) term.setTextColor(colors.yellow)
    term.write("[R] Restart now    [C] Continue")
    while true do
        local _,p1 = os.pullEvent("key")
        if p1==keys.r then os.reboot()
        elseif p1==keys.c then break end
    end
end

-- ─── 3. Lê e processa cloud_user.lua ─────────────────────────────────────────
local f = fs.open(CLOUD_USER, "r"); local src = f.readAll(); f.close()

-- Remove linhas finais até o while true do + doLogin() / adminMenu() / end
local lines = {}
for line in (src.."\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end

while #lines > 0 do
    local last = lines[#lines]:gsub("%s+$","")
    if last=="" or last:match("%-%-.-@installed:%d+") then
        table.remove(lines)
    else break end
end
-- Remove o loop principal (parallel.waitForAny ou while true do)
-- Corta a partir da PRIMEIRA linha que começa o loop de execução:
--   "parallel.waitForAny(" ou "while true do" no nível raiz (sem indentação)
local cutAt = #lines
for i = #lines, 1, -1 do
    local l = lines[i]:gsub("%s+$","")
    if l == "parallel.waitForAny(" or l:match("^while true do") then
        cutAt = i - 1
        break
    end
end
while cutAt > 0 and lines[cutAt]:gsub("%s+$","") == "" do cutAt = cutAt - 1 end

local stripped = table.concat(lines, "\n", 1, cutAt)

-- ─── 4. Constrói injeção ──────────────────────────────────────────────────────
--
-- O que é injetado depois do stripped:
--
--   a) _cloudAPI: tabela com referências a token, rpc, colors, etc.
--      Plugins usam isso — sem ficar caçando globals frágeis.
--
--   b) _registerPlugin / _runPlugins: sistema limpo para registrar e chamar.
--
--   c) Wrap de userMenu: adiciona entradas de plugin ao menu principal
--      de forma estável, sem hack de interceptar clickMenu.
--
--   d) Loop principal com doLogin() / userMenu() / adminMenu()

local inject = {}

table.insert(inject, [[

-- ═══════════════════════════════════════════════════════════════════════════════
-- Cloud Launcher v5 — Plugin System
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── API pública para plugins ────────────────────────────────────────────────
-- Plugins recebem esta tabela como argumento de p.run(api).
-- A tabela é reconstruída a cada chamada para garantir token atual.
local function buildApi()
    return {
        -- Identidade
        token     = token,
        username  = username,
        isAdmin   = isAdmin,
        -- Comunicação
        rpc       = rpc,
        httpRpc   = httpRpc,
        httpPost  = httpPost,
        -- UI helpers expostos pelo cloud_user
        clickMenu      = clickMenu,
        numInput       = numInput,
        amountPicker   = amountPicker,
        pickItem       = pickItem,
        -- Utilitários
        itemColor   = itemColor,
        prettyName  = prettyName,
        colors      = colors,
        term        = term,
        keys        = keys,
        W           = W, H = H,
        -- Marcar que precisa relogin
        requestRelogin = function() needsRelogin = true end,
    }
end

-- ── Registro de plugins ─────────────────────────────────────────────────────
local _menuPlugins  = {}   -- aparecem no menu principal
local _patchPlugins = {}   -- rodam no boot (modificam comportamento)

local function _registerPlugin(p)
    if not p or not p.name then return end
    p._priority = p.priority or (p.patch and 1 or 10)
    if p.patch then
        table.insert(_patchPlugins, p)
    else
        table.insert(_menuPlugins, p)
    end
end

-- ── Carrega plugins (priority > 0) ─────────────────────────────────────────
]])

for _, entry in ipairs(allPlugins) do
    if (entry.meta.priority or 10) > 0 then
        table.insert(inject, "do")
        table.insert(inject, "  _G._cloudPluginLoad = true")
        table.insert(inject, "  local _p = dofile("..string.format("%q", entry.path)..")")
        table.insert(inject, "  _G._cloudPluginLoad = nil")
        table.insert(inject, "  _registerPlugin(_p)")
        table.insert(inject, "end")
    end
end

-- Sort patch plugins by priority
table.insert(inject, [[

table.sort(_patchPlugins, function(a,b) return a._priority < b._priority end)
table.sort(_menuPlugins,  function(a,b) return a._priority < b._priority end)

-- Roda patch plugins logo após o boot (antes do primeiro menu)
for _, p in ipairs(_patchPlugins) do
    if p.run then pcall(p.run, buildApi()) end
end

-- ── Wrap userMenu para injetar entradas de plugins ────────────────────────────
if #_menuPlugins > 0 then
    local _origUserMenu = userMenu
    userMenu = function()
        while true do
            if needsRelogin then needsRelogin = false doLogin() end

            -- Monta itens do menu incluindo plugins
            local ncRes = rpc({type="get_notif_count", token=token}, 5)
            local unreadCount = (ncRes and ncRes.count) or unreadNotifs
            local hasUnread = unreadCount > 0
            local notifLabel = hasUnread and ("Notifications ("..unreadCount..")") or "Notifications"
            local hasFoodSub = foodSubCache and foodSubCache.food_sub

            local baseItems = {
                {label="Cloud Storage", icon=colors.cyan  },
                {label="Bank",          icon=colors.yellow},
                {label="Market",        icon=colors.orange},
                {label="Gambling",      icon=colors.pink  },
                {label="Subscriptions", icon=hasFoodSub and colors.lime or colors.purple},
                {label=notifLabel,      icon=colors.purple, flash=hasUnread},
                {label="Leaderboard",   icon=colors.gray  },
            }

            -- Insere plugins antes do Logout
            for _, p in ipairs(_menuPlugins) do
                table.insert(baseItems, {
                    label = p.label or p.name,
                    icon  = p.icon  or colors.purple,
                })
            end

            table.insert(baseItems, {label="Logout", icon=colors.red})

            local logoutIdx = #baseItems
            local sel = clickMenu("Cloud - "..username, baseItems, nil, 15)

            if sel == nil or sel == logoutIdx then
                token=nil username=nil isAdmin=false foodSubCache=nil return
            elseif sel==1 then cloudStorageMenu()
            elseif sel==2 then bankMenu()
            elseif sel==3 then marketMenu()
            elseif sel==4 then gamblingMenu()
            elseif sel==5 then subscriptionsMenu()
            elseif sel==6 then
                notificationsScreen()
                unreadCount=0 unreadNotifs=0
            elseif sel==7 then leaderboardScreen()
            else
                -- Plugin slot
                local pluginIdx = sel - 7   -- 7 base items before plugins
                local p = _menuPlugins[pluginIdx]
                if p and p.run then
                    local ok, err = pcall(p.run, buildApi())
                    if not ok then
                        term.setBackgroundColor(colors.black) term.clear()
                        term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                        term.setCursorPos(1,1) term.clearLine()
                        term.write(" Plugin error: "..p.name)
                        term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
                        term.setCursorPos(2,3) term.write(tostring(err):sub(1,W-2))
                        term.setCursorPos(2,5) term.setTextColor(colors.yellow)
                        term.write("Press any key...")
                        os.pullEvent()
                    end
                end
            end
        end
    end
end

-- ── Loop principal (preserva parallel + food delivery do original) ───────────
parallel.waitForAny(
    function()
        while true do
            if not tryRestoreSession() then doLogin() end
            if isAdmin then adminMenu() else userMenu() end
            if needsRelogin then
                local chk = httpPost("/session_check", {token=token or ""})
                if chk == nil then
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                    term.setCursorPos(1,1) term.clearLine() term.write(" Server Offline")
                    term.setBackgroundColor(colors.black)
                    term.setCursorPos(2,3) term.setTextColor(colors.yellow) term.write("Tunnel unreachable.")
                    term.setCursorPos(2,4) term.setTextColor(colors.gray)  term.write("Sessão mantida.")
                    term.setCursorPos(2,5) term.write("Pressione qualquer tecla para reconectar...")
                    os.pullEvent()
                    needsRelogin = false
                else
                    clearSession()
                    needsRelogin = false
                    token=nil username=nil isAdmin=false
                end
            end
        end
    end,
    function()
        while true do
            sleep(60)
            checkAndDeliverFood()
        end
    end
)
]])

-- ─── 5. Escreve e executa instância ───────────────────────────────────────────
local out = fs.open(INSTANCE, "w")
out.write(stripped)
out.write("\n")
out.write(table.concat(inject, "\n"))
out.close()

shell.run(INSTANCE)
