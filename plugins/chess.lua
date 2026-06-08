-- Chess Plugin v1
-- Full chess game for CraftOS / CC:Tweaked
-- Modes: vs Bot (4 difficulties) | Multiplayer via rednet
-- plugin.patch = false  (appears as menu entry)

local plugin = {}
plugin.name  = "Chess"
plugin.label = "Chess"
plugin.priority = 10

-- ── Constants ─────────────────────────────────────────────────────────────────
local PROTOCOL = "chess_plugin"

-- Piece codes: uppercase=white, lowercase=black
-- K/k=king Q/q=queen R/r=rook B/b=bishop N/n=knight P/p=pawn
local EMPTY = "."

-- Colors for board rendering
local CLR_LIGHT   = colors.white
local CLR_DARK    = colors.brown
local CLR_W_PIECE = colors.yellow
local CLR_B_PIECE = colors.blue
local CLR_SEL     = colors.lime
local CLR_MOVE    = colors.cyan
local CLR_CHECK   = colors.red
local CLR_UI_BG   = colors.black
local CLR_UI_FG   = colors.white

-- Board cell size in terminal chars (width x height)
local CW = 3  -- cell width
local CH = 1  -- cell height (terminal is wider than tall)

-- ── Board helpers ─────────────────────────────────────────────────────────────
local function newBoard()
    return {
        {"r","n","b","q","k","b","n","r"},
        {"p","p","p","p","p","p","p","p"},
        {".",".",".",".",".",".",".",".",},
        {".",".",".",".",".",".",".",".",},
        {".",".",".",".",".",".",".",".",},
        {".",".",".",".",".",".",".",".",},
        {"P","P","P","P","P","P","P","P"},
        {"R","N","B","Q","K","B","N","R"},
    }
end

local function isWhite(p) return p ~= EMPTY and p == p:upper() end
local function isBlack(p) return p ~= EMPTY and p == p:lower() end
local function isEmpty(p) return p == EMPTY end
local function sameColor(a,b)
    if isEmpty(a) or isEmpty(b) then return false end
    return isWhite(a) == isWhite(b)
end
local function pieceType(p) return p:lower() end

local function copyBoard(b)
    local nb = {}
    for r=1,8 do nb[r]={} for c=1,8 do nb[r][c]=b[r][c] end end
    return nb
end

-- ── Move generation ───────────────────────────────────────────────────────────
local function inBounds(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end

local function slideMoves(board, r, c, dirs)
    local moves = {}
    local p = board[r][c]
    for _, d in ipairs(dirs) do
        local nr, nc = r+d[1], c+d[2]
        while inBounds(nr,nc) do
            if isEmpty(board[nr][nc]) then
                table.insert(moves, {nr,nc})
            elseif not sameColor(p, board[nr][nc]) then
                table.insert(moves, {nr,nc}) break
            else break end
            nr,nc = nr+d[1], nc+d[2]
        end
    end
    return moves
end

local function stepMoves(board, r, c, steps)
    local moves = {}
    local p = board[r][c]
    for _, d in ipairs(steps) do
        local nr, nc = r+d[1], c+d[2]
        if inBounds(nr,nc) and not sameColor(p, board[nr][nc]) then
            table.insert(moves, {nr,nc})
        end
    end
    return moves
end

local function pawnMoves(board, r, c, state)
    local moves = {}
    local p = board[r][c]
    local dir = isWhite(p) and -1 or 1
    local startRow = isWhite(p) and 7 or 2

    -- forward
    if inBounds(r+dir,c) and isEmpty(board[r+dir][c]) then
        table.insert(moves, {r+dir,c})
        if r==startRow and isEmpty(board[r+2*dir][c]) then
            table.insert(moves, {r+2*dir,c})
        end
    end
    -- captures
    for _, dc in ipairs({-1,1}) do
        local nr,nc = r+dir, c+dc
        if inBounds(nr,nc) then
            if not isEmpty(board[nr][nc]) and not sameColor(p,board[nr][nc]) then
                table.insert(moves, {nr,nc})
            end
            -- en passant
            if state.enPassant and state.enPassant[1]==nr and state.enPassant[2]==nc then
                table.insert(moves, {nr,nc,"ep"})
            end
        end
    end
    return moves
end

local function rawMoves(board, r, c, state)
    local p = board[r][c]
    local t = pieceType(p)
    if t=="p" then return pawnMoves(board,r,c,state)
    elseif t=="r" then return slideMoves(board,r,c,{{0,1},{0,-1},{1,0},{-1,0}})
    elseif t=="b" then return slideMoves(board,r,c,{{1,1},{1,-1},{-1,1},{-1,-1}})
    elseif t=="q" then return slideMoves(board,r,c,{{0,1},{0,-1},{1,0},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1}})
    elseif t=="n" then return stepMoves(board,r,c,{{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}})
    elseif t=="k" then
        local moves = stepMoves(board,r,c,{{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}})
        -- castling
        if state then
            local cr = isWhite(p) and 8 or 1
            local ck = isWhite(p) and "K" or "k"
            if state.castling[ck] and board[cr][5]==p then
                -- kingside
                local cq = isWhite(p) and "KS" or "kS"
                if state.castling[cq] and board[cr][8]==(isWhite(p) and "R" or "r")
                    and isEmpty(board[cr][6]) and isEmpty(board[cr][7]) then
                    table.insert(moves, {cr,7,"castle_ks"})
                end
                -- queenside
                local cqs = isWhite(p) and "KQ" or "kQ"
                if state.castling[cqs] and board[cr][1]==(isWhite(p) and "R" or "r")
                    and isEmpty(board[cr][2]) and isEmpty(board[cr][3]) and isEmpty(board[cr][4]) then
                    table.insert(moves, {cr,3,"castle_qs"})
                end
            end
        end
        return moves
    end
    return {}
