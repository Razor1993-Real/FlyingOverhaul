-- The flight itself: which phase it is in, and how high the bird is.
--
-- Deliberately the only module that owns state. Everything else in this
-- mod -- the walk, the camera, the view distance, the borrowed settings --
-- reads this one and does its own job with the answer, so there is exactly
-- one place that knows whether the player is flying and exactly one
-- altitude for all of them to agree on.
--
-- Three phases, in order:
--
--   takeoff   the bird sprite replaces the walker and beats its wings while
--             the altitude eases up to CRUISE. Input is locked, as it is for
--             the vanilla departure.
--
--             Deliberately NOT the engine's own flyAnim state: that plays a
--             DEPARTURE -- FLY_PATH1 sweeps the bird up and off to the right
--             and FLY_PATH2 carries it off the top-left, because vanilla is
--             about leaving the map. Here the bird has to rise and STAY. It
--             would also cost the player their card outright: VoxelScene's
--             pose builder skips the player entirely while state.flyAnim is
--             set, since vanilla draws its own bird in a 2D overlay.
--   cruise    the free flight. BirdMove owns the pad, BirdCam owns the eye.
--   landing   the altitude eases back to the ground over the cell the
--             player chose. Input stays locked until it touches down.
--
-- Nothing here touches LOVE or the engine's singletons, so the whole
-- altitude curve and the phase machine are testable under plain luajit
-- (see tests/fly_logic_test.lua).

local V = ...

local Flight = {}

-- World pixels above the ground the bird cruises at. A cell is 16, so the
-- default is twenty-four cells up -- high enough that a turn shows a good
-- stretch of the region rather than the next block of town.
--
-- A DEFAULT, not a constant: main.lua overwrites both this and MULTIPLIER
-- from the FLY HEIGHT / FLY SPEED settings at take-off. They stay plain
-- fields on a plain table on purpose, so everything below keeps working --
-- and keeps being testable -- with no options system anywhere in reach.
Flight.CRUISE = 384

-- Seconds for the climb and for the descent. The climb is the longer of the
-- two, and grew with the altitude: the same distance in the old time would
-- have been a launch rather than a bird gaining height.
Flight.CLIMB_TIME = 2.0
Flight.DESCEND_TIME = 1.1

-- How much faster than walking the bird is. Kept as a MULTIPLIER rather
-- than an absolute px-per-step, because "faster than walking" is a
-- relationship to the walk and not a number of its own -- BirdMove reads the
-- voxel mod's FreeMove.WALK and multiplies, so retuning the walk carries the
-- flight with it instead of silently making this a different ratio.
Flight.MULTIPLIER = 4.5

-- What the walk is worth when it cannot be asked (no voxel mod loaded, the
-- pure-Lua suite): FreeMove.WALK's own value, the grid walker's 16 frames
-- per 16-pixel cell.
Flight.WALK_REFERENCE = 1.0

Flight.phase = nil        -- nil | "takeoff" | "cruise" | "landing"
Flight.altitude = 0       -- world pixels above the ground
Flight.t = 0              -- seconds inside the current eased phase
Flight.from = 0           -- altitude the current ease started at

-- smoothstep: zero slope at both ends, so the climb leaves the ground and
-- the descent meets it without a visible corner
local function ease(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end
Flight._ease = ease

function Flight.active()
  return Flight.phase ~= nil
end

-- Whether the free walk has the pad: cruise only. During the climb and the
-- descent the player is a passenger.
function Flight.steerable()
  return Flight.phase == "cruise"
end

function Flight.reset()
  Flight.phase, Flight.altitude, Flight.t, Flight.from = nil, 0, 0, 0
end

function Flight.beginTakeoff()
  Flight.phase = "takeoff"
  Flight.from = Flight.altitude
  Flight.t = 0
end

function Flight.beginLanding()
  if Flight.phase ~= "cruise" then return false end
  Flight.phase = "landing"
  Flight.from = Flight.altitude
  Flight.t = 0
  return true
end

-- Advance the phase machine by `dt` seconds. Returns the phase that was
-- just LEFT, or nil when nothing changed -- the caller uses that edge to
-- hand the settings back and unlock the player.
function Flight.update(dt)
  if not Flight.phase then return nil end
  Flight.t = Flight.t + (dt or 0)

  if Flight.phase == "takeoff" then
    local k = ease(Flight.t / Flight.CLIMB_TIME)
    Flight.altitude = Flight.from + (Flight.CRUISE - Flight.from) * k
    if Flight.t >= Flight.CLIMB_TIME then
      Flight.altitude = Flight.CRUISE
      Flight.phase = "cruise"
      return "takeoff"
    end
  elseif Flight.phase == "landing" then
    local k = ease(Flight.t / Flight.DESCEND_TIME)
    Flight.altitude = Flight.from * (1 - k)
    if Flight.t >= Flight.DESCEND_TIME then
      Flight.altitude = 0
      Flight.phase = nil
      return "landing"
    end
  end
  return nil
end

-- ------- where the bird may put itself down
--
-- A land cell, in bounds, that is not water. Asked of the engine's own
-- map predicates rather than of anything this mod keeps, so a cell that
-- the grid walker would refuse is refused here too -- and a mod that
-- rewrites walkability gets the same answer from both.
--
-- `map` is duck-typed on purpose: the suite hands in a table with the same
-- three methods rather than loading a real map.
function Flight.canLandAt(map, cx, cy)
  if not map then return false end
  if not map:inBounds(cx, cy) then return false end
  if map:isWaterCell(cx, cy) then return false end
  if not map:isWalkableCell(cx, cy) then return false end
  return true
end

return Flight
