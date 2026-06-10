-- Autologin Plugin v11 (Preenchimento Seguro de Usuário & Senha Oculta)
-- priority 2: runs after config_api (priority 1)

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
        -- Define o tipo como "password" para mascarar visualmente com '*' e proteger a exibição
        configAPI.register({
            plugin   = "Autologin",
            key      = "autologin.password",
            label    = "Password (Oculta)",
            type     = "password", 
            default  = "",
            onChange = function(v) end,
        })
    end

    -- 2. Se o Autologin estiver desativado, não interfere no sistema
    if not configAPI or not configAPI.get("autologin.enabled") then
        return
    end

    local user = tostring(configAPI.get("autologin.username") or "")
    if user == "" then return end

    -- 3. INTERCEPTADOR SEGURO DO READ
    local origRead = _G.read or read
    local chamadasRead = 0

    local function novoRead(substituteChar)
        local env = getfenv(2)
        chamadasRead = chamadasRead + 1

        -- 1ª Chamada (Username): Devolve o Usuário salvo automaticamente
        if chamadasRead == 1 then
            return user
        end
        
        -- 2ª Chamada (Password): Restaura o read original do Minecraft imediatamente!
        -- Isso força a tela a parar e pedir que digites a tua senha real com proteção "*"
        _G.read = origRead
        read = origRead
        
        return origRead("*") -- Garante que a digitação na tela do login use o caractere oculto
    end

    -- Aplica o interceptor para o doLogin() consumir
    _G.read = novoRead
    read = novoRead
end

return plugin
