-- The compass: which way the towns are, without turning the sky into a
-- wall of names.
--
-- A ribbon across the top of the playfield, read like every heading strip
-- ever made: what is straight ahead is in the middle, and turning slides the
-- world past it. Cardinal letters keep it legible as a compass even with no
-- town in view; each town is a pip at its own bearing.
--
-- THE WHOLE DESIGN PROBLEM IS CLUTTER. Eleven towns, some of them nearly in
-- line with each other, would stack their labels into an unreadable pile the
-- moment the player faced east. Three rules keep it calm, and each one is
-- doing a different job:
--
--   ONE PIP PER SECTOR    the arc is cut into 20-degree sectors and only the
--                         NEAREST town in each survives. "Which town lies
--                         that way" has exactly one answer, and because it
--                         is re-decided every frame, flying past the near
--                         one hands the sector to the one behind it.
--
--   LABELS ONLY WHERE     the pip in the middle -- what you are flying at --
--   THEY FIT              always gets its name. The rest get one only if the
--                         MEASURED width of the text clears everything
--                         already placed. Greedy from the middle out, so the
--                         labels you care about win the space, and no two
--                         can ever overlap at any window size.
--
--   FADE, NEVER POP       markers dim toward the edges of the arc and as
--                         they are reached, so the set changes by sliding
--                         rather than by blinking.
--
-- Colours are not a free choice here. The Game Boy font sheets are BLACK
-- glyphs on transparent, so setColor cannot make a letter pale -- the voxel
-- mod's own HUD documents the same trap (lib/HordeHud.lua). Everything is
-- therefore dark on a light plate, which is also how the game already talks
-- to the player, so the ribbon reads as part of it rather than as an overlay.

local V = ...
local Flight = V.require("Flight")

local Compass = {}

-- ------- the arc
--
-- SPAN is the half-arc the ribbon shows either side of the heading. Wide
-- enough that a town slightly off the nose is already on screen, narrow
-- enough that the scale stays readable rather than compressing the whole
-- horizon into 150 pixels.
Compass.SPAN = math.rad(80)

-- The sector width the nearest-only rule is applied over.
Compass.SECTOR = math.rad(20)

-- Inside this many world pixels a town counts as REACHED and leaves the
-- ribbon: you are over it and can see it out of the window, and its sector
-- is more useful showing what lies beyond. Ten cells.
Compass.ARRIVE = 160

-- ------- geometry (pure)

local TWO_PI = math.pi * 2

function Compass.wrapPi(a)
  a = (a + math.pi) % TWO_PI
  if a < 0 then a = a + TWO_PI end
  return a - math.pi
end

-- The world bearing from (bx, bz) to (tx, tz), in FirstPerson's own
-- convention: yaw 0 faces SOUTH (+Z) and grows toward east, because the look
-- direction there is (sin yaw, cos yaw). Deriving the compass from the same
-- expression is what keeps the ribbon and the flight pointing the same way.
function Compass.bearingTo(bx, bz, tx, tz)
  return math.atan2(tx - bx, tz - bz)
end

-- Where a world bearing sits relative to where the camera looks.
function Compass.relative(bearing, yaw)
  return Compass.wrapPi(bearing - (yaw or 0))
end

-- The cardinal points, as world bearings in that same convention: south is
-- 0, and a quarter turn is east. Written as multiples of pi/2 rather than as
-- numbers so the relationship to the convention above stays visible.
Compass.CARDINALS = {
  { label = "S", bearing = 0 },
  { label = "W", bearing = -math.pi / 2 },
  { label = "N", bearing = math.pi },
  { label = "E", bearing = math.pi / 2 },
}

-- The four in between, as ticks with no letter.
Compass.INTERCARDINALS = {
  math.pi / 4, 3 * math.pi / 4, -math.pi / 4, -3 * math.pi / 4,
}

-- A town you have been to, and may therefore land in. Dark enough to hold
-- its shape against the ribbon's pale plate at one screen pixel, green
-- enough to be read as a colour and not as ink that came out odd.
Compass.PIP_LANDABLE = { 0.13, 0.44, 0.19 }