end

local function findKing(board, white)
    local k = white and "K" or "k"
    for r=1,8 do for c=1,8 do
        if board[r][c]==k then return r,c end
    end end
end

local function isAttacked(board, r, c, byWhite, state)
    -- check if square r,c is attacked by byWhite's pieces
    for br=1,8 do for bc=1,8 do
        local p = board[br][bc]
        if (byWhite and isWhite(p)) or (not byWhite and isBlack(p)) then
            local ms = rawMoves(board, br, bc, state or {castling={},enPassant=nil})
            for _, m in ipairs(ms) do
                if m[1]==r and m[2]==c then return true end
            end
        end
    end end
    return false
end

local function inCheck(board, white, state)
    local kr,kc = findKing(board, white)
    if not kr then return false end
    return isAttacked(board, kr, kc, not white, state)
end

local function applyMove(board, state, r, c, nr, nc, flag)
    local nb = copyBoard(board)
    local ns = {
        castling = {},
        enPassant = nil,
        whiteToMove = not state.whiteToMove,
    }
    for k,v in pairs(state.castling) do ns.castling[k]=v end

    local p = nb[r][c]
    nb[nr][nc] = p
    nb[r][c]   = EMPTY

    -- en passant capture
    if flag=="ep" then
        local dir = isWhite(p) and 1 or -1
        nb[nr+dir][nc] = EMPTY
    end
    -- castling rook move
    if flag=="castle_ks" then
        nb[nr][6] = nb[nr][8] nb[nr][8] = EMPTY
    elseif flag=="castle_qs" then
        nb[nr][4] = nb[nr][1] nb[nr][1] = EMPTY
    end
    -- pawn double push → en passant target
    if pieceType(p)=="p" and math.abs(nr-r)==2 then
        local dir2 = isWhite(p) and -1 or 1
        ns.enPassant = {r+dir2, c}
    end
    -- promotion (auto-queen)
    if pieceType(p)=="p" and (nr==1 or nr==8) then
        nb[nr][nc] = isWhite(p) and "Q" or "q"
    end
    -- revoke castling rights
    if p=="K" then ns.castling["K"]=nil ns.castling["KS"]=nil ns.castling["KQ"]=nil
    elseif p=="k" then ns.castling["k"]=nil ns.castling["kS"]=nil ns.castling["kQ"]=nil
    elseif p=="R" then
        if r==8 and c==8 then ns.castling["KS"]=nil
        elseif r==8 and c==1 then ns.castling["KQ"]=nil end
    elseif p=="r" then
        if r==1 and c==8 then ns.castling["kS"]=nil
        elseif r==1 and c==1 then ns.castling["kQ"]=nil end
    end
    return nb, ns
end

local function legalMoves(board, r, c, state)
    local raw  = rawMoves(board, r, c, state)
    local legal = {}
    local p    = board[r][c]
    local white= isWhite(p)
    for _, m in ipairs(raw) do
        local nb, ns = applyMove(board, state, r, c, m[1], m[2], m[3])
        if not inCheck(nb, white, ns) then
            table.insert(legal, m)
        end
    end
    return legal
end

local function allLegalMoves(board, state, white)
    local all = {}
    for r=1,8 do for c=1,8 do
        local p = board[r][c]
        if (white and isWhite(p)) or (not white and isBlack(p)) then
            local ms = legalMoves(board, r, c, state)
            for _, m in ipairs(ms) do
                table.insert(all, {r,c,m[1],m[2],m[3]})
            end
        end
    end end
    return all
end

local function isCheckmate(board, state, white)
    return #allLegalMoves(board,state,white)==0 and inCheck(board,white,state)
