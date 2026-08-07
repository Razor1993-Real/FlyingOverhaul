-- The flight's walk: what the pad does while the player is a bird.
--
-- Modelled on the voxel mod's lib/FreeMove.lua -- same seam
-- (OverworldState:handleInput), same continuous position, same
-- camera-relative steering -- but the two differ on purpose in the things
-- that make a bird a bird:
--
--   NO COLLISION.       Nothing up here is in the way. FreeMove asks
--                       Collision per overlapped cell and slides along what
--                       refuses; this integrates a point.
--
--   NO onStepComplete.  This is the important one. FreeMove fires the
--                       engine's landing pipeline once per cell crossed, so
--                       a free walk rolls encounters, takes warps, trips
--                       triggers and counts steps exactly as a grid walk
--                       does. A bird at six cells up must do NONE of that:
--                       flying over tall grass is not walking through it,
--                       and crossing a door's cell at altitude is not
--                       entering it. The logical cell is still kept in step,
--                       because the landing needs to know which cell it is
--                       putting the player down on -- but that is all it is
--                       for.
--
--   NO map change.      Walking off the edge hands the direction to
--                       checkEdgeExit and the connection takes over. Here
--                       the position is clamped to the loaded
--                       neighbourhood instead, so one flight is one
--                       continuous stretch of world and the camera never
--                       has the map re-root under it.
--
-- What it does share with FreeMove is the steering: FirstPerson owns the
-- yaw (this mod makes it read the look inputs by reporting the flight as
-- engaged -- see main.lua), moveVector reads the pad and moveWorld rotates
-- it into the world, so forward is wherever the player is looking.

local V = ...
local Flight = V.require("Flight")

local BirdMove = {}

-- How far outside the loaded neighbourhood the bird may go before it is
-- held. A screen or so of slack, so the clamp is felt as the edge of the
-- world rather than as a wall at the last tile.
BirdMove.EDGE_SLACK = 160

local pos = nil          -- the free position (bird centre, world px)
local facing = "down"    -- the compass frame the bird card shows
local bearing = nil      -- the continuous heading behind that compass point
local flap = 0           -- wing-beat clock

function BirdMove.drop()
  pos = nil
  bearing = nil
  -- and hand the body's bearing back, so nothing downstream keeps turning
  -- the card by a heading the bird no longer has
  local DS = V.ds()
  if DS then
    pcall(function() DS.require("FirstPerson").releaseBody() end)
  end
end

function BirdMove._pos() return pos end
function BirdMove._bearing() return bearing end

-- ------- which way the bird points
--
-- The sprite sheet has all four views -- SPRITE_BIRD is a full six-frame
-- walker like the player, front and back and side -- and until now exactly
-- one of them was ever drawn.
--
-- The reason is worth writing down, because it looked correct from every
-- direction except the one that mattered. The body's heading used to come
-- from the voxel mod's pointBody, and that returns the direction of TRAVEL
-- only while the third-person boom is out; on any other rung it returns the
-- camera's own yaw instead. The flight runs on the "50" rung, so it always
-- got the camera's yaw -- and since the flight camera is itself boomed along
-- that same yaw, the bird sat at a fixed hundred and eighty degrees from the
-- lens forever. Its back, every frame, whatever the player did.
--
-- So the heading is worked out here, from where the bird is actually going.
-- Fly forward and the camera is behind you: the back. Strafe and the camera
-- is off your flank: the side. Turn, and for as long as the turn lasts the
-- travel and the look disagree, which is what makes the bird visibly lean
-- into it.

local TWO_PI = math.pi * 2

local function wrapPi(a)
  a = (a + math.pi) % TWO_PI
  if a < 0 then a = a + TWO_PI end
  return a - math.pi
end
BirdMove._wrapPi = wrapPi

-- The quantisation the engine's four sprite frames are cut on: whichever of
-- sin and cos is larger in magnitude picks the axis, so the boundaries fall
-- at the diagonals. A restatement of FirstPerson's own `facingOf`, which is
-- a local there -- and it must agree with it exactly, because this answer is
-- what the flat renderer draws when the voxel mod is off.
function BirdMove.facingOf(a)
  local s, c = math.sin(a), math.cos(a)
  if math.abs(s) > math.abs(c) then
    return s > 0 and "right" or "left"
  end
  return c > 0 and "down" or "up"
end

-- How much of the way to the new heading one step turns. A bird that snapped
-- would flick between two frames every time a turn crossed a diagonal, which
-- is the one place the quantisation above has an edge; easing carries the
-- bearing across it once.
BirdMove.TURN_RATE = 0.22

