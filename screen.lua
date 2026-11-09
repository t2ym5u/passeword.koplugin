local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local SeenHistory = require("seen_history")
local Game       = lrequire("game")
local W          = lrequire("widgets")

local DeviceScreen = Device.screen

-- Words remembered across games, per language (the whole bank, ~1700).
local SEEN_MAX = 2000

local GAME_RULES_EN = [[
Pass the Word — Rules

Inspired by the classic TV word-guessing game. Four players in two teams of two: in each team one player gives clues, the other guesses. The clue-giver holds the reader and sees the secret word; the guesser must not see the screen.

QUALIFICATION — 4 rounds. In each round every team plays 30 s with 5 words. Round 1: player 1 gives the clues to player 2; round 2: roles are reversed; rounds 3 and 4 are like rounds 1 and 2.
• Clues are ONE word at a time, as many as you like.
• Found: +1 point.
• Pass: the word goes to the end of the list and comes back if time remains.
• Forbidden!: the clue was not allowed, the word is lost.
The team with the most points plays the final.

TIE-BREAK — both teams get the same word. Both clue-givers see it, the guessers look away. The clue-givers take turns of 10 s (the reader shows whose turn it is). The first team to find the word goes to the final; a forbidden clue eliminates the team that gave it.

FINAL — a ladder of 5 levels: 1 000 · 2 500 · 5 000 · 10 000 · 20 000. On each level find 5 words in 1 min 30 out of a shrinking list (10, 9, 8, 7 then 6 words), harder and harder.
• At most 3 clues per word: tap "Clue" after each one. After the 3rd clue the word is lost if it isn't found.
• Pass or a forbidden clue: the word is lost for good.
• After a cleared level, stop and keep the prize, or continue.
• Level 2 is the safety level: 2 500 are guaranteed. A failed level ends the game with the safety amount (nothing before it).
• Joker: unlocked at the safety level, usable once. Before a later level it shows the level's first 5 words, 3 s each; then decide to play or to stop.

FORBIDDEN CLUES
• the word itself, or part of it;
• invented words;
• compound or hyphenated words;
• translations into another language;
• words of the same family, or starting with the same syllable;
• miming, gestures, pointing at things;
• brand names and acronyms;
• spelling the word or splitting it into pieces;
• two different clues in a row without waiting for an answer.

ALLOWED
• intonation, rhymes, repeating a clue, homophones.
• Plurals and feminine forms are accepted as answers.

Swap partners in rounds 3–4 (setting): the teams are mixed for rounds 3 and 4 (player 1 with player 4, player 3 with player 2) and the ranking becomes individual; the two best players play the final.
]]

local GAME_RULES_FR = [[
Passe-mot — Règles

Inspiré du jeu télévisé classique de mots à faire deviner. Quatre joueurs en deux équipes de deux : dans chaque équipe un joueur donne les indices, l'autre devine. Celui qui donne les indices tient la liseuse et voit le mot secret ; celui qui devine ne doit pas voir l'écran.

QUALIFICATION — 4 manches. À chaque manche, chaque équipe joue 30 s avec 5 mots. Manche 1 : le joueur 1 fait deviner le joueur 2 ; manche 2 : les rôles s'inversent ; les manches 3 et 4 reprennent les manches 1 et 2.
• Un seul mot par indice, autant d'indices qu'on veut.
• Trouvé : +1 point.
• Passer : le mot repart en fin de liste et revient s'il reste du temps.
• Interdit ! : l'indice n'était pas permis (le « bip »), le mot est perdu.
L'équipe qui a le plus de points joue la finale.

DÉPARTAGE — les deux équipes reçoivent le même mot. Les deux donneurs d'indices le voient, ceux qui devinent détournent les yeux. Les donneurs parlent à tour de rôle, 10 s chacun (la liseuse affiche à qui c'est le tour). La première équipe qui trouve va en finale ; un indice interdit élimine l'équipe qui l'a donné.

FINALE — une pyramide de 5 paliers : 1 000 · 2 500 · 5 000 · 10 000 · 20 000. À chaque palier, trouvez 5 mots en 1 min 30 dans une liste qui rétrécit (10, 9, 8, 7 puis 6 mots), de plus en plus difficiles.
• 3 indices au plus par mot : touchez « Indice » après chacun. Après le 3e indice, le mot est perdu s'il n'est pas trouvé.
• Passer ou un indice interdit : le mot est perdu pour de bon.
• Après un palier réussi, arrêtez et gardez le gain, ou continuez.
• Le palier 2 est le palier de sécurité : 2 500 sont assurés. Un palier raté termine la partie avec le gain de sécurité (rien avant lui).
• Joker : débloqué au palier de sécurité, une seule fois. Avant un palier suivant, il montre les 5 premiers mots, 3 s chacun ; ensuite on décide de jouer ou de s'arrêter.

INDICES INTERDITS
• le mot lui-même, ou une partie du mot ;
• les mots inventés ;
• les mots composés ou avec trait d'union ;
• les traductions dans une autre langue ;
• les mots de la même famille, ou commençant par la même syllabe ;
• mimer, faire des gestes, montrer du doigt ;
• les marques et les sigles ;
• épeler le mot ou le découper en morceaux ;
• deux indices différents d'affilée sans attendre de réponse.

PERMIS
• l'intonation, les rimes, répéter un indice, les homophones.
• Le pluriel et le féminin sont acceptés comme réponses.

Changer de partenaire aux manches 3–4 (réglage) : les équipes sont mélangées aux manches 3 et 4 (joueur 1 avec joueur 4, joueur 3 avec joueur 2) et le classement devient individuel ; les deux meilleurs joueurs jouent la finale.
]]

