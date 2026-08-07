-- The eye that follows the bird: the diorama's 50-degree pitch, but on a
-- boom that turns with the flight instead of standing fixed to the south.
--
-- Voxel3D.camera is the voxel mod's own documented slot for "a placed
-- camera rather than the orbit" -- the door the VR eyes and the staged
-- battle's over-the-shoulder rig already go through. This module fills the
-- same record shape and hands it over at the same seam the mod itself uses:
-- FirstPerson.frame, called once per frame from VoxelScene.render before
-- anything is cast or drawn.
--
-- Two things are borrowed from the first-person rig rather than rebuilt:
--
--   the YAW.        FirstPerson owns the look inputs -- mouse, right stick,
--                   touch drag, and the capture lifecycle around them.
--                   main.lua makes it read them during a flight by
--                   reporting the flight as engaged, so all this module
--                   does is read FirstPerson.yaw back out.
--
--   the ADOPTION.   FirstPerson.adoptVReye is how an outside camera tells
--                   the mod "I am the placed camera now", so the character
--                   cards yaw to face THIS eye instead of keeping the
--                   diorama's fixed southward lean. Without it a bird
--                   flying north would be looking at the back of every
--                   sprite's front.
--
-- The boom deliberately does NOT use ThirdPerson.place: that marches back
-- through the terrain height field and walks the eye in when it would clip
-- a wall, which is right for a camera at shoulder height and wrong for one
-- six cells above the rooftops -- it would drag the camera down into the
-- town every time the bird crossed a tall building.

local V = ...
local Flight = V.require("Flight")
local BirdMove = V.require("BirdMove")

local BirdCam = {}

-- How far back along the look the eye sits, in world pixels. The boom is
-- longer than the third-person one (48) because the subject is a bird over
-- a landscape rather than a character in a street: at this range the frame
-- carries a few blocks of town around it.
BirdCam.BOOM = 130

-- ------- where the camera actually looks
--
-- NOT at the bird. A boom aimed at its own subject puts the view direction
-- through the bird and out into the sky beyond, and at cruise altitude with
-- the world curve on that is most of the frame: the first cut of this module
-- flew Pallet to Viridian with forty per cent of the picture empty.
--
-- So the camera looks BELOW and slightly AHEAD of the bird, which tips the
-- view down onto the landscape being crossed and leaves the bird sitting in
-- the upper part of frame -- the flight-sim framing, and the one this mod
-- exists for: the world from above, with the bird to say where you are in it.
--
-- LEAD is how far ahead, in world pixels -- about three cells.
BirdCam.LEAD = 48

-- ------- how far below the bird the camera aims
--
-- Not a constant, and not a share of the altitude. Both of those were tried
-- and both put the subject somewhere it should never be:
--
--   Aiming at the literal GROUND makes the drop equal the whole altitude,
--   so the camera tips further down with every cell climbed. At six cells
--   that was a pleasant 51 degrees; at twenty-four it was 72, and the bird
--   had left the top of the screen.
--
--   A FIXED drop holds the framing across the height ladder, but not across
--   the ANGLE one: the boom hangs at whatever the FLY VOXEL rung says, and
--   at 75 -- an almost level diorama -- a drop tuned for 50 swung the aim
--   nearly 35 degrees below the bird, which is past the edge of a 65-degree
--   lens. The bird simply was not in the picture.
--
-- So the drop is SOLVED, per frame, from the angle the boom actually hangs
-- at: whatever puts the bird a fixed number of degrees above the middle of
-- the shot. Then no rung, no height and no amount of looking around can
-- misplace it -- the one thing about this camera that has to be true.
--
-- SIT is that fixed offset. Comfortably inside the half-lens (32.5 degrees),
-- so the bird reads as being in the upper part of frame rather than clinging
-- to its rim.
BirdCam.SIT = math.rad(18)

-- The aim may not go past this far below horizontal. At the steepest rungs
-- the bird is already almost directly below the eye, and asking for another
-- eighteen degrees would want an aim past straight down, which no drop can
-- express (the tangent runs away). Clamped, the bird simply sits a little
-- closer to the middle -- still in shot, which is the promise.
BirdCam.MAX_AIM = math.rad(85)

-- The drop that achieves it for a boom of length `R` at pitch `a` (from
-- vertical). Pure, so the suite can sweep every rung.
function BirdCam.dropFor(R, a)
  local back = math.sin(a) * R
  local up = math.cos(a) * R
  local toBird = math.atan2(up, back)
  local aim = math.min(toBird + BirdCam.SIT, BirdCam.MAX_AIM)
  return math.max(0, (back + BirdCam.LEAD) * math.tan(aim) - up)
