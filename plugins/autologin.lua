-- Autologin Plugin v5 (Ajuste de Carregamento)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- 1. Regista as configurações na interface gráfica (ConfigAPI)
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

    -- 2. Função interna que faz o login acontecer
    local function tentarAutoLogin()
        if configAPI then
            local enabled = configAPI.get("autologin.enabled")
            if enabled == true or enabled == "true" then
                local user = tostring(configAPI.get("autologin.username") or "")
                local pass = tostring(configAPI.get("autologin.password") or "")
                
                if user ~= "" and pass ~= "" and type(rpc) == "function" then
                    local res = rpc({ type="login", username=user, password=pass })
                    if res and res.ok then
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

    -- 3. O SEGREDO: Se 'doLogin' já existir, modifica-o. Se não, cria uma armadilha!
    if type(_G.doLogin) == "function" then
        local origLogin = _G.doLogin
        _G.doLogin = function()
            if tentarAutoLogin() then return end
            origLogin()
        end
    else
        -- Se o sistema principal ainda não criou o doLogin, nós criamos um que intercepta!
        _G.doLogin = function()
            if tentarAutoLogin() then return end
            -- Procura se o sistema reinjetou a função original por trás
            print("Autologin falhou ou aguardando tela...")
        end
    end
end

-- Força a execução imediata
plugin.run()

return plugin
