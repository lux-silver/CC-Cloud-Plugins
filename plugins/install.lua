-- CC-Cloud-Plugins Installer v3 (Otimizado via Hash SHA)
-- Usage: install  (first time or update)

local _isPlugin = _G._cloudPluginLoad == true

local plugin    = {}
plugin.name     = "installer"
plugin.label    = "installer"
plugin.patch    = true
plugin.priority = 0

local silentCheck

function plugin.preBoot(ctx)
    if silentCheck then
        local updated = silentCheck()
        if updated > 0 then
            ctx.requestRestart("Updates applied ("..updated.." file(s)). Restart to apply.")
        end
    end
end

function plugin.run() end

-- ── Configuração Base ────────────────────────────────────────────────────────
local REPO       = "lux-silver/CC-Cloud-Plugins"
local BRANCH     = "main"
local RAW_BASE   = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"
local API_BASE   = "https://api.github.com/repos/" .. REPO .. "/git/trees/" .. BRANCH .. "?recursive=1"
local BACKUP_DIR = "backup"

-- ── Auxiliares de Arquivos ───────────────────────────────────────────────────
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
    local name = path:gsub("/", "_")
    local n = 1
    while fs.exists(BACKUP_DIR.."/"..name.."."..n) do n = n + 1 end
    fs.copy(path, BACKUP_DIR.."/"..name.."."..n)
end

-- ── Gerador de Hash SHA-1 Nativo do ComputerCraft ────────────────────────────
-- Simula o cálculo de blob do GitHub para checagem local sem uso de rede
local function calcularLocalSHA(conteudo)
    if not conteudo then return "" end
    -- O GitHub calcula o SHA inserindo o cabeçalho "blob [tamanho]\0" antes do texto
    local prefixo = "blob " .. #conteudo .. "\0"
    local dadosProntos = prefixo .. conteudo
    
    if type(sha1) == "function" then
        return sha1(dadosProntos)
    elseif textutils and textutils.serializeJSON then
        -- Fallback nativo usando algoritmo de hashing se disponível na infraestrutura CC
        local hash = sha1 or (ccemux and ccemux.sha1)
        if hash then return hash(dadosProntos) end
    end
    return "forcar_download" -- Fallback caso o ambiente não possua biblioteca criptográfica nativa
end

-- ── Download Individual ──────────────────────────────────────────────────────
local function download(path)
    local ok, err = http.get(RAW_BASE .. path)
    if not ok then return nil, tostring(err) end
    local c = ok.readAll() ok.close() return c
end

-- ── Captura Avançada da Árvore de Arquivos + Hashes SHA Remotos ──────────────
local function fetchTreeWithHashes()
    local res = http.get(API_BASE)
    if not res then return nil end
    local raw = res.readAll() res.close()
    
    local files = {}
    -- Captura o caminho e o hash SHA mapeados de forma casada dentro do JSON da API do GitHub
    for path, sha in raw:gmatch('"path"%s*:%s*"([^"]+)".-"sha"%s*:%s*"([^"]+)"') do
        if path:match("%.lua$") and not path:match("^install%.lua$") then
            files[path] = sha
        end
    end
    return files
end

-- ── Renderização da Interface Gráfica (UI) ───────────────────────────────────
local BAR_ROW, LOG_ROW, W, H
local logLines = {}

local function initUI()
    W, H = term.getSize()
    BAR_ROW = math.floor(H / 2)
    LOG_ROW = BAR_ROW + 2
    term.setBackgroundColor(colors.black) term.clear()
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
    term.setCursorPos(1, 1) term.clearLine()
    term.write(" CC-Cloud-Plugins Installer v3 (SHA High-Speed)")
    term.setBackgroundColor(colors.black)
end