end

-- ------- looking around
--
-- How far the player's own look may swing the boom, either side of the rung
-- it hangs at. Generous, because the whole point is to be able to lift the
-- view off the ground and see where you are headed -- but bounded, so the
-- boom can never go over the top (a < 0 puts the eye in front of the bird
-- and the picture turns inside out) or drop below the horizon.
BirdCam.PITCH_MIN = math.rad(12)      -- nearly overhead
BirdCam.PITCH_MAX = math.rad(88)      -- nearly level with the bird

-- The boom's angle for a rung of `base`, with the player looking by `pitch`
-- (FirstPerson's convention: positive looks DOWN).
--
-- Looking down means the eye climbs and the camera peers further over the
-- top of the world, which is a SMALLER angle from vertical -- hence the
-- subtraction. Clamped rather than free, and the clamp is what makes this
-- safe to hand a player: whatever they do with the mouse, the drop above is
-- then solved for the angle they landed on, and the bird stays in shot.
function BirdCam.pitchFor(base, pitch)
  local a = base - (pitch or 0)
  if a < BirdCam.PITCH_MIN then a = BirdCam.PITCH_MIN end
  if a > BirdCam.PITCH_MAX then a = BirdCam.PITCH_MAX end
  return a
end

-- The pitch the boom hangs at, if nothing better can be worked out: the
-- angle from straight DOWN, in VoxelState's own convention.
BirdCam.FALLBACK_PITCH = 50

local rig = nil

-- The angle the boom sits at, taken from the VOXEL rung the flight is
-- actually flying under.
--
-- Read off the rung rather than written as a number, because the rung is a
-- setting now: point FLY VOXEL at 35 and the diorama tips to 35, so a camera
-- still hanging at a hardcoded 50 would be looking at the world from an
-- angle the mode is no longer drawn for. On KEEP the flight does not choose
-- a rung at all, so the answer is whichever one is live.
local function pitchAngle(DS)
  local ok, deg = pcall(function()
    local Voxel = DS.require("VoxelState")
    local Options = V.require("Options")
    local want = Options.wants(Options.voxel)
    if want then
      for i, label in ipairs(Voxel.ANGLE_LABELS) do
        if label == want then return Voxel.ANGLES_DEG[i] end
      end
    end
    -- KEEP, or a rung this build's ladder does not have: follow the live one
    local Pipelines = require("src.render.Pipelines")
    return Voxel.ANGLES_DEG[Pipelines.level("voxel") + 1]
  end)
  deg = ok and deg or nil
  -- Zero is the OFF rung's entry, and it is not an angle -- it is "there is
  -- no diorama". Nothing calls this in that case (no 3D pass runs at all),
  -- but answering with a straight-down camera if anything ever did would be
  -- a strange way to fail, so it falls back like any other unusable rung.
  if not deg or deg <= 0 then deg = BirdCam.FALLBACK_PITCH end
  return math.rad(deg)
end

-- The eye offset from the bird for a boom of length R at pitch `a` (from
-- vertical) and heading `yaw`.
--
-- The flat look direction is (sin yaw, cos yaw) -- FirstPerson's own
-- convention, where yaw 0 faces south -- so the camera, being BEHIND, sits
-- along its negative. At a = 0 the eye is straight overhead and at a = 90
-- it is level with the bird; 50 lands between, which is what the diorama's
-- own orbit does with the same number.
function BirdCam.offset(R, a, yaw)
  local s = math.sin(a)
  return -math.sin(yaw) * s * R, math.cos(a) * R, -math.cos(yaw) * s * R
end

-- ------- the attitude that framing works out to
--
-- Pure, and separated out because it is the thing that has to hold: how far
-- below horizontal the camera looks, and how far off that axis the bird sits.
-- Both must be independent of altitude, and the second must stay well inside
-- the lens or the subject leaves the picture. Two earlier versions of this
-- module failed exactly one of those and looked fine in the other's
-- screenshot, so the suite pins both rather than trusting an eye.
--
-- Returns the view angle and the bird's offset from it, in radians, for a
-- boom of `R` at pitch `a`.
function BirdCam.attitude(R, a)
  local back = math.sin(a) * R      -- how far behind the bird the eye sits
  local up = math.cos(a) * R        -- and how far above it
  -- the bird, seen from the eye
  local toBird = math.atan2(up, back)
  -- and the point the camera is aimed at: further along, and lower
  local toFocus = math.atan2(up + BirdCam.dropFor(R, a), back + BirdCam.LEAD)
  return toFocus, toFocus - toBird
end

-- Build the frame's camera. Signature matches FirstPerson.frame, because it
-- stands in for it: (me, cx, cy, vw, vh) -> rig, sceneCx, sceneCy.
--
-- `me` is the player's posed entry, already carrying the altitude as its
-- lift (the pose wrap in main.lua put it there), so the eye follows the
-- climb without this module tracking it separately. With no pose to read --
-- the frame a warp covers, a headless run -- the bird's own position and
-- Flight's altitude answer instead.
function BirdCam.frame(me, cx, cy, vw, vh)
  local DS = V.ds()
  local FirstPerson = DS.require("FirstPerson")
  local Voxel3D = DS.require("Voxel3D")

  local bx, by, bz, ground
  if me then
    ground = me.gh or 0
    bx, by, bz = me.px + 8, ground + (me.lift or 0), me.py + 8
  else
    local p = BirdMove._pos()
    ground = 0
    bx, bz = (p and p.x) or cx, (p and p.z) or cy
    by = Flight.altitude
  end

  -- The rung's own angle, then the player's look on top of it if FLY LOOK
  -- allows -- and the drop solved for whatever the two of them add up to,
  -- which is what keeps the bird in shot at any of them.
  local a = pitchAngle(DS)
  local Options = V.require("Options")
  if Options.look:get() then
    a = BirdCam.pitchFor(a, FirstPerson.pitch)
  end
  local yaw = FirstPerson.yaw
  local ox, oy, oz = BirdCam.offset(BirdCam.BOOM, a, yaw)

  -- below and ahead of the bird, never at the ground itself -- see dropFor
  local fx = bx + math.sin(yaw) * BirdCam.LEAD
  local fz = bz + math.cos(yaw) * BirdCam.LEAD
  -- Allowed to land UNDER the terrain, and it will at the lowest rung. The
  -- focus is a direction to look and a centre for the curve, not a place
  -- anything is drawn: clamping it to the ground would tip the camera back
  -- up exactly where the view is already shallowest.
  local fy = by - BirdCam.dropFor(BirdCam.BOOM, a)

  rig = {
    eye = { bx + ox, by + oy, bz + oz },
    focus = { fx, fy, fz },
    fov = FirstPerson.FOV,
    -- world up, so the horizon stays level through every turn. Left as the
    -- default rather than the orbit's leaning up: that one exists because a
    -- near-vertical orbit degenerates against world up, and this camera is
    -- never near vertical.
    up = { 0, 1, 0 },
    -- curve deliberately omitted: Voxel3D falls back to WorldCurve.k(vh),
    -- which is the V-CURVE 3 this mod borrowed for the flight. Setting it
    -- here would freeze the bend at whatever it was when the rig was built.
  }
  Voxel3D.camera = rig
  -- tell the mod this is the placed camera now, so the cards turn to face it
  pcall(FirstPerson.adoptVReye, rig)

  -- The scene centre is the point the camera LOOKS at, not the eye's own
  -- pivot: it is what the world curve stays flat around, what the depth
  -- reference is measured from and what the sun's box is fitted to, and all
  -- three want the ground being flown over rather than the bird above it.
  return rig, fx, fz
end

-- Let go on landing, and hand the frame straight back to the orbit.
--
-- Clearing Voxel3D.camera is not enough on its own. FirstPerson's blend is
-- at 1 (this mod reported the flight as engaged), and the moment the flight
-- ends its own frame() starts easing that back down over BLEND_TIME --
-- building, for those frames, the FIRST-PERSON rig: an eye in the player's
-- head, which is nowhere near where the boom just was. The player would see
-- the camera snap into their own skull and then drift out to the diorama.
--
-- So the blend is put to zero outright. The descent has already walked the
-- altitude back to the ground, so the orbit picks up a camera that is
-- looking at very nearly the same thing, and there is nothing left to ease.
function BirdCam.release()
  local DS = V.ds()
  if DS then
    pcall(function()
      local Voxel3D = DS.require("Voxel3D")
      local FirstPerson = DS.require("FirstPerson")
      if Voxel3D.camera == rig then Voxel3D.camera = nil end
      FirstPerson.blend = 0
      -- and let go of the adoption, so nothing downstream still believes a
      -- placed camera is drawing
      pcall(FirstPerson.adoptVReye, nil)
    end)
  end
  rig = nil
end

function BirdCam._rig() return rig end

return BirdCam
