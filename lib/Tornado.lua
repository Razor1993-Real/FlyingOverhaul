-- The weather the bird leaves the ground in, and comes back down through.
--
-- Three things happening at once, because one of them alone never looked
-- like wind:
--
--   DUST    thrown off the ground and flung outward, low and wide. This is
--           the part that puts the storm ON the map rather than in front of
--           it -- without something disturbed at ground level the funnel
--           reads as a decal hanging in the air.
--   THE CORE  the funnel itself: fine, fast, near-white, climbing a tight
--           spiral that opens toward the top.
--   LEAVES  torn up and carried round the outside, tumbling as they go.
--           Slower and much bigger than the core motes, and the only part
--           with colour, so the eye has something to follow round.
--
-- Everything is drawn as a STREAK rather than a dot: each mote is projected
-- twice, where it is now and where it was a moment ago, and the line between
-- them is what gets drawn. That single change is most of what makes this
-- read as moving air instead of as falling confetti -- a dot has no
-- direction, and a hundred directionless dots is static however fast they
-- move.
--
-- REAL WORLD COORDINATES, not a screen effect. Every particle has a position
-- in the same space the bird and the terrain are in, and is placed by the
-- voxel mod's own Voxel3D.project -- the function the engine's field effects
-- (the "!" bubble, the fishing rod, vanilla's own fly bird) are anchored
-- with. So you fly AROUND the column, look down INTO it, and the world curve
-- bends it along with the ground it stands on.
--
-- The flat renderer gets the same three layers through a much shorter path
-- (drawFlat): no projection to borrow, so the spiral is laid out in screen
-- space instead. Same shape, same clock, no depth.

local V = ...
local Flight = V.require("Flight")

local Tornado = {}

-- ------- how much of each
Tornado.CORE = 96
Tornado.DUST = 80
Tornado.LEAVES = 42

-- The funnel's own waist, in world pixels: narrow where it touches down,
-- open at the mouth. A cone standing on its point is what makes it look
-- like it is drilling into the ground rather than resting on it.
Tornado.FOOT = 14
Tornado.MOUTH = 72

-- How tall it stands, as a share of the bird's CURRENT altitude -- not of
-- the altitude it is climbing to. A little over one, so the mouth is always
-- just above the bird rather than stopping at its feet.
--
-- Live rather than fixed, because the column has to come down with the bird.
-- Sized to the cruise height it stayed full-length through the descent, and
-- the camera -- which descends too -- ended up looking through the middle of
-- it: leaves that belong eight cells out swept the whole screen as green
-- bars, because they were passing within a few pixels of the lens. Tied to
-- where the bird actually is, the funnel grows out of the ground on the way
-- up and folds back into it on the way down, and nothing is ever between the
-- camera and its own subject.
Tornado.HEIGHT = 1.15

-- The floor keeps it from collapsing to nothing in the first and last few
-- frames, where a zero-height column would put every particle in one spot.
Tornado.MIN_HEIGHT = 40

function Tornado.height()
  return math.max(Tornado.MIN_HEIGHT, Flight.altitude or 0) * Tornado.HEIGHT
end

-- Turns per second at the foot. The top turns slower (the `lean` below),
-- which is what stops the column reading as a rigid barber pole.
Tornado.SPIN = 1.9

-- How far back along its own path a particle is sampled to draw its streak,
-- in seconds -- and PER LAYER, because the layers do not move at the same
-- speed at all.
--
-- One shared value was the first cut and it painted the sky with ribbons:
-- dust travels furthest per second (it is the widest orbit AND it is being
-- flung outward at the same time), so the length that made a core mote into
-- a neat dash swept a dust mote most of the way round the town. A streak is
-- a smear of one thing moving, and it stops reading as one the moment it is
-- longer than the thing is.
Tornado.TRAIL_CORE = 0.030
Tornado.TRAIL_DUST = 0.012
-- Leaves get the SHORTEST trail of the three despite being the slowest
-- layer, because they orbit furthest out: the trail is a distance, and out
-- at the rim even a gentle angular rate covers a lot of ground. Sampled as
-- far back as the core they came out as green bars a couple of cells long.
Tornado.TRAIL_LEAF = 0.008

-- Wind-up and die-away, in seconds. Short: the climb is only a couple.
Tornado.FADE = 0.35

local clock = 0
local strength = 0        -- 0..1, eased in and out

function Tornado.reset()
  clock, strength = 0, 0
end

function Tornado.update(dt)
  dt = dt or 0
  clock = clock + dt
  local phase = Flight.phase
  local target = (phase == "takeoff" or phase == "landing") and 1 or 0
  local step = dt / Tornado.FADE
  if strength < target then
    strength = math.min(target, strength + step)
  elseif strength > target then
    strength = math.max(target, strength - step)
  end
end

function Tornado.visible()
  return strength > 0.01
end

function Tornado._strength() return strength end
function Tornado._clock() return clock end

-- ------- where everything is
--
-- All three layouts are pure and take the time explicitly, which is what
-- lets the draw ask each of them twice -- now, and a trail-length ago -- to
-- get a direction out of a position. It is also what makes them checkable
-- without a renderer.
--
-- Each particle owns a fixed lane of the loop and travels it on a wrap, so
-- the set stays evenly spread instead of bunching wherever the clock is.
-- The golden ratio spaces the lanes around the circle: any simpler spacing
-- leaves visible spokes standing still inside a spinning column.

local PHI = 1.618033988749895
local TAU = math.pi * 2

local function lane(i, n)
  return (i - 1) / math.max(1, n)
end

-- A repeatable 0..1 wobble for a lane. Deterministic on purpose: the layout
-- functions are pure and get asked twice per frame for the same particle, so
-- anything random here would give a streak two unrelated endpoints. Real
-- weather is not evenly spaced, and a ring of identically-spaced motes reads
-- as machinery however fast it turns.
local function scatter(l, seed)
  local v = (l * seed) % 1
  return v
end

-- The funnel. `up` is how far along its height, 0 at the ground.
function Tornado.core(i, n, height, t)
  local l = lane(i, n)
  local up = (l + t * 0.7) % 1
  local radius = Tornado.FOOT + (Tornado.MOUTH - Tornado.FOOT) * up
  local angle = l * TAU * PHI + t * Tornado.SPIN * TAU * (1 - up * 0.45)
  return math.cos(angle) * radius, up * height, math.sin(angle) * radius, up
end

-- Ground dust: a short life, spent low and travelling outward fast. The
-- radius runs well past the funnel's mouth, because what sells a storm on
-- the ground is the stuff leaving it, not the stuff in it.
function Tornado.dust(i, n, height, t)
  local l = lane(i, n)
  local life = (l + t * 1.35) % 1
  local up = life * life * 0.20                  -- lifts late, stays low
  local radius = (Tornado.MOUTH * 0.45 + life * Tornado.MOUTH * 1.9)
                 * (0.72 + 0.55 * scatter(l, 7.31))
  -- turns much more slowly than the funnel: out here the same angular rate
  -- is an enormous ground speed, and dust that outran the eye stopped
  -- looking like dust
  local angle = l * TAU * PHI + t * Tornado.SPIN * TAU * 0.22
  return math.cos(angle) * radius, up * height, math.sin(angle) * radius, life
end

-- Leaves: carried round the outside, rising slowly, bulging away from the
-- column at mid height and drawn back in near the top. `flip` is the
-- tumble -- it runs -1..1 and the draw squashes the leaf by it, which is
-- what a leaf turning over looks like from a distance.
function Tornado.leaf(i, n, height, t)
  local l = lane(i, n)
  local life = (l + t * 0.31) % 1
  local up = 0.06 + life * 0.82
  local radius = (Tornado.MOUTH * 0.85
                  + math.sin(life * math.pi) * Tornado.MOUTH * 0.75)
                 * (0.80 + 0.40 * scatter(l, 4.77))
  local angle = l * TAU * PHI + t * Tornado.SPIN * TAU * 0.5
  local flip = math.sin(t * 6.5 + l * 21)
  return math.cos(angle) * radius, up * height, math.sin(angle) * radius,
         life, flip
end

-- ------- the palette
--
-- Set here rather than at the call sites so the storm can be recoloured in
-- one place. Leaves come in two greens: a single one reads as a swarm of
-- identical chips going round.
Tornado.COLOUR = {
  core  = { 0.96, 0.97, 0.95 },
  dust  = { 0.76, 0.68, 0.52 },
  leafA = { 0.34, 0.60, 0.24 },
  leafB = { 0.52, 0.74, 0.32 },
}

-- ------- drawing it in the world
--
-- `project(wx, wy, wz)` is Voxel3D's, answering in the scene canvas's own
-- pixels; `scale` is how big a world pixel is on that canvas.

local function streak(project, px, pz, ground, ax, ay, az, bx, by, bz,
                      width, r, g, b, alpha)
  local x1, y1 = project(px + ax, ground + ay, pz + az)
  if not x1 then return end
  local x2, y2 = project(px + bx, ground + by, pz + bz)
  love.graphics.setColor(r, g, b, alpha)
  if x2 then
    love.graphics.setLineWidth(width)
    love.graphics.line(x1, y1, x2, y2)
  else
    love.graphics.rectangle("fill", x1 - width / 2, y1 - width / 2,
                            width, width)
  end
end

function Tornado.draw(px, pz, ground, project, scale)
  if not Tornado.visible() then return end
  local height = Tornado.height()
  local s = math.max(1, scale or 1)
  local t = clock
  local backCore = clock - Tornado.TRAIL_CORE
  local backDust = clock - Tornado.TRAIL_DUST
  local backLeaf = clock - Tornado.TRAIL_LEAF
  local C = Tornado.COLOUR

  love.graphics.setLineWidth(1)

  -- dust first: it belongs under everything else, and drawing it first is
  -- how it ends up there without a depth test
  for i = 1, Tornado.DUST do
    local ax, ay, az, life = Tornado.dust(i, Tornado.DUST, height, t)
    local bx, by, bz = Tornado.dust(i, Tornado.DUST, height, backDust)
    -- in fast, out slowly: dust appears the instant it is kicked and then
    -- hangs, which is the shape of the real thing
    local fade = math.min(1, life * 6) * (1 - life) * (1 - life)
    streak(project, px, pz, ground, ax, ay, az, bx, by, bz,
           s * 2.0, C.dust[1], C.dust[2], C.dust[3], strength * fade * 0.9)
  end

  -- the funnel
  for i = 1, Tornado.CORE do
    local ax, ay, az, up = Tornado.core(i, Tornado.CORE, height, t)
    local bx, by, bz = Tornado.core(i, Tornado.CORE, height, backCore)
    -- thins and fades toward the mouth, so the column dissolves into the
    -- air instead of ending on a rim
    local fade = (1 - up * 0.7) * math.min(1, up * 12)
    streak(project, px, pz, ground, ax, ay, az, bx, by, bz,
           s * (2.2 - up * 1.1), C.core[1], C.core[2], C.core[3],
           strength * fade * 0.9)
  end

  -- and the leaves over the top, where they can be seen against it
  for i = 1, Tornado.LEAVES do
    local ax, ay, az, life, flip = Tornado.leaf(i, Tornado.LEAVES, height, t)
    local bx, by, bz = Tornado.leaf(i, Tornado.LEAVES, height, backLeaf)
    local c = (i % 2 == 0) and C.leafA or C.leafB
    -- both ends of the life fade, so leaves arrive and leave rather than
    -- blinking in and out at a seam
    local fade = math.min(1, life * 8) * math.min(1, (1 - life) * 5)
    -- the tumble is in the WIDTH of the smear: a leaf turning over shows
    -- its face and then its edge, which at this distance is a chip that
    -- fattens and thins as it goes round
    local w = s * (0.9 + 1.8 * math.abs(flip))
    streak(project, px, pz, ground, ax, ay, az, bx, by, bz,
           w, c[1], c[2], c[3], strength * fade)
  end

  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- and on the flat world
--
-- With the diorama off there is no projection to borrow, so the same three
-- layers are laid out directly in screen space: horizontal offsets go
-- across, height goes up, and there is no perspective. Same storm on the
-- same clock; it simply does not turn with a camera, because there is none.
function Tornado.drawFlat(cx, cy, scale)
  if not Tornado.visible() then return end
  local height = Tornado.height()
  local s = math.max(1, scale or 1)
  local t = clock
  local backCore = clock - Tornado.TRAIL_CORE
  local backDust = clock - Tornado.TRAIL_DUST
  local backLeaf = clock - Tornado.TRAIL_LEAF
  local C = Tornado.COLOUR

  local function flatStreak(ax, ay, az, bx, by, bz, width, c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.setLineWidth(width)
    love.graphics.line(cx + ax * s, cy - ay * s, cx + bx * s, cy - by * s)
  end

  for i = 1, Tornado.DUST do
    local ax, ay, az, life = Tornado.dust(i, Tornado.DUST, height, t)
    local bx, by, bz = Tornado.dust(i, Tornado.DUST, height, backDust)
    local fade = math.min(1, life * 6) * (1 - life) * (1 - life)
    flatStreak(ax, ay, az, bx, by, bz, s * 2.0, C.dust, strength * fade * 0.9)
  end
  for i = 1, Tornado.CORE do
    local ax, ay, az, up = Tornado.core(i, Tornado.CORE, height, t)
    local bx, by, bz = Tornado.core(i, Tornado.CORE, height, backCore)
    local fade = (1 - up * 0.7) * math.min(1, up * 12)
    flatStreak(ax, ay, az, bx, by, bz, s * (2.2 - up * 1.1), C.core,
               strength * fade * 0.9)
  end
  for i = 1, Tornado.LEAVES do
    local ax, ay, az, life, flip = Tornado.leaf(i, Tornado.LEAVES, height, t)
    local bx, by, bz = Tornado.leaf(i, Tornado.LEAVES, height, backLeaf)
    local c = (i % 2 == 0) and C.leafA or C.leafB
    local fade = math.min(1, life * 8) * math.min(1, (1 - life) * 5)
    local w = s * (0.9 + 1.8 * math.abs(flip))
    flatStreak(ax, ay, az, bx, by, bz, w, c, strength * fade)
  end

  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

return Tornado