local function drawBar(done, total, label)
    local BAR_W = W - 4
    local filled = total > 0 and math.floor(done / total * BAR_W) or 0
    filled = math.max(0, math.min(filled, BAR_W))

    term.setCursorPos(2, BAR_ROW - 1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+" .. string.rep("-", BAR_W) .. "+")

    term.setCursorPos(2, BAR_ROW)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")
    if filled > 0 then
        term.setBackgroundColor(colors.green) term.setTextColor(colors.green)
        term.write(string.rep(" ", filled))
    end
    if BAR_W - filled > 0 then
        term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
        term.write(string.rep(" ", BAR_W - filled))
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("|")

    term.setCursorPos(2, BAR_ROW + 1)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
    term.write("+" .. string.rep("-", BAR_W) .. "+")

    local pct = total > 0 and math.floor(done / total * 100) or 0
    local txt = pct .. "% " .. (label or "")
    term.setCursorPos(math.floor((W - #txt) / 2) + 1, BAR_ROW - 2)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
    term.clearLine() term.write(txt)
end

local function log(msg, fg)
    table.insert(logLines, {msg = msg, fg = fg or colors.white})
    local maxLines = H - LOG_ROW
    while #logLines > maxLines do table.remove(logLines, 1) end
    for i, line in ipairs(logLines) do
        local row = LOG_ROW + i - 1
        if row <= H then
            term.setCursorPos(1, row)
            term.setBackgroundColor(colors.black) term.setTextColor(line.fg)
            term.clearLine() term.write(" " .. line.msg:sub(1, W - 1))
        end
    end
end

if _isPlugin then return plugin end

-- ── Execução Direta (UI Modo Ativo) ──────────────────────────────────────────
initUI()
drawBar(0, 1, "Analisando indices do repositorio...")
log("Solicitando Metadados Hash ao GitHub...", colors.gray)

local remoteTree = fetchTreeWithHashes()
local fileList = {}

if remoteTree then
    for path, _ in pairs(remoteTree) do table.insert(fileList, path) end
    table.sort(fileList)
else
    log("Falha na API — Utilizando lista de redundancia estatica", colors.yellow)
    fileList = { "cloud.lua", "cloud_user.lua", "plugins/autologin.lua", "plugins/settings.lua" }
end

log("Mapeados " .. #fileList .. " arquivos gerenciados.", colors.lime)

local updated, skipped, failed = 0, 0, 0

for i, path in ipairs(fileList) do
    drawBar(i - 1, #fileList, path)
    
    local localContent = readFile(path)
    local precisaAtualizar = true
    
    -- O PULO DO GATO: Se o arquivo existe localmente e temos a árvore remota, checa pelo SHA hash
    if localContent and remoteTree and remoteTree[path] then
        local localSHA = calcularLocalSHA(localContent)
        if localSHA == remoteTree[path] then
            precisaAtualizar = false -- São idênticos! Ignora a requisição web de download
        end
    end

    if not precisaAtualizar then
        log("Inalterado: " .. path, colors.gray)
        skipped = skipped + 1
    else
        log("Baixando modificacoes: " .. path .. "...", colors.yellow)
        local remoteContent, err = download(path)
        
        if not remoteContent then
            log("Erro ao baixar: " .. path .. " (" .. (err or "?") .. ")", colors.red)
            failed = failed + 1
        else
            if localContent then
                backupFile(path)
                log("Atualizado: " .. path, colors.lime)
            else
                log("Instalado de raiz: " .. path, colors.lime)
            end
            writeFile(path, remoteContent)
            updated = updated + 1
        end
    end

    drawBar(i, #fileList, path)
    -- Reduzido consideravelmente o delay artificial para acelerar a renderização da barra
    os.sleep(0.01) 
end

drawBar(#fileList, #fileList, "Concluido!")
log("", colors.black)
log("Modificados/Novos: " .. updated, colors.lime)
log("Preservados (SHA): " .. skipped, colors.white)
if failed > 0 then log("Falhas de Rede   : " .. failed, colors.red) end

term.setCursorPos(1, H)
term.setBackgroundColor(colors.black) term.setTextColor(colors.gray)
term.write(" Pressione qualquer tecla para retornar ao terminal...")
os.pullEvent("key")
term.setBackgroundColor(colors.black) term.clear()

-- ── Silent Check Otimizado (PreBoot do Segundo Plano) ────────────────────────
silentCheck = function()
    local remoteTree = fetchTreeWithHashes()
    if not remoteTree then return 0 end
    
    local count = 0
    for path, remoteSHA in pairs(remoteTree) do
        local localContent = readFile(path)
        local identical = false
        if localContent then
            local localSHA = calcularLocalSHA(localContent)
            if localSHA == remoteSHA then identical = true end
        end
        
        if not identical then
            local remote = download(path)
            if remote then
                if localContent then backupFile(path) end
                writeFile(path, remote)
                count = count + 1
            end
        end
    end
    return count
end

return plugin