end
local function isStalemate(board, state, white)
    return #allLegalMoves(board,state,white)==0 and not inCheck(board,white,state)
end

-- ── Piece value table ─────────────────────────────────────────────────────────
local pieceVal = {p=100,n=320,b=330,r=500,q=900,k=20000}

local pstPawn = {
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0,
}
local pstKnight = {
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
}
local pstBishop = {
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
}
local pstRook = {
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0,
}
local pstQueen = {
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20,
}
local pstKing = {
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20,
}
local pstMap = {p=pstPawn,n=pstKnight,b=pstBishop,r=pstRook,q=pstQueen,k=pstKing}

local function evalBoard(board, state)
    local score = 0
    for r=1,8 do for c=1,8 do
        local p = board[r][c]
        if p ~= EMPTY then
            local t   = pieceType(p)
            local val = pieceVal[t]
            local pst = pstMap[t]
            local idx = isWhite(p) and ((r-1)*8+c) or ((8-r)*8+c)
            local pos = pst and pst[idx] or 0
            if isWhite(p) then score = score + val + pos
            else               score = score - val - pos end
        end
    end end
    return score
end

-- ── Minimax with alpha-beta ───────────────────────────────────────────────────
local function minimax(board, state, depth, alpha, beta, maximizing)
    local white = maximizing
    if depth == 0 then return evalBoard(board, state) end
    local moves = allLegalMoves(board, state, white)
    if #moves == 0 then
        if inCheck(board, white, state) then
            return maximizing and -99999 or 99999
        end
        return 0
    end
    if maximizing then
        local best = -math.huge
        for _, m in ipairs(moves) do
            local nb,ns = applyMove(board,state,m[1],m[2],m[3],m[4],m[5])
            local v = minimax(nb,ns,depth-1,alpha,beta,false)
            if v > best then best = v end
            if v > alpha then alpha = v end
            if beta <= alpha then break end
        end
        return best
    else
        local best = math.huge
        for _, m in ipairs(moves) do
            local nb,ns = applyMove(board,state,m[1],m[2],m[3],m[4],m[5])
            local v = minimax(nb,ns,depth-1,alpha,beta,true)
            if v < best then best = v end
            if v < beta then beta = v end
            if beta <= alpha then break end
        end
        return best
    end
end

local DIFF_DEPTH = {easy=1, medium=2, hard=3, extreme=4}

