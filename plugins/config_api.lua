-- Config API Plugin v2
-- patch plugin: injects global "configAPI"
-- Saves per-plugin configs in config/pluginname.cfg
-- Applies onChange on boot

local plugin  = {}
plugin.name   = "config_api"
plugin.label  = "config_api"
plugin.patch  = true
plugin.priority = 1  -- must run before autologin (priority 2)

function plugin.run()

local CFG_DIR = "config"

-- ── Storage ───────────────────────────────────────────────────────────────────
local function cfgPath(pname)
    return CFG_DIR.."/"..pname:lower():gsub("[^a-z0-9_]","_")..".cfg"
end
local function loadCfg(pname)
    local db={}
    local path=cfgPath(pname)
    if not fs.exists(path) then return db end
    local f=fs.open(path,"r")
    while true do
        local line=f.readLine() if not line then break end
        local k,v=line:match("^([^=]+)=(.*)$")
        if k then db[k]=v end
    end
    f.close() return db
end
local function saveCfg(pname,db)
    if not fs.isDir(CFG_DIR) then fs.makeDir(CFG_DIR) end
    local f=fs.open(cfgPath(pname),"w")
    for k,v in pairs(db) do f.writeLine(k.."="..tostring(v)) end
    f.close()
end
local function parseVal(v)
    if v=="true" then return true end
    if v=="false" then return false end
    local n=tonumber(v) if n then return n end
    return v
end

-- ── Registry ──────────────────────────────────────────────────────────────────
local registry={}
local byKey={}
local cfgCache={}

local function getCache(pname)
    if not cfgCache[pname] then cfgCache[pname]=loadCfg(pname) end
    return cfgCache[pname]
end

local function register(entry)
    if byKey[entry.key] then return end
    local raw=getCache(entry.plugin)[entry.key]
    entry.value = raw~=nil and parseVal(raw) or entry.default
    entry.onChange = entry.onChange or function() end
    pcall(entry.onChange, entry.value)
    table.insert(registry,entry)
    byKey[entry.key]=entry
end

local function get(key)
    local e=byKey[key] return e and e.value or nil
end
local function set(key,value)
    local e=byKey[key] if not e then return end
    e.value=value
    local cache=getCache(e.plugin)
    cache[e.key]=tostring(value)
    saveCfg(e.plugin,cache)
    pcall(e.onChange,value)
end

-- ── Colors ────────────────────────────────────────────────────────────────────
local COLOR_LIST={
    {name="Blue",      c=colors.blue     },
    {name="Red",       c=colors.red      },
    {name="Green",     c=colors.green    },
    {name="Purple",    c=colors.purple   },
    {name="Cyan",      c=colors.cyan     },
    {name="Orange",    c=colors.orange   },
    {name="Magenta",   c=colors.magenta  },
    {name="Gray",      c=colors.gray     },
    {name="LightBlue", c=colors.lightBlue},
    {name="Yellow",    c=colors.yellow   },
    {name="Lime",      c=colors.lime     },
    {name="Brown",     c=colors.brown    },
}
local function colorName(c)
    for _,col in ipairs(COLOR_LIST) do if col.c==c then return col.name end end
    return "?"
end

-- ── Theme color helper ────────────────────────────────────────────────────────
-- Uses cloudThemeColor if set by theme.lua, otherwise falls back to colors.blue
local function themeColor()
    return _G.cloudThemeColor or colors.blue
end

-- ── Widgets (all values forced to string where needed) ───────────────────────
local function drawSlider(x,y,w,value,minV,maxV,step,col)
    local trackW=math.max(2,w-8)
    local range=maxV-minV
    local filled=range>0 and math.floor((value-minV)/range*trackW) or 0
    filled=math.max(0,math.min(filled,trackW))
    term.setCursorPos(x,y)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white) term.write("[")
    term.setTextColor(colors.lightGray) term.write("<")
    term.setBackgroundColor(col or themeColor()) term.setTextColor(col or themeColor())
    term.write(string.rep(" ",filled))
    term.setBackgroundColor(colors.gray) term.setTextColor(colors.gray)
    term.write(string.rep(" ",trackW-filled))
    term.setBackgroundColor(colors.black) term.setTextColor(colors.lightGray) term.write(">")
    term.setTextColor(colors.gray) term.write("]")
    term.setTextColor(colors.yellow) term.write(" "..tostring(value))
    return {row=y,decX=x+1,incX=x+2+trackW,trackX1=x+2,trackX2=x+1+trackW,trackW=trackW}
end

