-- Settings Plugin v1 (CORRIGIDO PARA MENU PRINCIPAL)
-- Menu plugin: opens settings screen with all registered configs
-- Also registers built-in settings: theme color + log nickname
-- Place at: plugins/settings.lua

local plugin  = {}
plugin.name   = "settings"
plugin.label  = "Settings"
plugin.patch  = true   -- AGORA É TRUE: Injeta logo no boot do sistema!
plugin.priority = 2    -- Roda logo a seguir à config_api

-- ── Patch Real: Intercetar o clickMenu global no momento do boot ──────────────
local function patchClickMenuColor()
    -- Procura o clickMenu onde quer que ele esteja
    local target = _G.clickMenu or clickMenu
    if not target then return end
    if _G._origClickMenu then return end -- Evita duplicar o patch

    _G._origClickMenu = target
    
    -- Substitui a função global para que afete o menu principal e secundários
    _G.clickMenu = function(title, items, msg)
        local origSetBG = term.setBackgroundColor
        
        -- Substitui temporariamente o term.setBackgroundColor do terminal inteiro
        term.setBackgroundColor = function(color)
            -- Se o menu tentar pintar com azul padrão e houver cor customizada guardada:
            if color == colors.blue and _G.cloudThemeColor then
                origSetBG(_G.cloudThemeColor)
            else
                origSetBG(color)
            end
        end

        -- Executa o menu original (Menu Principal, Vault, Log, etc.) com a nova cor
        local res = _G._origClickMenu(title, items, msg)

        -- Devolve a função original ao terminal após o menu fechar
        term.setBackgroundColor = origSetBG
        return res
    end
end

-- Como agora o patch=true roda automaticamente no boot, usamos a run() 
-- apenas quando o utilizador clica fisicamente no botão "Settings" do menu
function plugin.run()
    local api = _G.configAPI or configAPI
    if not api then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setTextColor(colors.red)
        term.write("config_api.lua not found!")
        os.pullEvent("key")
        return
    end

    api.settingsScreen()
end

-- ── Self-register built-in settings (Corre imediatamente no boot) ─────────────
local registered = false

-- Esta função vai ser injetada pelo Cloud Launcher no carregamento dos plugins
local function initSettings()
    local api = _G.configAPI or configAPI
    if not registered and api then
        registered = true

        -- Registo do Slider/Picker do Tema de Cor
        api.register({
            plugin   = "Cloud Theme",
            key      = "theme.headerColor",
            label    = "Header Color",
            type     = "color",
            default  = colors.blue,
            onChange = function(v)
                _G.cloudThemeColor = v
                patchClickMenuColor() -- Atualiza as cores do gancho imediatamente
            end,
        })

        -- Registo do Nickname
        api.register({
            plugin   = "Cloud Theme",
            key      = "theme.nickname",
            label    = "Nickname",
            type     = "text",
            default  = "",
            onChange = function(v)
                _G.cloudDisplayName = (v and v ~= "") and v or nil
            end,
        })
        
        -- Aplica o patch inicial com a cor recuperada do ficheiro de configuração
        patchClickMenuColor()
    end
end

-- Forçamos a execução do gancho assim que o ficheiro é lido pelo Launcher
pcall(initSettings)

return plugin
