-- Multiselect Plugin v1
-- Replaces itemListUI in the instance with a multi-select version
-- Left click  = toggle select/deselect
-- Right click = deselect
-- Scroll on selected item = change its qty
-- Confirm button = run action on all selected

local plugin  = {}
plugin.name   = "multiselect"
plugin.label  = "multiselect"
plugin.patch  = true   -- patch plugin: runs at load time, no menu entry

function plugin.run()
    -- This plugin patches itemListUI directly in the shared scope
    -- It is called once at startup by the launcher before any menu is shown
    itemListUI = function(cfg)
        local items       = {}
        local filtered    = {}
        local scroll      = 0
        local selected    = {}   -- selected[name] = true
        local amounts     = {}   -- amounts[name]  = qty
        local searchMode  = false
        local searchQuery = ""
        local message     = ""
        local msgTimer    = 0
        local fetchErr    = nil

        local LIST_TOP = 2
        local function listBot()  return H - 3 end
        local function listRows() return listBot() - LIST_TOP + 1 end

        local function countSel()
            local n = 0
            for _, v in pairs(selected) do if v then n = n + 1 end end
            return n
        end

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
        end

        doFetch()
        applyFilter()

        local function draw()
            W, H = term.getSize()
            term.setBackgroundColor(colors.black) term.clear()

            -- header
            term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
            term.setCursorPos(1, 1) term.clearLine()
            if searchMode then
                term.write(" /" .. searchQuery .. "_")
            else
                local n   = countSel()
                local hdr = " " .. cfg.title .. " [" .. #filtered .. "]"
                if n > 0 then hdr = hdr .. " +" .. n end
                if #hdr > W - 3 then hdr = hdr:sub(1, W - 3) end
                term.write(hdr .. string.rep(" ", math.max(0, W - #hdr - 3)) .. "[X]")
            end

            -- item rows
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
                        local isSel = selected[item.name]
                        local amt   = amounts[item.name] or 1
                        term.setBackgroundColor(itemColor(item.name))
                        term.setTextColor(colors.black) term.write(" ")
                        if isSel then
                            local qStr = " " .. amt .. "/" .. item.count
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

            -- scroll arrows
            if scroll > 0 then
                term.setCursorPos(W, LIST_TOP)
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
            end
            if scroll + listRows() < #filtered then
                term.setCursorPos(W, listBot())
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
            end

            -- button bar
            local bRow = H - 2
            term.setCursorPos(1, bRow) term.setBackgroundColor(colors.black) term.clearLine()
            term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write(" / Search ")
            term.setBackgroundColor(colors.black) term.write(" ")
            term.setBackgroundColor(colors.gray) term.write(" R Refresh ")
            term.setBackgroundColor(colors.black) term.write(" ")
            if countSel() > 0 then
                term.setBackgroundColor(colors.red)   term.write(" Clear ")
                term.setBackgroundColor(colors.black) term.write(" ")
                term.setBackgroundColor(colors.green) term.write(" Confirm ")
                term.setBackgroundColor(colors.black) term.write(" ")
            end
            term.setBackgroundColor(colors.blue) term.write(" < Back ")

            -- status
            term.setCursorPos(1, H - 1) term.setBackgroundColor(colors.black)
            if message ~= "" and os.clock() < msgTimer then
                term.setTextColor(colors.lime) term.write(message:sub(1, W))
            else
                message = ""
                if countSel() > 0 then
                    term.setTextColor(colors.yellow) term.write("L=select  R=deselect  Scroll=qty")
                else
                    term.setTextColor(colors.gray) term.write("Click item to select  Q=back")
                end
            end
            term.setCursorPos(1, H) term.setBackgroundColor(colors.black) term.write(string.rep(" ", W))
        end

        local function rowToItem(my)
            if my < LIST_TOP or my > listBot() then return nil end
            local idx = (my - LIST_TOP) + 1 + scroll
            return filtered[idx]
        end

        local function hitBtnBar(mx, my)
            if my ~= H - 2 then return nil end
            if mx >= 1  and mx <= 10 then return "search"  end
            if mx >= 12 and mx <= 22 then return "refresh" end
            local x = 24
            if countSel() > 0 then
                if mx >= x and mx <= x + 6 then return "clear" end
                x = x + 8
                if mx >= x and mx <= x + 8 then return "confirm" end
                x = x + 10
            end
            if mx >= x and mx <= x + 7 then return "back" end
            return nil
        end

        local function doConfirm()
            if not cfg.actionFn then return end
            local done, failed = 0, 0
            for _, item in ipairs(filtered) do
                if selected[item.name] then
                    local amt = math.min(amounts[item.name] or 1, item.count)
                    local ok, err = cfg.actionFn(item, amt)
                    if ok then
                        done = done + 1
                        selected[item.name] = nil
                        amounts[item.name]  = nil
                    else
                        failed = failed + 1
                    end
                end
            end
            message  = (cfg.actionLabel or "Done") .. " " .. done .. (failed > 0 and (" | " .. failed .. " failed") or "")
            msgTimer = os.clock() + 3
            doFetch() applyFilter()
        end

        while true do
            draw()
            local ev, p1, p2, p3 = os.pullEvent()

            if ev == "term_resize" then
                W, H = term.getSize()
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
                    local btn, mx, my = p1, p2, p3
                    if my == 1 and mx >= W - 2 then return end
                    local item = rowToItem(my)
                    if item then
                        if btn == 1 then
                            if selected[item.name] then
                                -- second left click on selected = confirm just this item
                                doConfirm()
                            else
                                -- first left click = select
                                selected[item.name] = true
                                amounts[item.name]  = amounts[item.name] or 1
                            end
                        elseif btn == 2 then
                            -- right click = deselect
                            selected[item.name] = nil
                            amounts[item.name]  = nil
                        end
                    end
                    local bb = hitBtnBar(mx, my)
                    if bb == "search"  then searchMode = true searchQuery = "" applyFilter()
                    elseif bb == "refresh" then doFetch() applyFilter() message = "Refreshed" msgTimer = os.clock() + 1
                    elseif bb == "clear"   then selected = {} amounts = {}
                    elseif bb == "confirm" then doConfirm()
                    elseif bb == "back"    then return end

                elseif ev == "mouse_scroll" then
                    local dir, mx, my = p1, p2, p3
                    local item = rowToItem(my)
                    if item and selected[item.name] then
                        local cur = amounts[item.name] or 1
                        amounts[item.name] = math.max(1, math.min(cur - dir, item.count))
                    else
                        scroll = math.max(0, math.min(scroll + dir, math.max(0, #filtered - listRows())))
                    end

                elseif ev == "key" then
                    if p1 == keys.q or p1 == keys.escape then
                        if countSel() > 0 then selected = {} amounts = {}
                        else return end
                    elseif p1 == keys.r then doFetch() applyFilter() message = "Refreshed" msgTimer = os.clock() + 1
                    elseif p1 == keys.slash then searchMode = true searchQuery = "" applyFilter()
                    elseif p1 == keys.enter then if countSel() > 0 then doConfirm() end end
                end
            end
        end
    end
end

return plugin
