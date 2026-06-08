-- Settings Plugin v1 (CORRIGIDO: Aplica cor de verdade)
local plugin  = {}
plugin.name   = "settings"
plugin.label  = "Settings"
plugin.patch  = false

-- ── Patch: Modifica o clickMenu para usar a cor do tema ──────────────────────
local function patchClickMenuColor()
    -- Busca o clickMenu do ambiente global
    local target = _G.clickMenu or clickMenu
    if not target then return end
    if _G._origClickMenu then return end -- evita loops infinitos

    _G._origClickMenu = target
    
    -- Substitui o clickMenu por uma versão que intercepta as cores
    _G.clickMenu = function(title, items, msg)
        -- Fazemos um patch temporário no term.setBackgroundColor durante o desenho
        local origSetBG = term.setBackgroundColor
        term.setBackgroundColor = function(color)
            -- Se o sistema tentar pintar algo com azul padrão (cabeçalho),
            -- e nós tivermos uma cor customizada, trocamos a cor!
            if color == colors.blue and _G.cloudThemeColor then
                origSetBG(_G.cloudThemeColor)
            else
                origSetBG(color)
            end
        end

        -- Executa o menu original com o nosso modificador de cor ativo
        local res = _G._origClickMenu(title, items, msg)

        -- Restaura a função original do terminal logo após fechar o menu
        term.setBackgroundColor = origSetBG
        return res
    end
end

-- ── Main Screen ───────────────────────────────────────────────────────────────
function plugin.run()
    patchClickMenuColor()

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

-- ── Self-register built-in settings ──────────────────────────────────────────
local registered = false
local _origRun = plugin.run

plugin.run = function()
    local api = _G.configAPI or configAPI
    if not registered and api then
        registered = true

        -- Tema de Cor
        api.register({
            plugin   = "Cloud Theme",
            key      = "theme.headerColor",
            label    = "Header Color",
            type     = "color",
            default  = colors.blue,
            onChange = function(v)
                _G.cloudThemeColor = v
                patchClickMenuColor()
            end,
        })

        -- Nickname
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
