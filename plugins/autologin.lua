-- Autologin Plugin v2
-- patch plugin: patches doLogin with optional auto-fill
-- Registers settings via configAPI if available

local plugin  = {}
plugin.name   = "autologin"
plugin.label  = "autologin"
plugin.patch  = true
plugin.priority = 1

function plugin.run()
    -- register settings if configAPI is available
    if configAPI then
        configAPI.register({
            plugin  = "Autologin",
            key     = "autologin.enabled",
            label   = "Enable Autologin",
            type    = "checkbox",
            default = false,
            onChange = function(v) end,
        })
        configAPI.register({
            plugin  = "Autologin",
            key     = "autologin.username",
            label   = "Username",
            type    = "text",
            default = "",
            onChange = function(v) end,
        })
        configAPI.register({
            plugin  = "Autologin",
            key     = "autologin.password",
            label   = "Password",
            type    = "text",
            default = "",
            onChange = function(v) end,
        })
    end

    local origLogin = doLogin
    doLogin = function()
        local enabled = configAPI and configAPI.get("autologin.enabled") or false
        local user    = configAPI and configAPI.get("autologin.username") or ""
        local pass    = configAPI and configAPI.get("autologin.password") or ""

        if enabled and user ~= "" and pass ~= "" then
            local res = rpc({ type="login", username=user, password=pass })
            if res and res.ok then
                token    = res.token
                username = user
                isAdmin  = res.isAdmin or false
                return
            end
        end
        -- fallback to normal login
        origLogin()
    end
end

return plugin
