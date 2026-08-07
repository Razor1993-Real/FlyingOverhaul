-- The borrowed settings: VOXEL "50", T-SHIFT "2", V-CURVE "3", for the
-- duration of the flight and not one frame longer.
--
-- The point of this module is that the player's OWN choices survive it.
-- Both mechanisms the three values live behind can be moved without
-- writing anything to disk, which is what makes a temporary override
-- honest rather than a settings edit that gets undone afterwards:
--
--   VOXEL and T-SHIFT are render pipelines of the voxel mod. The engine
--   keeps their live levels in a table inside src/render/Pipelines.lua;
--   only Pipelines.syncOptions + Game:writeOptions push them at the file,
--   and neither is called here.
--
--   V-CURVE is a plain ModSetting of the voxel mod. ModSetting:setIndex
--   would persist, so this uses :sync, which the voxel mod documents as
--   "nothing to store: just move the cached index" -- exactly a live
--   override with the stored value left alone.
--
-- Levels are resolved BY LABEL rather than hardcoded. The voxel mod's
-- ladder has grown a rung in its middle before (VoxelState's comment on
-- setValue says so outright), and "50" is a promise about what the player
-- sees, not about an index.

local V = ...

local Settings = {}

local saved = nil

-- The level whose label is `label`, or nil when this build's ladder has no
-- such rung. Compared on the leading token so "1ST (EXPERIMENTAL)" would
-- match "1ST" -- the rungs this mod wants are plain numbers, but the rule
-- costs nothing and keeps the lookup from being surprised by a suffix.
local function levelForLabel(Pipelines, id, label)
  local labels = Pipelines.levelLabels(id)
  for i, text in ipairs(labels) do
    if text == label or tostring(text):match("^%S+") == label then
      return i - 1
    end
  end
  return nil
end
Settings._levelForLabel = levelForLabel

-- ------- the FULL problem
--
-- The voxel pipeline's update hook calls applyFull(level) every frame, and
-- applyFull fires on the RISING EDGE into FULL -- where it rewrites seven
-- other settings and persists them.
--
-- So a player who was sitting on FULL when they took off would have their
-- T-SHIFT, V-CURVE, WATER, ZOOM, 3D-BTL, BACK SPRITES and DAYTIME quietly
-- overwritten the moment this module put the VOXEL row back on landing --
-- the preset firing at us, not at them.
--
-- It cannot be suppressed from out here (applyFull and its edge flag are
-- locals of the voxel mod's main.lua), so it is allowed to fire and then
-- undone: everything it touches is snapshotted before the flight and put
-- back after the restore. Only done when the stored rung actually is FULL,
-- because in every other case the edge never happens.
local function fullSettings(DS)
  local ok, list = pcall(function()
    return {
      { mod = DS.require("WorldCurve").setting },
      { mod = DS.require("Water").setting },
      { mod = DS.require("OverworldBattle").setting },
      { mod = DS.require("OverworldBattle").backSetting },
      { mod = DS.require("DayNight").setting },
    }
  end)
  return ok and list or {}
end

local function isFullLevel(DS, level)
  local ok, full = pcall(function()
    return DS.require("VoxelState").FULL_LEVEL
  end)
  return ok and level == full
end

-- ------- taking them

function Settings.borrow(DS, game)
  if saved then return end
  local Pipelines = require("src.render.Pipelines")
  local WorldCurve = DS.require("WorldCurve")

  local Options = V.require("Options")
  local wantVoxel = Options.wants(Options.voxel)
  local wantTilt = Options.wants(Options.tshift)
  local wantCurve = Options.wants(Options.curve)

  -- A setting on KEEP is not saved either. Snapshotting it would be
  -- harmless but dishonest: `saved.voxel = nil` is the record that this
  -- flight never owned that value, and restore reads it the same way.
  saved = {
    voxel = wantVoxel and Pipelines.level("voxel") or nil,
    tiltshift = wantTilt and Pipelines.level("tiltshift") or nil,
    curve = wantCurve and WorldCurve.setting:get() or nil,
    full = nil,
  }

  -- everything applyFull would clobber on the way back, if the way back
  -- goes through FULL. Only reachable when this flight actually owns the
  -- VOXEL row -- on KEEP the level never moves, so the preset's edge never
  -- fires and there is nothing to undo.
  if wantVoxel and isFullLevel(DS, saved.voxel) then
    saved.full = {}
    for _, entry in ipairs(fullSettings(DS)) do
      saved.full[#saved.full + 1] = { setting = entry.mod,
                                      value = entry.mod:get() }
    end
    local opts = game and game.save and game.save.options
    saved.zoom = opts and opts.zoom
    saved.battleLayout = opts and opts.battleLayout
  end

  if wantVoxel then
    local level = levelForLabel(Pipelines, "voxel", wantVoxel)
    if level then Pipelines.setLevel("voxel", level) end
  end
  if wantTilt then
    local level = levelForLabel(Pipelines, "tiltshift", wantTilt)
    if level then Pipelines.setLevel("tiltshift", level) end
  end
  if wantCurve then WorldCurve.setting:sync(wantCurve) end
end

-- ------- and handing them back

function Settings.restore(DS, game)
  if not saved then return end
  local Pipelines = require("src.render.Pipelines")
  local WorldCurve = DS.require("WorldCurve")

  -- nil means this flight never took that one (KEEP), so there is nothing
  -- to give back and writing anything would be the mod overruling a choice
  -- it was explicitly told to stay out of
  if saved.voxel then Pipelines.setLevel("voxel", saved.voxel) end
  if saved.tiltshift then Pipelines.setLevel("tiltshift", saved.tiltshift) end
  if saved.curve then WorldCurve.setting:sync(saved.curve) end

  -- Put back what the FULL preset is about to overwrite (or has already:
  -- setLevel above is what arms its edge, and the pipeline's update hook
  -- runs before the next frame draws). These DO write, because applyFull
  -- wrote -- restoring the live value alone would leave the file changed.
  if saved.full then
    for _, entry in ipairs(saved.full) do
      pcall(function() entry.setting:setValue(entry.value, game) end)
    end
    local opts = game and game.save and game.save.options
    if opts then
      if saved.zoom ~= nil then
        opts.zoom = saved.zoom
        pcall(function() require("src.render.Zoom").applyOptions(opts) end)
      end
      if saved.battleLayout ~= nil then opts.battleLayout = saved.battleLayout end
      if game.writeOptions then pcall(game.writeOptions, game) end
    end
  end

  saved = nil
end

-- The player changed one of these from the mod manager mid-flight: their
-- new choice is what the flight should hand back, not the one from before
-- take-off. Called from the mod.options_changed listener in main.lua.
function Settings.noteExternalChange(key, value)
  if not saved then return end
  -- only for a value this flight actually took: a nil slot means KEEP, and
  -- filling it in here would invent a restore for a setting the flight was
  -- told not to touch
  if key == "curve" and saved.curve ~= nil then saved.curve = value end
  if saved.full then
    for _, entry in ipairs(saved.full) do
      if entry.setting.key == key then entry.value = value end
    end
  end
end

function Settings.borrowed()
  return saved ~= nil
end

-- named for the suite
function Settings._saved() return saved end
function Settings._clear() saved = nil end

return Settings
