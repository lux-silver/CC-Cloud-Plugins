-- Autologin Plugin v7 (Bypass via RPC Interceptor)
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

    -- 2. INTERCEPTOR DA API RPC (Onde o cloud.lua valida os dados)
    local origRPC = _G.rpc or rpc
    
    if type(origRPC) == "function" then
        local novoRPC = function(origArgs)
            -- Se o cloud.lua disparar um pedido de login normal, nós trocamos os dados antes de enviar!
            if type(origArgs) == "table" and origArgs.type == "login" and configAPI then
                local enabled = configAPI.get("autologin.enabled")
                if enabled == true or enabled == "true" then
                    local user = tostring(configAPI.get("autologin.username") or "")
                    local pass = tostring(configAPI.get("autologin.password") or "")
                    
                    if user ~= "" and pass ~= "" then
                        -- Substitui o que foi digitado na tela pelas tuas credenciais automáticas
                        origArgs.username = user
                        origArgs.password = pass
                    end
                end
            end
            
            -- Executa a chamada real ao servidor
            local res = origRPC(origArgs)
            
            -- Se for o retorno do login, injeta os tokens no ambiente global para o Cloud aceitar
            if type(origArgs) == "table" and origArgs.type == "login" and res and res.ok then
                _G.token    = res.token
                _G.username = origArgs.username
                _G.isAdmin  = res.isAdmin or false
                
                -- Tenta injetar no ambiente local da thread do Cloud se aplicável
                local env = getfenv(2)
                if env then
                    env.token = res.token
                    env.username = origArgs.username
                    env.isAdmin = res.isAdmin or false
                    env.doLogin = function() return end -- Destrói o loop de login da tela
                end
            end
            return res
        end
        
        _G.rpc = novoRPC
        rpc = novoRPC
    end
end

return plugin
