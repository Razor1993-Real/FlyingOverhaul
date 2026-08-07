-- Pure-Lua checks for the parts of this mod that need no engine and no
-- LOVE: the phase machine, the altitude curve, the landing predicate, the
-- boom's geometry and the label lookup the borrowed settings resolve
-- through.
--
--   luajit mods/FlyingOverhaul/tests/fly_logic_test.lua
--
-- Run from the repository root.

package.path = "./?.lua;" .. package.path

local failures, checks = 0, 0

local function ok(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL " .. what)
  end
end

local function near(a, b, eps, what)
  ok(math.abs(a - b) <= (eps or 1e-6), what ..
     (" (got %s, want %s)"):format(tostring(a), tostring(b)))
end

-- ------- the namespace the modules expect

local V = {}
local modules = {}

-- Run from the ENGINE's repository root, not from the mod's folder: the
-- anchor section below measures against data/generated/maps.lua, which is
-- the point of it -- the numbers are the game's own and not mine.
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local chunk = assert(loadfile("mods/FlyingOverhaul/lib/"
                                .. name .. ".lua"))
  modules[name] = chunk(V)
  return modules[name]
end
V.ds = function() return nil end

local Flight = V.require("Flight")

-- ------- the phase machine

Flight.reset()
ok(not Flight.active(), "a fresh state is not flying")
ok(not Flight.steerable(), "a fresh state does not steer")

Flight.beginTakeoff()
ok(Flight.active(), "takeoff is a flight")
ok(not Flight.steerable(), "the climb is not steerable -- the player is cargo")

-- the climb: monotone from the ground to CRUISE, and nothing beyond it
local last = -1
-- a couple of steps past the nominal length: 1/60 has no exact binary
-- representation, so N increments of it can sum a hair under N/60 and the
-- edge would fall on the step after the one the arithmetic predicts
local steps = math.ceil(Flight.CLIMB_TIME * 60) + 2
local becameCruise = false
for _ = 1, steps do
  local left = Flight.update(1 / 60)
  ok(Flight.altitude >= last - 1e-9, "the climb never dips")
  ok(Flight.altitude <= Flight.CRUISE + 1e-9, "the climb never overshoots")
  last = Flight.altitude
  if left == "takeoff" then becameCruise = true end
end
ok(becameCruise, "the climb reports the edge into cruise")
near(Flight.altitude, Flight.CRUISE, 1e-6, "the climb lands on CRUISE")
ok(Flight.steerable(), "cruise steers")

-- cruise holds: no drift while nothing asks it to descend
for _ = 1, 120 do Flight.update(1 / 60) end
near(Flight.altitude, Flight.CRUISE, 1e-6, "cruise holds its altitude")

-- the descent: monotone back to the ground, and it ends the flight
ok(Flight.beginLanding(), "cruise accepts a landing")
ok(not Flight.beginLanding(), "a second landing request is refused")
last = Flight.CRUISE + 1
local ended = false
for _ = 1, math.ceil(Flight.DESCEND_TIME * 60) do
  local left = Flight.update(1 / 60)
  ok(Flight.altitude <= last + 1e-9, "the descent never climbs")
  ok(Flight.altitude >= -1e-9, "the descent never goes underground")
  last = Flight.altitude
  if left == "landing" then ended = true end
end
ok(ended, "the descent reports the edge out")
ok(not Flight.active(), "the flight is over")
near(Flight.altitude, 0, 1e-9, "the bird is on the ground")

-- a landing cannot be started from the ground
Flight.reset()
ok(not Flight.beginLanding(), "there is no landing without a flight")
ok(Flight.update(1 / 60) == nil, "a ticked non-flight reports nothing")

-- the ease itself
near(Flight._ease(0), 0, 1e-12, "ease starts at 0")
near(Flight._ease(1), 1, 1e-12, "ease ends at 1")
near(Flight._ease(0.5), 0.5, 1e-12, "ease is symmetric at the midpoint")
near(Flight._ease(-1), 0, 1e-12, "ease clamps below")
near(Flight._ease(2), 1, 1e-12, "ease clamps above")

-- ------- where the bird may land
--
-- A stand-in map with the three predicates the real one has, so the
-- verdict can be checked without a dataset.

local function mapWith(spec)
  return {
    inBounds = function(_, x, y) return spec.bounds[x .. "," .. y] ~= nil end,
    isWaterCell = function(_, x, y) return spec.water[x .. "," .. y] == true end,
    isWalkableCell = function(_, x, y) return spec.walk[x .. "," .. y] == true end,
  }
end

local m = mapWith{
  bounds = { ["1,1"] = 1, ["2,1"] = 1, ["3,1"] = 1 },
  water  = { ["2,1"] = true },
  walk   = { ["1,1"] = true, ["2,1"] = true },
}

ok(Flight.canLandAt(m, 1, 1), "walkable dry land accepts a landing")
ok(not Flight.canLandAt(m, 2, 1), "water refuses a landing even when walkable")
ok(not Flight.canLandAt(m, 3, 1), "an unwalkable cell refuses a landing")
ok(not Flight.canLandAt(m, 9, 9), "out of bounds refuses a landing")
ok(not Flight.canLandAt(nil, 1, 1), "no map refuses a landing")

-- ------- the boom
--
-- BirdCam pulls in FirstPerson through V.ds() at frame time only, so the
-- module loads without the voxel mod and its geometry can be checked here.

local BirdCam = V.require("BirdCam")
local R, A = 100, math.rad(50)

-- straight down (pitch 0 from vertical) puts the eye directly overhead
local ox, oy, oz = BirdCam.offset(R, 0, 0)
near(ox, 0, 1e-9, "a vertical boom has no east offset")
near(oy, R, 1e-9, "a vertical boom is all height")
near(oz, 0, 1e-9, "a vertical boom has no south offset")

-- level (90 from vertical), facing south: the eye stands NORTH of the bird
ox, oy, oz = BirdCam.offset(R, math.rad(90), 0)
near(oy, 0, 1e-9, "a level boom has no height")
near(oz, -R, 1e-9, "facing south, the eye is north of the bird")

-- facing east (yaw = pi/2): the eye is west of the bird
ox, oy, oz = BirdCam.offset(R, math.rad(90), math.pi / 2)
near(ox, -R, 1e-9, "facing east, the eye is west of the bird")

-- the length is preserved at the rung this mod actually flies at
ox, oy, oz = BirdCam.offset(R, A, 0.7)
near(math.sqrt(ox * ox + oy * oy + oz * oz), R, 1e-9,
     "the boom keeps its length at 50 degrees")
ok(oy > 0, "the 50-degree boom is above the bird")

-- ------- the camera's attitude, and why it is pinned
--
-- The framing broke twice, each time by tying the aim point to the altitude:
-- aiming at the ground tipped the camera from 51 to 72 degrees between the
-- lowest and highest rung and pushed the bird off the top of the screen;
-- aiming a fraction of the way down left it nearly level at the bottom rung,
-- pointing at the horizon, where the mesher can never catch up with what is
-- in shot. Both looked plausible in the other one's screenshot.
--
-- So the two things that actually matter are stated here.

local FOV_HALF = math.rad(65) / 2   -- FirstPerson.FOV, halved

local view, offset = BirdCam.attitude(BirdCam.BOOM, math.rad(50))
ok(math.deg(view) > 45 and math.deg(view) < 70,
   ("the camera looks well down at the world (%.0f degrees below level)")
   :format(math.deg(view)))
ok(offset > 0, "and the bird sits above the view axis, not below it")
ok(offset < FOV_HALF * 0.8,
   ("the bird stays clear of the top edge (%.0f%% of the way out)")
   :format(offset / FOV_HALF * 100))

-- ALTITUDE-INDEPENDENT: attitude takes no altitude at all, which is the
-- point -- the same framing at six cells and at forty-eight.
ok(select(2, BirdCam.attitude(BirdCam.BOOM, math.rad(50)))
   == select(2, BirdCam.attitude(BirdCam.BOOM, math.rad(50))),
   "the framing does not depend on how high the bird is")

-- ------- and the bird stays in shot at EVERY rung, and every look
--
-- The third way this went wrong: a drop tuned for the 50 rung swung the aim
-- 35 degrees below the bird on the 75 rung -- past the edge of the lens, so
-- the subject was simply not in the picture. The drop is solved from the
-- angle now, so this sweeps the whole range rather than checking one value.

for deg = 12, 88, 2 do
  local a = math.rad(deg)
  local axis, off = BirdCam.attitude(BirdCam.BOOM, a)
  ok(off > 0 and off < FOV_HALF * 0.9,
     ("the bird is in shot at a %d-degree boom (%.0f%% out)")
     :format(deg, off / FOV_HALF * 100))
  ok(axis > 0 and axis < math.pi / 2,
     ("and the camera still looks downward at %d degrees"):format(deg))
end

-- the look clamp keeps the boom inside that swept range whatever the player
-- does with the mouse, which is what makes the sweep above a proof
for _, base in ipairs({ math.rad(15), math.rad(35), math.rad(50), math.rad(75) }) do
  for _, pitch in ipairs({ -math.rad(50), -0.4, 0, 0.4, math.rad(70), 99, -99 }) do
    local a = BirdCam.pitchFor(base, pitch)
    ok(a >= BirdCam.PITCH_MIN - 1e-9 and a <= BirdCam.PITCH_MAX + 1e-9,
       "a steered boom stays inside the safe range")
    local _, off = BirdCam.attitude(BirdCam.BOOM, a)
    ok(off > 0 and off < FOV_HALF * 0.9,
       "and the bird is still in shot after steering")
  end
end

-- looking down tips the camera further over the world (a smaller angle from
-- vertical), looking up lifts it toward the horizon
ok(BirdCam.pitchFor(math.rad(50), 0.3) < BirdCam.pitchFor(math.rad(50), 0),
   "looking down tips the camera over the world")
ok(BirdCam.pitchFor(math.rad(50), -0.3) > BirdCam.pitchFor(math.rad(50), 0),
   "and looking up lifts it toward the horizon")

-- ------- resolving a rung by its label
--
-- The voxel mod's ladder has grown a rung in its middle before, so this mod
-- looks its levels up by label. The stub below is the shape
-- Pipelines.levelLabels answers in.

local Settings = V.require("Settings")
-- levelLabels is a plain function on the Pipelines namespace, not a method,
-- so the stub takes the id as its first argument.
local stub = {
  levelLabels = function(id)
    if id == "voxel" then
      return { "OFF", "FULL", "15", "35", "50", "75",
               "1ST (EXPERIMENTAL)", "3RD (EXPERIMENTAL)" }
    end
    return { "OFF", "1", "2", "3" }
  end,
}

ok(Settings._levelForLabel(stub, "voxel", "50") == 4,
   "VOXEL '50' is level 4 on the shipped ladder")
ok(Settings._levelForLabel(stub, "tiltshift", "2") == 2,
   "T-SHIFT '2' is level 2")
ok(Settings._levelForLabel(stub, "voxel", "OFF") == 0, "OFF is level 0")
ok(Settings._levelForLabel(stub, "voxel", "1ST") == 6,
   "a suffixed label matches on its leading token")
ok(Settings._levelForLabel(stub, "voxel", "999") == nil,
   "a rung this build does not have resolves to nil")

-- a ladder with the rung moved: the lookup follows it rather than the index
local moved = {
  levelLabels = function() return { "OFF", "15", "FULL", "35", "50" } end,
}
ok(Settings._levelForLabel(moved, "voxel", "50") == 4,
   "a reordered ladder still resolves '50' by label")

-- ------- the speed
--
-- With no voxel mod to ask (which is this suite), the walk falls back to
-- FreeMove.WALK's own value and the flight is three times it. The live
-- relationship against the real constant is checked in the driver suite,
-- where there is a voxel mod present to disagree.

local BirdMove = V.require("BirdMove")
ok(Flight.MULTIPLIER == 4.5, "the flight is 4.5 times the walk")
near(BirdMove.speed(), 4.5 * Flight.WALK_REFERENCE, 1e-12,
     "the fallback speed is 4.5 walks per step")
near(Flight.CRUISE, 384, 1e-12, "the bird cruises twenty-four cells up by default")

-- ------- the bounds the flight is held inside

local state = {
  map = { def = { width = 10, height = 9 } },      -- 320 x 288 px
  neighbors = {
    { map = { def = { width = 10, height = 9 } }, ox = 320, oy = 0 },
    { map = { def = { width = 10, height = 9 } }, ox = 0, oy = -288 },
  },
}
local x0, y0, x1, y1 = BirdMove.bounds(state)
local s = BirdMove.EDGE_SLACK
near(x0, -s, 1e-9, "the west edge is the current map plus slack")
near(y0, -288 - s, 1e-9, "the north edge reaches the northern neighbour")
near(x1, 640 + s, 1e-9, "the east edge reaches the eastern neighbour")
near(y1, 288 + s, 1e-9, "the south edge is the current map plus slack")
ok(BirdMove.bounds({}) == nil, "a state with no map has no bounds")

-- ------- the compass: bearings
--
-- Everything the ribbon does rests on agreeing with FirstPerson's yaw
-- convention -- yaw 0 faces SOUTH (+Z) and grows toward east, because the
-- look direction there is (sin yaw, cos yaw). Get the sign wrong and the
-- whole compass is mirrored, which is exactly the sort of thing that looks
-- plausible in a screenshot.

local Compass = V.require("Compass")

local function bearing(dx, dz) return Compass.bearingTo(0, 0, dx, dz) end
near(bearing(0, 10), 0, 1e-9, "due south is bearing 0")
near(bearing(10, 0), math.pi / 2, 1e-9, "due east is +pi/2")
near(math.abs(bearing(0, -10)), math.pi, 1e-9, "due north is pi")
near(bearing(-10, 0), -math.pi / 2, 1e-9, "due west is -pi/2")

-- and relative to where the camera looks
near(Compass.relative(0, 0), 0, 1e-9, "facing south, south is dead ahead")
near(Compass.relative(math.pi / 2, math.pi / 2), 0, 1e-9,
     "facing east, east is dead ahead")
near(Compass.relative(0, math.pi / 2), -math.pi / 2, 1e-9,
     "facing east, south is a quarter turn right-to-left")
-- the wrap: a bearing just past the back must not read as almost a full turn
ok(math.abs(Compass.wrapPi(math.pi + 0.1)) < math.pi,
   "a bearing past the back wraps to the short way round")
-- exactly-behind folds to one of the two equivalent half-turns; which one
-- is not a fact worth pinning, only that it IS a half turn
near(math.abs(Compass.wrapPi(3 * math.pi)), math.pi, 1e-9,
     "wrapPi folds full turns")

-- ------- the compass: one pip per sector

local function town(id, x, z, visited)
  return { id = id, name = id, x = x, z = z, visited = visited ~= false }
end

-- two towns almost due south, one much further away: only the near one
-- survives, because they share a sector
local near1 = town("NEAR", 0, 500)
local far1 = town("FAR", 10, 4000)
local picked = Compass.select({ near1, far1 }, 0, 0, 0)
ok(#picked == 1, "two towns in one sector yield one marker")
ok(picked[1] and picked[1].town.id == "NEAR",
   "and it is the nearer of the two")

-- pull the near one out of the way and the far one takes the sector: this is
-- the "next town fades in as you pass" behaviour, decided per frame
picked = Compass.select({ far1 }, 0, 0, 0)
ok(#picked == 1 and picked[1].town.id == "FAR",
   "with the near one gone, the one behind it appears")

-- towns in DIFFERENT sectors both survive
local east = town("EAST", 2000, 0)
picked = Compass.select({ near1, east }, 0, 0, math.pi / 4)
ok(#picked == 2, "towns in different sectors both show")

-- a town behind the camera is not on the ribbon at all
picked = Compass.select({ near1 }, 0, 0, math.pi)
ok(#picked == 0, "a town behind you is off the arc")

-- and one you are standing on drops out, freeing its sector
picked = Compass.select({ town("HERE", 0, Compass.ARRIVE - 10) }, 0, 0, 0)
ok(#picked == 0, "a town you have reached leaves the ribbon")

-- due east is a quarter turn, outside the arc when facing south
picked = Compass.select({ east }, 0, 0, 0)
ok(#picked == 0, "a town a quarter turn away is off the arc")

-- the one nearest the nose is marked centred, and it is first. Both towns
-- are inside the arc here: SE at 45 degrees, and NEAR straight ahead.
local southeast = town("SOUTHEAST", 1000, 1000)
picked = Compass.select({ southeast, near1 }, 0, 0, 0)
ok(#picked == 2, "both towns are on the arc")
ok(picked[1] and picked[1].town.id == "NEAR" and picked[1].centred,
   "the town nearest the heading is the centred one")
ok(picked[2] and not picked[2].centred, "and only that one is centred")

-- fade is full at the nose and gone at the rim
near(Compass.select({ near1 }, 0, 0, 0)[1].fade, 1, 1e-9,
     "a marker dead ahead is at full strength")
local rim = Compass.select({ town("RIM", 0, 1000) }, 0, 0,
                           -Compass.SPAN * 0.98)
ok(rim[1] and rim[1].fade < 0.2, "a marker at the rim is nearly faded out")

-- ------- the compass: labels never overlap

local function fixedWidth(n) return function() return n end end
local function xAt(rel) return 200 + rel * 100 end

-- three markers crowded together: only the first can have its plate
local crowd = {
  { rel = 0, dist = 100, centred = true, town = town("A", 0, 0) },
  { rel = 0.05, dist = 200, town = town("B", 0, 0) },
  { rel = 0.10, dist = 300, town = town("C", 0, 0) },
}
local labelled = Compass.assignLabels(crowd, fixedWidth(120), xAt, 0, 400)
ok(#labelled == 1, "crowded markers yield one label, not a pile")
ok(labelled[1].town.id == "A", "and it is the centred one")

-- spread them out and they all fit
local spread = {
  { rel = -0.9, dist = 100, centred = true, town = town("A", 0, 0) },
  { rel = 0, dist = 200, town = town("B", 0, 0) },
  { rel = 0.9, dist = 300, town = town("C", 0, 0) },
}
labelled = Compass.assignLabels(spread, fixedWidth(20), xAt, 0, 400)
ok(#labelled == 3, "well-separated markers all get labels")
-- and none of the placed spans intersect
for i = 1, #labelled do
  for j = i + 1, #labelled do
    local a, b = labelled[i], labelled[j]
    ok(a.lx + a.lw <= b.lx or b.lx + b.lw <= a.lx,
       "placed labels never intersect")
  end
end

-- a label is pulled back inside the band rather than hanging off the edge
local edge = { { rel = 1, dist = 100, centred = true, town = town("A", 0, 0) } }
labelled = Compass.assignLabels(edge, fixedWidth(80), xAt, 0, 400)
ok(labelled[1].lx >= 0 and labelled[1].lx + labelled[1].lw <= 400,
   "a label at the rim stays inside the band")

-- ------- the compass: what a plate says

-- Names come through WHOLE. The ribbon used to trim " CITY" and " TOWN" off
-- to buy room, using a hardcoded list of English suffixes -- which is a
-- translation mod's names mangled. Nothing in this mod knows what a place is
-- called any more, so the check is that whatever went in comes out.
local visitedNear = { rel = 0, dist = 320, centred = true,
                      town = town("PEWTER CITY", 0, 0) }
local centred = Compass.labelFor(visitedNear)
ok(centred[1] == "PEWTER CITY 20",
   "a visited town centred shows its whole name and its distance")
ok(centred[2] == "PEWTER CITY",
   "with the name alone as the fallback for a narrow band")
ok(Compass.labelFor({ rel = 0.5, dist = 320,
                      town = town("PEWTER CITY", 0, 0) })[1] == "PEWTER CITY",
   "off-centre it is the whole name, untrimmed")

-- a name in any shape at all survives intact -- there is no rule about
-- what a place name looks like left in this mod
for _, name in ipairs({ "PALLET TOWN", "CINNABAR ISLAND", "INDIGO PLATEAU",
                        "ALABASTIA", "BOURG PALETTE", "\230\183\161\232\143\156" }) do
  ok(Compass.labelFor({ rel = 0.5, dist = 0, town = town(name, 0, 0) })[1]
     == name, ("%q comes through untouched"):format(name))
end

local unseen = town("CERULEAN CITY", 0, 0, false)
ok(Compass.labelFor({ rel = 0, dist = 900, centred = true, town = unseen })[1]
   == "? NOT EXPLORED",
   "an unvisited town centred says so instead of naming itself")
ok(#Compass.labelFor({ rel = 0.5, dist = 900, town = unseen }) == 0,
   "and off-centre it is a bare pip, not a row of question marks")

-- ------- a narrow band gives way, the name does not
--
-- The rule that replaced the trimming: offer the fullest label, and let the
-- LAYOUT fall back when it will not fit. Measured in characters here, which
-- is what the real widthOf reduces to for a fixed-width font.

local function chars(n) return function(s) return #s * n end end
local function atX(rel) return 500 + rel * 100 end

local wide = Compass.assignLabels(
  { { rel = 0, dist = 320, centred = true, town = town("PEWTER CITY", 0, 0) } },
  chars(1), atX, 0, 1000)
ok(wide[1] and wide[1].label == "PEWTER CITY 20",
   "a band with room shows the name and the distance")

local narrow = Compass.assignLabels(
  { { rel = 0, dist = 320, centred = true, town = town("PEWTER CITY", 0, 0) } },
  chars(1), atX, 0, 13)
ok(narrow[1] and narrow[1].label == "PEWTER CITY",
   "a band too narrow for both drops the distance, not the name")

local tiny = Compass.assignLabels(
  { { rel = 0, dist = 320, centred = true, town = town("PEWTER CITY", 0, 0) } },
  chars(1), atX, 0, 5)
ok(#tiny == 0, "a band too narrow for the name leaves a bare pip")

-- ------- the atlas: which map is under a point

local Atlas = V.require("Atlas")
local layout = {
  HOME  = { id = "HOME",  ox = 0,   oy = 0,   w = 320, h = 288 },
  NORTH = { id = "NORTH", ox = 0,   oy = -576, w = 320, h = 576 },
  EAST  = { id = "EAST",  ox = 320, oy = 0,   w = 320, h = 288 },
}
ok(Atlas.mapAt(layout, 10, 10) == "HOME", "a point inside a map finds it")
ok(Atlas.mapAt(layout, 330, 10) == "EAST", "and the map east of it")
ok(Atlas.mapAt(layout, 10, -10) == "NORTH", "and the map north of it")
-- half-open rects: a point on the seam belongs to exactly one side
ok(Atlas.mapAt(layout, 320, 10) == "EAST",
   "a point on a seam belongs to the map it enters, not to both")
ok(Atlas.mapAt(layout, 0, 0) == "HOME", "and a corner to the map it opens")
-- the void: nothing is there, and nothing must be claimed
ok(Atlas.mapAt(layout, 400, -100) == nil, "a point in the void answers nil")
ok(Atlas.mapAt(layout, -50, 10) == nil, "and so does one off the west edge")
ok(Atlas.mapAt(nil, 0, 0) == nil, "no layout answers nil rather than throwing")

-- ------- the atlas: deriving where the player has been
--
-- A chain TOWN_A - route - TOWN_B - route - TOWN_C. Having been to A and B,
-- everything up to B is walkable ground; C is a town never visited, so it is
-- a wall and the route beyond it stays shut.

local function conn(to) return { map = to } end
local graph = {
  TOWN_A = { index = 0, connections = { north = conn("ROUTE_1") } },
  ROUTE_1 = { index = 20, connections = { south = conn("TOWN_A"),
                                          north = conn("TOWN_B") } },
  TOWN_B = { index = 1, connections = { south = conn("ROUTE_1"),
                                        north = conn("ROUTE_2") } },
  ROUTE_2 = { index = 21, connections = { south = conn("TOWN_B"),
                                          north = conn("TOWN_C") } },
  TOWN_C = { index = 2, connections = { south = conn("ROUTE_2"),
                                        north = conn("ROUTE_3") } },
  ROUTE_3 = { index = 22, connections = { south = conn("TOWN_C") } },
}
local isTown = function(def) return def.index ~= nil and def.index < 11 end

local derived = Atlas.deriveExplored(graph, { TOWN_A = true, TOWN_B = true },
                                     isTown)
ok(derived.TOWN_A and derived.TOWN_B, "the visited towns are explored")
ok(derived.ROUTE_1, "the route between two visited towns is explored")
ok(derived.ROUTE_2,
   "and the route leaving the last visited town, which they could walk")
ok(not derived.TOWN_C, "a town never visited is NOT explored")
ok(not derived.ROUTE_3,
   "and nothing beyond it is -- the unvisited town walls the walk off")

-- with nothing visited, nothing is derived
derived = Atlas.deriveExplored(graph, {}, isTown)
ok(next(derived) == nil, "no visited towns derives an empty region")

-- and a visited town at the far end opens its own side
derived = Atlas.deriveExplored(graph, { TOWN_C = true }, isTown)
ok(derived.ROUTE_3 and derived.ROUTE_2,
   "a visited town opens the routes on both sides of it")
ok(not derived.TOWN_A, "but not the town beyond those")

-- ------- the bird shows all four of its frames
--
-- This is the whole point of the heading work, so it is checked against the
-- geometry rather than against a screenshot.
--
-- SPRITE_BIRD is a full six-frame walker -- front, back, side, and the side
-- mirrored -- and exactly one of those frames was ever drawn, because the
-- body's heading was pinned to the camera's yaw while the camera itself was
-- boomed along that same yaw. The bird sat at a constant 180 degrees from
-- the lens forever.
--
-- What the renderer actually asks (FirstPerson.frameFor) is where the body's
-- bearing sits relative to the direction of the EYE, quantised into four.
-- The flight camera stands opposite the look, so the eye lies at yaw + pi
-- from the bird. Reproduced here, so the claim "all four are reachable" is
-- arithmetic and not an impression.

local FACING_ORDER = { "down", "right", "up", "left" }

local function frameSeenBy(bodyYaw, cameraYaw)
  local toEye = Compass.wrapPi(cameraYaw + math.pi)
  local rel = Compass.wrapPi(bodyYaw - toEye)
  local idx = math.floor((rel + math.pi / 4) / (math.pi / 2)) % 4
  return FACING_ORDER[idx + 1]
end

for _, cameraYaw in ipairs({ 0, math.pi / 2, math.pi, -math.pi / 2, 1.1, -2.7 }) do
  -- what BirdMove hands over as the body's bearing in each case: the
  -- direction of TRAVEL, which is the camera-relative move rotated to world
  local forward = cameraYaw
  local back = Compass.wrapPi(cameraYaw + math.pi)
  local strafeR = Compass.wrapPi(cameraYaw + math.pi / 2)
  local strafeL = Compass.wrapPi(cameraYaw - math.pi / 2)

  local seen = {
    forward = frameSeenBy(forward, cameraYaw),
    back = frameSeenBy(back, cameraYaw),
    right = frameSeenBy(strafeR, cameraYaw),
    left = frameSeenBy(strafeL, cameraYaw),
  }
  ok(seen.forward == "up",
     "flying away shows the bird's back whatever way the camera faces")
  ok(seen.back == "down", "flying at the camera shows its front")
  ok(seen.right ~= seen.left, "the two strafes show opposite sides")
  local distinct = {}
  for _, f in pairs(seen) do distinct[f] = true end
  local n = 0
  for _ in pairs(distinct) do n = n + 1 end
  ok(n == 4, ("all four frames are reachable at camera yaw %.2f"):format(cameraYaw))
end

-- and the quantisation this mod applies for the flat renderer agrees with
-- the engine's own four directions
ok(BirdMove.facingOf(0) == "down", "bearing 0 (south) is the down frame")
ok(BirdMove.facingOf(math.pi / 2) == "right", "east is the right frame")
ok(BirdMove.facingOf(math.pi) == "up", "north is the up frame")
ok(BirdMove.facingOf(-math.pi / 2) == "left", "west is the left frame")
-- the boundaries fall on the diagonals, not on the axes
ok(BirdMove.facingOf(math.pi / 4 - 0.01) == "down", "just short of SE is down")
ok(BirdMove.facingOf(math.pi / 4 + 0.01) == "right", "just past SE is right")

-- ------- the turn eases, and takes the short way
--
-- Without it the frame flickers whenever a turn sits on a diagonal, which is
-- the one place the quantisation above has an edge.

ok(BirdMove.turnToward(nil, 1.2) == 1.2,
   "the first heading is adopted outright, not eased into from nowhere")

-- monotone approach, no overshoot
local from, to = 0, 1.0
local last = from
for _ = 1, 60 do
  local nextB = BirdMove.turnToward(last, to)
  ok(nextB > last - 1e-9 and nextB <= to + 1e-9, "the turn approaches without overshooting")
  last = nextB
end
ok(math.abs(last - to) < 0.01, "and gets there")

-- the short way across the +/-pi seam: from just west of north to just east
-- of it must cross north, never swing the long way through south
local nearNorth = math.pi - 0.1
local justPast = -math.pi + 0.1
local stepped = BirdMove.turnToward(nearNorth, justPast)
ok(math.abs(Compass.wrapPi(stepped - nearNorth)) < 0.1,
   "a turn across the north seam moves by a small angle, not most of a circle")
ok(stepped > 0, "and it keeps going the way it was pointing rather than flipping")

-- ------- the settings ladder

local Setting = V.require("Setting")
local Options = V.require("Options")

local ladder = Setting.new("t", "TEST", { "a", "b", "c" }, { "A", "B", "C" }, "b")
ok(ladder:get() == "b", "an unread setting reads its default")
ok(ladder:label_() == "B", "and shows the matching label")
ladder:sync("c")
ok(ladder:get() == "c", "sync adopts a value")
ladder:sync("nonsense")
ok(ladder:get() == "b", "an unrecognised stored value falls back to the default")

-- cycling wraps
ladder:sync("a")
ladder.index = ladder:indexOf("a")
local seenValues = {}
for _ = 1, 3 do
  ladder.index = (ladder.index % 3) + 1
  seenValues[ladder:get()] = true
end
ok(seenValues.a and seenValues.b and seenValues.c, "cycling reaches every rung")

-- the schema the manager renders
local schema = ladder:schema()
ok(schema.type == "choice" and schema.key == "t", "the schema is a choice row")
ok(#schema.choices == 3, "with one choice per rung")
ok(schema.choices[1][1] == "A" and schema.choices[1][2] == "a",
   "each choice is a label/value pair")
ok(schema.default == "b", "and carries the default")

-- a default that is not on the ladder is a mistake worth refusing loudly
ok(not pcall(Setting.new, "x", "X", { 1, 2 }, { "1", "2" }, 9),
   "a default off the ladder is rejected")
ok(not pcall(Setting.new, "x", "X", { 1, 2 }, { "1" }, 1),
   "a ladder with a missing label is rejected")

-- the shipped defaults ARE the behaviour this mod had before the menu
ok(Options.height:get() == 384, "FLY HEIGHT defaults to 24 cells")
ok(Options.speed:get() == 4.5, "FLY SPEED defaults to 4.5x")
ok(Options.voxel:get() == "50", "FLY VOXEL defaults to the 50 rung")
ok(Options.tshift:get() == "2", "FLY T-SHIFT defaults to 2")
ok(Options.curve:get() == 0, "FLY V-CURVE defaults to OFF -- flat")
ok(#Options.rows() == 7, "seven rows reach the OPTIONS menu")
ok(#Options.schema() == 7, "and seven reach the mod manager")

-- KEEP is a sentinel, distinct from every real rung
ok(Options.wants(Options.voxel) == "50", "a chosen rung is what the flight wants")
Options.voxel:sync(Options.KEEP)
ok(Options.wants(Options.voxel) == nil, "KEEP means the flight wants nothing")
ok(Options.KEEP ~= "KEEP" and Options.KEEP ~= 0 and Options.KEEP ~= false,
   "and it cannot collide with a real value")
Options.voxel:sync("50")

-- OFF is a real choice and must not read as KEEP
Options.curve:sync(0)
ok(Options.wants(Options.curve) == 0,
   "V-CURVE OFF is a value the flight applies, not an absence")
Options.curve:sync(3)
ok(Options.wants(Options.curve) == 3, "and a bend is one too")
Options.curve:sync(0)

-- ------- the storm
--
-- All three layers are pure position functions, which is the only reason
-- any of this is checkable without a renderer -- and it is also what lets
-- the draw sample each one twice to get a direction out of it.

local Tornado = V.require("Tornado")
local H = 400

-- the column is the height of the bird, not of where it is heading: sized to
-- the cruise altitude it stayed full-length through the descent and the
-- camera came down through the middle of it
Flight.reset()
Flight.CRUISE = 384
Flight.altitude = 0
near(Tornado.height(), Tornado.MIN_HEIGHT * Tornado.HEIGHT, 1e-9,
     "on the ground the funnel is only its floor height")
Flight.altitude = 200
near(Tornado.height(), 200 * Tornado.HEIGHT, 1e-9,
     "mid-climb it stands as tall as the bird is high")
Flight.altitude = 384
near(Tornado.height(), 384 * Tornado.HEIGHT, 1e-9, "and grows with it")
ok(Tornado.height() > 0, "it is never zero-height, whatever the altitude")
Flight.altitude = 0
Flight.reset()

-- the funnel is a cone standing on its point
do
  local rMin, rMax = math.huge, 0
  local lowR, highR
  for i = 1, Tornado.CORE do
    local dx, y, dz, up = Tornado.core(i, Tornado.CORE, H, 0.4)
    local r = math.sqrt(dx * dx + dz * dz)
    rMin, rMax = math.min(rMin, r), math.max(rMax, r)
    ok(y >= -1e-9 and y <= H + 1e-9, "a core mote stays inside the column")
    ok(up >= 0 and up <= 1, "and its height runs 0..1")
    if up < 0.1 then lowR = r end
    if up > 0.9 then highR = r end
  end
  ok(rMin >= Tornado.FOOT - 1e-6, "nothing is narrower than the foot")
  ok(rMax <= Tornado.MOUTH + 1e-6, "and nothing wider than the mouth")
  if lowR and highR then
    ok(lowR < highR, "the funnel opens out toward the top")
  end
end

-- dust stays LOW and goes WIDE -- that is the whole difference between it
-- and the core, and it is what puts the storm on the ground
do
  local maxUp, maxR = 0, 0
  for i = 1, Tornado.DUST do
    local dx, y, dz = Tornado.dust(i, Tornado.DUST, H, 0.6)
    maxUp = math.max(maxUp, y / H)
    maxR = math.max(maxR, math.sqrt(dx * dx + dz * dz))
  end
  ok(maxUp < 0.25, ("dust hugs the ground (highest %.2f of the column)")
     :format(maxUp))
  ok(maxR > Tornado.MOUTH * 1.5,
     ("and is flung well past the funnel (%.0f vs mouth %d)")
     :format(maxR, Tornado.MOUTH))
end

-- leaves orbit OUTSIDE the funnel and climb most of it
do
  local minR, maxUp = math.huge, 0
  for i = 1, Tornado.LEAVES do
    local dx, y, dz, life, flip = Tornado.leaf(i, Tornado.LEAVES, H, 0.9)
    minR = math.min(minR, math.sqrt(dx * dx + dz * dz))
    maxUp = math.max(maxUp, y / H)
    ok(life >= 0 and life <= 1, "a leaf's life runs 0..1")
    ok(flip >= -1 and flip <= 1, "and its tumble runs -1..1")
  end
  ok(minR > Tornado.MOUTH * 0.5,
     "leaves stay outside the funnel rather than inside it")
  ok(maxUp > 0.5, "and are carried well up it")
end

-- every layer MOVES: sampled a moment apart, each particle has gone
-- somewhere. This is what the streak drawing depends on -- two identical
-- samples would draw a zero-length line, i.e. nothing at all.
do
  local dt = Tornado.TRAIL_CORE
  local layers = {
    { "core", Tornado.core, Tornado.CORE },
    { "dust", Tornado.dust, Tornado.DUST },
    { "leaf", Tornado.leaf, Tornado.LEAVES },
  }
  for _, entry in ipairs(layers) do
    local name, fn, n = entry[1], entry[2], entry[3]
    local moved = 0
    for i = 1, n do
      local ax, ay, az = fn(i, n, H, 1.0)
      local bx, by, bz = fn(i, n, H, 1.0 - dt)
      local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
      if d > 1e-6 then moved = moved + 1 end
    end
    ok(moved >= n - 1,
       ("%s particles have somewhere to streak from (%d of %d)")
       :format(name, moved, n))
  end
end

-- the wind-up: nothing before a flight, full during one, gone after
Flight.reset()
Tornado.reset()
ok(not Tornado.visible(), "no storm with no flight")
Tornado.update(1 / 60)
ok(not Tornado.visible(), "and none from ticking on the ground")

Flight.beginTakeoff()
for _ = 1, math.ceil(Tornado.FADE * 60) + 4 do Tornado.update(1 / 60) end
ok(Tornado.visible(), "it winds up on the climb")
near(Tornado._strength(), 1, 1e-6, "to full strength")

-- through the cruise it dies away again
Flight.phase = "cruise"
for _ = 1, math.ceil(Tornado.FADE * 60) + 4 do Tornado.update(1 / 60) end
ok(not Tornado.visible(), "and dies away for the cruise")

Flight.phase = "landing"
for _ = 1, math.ceil(Tornado.FADE * 60) + 4 do Tornado.update(1 / 60) end
ok(Tornado.visible(), "then comes back for the descent")
Flight.reset()
Tornado.reset()

-- ------- the Kanto underlay
--
-- The whole reason this warps rather than scales: the town map is a stylised
-- diagram, and a single scale and offset leaves Fuchsia thirteen cells out
-- and Indigo Plateau twenty-nine. Measured against the REAL data below, so
-- the numbers are the game's and not mine.

local Underlay = V.require("Underlay")

-- the eleven towns, as (sheet pixel) -> (world position). Taken from the
-- shipped dataset rather than invented, so this breaks if the map data or
-- the connection walk ever move.
local maps = assert(loadfile("data/generated/maps.lua"))()
local fieldData = assert(loadfile("data/generated/field.lua"))()

local function worldLayout(rootId)
  local out, placed = {}, { [rootId] = true }
  local root = maps[rootId]
  out[rootId] = { ox = 0, oy = 0, w = root.width * 32, h = root.height * 32 }
  local q, qi = { { def = root, ox = 0, oy = 0 } }, 1
  while q[qi] do
    local cur = q[qi]; qi = qi + 1
    for dir, conn in pairs(cur.def.connections or {}) do
      local d = maps[conn.map]
      if d and not placed[conn.map] then
        placed[conn.map] = true
        local ox, oy
        if dir == "north" then ox, oy = conn.offset * 32, -d.height * 32
        elseif dir == "south" then ox, oy = conn.offset * 32, cur.def.height * 32
        elseif dir == "west" then ox, oy = -d.width * 32, conn.offset * 32
        else ox, oy = cur.def.width * 32, conn.offset * 32 end
        ox, oy = cur.ox + ox, cur.oy + oy
        out[conn.map] = { ox = ox, oy = oy, w = d.width * 32, h = d.height * 32 }
        q[#q + 1] = { def = d, ox = ox, oy = oy }
      end
    end
  end
  return out
end

local layout = worldLayout("PALLET_TOWN")
local locs = fieldData.townMap.locations
local townIds = { "PALLET_TOWN", "VIRIDIAN_CITY", "PEWTER_CITY", "CERULEAN_CITY",
                  "LAVENDER_TOWN", "VERMILION_CITY", "CELADON_CITY",
                  "FUCHSIA_CITY", "CINNABAR_ISLAND", "SAFFRON_CITY",
                  "INDIGO_PLATEAU" }
local townList = {}
for _, id in ipairs(townIds) do
  local r = layout[id]
  townList[#townList + 1] = { id = id, x = r.ox + r.w / 2, z = r.oy + r.h / 2 }
end

local anchors = Underlay.anchors(townList, locs)
ok(#anchors == 11, "every fly town becomes an anchor")
ok(anchors[1].tx == locs.PALLET_TOWN.x * 8 + Underlay.MARK_X,
   "an anchor sits on the marker's own pixel, grid offset included")

-- the plain fit, and how badly it misses -- the reason the warp exists
local ax, bx, az, bz = Underlay.fit(anchors)
local worst, worstId = 0, nil
for _, a in ipairs(anchors) do
  local ex = math.abs(ax * a.tx + bx - a.wx)
  local ez = math.abs(az * a.ty + bz - a.wz)
  local e = math.max(ex, ez)
  if e > worst then worst, worstId = e, a.id end
end
print(("[underlay] plain fit worst miss: %.0f px (%.1f cells) at %s")
      :format(worst, worst / 16, tostring(worstId)))
ok(worst > 100,
   "a plain scale really does miss badly -- which is why the warp is here")

-- ------- THE ANCHOR CONDITION
--
-- Every town must land exactly where it really is. This is the promise the
-- whole module is for; if it fails, the sheet is decoration rather than a map.
local res = Underlay.residuals(anchors, ax, bx, az, bz)
local worstWarp = 0
for _, a in ipairs(anchors) do
  local wx, wz = Underlay.warp(res, ax, bx, az, bz, a.tx, a.ty)
  local e = math.max(math.abs(wx - a.wx), math.abs(wz - a.wz))
  worstWarp = math.max(worstWarp, e)
  ok(e < 1, ("%s lands on its real position (%.2f px out)"):format(a.id, e))
end
print(("[underlay] warped worst miss: %.3f px"):format(worstWarp))

-- and a point far from every anchor falls back to the plain fit rather than
-- running off somewhere of its own
do
  local fx, fz = Underlay.warp(res, ax, bx, az, bz, -4000, -4000)
  local px, pz = ax * -4000 + bx, az * -4000 + bz
  local drift = math.max(math.abs(fx - px), math.abs(fz - pz))
  ok(drift < 3000, "far outside the anchors the warp settles toward the fit")
end

-- the weights themselves
do
  local one = { { tx = 0, ty = 0, rx = 10, rz = -20 } }
  local wx, wz = Underlay.warp(one, 1, 0, 1, 0, 0, 0)
  near(wx, 10, 1e-9, "a lone anchor contributes its whole correction")
  near(wz, -20, 1e-9, "on both axes")
  -- exactly on an anchor, where the naive weight divides by zero
  local two = { { tx = 0, ty = 0, rx = 100, rz = 0 },
                { tx = 50, ty = 0, rx = -100, rz = 0 } }
  local ex = Underlay.warp(two, 1, 0, 1, 0, 0, 0)
  near(ex, 100, 1e-9, "standing on an anchor takes its correction, not a mix")
  ok(ex == ex, "and does not divide by zero into a NaN")
  -- halfway between two equal-and-opposite corrections they cancel
  local mid = Underlay.warp(two, 1, 0, 1, 0, 25, 0)
  near(mid, 25, 1e-6, "midway between two opposite anchors they cancel out")
end

-- ------- no folding
--
-- A warped sheet that crosses over itself shows the picture mirrored, which
-- reads as a rendering fault rather than as a map. Swept over the real
-- anchors at the mesh's own resolution.
do
  local n = Underlay.GRID
  local folds = 0
  local prevRow = nil
  for gy = 0, n do
    local ty = gy / n * Underlay.TEX_H
    local row, lastX = {}, nil
    for gx = 0, n do
      local tx = gx / n * Underlay.TEX_W
      local wx, wz = Underlay.warp(res, ax, bx, az, bz, tx, ty)
      if lastX and wx <= lastX then folds = folds + 1 end
      lastX = wx
      row[gx] = wz
    end
    if prevRow then
      for gx = 0, n do
        if row[gx] <= prevRow[gx] then folds = folds + 1 end
      end
    end
    prevRow = row
  end
  ok(folds == 0, ("the warped sheet never folds over itself (%d folds)")
     :format(folds))
end

-- ------- the sheet itself
do
  local bg = fieldData.townMap.background
  ok(#bg.map == 360, "the town map is 20x18 tiles")
  local maxTile = 0
  for i = 1, #bg.map do maxTile = math.max(maxTile, bg.map[i]) end
  local perSheet = (bg.tiles.width / 8) * (bg.tiles.height / 8)
  ok(maxTile < perSheet,
     ("every tile index is inside the sheet (max %d of %d)")
     :format(maxTile, perSheet))
  ok(#Underlay.PALETTE == 4, "the recolour has one colour per Game Boy shade")
  ok(Underlay.DEPTH < 0, "the sheet hangs below the ground it must not cover")

  -- the four shades, read off the red channel the way the sheet stores them
  for i, r in ipairs({ 0, 1 / 3, 2 / 3, 1 }) do
    ok(Underlay.shadeIndex(r) == i,
       ("shade %d reads back as itself"):format(i))
  end
  ok(Underlay.shadeIndex(-0.4) == 1,
     "and anything below the darkest is darkest")
  ok(Underlay.shadeIndex(1.4) == 4,
     "anything above the lightest is lightest")

  -- foam vs. route line. Same light pixel, twice, differing only in what
  -- stands around it -- which is the whole of the rule.
  do
    local w, h = 3, 3
    local function grid(ring)
      local g = {}
      for i = 1, 9 do g[i] = ring end
      g[5] = 4                                  -- the light pixel, centre
      return g
    end
    ok(Underlay.isFoam(grid(3), w, h, 1, 1) == true,
       "a light pixel surrounded by water is foam")
    ok(Underlay.isFoam(grid(2), w, h, 1, 1) == false,
       "the same pixel surrounded by land is a route and is left alone")
    ok(Underlay.isFoam(grid(4), w, h, 1, 1) == false,
       "light on light decides nothing, so nothing changes")
    local sea = grid(3)
    sea[5] = 3
    ok(Underlay.isFoam(sea, w, h, 1, 1) == false,
       "and open water is never foam, whatever surrounds it")
  end

  -- ------- the sheet's own legend comes off
  --
  -- Two glyphs on a 16x16 field of land: a city box filling the tile at
  -- (0,0), and a single dot inside the tile at (8,8). The rule is meant to
  -- treat them differently, and that difference is the whole point of it.
  do
    local w, h = 16, 16
    local s = {}
    for i = 1, w * h do s[i] = 2 end
    for i = 0, 7 do                       -- the box: black on the tile's rim
      s[0 * w + i + 1] = 1
      s[7 * w + i + 1] = 1
      s[i * w + 0 + 1] = 1
      s[i * w + 7 + 1] = 1
    end
    s[2 * w + 2 + 1] = 4                  -- and something pale inside it
    s[11 * w + 11 + 1] = 1                -- the dot, well inside its own tile
    s[11 * w + 12 + 1] = 4                -- with a pale pixel beside it

    local mask = Underlay.glyphMask(s, w, h)
    local boxed, dotted = 0, 0
    for k in pairs(mask) do
      local x, y = (k - 1) % w, math.floor((k - 1) / w)
      if x < 8 and y < 8 then boxed = boxed + 1 else dotted = dotted + 1 end
    end
    ok(boxed == 64, ("a box takes its whole tile (got %d of 64)"):format(boxed))
    ok(dotted == 1, ("a dot takes only itself (got %d)"):format(dotted))
    ok(mask[2 * w + 2 + 1] == true,
       "including the pale middle a box leaves behind when only the black goes")
    ok(mask[11 * w + 12 + 1] == nil,
       "and the dot's tile keeps everything else it was drawing")

    Underlay.dissolve(s, w, h, mask)
    local black, unresolved = 0, 0
    for i = 1, w * h do
      if s[i] == 1 then black = black + 1 end
      if s[i] == 0 then unresolved = unresolved + 1 end
    end
    ok(black == 0, "after the dissolve not one marker pixel is left")
    ok(unresolved == 0, "and every hole was filled by what stood around it")
    ok(s[2 * w + 2 + 1] == 2, "the box's tile came back as the land it sat on")
  end

  -- ------- and Vermilion gets its bay
  do
    local w, h = 16, 16
    local s = {}
    for i = 1, w * h do s[i] = 2 end
    for j = 0, 7 do                       -- one tile of dithered sea to copy
      for i = 0, 7 do
        s[j * w + i + 1] = ((i + j) % 2 == 0) and 3 or 4
      end
    end
    local rx, ry = Underlay.seaTile(s, w, h)
    ok(rx == 0 and ry == 0, "the sea tile is found where the sea is")

    Underlay.carve(s, w, h, 8, 8, 15, 15, rx, ry)
    local land = 0
    for j = 8, 15 do
      for i = 8, 15 do
        if s[j * w + i + 1] == 2 then land = land + 1 end
      end
    end
    ok(land == 0, "a carved bay leaves no land behind")
    -- and it carries the dither's phase, so the seam does not show
    ok(s[8 * w + 8 + 1] == s[0 * w + 0 + 1],
       "the bay continues the sea's own pattern rather than restarting it")

    local flat = {}
    for i = 1, w * h do flat[i] = 2 end
    ok(Underlay.seaTile(flat, w, h) == nil, "no sea, no reference tile")
    ok(Underlay.carve(flat, w, h, 0, 0, 3, 3, nil, nil)[1] == 2,
       "and without one nothing is carved")
  end

  -- the bay is stated against Vermilion's marker, and must stay on the sheet
  do
    ok(#Underlay.BAYS >= 1, "at least one bay is corrected")
    for _, bay in ipairs(Underlay.BAYS) do
      local loc = locs[bay.town]
      ok(loc ~= nil, bay.town .. " is a place the town map knows")
      if loc then
        local cx = loc.x * 8 + Underlay.MARK_X
        local cy = loc.y * 8 + Underlay.MARK_Y
        ok(cx + bay.x0 >= 0 and cx + bay.x1 < Underlay.TEX_W,
           bay.town .. "'s bay stays on the sheet across")
        ok(cy + bay.y0 >= 0 and cy + bay.y1 < Underlay.TEX_H,
           bay.town .. "'s bay stays on the sheet down")
        -- the marker box runs from -4 to +3 about the centre, so a bay may
        -- start at +4 and no earlier without eating the town itself
        ok(bay.y0 >= 4, bay.town .. "'s bay clears its own marker box")
      end
    end
  end
end

-- ------- result

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
