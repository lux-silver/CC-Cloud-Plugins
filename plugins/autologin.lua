-- Autologin Plugin v5 (Correção de Sandbox do Cloud)
-- patch plugin: patches doLogin with optional auto-fill
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- 1. Regista os campos normalmente no menu do ConfigAPI se ele existir
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

    -- 2. Captura a função de RPC correta do ambiente
    local rpcFunc = rpc or _G.rpc

    -- 3. Modifica a função doLogin global e injeta a armadilha de execução
    local origLogin = doLogin or _G.doLogin
    
    local function interceptorLogin()
        if configAPI then
            local enabled = configAPI.get("autologin.enabled")
            if enabled == true or enabled == "true" then
                local user = tostring(configAPI.get("autologin.username") or "")
                local pass = tostring(configAPI.get("autologin.password") or "")
                
                if user ~= "" and pass ~= "" and type(rpcFunc) == "function" then
                    local res = rpcFunc({ type="login", username=user, password=pass })
                    if res and res.ok then
                        -- Define os tokens tanto no escopo local do Cloud quanto no Global
                        token    = res.token
                        username = user
                        isAdmin  = res.isAdmin or false
                        
                        _G.token    = res.token
                        _G.username = user
                        _G.isAdmin  = res.isAdmin or false
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Substitui a chamada para o Cloud avançar direto caso o login seja bem-sucedido
    doLogin = function()
        if interceptorLogin() then
            return
        end
        if type(origLogin) == "function" then
            origLogin()
        end
    end
    
    _G.doLogin = doLogin
end

return plugin