local function drawCheckbox(x,y,value,label)
    term.setCursorPos(x,y) term.setBackgroundColor(colors.black)
    if value then term.setTextColor(colors.lime) term.write("[x] ")
    else          term.setTextColor(colors.gray) term.write("[ ] ") end
    term.setTextColor(colors.white) term.write(tostring(label or ""))
    return {row=y,x1=x,x2=x+3}
end

local function drawTextbox(x,y,w,value,focused,label)
    -- value always string
    local str=tostring(value or "")
    if label and label~="" then
        term.setCursorPos(x,y) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white) term.write(label..": ")
        x=x+#label+2 w=w-#label-2
    end
    term.setCursorPos(x,y)
    term.setBackgroundColor(focused and colors.gray or colors.black)
    term.setTextColor(colors.white)
    local avail=math.max(1,w-3)
    local disp=str:sub(-avail)
    local pad=math.max(0,avail-#disp)
    term.write("["..disp..(focused and "_" or " ")..string.rep(" ",pad).."]")
    return {row=y,x1=x,x2=x+w-1}
end

local function drawColorPicker(x,y,cur)
    for i,col in ipairs(COLOR_LIST) do
        term.setCursorPos(x+i-1,y)
        term.setBackgroundColor(col.c) term.setTextColor(colors.white)
        term.write(col.c==cur and "*" or " ")
    end
    term.setBackgroundColor(colors.black) term.setTextColor(colors.yellow)
    term.write(" "..colorName(cur))
    return {row=y,x1=x,x2=x+#COLOR_LIST-1}
end

-- ── Settings screen ───────────────────────────────────────────────────────────
-- Layout: plugin list (like main menu) → click plugin → its settings page → back
-- No horizontal tabs. Each plugin is a full page.

local function settingsScreen()
    local W,H=term.getSize()

    -- gather plugins
    local plugNames={}
    local plugMap={}
    for _,e in ipairs(registry) do
        if not plugMap[e.plugin] then
            table.insert(plugNames,e.plugin)
            plugMap[e.plugin]={}
        end
        table.insert(plugMap[e.plugin],e)
    end

    if #plugNames==0 then
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(themeColor()) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Settings")
        term.setCursorPos(1,3) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("No settings registered.")
        term.setCursorPos(1,H) term.write("[Q] back")
        repeat local ev,p1=os.pullEvent()
        until (ev=="key" and (p1==keys.q or p1==keys.escape)) or ev=="mouse_click"
        return
    end

    -- ── Plugin list page (like main menu) ─────────────────────────────────────
    local function drawPluginList()
        W,H=term.getSize()
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(themeColor()) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        term.write(" Settings")
        term.setCursorPos(W-2,1) term.write("[X]")
        for i,name in ipairs(plugNames) do
            local row=i+2
            if row>H-1 then break end
            term.setCursorPos(1,row)
            term.setBackgroundColor(colors.purple) term.setTextColor(colors.black)
            term.write(" ")
            term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
            term.write(" "..name..string.rep(" ",W-#name-2))
        end
        term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("[Q] back")
    end

    -- ── Single plugin config page ─────────────────────────────────────────────
    local function pluginPage(pname)
        local ents=plugMap[pname] or {}
        local focusIdx=nil
        local scroll=0

        local CONTENT_TOP=4   -- first content row
        local function maxScroll()
            return math.max(0,#ents - math.floor((H-CONTENT_TOP)/3))
        end

        local function draw()
            W,H=term.getSize()
            term.setBackgroundColor(colors.black) term.clear()
            -- header
            term.setBackgroundColor(themeColor()) term.setTextColor(colors.white)
            term.setCursorPos(1,1) term.clearLine()
            term.write(" "..pname)
            term.setCursorPos(W-2,1) term.write("[X]")
            -- breadcrumb
            term.setCursorPos(1,2) term.setBackgroundColor(colors.black)
            term.setTextColor(colors.gray) term.clearLine()
            term.write(" Settings > "..pname)
            -- divider
            term.setCursorPos(1,3) term.setTextColor(colors.gray)
            term.write(string.rep("-",W))

            local visY=CONTENT_TOP
            for idx=1+scroll,#ents do
                local e=ents[idx]
                if visY>H-2 then break end

                -- label
                term.setCursorPos(1,visY) term.setBackgroundColor(colors.black)
                term.setTextColor(colors.lightGray) term.clearLine()
                term.write(" "..e.label..":")
                visY=visY+1
                if visY>H-2 then break end

                -- widget
                term.setCursorPos(1,visY) term.setBackgroundColor(colors.black)
                term.clearLine()
                if e.type=="checkbox" then
                    drawCheckbox(3,visY,e.value,"")
                elseif e.type=="text" then
                    drawTextbox(3,visY,W-2,e.value,focusIdx==idx,"")
                elseif e.type=="color" then
                    drawColorPicker(3,visY,e.value)
                elseif e.type=="slider" then
                    drawSlider(3,visY,W-2,e.value,e.min,e.max,e.step or 1,e.sliderColor)
                end
                visY=visY+2
            end

            -- scroll arrows
            if scroll>0 then
                term.setCursorPos(W,CONTENT_TOP)
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("^")
            end
            if scroll<maxScroll() then
                term.setCursorPos(W,H-2)
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.white) term.write("v")
            end

            -- hint
            term.setCursorPos(1,H-1) term.setBackgroundColor(colors.black)
            term.setTextColor(colors.gray) term.clearLine()
            if focusIdx then
                term.setTextColor(colors.yellow) term.write(" Typing... [Enter]=done [Bksp]=delete")
            else
                term.write(" Click to change  [Q]=back")
            end
            term.setCursorPos(1,H) term.clearLine()
        end

        -- hit test: returns entry index and whether it's on widget row
        local function hitEntry(mx,my)
            local visY=CONTENT_TOP
            for idx=1+scroll,#ents do
                if visY>H-2 then break end
                local labelRow=visY
                local widgetRow=visY+1
                if my==labelRow or my==widgetRow then
                    return idx, my==widgetRow
                end
                visY=visY+3
            end
            return nil,false
        end

        while true do
            draw()
            local ev,p1,p2,p3=os.pullEvent()

            if ev=="term_resize" then W,H=term.getSize()
            elseif ev=="key" then
                if p1==keys.q or p1==keys.escape then
                    if focusIdx then focusIdx=nil
                    else return end
                elseif p1==keys.enter then focusIdx=nil
                elseif p1==keys.backspace and focusIdx then
                    local e=ents[focusIdx]
                    if e and e.type=="text" then
                        set(e.key, tostring(e.value or ""):sub(1,-2))
                    end
                end
            elseif ev=="char" then
                if focusIdx then
                    local e=ents[focusIdx]
                    if e and e.type=="text" then
                        set(e.key, tostring(e.value or "")..p1)
                    end
                end
            elseif ev=="mouse_scroll" then
                scroll=math.max(0,math.min(scroll+p1,maxScroll()))
            elseif ev=="mouse_click" then
                local mx,my=p2,p3
                if my==1 and mx>=W-2 then return end
                local idx,onWidget=hitEntry(mx,my)
                if idx then
                    local e=ents[idx]
                    if e.type=="checkbox" then
                        set(e.key, not e.value)
                    elseif e.type=="text" then
                        focusIdx=idx
                    elseif e.type=="color" and onWidget then
                        local ci=mx-3+1
                        if ci>=1 and ci<=#COLOR_LIST then
                            set(e.key,COLOR_LIST[ci].c)
                        end
                    elseif e.type=="slider" and onWidget then
                        local trackW=math.max(2,W-2-8)
                        local tx1=3+2 local tx2=tx1+trackW-1
                        local step=e.step or 1
                        if mx==tx1-1 then
                            set(e.key,math.max(e.min,e.value-step))
                        elseif mx==tx2+1 then
                            set(e.key,math.min(e.max,e.value+step))
                        elseif mx>=tx1 and mx<=tx2 then
                            local frac=(mx-tx1)/(tx2-tx1)
                            local v=e.min+math.floor(frac*(e.max-e.min)/step+0.5)*step
                            set(e.key,math.max(e.min,math.min(e.max,v)))
                        end
                    end
                end
            end
        end
    end

    -- ── Plugin list loop ──────────────────────────────────────────────────────
    while true do
        drawPluginList()
        local ev,p1,p2,p3=os.pullEvent()
        if ev=="key" and (p1==keys.q or p1==keys.escape) then return end
        if ev=="mouse_click" then
            local mx,my=p2,p3
            if my==1 and mx>=W-2 then return end
            local idx=my-2
            if idx>=1 and idx<=#plugNames then
                pluginPage(plugNames[idx])
            end
        end
    end
end

-- ── Expose global ─────────────────────────────────────────────────────────────
configAPI={
    register=register,
    get=get,
    set=set,
    settingsScreen=settingsScreen,
    colors=COLOR_LIST,
}

end -- plugin.run
return plugin