-- One file per language, loaded only when that language is played.
local function loadBank(lang)
    local chunk = loadfile(_dir .. "words/" .. lang .. ".lua")
    local ok, data = pcall(chunk or error)
    return ok and type(data) == "table" and data or {}
end

local function onOff(v)
    return v and _("On") or _("Off")
end

-- ---------------------------------------------------------------------------

local PassewordScreen = ScreenBase:extend{}

function PassewordScreen:init()
    local plugin = self.plugin
    self.lang = plugin:getLang({ "fr", "en" })
    self.unit = plugin:getSetting("unit", "euros")
    self:_migrateRecent()
    self.game = Game.new{
        players = self:_savedPlayers(),
        swap = plugin:getSetting("swap", false),
        bank = loadBank(self.lang),
        seen = self:_seen(self.lang),
    }
    self.game:load(plugin:loadState())
    ScreenBase.init(self)
end

function PassewordScreen:_savedPlayers()
    local saved = self.plugin:getSetting("players", {})
    local out = {}
    for i = 1, 4 do out[i] = saved[i] or T(_("Player %1"), i) end
    return out
end

function PassewordScreen:serializeState()
    return self.game:serialize()
end

function PassewordScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function PassewordScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function PassewordScreen:_name(p)
    return self.game.players[p] or "?"
end

function PassewordScreen:_teamName(t)
    local a, b = self.game:teamPlayers(t)
    return T(_("%1 & %2"), self:_name(a), self:_name(b))
end

function PassewordScreen:_prize(n)
    return Game.formatPrize(n, self.unit, _.lang())
end

-- ---------------------------------------------------------------------------
-- Timers: one tick per second, only the timer widget is refreshed.
-- ---------------------------------------------------------------------------

function PassewordScreen:_startCountdown(seconds)
    self.time_left = seconds
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function PassewordScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function PassewordScreen:_timerText()
    local t = self.time_left or 0
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function PassewordScreen:_refreshTimer()
    if not self.timer_widget then return end
    self.timer_widget:setText(self:_timerText())
    UIManager:setDirty(self, function()
        return "fast", self.timer_frame and self.timer_frame.dimen or self.dimen
    end)
end

local TIMED = { turn = true, tb_turn = true, final_turn = true }

function PassewordScreen:_onTick(gen)
    local phase = self.game.phase
    if gen ~= self._tick_gen or not TIMED[phase] then return end
    self.time_left = math.max(0, (self.time_left or 0) - 1)
    if self.time_left <= 0 then
        if phase == "turn" then
            self:onTimeUp()
            return
        elseif phase == "final_turn" then
            self:onFinalTimeUp()
            return
        end
        -- Tie-break: the other clue-giver's 10 s start.
        self.game:tbSwitch()
        self.time_left = Game.TB_SLICE
        self:_refreshBanner()
    end
    self:_refreshTimer()
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

-- The tie-break banner shows whose turn it is; swapping it is the visual "beep".
function PassewordScreen:_refreshBanner()
    if not self.banner_frame then return end
    local center = self.banner_frame[1]
    center[1] = W.fitLine(self:_tbBannerText(), self.banner_px, center.dimen.w - 2 * Size.padding.large,
                          true, require("ffi/blitbuffer").COLOR_WHITE)
    self:updateStatus()
    UIManager:setDirty(self, function()
        return "ui", self.banner_frame.dimen or self.dimen
    end)
end

function PassewordScreen:_tbBannerText()
    local s = self.game:tbSide()
    return T(_("%1 → %2"), self:_name(s.giver), self:_name(s.guesser))
end

-- ---------------------------------------------------------------------------
-- Actions: qualification
-- ---------------------------------------------------------------------------

-- The words dealt, remembered in the settings ("seen_words_<lang>") as they
-- are dealt: a word comes back only once its whole difficulty level has been
-- played, whatever the number of games in between.
function PassewordScreen:_seen(lang)
    return SeenHistory.open(self.plugin, "words_" .. lang, { max = SEEN_MAX })
end

-- Up to 1.0.x the last 400 words of finished games were kept under
-- "recent_words" (newest first, both languages mixed): move them into each
-- language's history once, then drop the old setting.
function PassewordScreen:_migrateRecent()
    local old = self.plugin:getSetting("recent_words", nil)
    if old == nil then return end
    if type(old) == "table" then
        Game.migrateRecent(old, { fr = loadBank("fr"), en = loadBank("en") },
            function(lang) return self:_seen(lang) end)
    end
    self.plugin:saveSetting("recent_words", nil)
end