-- ------- choosing what to show (pure)
--
-- `towns` is Atlas's list: { id, name, x, z, visited }. Returns the markers
-- that survive, nearest-first within each sector, each carrying its
-- relative bearing, its distance and its fade.
function Compass.select(towns, bx, bz, yaw)
  local best = {}
  for _, t in ipairs(towns or {}) do
    local dx, dz = t.x - bx, t.z - bz
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist > Compass.ARRIVE then
      local rel = Compass.relative(Compass.bearingTo(bx, bz, t.x, t.z), yaw)
      if math.abs(rel) <= Compass.SPAN then
        -- floor rather than round: sectors must tile the arc without gaps
        -- or a town on a boundary belongs to two of them
        local sector = math.floor((rel + Compass.SPAN) / Compass.SECTOR)
        local held = best[sector]
        if not held or dist < held.dist then
          best[sector] = { town = t, rel = rel, dist = dist }
        end
      end
    end
  end

  local out = {}
  for _, m in pairs(best) do out[#out + 1] = m end
  -- nearest the nose first: that is the order labels are handed out in, so
  -- the town being flown at can never lose its name to one off to the side
  table.sort(out, function(a, b)
    if math.abs(a.rel) ~= math.abs(b.rel) then
      return math.abs(a.rel) < math.abs(b.rel)
    end
    return a.town.id < b.town.id
  end)

  for i, m in ipairs(out) do
    -- dim toward the rim of the arc, so a marker slides out rather than
    -- vanishing mid-turn
    local edge = math.abs(m.rel) / Compass.SPAN
    m.fade = math.max(0, math.min(1, (1 - edge) / 0.3))
    m.centred = (i == 1)
  end
  return out
end

-- ------- handing out labels (pure)
--
-- `widthOf(text)` measures in the same units as `bandW`, and `xOf(rel)`
-- places a marker on the band. Greedy over the already-sorted markers: each
-- takes its span if it clears every span already taken.
--
-- Returns the markers that got one, each with `label`, `lx` and `lw`.
function Compass.assignLabels(markers, widthOf, xOf, bandX, bandW, gap)
  gap = gap or 4
  local taken, out = {}, {}
  for _, m in ipairs(markers or {}) do
    -- longest first: the fullest thing that fits wins, and a narrow window
    -- degrades to the name alone rather than to a clipped one
    for _, text in ipairs(Compass.labelFor(m)) do
      local w = widthOf(text)
      -- centred on the pip, then pulled back inside the band so a marker
      -- near the rim still shows its whole name
      local lx = xOf(m.rel) - w / 2
      if lx < bandX then lx = bandX end
      if lx + w > bandX + bandW then lx = bandX + bandW - w end
      local clear = w <= bandW
      if clear then
        for _, t in ipairs(taken) do
          if lx < t.x + t.w + gap and t.x < lx + w + gap then
            clear = false
            break
          end
        end
      end
      if clear then
        taken[#taken + 1] = { x = lx, w = w }
        m.label, m.lx, m.lw = text, lx, w
        out[#out + 1] = m
        break
      end
    end
  end
  return out
end

-- ------- what a marker's plate says
--
-- A LIST, longest first, not one string: the caller measures and takes the
-- first that fits.
--
-- An earlier cut trimmed the place-kind off every name ("VIRIDIAN" for
-- "VIRIDIAN CITY") to buy room. That bought it with a hardcoded list of
-- English suffixes -- which is a translation mod's name mangled in a
-- language whose towns do not end in " CITY", to save space the ribbon
-- turned out not to need once it stopped drawing at the world's scale.
--
-- So the name is now whatever the data says, in full, and it is the LAYOUT
-- that gives way when a window is too narrow: distance first, then the
-- label entirely, leaving a pip that still points the right way. Nothing in
-- this mod knows what a town is called.
--
-- An unvisited town is deliberately anonymous -- naming a place the player
-- has never been would hand them the map. It gets a name only in the sense
-- of saying what it is NOT: somewhere they can put down. Shown only when it
-- is the one being flown at, so the ribbon never carries a row of question
-- marks explaining themselves.
function Compass.labelFor(m)
  local t = m.town
  if not t.visited then
    if m.centred then return { "? NOT EXPLORED", "?" } end
    return {}
  end
  local name = tostring(t.name or "")
  if m.centred then
    return { ("%s %d"):format(name, math.floor(m.dist / 16 + 0.5)), name }
  end
  return { name }
end

-- ------- the toast
--
-- A line under the ribbon that says why something did not happen, then goes
-- away. Not a TextBox: pushing a real one would take the stack, stop the
-- world and end the flight's input for as long as it was up, which is a
-- heavy answer to "that button did nothing".

-- Two lines rather than one, for the same twenty-character reason the names
-- are shortened: "CAN'T LAND - NOT EXPLORED YET" is twenty-nine characters
-- and would run off both edges of the screen. Split, each line fits with
-- room to spare, and the message keeps both halves of what it has to say --
-- what happened, and why.
Compass.TOAST_TIME = 2.2
local toast = nil

function Compass.say(...)
  toast = { lines = { ... }, t = Compass.TOAST_TIME }
end

function Compass.update(dt)
  if toast then
    toast.t = toast.t - (dt or 0)
    if toast.t <= 0 then toast = nil end
  end
end

function Compass.clear()
  toast = nil
end

function Compass._toast() return toast end

-- ------- drawing

local Font = nil
local function font()
  if Font then return Font end
  local ok, F = pcall(require, "src.render.Font")
  if ok then Font = F end
  return Font
end

local BAND_H = 11        -- GB pixels
local BAND_Y = 5
local BAND_INSET = 6
local PAD = 2

local function plate(x, y, w, h, alpha)
  love.graphics.setColor(0.06, 0.05, 0.09, alpha * 0.9)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  love.graphics.setColor(0.93, 0.94, 0.90, alpha * 0.92)
  love.graphics.rectangle("fill", x, y, w, h)
end

-- Black glyphs at `s` times their size -- black because that is the only
-- colour the font has (see the header).
local function text(str, x, y, s, alpha)
  local F = font()
  if not F then return end
  love.graphics.setColor(0, 0, 0, alpha)
  love.graphics.push()
  love.graphics.translate(math.floor(x), math.floor(y))
  love.graphics.scale(s, s)
  F.draw(str, 0, 0)
  love.graphics.pop()
end

local function textW(str)
  local F = font()
  return F and F.width(str) or 0
end

-- The ribbon fades in with the climb and out with the descent, for free:
-- altitude already runs 0 -> CRUISE -> 0 over exactly those two beats.
local function ribbonAlpha()
  if not Flight.active() then return 0 end
  return math.max(0, math.min(1, Flight.altitude / Flight.CRUISE))
end

-- Counters the driver reads to tell "the ribbon drew nothing" apart from
-- "the ribbon was never asked to draw" -- two very different bugs that look
-- identical in a screenshot.
Compass.calls = 0
Compass.draws = 0
Compass.lastSkip = nil

-- viewport is render.hud's: window pixels, with the playfield rect inside it.
function Compass.draw(viewport, towns, bx, bz, yaw)
  Compass.calls = Compass.calls + 1
  local a = ribbonAlpha()
  if a <= 0.01 then Compass.lastSkip = "alpha" return end
  local F = font()
  if not F then Compass.lastSkip = "font" return end
  Compass.draws = Compass.draws + 1

  -- ------- how big the ribbon is
  --
  -- NOT one game pixel per game pixel. The screen is 160 game pixels wide
  -- and a character is eight of them, so a ribbon drawn at the world's own
  -- scale is a HUD twenty characters wide -- one label at a time, filling a
  -- third of the picture, with the diorama peering out from behind it.
  --
  -- So the ribbon has its own scale: a fraction of the world's, floored to a
  -- WHOLE NUMBER OF SCREEN PIXELS. Whole, because a pixel font at 3.2x
  -- samples its own edges and comes out furry -- the one thing that would
  -- make this read as an overlay bolted on rather than part of the game.
  local world = (viewport.gameWidth or 160) / 160
  local s = math.max(1, math.floor(world * 0.55))
  if s <= 0 then return end
  local gx, gy = viewport.gameX or 0, viewport.gameY or 0

  -- Centred and short of the full width, so the ribbon reads as an
  -- instrument sitting on the picture rather than as a bar clamped across
  -- the top of it -- and so the diorama still owns its own corners.
  local playW = viewport.gameWidth or 160
  local bandW = math.min(playW - 2 * BAND_INSET * s, playW * 0.82)
  local bandX = gx + (playW - bandW) / 2
  local bandY = gy + BAND_Y * s
  local bandH = BAND_H * s
  local midX = bandX + bandW / 2

  local function xOf(rel)
    return midX + (rel / Compass.SPAN) * (bandW / 2)
  end

  plate(bandX, bandY, bandW, bandH, a)

  -- the heading notch: a dark tick through the middle, so "straight ahead"
  -- is a place on the ribbon rather than something to estimate
  love.graphics.setColor(0.06, 0.05, 0.09, a)
  love.graphics.rectangle("fill", math.floor(midX) - math.max(1, s / 2),
                          bandY - 2 * s, math.max(1, s), bandH + 3 * s)

  -- the intercardinal ticks, then the cardinal letters over them
  for _, bearing in ipairs(Compass.INTERCARDINALS) do
    local rel = Compass.relative(bearing, yaw)
    if math.abs(rel) <= Compass.SPAN then
      love.graphics.setColor(0.06, 0.05, 0.09, a * 0.45)
      love.graphics.rectangle("fill", xOf(rel), bandY + bandH - 3 * s,
                              math.max(1, s), 3 * s)
    end
  end
  for _, c in ipairs(Compass.CARDINALS) do
    local rel = Compass.relative(c.bearing, yaw)
    if math.abs(rel) <= Compass.SPAN then
      local w = textW(c.label) * s
      text(c.label, xOf(rel) - w / 2, bandY + PAD * s, s, a * 0.85)
    end
  end

  -- the towns
  local markers = Compass.select(towns, bx, bz, yaw)
  for _, m in ipairs(markers) do
    local x = xOf(m.rel)
    local alpha = a * m.fade
    love.graphics.setColor(0.06, 0.05, 0.09, alpha)
    if m.town.visited then
      -- A solid pip for somewhere you can actually put down, and in green
      -- rather than in the ink the rest of the ribbon is drawn in. Filled
      -- against hollow is only one glance apart if you already know to look;
      -- "can I land there" is the question the ribbon exists to answer, so it
      -- gets a colour of its own and stops depending on the reading.
      local g = Compass.PIP_LANDABLE
      love.graphics.setColor(g[1], g[2], g[3], alpha)
      love.graphics.rectangle("fill", x - 1.5 * s, bandY + bandH - 3 * s,
                              3 * s, 3 * s)
    else
      -- and a hollow one for somewhere you cannot
      love.graphics.setLineWidth(math.max(1, s * 0.75))
      love.graphics.rectangle("line", x - 1.5 * s, bandY + bandH - 3 * s,
                              3 * s, 3 * s)
      love.graphics.setLineWidth(1)
    end
  end

  local labelled = Compass.assignLabels(markers,
                                        function(t) return textW(t) * s end,
                                        xOf, bandX, bandW, 4 * s)
  local labelY = bandY + bandH + 3 * s
  for _, m in ipairs(labelled) do
    local alpha = a * m.fade
    plate(m.lx - PAD * s, labelY, m.lw + 2 * PAD * s, 8 * s + 2 * PAD * s,
          alpha)
    text(m.label, m.lx, labelY + PAD * s, s, alpha)
  end

  if toast then
    local fade = math.min(1, toast.t / 0.4) * a
    local w = 0
    for _, line in ipairs(toast.lines) do
      w = math.max(w, textW(line) * s)
    end
    local h = (#toast.lines * 9 - 1) * s
    local tx = midX - w / 2
    local ty = labelY + (8 + 2 * PAD + 5) * s
    plate(tx - PAD * s, ty, w + 2 * PAD * s, h + 2 * PAD * s, fade)
    for i, line in ipairs(toast.lines) do
      -- each line centred in the plate, so a short second line sits under
      -- the middle of a longer first one rather than hanging off its left
      local lw = textW(line) * s
      text(line, midX - lw / 2, ty + PAD * s + (i - 1) * 9 * s, s, fade)
    end
  end
end

return Compass
