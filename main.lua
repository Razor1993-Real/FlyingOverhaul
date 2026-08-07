-- Razor1993s Flying Overhaul: FLY stops being a menu and becomes a flight.
--
-- Vanilla FLY opens the town map, takes a pin, and warps
-- (src/ui/PartyMenu.lua -> TownMap -> OverworldState:flyTo). This mod
-- replaces the middle of that: the player climbs onto the bird, rises, and
-- flies the world freely at three times walking speed until they choose a
-- spot and put down.
--
-- It is a companion to the Dramatic Shape voxel mod and does nothing
-- without it -- the flight is a thing you do in a 3D world, and the camera
-- it needs is that mod's. That mod publishes its namespace for exactly this
-- (mod.exports.lib, "so a companion mod can pin its own tiles' shapes or
-- read the camera without reaching into this mod's file layout"), which is
-- the only door this file goes through.
--
-- Five seams, all of them wraps that forward when no flight is running, so
-- an ordinary session is untouched:
--
--   ui.party.submenu        the FLY entry becomes a callback instead of the
--                           action id that opens the town map.
--   input.step              the fixed 60Hz tick the climb and the descent
--                           are eased on.
--   handleInput             the pad, while flying (lib/BirdMove.lua).
--   FirstPerson.frame       the eye, while flying (lib/BirdCam.lua).
--   Player:pose             the bird sprite, at altitude (below).
--
-- plus FirstPerson.engaged, which is how the flight borrows the voxel mod's
-- look inputs -- see the wrap for why that is the honest answer rather than
-- a lie.

local mod = ...

-- ------- the mod namespace
--
-- Same shape as the voxel mod's: a mod directory is not on package.path and
-- may live inside a mounted .love archive, so modules are read through
-- mod:read and loaded with V passed in as their vararg.

local V = { mod = mod, path = mod.path }

local function chunkFor(rel)
  local source = mod:read(rel)
  if not source then
    error(("FLYING_OVERHAUL: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then
    error(("FLYING_OVERHAUL: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return chunk
end

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local value = chunkFor("lib/" .. name .. ".lua")(V)
  modules[name] = value
  return value
end

-- ------- the voxel mod
--
-- Resolved lazily and cached: the loader may run either mod's entry chunk
-- first, and exports are only populated once the owning chunk has finished.
-- Every caller in this mod goes through here rather than holding a
-- reference from load time.
local ds = nil
function V.ds()
  if ds then return ds end
  local ok, Game = pcall(require, "src.core.Game")
  local handle = ok and Game and Game.mods and Game.mods.exports
                 and Game.mods.exports["DRAMATIC_SHAPE"]
  ds = handle and handle.lib or nil
  return ds
end

-- Whether the flight can run at all: the voxel mod present, with a 3D pass
-- the hardware can actually carry. Asked fresh each time, because the
-- answer is a fact about this frame's driver as much as about the install.
local function available()
  local DS = V.ds()
  if not DS then return false end
  local ok, yes = pcall(function()
    return DS.require("Voxel3D").available()
  end)
  return ok and yes and true or false
end

local Flight = V.require("Flight")
local BirdMove = V.require("BirdMove")
local BirdCam = V.require("BirdCam")
local FarView = V.require("FarView")
local Settings = V.require("Settings")
local Atlas = V.require("Atlas")
local Compass = V.require("Compass")
local Options = V.require("Options")
local Tornado = V.require("Tornado")
local Underlay = V.require("Underlay")

-- ------- the settings menu
--
-- Two homes for the same five values. The manager's page comes from the
-- schema; the OPTIONS menu comes from the rows hook further down. Defined
-- here at load, because the manager may render this mod's page before a
-- flight has ever happened.
mod.options:define(Options.schema())

-- Forward declarations: the hooks below are compiled before these are
-- defined, and a Lua closure resolves a local it cannot see lexically as a
-- global instead -- which would silently never install anything.
local installed = false
local install

-- ------- starting and ending a flight

local function game()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game or nil
end

local function beginFlight()
  local G = game()
  local ow = G and G.overworld
  if not (ow and ow.map and ow.player) then return false end
  if Flight.active() then return false end

  -- The two numbers the flight runs on, read once at take-off rather than
  -- per frame: Flight stays a plain table with no idea an options menu
  -- exists, which is what keeps its curves testable under bare luajit.
  Flight.CRUISE = Options.height:get()
  Flight.MULTIPLIER = Options.speed:get()

  Flight.beginTakeoff()
  ow.player.inputLocked = true
  pcall(function() require("src.core.Sound").play(G.data, "Fly") end)

  Settings.borrow(V.ds(), G)
  -- The region's layout, rooted where the flight begins: the compass reads
  -- town positions out of it, and the landing reads which map it is over.
  -- Once per flight is enough -- the flight never changes maps.
  Atlas.open(ow.map.id)
  Atlas.ensureLedger()
  Compass.clear()
  Tornado.reset()
  -- the wide neighbourhood, built once here: the meshes for it stream in
  -- under the climb, which is what the climb is for as much as the look
  FarView.refresh(ow)
  return true
end

local function endFlight()
  local G = game()
  local ow = G and G.overworld
  BirdCam.release()
  BirdMove.drop()
  Settings.restore(V.ds(), G)
  Compass.clear()
  Atlas.close()
  if ow then
    FarView.refresh(ow)          -- back to the screen's own neighbourhood
    if ow.player then ow.player.inputLocked = false end
  end
end

-- ------- the FLY entry
--
-- PartyMenu dispatches a submenu entry either by its `action` id or, for
-- entries a hook put there, by calling entry.onSelect(mon, game) -- the
-- documented way in for exactly this. So the vanilla FLY row is swapped for
-- one that carries a callback, and the branch that pushes the town map is
-- simply never reached.
--
-- Everything that decides WHETHER the row exists is left alone: the badge
-- check and CheckIfInOutsideMap still gate it upstream, so a player who
-- could not fly before still cannot.
mod.hooks:wrap("ui.party.submenu", function(next, g, items, mon, ctx)
  local out = next(g, items, mon, ctx)
  if type(out) ~= "table" or not available() then return out end
  for i, entry in ipairs(out) do
    if type(entry) == "table" and entry.action == "fly" then
      out[i] = {
        label = entry.label,
        onSelect = function(_, gg)
          local G = gg or g
          if G and G.stack then G.stack:pop() end   -- close the party menu
          beginFlight()
        end,
      }
      break
    end
  end
  return out
end)

-- ------- the tick
--
-- input.step is the engine's fixed 60Hz logic boundary for tool mods. The
-- climb and the descent are eased here rather than from a render hook so
-- they advance at the game's rate, not the display's.
-- install() runs from here too rather than from load: the voxel mod's
-- exports only exist once its own entry chunk has finished, and the load
-- order between two mods is not ours to assume.
mod.hooks:wrap("input.step", function(next, g, dt)
  if not installed then install() end
  -- Build the Kanto sheet's texture HERE, on the logic tick, and never from
  -- inside the draw. It renders into its own canvas, and doing that in the
  -- middle of the voxel pass means swapping the canvas out from under a
  -- bound depth buffer. Cheap to call: it returns the cached image at once
  -- from the second tick onward.
  if Options.underlay:get() then Underlay.warm() end
  Compass.update(dt)
  Tornado.update(dt)
  local left = Flight.update(dt)
  if left == "landing" then endFlight() end
  return next(g, dt)
end)

-- ------- the compass
--
-- render.hud runs on the finished composite, AFTER the world pass and after
-- every present stage -- which is the whole reason the ribbon lives here
-- rather than in a pipeline. The flight borrows T-SHIFT 2, so anything drawn
-- into the world would come out of the miniature blur soft; a compass you
-- cannot read is worse than none. It also gets the playfield rect, so the
-- ribbon sits on the game rather than in the letterbox.
local hudFailed = false

-- ------- where the playfield is
--
-- render.hud is handed the viewport Renderer:endFrame returns... except that
-- the voxel mod wraps endFrame to paint its battle-exit veil over the
-- finished frame, and that wrapper calls the inner endFrame WITHOUT
-- returning its result (lib/BattleExit.lua). So with Dramatic Shape
-- installed -- which, for this mod, is always -- every render.hud subscriber
-- is handed nil instead of the frame's geometry.
--
-- Rather than re-derive the letterbox arithmetic (which would be a second
-- copy of a sum only the renderer should own, and would drift the first time
-- a zoom or a DPI rule changed), the numbers are taken from the engine's own
-- render.letterbox hook. It fires inside the same endFrame, every frame,
-- before the game canvas is blitted, and it carries exactly the rect
-- render.hud would have described: origin, playfield size and scale.
--
-- The viewport is still preferred when one arrives, so this costs nothing
-- once the upstream wrapper starts returning it.
local frameRect = nil

mod.hooks:wrap("render.letterbox", function(next, m)
  if type(m) == "table" and m.vpw then
    frameRect = {
      width = m.ww, height = m.wh,
      gameX = m.ox, gameY = m.oy,
      gameWidth = m.vpw, gameHeight = m.vph,
      scale = m.scale, dpiX = m.dpiX, dpiY = m.dpiY,
    }
  end
  return next(m)
end)

mod.hooks:wrap("render.hud", function(next, g, viewport)
  local rect = viewport or frameRect
  if Flight.active() and rect then
    local ow = g and g.overworld
    local p = ow and ow.player
    if p then
      local gotFP, FirstPerson = pcall(function()
        return V.ds().require("FirstPerson")
      end)

      -- The funnel, when the diorama is off (FLY VOXEL: OFF) and the scene
      -- wrap that normally draws it never runs. Screen space, because there
      -- is no projection to borrow: the player's own screen position comes
      -- from the world camera the flat renderer is using, the same
      -- subtraction TileRenderer and SpriteRenderer do.
      if Tornado.visible() and ow.camera
         and require("src.render.Pipelines").level("voxel") == 0 then
        local s = (rect.gameWidth or 160) / 160
        local sx = rect.gameX + (p.px + 8 - ow.camera.x) * s
        local sy = rect.gameY + (p.py + 8 - ow.camera.y) * s
        pcall(Tornado.drawFlat, sx, sy, s)
      end

      -- Guarded, because a throwing draw at 60Hz would otherwise take the
      -- frame down -- but reported ONCE rather than swallowed. A silent
      -- pcall here is how a compass that simply never appears looks exactly
      -- like a compass that was never asked to.
      local drew, err = pcall(Compass.draw, rect, Atlas.towns(),
                              p.px + 8, p.py + 8,
                              (gotFP and FirstPerson and FirstPerson.yaw) or 0)
      if not drew and not hudFailed then
        hudFailed = true
        mod.log:error("compass draw failed: %s", tostring(err))
      end
      -- the hook draws into the engine's own frame, so anything left set
      -- here bleeds into the touch controls composited next
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  return next(g, viewport)
end)

-- Every map the player walks into, from now on. The engine only records the
-- eleven towns (save.visited is vanilla's wTownVisitedFlag), so this is the
-- only account of a route ever having been seen -- and what the landing rule
-- reads. Outside a flight as much as during one: the point is to be keeping
-- the record long before the first take-off.
mod.events:on("map.entered", function(payload)
  if payload and payload.mapId then Atlas.markExplored(payload.mapId) end
end)

-- ------- the seams inside the voxel mod
--
-- Installed on the first frame rather than at load: the voxel mod's own
-- exports (and the modules behind them) are only there once its entry chunk
-- has run, and load order between two mods is not ours to assume.
install = function()
  if installed then return end
  local DS = V.ds()
  if not DS then return end
  local FirstPerson = DS.require("FirstPerson")

  -- 1. the pad.
  --
  -- Wrapped AFTER the voxel mod's own FreeMove wrap (this mod's manifest
  -- priority puts it later in the load order), so this is the outer one and
  -- a flight never reaches the ground walk underneath.
  local OverworldState = require("src.world.OverworldController")
  if not OverworldState.flyOverhaulInputHook then
    local innerInput = OverworldState.handleInput
    function OverworldState:handleInput()
      if not Flight.active() then return innerInput(self) end
      return BirdMove.tick(self)
    end
    OverworldState.flyOverhaulInputHook = true
  end

  -- 2. the eye.
  local innerFrame = FirstPerson.frame
  FirstPerson.frame = function(me, cx, cy, vw, vh)
    if not Flight.active() then return innerFrame(me, cx, cy, vw, vh) end
    return BirdCam.frame(me, cx, cy, vw, vh)
  end

  -- 3. the look inputs.
  --
  -- FirstPerson reads the mouse, the right stick and the touch drag only
  -- while it is "engaged", which it defines as the 1ST or 3RD rung being
  -- selected. A flight is neither rung -- it runs on VOXEL 50 -- but it is
  -- every other thing engagement means: the camera stands with the player,
  -- the walk is free and camera-relative, and the view is steered. So it
  -- answers yes, and the blend, the mouse capture lifecycle and the look
  -- rates all work for the flight without being reimplemented.
  --
  -- The one thing engagement would otherwise cost is the player's own card:
  -- hidePlayer hides it once the rig is fully blended in, which is right for
  -- a camera inside someone's head and wrong for one on a boom behind a
  -- bird. So that answers no for the duration.
  local innerEngaged = FirstPerson.engaged
  FirstPerson.engaged = function(...)
    if Flight.active() then return true end
    return innerEngaged(...)
  end

  local innerHide = FirstPerson.hidePlayer
  FirstPerson.hidePlayer = function(...)
    if Flight.active() then return false end
    return innerHide(...)
  end

  -- 4. Kanto under the void.
  --
  -- Injected immediately BEFORE the first mesh of each scene, rather than
  -- straight after beginScene. Both are inside the pass, but only one of
  -- them is provably inside a working draw sequence: the very next call is
  -- the terrain, which demonstrably renders, so anything wrong afterwards is
  -- the sheet's own doing and not the seam's. The first attempt hung off
  -- beginScene's return and drew nothing at all, with the mesh, the texture
  -- and the projection all verified good -- an hour that a seam next to a
  -- known-working draw would not have cost.
  --
  -- Drawing FIRST is what makes it an underlay: the depth buffer is still
  -- empty, the sheet goes down below the ground, and every map drawn after
  -- it simply wins the depth test wherever a map exists. That is the whole
  -- of the "must not cover the towns" requirement -- no mask, no clipping.
  local Voxel3DMod = DS.require("Voxel3D")
  if not Voxel3DMod.flyOverhaulUnderlayHook then
    local sceneFresh = false

    local innerBegin = Voxel3DMod.beginScene
    Voxel3DMod.beginScene = function(...)
      local a, b, c = innerBegin(...)
      sceneFresh = a and true or false
      return a, b, c
    end

    local innerDraw = Voxel3DMod.draw
    Voxel3DMod.draw = function(mesh, tex, model, pull, sunModel)
      if sceneFresh then
        sceneFresh = false
        if Options.underlay:get() then
          pcall(function()
            local G = game()
            local ow = G and G.overworld
            local map = ow and ow.map
            if not map then return end
            local region = Atlas.forMap(map.id)
            if not region then return end
            local locs = ((G.data.field or {}).townMap or {}).locations or {}
            Underlay.draw(map.id, region.towns, locs, innerDraw)
          end)
        end
      end
      return innerDraw(mesh, tex, model, pull, sunModel)
    end

    Voxel3DMod.flyOverhaulUnderlayHook = true
  end

  -- 5. the wind on the way up and the way down.
  --
  -- Drawn straight after the scene, while Voxel3D still holds this frame's
  -- projection and its canvas -- the same moment, and the same two calls
  -- (beginOverlay / project), that the voxel mod's own drawWorld uses to put
  -- the engine's flat field effects over the diorama.
  --
  -- Wrapped around VoxelScene.render rather than added to a pipeline stage
  -- of its own: a present stage would hand back a resolved, possibly
  -- supersampled image with the projection already torn down, and the funnel
  -- has to be composited INTO the scene at scene resolution or it does not
  -- sit in the world at all.
  local VoxelScene = DS.require("VoxelScene")
  if not VoxelScene.flyOverhaulTornadoHook then
    local innerRender = VoxelScene.render
    VoxelScene.render = function(state, w, h, vw, vh, paletteFor, eyes)
      local canvas = innerRender(state, w, h, vw, vh, paletteFor, eyes)
      if canvas and Tornado.visible() and state and state.player then
        local Voxel3D = DS.require("Voxel3D")
        pcall(function()
          if not Voxel3D.beginOverlay() then return end
          local p = state.player
          local ground = 0
          local okG, g = pcall(function()
            return VoxelScene.groundAt and
                   VoxelScene.groundAt(state.map, p.cellX, p.cellY)
          end)
          if okG and type(g) == "number" then ground = g end
          Tornado.draw(p.px + 8, p.py + 8, ground,
                       function(wx, wy, wz) return Voxel3D.project(wx, wy, wz) end,
                       (w or 160) / (vw or 160))
          Voxel3D.endOverlay()
        end)
      end
      return canvas
    end
    VoxelScene.flyOverhaulTornadoHook = true
  end

  -- 6. nobody sees you up there.
  --
  -- BirdMove already keeps the flight out of the landing pipeline, so no
  -- cell it crosses rolls an encounter or takes a warp. Trainer sight is the
  -- one thing that does NOT come through there: OverworldState:update checks
  -- it directly, off the player's logical cell, before handleInput is even
  -- reached -- so a bird crossing a gym leader's line of sight would be
  -- challenged from six cells up, by someone who cannot possibly have seen
  -- them. Left alone for every other frame.
  if not OverworldState.flyOverhaulSightHook then
    local innerSight = OverworldState.checkTrainerSight
    function OverworldState:checkTrainerSight(...)
      if Flight.active() then return end
      return innerSight(self, ...)
    end
    OverworldState.flyOverhaulSightHook = true
  end

  -- 7. the bird.
  --
  -- VoxelScene turns a pose into 3D by taking the difference between the
  -- entity's base y and the VISUAL y that pose() returns, and using it as
  -- vertical lift -- the same mechanism the surf bob and the ledge hop ride.
  -- So a bird six cells up is a pose whose visual y is 96 pixels north of
  -- its own, and nothing in the renderer has to know a flight exists.
  --
  -- It reads correctly in 2D as well: with the voxel pass off, the flat
  -- renderer draws the same sprite that much higher up the screen.
  local Player = require("src.world.Player")
  if not Player.flyOverhaulPoseHook then
    local innerPose = Player.pose
    function Player:pose()
      local sprite, px, py, facing, phase, flip, hopping = innerPose(self)
      if not Flight.active() then
        return sprite, px, py, facing, phase, flip, hopping
      end
      local bird = V.birdSprite()
      return bird or sprite, px, py - Flight.altitude, BirdMove.facing(),
             BirdMove.flapPhase(), false, false
    end
    Player.flyOverhaulPoseHook = true
  end

  FarView.install()
  installed = true
end

-- The bird sheet, built once and kept: the same sprite id vanilla's fly
-- animation uses (field.playerSprites.fly -> SPRITE_BIRD).
local birdSprite = nil
function V.birdSprite()
  if birdSprite ~= nil then return birdSprite or nil end
  local G = game()
  local ok, sprite = pcall(function()
    local FieldDefaults = require("src.world.FieldDefaults")
    local id = FieldDefaults.fieldValue(G.data, "playerSprites", "fly")
    if not (id and G.data.sprites[id]) then return false end
    return require("src.render.SpriteRenderer").new(G.data.sprites[id], "player")
  end)
  birdSprite = (ok and sprite) or false
  return birdSprite or nil
end

-- ------- the OPTIONS menu
--
-- Appended rather than woven in. The voxel mod anchors its own block to the
-- engine's display rows (insertGrouped), and these five are not display
-- modes -- they are what one field move does. A block of their own at the
-- bottom is both easier to find and impossible to confuse with the rows that
-- change how the game looks all the time.
mod.hooks:wrap("ui.options.rows", function(next, g, rows)
  local out = next(g, rows)
  if type(out) ~= "table" then return out end
  for _, row in ipairs(Options.rows()) do out[#out + 1] = row end
  return out
end)

-- The player moved one of the borrowed settings from the mod manager while
-- the flight was in the air: their new choice is what the landing should
-- hand back, not the one from before take-off.
mod.events:on("mod.options_changed", function(payload)
  if not (payload and payload.mod == "DRAMATIC_SHAPE") then return end
  Settings.noteExternalChange(payload.key, payload.value)
end)

-- ------- exposed for the driver suite
mod.exports.version = "2.0.0"
mod.exports.lib = V
mod.exports.begin = beginFlight
-- returns (ok, reason) -- "terrain", "unexplored" or "phase" -- exactly what
-- the A press sees, so a test can assert WHY a landing was refused
mod.exports.land = function()
  local G = game()
  local ow = G and G.overworld
  if not ow then return false, "no-overworld" end
  return BirdMove.requestLanding(ow)
end
