-- Cloud User v5
local PROTOCOL = "cloud_ui"

local modemSide = nil
for _, s in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(s) == "modem" then modemSide = s break end
end
if not modemSide then error("No wireless modem found") end
rednet.open(modemSide)

local W, H     = term.getSize()
local serverId = nil
local token    = nil
local username = nil
local isAdmin  = false

local iconColors = {
    colors.orange, colors.magenta, colors.lightBlue, colors.yellow,
    colors.lime, colors.pink, colors.cyan, colors.purple,
    colors.blue, colors.brown, colors.green, colors.red,
}
local function itemColor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + string.byte(name, i)) % #iconColors end
    return iconColors[h + 1]
end

local function rpc(msg, timeout)
    if serverId then rednet.send(serverId, msg, PROTOCOL)
    else rednet.broadcast(msg, PROTOCOL) end
    local id, res = rednet.receive(PROTOCOL, timeout or 5)
    if id then serverId = id end
    return res
end

-- Login
local function doLogin()
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Cloud Storage")
        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
        term.setCursorPos(1,3) term.write("Username: ")
        local uname = read()
        term.setCursorPos(1,4) term.write("Password: ")
        local pass = read("*")
        local res = rpc({ type="login", username=uname, password=pass })
        if res and res.ok then
            token=res.token username=uname isAdmin=res.isAdmin or false return
        else
            term.setCursorPos(1,6) term.setTextColor(colors.red)
            term.write((res and res.err) or "Server not found")
            term.setCursorPos(1,7) term.setTextColor(colors.gray) term.write("Press any key...")
            os.pullEvent("key")
        end
    end
end

