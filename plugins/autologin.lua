-- Autologin Plugin v3
-- patch plugin: patches doLogin with optional auto-fill
-- priority 2: runs after config_api (priority 1)

local plugin    = {}
plugin.name     = "autologin"
plugin.label    = "autologin"
plugin.patch    = true
plugin.priority = 2

function plugin.run()
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

    local origLogin = doLogin
    doLogin = function()
        local enabled = false
        local user    = ""
        local pass    = ""

        if configAPI then
            -- get returns actual boolean/string from parseVal
            local ev = configAPI.get("autologin.enabled")
            -- handle both boolean true and string "true"
            enabled = (ev == true or ev == "true")
            user    = tostring(configAPI.get("autologin.username") or "")
            pass    = tostring(configAPI.get("autologin.password") or "")
        end

        if enabled and user ~= "" and pass ~= "" then
            local res = rpc({ type="login", username=user, password=pass })
            if res and res.ok then
                token    = res.token
                username = user
                isAdmin  = res.isAdmin or false
                return
            end
        end
        origLogin()
    end
end

return plugin