-- Ease `from` toward `to` the short way round. Going the short way is the
-- whole point: a bird turning from just west of north to just east of it
-- must cross north, not spin all the way through south.
function BirdMove.turnToward(from, to, rate)
  if from == nil then return to end
  return wrapPi(from + wrapPi(to - from) * (rate or BirdMove.TURN_RATE))
end

-- Which of the four sprite frames the bird is posed in.
function BirdMove.facing() return facing end

-- World pixels per fixed logic step: the walk, times the flight's
-- multiplier. Asked of the voxel mod's own FreeMove.WALK so the ratio holds
-- if that constant is ever retuned, with Flight.WALK_REFERENCE standing in
-- when there is nothing to ask.
function BirdMove.speed()
  local walk = Flight.WALK_REFERENCE
  local DS = V.ds()
  if DS then
    local got, w = pcall(function() return DS.require("FreeMove").WALK end)
    if got and type(w) == "number" and w > 0 then walk = w end
  end
  return walk * Flight.MULTIPLIER
end

-- The wing beat, as the two-frame phase the bird sheet is drawn in. Runs
-- off its own clock rather than the walk cycle: a bird flaps whether or not
-- it is going anywhere.
function BirdMove.flapPhase()
  return math.floor(flap / 6) % 2
end

-- ------- the world the flight may cover
--
-- The union of the current map and every neighbour rebuildNeighbors placed,
-- in the current map's own pixel space (neighbour offsets are already in it).
function BirdMove.bounds(state)
  local def = state.map and state.map.def
  if not def then return nil end
  local x0, y0 = 0, 0
  local x1, y1 = def.width * 32, def.height * 32
  for _, nb in ipairs(state.neighbors or {}) do
    local d = nb.map and nb.map.def
    if d then
      if nb.ox < x0 then x0 = nb.ox end
      if nb.oy < y0 then y0 = nb.oy end
      if nb.ox + d.width * 32 > x1 then x1 = nb.ox + d.width * 32 end
      if nb.oy + d.height * 32 > y1 then y1 = nb.oy + d.height * 32 end
    end
  end
  local s = BirdMove.EDGE_SLACK
  return x0 - s, y0 - s, x1 + s, y1 + s
end

local function adopt(p)
  pos = { x = p.px + 8, z = p.py + 8 }
end

-- ------- the tick
--
-- Runs in place of OverworldState:handleInput for the whole flight, so it
-- inherits every gate above the call -- scripted moves, transitions, and
-- anything pushed over the overworld all still stop it, exactly as they
-- stop the grid walk.
function BirdMove.tick(state)
  local p = state.player
  flap = flap + 1
  if not pos then adopt(p) end

  local Game = require("src.core.Game")
  local input = Game.input
  local DS = V.ds()
  local FirstPerson = DS and DS.require("FirstPerson")
  if not FirstPerson then return end

  -- Climbing or descending: the player is a passenger, and the altitude is
  -- eased by Flight from the fixed-step tick. The HEADING still has to be
  -- kept, though -- the bird is on screen for the whole climb, and one that
  -- held a stale bearing through it would turn to face its travel only after
  -- it had already arrived at cruise.
  if not Flight.steerable() then
    bearing = BirdMove.turnToward(bearing, FirstPerson.yaw)
    FirstPerson.bodyYaw = bearing
    facing = BirdMove.facingOf(bearing)
    return
  end

  -- A puts the bird down -- if the ground will have it, and if the player
  -- has been here before. The two refusals are answered differently on
  -- purpose: water refusing a landing explains itself, but "you have never
  -- been here" is a rule the player cannot see from the air, so it is said
  -- out loud instead of buzzed at.
  if input:wasPressed("a") then
    local landed, why = BirdMove.requestLanding(state)
    if not landed then
      if why == "unexplored" then
        V.require("Compass").say("CAN'T LAND HERE", "NEVER BEEN HERE YET")
      else
        require("src.core.Sound").play(Game.data, "Collision")
      end
    end
    return
  end

  local mx, mz = FirstPerson.moveVector()
  local wx, wz = FirstPerson.moveWorld(mx, mz)

  -- Where the bird points: along its travel while it is going somewhere, and
  -- along the look while it hovers -- so a stationary bird faces the way the
  -- player is looking rather than freezing on its last heading.
  --
  -- Written to FirstPerson.bodyYaw rather than through pointBody, which
  -- would hand back the camera's yaw on this rung (see the header). bodyYaw
  -- is what playerFacing measures the card against, so this is the intended
  -- lever -- the same one the third-person walk uses -- and not a way round
  -- anything. `facing` is the quantised twin, for the flat renderer.
  local moving = (wx ~= 0 or wz ~= 0)
  local want = moving and math.atan2(wx, wz) or FirstPerson.yaw
  bearing = BirdMove.turnToward(bearing, want)
  FirstPerson.bodyYaw = bearing
  facing = BirdMove.facingOf(bearing)

  if not moving then return end

  local speed = BirdMove.speed()
  local dx, dz = wx * speed, wz * speed
  pos.x, pos.z = pos.x + dx, pos.z + dz

  local x0, y0, x1, y1 = BirdMove.bounds(state)
  if x0 then
    if pos.x < x0 then pos.x = x0 elseif pos.x > x1 then pos.x = x1 end
    if pos.z < y0 then pos.z = y0 elseif pos.z > y1 then pos.z = y1 end
  end

  p.px, p.py = pos.x - 8, pos.z - 8
  -- the logical cell, kept honest for the landing and for everything that
  -- asks the map a question about where the player is -- and NOT followed
  -- by onStepComplete, which is the whole point (see the header)
  p.cellX, p.cellY = math.floor(pos.x / 16), math.floor(pos.z / 16)
