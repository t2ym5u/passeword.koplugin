-- Text helpers, the score table and the prize pyramid for the Pass the Word screen.

local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local LineWidget      = require("ui/widget/linewidget")
local Blitbuffer      = require("ffi/blitbuffer")
local Size            = require("ui/size")
local FrameContainer  = require("ui/widget/container/framecontainer")
local VerticalSpan    = require("ui/widget/verticalspan")

local DeviceScreen = Device.screen

-- Font:getFace() scales by DPI: pixel-derived sizes are divided back first.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local W = {}

function W.pxFace(px, bold)
    return Font:getFace(bold and "tfont" or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

-- One line at up to px, shrunk until it fits max_w.
function W.fitLine(text, px, max_w, bold, fgcolor)
    local tw
    fgcolor = fgcolor or Blitbuffer.COLOR_BLACK
    while true do
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold, fgcolor = fgcolor }
        if tw:getSize().w <= max_w or px <= 12 then break end
        tw:free()
        px = math.floor(px * 0.9)
    end
    if tw:getSize().w > max_w then
        tw:free()
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold, fgcolor = fgcolor,
                             max_width = max_w }
    end
    return tw
end

-- A centred paragraph as big as possible (<= max_px) inside width x max_h,
-- without splitting a word across lines.
function W.fitParagraph(text, max_px, width, max_h, bold)
    local px = max_px
    while true do
        local face = W.pxFace(px, bold)
        local words_fit = true
        for word in text:gmatch("%S+") do
            local tw = TextWidget:new{ text = word, face = face, bold = bold }
            local w = tw:getSize().w
            tw:free()
            if w > width then words_fit = false; break end
        end
        if words_fit or px <= 12 then
            local tb = TextBoxWidget:new{ text = text, face = face, bold = bold, width = width,
                                          alignment = "center" }
            if tb:getSize().h <= max_h or px <= 12 then return tb end
            tb:free()
        end
        px = math.floor(px * 0.9)
    end
end

-- Score table: one row per team, one column per round played, then total.
-- rows: { { name, s1, s2, s3, total, bold } }, headers: { "", "1", "2", "3", "Total" }
function W.scoreTable(headers, rows, width, max_h)
    local n = #rows + 1
    local row_h = math.floor(math.min(max_h / n, width * 0.12))
    local px = math.max(14, math.floor(row_h * 0.45))
    local ncols = #headers - 1
    local name_w = math.floor(width * (ncols > 2 and 0.42 or 0.6))
    local col_w = math.floor((width - name_w) / ncols)
    local function row(cells, bold_last, bold_all)
        local hg = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = name_w, h = row_h },
                W.fitLine(cells[1], px, name_w - Size.padding.default, true) },
        }
        for i = 2, #cells do
            local bold = bold_all or (bold_last and i == #cells)
            hg[#hg + 1] = CenterContainer:new{ dimen = Geom:new{ w = col_w, h = row_h },
                W.fitLine(tostring(cells[i]), px, col_w - Size.padding.small, bold) }
        end
        return hg
    end
    local g = VerticalGroup:new{ align = "left", row(headers, false, true),
        LineWidget:new{ background = Blitbuffer.COLOR_GRAY,
                        dimen = Geom:new{ w = width, h = Size.line.medium } } }
    for _, r in ipairs(rows) do g[#g + 1] = row(r, true) end
    return g
end


-- Prize pyramid, top level first. rows: { { label, prize, state } } bottom
-- (level 1) first; state = "cleared" | "current" | "todo", safety = level
-- index marked with a star. Narrow at the top, wide at the bottom.
function W.pyramid(rows, safety, width, max_h)
    local n = #rows
    local gap = Size.padding.small
    local row_h = math.floor(math.min((max_h - gap * (n - 1)) / n, width * 0.13))
    local px = math.max(12, math.floor(row_h * 0.5))
    local g = VerticalGroup:new{ align = "center" }
    for i = n, 1, -1 do
        local r = rows[i]
        local w = math.floor(width * (0.55 + 0.45 * (n - i) / math.max(1, n - 1)))
        local current = r.state == "current"
        local fg = current and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local mark = r.state == "cleared" and "✓ " or ""
        local star = i == safety and " ★" or ""
        local inner_w = w - 2 * (Size.border.thick + Size.padding.small)
        local inner_h = row_h - 2 * Size.border.thick
        g[#g + 1] = FrameContainer:new{
            bordersize = r.state == "todo" and Size.border.default or Size.border.thick,
            padding = 0, padding_left = Size.padding.small, padding_right = Size.padding.small,
            margin = 0, radius = Size.radius.default,
            background = current and Blitbuffer.COLOR_BLACK
                or (r.state == "cleared" and Blitbuffer.COLOR_LIGHT_GRAY) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                W.fitLine(mark .. r.label .. " · " .. r.prize .. star, px, inner_w,
                          current or r.state == "cleared", fg),
            },
        }
        if i > 1 then g[#g + 1] = VerticalSpan:new{ width = gap } end
    end
    return g
end

-- A black banner with white text (whose turn it is in the tie-break).
-- Returns the frame and its text widget, so the text can be swapped in place.
function W.banner(text, px, width)
    local tw = W.fitLine(text, px, width - 2 * Size.padding.large, true, Blitbuffer.COLOR_WHITE)
    local frame = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0, radius = Size.radius.window,
        background = Blitbuffer.COLOR_BLACK,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = tw:getSize().h + 2 * Size.padding.default }, tw },
    }
    return frame, tw
end

return W