-- Item list UI (click-based)
local function itemListUI(cfg)
    local items       = {}
    local filtered    = {}
    local scroll      = 0
    local selIdx      = nil
    local selAmt      = {}
    local searchMode  = false
    local searchQuery = ""
    local message     = ""
    local msgTimer    = 0
    local fetchErr    = nil
    local shiftHeld   = false

    local LIST_TOP = 2
    local function listBot()  return H - 3 end
    local function listRows() return listBot() - LIST_TOP + 1 end

    local function doFetch()
        local res = cfg.fetchFn()
        items    = (res and res.items) or {}
        fetchErr = res and res.err
    end

    local function applyFilter()
        if searchQuery == "" then
            filtered = items
        else
            local q = searchQuery:lower()
            filtered = {}
            for _, item in ipairs(items) do
                if (item.displayName or item.name):lower():find(q, 1, true) then
                    table.insert(filtered, item)
                end
            end
        end
        scroll = 0
        selIdx = nil
    end

    doFetch()
    applyFilter()

    local function getAmt(item)
        return selAmt[item.name] or 1
    end

    local function draw()
        W, H = term.getSize()
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1, 1) term.clearLine()
        if searchMode then
            term.write(" /" .. searchQuery .. "_")
        else
            local hdr = " " .. cfg.title .. " [" .. #filtered .. "]"
            if #hdr > W - 3 then hdr = hdr:sub(1, W - 3) end
            term.write(hdr .. string.rep(" ", math.max(0, W - #hdr - 3)) .. "[X]")
        end
        if fetchErr and #filtered == 0 then
            term.setCursorPos(1, LIST_TOP)
            term.setBackgroundColor(colors.black) term.setTextColor(colors.red)
            term.write(fetchErr:sub(1, W))
        else
            for row = 1, listRows() do
                local idx  = row + scroll
                local item = filtered[idx]
                local sr   = LIST_TOP + row - 1
                term.setCursorPos(1, sr)
                if item then
                    local isSel = (idx == selIdx)
                    local amt   = getAmt(item)
                    term.setBackgroundColor(itemColor(item.name)) term.setTextColor(colors.black) term.write(" ")
                    if isSel then
                        local qStr = ">" .. amt .. "/" .. item.count .. "<"
                        local lbl  = (item.displayName or item.name):sub(1, W - 2 - #qStr)
                        term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
                        term.write(" " .. lbl)
                        term.setTextColor(colors.lime)
                        term.write(string.rep(" ", math.max(0, W - 2 - #lbl - #qStr)) .. qStr)
                    else
                        local cs  = "x" .. item.count
                        local lbl = (item.displayName or item.name):sub(1, W - 3 - #cs)
                        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                        term.write(" " .. lbl)
                        term.setTextColor(colors.cyan)
                        term.write(string.rep(" ", math.max(0, W - 3 - #lbl - #cs)) .. cs)
                    end
                else
                    term.setBackgroundColor(colors.black) term.write(string.rep(" ", W))
                end
            end
        end
        if scroll > 0 then
            term.setCursorPos(W, LIST_TOP)
            term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
        end
        if scroll + listRows() < #filtered then
            term.setCursorPos(W, listBot())
            term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
        end
        local bRow = H - 2
        term.setCursorPos(1, bRow) term.setBackgroundColor(colors.black) term.clearLine()
        term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write(" / Search ")
        term.setBackgroundColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.gray)  term.write(" R Refresh ")
        term.setBackgroundColor(colors.black) term.write(" ")
        term.setBackgroundColor(colors.blue)  term.write(" < Back ")
        term.setCursorPos(1, H - 1) term.setBackgroundColor(colors.black)
        if message ~= "" and os.clock() < msgTimer then
            term.setTextColor(colors.lime) term.write(message:sub(1, W))
        else
            message = ""
            if selIdx and cfg.actionFn then
                local item = filtered[selIdx]
                if item then
                    term.setTextColor(colors.yellow)
                    term.write(("Click again to confirm (" .. (item.displayName or item.name) .. ")"):sub(1, W))
                end
            else
                term.setTextColor(colors.gray) term.write("RClick=full stack  Q=back")
            end
        end
        term.setCursorPos(1, H) term.setBackgroundColor(colors.black) term.write(string.rep(" ", W))
    end

    local function rowToIdx(my)
        if my < LIST_TOP or my > listBot() then return nil end
        local idx = (my - LIST_TOP) + 1 + scroll
        return (idx >= 1 and idx <= #filtered) and idx or nil
    end

    local function hitBtnBar(mx, my)
        if my ~= H - 2 then return nil end
        if mx >= 1  and mx <= 10 then return "search"  end
        if mx >= 12 and mx <= 22 then return "refresh" end
        if mx >= 24 and mx <= 31 then return "back"    end
        return nil
    end

    local function doAction(item)
        if not cfg.actionFn then return end
        local amt = math.min(getAmt(item), item.count)
        local ok, err = cfg.actionFn(item, amt)
        if ok then
            message  = (cfg.actionLabel or "Done") .. " x" .. amt .. ": " .. (item.displayName or item.name)
            msgTimer = os.clock() + 3
            selIdx   = nil
            doFetch() applyFilter()
        else
            message  = err or "Failed"
            msgTimer = os.clock() + 3
        end
    end

    while true do
        draw()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "term_resize" then W, H = term.getSize() shiftHeld = false
        elseif searchMode then
            if ev == "char" then searchQuery = searchQuery .. p1 applyFilter()
            elseif ev == "key" then
                if p1 == keys.backspace then
                    if searchQuery == "" then searchMode = false
                    else searchQuery = searchQuery:sub(1, -2) applyFilter() end
                elseif p1 == keys.enter then searchMode = false end
            elseif ev == "mouse_click" then searchMode = false end
        else
            if ev == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= W - 2 then return end
                local idx = rowToIdx(my)
                if idx then
                    local item = filtered[idx]
                    if p1 == 2 then
                        -- right click: instant full stack
                        selAmt[item.name] = math.min(64, item.count)
                        selIdx = idx
                        doAction(item)
                    elseif idx == selIdx then doAction(item)
                    else
                        selIdx = idx
                        if not selAmt[item.name] then selAmt[item.name] = 1 end
                    end
                else selIdx = nil end
                local btn = hitBtnBar(mx, my)
                if btn == "search" then searchMode = true searchQuery = "" applyFilter()
                elseif btn == "refresh" then doFetch() applyFilter() message = "Refreshed" msgTimer = os.clock() + 1
                elseif btn == "back" then return end
            elseif ev == "mouse_scroll" then
                local dir, mx, my = p1, p2, p3
                local idx = rowToIdx(my)
                if idx and idx == selIdx then
                    local item = filtered[idx]
                    local cur  = selAmt[item.name] or 1
                    selAmt[item.name] = math.max(1, math.min(cur - dir, item.count))
                else
                    scroll = math.max(0, math.min(scroll + dir, math.max(0, #filtered - listRows())))
                end
            elseif ev == "key" then
                if p1 == keys.q then
                    if selIdx then selIdx = nil else return end
                elseif p1 == keys.r then doFetch() applyFilter() message = "Refreshed" msgTimer = os.clock() + 1
                elseif p1 == keys.slash then searchMode = true searchQuery = "" applyFilter() end
            elseif ev == "key_up" then
                if p1 == keys.leftShift or p1 == keys.rightShift then shiftHeld = false end
            end
        end
    end
end

-- Log screen (click-based)
local function logScreen()
    local res = rpc({ type="get_log", token=token })
    local log = (res and res.log) or {}
    local scroll = 0
    while true do
        W, H = term.getSize()
        local listH = H - 3
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1, 1) term.clearLine()
        local hdr = " Activity Log [" .. #log .. "]"
        term.write(hdr .. string.rep(" ", math.max(0, W - #hdr - 3)) .. "[X]")
        for row = 1, listH do
            local idx = #log - scroll - row + 1
            term.setCursorPos(1, row + 1) term.setBackgroundColor(colors.black)
            if log[idx] then
                term.setTextColor(colors.white) term.write((log[idx].event or ""):sub(1, W))
            else
                term.setTextColor(colors.black) term.write(string.rep(" ", W))
            end
        end
        if scroll > 0 then
            term.setCursorPos(W, 2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
        end
        if scroll + listH < #log then
            term.setCursorPos(W, H - 2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
        end
        term.setCursorPos(1, H - 1) term.setBackgroundColor(colors.black) term.clearLine()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white) term.write(" < Back ")
        term.setBackgroundColor(colors.black) term.setTextColor(colors.gray) term.write("  Q=back")
        term.setCursorPos(1, H) term.setBackgroundColor(colors.black) term.write(string.rep(" ", W))
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "term_resize" then W, H = term.getSize() shiftHeld = false
        elseif ev == "mouse_click" then
            local mx, my = p2, p3
            if (my == 1 and mx >= W - 2) or (my == H - 1 and mx <= 8) then return end
        elseif ev == "mouse_scroll" then
            scroll = math.max(0, math.min(scroll + p1, math.max(0, #log - listH)))
        elseif ev == "key" then
            if p1 == keys.q then return
            elseif p1 == keys.up   then scroll = math.max(0, scroll - 1)
            elseif p1 == keys.down then scroll = math.min(math.max(0, #log - listH), scroll + 1) end
        end
    end
end

-- Shared clickable menu helper
local function clickMenu(title, items, msg)
    -- items = { {label, icon} }
    -- returns selected index, or nil if closed
    local message = msg or ""
    local msgTimer = 0
    while true do
        W, H = term.getSize()
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1, 1) term.clearLine()
        local hdr = " " .. title
        if #hdr > W - 3 then hdr = hdr:sub(1, W - 3) end
        term.write(hdr .. string.rep(" ", math.max(0, W - #hdr - 3)) .. "[X]")
        for i, opt in ipairs(items) do
            term.setCursorPos(1, i + 2)
            term.setBackgroundColor(opt.icon or colors.gray) term.setTextColor(colors.black) term.write(" ")
            term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
            term.write(" " .. opt.label .. string.rep(" ", math.max(0, W - #opt.label - 2)))
        end
        term.setCursorPos(1, H) term.setBackgroundColor(colors.black)
        if message ~= "" and os.clock() < msgTimer then
            term.setTextColor(colors.lime) term.write(message:sub(1, W))
        else
            message = ""
            term.setTextColor(colors.gray) term.write("Click to select  Q=back")
        end
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "term_resize" then W, H = term.getSize() shiftHeld = false
        elseif ev == "mouse_click" then
            local mx, my = p2, p3
            if my == 1 and mx >= W - 2 then return nil end
            local idx = my - 2
            if idx >= 1 and idx <= #items then return idx end
        elseif ev == "key" then
            if p1 == keys.q then return nil end
        end
    end
end

-- User menu
local function userMenu()
    local menuItems = {
        { label="Withdraw", icon=colors.green },
        { label="Deposit",  icon=colors.blue  },
        { label="Log",      icon=colors.gray  },
        { label="Logout",   icon=colors.red   },
    }
    while true do
        local sel = clickMenu("Cloud - " .. username, menuItems)
        if sel == nil or sel == 4 then token=nil username=nil isAdmin=false return
        elseif sel == 1 then
            itemListUI({ title="Withdraw", actionLabel="Withdrew",
                fetchFn=function() local r=rpc({type="list_vault",token=token}) return r or {} end,
                actionFn=function(item,amt)
                    local r=rpc({type="withdraw",token=token,name=item.name,displayName=item.displayName,count=amt},10)
                    return r and r.ok, r and r.err end })
        elseif sel == 2 then
            itemListUI({ title="Deposit", actionLabel="Deposited",
                fetchFn=function() local r=rpc({type="list_inventory",token=token}) return r or {} end,
                actionFn=function(item,amt)
                    local r=rpc({type="deposit",token=token,name=item.name,displayName=item.displayName,count=amt},10)
                    return r and r.ok, r and r.err end })
        elseif sel == 3 then
            logScreen()
        end
    end
end

-- Admin: pick user from scrollable click list
local function pickUser()
    local res   = rpc({type="admin_list_users", token=token})
    local ulist = (res and res.users) or {}
    if #ulist == 0 then return nil, "No users found" end
    local scroll = 0
    while true do
        W, H = term.getSize()
        local listH = H - 2
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        term.write(" Select User [" .. #ulist .. "]" .. string.rep(" ", math.max(0, W - 17)) .. "[X]")
        for row = 1, listH do
            local u = ulist[row + scroll]
            term.setCursorPos(1, row + 1) term.setBackgroundColor(colors.black)
            if u then
                term.setTextColor(colors.yellow) term.write(" " .. (u.username or ""):sub(1, W - 2))
                term.setTextColor(colors.black) term.write(string.rep(" ", math.max(0, W - #(u.username or "") - 2)))
            else
                term.write(string.rep(" ", W))
            end
        end
        if scroll > 0 then
            term.setCursorPos(W, 2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
        end
        if scroll + listH < #ulist then
            term.setCursorPos(W, H) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
        end
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "term_resize" then W, H = term.getSize() shiftHeld = false
        elseif ev == "mouse_click" then
            local mx, my = p2, p3
            if my == 1 and mx >= W - 2 then return nil end
            local idx = my - 1 + scroll
            if idx >= 1 and idx <= #ulist then return ulist[idx].username end
        elseif ev == "mouse_scroll" then
            scroll = math.max(0, math.min(scroll + p1, math.max(0, #ulist - listH)))
        elseif ev == "key" then
            if p1 == keys.q then return nil
            elseif p1 == keys.up   then scroll = math.max(0, scroll - 1)
            elseif p1 == keys.down then scroll = math.min(math.max(0, #ulist - listH), scroll + 1) end
        end
    end
end

-- Admin menu
local function adminMenu()
    local msg2 = ""
    local mt2  = 0
    while true do
        local adminItems = {
            { label="List Users",        icon=colors.cyan   },
            { label="Create User",       icon=colors.lime   },
            { label="Manage User",       icon=colors.yellow },
            { label="Debug Peripherals", icon=colors.orange },
            { label="Logout",            icon=colors.red    },
        }
        local sel = clickMenu("Cloud Admin", adminItems, msg2)
        msg2 = ""

        if sel == nil or sel == 5 then
            token=nil username=nil isAdmin=false return

        elseif sel == 1 then
            -- List users
            local res   = rpc({type="admin_list_users", token=token})
            local users = (res and res.users) or {}
            local scroll = 0
            while true do
                W, H = term.getSize()
                local listH = H - 2
                term.setBackgroundColor(colors.black) term.clear()
                term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                term.setCursorPos(1,1) term.clearLine()
                term.write(" Users [" .. #users .. "]" .. string.rep(" ", math.max(0, W - 12)) .. "[X]")
                for row = 1, listH do
                    local u = users[row + scroll]
                    term.setCursorPos(1, row + 1) term.setBackgroundColor(colors.black)
                    if u then
                        term.setTextColor(colors.yellow) term.write(" " .. u.username:sub(1, 12))
                        term.setTextColor(colors.gray)   term.write("  " .. (u.vault or "no vault"):sub(1, W - 16))
                    else
                        term.setTextColor(colors.black) term.write(string.rep(" ", W))
                    end
                end
                if scroll > 0 then
                    term.setCursorPos(W, 2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
                end
                if scroll + listH < #users then
                    term.setCursorPos(W, H) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
                end
                local ev2, p2, p3, p4 = os.pullEvent()
                if ev2=="term_resize" then W, H = term.getSize()
                elseif ev2=="mouse_click" and p3==1 and p4>=W-2 then break
                elseif ev2=="mouse_scroll" then scroll=math.max(0,math.min(scroll+p2,math.max(0,#users-listH)))
                elseif ev2=="key" then
                    if p2==keys.q then break
                    elseif p2==keys.up   then scroll=math.max(0,scroll-1)
                    elseif p2==keys.down then scroll=math.min(math.max(0,#users-listH),scroll+1) end
                end
            end

        elseif sel == 2 then
            -- Create user (text input, keyboard only)
            term.setBackgroundColor(colors.black) term.clear()
            term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
            term.setCursorPos(1,1) term.clearLine() term.write(" Create User")
            term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
            local function prompt(row, label)
                term.setCursorPos(1,row) term.write(label) return read()
            end
            local uname = prompt(3,"Username:   ")
            local pass  = prompt(4,"Password:   ")
            local vnum  = prompt(5,"Vault #:    ")
            local imnum = prompt(6,"InvMgr #:   ")
            local vdir  = prompt(7,"VaultDir:   ")
            if vdir == "" then vdir = "back" end
            local vault  = "create:item_vault_"..vnum
            local invmgr = "inventory_manager_"..imnum
            local r = rpc({type="admin_create_user", token=token,
                username=uname, password=pass, vault=vault, invmanager=invmgr, vaultDir=vdir}, 10)
            if r and r.ok then msg2="Created: "..uname mt2=os.clock()+3
            else msg2=(r and r.err) or "Failed" mt2=os.clock()+3 end

        elseif sel == 3 then
            -- Manage user
            local target, err = pickUser()
            if not target then
                if err then msg2=err mt2=os.clock()+2 end
            else
                local subItems = {
                    { label="View Vault",      icon=colors.cyan   },
                    { label="View Inventory",  icon=colors.blue   },
                    { label="Withdraw",        icon=colors.green  },
                    { label="Deposit",         icon=colors.lime   },
                    { label="Delete User",     icon=colors.red    },
                    { label="Back",            icon=colors.gray   },
                }
                while true do
                    local sub = clickMenu("Manage: " .. target, subItems)
                    if sub == nil or sub == 6 then break
                    elseif sub == 1 then
                        itemListUI({title=target.." Vault", readOnly=true,
                            fetchFn=function() local r=rpc({type="admin_view_vault",token=token,username=target}) return r or {} end})
                    elseif sub == 2 then
                        itemListUI({title=target.." Inventory", readOnly=true,
                            fetchFn=function() local r=rpc({type="admin_view_inventory",token=token,username=target}) return r or {} end})
                    elseif sub == 3 then
                        itemListUI({title="Withdraw: "..target, actionLabel="Withdrew",
                            fetchFn=function() local r=rpc({type="admin_view_vault",token=token,username=target}) return r or {} end,
                            actionFn=function(item,amt)
                                local r=rpc({type="admin_withdraw",token=token,username=target,name=item.name,count=amt},10)
                                return r and r.ok, r and r.err end})
                    elseif sub == 4 then
                        itemListUI({title="Deposit: "..target, actionLabel="Deposited",
                            fetchFn=function() local r=rpc({type="admin_view_inventory",token=token,username=target}) return r or {} end,
                            actionFn=function(item,amt)
                                local r=rpc({type="admin_deposit",token=token,username=target,name=item.name,count=amt},10)
                                return r and r.ok, r and r.err end})
                    elseif sub == 5 then
                        term.setBackgroundColor(colors.black) term.clear()
                        term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                        term.setCursorPos(1,1) term.clearLine() term.write(" Confirm Delete")
                        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                        term.setCursorPos(1,3) term.write("Delete " .. target .. "?")
                        term.setCursorPos(1,5)
                        term.setBackgroundColor(colors.red)    term.write(" Yes ")
                        term.setBackgroundColor(colors.black)  term.write("   ")
                        term.setBackgroundColor(colors.gray)   term.write(" No ")
                        local ev4, p4, p5, p6 = os.pullEvent()
                        if ev4 == "mouse_click" and p6 == 5 then
                            if p5 >= 1 and p5 <= 5 then
                                local r = rpc({type="admin_delete_user",token=token,username=target},10)
                                if r and r.ok then msg2="Deleted: "..target mt2=os.clock()+3 break end
                            end
                        elseif ev4 == "key" and p4 == keys.y then
                            local r = rpc({type="admin_delete_user",token=token,username=target},10)
                            if r and r.ok then msg2="Deleted: "..target mt2=os.clock()+3 break end
                        end
                    end
                end
            end

        elseif sel == 4 then
            -- Debug peripherals
            local res   = rpc({type="debug_peripherals"})
            local names = (res and res.names) or {}
            local scroll = 0
            while true do
                W, H = term.getSize()
                local listH = H - 2
                term.setBackgroundColor(colors.black) term.clear()
                term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                term.setCursorPos(1,1) term.clearLine()
                term.write(" Peripherals [" .. #names .. "]" .. string.rep(" ", math.max(0, W - 18)) .. "[X]")
                for row = 1, listH do
                    local n = names[row + scroll]
                    term.setCursorPos(1, row + 1) term.setBackgroundColor(colors.black)
                    if n then term.setTextColor(colors.white) term.write(" " .. n:sub(1, W - 1))
                    else term.setTextColor(colors.black) term.write(string.rep(" ", W)) end
                end
                if scroll > 0 then
                    term.setCursorPos(W, 2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
                end
                if scroll + listH < #names then
                    term.setCursorPos(W, H) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
                end
                local ev2, p2, p3, p4 = os.pullEvent()
                if ev2=="term_resize" then W, H = term.getSize()
                elseif ev2=="mouse_click" and p3==1 and p4>=W-2 then break
                elseif ev2=="mouse_scroll" then scroll=math.max(0,math.min(scroll+p2,math.max(0,#names-listH)))
                elseif ev2=="key" then
                    if p2==keys.q then break
                    elseif p2==keys.up   then scroll=math.max(0,scroll-1)
                    elseif p2==keys.down then scroll=math.min(math.max(0,#names-listH),scroll+1) end
                end
            end
        end
    end
end

while true do
    doLogin()
    if isAdmin then adminMenu() else userMenu() end
end