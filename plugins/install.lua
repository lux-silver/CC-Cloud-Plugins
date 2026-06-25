-- CC-Cloud-Plugins Installer v4
-- Usage: install  (first time or update)
-- As plugin (priority=0): silent update check on boot
--
-- Per-file status (saved in .install_rules):
--   "allow"  (default) → instala e atualiza normalmente  [verde]
--   "freeze"           → mantém o arquivo atual, ignora atualizações [amarelo]
--   "block"            → deleta o arquivo e nunca instala de novo [vermelho]

local _isPlugin = _G._cloudPluginLoad == true

local plugin        = {}
plugin.name         = "installer"
plugin.label        = "installer"
plugin.patch        = true
plugin.priority     = 0

local silentCheck

function plugin.preBoot(ctx)
    if not silentCheck then return end
    local updated = silentCheck()
    if updated > 0 then
        ctx.requestRestart("Updates applied ("..updated.." file(s)). Restart to apply.")
    end
end

function plugin.run() end

if _isPlugin then return plugin end

-- ── Constants ─────────────────────────────────────────────────────────────────
local REPO      = "lux-silver/CC-Cloud-Plugins"
local BRANCH    = "main"
local RAW_BASE  = "https://raw.githubusercontent.com/"..REPO.."/"..BRANCH.."/"
local API_BASE  = "https://api.github.com/repos/"..REPO.."/git/trees/"..BRANCH.."?recursive=1"
local RULES_FILE = ".install_rules"

local FALLBACK = {
    "cloud.lua",
    "plugins/autologin.lua",
    "plugins/chess.lua",
    "plugins/config_api.lua",
    "plugins/multiselect.lua",
    "plugins/settings.lua",
    "plugins/theme.lua",
}

local function now() return math.floor(os.epoch("utc") / 1000) end

-- ── Rules persistence ─────────────────────────────────────────────────────────
-- rules[path] = "allow" | "freeze" | "block"
local rules = {}

local function loadRules()
    if not fs.exists(RULES_FILE) then return end
    local f = fs.open(RULES_FILE, "r"); local raw = f.readAll(); f.close()
    local t = textutils.unserialise(raw)
    if type(t) == "table" then rules = t end
end

local function saveRules()
    local f = fs.open(RULES_FILE, "w")
    f.write(textutils.serialise(rules))
    f.close()
end

local function getRule(path)
    return rules[path] or "allow"
end

-- ── File helpers ──────────────────────────────────────────────────────────────
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path,"r"); local s = f.readAll(); f.close(); return s
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.isDir(dir) then fs.makeDir(dir) end
    local f = fs.open(path,"w"); f.write(content); f.close()
end

local function stripTS(s)
    if not s then return s end
    return s:gsub("\n%-%- @installed:%d+%s*$",""):gsub("\n%-%- @installed:%d+","")
end

local function injectTS(s, ts)
    return stripTS(s).."\n-- @installed:"..tostring(ts)
end

-- ── Network ───────────────────────────────────────────────────────────────────
local function download(path)
    local ok, err = http.get(RAW_BASE..path)
    if not ok then return nil, tostring(err) end
    local c = ok.readAll(); ok.close(); return c
end

local function fetchTree()
    local res = http.get(API_BASE)
    if not res then return nil end
    local raw = res.readAll(); res.close()
    local files = {}
    for path in raw:gmatch('"path"%s*:%s*"([^"]+)"') do
        if path:match("%.lua$")
           and not path:match("^install%.lua$")
           and not path:match("^plugins/install%.lua$") then
            table.insert(files, path)
        end
    end
    return #files > 0 and files or nil
end

-- ── UI ────────────────────────────────────────────────────────────────────────
local W, H = term.getSize()

local function initUI()
    W, H = term.getSize()
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
    term.setCursorPos(1,1) term.clearLine()
    term.write(" CC-Cloud-Plugins Installer v4")
    term.setBackgroundColor(colors.black)
end

