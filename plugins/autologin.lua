-- Autologin Plugin v10 (Bypass via Read Interceptor)
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- 1. Regista os campos no menu de Configurações normalmente
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

    -- 2. Se o Autologin estiver desativado nas configurações, não faz nada
    if not configAPI or not configAPI.get("autologin.enabled") then
        return
    end

    local user = tostring(configAPI.get("autologin.username") or "")
    local pass = tostring(configAPI.get("autologin.password") or "")
    if user == "" or pass == "" then return end

    -- 3. INTERCEPTADOR INTELIGENTE DO READ
    -- Guardamos a função original do sistema operacional
    local origRead = _G.read or read
    local chamadasRead = 0

    local function novoRead(substituteChar)
        chamadasRead = chamadasRead + 1

        -- A primeira chamada do read() dentro do doLogin() é para o Username
        if chamadasRead == 1 then
            return user
        end
        
        -- A segunda chamada do read() é para a Password
        if chamadasRead == 2 then
            -- Restauramos o read original imediatamente após passar a tela de login
            _G.read = origRead
            read = origRead
            return pass
        end

        return origRead(substituteChar)
    end

    -- Substitui globalmente a função de leitura para o doLogin() consumi-la
    _G.read = novoRead
    read = novoRead
end

return plugin
