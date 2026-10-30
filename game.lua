-- Pass the Word game logic, after the classic TV word-guessing format.
-- Pure Lua, no UI: the screen drives the timers and calls these methods.
--
-- Four players, two teams of two. Players 1-2 are team A, 3-4 team B.
--   * Qualification: 4 rounds, each team plays a 30 s turn per round with 5
--     words; the clue-giver and the guesser swap roles every round. Found = +1,
--     Pass = the word goes to the end of the turn's list, Forbidden = lost.
--   * Tie-break (equal scores): one word for both teams, the clue-givers take
--     10 s turns; the first team to find it wins, a forbidden clue eliminates.
--   * Final: the best team climbs a 5-level ladder. Each level: find 5 words
--     in 1:30 out of a shrinking list, 3 clues at most per word, Pass = lost.
--     After a cleared level the team may stop and keep the prize, or go on.
--     Level 2 is the safety level and unlocks the joker (a preview of the
--     next level's first 5 words).
--
-- With `swap` on, rounds 3-4 mix the teams (1 with 4, 3 with 2) and the
-- ranking is individual: the two best players play the final.

local Game = {}
Game.__index = Game

Game.QUAL_ROUNDS  = 4
Game.QUAL_WORDS   = 5
Game.QUAL_TIME    = 30
Game.TB_SLICE     = 10
Game.FINAL_TIME   = 90
Game.FINAL_TARGET = 5
Game.MAX_CLUES    = 3
Game.SAFETY_LEVEL = 2
Game.JOKER_WORDS  = 5
Game.JOKER_TIME   = 3

-- The final's ladder: words available per level, prize when cleared.
Game.LEVELS = {
    { words = 10, prize = 1000 },
    { words = 9,  prize = 2500 },
    { words = 8,  prize = 5000 },
    { words = 7,  prize = 10000 },
    { words = 6,  prize = 20000 },
}

-- Difficulties drawn in each qualification round, and for the tie-break.
-- The final's level n draws difficulty n.
Game.QUAL_DIFFICULTY = { { 1, 2 }, { 1, 2 }, { 2, 3 }, { 2, 3 } }
Game.TB_DIFFICULTY   = { 2, 3 }

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

local function shuffle(t, rng)
    for i = #t, 2, -1 do
        local j = rng(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- "1 000 €" / "€1,000", "1 000 pts" / "1,000 pts".
function Game.formatPrize(n, unit, lang)
    local s = tostring(math.floor(n))
    local sep = lang == "fr" and "\u{00A0}" or ","
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    if unit == "euros" then
        return lang == "fr" and (out .. "\u{00A0}€") or ("€" .. out)
    end
    return out .. (lang == "fr" and "\u{00A0}pts" or " pts")
end

-- opts: players (4 names), swap (bool), bank ({ [difficulty] = { words } }),
-- recent (set of words to avoid), rng (function(n) -> 1..n).
function Game.new(opts)
    local self = setmetatable({}, Game)
    self.rng = opts.rng or math.random
    self.bank = opts.bank or {}
    self.recent = opts.recent or {}
    self.swap = opts.swap and true or false
    self.players = {}
    for i = 1, 4 do self.players[i] = (opts.players or {})[i] or ("Player " .. i) end
    self:newGame()
    return self
end

function Game:newGame()
    self.phase = "setup"
    self.round, self.slot = 1, 1
    self.score = { 0, 0, 0, 0 }          -- per player
    self.rounds = {}                      -- rounds[r][slot] = points
    self.used, self.used_list = {}, {}
    self.queue, self.turn_points, self.history = nil, 0, nil
    self.last_turn = nil
    self.qual = nil
    self.tb = nil
    self.final = nil
end

-- ---------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------

-- n distinct words of the given difficulties, never twice in a game; words
-- in self.recent (seen in recent games) only once the fresh ones run out.
function Game:draw(difficulties, n)
    local fresh, stale = {}, {}
    for _, d in ipairs(difficulties) do
        for _, w in ipairs(self.bank[d] or {}) do
            if not self.used[w] then
                if self.recent[w] then stale[#stale + 1] = w else fresh[#fresh + 1] = w end
            end
        end
    end
    shuffle(fresh, self.rng)
    shuffle(stale, self.rng)
    local out = {}
    for _, list in ipairs({ fresh, stale }) do
        for _, w in ipairs(list) do
            if #out >= n then break end
            out[#out + 1] = w
        end
    end
    for _, w in ipairs(out) do
        self.used[w] = true
        self.used_list[#self.used_list + 1] = w
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Qualification
-- ---------------------------------------------------------------------------

function Game:teamOf(p)
    return p <= 2 and 1 or 2
end

function Game:teamPlayers(t)
    return t == 1 and 1 or 3, t == 1 and 2 or 4
end

-- Clue-giver and guesser of a qualification turn.
function Game:pairing(round, slot)
    round, slot = round or self.round, slot or self.slot
    local a, b
    if self.swap and round >= 3 then
        if slot == 1 then a, b = 1, 4 else a, b = 3, 2 end
    else
        a, b = self:teamPlayers(slot)
    end
    if round % 2 == 0 then a, b = b, a end
    return a, b
end

function Game:teamScore(t)
    local a = self:teamPlayers(t)
    return self.score[a]
end

function Game:startGame()
    local players, swap = self.players, self.swap
    self:newGame()
    self.players, self.swap = players, swap
    self.phase = "handover"
end

function Game:startTurn()
    self.queue = self:draw(Game.QUAL_DIFFICULTY[self.round], Game.QUAL_WORDS)
    self.turn_points = 0
    self.turn_results = {}
    self.history = {}
    self.phase = "turn"
end

function Game:currentWord()
    if self.phase == "turn" then return self.queue and self.queue[1] end
    if self.phase == "tb_turn" then return self.tb and self.tb.word end
    if self.phase == "final_turn" then
        local f = self.final
        return f and f.words and f.words[f.pos]
    end
end

function Game:_pushHistory()
    local h = { queue = copy(self.queue), points = self.turn_points,
                results = copy(self.turn_results) }
    self.history[#self.history + 1] = h
end

-- Each returns true when the turn is over (no word left).
function Game:found()
    if self.phase ~= "turn" or not self.queue[1] then return false end
    self:_pushHistory()
    local w = table.remove(self.queue, 1)
    self.turn_points = self.turn_points + 1
    self.turn_results[#self.turn_results + 1] = { word = w, found = true }
    return self:_checkTurnEnd()
end

function Game:pass()
    if self.phase ~= "turn" or #self.queue < 2 then return false end
    self:_pushHistory()
    local w = table.remove(self.queue, 1)
    self.queue[#self.queue + 1] = w
    return false
end

function Game:canPass()
    return self.phase == "turn" and self.queue ~= nil and #self.queue >= 2
end

function Game:forbidden()
    if self.phase ~= "turn" or not self.queue[1] then return false end
    self:_pushHistory()
    local w = table.remove(self.queue, 1)
    self.turn_results[#self.turn_results + 1] = { word = w, found = false }
    return self:_checkTurnEnd()
end

function Game:canUndo()
    if self.phase == "turn" then return self.history and #self.history > 0 end
    if self.phase == "final_turn" then return self.final and #self.final.history > 0 end
    return false
end

function Game:undo()
    if self.phase == "final_turn" then return self:finalUndo() end
    if not self:canUndo() then return false end
    local h = table.remove(self.history)
    self.queue, self.turn_points, self.turn_results = h.queue, h.points, h.results
    return true
end

function Game:_checkTurnEnd()
    if #self.queue == 0 then
        self:endTurn()
        return true
    end
    return false
end

-- Time up or no word left: score the turn and move to the next one.
function Game:endTurn()
    if self.phase ~= "turn" then return end
    local giver, guesser = self:pairing()
    self.score[giver] = self.score[giver] + self.turn_points
    self.score[guesser] = self.score[guesser] + self.turn_points
    self.rounds[self.round] = self.rounds[self.round] or {}
    self.rounds[self.round][self.slot] = self.turn_points
    self.last_turn = { giver = giver, guesser = guesser, points = self.turn_points }
    self.queue, self.history = nil, nil
    if self.slot == 1 then
        self.slot = 2
        self.phase = "handover"
    elseif self.round < Game.QUAL_ROUNDS then
        self.round, self.slot = self.round + 1, 1
        self.phase = "handover"
    else
        self:_qualify()
    end
end

-- Players by score, best first (ties keep the player order).
function Game:ranking()
    local order = { 1, 2, 3, 4 }
    table.sort(order, function(a, b)
        if self.score[a] ~= self.score[b] then return self.score[a] > self.score[b] end
        return a < b
    end)
    return order
end

-- Decides who plays the final, or sets up the tie-break.
function Game:_qualify()
    self.phase = "qual_over"
    local q = {}
    self.qual = q
    if not self.swap then
        local a, b = self:teamScore(1), self:teamScore(2)
        if a ~= b then
            local t = a > b and 1 or 2
            q.finalists = { self:teamPlayers(t) }
            q.team = t
        else
            q.tiebreak = { { giver = 1, guesser = 2, team = 1 }, { giver = 3, guesser = 4, team = 2 } }
        end
        return
    end
    local r = self:ranking()
    local s = function(i) return self.score[r[i]] end
    if s(2) > s(3) then
        q.finalists = { r[1], r[2] }
    elseif s(1) > s(2) and s(3) > s(4) then
        -- One leader, two tied for second: they give clues in turn to the leader.
        q.tiebreak = { { giver = r[2], guesser = r[1] }, { giver = r[3], guesser = r[1] } }
    else
        -- Any other tie: the tied players are ordered by lot.
        local best = {}
        for i = 1, 4 do
            if s(i) > s(2) then best[#best + 1] = r[i] end
        end
        local tied = {}
        for i = 1, 4 do
            if s(i) == s(2) then tied[#tied + 1] = r[i] end
        end
        shuffle(tied, self.rng)
        for _, p in ipairs(tied) do
            if #best >= 2 then break end
            best[#best + 1] = p
        end
        q.finalists = best
        q.by_lot = true
    end
end

-- ---------------------------------------------------------------------------
-- Tie-break
-- ---------------------------------------------------------------------------

function Game:startTiebreak()
    if not (self.qual and self.qual.tiebreak) then return end
    self.phase = "tb_handover"
end

function Game:tbStart()
    self.tb = { active = 1, word = self:draw(Game.TB_DIFFICULTY, 1)[1] }
    self.phase = "tb_turn"
end

function Game:tbSide(i)
    return self.qual.tiebreak[i or (self.tb and self.tb.active) or 1]
end

-- The 10 s slice is over: the other side's clue-giver speaks.
function Game:tbSwitch()
    if self.phase ~= "tb_turn" then return end
    self.tb.active = 3 - self.tb.active
end

function Game:_tbWin(side, reason)
    local q = self.qual
    local s = q.tiebreak[side]
    q.tb_result = { side = side, word = self.tb.word, reason = reason }
    if s.team then
        q.finalists = { self:teamPlayers(s.team) }
        q.team = s.team
    else
        q.finalists = { s.guesser, s.giver }
    end
    self.tb = nil
    self.phase = "qual_over"
end

function Game:tbFound()
    if self.phase ~= "tb_turn" then return end
    self:_tbWin(self.tb.active, "found")
end

-- A forbidden clue eliminates the side that gave it.
function Game:tbForbidden()
    if self.phase ~= "tb_turn" then return end
    self:_tbWin(3 - self.tb.active, "forbidden")
end

-- Nobody finds it: another word, the alternation goes on.
function Game:tbNewWord()
    if self.phase ~= "tb_turn" then return end
    self.tb.word = self:draw(Game.TB_DIFFICULTY, 1)[1]
end

-- ---------------------------------------------------------------------------
-- Final
-- ---------------------------------------------------------------------------

function Game:startFinal()
    local q = self.qual
    if not (q and q.finalists) then return end
    local a, b = q.finalists[1], q.finalists[2]
    -- The usual guesser of round 1 guesses in the final too; roles can be swapped.
    self.final = { pair = { a, b }, giver = a, guesser = b, level = 1, cleared = 0,
                   joker = "locked", history = {} }
    self.phase = "final_handover"
end

-- "Final again": same pair, from level 1.
function Game:restartFinal()
    if not self.final then return end
    local f = self.final
    self.final = { pair = f.pair, giver = f.giver, guesser = f.guesser, level = 1,
                   cleared = 0, joker = "locked", history = {} }
    self.phase = "final_handover"
end

function Game:swapRoles()
    local f = self.final
    if f then f.giver, f.guesser = f.guesser, f.giver end
end

function Game:_drawLevel()
    local f = self.final
    if not f.words then
        f.words = self:draw({ f.level }, Game.LEVELS[f.level].words)
    end
end

function Game:finalStart()
    if self.phase ~= "final_handover" then return end
    local f = self.final
    self:_drawLevel()
    f.pos, f.found, f.clues, f.results, f.history = 1, 0, 0, {}, {}
    self.phase = "final_turn"
end

function Game:finalWordsLeft()
    local f = self.final
    return #f.words - f.pos + 1
end

function Game:_finalPush()
    local f = self.final
    f.history[#f.history + 1] = { pos = f.pos, found = f.found, clues = f.clues,
                                  results = copy(f.results) }
end

function Game:finalUndo()
    local f = self.final
    if self.phase ~= "final_turn" or #f.history == 0 then return false end
    local h = table.remove(f.history)
    f.pos, f.found, f.clues, f.results = h.pos, h.found, h.clues, h.results
    return true
end

-- One clue spoken for the current word (3 at most).
function Game:finalClue()
    local f = self.final
    if self.phase ~= "final_turn" or f.clues >= Game.MAX_CLUES then return false end
    self:_finalPush()
    f.clues = f.clues + 1
    return true
end

function Game:canClue()
    return self.phase == "final_turn" and self.final.clues < Game.MAX_CLUES
end

function Game:finalFound()
    if self.phase ~= "final_turn" then return end
    self:_finalPush()
    local f = self.final
    f.results[#f.results + 1] = { word = f.words[f.pos], found = true }
    f.found = f.found + 1
    self:_finalNext()
end

-- Passed, forbidden clue, or not found after 3 clues: the word is lost.
function Game:finalLose(reason)
    if self.phase ~= "final_turn" then return end
    self:_finalPush()
    local f = self.final
    f.results[#f.results + 1] = { word = f.words[f.pos], found = false, reason = reason }
    self:_finalNext()
end

function Game:_finalNext()
    local f = self.final
    f.pos, f.clues = f.pos + 1, 0
    if f.found >= Game.FINAL_TARGET then
        self:_levelCleared()
    elseif f.found + self:finalWordsLeft() < Game.FINAL_TARGET then
        self:_levelFailed("words")
    end
end

function Game:finalTimeUp()
    if self.phase ~= "final_turn" then return end
    self:_levelFailed("time")
end

-- Prize kept when a level fails: the safety level's, once it was reached.
function Game:safetyPrize()
    local f = self.final
    if f and f.cleared >= Game.SAFETY_LEVEL then return Game.LEVELS[Game.SAFETY_LEVEL].prize end
    return 0
end

function Game:_levelFailed(why)
    local f = self.final
    f.history = {}
    f.outcome = { kind = "failed", why = why, level = f.level, prize = self:safetyPrize(),
                  found = f.found }
    self.phase = "game_over"
end

function Game:_levelCleared()
    local f = self.final
    f.history = {}
    f.cleared = f.level
    if f.level == Game.SAFETY_LEVEL and f.joker == "locked" then f.joker = "available" end
    if f.level >= #Game.LEVELS then
        f.outcome = { kind = "won", level = f.level, prize = Game.LEVELS[f.level].prize }
        self.phase = "game_over"
        return
    end
    -- The next level's words are drawn now: the joker previews them.
    f.level = f.level + 1
    f.words = nil
    self:_drawLevel()
    f.preview_seen = false
    self.phase = "decision"
end

function Game:stopAndKeep()
    if self.phase ~= "decision" then return end
    local f = self.final
    f.outcome = { kind = "stopped", level = f.cleared, prize = Game.LEVELS[f.cleared].prize }
    self.phase = "game_over"
end

function Game:continueFinal()
    if self.phase ~= "decision" then return end
    self.phase = "final_handover"
end

function Game:canUseJoker()
    local f = self.final
    return self.phase == "decision" and f.joker == "available"
end

-- The joker shows the next level's first words; the screen times them.
function Game:useJoker()
    if not self:canUseJoker() then return nil end
    local f = self.final
    f.joker = "used"
    f.preview_seen = true
    local out = {}
    for i = 1, math.min(Game.JOKER_WORDS, #f.words) do out[i] = f.words[i] end
    return out
end

function Game:isGameOver()
    return self.phase == "game_over"
end

-- ---------------------------------------------------------------------------
-- Save / restore. A turn in progress is never restored on a visible word: it
-- goes back to its hand-over screen and is replayed with new words.
-- ---------------------------------------------------------------------------

function Game:serialize()
    local phase = self.phase
    local final = self.final and copy(self.final) or nil
    if phase == "turn" then
        phase = "handover"
    elseif phase == "tb_turn" then
        phase = "tb_handover"
    elseif phase == "final_turn" then
        phase = "final_handover"
        final.words, final.history = nil, {}
    end
    if final then final.history = {} end
    return {
        version = 1, phase = phase, round = self.round, slot = self.slot,
        swap = self.swap, players = copy(self.players), score = copy(self.score),
        rounds = copy(self.rounds), used = copy(self.used_list),
        last_turn = copy(self.last_turn), qual = self.qual and copy(self.qual) or nil,
        final = final,
    }
end

local PHASES = { setup = true, handover = true, qual_over = true, tb_handover = true,
                 final_handover = true, decision = true, game_over = true }

function Game:load(state)
    if type(state) ~= "table" or state.version ~= 1 or not PHASES[state.phase]
        or type(state.players) ~= "table" or type(state.score) ~= "table" then
        return false
    end
    self:newGame()
    self.phase = state.phase
    self.round = tonumber(state.round) or 1
    self.slot = tonumber(state.slot) or 1
    self.swap = state.swap and true or false
    for i = 1, 4 do
        self.players[i] = tostring(state.players[i] or self.players[i])
        self.score[i] = tonumber(state.score[i]) or 0
    end
    self.rounds = state.rounds or {}
    for _, w in ipairs(state.used or {}) do
        self.used[w] = true
        self.used_list[#self.used_list + 1] = w
    end
    self.last_turn = state.last_turn
    self.qual = state.qual
    self.final = state.final
    if self.final then self.final.history = {} end
    local needs_final = { final_handover = true, decision = true, game_over = true }
    if needs_final[self.phase] and not self.final then self.phase = "setup" end
    if self.phase == "decision" and not (self.final.words and #self.final.words > 0) then
        self.phase = "final_handover"
    end
    if (self.phase == "qual_over" or self.phase == "tb_handover") and not self.qual then
        self.phase = "setup"
    end
    return true
end

return Game