local function botMove(board, state, diff)
    local depth = DIFF_DEPTH[diff] or 2
    local moves = allLegalMoves(board, state, false)  -- bot plays black
    if #moves == 0 then return nil end
    local bestVal = math.huge
    local bestMove = nil
    -- add some randomness for easy
    if diff == "easy" then
        return moves[math.random(#moves)]
    end
    for _, m in ipairs(moves) do
        local nb,ns = applyMove(board,state,m[1],m[2],m[3],m[4],m[5])
        local v = minimax(nb,ns,depth-1,-math.huge,math.huge,true)
        if v < bestVal then bestVal=v bestMove=m end
    end
    return bestMove
end

-- ── Rendering ─────────────────────────────────────────────────────────────────
-- Board is drawn in top-left. Right panel shows info.
-- Terminal layout (51x19 typical):
--   Cols 1..24  = board (8 cols * 3 chars each)
--   Cols 25..51 = side panel

local BOARD_X = 1   -- board left edge (col)
local BOARD_Y = 2   -- board top edge (row)
local PANEL_X = 26

local function boardToScreen(r, c)
    -- returns top-left screen col,row of cell (r,c)
    return BOARD_X + (c-1)*CW, BOARD_Y + (r-1)*CH
end

local function screenToBoard(mx, my)
    local c = math.floor((mx - BOARD_X) / CW) + 1
    local r = (my - BOARD_Y) + 1
    if r>=1 and r<=8 and c>=1 and c<=8 then return r,c end
    return nil,nil
end

local pieceGlyph = {
    P=" P",p=" p",R=" R",r=" r",N=" N",n=" n",
    B=" B",b=" b",Q=" Q",q=" q",K=" K",k=" k",
    ["."]="  ",
}

local function drawBoard(board, sel, legalSet, state, flipped)
    local W,H = term.getSize()
    for r=1,8 do
        for c=1,8 do
            local dr = flipped and (9-r) or r
            local dc = flipped and (9-c) or c
            local sx, sy = boardToScreen(dr, dc)
            term.setCursorPos(sx, sy)
            local isLight = (r+c)%2==0
            local bg
            if sel and sel[1]==r and sel[2]==c then
                bg = CLR_SEL
            elseif legalSet and legalSet[r..","..c] then
                bg = CLR_MOVE
            elseif state.checkSq and state.checkSq[1]==r and state.checkSq[2]==c then
                bg = CLR_CHECK
            else
                bg = isLight and CLR_LIGHT or CLR_DARK
            end
            local p  = board[r][c]
            local fg = isWhite(p) and CLR_W_PIECE or CLR_B_PIECE
            term.setBackgroundColor(bg)
            term.setTextColor(fg)
            term.write(pieceGlyph[p] or "  ")
            term.write(" ")
        end
    end
end

local function drawRankFile(flipped)
    -- rank numbers on left
    for r=1,8 do
        local dr = flipped and (9-r) or r
        local _,sy = boardToScreen(dr,1)
        term.setCursorPos(BOARD_X+CW*8, sy)
        term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write(tostring(9-r))
    end
    -- file letters on bottom
    for c=1,8 do
        local dc = flipped and (9-c) or c
        local sx,_ = boardToScreen(8,dc)
        term.setCursorPos(sx+1, BOARD_Y+8)
        term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write(string.char(96+c))
    end
end

local function drawPanel(state, msg, timeW, timeB, turn, check, flipped)
    local W,H = term.getSize()
    -- clear panel
    for row=1,H do
        term.setCursorPos(PANEL_X, row)
        term.setBackgroundColor(CLR_UI_BG)
        term.write(string.rep(" ", W-PANEL_X+1))
    end

    local function pw(row, text, fg)
        term.setCursorPos(PANEL_X, row)
        term.setBackgroundColor(CLR_UI_BG)
        term.setTextColor(fg or CLR_UI_FG)
        term.write(tostring(text):sub(1, W-PANEL_X+1))
    end

    pw(1,  "=== CHESS ===", colors.yellow)
    pw(2,  "Turn: " .. (turn and "White" or "Black"), turn and CLR_W_PIECE or CLR_B_PIECE)
    if check then pw(3, "  !! CHECK !!", CLR_CHECK) end
    if timeW then
        pw(4,  "W: " .. math.floor(timeW/60) .. ":" .. string.format("%02d",timeW%60), CLR_W_PIECE)
        pw(5,  "B: " .. math.floor(timeB/60) .. ":" .. string.format("%02d",timeB%60), CLR_B_PIECE)
    end
    if msg and msg ~= "" then
        pw(7, msg, colors.lime)
    end
    pw(H-2, "[Q]=quit", colors.gray)
    pw(H-1, "[F]=flip", colors.gray)
end

-- ── Game loop (shared by bot and local) ──────────────────────────────────────
local function gameLoop(board, state, getMove, onDraw, timeLimit)
    -- getMove(board, state) -> r,c,nr,nc,flag or nil=resign
    -- onDraw() called each frame
    -- timeLimit: seconds per side or nil

    local timeW = timeLimit
    local timeB = timeLimit
    local lastTick = os.clock()
    local flipped  = false
    local sel      = nil
    local legalSet = {}
    local msg      = ""
    local msgTimer = 0
    local result   = nil

    local function setMsg(m) msg=m msgTimer=os.clock()+4 end

    local function redraw(check)
        term.setBackgroundColor(CLR_UI_BG) term.clear()
        drawBoard(board, sel, legalSet, state, flipped)
        drawRankFile(flipped)
        drawPanel(state, os.clock()<msgTimer and msg or "",
                  timeW, timeB,
                  state.whiteToMove, check, flipped)
        if onDraw then onDraw() end
    end

    while not result do
        -- tick timers
        local now = os.clock()
        local dt  = now - lastTick
        lastTick  = now
        if timeLimit then
            if state.whiteToMove then timeW = math.max(0, timeW-dt)
            else                       timeB = math.max(0, timeB-dt) end
            if timeW <= 0 then result="Black wins (time)" break end
            if timeB <= 0 then result="White wins (time)" break end
        end

        local check = inCheck(board, state.whiteToMove, state)
        -- mark king sq for check highlight
        if check then
            local kr,kc = findKing(board, state.whiteToMove)
            state.checkSq = {kr,kc}
        else
            state.checkSq = nil
        end

        redraw(check)

        -- get move
        local mv = getMove(board, state, sel, flipped)
        if mv == "quit" then result="quit" break end
        if mv == "flip" then flipped = not flipped
        elseif mv == "select" then
            local r,c = mv[2],mv[3]  -- handled below
        elseif type(mv)=="table" and #mv>=4 then
            local r,c,nr,nc,flag = mv[1],mv[2],mv[3],mv[4],mv[5]
            board, state = applyMove(board, state, r,c,nr,nc,flag)
            sel = nil legalSet = {}
            -- check end conditions
            local nextWhite = state.whiteToMove
            if isCheckmate(board,state,nextWhite) then
                result = (nextWhite and "Black" or "White") .. " wins by checkmate!"
            elseif isStalemate(board,state,nextWhite) then
                result = "Stalemate — Draw!"
            end
            if check then setMsg("Check!") end
        end
    end

    -- show result
    term.setBackgroundColor(CLR_UI_BG) term.clear()
    drawBoard(board, nil, {}, state, flipped)
    term.setCursorPos(PANEL_X, 5)
    term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.yellow)
    term.write("Game over!")
    term.setCursorPos(PANEL_X, 6)
    term.setTextColor(colors.lime)
    term.write(tostring(result):sub(1,25))
    term.setCursorPos(PANEL_X, 8)
    term.setTextColor(colors.gray)
    term.write("Any key to exit")
    os.pullEvent("key")
end

-- ── Human input handler ───────────────────────────────────────────────────────
local function humanInput(board, state, selRef, flippedRef)
    -- returns move table, "quit", "flip", or nil (wait)
    local ev, p1,p2,p3 = os.pullEventRaw()
    if ev == "key" then
        if p1 == keys.q then return "quit"
        elseif p1 == keys.f then return "flip" end
    elseif ev == "mouse_click" then
        local mx,my = p2,p3
        local r,c = screenToBoard(mx,my)
        if r and c then
            local br = flippedRef and (9-r) or r
            local bc = flippedRef and (9-c) or c
            if selRef[1] then
                -- check if this is a legal move
                local key = br..","..bc
                if selRef.legalSet and selRef.legalSet[key] then
                    local flag = selRef.legalSet[key]
                    return {selRef[1],selRef[2],br,bc,flag~=true and flag or nil}
                else
                    -- reselect
                    selRef[1]=nil selRef[2]=nil selRef.legalSet={}
                    local p = board[br][bc]
                    if p~=EMPTY and isWhite(p)==state.whiteToMove then
                        selRef[1]=br selRef[2]=bc
                        local ms = legalMoves(board,br,bc,state)
                        for _,m in ipairs(ms) do
                            selRef.legalSet[m[1]..","..m[2]] = m[3] or true
                        end
                    end
                end
            else
                local p = board[br][bc]
                if p~=EMPTY and isWhite(p)==state.whiteToMove then
                    selRef[1]=br selRef[2]=bc selRef.legalSet={}
                    local ms = legalMoves(board,br,bc,state)
                    for _,m in ipairs(ms) do
                        selRef.legalSet[m[1]..","..m[2]] = m[3] or true
                    end
                end
            end
        end
    end
    return nil  -- no move yet
end

-- ── Bot game ──────────────────────────────────────────────────────────────────
local function playVsBot(diff)
    local board = newBoard()
    local state = {
        whiteToMove = true,
        castling    = {K=true,k=true,KS=true,KQ=true,kS=true,kQ=true},
        enPassant   = nil,
        checkSq     = nil,
    }
    local sel = {legalSet={}}
    local flipped = false
    local result  = nil

    while not result do
        -- timers / check
        local check = inCheck(board, state.whiteToMove, state)
        if check then
            local kr,kc = findKing(board, state.whiteToMove)
            state.checkSq = {kr,kc}
        else state.checkSq = nil end

        -- draw
        term.setBackgroundColor(CLR_UI_BG) term.clear()
        drawBoard(board, (sel[1] and sel) or nil, sel.legalSet, state, flipped)
        drawRankFile(flipped)
        drawPanel(state, check and "Check!" or "",
                  nil, nil, state.whiteToMove, check, flipped)
        term.setCursorPos(PANEL_X, 4)
        term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write("Diff: "..diff)

        if state.whiteToMove then
            -- human turn
            local mv = humanInput(board, state, sel, flipped)
            if mv == "quit" then break
            elseif mv == "flip" then flipped = not flipped
            elseif type(mv)=="table" then
                board,state = applyMove(board,state,mv[1],mv[2],mv[3],mv[4],mv[5])
                sel = {legalSet={}}
                if isCheckmate(board,state,state.whiteToMove) then
                    result=(state.whiteToMove and "Black" or "White").." wins!"
                elseif isStalemate(board,state,state.whiteToMove) then
                    result="Stalemate!"
                end
            end
        else
            -- bot turn
            term.setCursorPos(PANEL_X, 6)
            term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.yellow)
            term.write("Bot thinking...")
            local bm = botMove(board, state, diff)
            if bm then
                board,state = applyMove(board,state,bm[1],bm[2],bm[3],bm[4],bm[5])
            end
            if isCheckmate(board,state,state.whiteToMove) then
                result=(state.whiteToMove and "Black" or "White").." wins!"
            elseif isStalemate(board,state,state.whiteToMove) then
                result="Stalemate!"
            end
        end
    end

    -- result screen
    term.setBackgroundColor(CLR_UI_BG) term.clear()
    drawBoard(board,nil,{},state,flipped)
    term.setCursorPos(PANEL_X,5) term.setBackgroundColor(CLR_UI_BG)
    term.setTextColor(colors.yellow) term.write("Game Over!")
    term.setCursorPos(PANEL_X,6) term.setTextColor(colors.lime)
    term.write(tostring(result or "Quit"):sub(1,25))
    term.setCursorPos(PANEL_X,8) term.setTextColor(colors.gray) term.write("Any key...")
    os.pullEvent("key")
