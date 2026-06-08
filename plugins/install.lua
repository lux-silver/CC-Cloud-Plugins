-- CC-Cloud-Plugins Installer v2
-- Usage: install  (first time or update)

local REPO     = "lux-silver/CC-Cloud-Plugins"
local BRANCH   = "main"
local RAW_BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"
local API_BASE = "https://api.github.com/repos/" .. REPO .. "/git/trees/" .. BRANCH .. "?recursive=1"
local BACKUP_DIR = "backup"

-- timestamp injected at end of every managed file:  -- @installed:NNNNNNNNNN
local TS_PAT  = "%-%-%-? ?@installed:(%d+)"
local TS_LINE = "\n-- @installed:%d"

local function now() return math.floor(os.epoch("utc") / 1000) end

-- ── File helpers ──────────────────────────────────────────────────────────────
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r") local s = f.readAll() f.close() return s
end
local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.isDir(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w") f.write(content) f.close()
end
local function backupFile(path)
    if not fs.exists(path) then return end
    if not fs.isDir(BACKUP_DIR) then fs.makeDir(BACKUP_DIR) end
    local name = path:gsub("/","_")
    local n = 1
    while fs.exists(BACKUP_DIR.."/"..name.."."..n) do n=n+1 end
    fs.copy(path, BACKUP_DIR.."/"..name.."."..n)
end

-- strip existing timestamp from content
local function stripTS(s)
    if not s then return s end
    return s:gsub("\n%-%- @installed:%d+%s*$",""):gsub("\n%-%- @installed:%d+","")
end
-- get timestamp embedded in file
local function getTS(s)
    if not s then return nil end
    local ts = s:match("%-%-.-@installed:(%d+)")
    return ts and tonumber(ts) or nil
end
-- inject timestamp at end
local function injectTS(s, ts)
    return stripTS(s) .. "\n-- @installed:" .. tostring(ts)
end

-- ── Download ──────────────────────────────────────────────────────────────────
local function download(path)
    local ok, err = http.get(RAW_BASE .. path)
    if not ok then return nil, tostring(err) end
    local c = ok.readAll() ok.close() return c
end

-- ── GitHub tree ───────────────────────────────────────────────────────────────
local function fetchTree()
    local res, err = http.get(API_BASE)
    if not res then return nil end
    local raw = res.readAll() res.close()
    local files = {}
    for path in raw:gmatch('"path"%s*:%s*"([^"]+)"') do
        if path:match("%.lua$") and not path:match("^install%.lua$") then
            table.insert(files, path)
        end
    end
    return #files > 0 and files or nil
end

-- ── Progress bar ─────────────────────────────────────────────────────────────
-- Minecraft-style: green filled + gray empty, white border
-- drawn at fixed row in center of screen

local BAR_ROW   -- set after term size known
local LOG_ROW   -- prints start here (below bar)
local logLines  = {}
local W, H

local function initUI()
    W, H = term.getSize()
    BAR_ROW  = math.floor(H / 2)
    LOG_ROW  = BAR_ROW + 2
    term.setBackgroundColor(colors.black) term.clear()
    -- title
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
    term.setCursorPos(1,1) term.clearLine()
    term.write(" CC-Cloud-Plugins Installer v2")
    term.setBackgroundColor(colors.black)
end

local function drawBar(done, total, label)
    local BAR_W = W - 4  -- 2 border + 1 pad each side
    local filled = total > 0 and math.floor(done / total * BAR_W) or 0
    filled = math.max(0, math.min(filled, BAR_W))

    -- border row above
    term.setCursorPos(2, BAR_ROW - 1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+" .. string.rep("-", BAR_W) .. "+")

    -- bar itself
    term.setCursorPos(2, BAR_ROW)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    -- filled (green)
    if filled > 0 then
        term.setBackgroundColor(colors.green) term.setTextColor(colors.green)
        term.write(string.rep(" ", filled))
    end
    -- empty (gray)
    if BAR_W - filled > 0 then
        term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
        term.write(string.rep(" ", BAR_W - filled))
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")

    -- border row below
    term.setCursorPos(2, BAR_ROW + 1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+" .. string.rep("-", BAR_W) .. "+")

    -- percent + label centered above bar
    local pct = total > 0 and math.floor(done / total * 100) or 0
    local txt = pct .. "% " .. (label or "")
    txt = txt:sub(1, W)
    term.setCursorPos(math.floor((W - #txt) / 2) + 1, BAR_ROW - 2)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.clearLine() term.write(txt)
end

local function log(msg, fg)
    table.insert(logLines, {msg=msg, fg=fg or colors.white})
    -- keep only as many lines as fit below bar
    local maxLines = H - LOG_ROW
    while #logLines > maxLines do table.remove(logLines, 1) end
    -- redraw log area
    for i, line in ipairs(logLines) do
        local row = LOG_ROW + i - 1
        if row <= H then
            term.setCursorPos(1, row)
            term.setBackgroundColor(colors.black) term.setTextColor(line.fg)
            term.clearLine() term.write(" " .. line.msg:sub(1, W-1))
        end
    end
end

-- ── Main ──────────────────────────────────────────────────────────────────────
initUI()
drawBar(0, 1, "Fetching file list...")
log("Connecting to GitHub...", colors.gray)

local files = fetchTree()
if not files then
    log("API failed — using fallback list", colors.yellow)
    files = {
        "cloud.lua",
        "cloud_user.lua",
        "plugins/multiselect.lua",
        "plugins/autologin.lua",
        "plugins/chess.lua",
    }
end

log("Found " .. #files .. " file(s)", colors.lime)

local updated = 0
local skipped = 0
local failed  = 0
local ts = now()

for i, path in ipairs(files) do
    drawBar(i - 1, #files, path)
    log("Checking " .. path .. "...", colors.gray)

    local remote, err = download(path)
    if not remote then
        log("FAIL: " .. path .. " (" .. (err or "?") .. ")", colors.red)
        failed = failed + 1
    else
        local local_ = readFile(path)
        local localTS  = getTS(local_)
        local remoteClean = stripTS(remote)

        -- compare: strip timestamps from both before comparing content
        local localClean = stripTS(local_)
        local same = localClean and localClean:gsub("%s+$","") == remoteClean:gsub("%s+$","")

        if same then
            log("Up to date: " .. path, colors.gray)
            skipped = skipped + 1
            -- refresh timestamp so we know when it was last checked
            writeFile(path, injectTS(remoteClean, ts))
        else
            if local_ then
                backupFile(path)
                log("Updated: " .. path, colors.lime)
            else
                log("Installed: " .. path, colors.lime)
            end
            writeFile(path, injectTS(remoteClean, ts))
            updated = updated + 1
        end
    end

    drawBar(i, #files, path)
    os.sleep(0.05)  -- small delay so bar is visible
end

drawBar(#files, #files, "Done!")
log("", colors.black)
log("Updated  : " .. updated, colors.lime)
log("Up to date: " .. skipped, colors.white)
if failed > 0 then
    log("Failed   : " .. failed, colors.red)
end
log("", colors.black)
if updated > 0 then
    log("Run 'cloud' to start.", colors.yellow)
else
    log("Everything up to date. Run 'cloud'.", colors.white)
end

-- wait for key
term.setCursorPos(1, H)
term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
term.write(" Press any key to exit...")
os.pullEvent("key")
term.setBackgroundColor(colors.black) term.clear()
