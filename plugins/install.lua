-- CC-Cloud-Plugins Installer v1
-- Run once: install everything from GitHub
-- Run again: checks for updates and applies them

local REPO     = "lux-silver/CC-Cloud-Plugins"
local BRANCH   = "main"
local RAW_BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"
local API_BASE = "https://api.github.com/repos/" .. REPO .. "/git/trees/" .. BRANCH .. "?recursive=1"
local BACKUP_DIR = "backup"

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local s = f.readAll()
    f.close()
    return s
end

local function writeFile(path, content)
    -- ensure parent dir exists
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.isDir(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    f.write(content)
    f.close()
end

local function backupFile(path)
    if not fs.exists(path) then return end
    if not fs.isDir(BACKUP_DIR) then fs.makeDir(BACKUP_DIR) end
    local name = path:gsub("/", "_")
    local n = 1
    while fs.exists(BACKUP_DIR .. "/" .. name .. "." .. n) do n = n + 1 end
    fs.copy(path, BACKUP_DIR .. "/" .. name .. "." .. n)
end

local function download(path)
    -- returns content string or nil
    local url = RAW_BASE .. path
    local ok, err = http.get(url)
    if not ok then return nil, err end
    local content = ok.readAll()
    ok.close()
    return content
end

local function same(a, b)
    -- compare ignoring trailing newline differences
    if a == nil or b == nil then return false end
    return a:gsub("%s+$","") == b:gsub("%s+$","")
end

-- ── Fetch file tree from GitHub API ──────────────────────────────────────────
local function fetchTree()
    print("Fetching file list from GitHub...")
    local res, err = http.get(API_BASE)
    if not res then
        print("Error fetching tree: " .. tostring(err))
        return nil
    end
    local raw = res.readAll()
    res.close()

    -- parse JSON manually (no json lib in CC)
    -- extract all "path":"..." entries that are blobs (files)
    local files = {}
    for path in raw:gmatch('"path"%s*:%s*"([^"]+)"') do
        -- skip README and non-lua root files we don't need to install
        if path:match("%.lua$") then
            table.insert(files, path)
        end
    end
    return files
end

-- ── Main ──────────────────────────────────────────────────────────────────────
print("=== CC-Cloud-Plugins Installer ===")
print("")

local files = fetchTree()
if not files or #files == 0 then
    print("Could not get file list. Check your internet connection.")
    print("Trying known files as fallback...")
    -- hardcoded fallback in case API is unavailable
    files = {
        "cloud.lua",
        "cloud_user.lua",
        "plugins/multiselect.lua",
        "plugins/autologin.lua",
        "plugins/chess.lua",
         "plugins/",
    }
end

print("Found " .. #files .. " file(s)")
print("")

local updated = 0
local skipped = 0
local failed  = 0

for _, path in ipairs(files) do
    io.write("  " .. path .. " ... ")

    local remote, err = download(path)
    if not remote then
        print("FAIL (" .. tostring(err) .. ")")
        failed = failed + 1
    else
        local local_ = readFile(path)
        if same(local_, remote) then
            print("ok (up to date)")
            skipped = skipped + 1
        else
            if local_ then
                backupFile(path)
                print("updated (backup saved)")
            else
                print("installed")
            end
            writeFile(path, remote)
            updated = updated + 1
        end
    end
end

print("")
print("Done!")
print("  Installed/Updated : " .. updated)
print("  Already up to date: " .. skipped)
if failed > 0 then
    print("  Failed            : " .. failed)
end
print("")
if updated > 0 then
    print("Changes applied. Run 'cloud' to start.")
else
    print("Everything is up to date.")
end
