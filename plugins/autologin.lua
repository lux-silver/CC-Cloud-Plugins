-- Autologin Plugin v9 (RPC Interceptor para Variáveis Locais)
-- priority 2: corre logo após a inicialização da API de configurações

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- 1. Regista os campos no menu de Configurações
    if configAPI then
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.enabled",
            label    = "Enable Autologin",
            type     = "checkbox",
            default  = true,
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

    -- 2. Intercepta a função RPC que o doLogin() usa para validar
    local origRPC = _G.rpc or rpc
    
    if type(origRPC) == "function" then
        local novoRPC = function(origArgs, timeout)
            -- Se for uma tentativa de login e o autologin estiver ativo, injeta as credenciais
            if type(origArgs) == "table" and origArgs.type == "login" and configAPI then
                local enabled = configAPI.get("autologin.enabled")
                if enabled == true or enabled == "true" then
                    local user = tostring(configAPI.get("autologin.username") or "")
                    local pass = tostring(configAPI.get("autologin.password") or "")
                    
                    if user ~= "" and pass ~= "" then
                        origArgs.username = user
                        origArgs.password = pass
                    end
                end
            end
            
            -- Executa a comunicação real com o servidor rednet
            return origRPC(origArgs, timeout)
        end
        
        -- Substitui globalmente para que a função interna do cloud_user a utilize
        _G.rpc = novoRPC
        rpc = novoRPC
    end

    -- 3. IGNORA A TELA (Simula um ENTER automático para disparar o login)
    if configAPI and configAPI.get("autologin.enabled") then
        local user = tostring(configAPI.get("autologin.username") or "")
        local pass = tostring(configAPI.get("autologin.password") or "")
        if user ~= "" and pass ~= "" then
            -- Envia eventos virtuais de ENTER para avançar os campos de texto vazios rapidamente
            local function dispararLogin()
                sleep(0.2)
                os.queueEvent("key", keys.enter, false)
                sleep(0.2)
                os.queueEvent("key", keys.enter, false)
            end
            local co = coroutine.create(dispararLogin)
            coroutine.resume(co)
        end
    end
end

return plugin
