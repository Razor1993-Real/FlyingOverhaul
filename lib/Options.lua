-- The five things about a flight the player gets to decide.
--
-- Defaults are exactly what the mod did before there was a menu, so a save
-- that never opens it flies the way it always has.
--
-- Three of the five reach into the voxel mod's settings for the duration of
-- the flight, and each of those carries a KEEP rung. KEEP is not "off" -- it
-- means the flight does not touch that setting at all, neither on the way in
-- nor on the way out. A player who has tuned their own diorama and wants to
-- see it from the air, rather than through this mod's idea of a good view,
-- picks KEEP and keeps it.

local V = ...
local Setting = V.require("Setting")

local Options = {}

-- The sentinel for "leave the player's own value alone". A table rather than
-- a string, so it can never collide with a real ladder value however the
-- voxel mod relabels its rungs.
Options.KEEP = setmetatable({}, { __tostring = function() return "KEEP" end })

local KEEP = Options.KEEP

-- ------- height
--
-- Stored in world pixels, shown in CELLS, which is the unit the player reads
-- the world in: a cell is one step and one tile.
Options.height = Setting.new("height", "FLY HEIGHT",
  { 96, 192, 384, 768 },
  { "6 CELLS", "12 CELLS", "24 CELLS", "48 CELLS" },
  384,
  "How high the bird climbs. Higher shows more of the region at once and "
  .. "tips the camera further over; lower keeps you close enough to read "
  .. "the streets you are crossing.")

-- ------- speed
--
-- A multiplier on WALKING, not an absolute, so it keeps meaning the same
-- thing if the walk is ever retuned.
Options.speed = Setting.new("speed", "FLY SPEED",
  { 3, 4.5, 6, 9 },
  { "3X", "4.5X", "6X", "9X" },
  4.5,
  "How fast the bird crosses ground, as a multiple of walking speed.")

-- ------- the borrowed diorama settings
--
-- The ladders mirror the voxel mod's own rungs BY LABEL: this mod stores
-- "50" and resolves it against Pipelines.levelLabels at take-off, so a
-- reordered ladder over there moves this with it instead of silently
-- meaning a different angle (VoxelState says outright that its rung order
-- is not a promise).
-- OFF is a rung like any other here, and it is the one that turns the
-- diorama off for the flight: the world goes back to the flat tile
-- renderer, the bird rides above it as a raised sprite, and the compass and
-- the landing rules carry on unchanged. For anyone who wants the flight
-- without the 3D, or whose machine would rather not draw thirty maps of
-- geometry at once.
Options.voxel = Setting.new("voxel", "FLY VOXEL",
  { KEEP, "OFF", "15", "35", "50", "75" },
  { "KEEP", "OFF", "15", "35", "50", "75" },
  "50",
  "The camera angle the flight switches the diorama to. OFF flies over the "
  .. "flat world instead. KEEP leaves your own VOXEL setting alone. The "
  .. "bird's camera follows whichever rung this picks.")

Options.tshift = Setting.new("tshift", "FLY T-SHIFT",
  { KEEP, "OFF", "1", "2", "3" },
  { "KEEP", "OFF", "1", "2", "3" },
  "2",
  "The miniature blur during a flight. KEEP leaves your own T-SHIFT alone.")

-- OFF by default. The bend was chosen when the flight was a novelty seen
-- from one altitude, and it does read as a small planet from up there -- but
-- it also drops everything past the near distance below the horizon, and
-- what you are usually doing up here is looking at Kanto. Flat shows more of
-- it, and now that the void is filled there is something out there to see.
Options.curve = Setting.new("curve", "FLY V-CURVE",
  { KEEP, 0, 1, 2, 3 },
  { "KEEP", "OFF", "1", "2", "3" },
  0,
  "How far the world bends away over the horizon during a flight. OFF keeps "
  .. "it flat, which shows the most of the map. KEEP leaves your own V-CURVE "
  .. "alone.")

-- ------- steering the eye
--
-- Whether the look inputs tip the camera up and down during a flight, the
-- way they do on the third-person rung. On by default: the flight already
-- reads the look for its heading, and being able to lift the view off the
-- ground to see where you are going is most of what a camera is for.
--
-- The bird stays in frame at every angle either way -- that is BirdCam's
-- job, not this setting's (see BirdCam.dropFor).
Options.look = Setting.new("look", "FLY LOOK",
  { true, false },
  { "ON", "OFF" },
  true,
  "Tip the camera up and down while flying, with the mouse or the right "
  .. "stick. The bird stays in shot whatever you do. OFF pins the camera to "
  .. "the angle the FLY VOXEL rung implies.")

-- ------- the map under the void
--
-- The one setting here that is not about a flight at all: the Kanto sheet
-- shows whenever the diorama does, walking included. It lives with these
-- because it is this mod's, and because the place a player looks for it is
-- the block with the other rows this mod added.
Options.underlay = Setting.new("underlay", "KANTO MAP",
  { true, false },
  { "ON", "OFF" },
  true,
  "Lay the game's own Kanto map under the empty space between towns and "
  .. "routes, so the gaps read as sea and coastline instead of as nothing. "
  .. "It hangs below the ground, so it never covers anywhere you can walk. "
  .. "OFF builds nothing and draws nothing.")

-- In the order they appear on both menus.
Options.ALL = {
  Options.height, Options.speed, Options.look,
  Options.voxel, Options.tshift, Options.curve,
  Options.underlay,
}

function Options.schema()
  local out = {}
  for _, s in ipairs(Options.ALL) do out[#out + 1] = s:schema() end
  return out
end

function Options.rows()
  local out = {}
  for _, s in ipairs(Options.ALL) do out[#out + 1] = s:row() end
  return out
end

-- The manager wrote one of ours: move the cached index so the OPTIONS row
-- and the next flight agree with the page the player just used.
function Options.sync(key, value)
  for _, s in ipairs(Options.ALL) do
    if s.key == key then s:sync(value) end
  end
end

function Options.wants(setting)
  local v = setting:get()
  if v == KEEP then return nil end
  return v
end

return Options
