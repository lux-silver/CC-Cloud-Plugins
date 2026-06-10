-- Autologin Plugin v12 (Tranca de Segurança para Config)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- Função auxiliar para validar a senha real com o servidor via RPC antes de abrir o menu
    local function verificarSenhaSeguranca()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.red)
        term.setCursorPos(1, 2)
        print("=== AREA RESTRITA ===")
        term.setTextColor(colors.white)
        print("Insira a senha do Usuario para alterar as configuracoes:")
        
        term.setCursorPos(1, 5)
        term.write("Senha: ")
        -- Usa o caractere "*" nativo do read para mascarar e ocultar a senha digitada
        local senhaDigitada = read("*")
        
        local userSalvo = configAPI and configAPI.get("autologin.username") or ""
        local rpcFunc = _G.rpc or rpc
        
        if type(rpcFunc) == "function" and userSalvo ~= "" then
            -- Faz uma chamada de teste ao servidor para verificar se a senha está certa
            local res = rpcFunc({ type = "login", username = userSalvo, password = senhaDigitada })
            if res and res.ok then
                return true -- Senha correta, permite acesso ao menu
            end
        end
        
        term.setCursorPos(1, 7)
        term.setTextColor(colors.red)
        print("Senha incorreta! Acesso negado.")
        sleep(2)
        return false
    end

    -- 1. REGISTRO NO CONFIG API (Com interceptor de segurança no clique)
    if configAPI then
        -- Criamos uma armadilha na função que abre o menu de configurações
        if type(configAPI.open) == "function" or type(_G.configAPI.open) == "function" then
            local origOpen = configAPI.open or _G.configAPI.open
            local gerenciadorOpen = function(...)
                -- Quando o usuário tentar abrir a tela de Config, pede a senha primeiro!
                if verificarSenhaSeguranca() then
                    return origOpen(...)
                end
                -- Se errar a senha, o menu fecha sozinho e não abre nada
            end
            configAPI.open = gerenciadorOpen
            _G.configAPI.open = gerenciadorOpen
        end

        -- Registra os campos normais na interface
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
        -- Deixamos o campo invisível no layout usando uma máscara vazia para não expor nada
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.password",
            label    = "Password Oculta",
            type     = "password",
            default  = "",
            onChange = function(v) end,
        })
    end

    -- 2. LOGICA DE INICIALIZAÇÃO (AUTO-PREENCHIMENTO DO USERNAME)
    if not configAPI or not configAPI.get("autologin.enabled") then
        return
    end

    local user = tostring(configAPI.get("autologin.username") or "")
    if user == "" then return end

    -- Interceptador do Read padrão para preencher o Username na tela de boot inicial
    local origRead = _G.read or read
    local chamadasRead = 0

    local function novoRead(substituteChar)
        chamadasRead = chamadasRead + 1

        -- 1ª Chamada: Devolve o nome de usuário salvo automaticamente
        if chamadasRead == 1 then
            return user
        end
        
        -- 2ª Chamada: Restaura o teclado original para o usuário digitar a senha na hora do boot
        _G.read = origRead
        read = origRead
        return origRead("*")
    end

    _G.read = novoRead
    read = novoRead
end

return plugin