end

-- ── Multiplayer ───────────────────────────────────────────────────────────────
local function mpSend(id, msg)
    rednet.send(id, msg, PROTOCOL)
end
local function mpReceive(timeout)
    local id, msg = rednet.receive(PROTOCOL, timeout or 10)
    return id, msg
end

local function playMultiplayer(isHost, peerId, timeLimit, rules)
    local board = newBoard()
    local state = {
        whiteToMove = true,
        castling    = {K=true,k=true,KS=true,KQ=true,kS=true,kQ=true},
        enPassant   = nil,
        checkSq     = nil,
    }
    local myWhite = isHost  -- host plays white
    local sel     = {legalSet={}}
    local flipped = not myWhite
    local result  = nil
    local timeW   = timeLimit
    local timeB   = timeLimit
    local lastTick= os.clock()
    local msg     = ""
    local msgTimer= 0

    local function setMsg(m) msg=m msgTimer=os.clock()+4 end

    while not result do
        local now = os.clock()
        local dt  = now - lastTick lastTick = now
        if timeLimit then
            if state.whiteToMove then timeW=math.max(0,timeW-dt)
            else                       timeB=math.max(0,timeB-dt) end
            if timeW<=0 then result="Black wins (time)" break end
            if timeB<=0 then result="White wins (time)" break end
        end

        local check = inCheck(board,state.whiteToMove,state)
        if check then
            local kr,kc = findKing(board,state.whiteToMove)
            state.checkSq={kr,kc}
            if state.whiteToMove==myWhite then setMsg("!! CHECK !!") end
        else state.checkSq=nil end

        term.setBackgroundColor(CLR_UI_BG) term.clear()
        drawBoard(board,(sel[1] and sel) or nil, sel.legalSet, state, flipped)
        drawRankFile(flipped)
        drawPanel(state, os.clock()<msgTimer and msg or "",
                  timeW, timeB, state.whiteToMove, check, flipped)
        term.setCursorPos(PANEL_X,4)
        term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write("You="..(myWhite and "White" or "Black"))

        if state.whiteToMove == myWhite then
            -- my turn: human input
            local mv = humanInput(board, state, sel, flipped)
            if mv=="quit" then
                mpSend(peerId, {type="resign"})
                result="You resigned"
            elseif mv=="flip" then flipped=not flipped
            elseif type(mv)=="table" then
                board,state = applyMove(board,state,mv[1],mv[2],mv[3],mv[4],mv[5])
                sel={legalSet={}}
                mpSend(peerId, {type="move", m=mv})
                if isCheckmate(board,state,state.whiteToMove) then
                    result=(myWhite and "White" or "Black").." wins!"
                elseif isStalemate(board,state,state.whiteToMove) then
                    result="Stalemate!"
                end
            end
        else
            -- opponent turn: wait for rednet or input (quit/flip only)
            local ev = {os.pullEventRaw(0.1)}
            if ev[1]=="key" then
                if ev[2]==keys.q then
                    mpSend(peerId,{type="resign"}) result="You resigned"
                elseif ev[2]==keys.f then flipped=not flipped end
            elseif ev[1]=="rednet_message" then
                local sid,smsg = ev[2],ev[3]
                if sid==peerId and type(smsg)=="table" then
                    if smsg.type=="move" then
                        local m=smsg.m
                        board,state=applyMove(board,state,m[1],m[2],m[3],m[4],m[5])
                        if isCheckmate(board,state,state.whiteToMove) then
                            result=(myWhite and "Black" or "White").." wins!"
                        elseif isStalemate(board,state,state.whiteToMove) then
                            result="Stalemate!"
                        end
                    elseif smsg.type=="resign" then
                        result="Opponent resigned — You win!"
                    end
                end
            end
        end
    end

    term.setBackgroundColor(CLR_UI_BG) term.clear()
    drawBoard(board,nil,{},state,flipped)
    term.setCursorPos(PANEL_X,5) term.setBackgroundColor(CLR_UI_BG)
    term.setTextColor(colors.yellow) term.write("Game Over!")
    term.setCursorPos(PANEL_X,6) term.setTextColor(colors.lime)
    term.write(tostring(result or ""):sub(1,25))
    term.setCursorPos(PANEL_X,8) term.setTextColor(colors.gray) term.write("Any key...")
    os.pullEvent("key")
