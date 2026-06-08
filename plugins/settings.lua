-- Settings Plugin v1 (CORRIGIDO)
-- Menu plugin: opens settings screen with all registered configs
-- Also registers built-in settings: theme color + log nickname
-- Place at: plugins/settings.lua

local plugin  = {}
plugin.name   = "settings"
plugin.label  = "Settings"
plugin.patch  = false  -- aparece como entrada no menu

-- ── Patch Real: Interceta o clickMenu para injetar a cor customizada ──────────
local function patchClickMenuColor()
    -- Procura o clickMenu no ambiente correto (global ou local injetado)
    local target = _G.clickMenu or clickMenu
    if not target then return end
    if _G._origClickMenu then return end -- evita loops infinitos se chamado várias vezes

    -- Guarda o ponteiro original para podermos chamar depois
    _G._origClickMenu = target
    
    -- Substitui a função global por um hook dinâmico
    _G.clickMenu = function(title, items, msg)
        -- Guardamos a função original de mudar a cor de fundo do terminal
        local origSetBG = term.setBackgroundColor
        
        -- Substituímos temporariamente o term.setBackgroundColor do computador
        term.setBackgroundColor = function(color)
            -- Sempre que o menu original tentar pintar algo com AZUL (cabeçalho)
            -- e nós tivermos uma cor escolhida nas definições, usamos a nossa cor!
            if color == colors.blue and _G.cloudThemeColor then
                origSetBG(_G.cloudThemeColor)
            else
                origSetBG(color)
            end
        end

        -- Executa o menu original completo com o nosso modificador ativo
        local res = _G._origClickMenu(title, items, msg)

        -- Assim que o menu fecha, devolvemos a função original ao terminal
        term.setBackgroundColor = origSetBG
        return res
    end
end

-- ── Main Screen ───────────────────────────────────────────────────────────────
function plugin.run()
    -- Garante que o patch é aplicado quando entramos no plugin
    patchClickMenuColor()

    local api = _G.configAPI or configAPI
    if not api then
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(1,2) term.setTextColor(colors.red)
        term.write("config_api.lua not found!")
        term.setCursorPos(1,4) term.setTextColor(colors.gray)
        term.write("Add plugins/config_api.lua")
        os.pullEvent("key")
        return
    end

    api.settingsScreen()
end

-- ── Self-register built-in settings (runs at load time) ──────────────────────
local registered = false
local _origRun = plugin.run

plugin.run = function()
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
                patchClickMenuColor() -- Atualiza o injetor imediatamente
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
    end
    _origRun()
end

return plugin