function PassewordScreen:onStartGame()
    if not self.game.bank[1] then
        self:showMessage(_("No words for this language."))
        return
    end
    self.game.swap = self.plugin:getSetting("swap", false)
    self.game:startGame()
    self:_save()
    self:_redraw()
end

function PassewordScreen:onReady()
    self.game:startTurn()
    self:_save()
    self:_startCountdown(Game.QUAL_TIME)
    self:_redraw()
end

function PassewordScreen:_afterTurnAction(ended)
    if ended then self:_stopCountdown() end
    self:_save()
    self:_redraw()
end

function PassewordScreen:onFound()
    self:_afterTurnAction(self.game:found())
end

function PassewordScreen:onPass()
    self.game:pass()
    self:_redraw()
end

function PassewordScreen:onForbidden()
    self:_afterTurnAction(self.game:forbidden())
end

function PassewordScreen:onUndo()
    if self.game:undo() then self:_redraw() end
end

function PassewordScreen:onTimeUp()
    self:_stopCountdown()
    self.game:endTurn()
    self:_save()
    self:_redraw()
    self:showMessage(_("Time's up!"), 2)
end

function PassewordScreen:onQualNext()
    local q = self.game.qual
    if q.finalists then
        self.game:startFinal()
    else
        self.game:startTiebreak()
    end
    self:_save()
    self:_redraw()
end

-- Tie-break --------------------------------------------------------------

function PassewordScreen:onTbReady()
    self.game:tbStart()
    self:_save()
    self:_startCountdown(Game.TB_SLICE)
    self:_redraw()
end

function PassewordScreen:onTbFound()
    self:_stopCountdown()
    self.game:tbFound()
    self:_save()
    self:_redraw()
end

function PassewordScreen:onTbForbidden()
    self:_stopCountdown()
    self.game:tbForbidden()
    self:_save()
    self:_redraw()
end

-- Another word, and the same clue-giver gets a fresh 10 s.
function PassewordScreen:onTbNewWord()
    self.game:tbNewWord()
    self:_startCountdown(Game.TB_SLICE)
    self:_redraw()
end

-- Final -------------------------------------------------------------------

function PassewordScreen:onSwapRoles()
    self.game:swapRoles()
    self:_save()
    self:_redraw()
end

function PassewordScreen:onFinalReady()
    self.game:finalStart()
    self:_startCountdown(Game.FINAL_TIME)
    self:_redraw()
end

function PassewordScreen:_afterFinalAction()
    if self.game.phase ~= "final_turn" then
        self:_stopCountdown()
        self:_save()
    end
    self:_redraw()
end

function PassewordScreen:onClue()
    if self.game:finalClue() then self:_redraw() end
end

function PassewordScreen:onFinalFound()
    self.game:finalFound()
    self:_afterFinalAction()
end

function PassewordScreen:onFinalLose(reason)
    self.game:finalLose(reason)
    self:_afterFinalAction()
end

function PassewordScreen:onFinalUndo()
    if self.game:finalUndo() then self:_redraw() end
end

function PassewordScreen:onFinalTimeUp()
    self:_stopCountdown()
    self.game:finalTimeUp()
    self:_save()
    self:_redraw()
    self:showMessage(_("Time's up!"), 2)
end

function PassewordScreen:onStop()
    self.game:stopAndKeep()
    self:_save()
    self:_redraw()
end

function PassewordScreen:onContinue()
    self.game:continueFinal()
    self:_save()
    self:_redraw()
end

-- The joker: the next level's first words, 3 s each, then back to the choice.
function PassewordScreen:onJoker()
    local words = self.game:useJoker()
    if not words then return end
    self:_save()
    self.joker_words, self.joker_idx = words, 1
    self:_scheduleJoker()
    self:_redraw()
end

function PassewordScreen:_scheduleJoker()
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(Game.JOKER_TIME, function() self:_onJokerTick(gen) end)
end

function PassewordScreen:_onJokerTick(gen)
    if gen ~= self._tick_gen or not self.joker_words then return end
    self.joker_idx = self.joker_idx + 1
    if self.joker_idx > #self.joker_words then
        self.joker_words, self.joker_idx = nil, nil
    else
        self:_scheduleJoker()
    end
    self:_redraw()
end

function PassewordScreen:onNewGame()
    self:_stopCountdown()
    self.joker_words = nil
    self.game.swap = self.plugin:getSetting("swap", false)
    self.game:newGame()
    self:_save()
    self:_redraw()
end

function PassewordScreen:onFinalAgain()
    self.game:restartFinal()
    self:_save()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PassewordScreen:_picker(title, items, current, on_select)
    MenuHelper.openPickerMenu{
        title = title, items = items, current_id = current, parent = self,
        on_select = function(id)
            on_select(id)
            self:_redraw()
        end,
    }
end

function PassewordScreen:openLangMenu()
    self:_picker(_("Language"),
        { { id = "fr", text = "Français" }, { id = "en", text = "English" } }, self.lang,
        function(lang)
            self.lang = lang
            self.plugin:setLang(lang)
            self.game.bank = loadBank(lang)
            self.game.seen = self:_seen(lang)
        end)
