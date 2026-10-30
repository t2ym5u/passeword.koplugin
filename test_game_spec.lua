local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Game = dofile(DIR .. "game.lua")

local function lcg(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return (s % n) + 1
    end
end

-- A small bank: 60 words per difficulty, named after it ("d3w12").
local function fakeBank()
    local bank = {}
    for d = 1, 5 do
        bank[d] = {}
        for i = 1, 60 do bank[d][i] = "d" .. d .. "w" .. i end
    end
    return bank
end

local function newGame(opts)
    opts = opts or {}
    return Game.new{ players = { "Alice", "Bob", "Carol", "Dave" }, swap = opts.swap,
                     bank = fakeBank(), rng = lcg(opts.seed or 1) }
end

local function difficulty(w) return tonumber(w:match("^d(%d)")) end

-- Plays one qualification turn finding `n` words, then lets the time run out.
local function playTurn(g, n)
    assert.are.equal("handover", g.phase)
    g:startTurn()
    for _ = 1, n do g:found() end
    if g.phase == "turn" then g:endTurn() end
end

local function playQualification(g, points)  -- points[round][slot]
    g:startGame()
    for r = 1, Game.QUAL_ROUNDS do
        for slot = 1, 2 do playTurn(g, points[r][slot]) end
    end
end

describe("passeword qualification", function()
    it("swaps clue-giver and guesser every round", function()
        local g = newGame()
        local a, b = g:pairing(1, 1); assert.are.same({ 1, 2 }, { a, b })
        a, b = g:pairing(2, 1); assert.are.same({ 2, 1 }, { a, b })
        a, b = g:pairing(3, 2); assert.are.same({ 3, 4 }, { a, b })
        a, b = g:pairing(4, 2); assert.are.same({ 4, 3 }, { a, b })
    end)

    it("mixes the partners in rounds 3-4 when swap is on", function()
        local g = newGame{ swap = true }
        local a, b = g:pairing(3, 1); assert.are.same({ 1, 4 }, { a, b })
        a, b = g:pairing(4, 2); assert.are.same({ 2, 3 }, { a, b })
        a, b = g:pairing(1, 2); assert.are.same({ 3, 4 }, { a, b })
    end)

    it("draws 5 distinct words per turn from the round's difficulties", function()
        local g = newGame()
        g:startGame()
        g:startTurn()
        assert.are.equal(5, #g.queue)
        for _, w in ipairs(g.queue) do assert.is_true(difficulty(w) <= 2) end
        g.round = 3
        g:startTurn()
        for _, w in ipairs(g.queue) do assert.is_true(difficulty(w) >= 2 and difficulty(w) <= 3) end
    end)

    it("handles found, pass (to the end), forbidden (lost) and undo", function()
        local g = newGame()
        g:startGame()
        g:startTurn()
        local first, second = g.queue[1], g.queue[2]
        g:pass()
        assert.are.equal(second, g.queue[1])
        assert.are.equal(first, g.queue[5])
        g:found()
        assert.are.equal(1, g.turn_points)
        g:forbidden()
        assert.are.equal(3, #g.queue)
        assert.are.equal(1, g.turn_points)
        g:undo()
        assert.are.equal(4, #g.queue)
        g:undo(); g:undo()
        assert.are.equal(first, g.queue[1])
        assert.are.equal(0, g.turn_points)
        assert.is_false(g:canUndo())
    end)

    it("a word passed alone cannot be passed again; the turn ends when the list is empty", function()
        local g = newGame()
        g:startGame()
        g:startTurn()
        for _ = 1, 4 do g:found() end
        assert.is_false(g:canPass())
        assert.is_true(g:found())
        assert.are.equal("handover", g.phase)
        assert.are.equal(2, g.slot)
        assert.are.equal(5, g:teamScore(1))
    end)

    it("sends the best team to the final", function()
        local g = newGame()
        playQualification(g, { { 3, 2 }, { 4, 1 }, { 2, 2 }, { 0, 5 } })
        assert.are.equal("qual_over", g.phase)
        assert.are.equal(9, g:teamScore(1))
        assert.are.equal(10, g:teamScore(2))
        assert.are.same({ 3, 4 }, g.qual.finalists)
        assert.are.same({ 3, 4, 2, 5 }, { g.rounds[1][1], g.rounds[2][1], g.rounds[3][1], g.rounds[4][2] })
    end)

    it("never deals a word twice in a game", function()
        local g = newGame()
        playQualification(g, { { 1, 1 }, { 1, 1 }, { 1, 1 }, { 1, 1 } })
        local seen = {}
        for _, w in ipairs(g.used_list) do
            assert.is_nil(seen[w]); seen[w] = true
        end
        assert.are.equal(40, #g.used_list)
    end)
end)

describe("passeword tie-break", function()
    it("team mode: first to find wins, a forbidden clue eliminates", function()
        local g = newGame()
        playQualification(g, { { 1, 1 }, { 1, 1 }, { 1, 1 }, { 1, 1 } })
        assert.is_nil(g.qual.finalists)
        g:startTiebreak()
        assert.are.equal("tb_handover", g.phase)
        g:tbStart()
        assert.are.equal(1, g.tb.active)
        assert.is_truthy(g:currentWord())
        g:tbSwitch()
        assert.are.equal(3, g:tbSide().giver)
        g:tbFound()
        assert.are.same({ 3, 4 }, g.qual.finalists)
        assert.are.equal("qual_over", g.phase)

        g = newGame()
        playQualification(g, { { 1, 1 }, { 1, 1 }, { 1, 1 }, { 1, 1 } })
        g:startTiebreak(); g:tbStart()
        g:tbForbidden()       -- team A's clue-giver speaks first
        assert.are.same({ 3, 4 }, g.qual.finalists)
        assert.are.equal("forbidden", g.qual.tb_result.reason)
    end)

    it("swap mode: individual ranking; two tied for 2nd duel for the leader", function()
        local g = newGame{ swap = true }
        -- r1: 1-2 get 3, 3-4 get 1; r2 same; r3: 1-4 get 0, 3-2 get 2; r4: 4-1 get 0, 2-3 get 0
        playQualification(g, { { 3, 1 }, { 3, 1 }, { 0, 2 }, { 0, 0 } })
        -- Alice 6, Bob 8, Carol 4, Dave 2 -> Bob and Alice
        assert.are.same({ 8, 6, 4, 2 }, { g.score[2], g.score[1], g.score[3], g.score[4] })
        assert.are.same({ 2, 1 }, g.qual.finalists)

        g = newGame{ swap = true }
        -- Alice 4, Bob 6, Carol 4, Dave 2: Alice and Carol tied behind Bob.
        playQualification(g, { { 2, 1 }, { 2, 1 }, { 0, 2 }, { 0, 0 } })
        assert.are.same({ 4, 6, 4, 2 }, g.score)
        local tb = g.qual.tiebreak
        assert.are.equal(2, tb[1].guesser)
        assert.are.equal(2, tb[2].guesser)
        g:startTiebreak(); g:tbStart(); g:tbSwitch(); g:tbFound()
        assert.are.same({ 2, tb[2].giver }, g.qual.finalists)
    end)

    it("swap mode: other ties are drawn by lot", function()
        local g = newGame{ swap = true }
        playQualification(g, { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } })
        assert.is_true(g.qual.by_lot)
        assert.are.equal(2, #g.qual.finalists)
        assert.are_not.equal(g.qual.finalists[1], g.qual.finalists[2])
    end)
end)

describe("passeword final", function()
    local function toFinal()
        local g = newGame()
        playQualification(g, { { 5, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } })
        g:startFinal()
        return g
    end

    local function clearLevel(g)
        g:finalStart()
        for _ = 1, Game.FINAL_TARGET do g:finalFound() end
    end

    it("has a shrinking ladder of words and growing prizes", function()
        for i = 2, #Game.LEVELS do
            assert.is_true(Game.LEVELS[i].words < Game.LEVELS[i - 1].words)
            assert.is_true(Game.LEVELS[i].prize > Game.LEVELS[i - 1].prize)
            assert.is_true(Game.LEVELS[i].words >= Game.FINAL_TARGET)
        end
        assert.are.equal(2500, Game.LEVELS[Game.SAFETY_LEVEL].prize)
    end)

    it("draws each level's words at its difficulty", function()
        local g = toFinal()
        assert.are.equal("final_handover", g.phase)
        g:finalStart()
        assert.are.equal(10, #g.final.words)
        for _, w in ipairs(g.final.words) do assert.are.equal(1, difficulty(w)) end
    end)

    it("allows 3 clues per word, then the word must be given up", function()
        local g = toFinal()
        g:finalStart()
        for _ = 1, 3 do assert.is_true(g:finalClue()) end
        assert.is_false(g:canClue())
        assert.is_false(g:finalClue())
        g:finalLose("clues")
        assert.are.equal(0, g.final.clues)
        assert.are.equal(9, g:finalWordsLeft())
        g:finalUndo()
        assert.are.equal(3, g.final.clues)
        assert.are.equal(10, g:finalWordsLeft())
    end)

    it("fails a level as soon as 5 words can no longer be found", function()
        local g = toFinal()
        g:finalStart()
        for _ = 1, 5 do g:finalLose("pass") end
        assert.are.equal("final_turn", g.phase)     -- 5 left, 5 needed
        g:finalLose("forbidden")
        assert.are.equal("game_over", g.phase)
        assert.are.equal(0, g.final.outcome.prize)
    end)

    it("stops and keeps, or fails back to the safety level", function()
        local g = toFinal()
        clearLevel(g)
        assert.are.equal("decision", g.phase)
        assert.are.equal("locked", g.final.joker)
        g:stopAndKeep()
        assert.are.equal(1000, g.final.outcome.prize)

        g = toFinal()
        clearLevel(g); g:continueFinal()
        clearLevel(g)
        assert.are.equal("available", g.final.joker)
        g:continueFinal()
        g:finalStart()
        assert.are.equal(8, #g.final.words)
        g:finalTimeUp()
        assert.are.equal("game_over", g.phase)
        assert.are.equal("time", g.final.outcome.why)
        assert.are.equal(2500, g.final.outcome.prize)
    end)

    it("joker previews the next level's first 5 words, once", function()
        local g = toFinal()
        clearLevel(g); g:continueFinal(); clearLevel(g)
        assert.is_true(g:canUseJoker())
        local preview = g:useJoker()
        assert.are.equal(5, #preview)
        for i = 1, 5 do assert.are.equal(g.final.words[i], preview[i]) end
        for _, w in ipairs(preview) do assert.are.equal(3, difficulty(w)) end
        assert.is_false(g:canUseJoker())
        assert.is_nil(g:useJoker())
        g:continueFinal(); g:finalStart()
        assert.are.equal(preview[1], g:currentWord())
    end)

    it("wins the jackpot after level 5", function()
        local g = toFinal()
        for l = 1, 5 do
            clearLevel(g)
            if l < 5 then g:continueFinal() end
        end
        assert.are.equal("game_over", g.phase)
        assert.are.equal("won", g.final.outcome.kind)
        assert.are.equal(20000, g.final.outcome.prize)
        g:restartFinal()
        assert.are.equal("final_handover", g.phase)
        assert.are.equal(1, g.final.level)
    end)

    it("swaps the roles", function()
        local g = toFinal()
        local a, b = g.final.giver, g.final.guesser
        g:swapRoles()
        assert.are.same({ b, a }, { g.final.giver, g.final.guesser })
    end)
end)

describe("passeword save/restore", function()
    it("never restores on a visible word", function()
        local g = newGame()
        g:startGame(); g:startTurn(); g:found()
        local s = g:serialize()
        assert.are.equal("handover", s.phase)
        local h = newGame()
        assert.is_true(h:load(s))
        assert.are.equal("handover", h.phase)
        assert.are.equal(0, h:teamScore(1))

        g = newGame()
        playQualification(g, { { 5, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } })
        g:startFinal(); g:finalStart(); g:finalFound()
        s = g:serialize()
        assert.are.equal("final_handover", s.phase)
        assert.is_nil(s.final.words)
        h = newGame()
        assert.is_true(h:load(s))
        h:finalStart()
        assert.are.equal(10, #h.final.words)
        assert.are.equal(0, h.final.found)
        -- Words already dealt in this game are not dealt again.
        for _, w in ipairs(h.final.words) do
            local n = 0
            for _, u in ipairs(h.used_list) do if u == w then n = n + 1 end end
            assert.are.equal(1, n)
        end
    end)

    it("restores a decision and a finished game", function()
        local g = newGame()
        playQualification(g, { { 5, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } })
        g:startFinal(); g:finalStart()
        for _ = 1, 5 do g:finalFound() end
        local h = newGame(); h:load(g:serialize())
        assert.are.equal("decision", h.phase)
        assert.are.same(g.final.words, h.final.words)
        h:stopAndKeep()
        local k = newGame(); k:load(h:serialize())
        assert.is_true(k:isGameOver())
        assert.are.equal(1000, k.final.outcome.prize)
    end)

    it("rejects junk", function()
        local g = newGame()
        assert.is_false(g:load(nil))
        assert.is_false(g:load({ version = 1, phase = "turn", players = {}, score = {} }))
    end)
end)

describe("passeword prizes", function()
    it("formats euros and points per language", function()
        assert.are.equal("€20,000", Game.formatPrize(20000, "euros", "en"))
        assert.are.equal("2\u{00A0}500\u{00A0}€", Game.formatPrize(2500, "euros", "fr"))
        assert.are.equal("1,000 pts", Game.formatPrize(1000, "points", "en"))
        assert.are.equal("100\u{00A0}000\u{00A0}pts", Game.formatPrize(100000, "points", "fr"))
        assert.are.equal("€500", Game.formatPrize(500, "euros", "en"))
    end)
end)

-- ---------------------------------------------------------------------------
-- Word banks
-- ---------------------------------------------------------------------------

local MIN_PER_LEVEL = { 400, 350, 300, 250, 200 }

-- Never in the banks (lowercase, checked as whole entries and as words).
local EXCLUDED = {
    "hitler", "staline", "stalin", "pol pot", "ben laden", "bin laden", "mussolini", "franco",
    "mao", "lénine", "lenin", "robespierre", "himmler", "goebbels", "idi amin", "ceausescu",
    "jack l'éventreur", "jack the ripper", "landru", "nazi", "terroriste", "terrorist",
    -- brands
    "nutella", "coca-cola", "coca", "lego", "iphone", "google", "kleenex", "frigidaire",
    "bic", "velcro", "frisbee", "hoover", "monopoly", "playmobil", "nintendo", "mcdonald's",
    "facebook", "netflix", "jacuzzi", "post-it", "scotch", "tupperware", "sopalin", "nike",
    "adidas", "rolex", "ikea", "disney", "barbie", "chupa chups", "caddie", "karcher",
}

local function lower(s)
    s = s:lower()
    local map = { ["É"] = "é", ["È"] = "è", ["Ê"] = "ê", ["À"] = "à", ["Â"] = "â", ["Î"] = "î",
                  ["Ô"] = "ô", ["Û"] = "û", ["Ç"] = "ç", ["Œ"] = "œ" }
    for k, v in pairs(map) do s = s:gsub(k, v) end
    return s
end

for _, lang in ipairs({ "fr", "en" }) do
    describe("passeword " .. lang .. " words", function()
        local bank = dofile(DIR .. "words/" .. lang .. ".lua")

        it("has enough words per level and 1500+ in all", function()
            local total = 0
            for l = 1, 5 do
                assert.is_true(#bank[l] >= MIN_PER_LEVEL[l],
                    lang .. " level " .. l .. ": " .. #bank[l])
                total = total + #bank[l]
            end
            assert.is_true(total >= 1500, lang .. " total " .. total)
            print(string.format("%s words: %d %d %d %d %d = %d", lang,
                #bank[1], #bank[2], #bank[3], #bank[4], #bank[5], total))
        end)

        it("has no duplicates, empty or overlong entries", function()
            local seen = {}
            for l = 1, 5 do
                for _, w in ipairs(bank[l]) do
                    assert.is_true(type(w) == "string" and w:match("%S") ~= nil)
                    assert.are.equal(w, (w:gsub("^%s+", ""):gsub("%s+$", "")))
                    local k = lower(w)
                    assert.is_nil(seen[k], lang .. " duplicate: " .. w .. " (" .. tostring(seen[k]) .. "/" .. l .. ")")
                    seen[k] = l
                    local n = 0
                    for _ in w:gmatch("%S+") do n = n + 1 end
                    assert.is_true(n <= 4, lang .. " too long: " .. w)
                end
            end
        end)

        it("has no proper nouns at level 1 and some at levels 2-5", function()
            local caps = {}
            for l = 1, 5 do
                caps[l] = 0
                for _, w in ipairs(bank[l]) do
                    if w:match("^%u") or w:match("^[\195][\128-\159]") then caps[l] = caps[l] + 1 end
                end
            end
            assert.are.equal(0, caps[1])
            for l = 2, 5 do assert.is_true(caps[l] >= 10, lang .. " level " .. l .. ": " .. caps[l]) end
        end)

        it("contains no excluded name or brand", function()
            for l = 1, 5 do
                for _, w in ipairs(bank[l]) do
                    local k = " " .. lower(w):gsub("[%-']", " ") .. " "
                    for _, bad in ipairs(EXCLUDED) do
                        local b = bad:gsub("[%-']", " ")
                        assert.is_nil(k:find(" " .. b .. " ", 1, true), lang .. ": " .. w)
                    end
                end
            end
        end)
    end)
end