local function drawBar(done, total, label)
    local BW = W - 4
    local filled = total > 0 and math.floor(done/total*BW) or 0
    filled = math.max(0, math.min(filled, BW))
    local BAR_ROW = math.floor(H/2)
    term.setCursorPos(2, BAR_ROW-1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+"..string.rep("-",BW).."+")
    term.setCursorPos(2, BAR_ROW)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    if filled > 0 then
        term.setBackgroundColor(colors.green) term.write(string.rep(" ",filled))
    end
    if BW-filled > 0 then
        term.setBackgroundColor(colors.gray) term.write(string.rep(" ",BW-filled))
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    term.setCursorPos(2, BAR_ROW+1)
    term.write("+"..string.rep("-",BW).."+")
    local pct = total > 0 and math.floor(done/total*100) or 0
    local txt = pct.."% "..(label or ""); txt = txt:sub(1, W)
    term.setCursorPos(math.floor((W-#txt)/2)+1, BAR_ROW-2)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.clearLine() term.write(txt)
end

-- ── Process files (install/update/block/freeze) ───────────────────────────────
-- Returns list of result entries: {path, status, rule, hasUpdate}
--   status: "installed" | "updated" | "uptodate" | "blocked" | "frozen" | "failed"
local function processFiles(files, ui)
    local ts = now()
    local results = {}
    for i, path in ipairs(files) do
        -- install.lua never overwrites itself — always skip
        if path:match("^install%.lua$") or path:match("^plugins/install%.lua$") then
            if ui then drawBar(i, #files, path) end
            goto continue
        end

        local rule = getRule(path)

        -- BLOCK: delete file if exists, skip download
        if rule == "block" then
            if fs.exists(path) then fs.delete(path) end
            table.insert(results, {path=path, status="blocked", rule="block"})
            if ui then drawBar(i, #files, path) end
        else
            -- Download remote
            if ui then drawBar(i-1, #files, path) end
            local remote, err = download(path)
            if not remote then
                table.insert(results, {path=path, status="failed", rule=rule, err=err})
            else
                local local_ = readFile(path)
                local lc = stripTS(local_)
                local rc = stripTS(remote)
                local same = lc and lc:gsub("%s+$","") == rc:gsub("%s+$","")
                local hasUpdate = not same

                if rule == "freeze" then
                    -- Don't touch the file — but note if there's an update available
                    if not local_ then
                        -- File doesn't exist yet and is frozen → install once, then freeze
                        writeFile(path, injectTS(rc, ts))
                        table.insert(results, {path=path, status="installed", rule="freeze", hasUpdate=false})
                    else
                        table.insert(results, {path=path, status="frozen", rule="freeze", hasUpdate=hasUpdate})
                    end
                else
                    -- ALLOW: normal install/update
                    if same then
                        writeFile(path, injectTS(rc, ts))  -- refresh timestamp only
                        table.insert(results, {path=path, status="uptodate", rule="allow", hasUpdate=false})
                    else
                        writeFile(path, injectTS(rc, ts))
                        local st = local_ and "updated" or "installed"
                        table.insert(results, {path=path, status=st, rule="allow", hasUpdate=false})
                    end
                end
            end
            if ui then drawBar(i, #files, path); os.sleep(0.05) end
        end
        ::continue::
    end
    return results
end

-- ── Interactive results screen ──────────────────────────────────────────────
local RULE_COLORS  = { allow=colors.lime, freeze=colors.yellow, block=colors.red  }
-- Single char icons using CC block characters
--  = bullet,  = right arrow,  = diamond
local RULE_ICONS   = { allow="", freeze="*", block="" }
local STATUS_COLORS = {
    installed=colors.lime, updated=colors.lime,
    uptodate=colors.gray,  frozen=colors.yellow,
    blocked=colors.red,    failed=colors.red,
}
local STATUS_ICON = {
    installed="+", updated="^", uptodate="=",
    frozen="*",    blocked="x", failed="!",
}

local function shortPath(path, maxW)
    if #path <= maxW then return path end
    local fname = path:match("([^/]+)$") or path
    if #fname >= maxW then return fname:sub(1,maxW) end
    return "»"..path:sub(#path - maxW + 2)  -- » = right guillemet >>
end

local function resultsScreen(results)
    W, H = term.getSize()
    local scroll = 0
    local listH  = H - 4
    local changed = false

    local function draw()
        W, H = term.getSize()
        listH = H - 4
        term.setBackgroundColor(colors.black) term.clear()

        -- ── Header ──────────────────────────────────────────────────────────
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        local hdr = " Installer v4  [" .. #results .. " files]"
        term.write(hdr .. string.rep(" ", W - #hdr))

        -- ── Legend row (compact, fits 26-char wide) ──────────────────────────
        term.setCursorPos(1,2) term.setBackgroundColor(colors.black)
        -- green square
        term.setBackgroundColor(colors.lime)    term.setTextColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.black)   term.setTextColor(colors.lime)  term.write(" update ")
        -- yellow square
        term.setBackgroundColor(colors.yellow)  term.setTextColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.black)   term.setTextColor(colors.yellow) term.write(" freeze ")
        -- red square
        term.setBackgroundColor(colors.red)     term.setTextColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.black)   term.setTextColor(colors.red)   term.write(" block")

        -- ── File list ────────────────────────────────────────────────────────
        for row = 1, listH do
            local idx   = row + scroll
            local entry = results[idx]
            local y     = row + 2
            term.setCursorPos(1, y)
            term.setBackgroundColor(colors.black) term.clearLine()
            if entry then
                local rc  = RULE_COLORS[entry.rule]
                local sc  = STATUS_COLORS[entry.status] or colors.white
                local si  = STATUS_ICON[entry.status] or "?"

                -- Colored rule square (1 char bg)
                term.setBackgroundColor(rc) term.setTextColor(colors.black)
                term.write(" ")
                term.setBackgroundColor(colors.black) term.write(" ")

                -- Status char (shows what happened to file)
                term.setTextColor(sc) term.write(si.." ")

                -- Filename
                local nameW = W - 5
                local label = shortPath(entry.path, nameW)
                if entry.status == "frozen" and entry.hasUpdate then
                    label = shortPath(entry.path, nameW-2) .. " *"
                end
                term.setTextColor(sc) term.write(label)
            end
        end

        -- ── Scroll arrows ────────────────────────────────────────────────────
        if scroll > 0 then
            term.setCursorPos(W, 3)
            term.setBackgroundColor(colors.gray) term.setTextColor(colors.white)
            term.write("")  -- up arrow char
        end
        if scroll + listH < #results then
            term.setCursorPos(W, H-1)
            term.setBackgroundColor(colors.gray) term.setTextColor(colors.white)
            term.write("")  -- down arrow char
        end

        -- ── Footer: single "Confirm" button ──────────────────────────────────
        term.setCursorPos(1, H) term.setBackgroundColor(colors.black) term.clearLine()
        local btnBg = changed and colors.green or colors.lime
        term.setBackgroundColor(btnBg) term.setTextColor(colors.black)
        term.write(" Confirm ")
        term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
        term.write("  click file to cycle rule")
    end

    draw()

    while true do
        local ev, p1, p2, p3 = os.pullEvent()

        if ev == "mouse_click" then
            local mx, my = p2, p3
            -- Confirm button (anywhere on footer row)
            if my == H then
                saveRules(); return
            end
            -- Scroll arrows
            if mx == W and my == 3 and scroll > 0 then
                scroll = scroll - 1; draw()
            elseif mx == W and my == H-1 and scroll + listH < #results then
                scroll = scroll + 1; draw()
            end
            -- File row → cycle rule
            local row = my - 2
            if row >= 1 and row <= listH then
                local idx   = row + scroll
                local entry = results[idx]
                if entry then
                    local cycle  = {allow="freeze", freeze="block", block="allow"}
                    local newRule = cycle[entry.rule] or "allow"
                    entry.rule    = newRule
                    rules[entry.path] = newRule
                    changed = true
                    if newRule == "block" and fs.exists(entry.path) then
                        fs.delete(entry.path)
                        entry.status = "blocked"
                    end
                    draw()
                end
            end

        elseif ev == "mouse_scroll" then
            scroll = math.max(0, math.min(#results - listH, scroll + p1))
            draw()

        elseif ev == "key" then
            if     p1 == keys.up    then scroll = math.max(0, scroll-1); draw()
            elseif p1 == keys.down  then
                scroll = math.min(math.max(0,#results-listH), scroll+1); draw()
            elseif p1 == keys.enter then saveRules(); return
            elseif p1 == keys.q     then saveRules(); return
            end
        end
    end
end

-- ── Silent check (for preBoot) ────────────────────────────────────────────────
silentCheck = function()
    loadRules()
    local files = fetchTree() or FALLBACK
    local results = processFiles(files, false)
    local updated = 0
    for _, r in ipairs(results) do
        if r.status == "updated" or r.status == "installed" then
            updated = updated + 1
        end
    end
    return updated
end

-- ── Main (direct run) ─────────────────────────────────────────────────────────
loadRules()
initUI()
drawBar(0, 1, "Fetching file list...")

local files = fetchTree()
if not files then
    term.setCursorPos(2,4) term.setTextColor(colors.yellow)
    term.write("API failed — using fallback list")
    os.sleep(0.8)
    files = FALLBACK
end

local results = processFiles(files, true)

-- ── Summary screen ────────────────────────────────────────────────────────────
do
    local updated2, uptodate2, frozen2, blocked2, failed2 = 0,0,0,0,0
    for _, r in ipairs(results) do
        if     r.status=="updated"  or r.status=="installed" then updated2  = updated2+1
        elseif r.status=="uptodate"                          then uptodate2 = uptodate2+1
        elseif r.status=="frozen"                            then frozen2   = frozen2+1
        elseif r.status=="blocked"                           then blocked2  = blocked2+1
        elseif r.status=="failed"                            then failed2   = failed2+1
        end
    end

    W,H = term.getSize()
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
    term.setCursorPos(1,1) term.clearLine()
    term.write(" CC-Cloud-Plugins  Done!")
    term.setBackgroundColor(colors.black)

    local y = 3
    local function stat(icon, fg, label, count)
        if count == 0 then return end
        term.setCursorPos(3, y)
        term.setBackgroundColor(fg) term.setTextColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.black) term.setTextColor(fg)
        term.write("  "..label..": "..count)
        y = y + 1
    end
    stat("â ", colors.lime,   "Updated / Installed", updated2)
    stat("â ", colors.gray,   "Up to date",          uptodate2)
    stat("â ", colors.yellow, "Frozen",              frozen2)
    stat("â ", colors.red,    "Blocked / Deleted",   blocked2)
    if failed2 > 0 then
        stat("â ", colors.red, "Failed", failed2)
    end

    y = y + 1
    term.setCursorPos(1, H-1) term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow) term.setCursorPos(2, H-1)
    term.write("[R] Manage rules")
    term.setCursorPos(2, H)
    term.setTextColor(colors.gray)   term.write("Any other key to exit")

    while true do
        local ev, key = os.pullEvent("key")
        if key == keys.r then
            resultsScreen(results)
        end
        break
    end
end

term.setBackgroundColor(colors.black) term.clear()
return plugin
