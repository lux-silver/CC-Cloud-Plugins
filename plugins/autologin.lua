-- Autologin Plugin v13 (Bypass via Read + Tranca no Menu Settings)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- Função interna que pede a senha do usuário para destravar o menu Settings
    local function verificarSenhaSeguranca()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.red)
        term.setCursorPos(1, 2)
        print("=== AREA RESTRITA ===")
        term.setTextColor(colors.white)
        print("Insira a senha do Usuario para acessar as Configuracoes:")
        
        term.setCursorPos(1, 5)
        term.write("Senha: ")
        
        -- Usa o read("*") para que a digitação da senha de desbloqueio fique oculta
        local senhaDigitada = read("*")
        
        local userSalvo = configAPI and configAPI.get("autologin.username") or ""
        local rpcFunc = _G.rpc or rpc
        
        if type(rpcFunc) == "function" and userSalvo ~= "" then
            -- Envia um teste de login em tempo real para o servidor Rednet validar a senha
            local res = rpcFunc({ type = "login", username = userSalvo, password = senhaDigitada })
            if res and res.ok then
                return true -- Senha correta, destrava o menu
            end
        end
        
        term.setCursorPos(1, 7)
        term.setTextColor(colors.red)
        print("Senha incorreta! Acesso negado.")
        sleep(2)
        return false
    end

    -- 1. REGISTRO E PROTEÇÃO DOS MENUS (ConfigAPI & Settings)
    if configAPI then
        -- TRANCA NATIVA: Intercepta a função .open() principal das configurações do OS
        if type(configAPI.open) == "function" or type(_G.configAPI.open) == "function" then
            local origOpen = configAPI.open or _G.configAPI.open
            local gerenciadorOpen = function(...)
                if verificarSenhaSeguranca() then
                    return origOpen(...)
                end
                -- Se errar a senha, o menu fecha e limpa a tela de volta para o Cloud
                term.clear()
            end
            configAPI.open = gerenciadorOpen
            _G.configAPI.open = gerenciadorOpen
        end

        -- Registra os teus campos normais na interface gráfica do usuário
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
        -- Mudado o tipo para "password" para ocultar os caracteres por segurança
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.password",
            label    = "Password",
            type     = "password", 
            default  = "",
            onChange = function(v) end,
        })
    end

    -- 2. BI-PASS DO LOGIN INICIAL (A Lógica da Versão 10 que funcionou)
    if not configAPI or not configAPI.get("autologin.enabled") then
        return
    end

    local user = tostring(configAPI.get("autologin.username") or "")
    local pass = tostring(configAPI.get("autologin.password") or "")
    if user == "" or pass == "" then return end

    local origRead = _G.read or read
    local chamadasRead = 0

    local function novoRead(substituteChar)
        chamadasRead = chamadasRead + 1

        -- 1ª chamada dentro do doLogin() -> Entrega o Username salvo
        if chamadasRead == 1 then
            return user
        end
        
        -- 2ª chamada dentro do doLogin() -> Entrega a Senha salva e restaura o read() do OS
        if chamadasRead == 2 then
            _G.read = origRead
            read = origRead
            return pass
        end

        return origRead(substituteChar)
    end

    _G.read = novoRead
    read = newRead
end

return plugin
