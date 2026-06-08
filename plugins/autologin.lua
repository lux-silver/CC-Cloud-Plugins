-- Autologin Plugin v1
-- Patches doLogin to auto-fill credentials on startup
-- Place at: plugins/autologin.lua
-- plugin.patch = true  (runs at load, no menu entry)

-- ── Config ────────────────────────────────────────────────────────────────────
local USERNAME = "your_username"
local PASSWORD = "your_password"
-- ─────────────────────────────────────────────────────────────────────────────

local plugin  = {}
plugin.name   = "autologin"
plugin.label  = "autologin"
plugin.patch  = true

function plugin.run()
    local origLogin = doLogin
    doLogin = function()
        -- try auto-login first
        local res = rpc({ type="login", username=USERNAME, password=PASSWORD })
        if res and res.ok then
            token    = res.token
            username = USERNAME
            isAdmin  = res.isAdmin or false
            return
        end
        -- if it fails fall back to normal login screen
        origLogin()
    end
end

return plugin