end

-- ── Lobby (room list) ─────────────────────────────────────────────────────────
local LOBBY_HOST = 0  -- broadcast
local rooms = {}  -- {id, owner, timeLimit, rules}

local function broadcastRoom(myId, timeLimit, rules)
    rednet.broadcast({
        type="chess_room", id=myId,
        owner=os.getComputerLabel() or ("PC#"..myId),
        timeLimit=timeLimit, rules=rules
    }, PROTOCOL)
end

local function lobbyScreen()
    local W,H = term.getSize()
    local myId = os.getComputerID()
    rooms = {}
    local scroll = 0
    local selected = nil
    local msg = ""
    local msgTimer = 0
    local scanTimer = os.startTimer(0.5)

    -- broadcast my presence
    rednet.broadcast({type="chess_scan"}, PROTOCOL)

    while true do
        W,H = term.getSize()
        term.setBackgroundColor(CLR_UI_BG) term.clear()

        -- header
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        term.write(" Chess Lobby  [C]=create  [R]=refresh  [Q]=back")

        -- room list
        local listH = H-3
        for row=1,listH do
            local room = rooms[row+scroll]
            term.setCursorPos(1,row+1) term.setBackgroundColor(CLR_UI_BG)
            if room then
                local isSel = selected and selected.id==room.id
                term.setBackgroundColor(isSel and colors.gray or CLR_UI_BG)
                term.setTextColor(isSel and colors.yellow or CLR_UI_FG)
                local tl = room.timeLimit and (room.timeLimit.."s") or "∞"
                term.write(string.format(" %-15s  time:%-4s  ", room.owner:sub(1,15), tl))
            else
                term.setTextColor(CLR_UI_BG) term.write(string.rep(" ",W))
            end
        end

        -- status
        term.setCursorPos(1,H) term.setBackgroundColor(CLR_UI_BG)
        if msg~="" and os.clock()<msgTimer then
            term.setTextColor(colors.lime) term.write(msg:sub(1,W))
        else
            term.setTextColor(colors.gray)
            term.write("Click room to join | "..#rooms.." room(s)")
        end

        local ev,p1,p2,p3 = os.pullEventRaw()
        if ev=="timer" and p1==scanTimer then
            rednet.broadcast({type="chess_scan"}, PROTOCOL)
            scanTimer = os.startTimer(3)
        elseif ev=="rednet_message" then
            local sid,smsg = p2,p3
            if type(smsg)=="table" then
                if smsg.type=="chess_room" and smsg.id~=myId then
                    -- upsert room
                    local found=false
                    for i,r in ipairs(rooms) do
                        if r.id==smsg.id then rooms[i]=smsg found=true break end
                    end
                    if not found then table.insert(rooms,smsg) end
                elseif smsg.type=="chess_scan" then
                    -- ignore, we're not hosting
                end
            end
        elseif ev=="mouse_click" then
            local mx,my=p2,p3
            local idx=(my-1)+scroll
            if idx>=1 and idx<=#rooms then
                selected=rooms[idx]
                -- join
                rednet.send(selected.id,{type="chess_join",from=myId},PROTOCOL)
                msg="Waiting for host..." msgTimer=os.clock()+10
                -- wait for accept
                local _,resp = rednet.receive(PROTOCOL, 10)
                if type(resp)=="table" and resp.type=="chess_accept" then
                    return "join", selected.id, selected.timeLimit, selected.rules
                else
                    msg="No response" msgTimer=os.clock()+3 selected=nil
                end
            end
        elseif ev=="key" then
            if p1==keys.q then return "back"
            elseif p1==keys.r then
                rooms={} rednet.broadcast({type="chess_scan"},PROTOCOL)
            elseif p1==keys.c then
                return "create"
            elseif p1==keys.up and scroll>0 then scroll=scroll-1
            elseif p1==keys.down and scroll<#rooms-listH then scroll=scroll+1
            end
        elseif ev=="mouse_scroll" then
            scroll=math.max(0,math.min(scroll+p1,math.max(0,#rooms-listH)))
        end
    end
end

local function createRoomScreen()
    local W,H = term.getSize()
    local myId = os.getComputerID()
    local timeOptions = {"No limit","1 min","3 min","5 min","10 min"}
    local timeValues  = {nil,60,180,300,600}
    local selTime     = 1
    local rules       = {fiftyMove=true, threeRep=false}

    while true do
        term.setBackgroundColor(CLR_UI_BG) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Create Room")

        term.setCursorPos(1,3) term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.white)
        term.write("Time control:")
        for i,opt in ipairs(timeOptions) do
            term.setCursorPos(3,3+i)
            if i==selTime then
                term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else
                term.setBackgroundColor(CLR_UI_BG) term.setTextColor(CLR_UI_FG)
            end
            term.write(" "..opt.." ")
        end

        term.setCursorPos(1,10) term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.white)
        term.write("Rules:")
        term.setCursorPos(3,11)
        term.setTextColor(rules.fiftyMove and colors.lime or colors.red)
        term.write("["..(rules.fiftyMove and "x" or " ").."] 50-move rule")
        term.setCursorPos(3,12)
        term.setTextColor(rules.threeRep and colors.lime or colors.red)
        term.write("["..(rules.threeRep and "x" or " ").."] 3-fold repetition")

        term.setCursorPos(1,H-1) term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write("[Enter]=host  [Q]=back")

        local ev,p1,p2,p3 = os.pullEventRaw()
        if ev=="key" then
            if p1==keys.q then return nil,nil,nil
            elseif p1==keys.up and selTime>1 then selTime=selTime-1
            elseif p1==keys.down and selTime<#timeOptions then selTime=selTime+1
            elseif p1==keys.enter then
                return myId, timeValues[selTime], rules
            end
        elseif ev=="mouse_click" then
            local mx,my=p2,p3
            for i=1,#timeOptions do
                if my==3+i then selTime=i end
            end
            if my==11 then rules.fiftyMove=not rules.fiftyMove end
            if my==12 then rules.threeRep=not rules.threeRep end
        end
    end
end

local function hostRoom(timeLimit, rules)
    local myId = os.getComputerID()
    local W,H  = term.getSize()
    local scanTimer = os.startTimer(0.5)
    local peerId = nil

    while not peerId do
        term.setBackgroundColor(CLR_UI_BG) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Hosting Room — waiting...")
        term.setCursorPos(1,3) term.setBackgroundColor(CLR_UI_BG) term.setTextColor(CLR_UI_FG)
        local tl = timeLimit and (timeLimit.."s") or "no limit"
        term.write("Time: "..tl)
        term.setCursorPos(1,H) term.setTextColor(colors.gray) term.write("[Q]=cancel")

        local ev,p1,p2,p3 = os.pullEventRaw()
        if ev=="timer" and p1==scanTimer then
            broadcastRoom(myId, timeLimit, rules)
            scanTimer = os.startTimer(2)
        elseif ev=="rednet_message" then
            local sid,smsg = p2,p3
            if type(smsg)=="table" and smsg.type=="chess_join" then
                peerId = smsg.from
                rednet.send(peerId,{type="chess_accept"},PROTOCOL)
            end
        elseif ev=="key" and p1==keys.q then
            return
        end
    end

    playMultiplayer(true, peerId, timeLimit, rules)
end

-- ── Difficulty select ─────────────────────────────────────────────────────────
local function diffSelect()
    local opts = {
        {label="Easy",   diff="easy",   icon=colors.lime},
        {label="Medium", diff="medium", icon=colors.yellow},
        {label="Hard",   diff="hard",   icon=colors.orange},
        {label="Extreme",diff="extreme",icon=colors.red},
    }
    while true do
        term.setBackgroundColor(CLR_UI_BG) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" vs Bot — Choose Difficulty")
        for i,opt in ipairs(opts) do
            term.setCursorPos(1,i+2)
            term.setBackgroundColor(opt.icon) term.setTextColor(colors.black) term.write(" ")
            term.setBackgroundColor(CLR_UI_BG) term.setTextColor(CLR_UI_FG)
            term.write(" "..opt.label..string.rep(" ",20))
        end
        term.setCursorPos(1,8) term.setBackgroundColor(CLR_UI_BG) term.setTextColor(colors.gray)
        term.write("[Q]=back")

        local ev,p1,p2,p3 = os.pullEventRaw()
        if ev=="key" and p1==keys.q then return nil end
        if ev=="mouse_click" then
            local my=p3
            for i,opt in ipairs(opts) do
                if my==i+2 then return opt.diff end
            end
        end
    end
end

-- ── Main menu ─────────────────────────────────────────────────────────────────
function plugin.run()
    local menuItems = {
        {label="vs Bot",       icon=colors.green },
        {label="Multiplayer",  icon=colors.blue  },
    }
    while true do
        local sel = clickMenu("Chess", menuItems)
        if not sel then return end
        if sel==1 then
            local diff = diffSelect()
            if diff then playVsBot(diff) end
        elseif sel==2 then
            -- multiplayer lobby
            while true do
                local action, peerId, tl, rules = lobbyScreen()
                if action=="back" then break
                elseif action=="join" then
                    playMultiplayer(false, peerId, tl, rules)
                    break
                elseif action=="create" then
                    local _, timeLimit, myRules = createRoomScreen()
                    if timeLimit ~= nil or myRules ~= nil then
                        hostRoom(timeLimit, myRules)
                    end
                end
            end
        end
    end
end

return plugin