end

function PassewordScreen:_unitLabel(u)
    return (u or self.unit) == "points" and _("Points") or _("Euros (for fun)")
end

function PassewordScreen:openUnitMenu()
    self:_picker(_("Prizes"),
        { { id = "euros", text = self:_unitLabel("euros") }, { id = "points", text = self:_unitLabel("points") } },
        self.unit, function(u)
            self.unit = u
            self.plugin:saveSetting("unit", u)
        end)
end

-- The partner swap changes how a game is played: it applies from the next game.
function PassewordScreen:toggleSwap()
    local v = not self.plugin:getSetting("swap", false)
    self.plugin:saveSetting("swap", v)
    if self.game.phase == "setup" then
        self.game.swap = v
    else
        self:showMessage(_("Applies from the next game."), 2)
    end
    self:_redraw()
end

function PassewordScreen:openPlayersDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Player names"),
        description = _("One name per line: team A's two players, then team B's."),
        input = table.concat(self.game.players, "\n"),
        allow_newline = true,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), callback = function()
                local text = dialog:getInputText() or ""
                UIManager:close(dialog)
                self:applyPlayerNames(text)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Renames in place (scores kept); missing lines keep the old name.
function PassewordScreen:applyPlayerNames(text)
    local names = {}
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then names[#names + 1] = line end
    end
    for i = 1, 4 do
        if names[i] then self.game.players[i] = names[i] end
    end
    self.plugin:saveSetting("players", { unpack(self.game.players) })
    self:_save()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

function PassewordScreen:isRoundOver()
    return self.game:isGameOver()
end

function PassewordScreen:getRoundOverButtons()
    local new = self:_bigButton(_("New game"), function() self:onNewGame() end)
    local again = self:_bigButton(_("Final again"), function() self:onFinalAgain() end)
    if self:isLandscape() then return { { new }, { again } } end
    return { new, again }
end

function PassewordScreen:_bigButton(text, callback, extra, scale)
    local b = { text = text, callback = callback,
                height = DeviceScreen:scaleBySize(60 * (scale or 1)),
                font_size = math.floor(22 * math.min(scale or 1, 1.3)) }
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

function PassewordScreen:_titleBar()
    return self:buildTitleBar(_("Pass the Word"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = T(_("Prizes: %1"), self:_unitLabel()), callback = function() self:openUnitMenu() end },
            { text = T(_("Swap partners in rounds 3–4: %1"), onOff(self.plugin:getSetting("swap", false))),
              callback = function() self:toggleSwap() end },
            { text = _("Player names"), callback = function() self:openPlayersDialog() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

function PassewordScreen:_controls(rows, extra_top)
    self.status_text:setMaxWidth(self:getControlsWidth())
    local g = VerticalGroup:new{ align = "center" }
    if extra_top then
        g[#g + 1] = extra_top
        g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end
    g[#g + 1] = self.status_text
    g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    g[#g + 1] = self:buildActionBar(rows)
    return g
end

function PassewordScreen:_place(title_bar, content, controls)
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
end

local function para(text, face, width)
    return TextBoxWidget:new{ text = text, face = face, width = width, alignment = "center" }
end

-- A vertical list of widgets separated by spans, each line shrunk to fit.
local function stack(items, vs)
    local g = VerticalGroup:new{ align = "center" }
    for i, w in ipairs(items) do
        if i > 1 then g[#g + 1] = VerticalSpan:new{ width = vs } end
        g[#g + 1] = w
    end
    return g
end

function PassewordScreen:_pyramid(width, max_h)
    local f = self.game.final
    local rows = {}
    for i, lv in ipairs(Game.LEVELS) do
        local state = "todo"
        if f then
            if i <= f.cleared then
                state = "cleared"
            elseif i == f.level and self.game.phase ~= "game_over" then
                state = "current"
            end
        end
        rows[i] = { label = T(_("Level %1"), i), prize = self:_prize(lv.prize), state = state }
    end
    return W.pyramid(rows, Game.SAFETY_LEVEL, width, max_h)
end

-- The big card holding the secret word, with an optional line under it.
function PassewordScreen:_wordCard(word, sub, bw, bh)
    local pad = Size.padding.large
    local vs = Size.span.vertical_large
    local inner_w = bw - 2 * (pad + Size.border.thick)
    local inner_h = bh - 2 * (pad + Size.border.thick)
    local g = VerticalGroup:new{ align = "center" }
    local sub_h = 0
    local sub_w
    if sub then
        sub_w = W.fitLine(sub, math.min(inner_h * 0.12, inner_w * 0.07), inner_w)
        sub_h = sub_w:getSize().h + vs * 2
    end
    g[#g + 1] = W.fitParagraph(word or "?", math.min(inner_w * 0.15, inner_h * 0.32),
        inner_w, inner_h - sub_h, true)
    if sub_w then
        g[#g + 1] = VerticalSpan:new{ width = vs * 2 }
        g[#g + 1] = sub_w
    end
    return FrameContainer:new{
        bordersize = Size.border.thick, padding = pad, margin = 0, radius = Size.radius.window,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, g },
    }
end

-- Timer frame: only this area is refreshed every second.
function PassewordScreen:_timer(px)
    self.timer_widget = TextWidget:new{ text = self:_timerText(), face = W.pxFace(px, true), bold = true }
    local probe = W.fitLine("0:00", px, 10000, true)
    local w = probe:getSize().w + Size.padding.large
    probe:free()
    self.timer_frame = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = self.timer_widget:getSize().h }, self.timer_widget },
    }
    return self.timer_frame
end

-- Turn screens: header (timer + info) above the card in portrait, beside the
-- buttons in landscape.
function PassewordScreen:_turnLayout(header, word, sub, rows)
    local land = self:isLandscape()
    local title_bar = self:_titleBar()
    local controls = self:_controls(rows, land and header or nil)
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local vs = Size.span.vertical_large
    local card_h = bh - (land and 0 or (header:getSize().h + vs))
    local card = self:_wordCard(word, sub, bw, card_h)
    local content = land and card or VerticalGroup:new{ align = "center", header, VerticalSpan:new{ width = vs }, card }
    self:_place(title_bar, content, controls)
end

function PassewordScreen:_timerPx()
    local short = math.min(self.dimen.w, self.dimen.h)
    return math.floor(short * (self:isLandscape() and 0.1 or 0.11))
end

-- ---------------------------------------------------------------------------
-- Screens
-- ---------------------------------------------------------------------------

function PassewordScreen:buildLayout()
    local phase = self.game.phase
    self.timer_widget, self.timer_frame, self.banner_frame = nil, nil, nil
    if self.joker_words and phase == "decision" then
        self:_buildJoker()
    elseif phase == "handover" then
        self:_buildHandover()
    elseif phase == "turn" then
        self:_buildTurn()
    elseif phase == "qual_over" then
        self:_buildQualOver()
    elseif phase == "tb_handover" then
        self:_buildTbHandover()
    elseif phase == "tb_turn" then
        self:_buildTbTurn()
    elseif phase == "final_handover" then
        self:_buildFinalHandover()
    elseif phase == "final_turn" then
        self:_buildFinalTurn()
    elseif phase == "decision" then
        self:_buildDecision()
    elseif phase == "game_over" then
        self:_buildGameOver()
    else
        self:_buildSetup()
    end
    self[1] = self.layout
    self:updateStatus()
end

function PassewordScreen:_scoreTable(width, max_h)
    local g = self.game
    if g.swap then
        local rows = {}
        local order = g.phase == "setup" and { 1, 2, 3, 4 } or g:ranking()
        for i, p in ipairs(order) do rows[i] = { self:_name(p), g.score[p] } end
        return W.scoreTable({ "", _("Total") }, rows, width, max_h)
    end
    local headers = { "" }
    for r = 1, Game.QUAL_ROUNDS do headers[#headers + 1] = T(_("R%1"), r) end
    headers[#headers + 1] = _("Total")
    local rows = {}
    for t = 1, 2 do
        local row = { self:_teamName(t) }
        for r = 1, Game.QUAL_ROUNDS do
            local v = g.rounds[r] and g.rounds[r][t]
            row[#row + 1] = v and tostring(v) or "–"
        end
        row[#row + 1] = g:teamScore(t)
        rows[t] = row
    end
    return W.scoreTable(headers, rows, width, max_h)
end

function PassewordScreen:_buildSetup()
    local g = self.game
    local title_bar = self:_titleBar()
    local controls = self:_controls({
        { self:_bigButton(_("Start game"), function() self:onStartGame() end, nil, 1.3) },
        { self:_bigButton(_("Player names"), function() self:openPlayersDialog() end) },
    })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local info_face = Font:getFace("infofont")
    local items = {
        W.fitLine(_("Pass the Word"), short * 0.1, bw, true),
        W.fitLine(T(_("Team %1: %2"), "A", self:_teamName(1)), short * 0.055, bw, true),
        W.fitLine(T(_("Team %1: %2"), "B", self:_teamName(2)), short * 0.055, bw, true),
        para(_("Qualification: 4 rounds of 30 s, 5 words each. The best team plays the final: 5 levels, 5 words in 1:30, at most 3 clues per word."),
            info_face, bw),
        para(g.swap and _("Partners swap in rounds 3–4: individual ranking.")
            or _("Team ranking (partners swap: off)."), Font:getFace("smallinfofont"), bw),
    }
    local head = stack({ items[1] }, vs)
    local body = stack({ items[2], items[3] }, vs)
    local used = head:getSize().h + body:getSize().h + items[4]:getSize().h + items[5]:getSize().h + 8 * vs
    local pyr = self:_pyramid(math.floor(bw * 0.75), math.max(bh - used, short * 0.25))
    local content = stack({ head, body, items[4], pyr, items[5] }, vs * 2)
    self:_place(title_bar, content, controls)
end

-- Neutral screen between turns: no word visible until Ready is tapped.
function PassewordScreen:_buildHandover()
    local g = self.game
    local giver, guesser = g:pairing()
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("Ready"), function() self:onReady() end, nil, 1.4) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local info = Font:getFace("infofont")
    local items = {}
    if g.last_turn then
        local lt = g.last_turn
        items[#items + 1] = para(T(lt.points == 1 and _("%1 and %2 found %3 word.") or _("%1 and %2 found %3 words."),
            self:_name(lt.giver), self:_name(lt.guesser), lt.points), info, bw)
    end
    items[#items + 1] = W.fitLine(T(_("Round %1 of %2"), g.round, Game.QUAL_ROUNDS), short * 0.07, bw, true)
    items[#items + 1] = W.fitLine(T(_("Clue-giver: %1"), self:_name(giver)), short * 0.09, bw, true)
    items[#items + 1] = W.fitLine(T(_("Guesser: %1"), self:_name(guesser)), short * 0.07, bw)
    items[#items + 1] = W.fitLine(_("Guesser, look away!"), short * 0.065, bw, true)
    items[#items + 1] = para(T(_("Hold the reader so only %1 sees it. Tap Ready to show the first word and start the %2 s timer."),
        self:_name(giver), Game.QUAL_TIME), Font:getFace("smallinfofont"), math.floor(bw * 0.92))
    local content = stack(items, vs * 2)
    local used = content:getSize().h
    if bh - used > short * 0.25 then
        content = stack({ content, self:_scoreTable(math.floor(bw * 0.92), math.min(bh - used - 4 * vs, short * 0.4)) }, vs * 4)
    end
    self:_place(title_bar, content, controls)
end

function PassewordScreen:_buildTurn()
    local g = self.game
    local giver, guesser = g:pairing()
    local header = VerticalGroup:new{
        align = "center",
        self:_timer(self:_timerPx()),
        W.fitLine(T(_("Round %1 of %2"), g.round, Game.QUAL_ROUNDS) .. " · "
            .. T(_("%1 → %2"), self:_name(giver), self:_name(guesser)),
            Font:getFace("infofont").size, self:getControlsWidth()),
    }
    local found = self:_bigButton("✓ " .. _("Found"), function() self:onFound() end, nil, 1.6)
    local pass = self:_bigButton("→ " .. _("Pass"), function() self:onPass() end, { enabled = g:canPass() })
    local forbidden = self:_bigButton("✗ " .. _("Forbidden!"), function() self:onForbidden() end)
    local undo = self:_bigButton("↶ " .. _("Undo"), function() self:onUndo() end, { enabled = g:canUndo() })
    -- The landscape side panel is too narrow for three labels on one row.
    local rows = self:isLandscape() and { { found }, { forbidden }, { pass, undo } }
        or { { found }, { pass, forbidden, undo } }
    self:_turnLayout(header, g:currentWord(), nil, rows)
end

function PassewordScreen:_buildQualOver()
    local g = self.game
    local q = g.qual
    local title_bar = self:_titleBar()
    local label = q.finalists and _("Go to the final") or _("Tie-break")
    local controls = self:_controls({ self:_bigButton(label, function() self:onQualNext() end, nil, 1.3) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local info = Font:getFace("infofont")
    local items = { W.fitLine(_("Qualification over"), short * 0.08, bw, true) }
    if q.tb_result then
        local r = q.tb_result
        local s = q.tiebreak[r.side]
        local who = s.team and self:_teamName(s.team) or T(_("%1 & %2"), self:_name(s.giver), self:_name(s.guesser))
        items[#items + 1] = para(r.reason == "found"
            and T(_("Tie-break: %1 found “%2”."), who, r.word)
            or T(_("Tie-break: forbidden clue on “%1”, %2 go through."), r.word, who), info, bw)
    end
    if q.finalists then
        items[#items + 1] = para(T(_("%1 and %2 play the final!"), self:_name(q.finalists[1]),
            self:_name(q.finalists[2])), Font:getFace("tfont"), bw)
        if q.by_lot then
            items[#items + 1] = para(_("Tied scores: the finalists were drawn by lot."), Font:getFace("smallinfofont"), bw)
        end
    else
        items[#items + 1] = para(_("It's a tie! One word for both sides, clue-givers take 10 s turns."), info, bw)
    end
    local top = stack(items, vs * 2)
    local content = stack({ top, self:_scoreTable(math.floor(bw * 0.95), bh - top:getSize().h - 4 * vs) }, vs * 3)
    self:_place(title_bar, content, controls)
end

function PassewordScreen:_buildTbHandover()
    local g = self.game
    local s1, s2 = g:tbSide(1), g:tbSide(2)
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("Ready"), function() self:onTbReady() end, nil, 1.4) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local guessers = s1.guesser == s2.guesser and self:_name(s1.guesser)
        or T(_("%1 and %2"), self:_name(s1.guesser), self:_name(s2.guesser))
    local items = {
        W.fitLine(_("Tie-break"), short * 0.1, bw, true),
        W.fitLine(T(_("Clue-givers: %1 and %2"), self:_name(s1.giver), self:_name(s2.giver)), short * 0.065, bw, true),
        W.fitLine(T(_("Look away: %1"), guessers), short * 0.065, bw, true),
        para(T(_("One word for both sides. %1 starts; every 10 s the other clue-giver takes over. The first to make their partner find it wins; a forbidden clue eliminates."),
            self:_name(s1.giver)), Font:getFace("infofont"), math.floor(bw * 0.95)),
    }
    self:_place(title_bar, stack(items, vs * 3), controls)
end

function PassewordScreen:_buildTbTurn()
    local g = self.game
    local land = self:isLandscape()
    local cw = land and self:getControlsWidth() or (self.dimen.w - 2 * self:getGutter())
    self.banner_px = math.floor(self:_timerPx() * 0.6)
    local banner = W.banner(self:_tbBannerText(), self.banner_px, cw)
    self.banner_frame = banner
    local header = VerticalGroup:new{
        align = "center", banner, VerticalSpan:new{ width = Size.span.vertical_default },
        self:_timer(math.floor(self:_timerPx() * 0.8)),
    }
    local other = self:_bigButton("⟳ " .. _("Other word"), function() self:onTbNewWord() end)
    local forbidden = self:_bigButton("✗ " .. _("Forbidden!"), function() self:onTbForbidden() end)
    local rows = { { self:_bigButton("✓ " .. _("Found"), function() self:onTbFound() end, nil, 1.6) } }
    if land then
        rows[2], rows[3] = { forbidden }, { other }
    else
        rows[2] = { other, forbidden }
    end
    self:_turnLayout(header, g:currentWord(), nil, rows)
end

function PassewordScreen:_levelText(level)
    local lv = Game.LEVELS[level]
    return T(_("Find %1 words out of %2 in 1:30. At most 3 clues per word; a passed word is lost."),
        Game.FINAL_TARGET, lv.words)
end

function PassewordScreen:_buildFinalHandover()
    local g = self.game
    local f = g.final
    local title_bar = self:_titleBar()
    local controls = self:_controls({
        { self:_bigButton(_("Ready"), function() self:onFinalReady() end, nil, 1.4) },
        { self:_bigButton("⇄ " .. _("Swap roles"), function() self:onSwapRoles() end) },
    })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local items = {
        W.fitLine(T(_("Final · Level %1"), f.level), short * 0.085, bw, true),
        W.fitLine(T(_("Clue-giver: %1"), self:_name(f.giver)), short * 0.07, bw, true),
        W.fitLine(T(_("Guesser: %1 — look away!"), self:_name(f.guesser)), short * 0.06, bw),
        para(self:_levelText(f.level), Font:getFace("smallinfofont"), math.floor(bw * 0.92)),
    }
    local top = stack(items, vs * 2)
    local pyr = self:_pyramid(math.floor(bw * 0.8), math.min(bh - top:getSize().h - 4 * vs, short * 0.7))
    self:_place(title_bar, stack({ top, pyr }, vs * 3), controls)
end

function PassewordScreen:_buildFinalTurn()
    local g = self.game
    local f = g.final
    local lv = Game.LEVELS[f.level]
    local header = VerticalGroup:new{
        align = "center",
        self:_timer(self:_timerPx()),
        W.fitLine(T(_("Level %1"), f.level) .. " · " .. self:_prize(lv.prize) .. " · "
            .. T(_("Found: %1/%2"), f.found, Game.FINAL_TARGET),
            Font:getFace("infofont").size, self:getControlsWidth()),
    }
    local dots = {}
    for i = 1, Game.MAX_CLUES do dots[i] = i <= f.clues and "●" or "○" end
    local sub = T(_("Clues: %1"), table.concat(dots, " "))
    local clue_btn
    if g:canClue() then
        clue_btn = self:_bigButton(T(_("Clue given (%1/%2)"), f.clues, Game.MAX_CLUES),
            function() self:onClue() end)
    else
        clue_btn = self:_bigButton("✗ " .. _("Not found"), function() self:onFinalLose("clues") end)
    end
    local rows = {
        { self:_bigButton("✓ " .. _("Found"), function() self:onFinalFound() end, nil, 1.5) },
        { clue_btn, self:_bigButton("→ " .. _("Pass (lost)"), function() self:onFinalLose("pass") end) },
        {
            self:_bigButton("✗ " .. _("Forbidden!"), function() self:onFinalLose("forbidden") end),
            self:_bigButton("↶ " .. _("Undo"), function() self:onFinalUndo() end, { enabled = g:canUndo() }),
        },
    }
    self:_turnLayout(header, g:currentWord(), sub, rows)
end

function PassewordScreen:_buildDecision()
    local g = self.game
    local f = g.final
    local title_bar = self:_titleBar()
    local keep = self:_prize(Game.LEVELS[f.cleared].prize)
    local rows = {
        { self:_bigButton(T(_("Continue: level %1"), f.level), function() self:onContinue() end, nil, 1.3) },
        { self:_bigButton(T(_("Stop and keep %1"), keep), function() self:onStop() end) },
    }
    if g:canUseJoker() then
        local joker = self:_bigButton("★ " .. _("Joker"), function() self:onJoker() end)
        if self:isLandscape() then rows[3] = { joker } else rows[2][2] = joker end
    end
    local controls = self:_controls(rows)
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local risk = g:safetyPrize()
    local items = {
        W.fitLine(T(_("Level %1 cleared!"), f.cleared), short * 0.09, bw, true),
        para(T(_("Stop now with %1, or play level %2 for %3."), keep, f.level,
            self:_prize(Game.LEVELS[f.level].prize)), Font:getFace("infofont"), bw),
        para(risk > 0 and T(_("If you fail, you leave with %1 (safety level)."), self:_prize(risk))
            or _("If you fail, you leave with nothing."), Font:getFace("smallinfofont"), bw),
    }
    if g:canUseJoker() then
        items[#items + 1] = para(T(_("Joker: see the first %1 words of level %2 for 3 s each before deciding."),
            Game.JOKER_WORDS, f.level), Font:getFace("smallinfofont"), bw)
    elseif f.preview_seen then
        items[#items + 1] = para(_("Joker used."), Font:getFace("smallinfofont"), bw)
    end
    local top = stack(items, vs * 2)
    local pyr = self:_pyramid(math.floor(bw * 0.8), math.min(bh - top:getSize().h - 4 * vs, short * 0.7))
    self:_place(title_bar, stack({ top, pyr }, vs * 3), controls)
end

function PassewordScreen:_buildJoker()
    local g = self.game
    local f = g.final
    local header = W.fitLine(T(_("Joker · level %1 · word %2 of %3"), f.level, self.joker_idx, #self.joker_words),
        Font:getFace("infofont").size * 1.2, self:getControlsWidth(), true)
    self:_turnLayout(header, self.joker_words[self.joker_idx], _("Next word in 3 s"), {})
end

function PassewordScreen:_buildGameOver()
    local g = self.game
    local f = g.final
    local o = f.outcome or { kind = "failed", level = f.level, prize = 0 }
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("New game"), function() self:onNewGame() end) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local head, line
    if o.kind == "won" then
        head = T(_("Jackpot: %1!"), self:_prize(o.prize))
        line = _("All five levels cleared. Bravo!")
    elseif o.kind == "stopped" then
        head = T(_("You keep %1"), self:_prize(o.prize))
        line = T(_("Stopped after level %1."), o.level)
    else
        head = o.prize > 0 and T(_("You leave with %1"), self:_prize(o.prize)) or _("You leave with nothing")
        line = T(o.why == "time" and _("Level %1 failed: time's up with %2 words found.")
            or _("Level %1 failed: not enough words left (%2 found)."), o.level, o.found or 0)
    end
    local items = {
        W.fitLine(head, short * 0.09, bw, true),
        para(T(_("%1 and %2"), self:_name(f.pair[1]), self:_name(f.pair[2])) .. " · " .. line,
            Font:getFace("infofont"), bw),
    }
    -- The words of the last level played, found or not.
    if f.results and #f.results > 0 and o.kind ~= "stopped" then
        local parts = {}
        for _i, r in ipairs(f.results) do parts[#parts + 1] = (r.found and "✓\u{00A0}" or "✗\u{00A0}") .. r.word:gsub(" ", "\u{00A0}") end
        items[#items + 1] = para(table.concat(parts, "   "), Font:getFace("smallinfofont"), bw)
    end
    local top = stack(items, vs * 2)
    local pyr = self:_pyramid(math.floor(bw * 0.8), math.min(bh - top:getSize().h - 4 * vs, short * 0.7))
    self:_place(title_bar, stack({ top, pyr }, vs * 3), controls)
end

function PassewordScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local g = self.game
    local p = g.phase
    local s
    if p == "turn" then
        s = self:joinStatus(T(_("Words left: %1"), #g.queue), T(_("Words found: %1"), g.turn_points))
    elseif p == "handover" or p == "qual_over" then
        if g.swap then
            local parts = {}
            for _i, i in ipairs(g:ranking()) do parts[#parts + 1] = self:_name(i) .. " " .. g.score[i] end
            s = self:joinStatus(unpack(parts))
        else
            s = self:joinStatus(T(_("Team %1: %2"), "A", g:teamScore(1)), T(_("Team %1: %2"), "B", g:teamScore(2)))
        end
    elseif p == "tb_turn" then
        local side = g:tbSide()
        s = self:joinStatus(_("Tie-break"), T(_("Clue-giver: %1"), self:_name(side.giver)))
    elseif p == "final_turn" then
        s = self:joinStatus(T(_("Words left: %1"), g:finalWordsLeft()),
            T(_("Guaranteed: %1"), self:_prize(g:safetyPrize())))
    elseif p == "final_handover" or p == "decision" then
        local f = g.final
        local joker = f.joker == "available" and _("Joker: available")
            or (f.joker == "used" and _("Joker: used") or _("Joker: at level 2"))
        s = self:joinStatus(T(_("%1 and %2"), self:_name(f.pair[1]), self:_name(f.pair[2])), joker)
    elseif p == "setup" then
        s = self:joinStatus(T(_("Language: %1"), self.lang:upper()), T(_("Prizes: %1"), self:_unitLabel()))
    else
        s = ""
    end
    ScreenBase.updateStatus(self, s)
end

function PassewordScreen:closeScreen()
    self:_stopCountdown()
    ScreenBase.closeScreen(self)
end

return PassewordScreen
