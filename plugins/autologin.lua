-- Autologin Plugin v6 (Injeção Direta no Escopo Global)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    print("[Autologin] Executando injeção de patch...")

    -- 1. Garante o registro de chaves no ConfigAPI se ele existir
    if _G.configAPI then
        _G.configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.enabled",
            label    = "Enable Autologin",
            type     = "checkbox",
            default  = false,
            onChange = function(v) end,
        })
        _G.configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.username",
            label    = "Username",
            type     = "text",
            default  = "",
            onChange = function(v) end,
        })
        _G.configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.password",
            label    = "Password",
            type     = "text",
            default  = "",
            onChange = function(v) end,
        })
    end

    -- 2. Rotina interna que manipula as variáveis locais/globais de autenticação
    local function processarAutenticacao()
        if not _G.configAPI then return false end
        
        local enabled = _G.configAPI.get("autologin.enabled")
        if enabled == true or enabled == "true" then
            local user = tostring(_G.configAPI.get("autologin.username") or "")
            local pass = tostring(_G.configAPI.get("autologin.password") or "")
            
            -- Se as credenciais estiverem salvas e a API rpc estiver disponível
            if user ~= "" and pass ~= "" and type(_G.rpc) == "function" then
                local res = _G.rpc({ type = "login", username = user, password = pass })
                if res and res.ok then
                    -- Alimenta tanto o ambiente local quanto a tabela global do OS
                    _G.token    = res.token
                    _G.username = user
                    _G.isAdmin  = res.isAdmin or false
                    
                    -- Adiciona no ambiente da thread pai se aplicável
                    local env = getfenv(2)
                    if env then
                        env.token = res.token
                        env.username = user
                        env.isAdmin = res.isAdmin or false
                    end
                    print("[Autologin] Logado com sucesso como: " .. user)
                    return true
                end
            end
        end
        return false
    end

    -- 3. INTERCEPTAÇÃO: Procura onde doLogin está escondido
    -- Tenta substituir no ambiente global direto
    if type(_G.doLogin) == "function" then
        local origLogin = _G.doLogin
        _G.doLogin = function(...)
            if processarAutenticacao() then return end
            return origLogin(...)
        end
    else
        -- Se doLogin não for global, criamos um listener na metatabela global para interceptar
        -- assim que o sistema operacional tentar ler ou gravar a função!
        local mt = getmetatable(_G) or {}
        local oldNewIndex = mt.__newindex
        
        mt.__newindex = function(t, k, v)
            if k == "doLogin" and type(v) == "function" then
                local orig = v
                v = function(...)
                    if processarAutenticacao() then return end
                    return orig(...)
                end
                print("[Autologin] Armadilha ativada para interceptar doLogin dinâmico!")
            end
            if oldNewIndex then
                oldNewIndex(t, k, v)
            else
                rawset(t, k, v)
            end
        end
        setmetatable(_G, mt)
    end
end

-- Forçar execução caso o gerenciador do OS apenas carregue mas não execute
plugin.run()

return plugin