end

-- ------- the ground under the bird
--
-- NOT state.map. The flight crosses seams in the air -- nothing calls
-- onStepComplete, so no connection is ever taken -- which means the player's
-- cell goes on counting in the TAKE-OFF map's frame while the bird is bodily
-- over a neighbour. Asking state.map about a cell three maps north gets
-- "out of bounds", and the honest answer to "can I land here" becomes no
-- everywhere except the map the flight started on.
--
-- So the point is resolved against the maps actually loaded and drawn:
-- state.map at the origin, and every neighbour at its own offset. Those are
-- real Map objects, which is what the walkability question needs.
--
-- Returns map, cellX, cellY in THAT map's own coordinates, or nil over the
-- void between maps.
function BirdMove.groundUnder(state)
  local p = state.player
  local wx, wz = p.px + 8, p.py + 8

  local def = state.map and state.map.def
  if def and wx >= 0 and wx < def.width * 32
     and wz >= 0 and wz < def.height * 32 then
    return state.map, math.floor(wx / 16), math.floor(wz / 16)
  end

  for _, nb in ipairs(state.neighbors or {}) do
    local d = nb.map and nb.map.def
    if d and wx >= nb.ox and wx < nb.ox + d.width * 32
       and wz >= nb.oy and wz < nb.oy + d.height * 32 then
      return nb.map, math.floor((wx - nb.ox) / 16),
             math.floor((wz - nb.oy) / 16)
    end
  end
  return nil
end

-- The id alone, for callers that only want to know where they are.
function BirdMove.mapUnder(state)
  local map = BirdMove.groundUnder(state)
  return map and map.id or nil
end

-- Put the bird down, if the ground under it will have it and the player has
-- been there before. Returns (ok, reason) -- "terrain" or "unexplored" --
-- because the two refusals deserve different answers at the button.
--
-- The verdict lives HERE rather than at the button, so every way of asking
-- gets the same one: the A press, the mod's exported land() and the driver
-- suite alike. A landing that skipped the check would drop the player into
-- the sea, or into a town they have never walked to.
function BirdMove.requestLanding(state)
  local map, cx, cy = BirdMove.groundUnder(state)
  if not (map and Flight.canLandAt(map, cx, cy)) then
    return false, "terrain"
  end
  local Atlas = V.require("Atlas")
  Atlas.ensureLedger()
  if not Atlas.explored(map.id) then
    return false, "unexplored"
  end
  if not Flight.beginLanding() then return false, "phase" end

  local p = state.player
  if map.id ~= state.map.id then
    -- The bird flew across a seam, so the crossing has to be made official
    -- before it puts down -- otherwise the descent ends with the player
    -- standing at a negative cell on the map they took off from, which is a
    -- position no walk, warp or script can reason about.
    --
    -- setMap seamless, the same door crossConnection walks through: no fade,
    -- because the destination is already on screen underneath the bird and a
    -- wipe here would black out a landing the player is watching.
    state:setMap(map.id, cx, cy, p.facing, { seamless = true })
    -- and the region re-roots with it, so the compass and the next
    -- ground lookup measure from where the player now is
    Atlas.open(map.id)
  end
  p = state.player
  p.cellX, p.cellY = cx, cy
  -- snap onto the cell centre the descent will land on, so the bird comes
  -- down on the grid rather than between two cells
  p.px, p.py = cx * 16, cy * 16
  pos = nil
  p.inputLocked = true
  return true
end

return BirdMove
