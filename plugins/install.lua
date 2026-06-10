-- CC-Cloud-Plugins Installer v3
-- Usage: install  (first time or update)
-- As plugin (priority=0): silent update check on boot

-- !! Mode check FIRST !!
local _isPlugin = _G._cloudPluginLoad == true

local plugin        = {}
plugin.name         = "installer"
plugin.label        = "installer"
plugin.patch        = true
plugin.priority     = 0

local silentCheck   -- forward declared

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
local REPO       = "lux-silver/CC-Cloud-Plugins"
local BRANCH     = "main"
local RAW_BASE   = "https://raw.githubusercontent.com/"..REPO.."/"..BRANCH.."/"
local API_BASE   = "https://api.github.com/repos/"..REPO.."/git/trees/"..BRANCH.."?recursive=1"
local BACKUP_DIR = "backup"

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

-- ── File helpers ──────────────────────────────────────────────────────────────
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r") local s=f.readAll() f.close() return s
end
local function writeFile(path, content)
    local dir=fs.getDir(path)
    if dir~="" and not fs.isDir(dir) then fs.makeDir(dir) end
    local f=fs.open(path,"w") f.write(content) f.close()
end
local function backupFile(path)
    if not fs.exists(path) then return end
    if not fs.isDir(BACKUP_DIR) then fs.makeDir(BACKUP_DIR) end
    local name=path:gsub("/","_")
    local n=1
    while fs.exists(BACKUP_DIR.."/"..name.."."..n) do n=n+1 end
    fs.copy(path, BACKUP_DIR.."/"..name.."."..n)
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
    local ok,err=http.get(RAW_BASE..path)
    if not ok then return nil,tostring(err) end
    local c=ok.readAll() ok.close() return c
end

local function fetchTree()
    local res=http.get(API_BASE)
    if not res then return nil end
    local raw=res.readAll() res.close()
    local files={}
    for path in raw:gmatch('"path"%s*:%s*"([^"]+)"') do
        if path:match("%.lua$")
           and not path:match("^install%.lua$")
           and not path:match("^plugins/install%.lua$") then
            table.insert(files, path)
        end
    end
    return #files>0 and files or nil
end

-- ── UI ────────────────────────────────────────────────────────────────────────
local W,H = term.getSize()
local BAR_ROW = math.floor(H/2)
local LOG_ROW = BAR_ROW+2
local logLines = {}

local function initUI()
    W,H=term.getSize()
    BAR_ROW=math.floor(H/2) LOG_ROW=BAR_ROW+2
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
    term.setCursorPos(1,1) term.clearLine()
    term.write(" CC-Cloud-Plugins Installer v3")
    term.setBackgroundColor(colors.black)
end

local function drawBar(done, total, label)
    local BW=W-4
    local filled=total>0 and math.floor(done/total*BW) or 0
    filled=math.max(0,math.min(filled,BW))
    term.setCursorPos(2,BAR_ROW-1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+"..string.rep("-",BW).."+")
    term.setCursorPos(2,BAR_ROW)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    if filled>0 then
        term.setBackgroundColor(colors.green) term.setTextColor(colors.green)
        term.write(string.rep(" ",filled))
    end
    if BW-filled>0 then
        term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
        term.write(string.rep(" ",BW-filled))
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    term.setCursorPos(2,BAR_ROW+1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+"..string.rep("-",BW).."+")
    local pct=total>0 and math.floor(done/total*100) or 0
    local txt=pct.."% "..(label or "") txt=txt:sub(1,W)
    term.setCursorPos(math.floor((W-#txt)/2)+1,BAR_ROW-2)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.clearLine() term.write(txt)
end

local function log(msg, fg)
    table.insert(logLines,{msg=msg,fg=fg or colors.white})
    local maxL=H-LOG_ROW
    while #logLines>maxL do table.remove(logLines,1) end
    for i,line in ipairs(logLines) do
        local row=LOG_ROW+i-1
        if row<=H then
            term.setCursorPos(1,row)
            term.setBackgroundColor(colors.black) term.setTextColor(line.fg)
            term.clearLine() term.write(" "..line.msg:sub(1,W-1))
        end
    end
end

-- ── Install logic ─────────────────────────────────────────────────────────────
local function processFiles(files, ui)
    local updated,skipped,failed=0,0,0
    local ts=now()
    for i,path in ipairs(files) do
        if ui then drawBar(i-1,#files,path) log("Checking "..path,colors.gray) end
        local remote,err=download(path)
        if not remote then
            if ui then log("FAIL: "..path.." ("..(err or "?")..")",colors.red) end
            failed=failed+1
        else
            local local_=readFile(path)
            local lc=stripTS(local_) local rc=stripTS(remote)
            local same=lc and lc:gsub("%s+$","")==rc:gsub("%s+$","")
            if same then
                if ui then log("Up to date: "..path,colors.gray) end
                skipped=skipped+1
                writeFile(path,injectTS(rc,ts))
            else
                if local_ then backupFile(path) end
                writeFile(path,injectTS(rc,ts))
                updated=updated+1
                if ui then
                    log((local_ and "Updated: " or "Installed: ")..path,colors.lime)
                end
            end
        end
        if ui then drawBar(i,#files,path) os.sleep(0.05) end
    end
    return updated,skipped,failed
end

-- ── Silent check (for preBoot) ────────────────────────────────────────────────
silentCheck = function()
    local files=fetchTree() or FALLBACK
    local updated,_,_=processFiles(files,false)
    return updated
end

-- ── Main UI (direct run) ──────────────────────────────────────────────────────
initUI()
drawBar(0,1,"Fetching file list...")
log("Connecting to GitHub...",colors.gray)

local files=fetchTree()
if not files then
    log("API failed — using fallback list",colors.yellow)
    files=FALLBACK
end
log("Found "..#files.." file(s)",colors.lime)

local updated,skipped,failed=processFiles(files,true)

drawBar(#files,#files,"Done!")
log("",colors.black)
log("Updated   : "..updated, colors.lime)
log("Up to date: "..skipped, colors.white)
if failed>0 then log("Failed    : "..failed, colors.red) end
log("",colors.black)
log(updated>0 and "Run 'cloud' to start." or "Everything up to date.",
    updated>0 and colors.yellow or colors.white)

term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
term.setTextColor(colors.gray) term.write(" Press any key to exit...")
os.pullEvent("key")
term.setBackgroundColor(colors.black) term.clear()

return plugin
