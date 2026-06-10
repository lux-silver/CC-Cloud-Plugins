-- Autologin Plugin v4
-- patch plugin: patches doLogin with optional auto-fill
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
    -- register settings first so values are loaded from disk before we patch doLogin
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

    -- patch doLogin — reads fresh from configAPI each call
    local origLogin = doLogin
    doLogin = function()
        if configAPI then
            local enabled = configAPI.get("autologin.enabled")
            -- parseVal returns actual boolean, but guard against string just in case
            if enabled == true or enabled == "true" then
                local user = tostring(configAPI.get("autologin.username") or "")
                local pass = tostring(configAPI.get("autologin.password") or "")
                if user ~= "" and pass ~= "" then
                    local res = rpc({ type="login", username=user, password=pass })
                    if res and res.ok then
                        token    = res.token
                        username = user
                        isAdmin  = res.isAdmin or false
                        return
                    end
                    -- if login failed, fall through to normal login
                end
            end
        end
        origLogin()
    end
end

return plugin
