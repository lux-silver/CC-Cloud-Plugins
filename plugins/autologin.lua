-- Autologin Plugin v8 (Injetor de Eventos Virtuais de Teclado)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- 1. Regista os campos normalmente no menu de configurações
    if configAPI then
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.enabled",
            label    = "Enable Autologin",
            type     = "checkbox",
            default  = false,
            onChange = function(v) end,
        })
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.username",
            label    = "Username",
            type     = "text",
            default  = "",
            onChange = function(v) end,
        })
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.password",
            label    = "Password",
            type     = "text",
            default  = "",
            onChange = function(v) end,
        })
    end

    -- 2. Se não estiver ativo no Config, não faz nada
    if not configAPI or not configAPI.get("autologin.enabled") then
        return
    end

    local user = tostring(configAPI.get("autologin.username") or "")
    local pass = tostring(configAPI.get("autologin.password") or "")
    if user == "" or pass == "" then return end

    -- 3. SOLUÇÃO DE INJEÇÃO EM PARALELO (Ignora totalmente a Sandbox)
    -- Criamos uma thread nativa no OS que espera a tela abrir e "digita" os teus dados
    local function simularDigitacaoEEnter()
        sleep(0.5) -- Aguarda a tela de login desenhar e focar no campo Username
        
        -- Digita o Usuário
        for i = 1, #user do
            os.queueEvent("char", string.sub(user, i, i))
            sleep(0.05)
        end
        sleep(0.2)
        
        -- Avança para o campo Password (Envia a tecla TAB ou ENTER dependendo do teu OS)
        os.queueEvent("key", keys.tab, false)
        sleep(0.2)
        
        -- Digita a Senha
        for i = 1, #pass do
            os.queueEvent("char", string.sub(pass, i, i))
            sleep(0.05)
        end
        sleep(0.2)
        
        -- Envia o ENTER final para disparar o botão de Login!
        os.queueEvent("key", keys.enter, false)
    end

    -- Dispara a simulação em background de forma assíncrona
    local antigaRotina = os.pullEvent
    _G.os.pullEvent = function(targetEvent)
        -- Na primeira vez que o sistema tentar ler um evento do teclado/mouse,
        -- nós injetamos a nossa sequência fantasma de digitação
        if not _G.autologin_disparado then
            _G.autologin_disparado = true
            -- Inicia a nossa função paralela sem travar a thread principal
            local co = coroutine.create(simularDigitacaoEEnter)
            coroutine.resume(co)
        end
        return antigaRotina(targetEvent)
    end
end

return plugin
