-- Autologin Plugin v15 (Auto-Destruição Pós-Uso)
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

    -- 3. INTERCEPTADOR COM AUTO-DESTRUIÇÃO MÁXIMA
    local origRead = _G.read or read
    local chamadasRead = 0

    local function novoRead(substituteChar)
        chamadasRead = chamadasRead + 1

        -- 1ª Chamada: Injeta o Username
        if chamadasRead == 1 then
            return user
        end
        
        -- 2ª Chamada: Injeta a Password
        if chamadasRead == 2 then
            -- RESTAURAÇÃO TOTAL E DEFINITIVA ANTES DE RETORNAR
            _G.read = origRead
            read = origRead
            novoRead = nil -- Auto-destrói a referência na memória
            return pass
        end

        -- Segurança extra: se escapar qualquer chamada, desliga imediatamente
        _G.read = origRead
        read = origRead
        return origRead(substituteChar)
    end

    -- Substitui globalmente a função de leitura apenas para o instante do login
    _G.read = novoRead
    read = novoRead
end

return plugin